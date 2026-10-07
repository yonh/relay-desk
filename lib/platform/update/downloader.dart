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
  /// verifies the SHA-256 when GitHub published a digest, then extracts the
  /// archive (macOS zip via `ditto`) and locates the `.app` bundle.
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
class HttpUpdateDownloader implements UpdateDownloader {
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
      final request = await client.getUrl(Uri.parse(asset.downloadUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'relay-desk-updater');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw HttpException(
          'download failed (${response.statusCode})',
          uri: request.uri,
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
      if (!await part.exists() || await part.length() == 0) {
        throw const HttpException('empty download');
      }
      final sha = await sha256.bind(part.openRead()).first;
      if (asset.sha256 != null &&
          !sha.toString().equalsIgnoreCase(asset.sha256!)) {
        throw StateError('sha256 mismatch');
      }
      await part.rename(archive.path);
      onProgress?.call(1);
      Directory? appBundle;
      if (Platform.isMacOS && ext == '.zip') {
        appBundle = await _extractApp(archive, payload);
      }
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
      if (await part.exists()) {
        try {
          await part.delete();
        } catch (_) {}
      }
      // Extraction is only attempted after a verified archive exists, so a
      // partial payload means we bailed mid-extract — drop it.
      if (!await archive.exists() && await payload.exists()) {
        try {
          await payload.delete(recursive: true);
        } catch (_) {}
      }
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
