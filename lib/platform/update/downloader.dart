import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../core/update/models.dart';

/// Where staged update files live for one release. Everything under [root]
/// is disposable — the installer deletes the payload after a successful
/// swap and the app sweeps leftovers on launch.
class StagedUpdate {
  const StagedUpdate({required this.root, required this.archive, this.app});

  /// Per-release staging directory (`<updates>/<tag>`).
  final Directory root;

  /// The downloaded archive (`package.zip` etc).
  final File archive;

  /// Extracted `.app` bundle awaiting install (macOS only).
  final Directory? app;
}

/// Resolves staging locations so tests can point them at temp dirs.
abstract class UpdatePaths {
  /// Staging directory for [tag] — created on demand.
  Future<Directory> stageDir(String tag);

  /// The directory every stage dir lives under; swept on launch.
  Future<Directory> updatesRoot();
}

/// Thrown when a download is aborted by [UpdateDownloader.cancel].
class DownloadCancelled implements Exception {
  const DownloadCancelled();
  @override
  String toString() => 'download cancelled';
}

/// Download + verify + extract seam.
abstract class UpdateDownloader {
  /// Streams [asset] to `<dir>/package.<ext>` showing progress via
  /// [onProgress] (0..1, `-1` content-length → bytes-only progress capped),
  /// verifies the SHA-256 GitHub published (required — a release asset
  /// with no digest cannot be auto-installed), then extracts the archive
  /// (macOS zip via `ditto`) and locates the `.app` bundle.
  Future<StagedUpdate> fetchAndStage(
    ReleaseAsset asset,
    Directory dir, {
    void Function(double progress)? onProgress,
  });

  /// Aborts an in-flight [fetchAndStage]; the partial `.part` file and any
  /// half-extracted payload are removed.
  void cancel();
}

/// dart:io implementation — dedicated [HttpClient] per download so cancel
/// can force-close the socket without touching anything else.
///
/// The asset URL travels in release metadata, so it is validated before
/// use: HTTPS only, on GitHub's own hosts. Anything else throws before a
/// single byte is fetched — a hostile/MITM'd metadata payload cannot steer
/// the updater at an arbitrary origin.
class HttpUpdateDownloader implements UpdateDownloader {
  /// Hosts a release asset may legitimately resolve to. The API emits
  /// `api.github.com` `browser_download_url`s on `github.com`; the web
  /// fallback builds them on `github.com` too. Redirects hop to
  /// `objects.githubusercontent.com` (GitHub's asset CDN).
  static const assetHosts = {
    'github.com',
    'api.github.com',
    'objects.githubusercontent.com',
    'githubusercontent.com',
  };

  static void _checkAssetUri(Uri uri) {
    final hostOk = assetHosts.any(
      (h) => uri.host == h || uri.host.endsWith('.$h'),
    );
    if (!uri.isScheme('https') || !hostOk) {
      throw StateError('untrusted asset origin: ${uri.host}');
    }
  }

