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
final quitAppProvider = Provider<void Function()>(
  (ref) =>
      () => exit(0),
);

class _AppUpdatePaths implements UpdatePaths {
  @override
  Future<Directory> updatesRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'updates'));
  }

  @override
  Future<Directory> stageDir(String tag) async {
    final root = await updatesRoot();
    // The tag comes from release metadata — keep it a plain directory name
    // even if a tag ever slips past semver parsing with separators in it.
    var safe = tag.replaceAll(RegExp('[^A-Za-z0-9._+-]'), '_');
    // Dots survive the filter, so '.'/'..' would escape the updates dir.
    if (RegExp(r'^\.+$').hasMatch(safe)) safe = 'v$safe';
    return Directory(p.join(root.path, safe));
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

  Future<void> clearSkipped() => _write(state.copyWith(clearSkipped: true));

  Future<void> setReadyTag(String? tag) => _write(
    tag == null
        ? state.copyWith(clearReady: true)
        : state.copyWith(readyTag: tag),
  );
}

final updateStatusProvider = NotifierProvider<UpdateController, UpdateStatus>(
  UpdateController.new,
);

/// Drives the check → download → verify → install pipeline. All entry
/// points funnel through [state.busy] so concurrent triggers (launch
/// auto-check, settings button, dialog action) can never double-run.
class UpdateController extends Notifier<UpdateStatus> {
  /// Auto-checks at most once per this interval; manual checks bypass.
  static const checkThrottle = Duration(hours: 6);

  /// Shared operation mutex taken SYNCHRONOUSLY before the first await by
  /// every entry point that mutates staged files. `state.busy` alone is
  /// not enough: `skipVersion` awaits persistence and staging cleanup
  /// while the phase is still `ready`, so a reopened dialog could start
  /// an install over the same payload mid-delete.
  var _opBusy = false;

  bool get _locked => state.busy || _opBusy;

