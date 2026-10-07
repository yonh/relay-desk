import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../core/update/models.dart';
import '../../core/update/settings_storage.dart';
import '../../platform/update/downloader.dart';
import '../../platform/update/installer.dart';
import '../../platform/update/release_client.dart';

/// Injectable seams — overridden in `main` with shared_preferences and in
/// tests with fakes.
final updateStorageProvider = Provider<UpdateStorage>(
  (ref) => MemoryUpdateStorage(),
);

final releaseClientProvider = Provider<ReleaseClient>(
  (ref) => GithubReleaseClient(),
);

final updateDownloaderProvider = Provider<UpdateDownloader>(
  (ref) => HttpUpdateDownloader(),
);

final updateInstallerProvider = Provider<UpdateInstaller>(
  (ref) => MacOSUpdateInstaller(),
);

/// Where staged updates live. Overridable for tests.
final updatePathsProvider = Provider<UpdatePaths>((ref) => _AppUpdatePaths());

/// Reads the running app's version. Default: package_info_plus.
abstract class AppVersionReader {
  Future<String> read();
}

class PackageInfoVersionReader implements AppVersionReader {
  @override
  Future<String> read() async => (await PackageInfo.fromPlatform()).version;
}

final appVersionReaderProvider = Provider<AppVersionReader>(
  (ref) => PackageInfoVersionReader(),
);

/// Called instead of `exit(0)` after a successful install hand-off.
/// Tests override to observe without terminating the harness.
final quitAppProvider = Provider<void Function()>((ref) => () => exit(0));

class _AppUpdatePaths implements UpdatePaths {
  @override
  Future<Directory> updatesRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'updates'));
  }

  @override
  Future<Directory> stageDir(String tag) async {
    final root = await updatesRoot();
    return Directory(p.join(root.path, tag));
  }
}

/// User-facing update preferences — the settings dialog toggles these.
final updateSettingsProvider =
    NotifierProvider<UpdateSettingsController, UpdateSettings>(
      UpdateSettingsController.new,
    );

class UpdateSettingsController extends Notifier<UpdateSettings> {
  @override
  UpdateSettings build() {
    try {
      return ref.read(updateStorageProvider).read();
    } catch (_) {
      return const UpdateSettings();
    }
  }

  Future<void> _write(UpdateSettings next) async {
    state = next;
    try {
      await ref.read(updateStorageProvider).write(next);
    } catch (_) {}
  }

  Future<void> setAutoCheck(bool value) =>
      _write(state.copyWith(autoCheck: value));

  Future<void> setAutoDownload(bool value) =>
      _write(state.copyWith(autoDownload: value));

  /// Internal bookkeeping shared with `UpdateController`.
  Future<void> markChecked() => _write(
    state.copyWith(lastCheckMs: DateTime.now().millisecondsSinceEpoch),
  );

  /// Clears the throttle stamp so the next auto-check runs immediately —
  /// used by "稍后" so a relaunch re-prompts instead of waiting out the
  /// throttle window.
  Future<void> resetThrottle() => _write(state.copyWith(lastCheckMs: 0));

  Future<void> skipVersion(String normalizedVersion) =>
      _write(state.copyWith(skippedVersion: normalizedVersion));

  Future<void> clearSkipped() =>
      _write(state.copyWith(clearSkipped: true));

  Future<void> setReadyTag(String? tag) => _write(
    tag == null
        ? state.copyWith(clearReady: true)
        : state.copyWith(readyTag: tag),
  );
}

final updateStatusProvider =
    NotifierProvider<UpdateController, UpdateStatus>(UpdateController.new);

/// Drives the check → download → verify → install pipeline. All entry
/// points funnel through [state.busy] so concurrent triggers (launch
/// auto-check, settings button, dialog action) can never double-run.
class UpdateController extends Notifier<UpdateStatus> {
  /// Auto-checks at most once per this interval; manual checks bypass.
  static const checkThrottle = Duration(hours: 6);

  @override
  UpdateStatus build() {
    Future<void>.microtask(_sweepStaging);
    return const UpdateStatus();
  }

  UpdateSettings get _settings => ref.read(updateSettingsProvider);
  UpdateSettingsController get _settingsCtl =>
      ref.read(updateSettingsProvider.notifier);