  HttpUpdateDownloader({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;
  HttpClient? _active;
  var _cancelRequested = false;

  @override
  void cancel() {
    _cancelRequested = true;
    _active?.close(force: true);
  }

  @override
  Future<StagedUpdate> fetchAndStage(
    ReleaseAsset asset,
    Directory dir, {
    void Function(double progress)? onProgress,
  }) async {
    // Fail closed: without a publisher-supplied digest there is nothing to
    // verify the bytes against, and this artifact can replace the app.
    if (asset.sha256 == null || asset.sha256!.trim().isEmpty) {
      throw StateError('release asset lacks an integrity digest');
    }
    await dir.create(recursive: true);
    final ext = asset.name.toLowerCase().endsWith('.tar.gz')
        ? '.tar.gz'
        : '.zip';
    final part = File(p.join(dir.path, 'package$ext.part'));
    final archive = File(p.join(dir.path, 'package$ext'));
    final payload = Directory(p.join(dir.path, 'payload'));
    final client = _clientFactory();
    _active = client;
    _cancelRequested = false;
    try {
      final uri = Uri.parse(asset.downloadUrl);
      _checkAssetUri(uri);
      // Redirects are followed manually and every hop is re-validated — a
      // trusted URL must not smuggle the download to an arbitrary origin.
      HttpClientResponse? response;
      var current = uri;
      for (var hops = 0; hops <= 5 && response == null; hops++) {
        final request = await client.getUrl(current);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, 'relay-desk-updater');
        final hop = await request.close().timeout(const Duration(seconds: 30));
        if (!hop.isRedirect) {
          response = hop;
          break;
        }
        // Read and validate the target BEFORE consuming the body — a
        // hostile hop streaming an endless redirect body must not pin the
        // download or bypass the origin check on the next hop.
        final location = hop.headers.value(HttpHeaders.locationHeader);
        if (location == null) {
          await hop.drain<void>();
          throw HttpException('redirect without location', uri: current);
        }
        current = current.resolve(location);
        _checkAssetUri(current);
        // Bound the courtesy drain — the connection is not reused anyway.
        await hop.drain<void>().timeout(
          const Duration(seconds: 10),
          onTimeout: () {},
        );
      }
      if (response == null) {
        throw HttpException('too many redirects', uri: uri);
      }
      if (response.statusCode != 200) {
        await _drainBounded(response, const Duration(seconds: 10));
        throw HttpException(
          'download failed (${response.statusCode})',
          uri: current,
        );
      }
      final total = response.contentLength;
      final sink = part.openWrite();
      var received = 0;
      try {
        // Per-chunk stall timeout — a hung connection aborts instead of
        // pinning the update state machine in `downloading` forever.
        await for (final chunk in response.timeout(
          const Duration(seconds: 60),
        )) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
      }
      // The stream is done but the dialog still shows "cancel" — a cancel
      // racing the verify/extract stage must still win.
      if (_cancelRequested) throw const DownloadCancelled();
      if (!await part.exists() || await part.length() == 0) {
        throw const HttpException('empty download');
      }
      final sha = await sha256.bind(part.openRead()).first;
      if (!sha.toString().equalsIgnoreCase(asset.sha256!)) {
        throw StateError('sha256 mismatch');
      }
      await part.rename(archive.path);
      onProgress?.call(1);
      Directory? appBundle;
      if (Platform.isMacOS && ext == '.zip') {
        appBundle = await _extractApp(archive, payload);
      }
      // Same check at the boundary: a cancel during ditto still aborts
      // instead of reporting a staged update the user asked to drop.
      if (_cancelRequested) throw const DownloadCancelled();
      return StagedUpdate(root: dir, archive: archive, app: appBundle);
    } catch (e) {
      if (_cancelRequested) {
        throw const DownloadCancelled();
      }
      rethrow;
    } finally {
      _active = null;
      client.close();
      // A cancelled/failed attempt leaves no half files behind.
      if (_cancelRequested) {
        // Cancel can land after the .part was renamed or after extraction
        // completed — drop the full archive and payload, not just .part.
        for (final f in [part, archive]) {
          if (await f.exists()) {
            try {
              await f.delete();
            } catch (_) {}
          }
        }
        if (await payload.exists()) {
          try {
            await payload.delete(recursive: true);
          } catch (_) {}
        }
      } else {
        if (await part.exists()) {
          try {
            await part.delete();
          } catch (_) {}
        }
        // Extraction is only attempted after a verified archive exists, so
        // a partial payload means we bailed mid-extract — drop it.
        if (!await archive.exists() && await payload.exists()) {
          try {
            await payload.delete(recursive: true);
          } catch (_) {}
        }
      }
    }
  }

  /// Courtesy-drains an error body with a hard bound — and unlike a bare
  /// `.drain().timeout()`, cancelling the subscription actually closes
  /// the socket instead of leaving a hanging connection behind.
  static Future<void> _drainBounded(
    HttpClientResponse response,
    Duration limit,
  ) async {
    final sub = response.listen((_) {}, onError: (_) {});
    try {
      await sub.asFuture<void>().timeout(limit);
    } catch (_) {
    } finally {
      await sub.cancel();
    }
  }

  /// `ditto -xk` handles `.app` zips correctly (resource forks, symlinks);
  /// falls back to `unzip` if ditto is unavailable.
  Future<Directory> _extractApp(File archive, Directory payload) async {
    // A previous attempt may have died mid-extract — ditto merges into an
    // existing dir, which would leave stale files inside the new payload.
    if (await payload.exists()) {
      await payload.delete(recursive: true);
    }
    await payload.create(recursive: true);
    var result = await Process.run('ditto', [
      '-x',
      '-k',
      archive.path,
      payload.path,
    ]);
    if (result.exitCode != 0) {
      result = await Process.run('unzip', [
        '-q',
        '-o',
        archive.path,
        '-d',
        payload.path,
      ]);
    }
    if (result.exitCode != 0) {
      try {
        await payload.delete(recursive: true);
      } catch (_) {}
      throw ProcessException(
        'ditto/unzip',
        const [],
        'extract failed: ${result.stderr}',
        result.exitCode,
      );
    }
    Directory? bundle;
    await for (final entity in payload.list(recursive: true)) {
      if (entity is Directory && entity.path.endsWith('.app')) {
        bundle = entity;
        break;
      }
    }
    if (bundle == null) {
      try {
        await payload.delete(recursive: true);
      } catch (_) {}
      throw StateError('no .app bundle in archive');
    }
    return bundle;
  }
}

extension on String {
  bool equalsIgnoreCase(String other) => toLowerCase() == other.toLowerCase();
}
