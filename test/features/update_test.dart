import 'dart:async';
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

  @override
  void cancel() => cancelled = true;

  @override
  Future<StagedUpdate> fetchAndStage(
    ReleaseAsset asset,
    Directory dir, {
    void Function(double progress)? onProgress,
  }) async {
    calls++;
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

GithubRelease release({
  String tag = 'v1.1.0',
  bool withAsset = true,
}) {
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
      expect(isRemoteNewer(versionFromTag('v1.0.3')!, versionFromPackage('1.0.2+9')!), isTrue);
      expect(isRemoteNewer(versionFromTag('v1.0.2')!, versionFromPackage('1.0.2+9')!), isFalse);
      expect(isRemoteNewer(versionFromTag('v1.0.1')!, versionFromPackage('1.0.2+1')!), isFalse);
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

    test('current build up to date, local ahead, and throttled auto-check',
        () async {
      final client = FakeReleaseClient()..release = release(tag: 'v1.0.2');
      final container = makeContainer(client: client);
      addTearDown(container.dispose);
      final notifier = container.read(updateStatusProvider.notifier);
      await notifier.check(manual: true);
      expect(container.read(updateStatusProvider).phase, UpdatePhase.upToDate);
      expect(client.calls, 1);
      // Auto-check is throttled by lastCheckMs — a second one is a no-op.
      await notifier.check();
      expect(client.calls, 1);
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
      expect(
        container.read(updateStatusProvider).phase,
        UpdatePhase.available,
      );
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
      expect(
        container.read(updateSettingsProvider).readyTag,
        'v1.1.0',
      );
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
      expect(
        container.read(updateStatusProvider).phase,
        UpdatePhase.available,
      );
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
      expect(container.read(updateStatusProvider).phase, UpdatePhase.installing);
      await notifier.skipVersion();
      expect(container.read(updateSettingsProvider).skippedVersion, isNull);
      installer.gate!.complete(true);
      await installFuture;
    });

    test('staged download for the pending release resumes at ready',
        () async {
      final storage = MemoryUpdateStorage(
        const UpdateSettings(readyTag: 'v1.1.0'),
      );
      final paths = FakePaths(Directory.systemTemp.createTempSync('upd'));
      // Recreate what a finished download leaves behind.
      await Directory('${paths.root.path}/v1.1.0/payload/Relay Desk.app')
          .create(recursive: true);
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
      'macos/Runner/RelayDeskUpdater.app/Contents/MacOS/updater',
    ).readAsStringSync();

    int lineOf(String needle, [int from = 0]) {
      final i = script.indexOf(needle, from);
      expect(i, isNonNegative, reason: 'missing: $needle');
      return i;
    }

    test('runtime values arrive via argv, not embedded literals', () {
      expect(script, contains('PARENT="\${1:?pid}"'));
      expect(script, contains('ROOT="\${2:?root}"'));
      expect(script, contains('TARGET="\${4:?target}"'));
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
  });

  group('UpdateSettingsSection', () {
    testWidgets('toggles persist and check button drives the controller',
        (tester) async {
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
