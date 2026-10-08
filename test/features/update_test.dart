import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_desk/core/update/models.dart';
import 'package:relay_desk/core/update/settings_storage.dart';
import 'package:relay_desk/features/update/update_controller.dart';
import 'package:relay_desk/features/update/update_ui.dart';
import 'package:relay_desk/platform/update/downloader.dart';
import 'package:relay_desk/platform/update/installer.dart';
import 'package:relay_desk/platform/update/release_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_app.dart';

/// Undoes flutter_test's global HttpClient mock for the duration of a test —
/// `HttpOverrides.global` is restored afterwards.
class _RealHttpOverrides extends HttpOverrides {}

class FakeReleaseClient implements ReleaseClient {
  GithubRelease? release;
  Object? error;
  int calls = 0;

  @override
  Future<GithubRelease?> latestRelease() async {
    calls++;
    if (error != null) throw error!;
    return release;
  }
}

class FakeDownloader implements UpdateDownloader {
  Object? error;
  int calls = 0;
  bool cancelled = false;
  Completer<void>? gate;

  @override
  void cancel() => cancelled = true;

  @override
  Future<StagedUpdate> fetchAndStage(
    ReleaseAsset asset,
    Directory dir, {
    void Function(double progress)? onProgress,
  }) async {
    calls++;
    await gate?.future;
    if (error != null) throw error!;
    onProgress?.call(0.5);
    await dir.create(recursive: true);
    final archive = File('${dir.path}/package.zip');
    await archive.writeAsBytes(const [1, 2, 3]);
    final app = Directory('${dir.path}/payload/Relay Desk.app');
    await app.create(recursive: true);
    onProgress?.call(1);
    return StagedUpdate(root: dir, archive: archive, app: app);
  }
}

class FakeInstaller implements UpdateInstaller {
  bool result = true;
  StagedUpdate? last;
  Completer<bool>? gate;

  @override
  Future<bool> installAndRelaunch(StagedUpdate update) async {
    last = update;
    await gate?.future;
    return result;
  }
}

class FakePaths implements UpdatePaths {
  FakePaths(this.root);
  final Directory root;

  @override
  Future<Directory> updatesRoot() async => root;

  @override
  Future<Directory> stageDir(String tag) async =>
      Directory('${root.path}/$tag');
}

class FakeVersionReader implements AppVersionReader {
  FakeVersionReader(this.version);
  String version;
  @override
  Future<String> read() async => version;
}

GithubRelease release({String tag = 'v1.1.0', bool withAsset = true}) {
  return GithubRelease(
    tag: tag,
    version: versionFromTag(tag)!,
    name: tag,
    body: 'notes',
    htmlUrl: 'https://example.test/$tag',
    prerelease: false,
    draft: false,
    assets: withAsset
        ? [
            ReleaseAsset(
              name: 'RelayDesk-$tag-macos-universal.zip',
              downloadUrl: 'https://example.test/$tag.zip',
              size: 1024,
              sha256: 'abc',
            ),
          ]
        : const [],
  );
}