  /// Checks GitHub for a newer release.
  ///
  /// [manual] checks (the settings button) bypass the throttle and the
  /// skipped-version silencer — a user who asks for the latest release gets
  /// to see it even if they skipped it. Auto checks respect both.
  Future<void> check({bool manual = false}) async {
    if (state.busy) return;
    if (!manual &&
        DateTime.now().millisecondsSinceEpoch - _settings.lastCheckMs <
            checkThrottle.inMilliseconds) {
      return;
    }
    state = const UpdateStatus(phase: UpdatePhase.checking);
    try {
      final release = await ref.read(releaseClientProvider).latestRelease();
      // Throttle consumes only on a completed fetch — a failed auto-check
      // must not lock out retrying for 6 hours.
      await _settingsCtl.markChecked();
      final current = await _currentVersion();
      if (release == null || current == null || !isRemoteNewer(release.version, current)) {
        state = UpdateStatus(
          phase: UpdatePhase.upToDate,
          latestVersion: release?.version,
          currentVersion: current,
        );
        return;
      }
      final skipped = versionFromTag(_settings.skippedVersion ?? '');
      if (!manual && isSkipped(release.version, skipped)) {
        state = UpdateStatus(
          phase: UpdatePhase.upToDate,
          latestVersion: release.version,
          currentVersion: current,
        );
        return;
      }
      final asset = selectAsset(release.assets, hostPlatformToken());
      // A previously staged download for exactly this release is still
      // usable — skip straight to install.
      if (_settings.readyTag == release.tag &&
          await _stagedAppExists(release.tag)) {
        state = UpdateStatus(
          phase: UpdatePhase.ready,
          release: release,
          asset: asset,
          latestVersion: release.version,
          currentVersion: current,
        );
        return;
      }
      // A stale staged dir for a different tag is dead weight — drop it.
      final ready = _settings.readyTag;
      if (ready != null && ready != release.tag) {
        unawaited(_dropStage(ready));
        await _settingsCtl.setReadyTag(null);
      }
      state = UpdateStatus(
        phase: UpdatePhase.available,
        release: release,
        asset: asset,
        latestVersion: release.version,
        currentVersion: current,
      );
      if (_settings.autoDownload && asset != null) {
        await download();
      }
    } catch (e) {
      // Auto-checks fail silently (network hiccups, API rate limits); a
      // manual check surfaces the error in settings.
      state = manual
          ? UpdateStatus(
              phase: UpdatePhase.failed,
              stage: UpdateStage.check,
              error: e.toString(),
            )
          : const UpdateStatus();
    }
  }

  /// Downloads the pending release's asset, verifies it, stages it.
  /// Idempotent: a still-valid staged payload short-circuits to `ready`.
  Future<void> download() async {
    final release = state.release;
    final asset = state.asset;
    if (release == null || asset == null || state.busy) return;
    if (_settings.readyTag == release.tag &&
        await _stagedAppExists(release.tag)) {
      state = state.copyWith(phase: UpdatePhase.ready, progress: 1);
      return;
    }
    state = state.copyWith(phase: UpdatePhase.downloading, progress: 0);
    try {
      final dir = await ref.read(updatePathsProvider).stageDir(release.tag);
      await ref
          .read(updateDownloaderProvider)
          .fetchAndStage(
            asset,
            dir,
            onProgress: (v) {
              if (state.phase == UpdatePhase.downloading) {
                state = state.copyWith(progress: v);
              }
            },
          );
      state = state.copyWith(phase: UpdatePhase.verifying);
      await _settingsCtl.setReadyTag(release.tag);
      state = state.copyWith(phase: UpdatePhase.ready, progress: 1);
    } on DownloadCancelled {
      // Back to "available" — the user can start the download again.
      state = state.copyWith(phase: UpdatePhase.available, progress: 0);
    } catch (e) {
      state = state.copyWith(
        phase: UpdatePhase.failed,
        stage: UpdateStage.download,
        error: e.toString(),
      );
    }
  }

  /// Aborts an in-flight download; the partial file is removed by the
  /// downloader.
  void cancelDownload() => ref.read(updateDownloaderProvider).cancel();

