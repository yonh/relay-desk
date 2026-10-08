import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'downloader.dart';

/// Installs a staged update. The app cannot replace its own bundle while
/// running (and, sandboxed, cannot write outside its container at all), so
/// installation is handed to a helper that outlives the process.
abstract class UpdateInstaller {
  /// Returns `true` when the hand-off succeeded and the caller should quit
  /// immediately — the helper then swaps the bundle and relaunches.
  Future<bool> installAndRelaunch(StagedUpdate update);
}

/// Resolves the running `.app` bundle path from the executable location:
/// `<App>.app/Contents/MacOS/<exe>` → `<App>.app`. Returns `null` when the
/// binary is not inside a bundle (tests, `flutter run` edge cases).
Directory? runningAppBundle([String? executable]) {
  var dir = File(executable ?? Platform.resolvedExecutable).parent;
  while (true) {
    if (dir.path.endsWith('.app')) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

/// Path of the update helper bundled inside the main app at build time
/// (`Contents/Resources/RelayDeskUpdater.app`). Testable via [bundle].
File? embeddedHelperScript(Directory bundle) {
  final script = File(
    p.join(
      bundle.path,
      'Contents',
      'Resources',
      'RelayDeskUpdater.app',
      'Contents',
      'MacOS',
      'updater',
    ),
  );
  return script.existsSync() ? script : null;
}

/// Full self-update for macOS that keeps `app-sandbox` enabled.
///
/// `RelayDeskUpdater.app` ships inside the main bundle (Resources) and is
/// therefore covered by the app's signature and notarization — unlike a
/// helper generated at runtime, which a sandboxed app would create with
/// `com.apple.quarantine` and LaunchServices would refuse (-10810).
///
/// The helper is launched through `/usr/bin/open -n`; LaunchServices spawns
/// it outside our sandbox. `--args` argv is NOT used: LaunchServices drops
/// argv for launch requests issued by sandboxed processes (verified — the
/// stub arrives with only argv[0] and the script dies on `${1:?}`). The
/// handoff parameters therefore ride a file the app writes into the shared
/// staging area (`<updatesRoot>/handoff.params`), which the helper sources
/// line-by-line. argv is still accepted as a fallback so the helper can be
/// run by hand for debugging.
///
/// The helper writes `helper.started` into the staging dir, waits for this
/// process to exit, swaps the bundle with rollback protection, strips
/// quarantine on the new bundle, relaunches, and deletes the payload.
class MacOSUpdateInstaller implements UpdateInstaller {
  /// Polls for the helper marker this long before reporting hand-off
  /// failure; LaunchServices is normally well under a second but first-launch
  /// registration on a loaded machine can take longer.
  static const markerTimeout = Duration(seconds: 8);

  /// Name of the file that, when present in the stage dir, tells a
  /// late-starting helper to stand down instead of swapping.
  static const abortFileName = 'helper.abort';

  /// Handoff file written into `update.root`'s PARENT directory (the shared
  /// `<Application Support>/updates/` root the helper resolves from HOME).
  /// Key=value lines, one per field — bash reads it without quoting pitfalls.
  static const handoffFileName = 'handoff.params';

  @override
  Future<bool> installAndRelaunch(StagedUpdate update) async {
    final stagedApp = update.app;
    final target = runningAppBundle();
    if (stagedApp == null || target == null) return false;
    final helper = embeddedHelperApp(target);
    if (helper == null) return false;

    final marker = File(p.join(update.root.path, 'helper.started'));
    final abort = File(p.join(update.root.path, abortFileName));
    final aborted = File(p.join(update.root.path, 'helper.aborted'));
    for (final f in [marker, abort, aborted]) {
      if (await f.exists()) await f.delete();
    }

    // The handoff lives one level above the tag staging dir: the helper
    // finds `<updatesRoot>/handoff.params` without needing argv. Key=value
    // lines are sourced verbatim — no quoting, spaces in paths are fine.
    try {
      final handoff = File(p.join(update.root.parent.path, handoffFileName));
      await handoff.writeAsString(
        '${[
          'PARENT=$pid',
          'ROOT=${update.root.path}',
          'STAGED=${stagedApp.path}',
          'TARGET=${target.path}',
          'ARCHIVE=${update.archive.path}',
        ].join('\n')}\n',
      );
    } catch (_) {
      return false;
    }

    final launch = await Process.run('/usr/bin/open', ['-n', helper.path]);
    if (launch.exitCode != 0) return false;

    // Confirm the helper actually started before committing to quit.
    final deadline = DateTime.now().add(markerTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await marker.exists()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // Re-check once after the deadline — a marker that landed inside the
    // last poll interval is still a valid hand-off, not a failure.
    if (await marker.exists()) return true;
    // A late-starting helper would otherwise swap a still-running app —
    // leave the abort file for it to find.
    try {
      await abort.writeAsString('abort');
    } catch (_) {}
    return false;
  }

  /// The bundled `RelayDeskUpdater.app` inside the running app's Resources.
  /// Overridable in tests.
  Directory? embeddedHelperApp(Directory bundle) {
    final app = Directory(
      p.join(bundle.path, 'Contents', 'Resources', 'RelayDeskUpdater.app'),
    );
    return app.existsSync() ? app : null;
  }
}

/// Reveals the staged payload in the file manager — the manual path for
/// platforms where self-swap is not implemented, and the fallback when the
/// macOS helper cannot launch.
Future<void> revealStagedUpdate(StagedUpdate update) async {
  final target = update.app?.path ?? update.archive.path;
  try {
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', target]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', target]);
    } else {
      await Process.run('xdg-open', [update.root.path]);
    }
  } catch (_) {}
}