  @override
  UpdateStatus build() {
    Future<void>.microtask(_sweepStaging);
    // The settings section always shows the installed version — populate
    // it now instead of waiting for the first check to run.
    Future<void>.microtask(() async {
      final v = await _currentVersion();
      if (v != null && state.currentVersion == null) {
        state = state.copyWith(currentVersion: v);
      }
    });
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
    if (_locked) return;
    if (!manual &&
        DateTime.now().millisecondsSinceEpoch - _settings.lastCheckMs <
            checkThrottle.inMilliseconds) {
      return;
    }
    // Drop any stale release candidate up front — a failed re-check must
    // never leave an old asset operable behind an up-to-date banner.
    state = state.copyWith(
      phase: UpdatePhase.checking,
      clearError: true,
      clearRelease: true,
    );
    try {
      final release = await ref.read(releaseClientProvider).latestRelease();
      // Throttle consumes only on a completed fetch — a failed auto-check
      // must not lock out retrying for 6 hours.
      await _settingsCtl.markChecked();
      final current = await _currentVersion();
      if (release == null ||
          current == null ||
          !isRemoteNewer(release.version, current)) {
        state = UpdateStatus(
          phase: UpdatePhase.upToDate,
          latestVersion: release?.version,
          currentVersion: current ?? state.currentVersion,
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
      // Awaited, not fire-and-forget: a background delete could still be
      // running when a later manual download restages that same tag.
      final ready = _settings.readyTag;
      if (ready != null && ready != release.tag) {
        await _dropStage(ready);
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
      // manual check surfaces the error in settings. Either way the
      // installed-version row must survive the reset.
      state = manual
          ? state.copyWith(
              phase: UpdatePhase.failed,
              stage: UpdateStage.check,
              error: e.toString(),
            )
          : state.copyWith(phase: UpdatePhase.idle, clearError: true);
    }
  }

  /// Downloads the pending release's asset, verifies it, stages it.
  /// Idempotent: a still-valid staged payload short-circuits to `ready`.
  Future<void> download() async {
    final release = state.release;
    final asset = state.asset;
    if (release == null || asset == null || _locked) return;
    // The op lock covers the WHOLE method — the staged-dir probe below
    // awaits before `busy` engages, so without it two downloads could both
    // decide a re-fetch is needed and write the same `.part` file, and a
    // skip could interleave and let the download write back the skipped
    // version afterward.
    _opBusy = true;
    try {
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
    } finally {
      _opBusy = false;
    }
  }

  /// Aborts an in-flight download; the partial file is removed by the
  /// downloader.
  void cancelDownload() => ref.read(updateDownloaderProvider).cancel();

  /// Hands the staged update to the platform installer and quits when it
  /// confirms it is running.
  Future<void> installAndRelaunch() async {
    final release = state.release;
    if (release == null || _locked) return;
    state = state.copyWith(phase: UpdatePhase.installing);
    try {
      final dir = await ref.read(updatePathsProvider).stageDir(release.tag);
      // Locate the extracted .app rather than assuming its name. Only
      // macOS stages a payload — Windows/Linux stage only the archive.
      Directory? appBundle;
      final payload = Directory(p.join(dir.path, 'payload'));
      if (await payload.exists()) {
        await for (final entity in payload.list(recursive: true)) {
          if (entity is Directory && entity.path.endsWith('.app')) {
            appBundle = entity;
            break;
          }
        }
      }
      // The archive name follows the downloaded asset (.zip or .tar.gz),
      // not a hardcoded package.zip — find what actually landed.
      var archive = File(p.join(dir.path, 'package.zip'));
      await for (final entity in dir.list()) {
        if (entity is File && p.basename(entity.path).startsWith('package.')) {
          archive = entity;
          break;
        }
      }
      final staged = StagedUpdate(root: dir, archive: archive, app: appBundle);
      if (appBundle != null) {
        final handed = await ref
            .read(updateInstallerProvider)
            .installAndRelaunch(staged);
        if (handed) {
          await _settingsCtl.setReadyTag(null);
          ref.read(quitAppProvider)();
          return;
        }
      }
      // No staged bundle (Windows/Linux, or a zip without one) — the
      // manual path: reveal the real archive in the file manager.
      await revealStagedUpdate(staged);
      state = state.copyWith(
        phase: UpdatePhase.failed,
        stage: UpdateStage.install,
        error: 'manual install required — archive revealed',
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
      // Keep latest+current versions — the settings rows must not blank
      // out on dismiss.
      state = state.copyWith(
        phase: UpdatePhase.idle,
        clearRelease: true,
        clearError: true,
      );
    }
  }

  /// Lets the settings UI retry the failing stage.
  Future<void> retry() async {
    // A download-stage retry flips phase back to `available`, which clears
    // `busy` — without this guard a rapid second tap would start a second
    // fetchAndStage writing the same `.part` file concurrently.
    if (_locked) return;
    if (state.stage == UpdateStage.check) {
      await check(manual: true);
    } else if (state.stage == UpdateStage.download) {
      state = state.copyWith(phase: UpdatePhase.available, clearError: true);
      await download();
    } else if (state.stage == UpdateStage.install) {
      // The staged payload is still valid — go straight back to ready.
      state = state.copyWith(phase: UpdatePhase.ready, clearError: true);
    } else {
      state = state.copyWith(phase: UpdatePhase.available, clearError: true);
    }
  }

  /// "Skip this version" — persists the normalized version, drops any
  /// staged download for it, and settles back to quiet. The op lock is
  /// taken synchronously: without it the awaits below run while the phase
  /// still reads `ready`, letting a reopened dialog start an install over
  /// the payload being deleted (and the final quiet state could clobber
  /// an `installing` phase that started mid-skip).
  Future<void> skipVersion() async {
    final release = state.release;
    if (release == null || _locked) return;
    _opBusy = true;
    try {
      await _settingsCtl.skipVersion(release.version.toString());
      if (_settings.readyTag == release.tag) {
        // Awaited for the same reason — a re-download of this exact tag
        // must never race the removal of its old staging dir.
        await _dropStage(release.tag);
        await _settingsCtl.setReadyTag(null);
      }
      state = state.copyWith(
        phase: UpdatePhase.upToDate,
        clearRelease: true,
        clearError: true,
      );
    } finally {
      _opBusy = false;
    }
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
      final current = await _currentVersion();
      await for (final entity in root.list()) {
        if (entity is! Directory) continue;
        // Each delete takes the shared op mutex briefly and RE-VALIDATES
        // under it — reading readyTag before a long await and deleting on
        // that stale snapshot can wipe a freshly staged dir. Between
        // entries we hold nothing, so a real operation can always slip in
        // and we stand down instead of blocking it.
        if (_locked) return;
        _opBusy = true;
        try {
          if (state.busy) return;
          final ready = _settings.readyTag;
          final tag = p.basename(entity.path);
          final consumed =
              tag == ready &&
              current != null &&
              (versionFromTag(tag) ?? Version(0, 0, 0)) <= current;
          // The live ready payload is kept; everything else goes.
          if (tag == ready && !consumed) continue;
          if (consumed) await _settingsCtl.setReadyTag(null);
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        } finally {
          _opBusy = false;
        }
      }
    } catch (_) {}
  }
}
