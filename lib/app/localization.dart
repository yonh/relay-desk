/// App-wide language switching: the user's locale preference, its injectable
/// persistence, and the Riverpod controller driving `MaterialApp.locale`.
///
/// Supported UI languages live in `lib/l10n/app_*.arb` (English + Simplified
/// Chinese). The persisted value is one of `system` (follow the OS locale),
/// `en`, or `zh`. Anything else — missing, legacy, or corrupted — parses to
/// `system`, which resolves through the platform's locale and falls back to
/// English when unsupported.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/platform/domain.dart';
import '../core/platform/webview_adapter.dart';
import '../l10n/app_localizations.dart';

/// The user's explicit language choice, or `system` to follow the OS locale.
enum LocalePreference {
  system,
  english,
  simplifiedChinese;

  /// Persisted representation. Unknown stored values never reach here — they
  /// are normalized by [parse] before they can become state.
  String get storageValue => switch (this) {
    LocalePreference.system => 'system',
    LocalePreference.english => 'en',
    LocalePreference.simplifiedChinese => 'zh',
  };

  /// Parses a stored value. `null`, `'system'`, and any unrecognized string
  /// (including values from future versions) fall back to [system], which
  /// then resolves via the platform locale and finally English.
  static LocalePreference parse(String? raw) => switch (raw) {
    'en' => LocalePreference.english,
    'zh' => LocalePreference.simplifiedChinese,
    _ => LocalePreference.system,
  };
}

extension LocalePreferenceX on LocalePreference {
  /// The explicit `MaterialApp.locale` override; `null` = follow system.
  Locale? get locale => switch (this) {
    LocalePreference.system => null,
    LocalePreference.english => const Locale('en'),
    LocalePreference.simplifiedChinese => const Locale('zh'),
  };
}

/// Injectable persistence seam for the locale preference. Production uses
/// [SharedPreferencesLocaleStorage]; tests inject [InMemoryLocaleStorage]
/// or a fake. `read` is synchronous so the initial locale is known before the
/// first frame (no startup flicker); `write` is fire-and-forget.
abstract class LocaleStorage {
  /// Reads the persisted preference. Implementations must normalize unknown
  /// values to [LocalePreference.system] and must not throw on missing data.
  LocalePreference read();

  /// Persists [preference]. Implementations must swallow I/O failures — a
  /// persistence failure must never crash the app or surface as an
  /// unhandled async error.
  Future<void> write(LocalePreference preference);
}

/// shared_preferences-backed storage. The instance is created before runApp
/// so [read] hits the in-memory cache synchronously.
class SharedPreferencesLocaleStorage implements LocaleStorage {
  SharedPreferencesLocaleStorage(this._prefs);

  static const String key = 'app.locale';

  final SharedPreferences _prefs;

  @override
  LocalePreference read() {
    try {
      return LocalePreference.parse(_prefs.getString(key));
    } catch (_) {
      return LocalePreference.system;
    }
  }

  @override
  Future<void> write(LocalePreference preference) async {
    try {
      await _prefs.setString(key, preference.storageValue);
    } catch (_) {
      // Persistence is best-effort: a disk/plugin failure must not crash or
      // propagate as an unhandled async error. The in-memory state (already
      // updated by the controller) still applies for this session.
    }
  }
}

/// Volatile storage used as the provider default and in tests.
class InMemoryLocaleStorage implements LocaleStorage {
  InMemoryLocaleStorage([this._value = LocalePreference.system]);

  LocalePreference _value;

  @override
  LocalePreference read() => _value;

  @override
  Future<void> write(LocalePreference preference) async {
    _value = preference;
  }
}

/// The active [LocaleStorage]. `main()` overrides this with a
/// [SharedPreferencesLocaleStorage] built from the prefs instance resolved
/// before `runApp`; the in-memory default keeps tests and fallback paths
/// working without platform plugins.
final localeStorageProvider = Provider<LocaleStorage>(
  (ref) => InMemoryLocaleStorage(),
);

/// The current locale preference, watched by `RelayDeskApp`.
final localePreferenceProvider =
    NotifierProvider<LocaleController, LocalePreference>(LocaleController.new);

/// Holds the user's locale preference and persists changes through the
/// injected [LocaleStorage].
class LocaleController extends Notifier<LocalePreference> {
  /// Serialized write queue: each `select` appends to this chain so a slow
  /// in-flight write can never be overtaken by (and then overwrite) a newer
  /// selection. [_persist] never throws, so a failed write neither breaks
  /// the chain nor becomes an unhandled async error.
  Future<void> _writeChain = Future<void>.value();

  @override
  LocalePreference build() {
    try {
      return ref.read(localeStorageProvider).read();
    } catch (_) {
      return LocalePreference.system;
    }
  }

  /// Applies [preference] immediately and queues its persistence write
  /// behind any in-flight one.
  void select(LocalePreference preference) {
    if (preference == state) return;
    state = preference;
    _writeChain = _writeChain.then((_) => _persist(preference));
  }

  Future<void> _persist(LocalePreference preference) async {
    try {
      await ref.read(localeStorageProvider).write(preference);
    } catch (_) {
      // Catches synchronous throws from `write` (the try surrounds the call
      // itself) as well as async failures. A persistence failure never
      // crashes the app, blocks the UI, or prevents later writes.
    }
  }
}

/// Convenience accessor: `context.l10n.someMessage`.
extension AppL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Localized presentation labels for [IsolationMode]. The domain's
/// `displayName`/`dbValue` stay untouched (database contract); this maps the
/// enum to UI strings.
extension IsolationModeL10n on IsolationMode {
  String label(AppLocalizations l10n) => switch (this) {
    IsolationMode.nativeProfile => l10n.isolationNativeProfile,
    IsolationMode.originProxy => l10n.isolationOriginProxy,
    IsolationMode.sharedSession => l10n.isolationSharedSession,
  };
}

/// Localized presentation labels for [LayoutMode] (toolbar segments).
extension LayoutModeL10n on LayoutMode {
  String label(AppLocalizations l10n) => switch (this) {
    LayoutMode.canvas => l10n.layoutCanvas,
    LayoutMode.grid => l10n.layoutGrid,
    LayoutMode.columns => l10n.layoutColumns,
    LayoutMode.focus => l10n.layoutFocus,
  };
}

/// Localized presentation labels for [WebviewState] panel badges.
extension WebviewStateL10n on WebviewState {
  String label(AppLocalizations l10n) => switch (this) {
    WebviewState.closed => l10n.stateClosed,
    WebviewState.openingEmbedded => l10n.stateOpening,
    WebviewState.embedded => l10n.stateEmbedded,
    WebviewState.detaching => l10n.stateDetaching,
    WebviewState.detached => l10n.stateDetached,
    WebviewState.attaching => l10n.stateAttaching,
    WebviewState.closing => l10n.stateClosing,
    WebviewState.failed => l10n.stateFailed,
  };
}