ProviderContainer makeContainer({
  UpdateStorage? storage,
  FakeReleaseClient? client,
  FakeDownloader? downloader,
  FakeInstaller? installer,
  FakePaths? paths,
  FakeVersionReader? versionReader,
  void Function()? onQuit,
}) {
  return ProviderContainer(
    overrides: [
      updateStorageProvider.overrideWithValue(storage ?? MemoryUpdateStorage()),
      releaseClientProvider.overrideWithValue(client ?? FakeReleaseClient()),
      updateDownloaderProvider.overrideWithValue(
        downloader ?? FakeDownloader(),
      ),
      updateInstallerProvider.overrideWithValue(installer ?? FakeInstaller()),
      updatePathsProvider.overrideWithValue(
        paths ?? FakePaths(Directory.systemTemp.createTempSync('upd')),
      ),
      appVersionReaderProvider.overrideWithValue(
        versionReader ?? FakeVersionReader('1.0.2+3'),
      ),
      quitAppProvider.overrideWithValue(onQuit ?? () {}),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('version helpers', () {
    test('tags and package versions normalize to comparable semvers', () {
      expect(versionFromTag('v1.2.3')!.toString(), '1.2.3');
      expect(versionFromTag('1.2.3')!.toString(), '1.2.3');
      expect(versionFromTag('release-candidate'), isNull);
      expect(versionFromPackage('1.0.2+3')!.toString(), '1.0.2');
      expect(
        isRemoteNewer(
          versionFromTag('v1.0.3')!,
          versionFromPackage('1.0.2+9')!,
        ),
        isTrue,
      );
      expect(
        isRemoteNewer(
          versionFromTag('v1.0.2')!,
          versionFromPackage('1.0.2+9')!,
        ),
        isFalse,
      );
      expect(
        isRemoteNewer(
          versionFromTag('v1.0.1')!,
          versionFromPackage('1.0.2+1')!,
        ),
        isFalse,
      );
    });

    test('skip covers the skipped version and older only', () {
      final skipped = versionFromTag('1.0.3');
      expect(isSkipped(versionFromTag('1.0.3')!, skipped), isTrue);
      expect(isSkipped(versionFromTag('1.0.2')!, skipped), isTrue);
      expect(isSkipped(versionFromTag('1.0.4')!, skipped), isFalse);
      expect(isSkipped(versionFromTag('1.0.3')!, null), isFalse);
    });

    test('asset selection prefers the platform archive', () {
      final assets = [
        const ReleaseAsset(
          name: 'RelayDesk-v1.1.0-windows-x64.zip',
          downloadUrl: 'u',
          size: 1,
        ),
        const ReleaseAsset(
          name: 'RelayDesk-v1.1.0-macos-universal.dmg',
          downloadUrl: 'u',
          size: 1,
        ),
        const ReleaseAsset(
          name: 'RelayDesk-v1.1.0-macos-universal.zip',
          downloadUrl: 'u',
          size: 1,
        ),
      ];
      expect(
        selectAsset(assets, 'macos')!.name,
        'RelayDesk-v1.1.0-macos-universal.zip',
      );
      expect(
        selectAsset(assets, 'windows')!.name,
        'RelayDesk-v1.1.0-windows-x64.zip',
      );
      expect(selectAsset(assets, 'linux'), isNull);
    });
  });

  group('GithubRelease.fromJson', () {
    Map<String, dynamic> payload({
      String tag = 'v1.1.0',
      bool draft = false,
      bool prerelease = false,
    }) => {
      'tag_name': tag,
      'name': 'Release $tag',
      'body': 'changes',
      'html_url': 'https://example.test/$tag',
      'draft': draft,
      'prerelease': prerelease,
      'assets': [
        {
          'name': 'RelayDesk-$tag-macos-universal.zip',
          'browser_download_url': 'https://example.test/dl.zip',
          'size': 42,
          'digest': 'sha256:deadbeef',
        },
      ],
    };

    test('parses tag, body and asset sha256 digest', () {
      final r = GithubRelease.fromJson(payload())!;
      expect(r.version.toString(), '1.1.0');
      expect(r.assets.single.sha256, 'deadbeef');
      expect(r.assets.single.size, 42);
    });

    test('drafts, prereleases and malformed tags yield null', () {
      expect(GithubRelease.fromJson(payload(draft: true)), isNull);
      expect(GithubRelease.fromJson(payload(prerelease: true)), isNull);
      expect(GithubRelease.fromJson(payload(tag: 'nightly')), isNull);
      // A semver pre-release suffix must be rejected even when GitHub's
      // `prerelease` flag is false (v1.1.0-rc.1 shipped as a release).
      expect(GithubRelease.fromJson(payload(tag: 'v1.1.0-rc.1')), isNull);
      expect(GithubRelease.fromJson(payload(tag: 'v1.1.0-beta+2')), isNull);
    });
  });

  group('GithubReleaseClient web fallback', () {
    HttpServer? server;
    HttpOverrides? priorOverrides;
    final seenPaths = <String>[];

    setUp(() {
      // flutter_test installs a global HttpOverrides that 400s every request;
      // swap in a passthrough so this group talks to a real local server.
      priorOverrides = HttpOverrides.current;
      HttpOverrides.global = _RealHttpOverrides();
    });

    Future<HttpServer> serve(
      FutureOr<void> Function(HttpRequest req) handler,
    ) async {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      s.forEach((req) async {
        seenPaths.add(req.uri.path);
        await handler(req);
        await req.response.close();
      });
      return s;
    }

    GithubReleaseClient clientFor(int port) => GithubReleaseClient(
      apiBase: Uri.http('127.0.0.1:$port', ''),
      webBase: Uri.http('127.0.0.1:$port', ''),
      timeout: const Duration(seconds: 5),
    );

    tearDown(() async {
      await server?.close(force: true);
      server = null;
      seenPaths.clear();
      HttpOverrides.global = priorOverrides;
      priorOverrides = null;
    });

    const macosDigest =
        '0abfa89ea8e1e77c6730136bfba317a1797f9ddd1910973f3fa520f884876aa8';
    const windowsDigest =
        'b52a921a2d4f4799c1cab3d073df0e94affea48db72e0495decfb09bb79f8f44';
    const assetsHtml =
        '''
      <div>
        <a href="/yonh/relay-desk/releases/download/v9.9.9/RelayDesk-v9.9.9-macos-universal.zip">zip</a>
        <span class="Truncate-text">sha256:$macosDigest</span>
        <a href="/yonh/relay-desk/releases/download/v9.9.9/RelayDesk-v9.9.9-windows-x64.zip">zip</a>
        <span class="Truncate-text">sha256:$windowsDigest</span>
        <a href="/yonh/relay-desk/releases/download/v9.9.9/RelayDesk-v9.9.9-macos-universal.dmg">dmg</a>
        <a href="/other/repo/releases/download/v9.9.9/nope.zip">other</a>
      </div>
    ''';

    test(
      'falls back to github.com pages when the API is rate-limited',
      () async {
        server = await serve((req) {
          final path = req.uri.path;
          if (path.startsWith('/repos/')) {
            req.response.statusCode = 403;
            req.response.write('{"message":"API rate limit exceeded"}');
          } else if (path == '/yonh/relay-desk/releases/latest') {
            req.response.statusCode = 302;
            req.response.headers.set(
              'location',
              'http://127.0.0.1:${server!.port}'
                  '/yonh/relay-desk/releases/tag/v9.9.9',
            );
          } else if (path == '/yonh/relay-desk/releases/tag/v9.9.9') {
            req.response.statusCode = 200;
            req.response.write('<html>release page</html>');
          } else if (path ==
              '/yonh/relay-desk/releases/expanded_assets/v9.9.9') {
            req.response.statusCode = 200;
            req.response.write(assetsHtml);
          } else if (req.method == 'HEAD' &&
              path.startsWith('/yonh/relay-desk/releases/download/')) {
            // The page carries no size column — sizes arrive via HEAD.
            req.response.statusCode = 200;
            req.response.headers.set(
              HttpHeaders.contentLengthHeader,
              path.endsWith('-universal.zip') ? '1048576' : '2097152',
            );
          } else {
            req.response.statusCode = 404;
          }
        });

        final release = await clientFor(server!.port).latestRelease();
        expect(release, isNotNull);
        expect(release!.tag, 'v9.9.9');
        expect(release.version.toString(), '9.9.9');
        expect(
          release.assets.map((a) => a.name),
          containsAll([
            'RelayDesk-v9.9.9-macos-universal.zip',
            'RelayDesk-v9.9.9-windows-x64.zip',
            'RelayDesk-v9.9.9-macos-universal.dmg',
          ]),
        );
        // Digests rendered on the page are scraped per asset — the dmg row
        // publishes none.
        expect(
          release.assets
              .firstWhere((a) => a.name.endsWith('-universal.zip'))
              .sha256,
          macosDigest,
        );
        expect(
          release.assets.firstWhere((a) => a.name.endsWith('-x64.zip')).sha256,
          windowsDigest,
        );
        expect(
          release.assets.firstWhere((a) => a.name.endsWith('.dmg')).sha256,
          isNull,
        );
        // Sizes are absent from the fragment — filled by a HEAD per asset.
        expect(
          release.assets
              .firstWhere((a) => a.name.endsWith('-universal.zip'))
              .size,
          1048576,
        );
        expect(
          release.assets.firstWhere((a) => a.name.endsWith('.dmg')).size,
          2097152,
        );
        expect(
          release.assets.first.downloadUrl,
          contains('/yonh/relay-desk/releases/download/v9.9.9/'),
        );
        // API hit first, web pages only after it failed.
        expect(seenPaths.first, '/repos/yonh/relay-desk/releases/latest');
        expect(seenPaths, contains('/yonh/relay-desk/releases/latest'));
        expect(
          seenPaths,
          contains('/yonh/relay-desk/releases/expanded_assets/v9.9.9'),
        );
      },
    );

    test('does not touch web pages when the API succeeds', () async {
      server = await serve((req) {
        req.response.statusCode = 200;
        req.response.write(
          jsonEncode({
            'tag_name': 'v1.1.0',
            'draft': false,
            'prerelease': false,
            'assets': [],
          }),
        );
      });
      final release = await clientFor(server!.port).latestRelease();
      expect(release!.version.toString(), '1.1.0');
      expect(seenPaths, everyElement(startsWith('/repos/')));
    });

    test('semver-prerelease tags still yield null via the web path', () async {
      server = await serve((req) {
        final path = req.uri.path;
        if (path.startsWith('/repos/')) {
          req.response.statusCode = 403;
        } else if (path == '/yonh/relay-desk/releases/latest') {
          req.response.statusCode = 302;
          req.response.headers.set(
            'location',
            'http://127.0.0.1:${server!.port}'
                '/yonh/relay-desk/releases/tag/v9.9.9-rc.1',
          );
        } else if (path.startsWith('/yonh/relay-desk/releases/tag/')) {
          req.response.statusCode = 200;
        } else {
          req.response.statusCode = 404;
        }
      });
      expect(await clientFor(server!.port).latestRelease(), isNull);
    });

    test('web path returns null when latest yields no tag redirect', () async {
      server = await serve((req) {
        if (req.uri.path.startsWith('/repos/')) {
          req.response.statusCode = 403;
        } else {
          req.response.statusCode = 200; // page, but no /tag/ redirect
        }
      });
      expect(await clientFor(server!.port).latestRelease(), isNull);
    });

    test('rethrows the API error when the web path also fails', () async {
      server = await serve((req) {
        req.response.statusCode = 500;
      });
      await expectLater(
        clientFor(server!.port).latestRelease(),
        throwsA(
          isA<HttpException>().having(
            (e) => e.uri?.path ?? '',
            'uri',
            contains('/repos/'),
          ),
        ),
      );
    });

    test('parses tag and assets from the web fragments', () {
      expect(
        GithubReleaseClient.tagFromReleaseLocation(
          'https://github.com/yonh/relay-desk/releases/tag/v2.0.0',
        ),
        'v2.0.0',
      );
      expect(
        GithubReleaseClient.tagFromReleaseLocation('/yonh/relay-desk/releases'),
        isNull,
      );
      final assets = GithubReleaseClient.parseAssetsFromExpandedHtml(
        html:
            '<a href="/o/r/releases/download/v1.0.0/A%20B.zip">x</a>'
            '<a href="/o/r/releases/download/v1.0.0/A%20B.zip">dup</a>'
            '<a href="/o/r/releases/download/v9.9.9/wrong-tag.zip">y</a>',
        owner: 'o',
        repo: 'r',
        tag: 'v1.0.0',
      );
      expect(assets, hasLength(1));
      expect(assets.single.name, 'A B.zip');
      expect(
        assets.single.downloadUrl,
        'https://github.com/o/r/releases/download/v1.0.0/A%20B.zip',
      );
      // A digest between this href and the next belongs to THIS asset; one
      // after the last href belongs to it too.
      final withDigest = GithubReleaseClient.parseAssetsFromExpandedHtml(
        html:
            '<a href="/o/r/releases/download/v1.0.0/A.zip">a</a>'
            '<span>sha256:${'a' * 64}</span>'
            '<a href="/o/r/releases/download/v1.0.0/B.zip">b</a>',
        owner: 'o',
        repo: 'r',
        tag: 'v1.0.0',
      );
      expect(withDigest, hasLength(2));
      expect(withDigest[0].sha256, 'a' * 64);
      expect(withDigest[1].sha256, isNull);
    });
  });

  group('HttpUpdateDownloader', () {
    test(
      'rejects non-https and non-GitHub asset origins before fetching',
      () async {
        final dir = Directory.systemTemp.createTempSync('dl-origin');
        addTearDown(() => dir.delete(recursive: true));
        final downloader = HttpUpdateDownloader(clientFactory: HttpClient.new);
        for (final url in [
          'http://github.com/x.zip',
          'https://evil.example.com/x.zip',
        ]) {
          await expectLater(
            downloader.fetchAndStage(
              ReleaseAsset(
                name: 'x.zip',
                downloadUrl: url,
                size: 0,
                sha256: 'abc',
              ),
              dir,
            ),
            throwsA(isA<StateError>()),
          );
        }
      },
    );

    test('refuses a release asset that has no integrity digest', () async {
      final dir = Directory.systemTemp.createTempSync('dl-digest');
      addTearDown(() => dir.delete(recursive: true));
      final downloader = HttpUpdateDownloader(clientFactory: HttpClient.new);
      await expectLater(
        downloader.fetchAndStage(
          const ReleaseAsset(
            name: 'x.zip',
            downloadUrl: 'https://github.com/o/r/x.zip',
            size: 0,
          ),
          dir,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('UpdateStorage', () {
    test('round-trips settings and tolerates missing keys', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = SharedPreferencesUpdateStorage(prefs);
      var s = storage.read();
      expect(s.autoCheck, isTrue);
      expect(s.autoDownload, isFalse);
      expect(s.skippedVersion, isNull);
      await storage.write(
        s.copyWith(
          autoCheck: false,
          autoDownload: true,
          skippedVersion: '1.2.0',
          readyTag: 'v1.2.0',
        ),
      );
      s = SharedPreferencesUpdateStorage(prefs).read();
      expect(s.autoCheck, isFalse);
      expect(s.autoDownload, isTrue);
      expect(s.skippedVersion, '1.2.0');
      expect(s.readyTag, 'v1.2.0');
      await storage.write(s.copyWith(clearSkipped: true, clearReady: true));
      s = SharedPreferencesUpdateStorage(prefs).read();
      expect(s.skippedVersion, isNull);
      expect(s.readyTag, isNull);
    });
  });

  group('UpdateController', () {
    // The controller matches assets via the real host platform token — on
    // Linux CI that is `linux`, which would select nothing from the macOS
    // fixtures. Pin macOS for this group.
    setUp(() => debugHostPlatformToken = 'macos');
    tearDown(() => debugHostPlatformToken = null);

    test('newer release transitions to available', () async {
      final client = FakeReleaseClient()..release = release();
      final container = makeContainer(client: client);
      addTearDown(container.dispose);
      await container.read(updateStatusProvider.notifier).check(manual: true);
      final status = container.read(updateStatusProvider);
      expect(status.phase, UpdatePhase.available);
      expect(status.release!.version.toString(), '1.1.0');
      expect(status.asset, isNotNull);
    });

    test(
      'current build up to date, local ahead, and throttled auto-check',
      () async {
        final client = FakeReleaseClient()..release = release(tag: 'v1.0.2');
        final container = makeContainer(client: client);
        addTearDown(container.dispose);
        final notifier = container.read(updateStatusProvider.notifier);
        await notifier.check(manual: true);
        expect(
          container.read(updateStatusProvider).phase,
          UpdatePhase.upToDate,
        );
        expect(client.calls, 1);
        // Auto-check is throttled by lastCheckMs — a second one is a no-op.
        await notifier.check();
        expect(client.calls, 1);
      },
    );

    test('retry while a download is in flight is a no-op', () async {
      final downloader = FakeDownloader()..gate = Completer<void>();
      final client = FakeReleaseClient()..release = release();
      final container = makeContainer(client: client, downloader: downloader);
      addTearDown(container.dispose);
      final notifier = container.read(updateStatusProvider.notifier);
      await notifier.check(manual: true);
      // Kick off the download without awaiting — the gate keeps it busy.
      unawaited(notifier.download());
      // Poll briefly for the downloading phase rather than sleeping.
      for (var i = 0; i < 50; i++) {
        if (container.read(updateStatusProvider).phase ==
            UpdatePhase.downloading) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
      expect(
        container.read(updateStatusProvider).phase,
        UpdatePhase.downloading,
      );
      // The failed-download retry path would reset to `available` and call
      // download() again; the busy guard must stop the second fetch.
      await notifier.retry();
      expect(downloader.calls, 1);
      downloader.gate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(downloader.calls, 1);
    });

    test('skipped version silences auto but not manual check', () async {
      final storage = MemoryUpdateStorage(
        const UpdateSettings(skippedVersion: '1.1.0'),
      );
      final client = FakeReleaseClient()..release = release();
      final container = makeContainer(storage: storage, client: client);
      addTearDown(container.dispose);
      final notifier = container.read(updateStatusProvider.notifier);
      await notifier.check();
      expect(container.read(updateStatusProvider).phase, UpdatePhase.upToDate);
      await notifier.check(manual: true);
      expect(container.read(updateStatusProvider).phase, UpdatePhase.available);
    });

    test('autoDownload goes straight from check to ready', () async {
      final storage = MemoryUpdateStorage(
        const UpdateSettings(autoDownload: true),
      );
      final client = FakeReleaseClient()..release = release();
      final downloader = FakeDownloader();
      final container = makeContainer(
        storage: storage,
        client: client,
        downloader: downloader,
      );
      addTearDown(container.dispose);
      await container.read(updateStatusProvider.notifier).check(manual: true);
      expect(downloader.calls, 1);
      expect(container.read(updateStatusProvider).phase, UpdatePhase.ready);
      expect(container.read(updateSettingsProvider).readyTag, 'v1.1.0');
    });

    test('download stages files, then install quits the app', () async {
      final client = FakeReleaseClient()..release = release();
      final installer = FakeInstaller();
      var quit = 0;
      final container = makeContainer(
        client: client,
        installer: installer,
        onQuit: () => quit++,
      );
      addTearDown(container.dispose);
      final notifier = container.read(updateStatusProvider.notifier);
      await notifier.check(manual: true);
      await notifier.download();
      final afterDl = container.read(updateStatusProvider);
      expect(afterDl.phase, UpdatePhase.ready, reason: '${afterDl.error}');
      await notifier.installAndRelaunch();
      expect(installer.last, isNotNull);
      expect(installer.last!.app!.path.endsWith('.app'), isTrue);
      expect(quit, 1);
      expect(container.read(updateSettingsProvider).readyTag, isNull);
    });

    test('download failure reports the download stage', () async {
      final client = FakeReleaseClient()..release = release();
      final downloader = FakeDownloader()..error = StateError('boom');
      final container = makeContainer(client: client, downloader: downloader);
      addTearDown(container.dispose);
      final notifier = container.read(updateStatusProvider.notifier);
      await notifier.check(manual: true);
      await notifier.download();
      final status = container.read(updateStatusProvider);
      expect(status.phase, UpdatePhase.failed);
      expect(status.stage, UpdateStage.download);
    });

    test('cancel returns to available', () async {
      final client = FakeReleaseClient()..release = release();
      final downloader = FakeDownloader()..error = const DownloadCancelled();
      final container = makeContainer(client: client, downloader: downloader);
      addTearDown(container.dispose);
      final notifier = container.read(updateStatusProvider.notifier);
      await notifier.check(manual: true);
      await notifier.download();
      expect(container.read(updateStatusProvider).phase, UpdatePhase.available);
    });

    test('skipVersion persists and clears the staged tag', () async {
      final storage = MemoryUpdateStorage();
      final client = FakeReleaseClient()..release = release();
      final container = makeContainer(storage: storage, client: client);
      addTearDown(container.dispose);
      final notifier = container.read(updateStatusProvider.notifier);
      await notifier.check(manual: true);
      await notifier.skipVersion();
      expect(container.read(updateSettingsProvider).skippedVersion, '1.1.0');
      expect(container.read(updateStatusProvider).phase, UpdatePhase.upToDate);
    });

    test('failed auto check stays silent, manual check reports', () async {
      final client = FakeReleaseClient()..error = StateError('offline');
      final container = makeContainer(client: client);
      addTearDown(container.dispose);
      final notifier = container.read(updateStatusProvider.notifier);
      await notifier.check();
      expect(container.read(updateStatusProvider).phase, UpdatePhase.idle);
      await notifier.check(manual: true);
      expect(container.read(updateStatusProvider).phase, UpdatePhase.failed);
    });

    test('skipVersion is a no-op while a phase is busy', () async {
      final storage = MemoryUpdateStorage();
      final client = FakeReleaseClient()..release = release();
      final installer = FakeInstaller()..gate = Completer<bool>();
      final container = makeContainer(
        storage: storage,
        client: client,
        installer: installer,
      );
      addTearDown(container.dispose);
      final notifier = container.read(updateStatusProvider.notifier);
      await notifier.check(manual: true);
      await notifier.download();
      final installFuture = notifier.installAndRelaunch();
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(updateStatusProvider).phase,
        UpdatePhase.installing,
      );
      await notifier.skipVersion();
      expect(container.read(updateSettingsProvider).skippedVersion, isNull);
      installer.gate!.complete(true);
      await installFuture;
    });

    test('staged download for the pending release resumes at ready', () async {
      final storage = MemoryUpdateStorage(
        const UpdateSettings(readyTag: 'v1.1.0'),
      );
      final paths = FakePaths(Directory.systemTemp.createTempSync('upd'));
      // Recreate what a finished download leaves behind.
      await Directory(
        '${paths.root.path}/v1.1.0/payload/Relay Desk.app',
      ).create(recursive: true);
      final client = FakeReleaseClient()..release = release();
      final downloader = FakeDownloader();
      final container = makeContainer(
        storage: storage,
        client: client,
        paths: paths,
        downloader: downloader,
      );
      addTearDown(container.dispose);
      await container.read(updateStatusProvider.notifier).check(manual: true);
      expect(container.read(updateStatusProvider).phase, UpdatePhase.ready);
      expect(downloader.calls, 0);
    });
  });

  group('helper script invariants', () {
    // Locks the shell-level safety properties that reviews found by
    // hand — the order of operations inside the bundled script is the
    // contract, so assert on index ordering, not exact text. The file
    // under test is the actual artifact shipped in the app bundle.
    final script = File(
      'macos/Runner/RelayDeskUpdater.app/Contents/MacOS/updater.sh',
    ).readAsStringSync();

    int lineOf(String needle, [int from = 0]) {
      final i = script.indexOf(needle, from);
      expect(i, isNonNegative, reason: 'missing: $needle');
      return i;
    }

    test('runtime values arrive via handoff file, argv kept as fallback', () {
      // LaunchServices strips --args argv for sandboxed launchers, so the
      // app writes <updatesRoot>/handoff.params and the script parses it
      // field-by-field; argv remains a manual-debug fallback.
      expect(script, contains('handoff.params'));
      expect(script, contains('PARENT="\${1:-}"'));
      expect(script, contains('ROOT="\${2:-}"'));
      expect(script, contains('TARGET="\${4:-}"'));
      expect(script, contains('PARENT=*)  PARENT='));
      expect(script, contains('TARGET=*)  TARGET='));
      // All five params are still mandatory before the swap section runs.
      expect(script, contains('\${PARENT:?pid}'));
      expect(script, contains('\${TARGET:?target}'));
      expect(
        lineOf('kill -0 \$PARENT'),
        lessThan(lineOf('mv "\$TARGET" "\$BACKUP"')),
      );
    });

    test('atomic lock is acquired before mutating the target', () {
      expect(
        lineOf('mkdir "\$LOCK"'),
        lessThan(lineOf('mv "\$TARGET" "\$BACKUP"')),
      );
    });

    test('old-bundle backup failure aborts before ditto', () {
      expect(
        lineOf('mv "\$TARGET" "\$BACKUP" ||'),
        lessThan(lineOf('if ditto')),
      );
    });

    test('live-instance guard runs once before and once after ditto', () {
      final first = lineOf('pgrep -f "\$TARGET/Contents/MacOS/"');
      final second = lineOf('pgrep -f "\$TARGET/Contents/MacOS/"', first + 1);
      expect(first, lessThan(lineOf('if ditto')));
      expect(second, greaterThan(lineOf('if ditto')));
      expect(second, lessThan(lineOf('open "\$TARGET"')));
    });

    test('ditto failure rolls back without nesting the backup', () {
      final rollback = lineOf(r'rm -rf "$TARGET" && mv "$BACKUP" "$TARGET"');
      expect(rollback, greaterThan(lineOf('if ditto')));
    });

    test('failure path moves payload to Downloads before relaunching', () {
      final failBranch = lineOf('else', lineOf('if ditto'));
      expect(
        lineOf('mv "\$PAYLOAD" "\$DEST"', failBranch),
        lessThan(lineOf('open "\$TARGET" 2>/dev/null', failBranch)),
      );
    });

    test('backup is deleted only after the new app launches', () {
      final success = lineOf('if ditto');
      expect(
        lineOf('open "\$TARGET" && rm -rf "\$BACKUP"', success),
        greaterThan(lineOf('xattr', success)),
      );
    });

    test('exit trap restores the backup when the target is missing', () {
      expect(lineOf('trap cleanup EXIT'), lessThan(lineOf('mkdir "\$LOCK"')));
      expect(script, contains('[ -d "\$BACKUP" ] && [ ! -d "\$TARGET" ]'));
    });

    test('a leftover backup is restored before it can be deleted', () {
      // A killed helper can leave TARGET missing and BACKUP holding the only
      // working app — the restore must precede `rm -rf "$BACKUP"`.
      final restore = lineOf('[ ! -d "\$TARGET" ] && [ -d "\$BACKUP" ]');
      expect(restore, lessThan(lineOf('rm -rf "\$BACKUP"')));
      expect(
        lineOf('mv "\$BACKUP" "\$TARGET" 2>/dev/null ||', restore),
        lessThan(lineOf('if ditto')),
      );
    });

    test('file-sourced params pass containment and freshness checks', () {
      expect(script, contains('now - mtime)) -gt 600'));
      expect(script, contains('*[!0-9]*|"") exit 0'));
      expect(script, contains('*/updates/?*) ;; *) exit 0'));
      expect(script, contains('"\$ROOT"/*) ;; *) exit 0'));
      expect(script, contains('*.app) ;; *) exit 0'));
      // The checks gate the marker write too — a planted handoff must not
      // even fake a started helper.
      expect(
        lineOf('*.app) ;; *) exit 0'),
        lessThan(lineOf('touch "\$MARKER"')),
      );
    });

    test(
      'an orphaned lock is reclaimed atomically, never by a live holder',
      () {
        // SIGKILL skips the EXIT trap — its lock dir outlives it. The next
        // helper must reclaim an orphan (liveness check, then an atomic
        // rename — never rm+mkdir, which a concurrent helper could turn
        // against the lock we just created).
        final take = lineOf('if ! mkdir "\$LOCK"');
        final check = lineOf('pgrep -f "\$0" | grep -vx "\$\$"', take);
        final claim = lineOf('mv "\$LOCK" "\$CLAIM"', check);
        expect(check, lessThan(claim));
        expect(claim, lessThan(lineOf('rm -rf "\$CLAIM"', claim)));
        // And only after the reclaim may the backup-rescue run.
        expect(
          lineOf('[ ! -d "\$TARGET" ] && [ -d "\$BACKUP" ]', claim),
          greaterThan(claim),
        );
      },
    );
  });

  group('UpdateSettingsSection', () {
    testWidgets('toggles persist and check button drives the controller', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final storage = SharedPreferencesUpdateStorage(
        await SharedPreferences.getInstance(),
      );
      final client = FakeReleaseClient()..release = release(tag: 'v1.0.2');
      final container = makeContainer(storage: storage, client: client);
      addTearDown(container.dispose);
      await tester.binding.setSurfaceSize(const Size(600, 500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const LocalizedTestApp(
            locale: Locale('en'),
            home: Scaffold(body: UpdateSettingsSection()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The installed version is always shown, even before any check.
      expect(find.text('Current version: v1.0.2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('update-auto-download')));
      await tester.pumpAndSettle();
      expect(storage.read().autoDownload, isTrue);
      await tester.tap(find.byKey(const ValueKey('update-check-now')));
      await tester.pumpAndSettle();
      expect(client.calls, 1);
      expect(find.text('Relay Desk is up to date'), findsOneWidget);
    });
  });
}