  /// Hands the staged update to the platform installer and quits when it
  /// confirms it is running.
  Future<void> installAndRelaunch() async {
    final release = state.release;
    if (release == null || state.busy) return;
    state = state.copyWith(phase: UpdatePhase.installing);
    try {
      final dir = await ref.read(updatePathsProvider).stageDir(release.tag);
      // Locate the extracted .app rather than assuming its name.
      Directory? appBundle;
      final payload = Directory(p.join(dir.path, 'payload'));
      await for (final entity in payload.list(recursive: true)) {
        if (entity is Directory && entity.path.endsWith('.app')) {
          appBundle = entity;
          break;
        }
      }
      final staged = StagedUpdate(
        root: dir,
        archive: File(p.join(dir.path, 'package.zip')),
        app: appBundle,
      );
      final handed = await ref
          .read(updateInstallerProvider)
          .installAndRelaunch(staged);
      if (handed) {
        await _settingsCtl.setReadyTag(null);
        ref.read(quitAppProvider)();
        return;
      }
      await revealStagedUpdate(staged);
      state = state.copyWith(
        phase: UpdatePhase.failed,
        stage: UpdateStage.install,
        error: 'helper did not start',
      );
    } catch (e) {
      state = state.copyWith(
        phase: UpdatePhase.failed,
        stage: UpdateStage.install,
        error: e.toString(),
      );
    }
  }

  /// Dismisses the current prompt without any persistence ("later"). The
  /// throttle stamp is reset so the next launch checks again — "later"
  /// means "remind me next launch", not "stay quiet for 6 hours".
  void dismiss() {
    if (state.phase == UpdatePhase.available ||
        state.phase == UpdatePhase.ready ||
        state.phase == UpdatePhase.failed) {
      unawaited(_settingsCtl.resetThrottle());
      state = UpdateStatus(latestVersion: state.latestVersion);
    }
  }

  /// Lets the settings UI retry the failing stage.
  Future<void> retry() async {
    if (state.stage == UpdateStage.check) {
      await check(manual: true);
    } else if (state.stage == UpdateStage.download) {
      state = state.copyWith(phase: UpdatePhase.available, clearError: true);
      await download();
    } else if (state.stage == UpdateStage.install) {
      // The staged payload is still valid — go straight back to ready.
      state = state.copyWith(phase: UpdatePhase.ready, clearError: true);
    } else {
      state = UpdateStatus(
        phase: UpdatePhase.available,
        release: state.release,
        asset: state.asset,
        latestVersion: state.latestVersion,
      );
    }
  }

  /// "Skip this version" — persists the normalized version, drops any
  /// staged download for it, and settles back to quiet. Guarded by `busy`:
  /// skipping mid-install would delete the payload under the helper's feet.
  Future<void> skipVersion() async {
    final release = state.release;
    if (release == null || state.busy) return;
    await _settingsCtl.skipVersion(release.version.toString());
    if (_settings.readyTag == release.tag) {
      unawaited(_dropStage(release.tag));
      await _settingsCtl.setReadyTag(null);
    }
    state = const UpdateStatus(phase: UpdatePhase.upToDate);
  }

  Future<Version?> _currentVersion() async {
    try {
      return versionFromPackage(
        await ref.read(appVersionReaderProvider).read(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _stagedAppExists(String tag) async {
    try {
      final payload = Directory(
        p.join(
          (await ref.read(updatePathsProvider).stageDir(tag)).path,
          'payload',
        ),
      );
      await for (final entity in payload.list(recursive: true)) {
        if (entity is Directory && entity.path.endsWith('.app')) return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _dropStage(String tag) async {
    try {
      final dir = await ref.read(updatePathsProvider).stageDir(tag);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  /// Launch-time cleanup: delete staging for anything that is not the
  /// persisted readyTag, plus the readyTag itself once the running app is
  /// already that version (a consumed update leaves only the tiny helper
  /// bundle behind, which this removes). Keeps downloads from ever
  /// accumulating.
  Future<void> _sweepStaging() async {
    try {
      final root = await ref.read(updatePathsProvider).updatesRoot();
      if (!await root.exists()) return;
      final ready = _settings.readyTag;
      final current = await _currentVersion();
      await for (final entity in root.list()) {
        if (entity is! Directory) continue;
        final tag = p.basename(entity.path);
        final consumed =
            tag == ready &&
            current != null &&
            (versionFromTag(tag) ?? Version(0, 0, 0)) <= current;
        if (tag != ready || consumed) {
          if (consumed) await _settingsCtl.setReadyTag(null);
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
