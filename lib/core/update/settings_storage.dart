import 'package:shared_preferences/shared_preferences.dart';

/// User-facing update preferences plus bookkeeping needed across launches.
///
/// `skippedVersion` stores a normalized `X.Y.Z` string: that release (and
/// anything older) never prompts again; a newer release does. `readyTag`
/// records a fully downloaded+verified update so a later relaunch can offer
/// install without re-downloading.
class UpdateSettings {
  const UpdateSettings({
    this.autoCheck = true,
    this.autoDownload = false,
    this.skippedVersion,
    this.lastCheckMs = 0,
    this.readyTag,
  });

  /// Check GitHub on launch (throttled), silently.
  final bool autoCheck;

  /// When a new version is found, download it without asking first.
  final bool autoDownload;

  /// Normalized `X.Y.Z` the user chose to skip; `null` = nothing skipped.
  final String? skippedVersion;

  /// Epoch ms of the last check attempt (throttle source).
  final int lastCheckMs;

  /// Release tag whose artifacts sit verified in the staging directory.
  final String? readyTag;

  UpdateSettings copyWith({
    bool? autoCheck,
    bool? autoDownload,
    String? skippedVersion,
    bool clearSkipped = false,
    int? lastCheckMs,
    String? readyTag,
    bool clearReady = false,
  }) {
    return UpdateSettings(
      autoCheck: autoCheck ?? this.autoCheck,
      autoDownload: autoDownload ?? this.autoDownload,
      skippedVersion: clearSkipped
          ? null
          : (skippedVersion ?? this.skippedVersion),
      lastCheckMs: lastCheckMs ?? this.lastCheckMs,
      readyTag: clearReady ? null : (readyTag ?? this.readyTag),
    );
  }
}

/// Persistence seam, mirroring `LocaleStorage`: synchronous `read` so
/// controllers can build initial state before the first frame; writes are
/// fire-and-forget and must never throw into the UI.
abstract class UpdateStorage {
  UpdateSettings read();
  Future<void> write(UpdateSettings settings);
}

/// shared_preferences-backed storage; keys are independent so partially
/// written older builds degrade gracefully.
class SharedPreferencesUpdateStorage implements UpdateStorage {
  SharedPreferencesUpdateStorage(this._prefs);

  static const autoCheckKey = 'update.auto_check';
  static const autoDownloadKey = 'update.auto_download';
  static const skippedKey = 'update.skipped_version';
  static const lastCheckKey = 'update.last_check_ms';
  static const readyTagKey = 'update.ready_tag';

  final SharedPreferences _prefs;

  @override
  UpdateSettings read() {
    try {
      return UpdateSettings(
        autoCheck: _prefs.getBool(autoCheckKey) ?? true,
        autoDownload: _prefs.getBool(autoDownloadKey) ?? false,
        skippedVersion: _prefs.getString(skippedKey),
        lastCheckMs: _prefs.getInt(lastCheckKey) ?? 0,
        readyTag: _prefs.getString(readyTagKey),
      );
    } catch (_) {
      return const UpdateSettings();
    }
  }

  @override
  Future<void> write(UpdateSettings settings) async {
    try {
      await _prefs.setBool(autoCheckKey, settings.autoCheck);
      await _prefs.setBool(autoDownloadKey, settings.autoDownload);
      if (settings.skippedVersion == null) {
        await _prefs.remove(skippedKey);
      } else {
        await _prefs.setString(skippedKey, settings.skippedVersion!);
      }
      await _prefs.setInt(lastCheckKey, settings.lastCheckMs);
      if (settings.readyTag == null) {
        await _prefs.remove(readyTagKey);
      } else {
        await _prefs.setString(readyTagKey, settings.readyTag!);
      }
    } catch (_) {
      // Persistence is best-effort; in-memory state still applies.
    }
  }
}

/// Volatile storage for tests and provider fallback.
class MemoryUpdateStorage implements UpdateStorage {
  MemoryUpdateStorage([this._value = const UpdateSettings()]);

  UpdateSettings _value;

  @override
  UpdateSettings read() => _value;

  @override
  Future<void> write(UpdateSettings settings) async {
    _value = settings;
  }
}
