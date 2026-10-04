/// Tests for app-wide language switching: menu-driven immediate en/zh
/// switching, persisted preference restore in a fresh controller, system /
/// unsupported-locale fallback, widget-state preservation across a switch,
/// live update of open dialogs + OverlayEntry surfaces, and resilience to
/// persistence failures.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_desk/app/localization.dart';
import 'package:relay_desk/app/providers.dart';
import 'package:relay_desk/core/platform/domain.dart';
import 'package:relay_desk/data/database/database.dart';
import 'package:relay_desk/data/repositories/project_repository.dart';
import 'package:relay_desk/features/management/management_screen.dart';
import 'package:relay_desk/features/workspace/workspace_controller.dart';
import 'package:relay_desk/features/workspace/workspace_screen.dart';
import 'package:relay_desk/main.dart';
import 'package:relay_desk/platform/webview/headless_webview_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_app.dart';

/// Raw-string fake so tests can seed both valid and invalid persisted values.
class FakeLocaleStorage implements LocaleStorage {
  FakeLocaleStorage([this._stored]);

  String? _stored;
  Object? error;
  int writes = 0;

  @override
  LocalePreference read() {
    final e = error;
    if (e != null) throw e;
    return LocalePreference.parse(_stored);
  }

  @override
  Future<void> write(LocalePreference preference) async {
    writes++;
    final e = error;
    if (e != null) throw e;
    _stored = preference.storageValue;
  }
}

/// Storage whose writes complete after [writeDelay] (fake-async safe) and can
/// be made to fail — synchronously via [syncError] or asynchronously via
/// [asyncFailuresRemaining]. Records persisted values in [writes].
class DelayedLocaleStorage implements LocaleStorage {
  DelayedLocaleStorage([this._stored]);

  String? _stored;
  Duration writeDelay = Duration.zero;
  int asyncFailuresRemaining = 0;
  Object? syncError;
  final List<String> writes = [];

  @override
  LocalePreference read() => LocalePreference.parse(_stored);

  @override
  Future<void> write(LocalePreference preference) {
    final sync = syncError;
    if (sync != null) throw sync; // synchronous failure before any Future
    return Future<void>.delayed(writeDelay).then((_) {
      if (asyncFailuresRemaining > 0) {
        asyncFailuresRemaining--;
        throw StateError('write failed');
      }
      _stored = preference.storageValue;
      writes.add(preference.storageValue);
    });
  }
}

const _sidebarOnlyHome = Scaffold(body: Row(children: [ManagementScreen()]));

const _fullHome = Scaffold(
  body: Row(
    children: [
      ManagementScreen(),
      VerticalDivider(width: 1),
      Expanded(child: WorkspaceScreen()),
    ],
  ),
);

void main() {
  late RelayDatabase db;
  late HeadlessWebviewAdapter adapter;
  late FakeLocaleStorage storage;

  setUp(() {
    db = RelayDatabase(NativeDatabase.memory());
    adapter = HeadlessWebviewAdapter();
    storage = FakeLocaleStorage();
  });

  tearDown(() async {
    adapter.dispose();
    await db.close();
  });

  ProviderContainer makeContainer({LocaleStorage? localeStorage}) =>
      ProviderContainer(
        overrides: [
          databaseProvider.overrideWith((ref) async {
            ref.onDispose(db.close);
            return db;
          }),
          webviewAdapterProvider.overrideWithValue(adapter),
          webviewPlatformSupportedProvider.overrideWithValue(false),
          localeStorageProvider.overrideWithValue(localeStorage ?? storage),
        ],
      );

  Future<ProviderContainer> boot(
    WidgetTester tester, {
    Widget? home,
    Size surfaceSize = const Size(1440, 900),
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = makeContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(home: home ?? _sidebarOnlyHome),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// Boots the production [RelayDeskApp] (which watches
  /// `localePreferenceProvider` itself) instead of the test wrapper.
  Future<ProviderContainer> bootApp(
    WidgetTester tester, {
    Size surfaceSize = const Size(1440, 900),
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = makeContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const RelayDeskApp(),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('menu switches to 简体中文 and back to English immediately', (
    tester,
  ) async {
    final container = await bootApp(tester);
    expect(find.text('Welcome to Relay Desk'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('language-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('简体中文'));
    await tester.pumpAndSettle();

    expect(find.text('欢迎使用 Relay Desk'), findsOneWidget);
    expect(find.text('Welcome to Relay Desk'), findsNothing);
    expect(
      container.read(localePreferenceProvider),
      LocalePreference.simplifiedChinese,
    );
    expect(storage._stored, 'zh');

    await tester.tap(find.byKey(const ValueKey('language-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Relay Desk'), findsOneWidget);
    expect(container.read(localePreferenceProvider), LocalePreference.english);
    expect(storage._stored, 'en');
  });

  testWidgets('menu shows check mark on the selected option', (tester) async {
    storage = FakeLocaleStorage('zh');
    await boot(tester);

    await tester.tap(find.byKey(const ValueKey('language-menu')));
    await tester.pumpAndSettle();

    final zhRow = find.byKey(const ValueKey('language-option-zh'));
    expect(zhRow, findsOneWidget);
    expect(
      find.descendant(of: zhRow, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('language-option-en')),
        matching: find.byIcon(Icons.check),
      ),
      findsNothing,
    );
  });

  testWidgets('persisted zh is restored by a fresh controller and app', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app.locale': 'zh'});
    final prefsStorage = SharedPreferencesLocaleStorage(
      await SharedPreferences.getInstance(),
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        localeStorageProvider.overrideWithValue(prefsStorage),
      ],
    );
    addTearDown(container.dispose);
    expect(
      container.read(localePreferenceProvider),
      LocalePreference.simplifiedChinese,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(home: _sidebarOnlyHome),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('欢迎使用 Relay Desk'), findsOneWidget);
  });

  testWidgets('invalid stored values fall back to system (then English)', (
    tester,
  ) async {
    for (final raw in [null, 'system', 'klingon', 'zh-Hant-HK']) {
      SharedPreferences.setMockInitialValues(
        raw == null ? const {} : {'app.locale': raw},
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        SharedPreferencesLocaleStorage(prefs).read(),
        LocalePreference.system,
        reason: 'stored "$raw" must normalize to system',
      );
    }

    // An unsupported system locale resolves to English via supportedLocales.
    final dispatcher = tester.binding.platformDispatcher;
    dispatcher.localeTestValue = const Locale('fr');
    addTearDown(dispatcher.clearLocaleTestValue);

    storage = FakeLocaleStorage('klingon');
    await boot(tester);
    expect(find.text('Welcome to Relay Desk'), findsOneWidget);
  });

  testWidgets('switching language preserves selection, panels and adapters', (
    tester,
  ) async {
    final projectRepo = ProjectRepository(db);
    final identityRepo = IdentityRepository(db);
    final project = await projectRepo.create(
      name: 'Demo',
      targetUrl: 'https://demo.app',
    );
    for (final name in ['Alpha', 'Bravo', 'Charlie']) {
      await identityRepo.create(
        projectId: project.id,
        name: name,
        color: '#FF0000',
        isolationMode: IsolationMode.nativeProfile,
      );
    }
    final container = await bootApp(tester);
    container.read(selectedProjectIdProvider.notifier).select(project.id);
    await tester.pumpAndSettle();

    final before = container.read(workspaceControllerProvider);
    expect(before.panels, hasLength(3));
    final panelIds = before.panels.keys.toList();
    final selectedPanel = before.selectedPanelId;
    final openCount = adapter.methodLog
        .where((m) => m.startsWith('openEmbedded('))
        .length;

    await tester.tap(find.byKey(const ValueKey('language-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('简体中文'));
    await tester.pumpAndSettle();

    final after = container.read(workspaceControllerProvider);
    expect(after.panels.keys, panelIds);
    expect(after.selectedPanelId, selectedPanel);
    expect(container.read(selectedProjectIdProvider), project.id);
    // No WebView was reconstructed: the adapter saw no new open calls.
    expect(
      adapter.methodLog.where((m) => m.startsWith('openEmbedded(')).length,
      openCount,
    );
    // The workspace chrome now renders Chinese.
    expect(find.text('3 个面板'), findsOneWidget);
  });

  testWidgets('open dialog and quick-sites overlay respond to locale change', (
    tester,
  ) async {
    final projectRepo = ProjectRepository(db);
    final identityRepo = IdentityRepository(db);
    final project = await projectRepo.create(
      name: 'Demo',
      targetUrl: 'https://demo.app',
    );
    await identityRepo.create(
      projectId: project.id,
      name: 'Alpha',
      color: '#FF0000',
      isolationMode: IsolationMode.nativeProfile,
    );
    final container = await boot(tester, home: _fullHome);
    container.read(selectedProjectIdProvider.notifier).select(project.id);
    await tester.pumpAndSettle();

    // OverlayEntry surface: the anchored quick-sites menu.
    await tester.tap(find.byKey(const ValueKey('quick-sites-trigger')));
    await tester.pumpAndSettle();
    expect(find.text('All sites'), findsOneWidget);

    container
        .read(localePreferenceProvider.notifier)
        .select(LocalePreference.simplifiedChinese);
    await tester.pumpAndSettle();
    expect(find.text('所有站点'), findsOneWidget);
    expect(find.text('快捷站点'), findsWidgets);

    // AlertDialog opened under the old locale must relabel after switching.
    await tester.tap(find.byKey(const ValueKey('quick-sites-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建项目'));
    await tester.pumpAndSettle();
    expect(find.text('名称'), findsOneWidget);

    container
        .read(localePreferenceProvider.notifier)
        .select(LocalePreference.english);
    await tester.pumpAndSettle();
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('New Project'), findsOneWidget);
  });

  testWidgets('persistence failures do not crash or surface async errors', (
    tester,
  ) async {
    storage.error = StateError('disk full');
    final container = await boot(tester);
    // Read failure fell back to system -> English UI still boots.
    expect(find.text('Welcome to Relay Desk'), findsOneWidget);

    // Write failure: the in-memory switch still applies immediately.
    container
        .read(localePreferenceProvider.notifier)
        .select(LocalePreference.simplifiedChinese);
    await tester.pumpAndSettle();
    expect(find.text('欢迎使用 Relay Desk'), findsOneWidget);
    expect(
      container.read(localePreferenceProvider),
      LocalePreference.simplifiedChinese,
    );
  });

  testWidgets(
    'rapid zh/en/system switching serializes writes; the final choice '
    'survives, and failed writes do not block later ones',
    (tester) async {
      final delayed = DelayedLocaleStorage()
        ..writeDelay = const Duration(milliseconds: 50);
      final container = makeContainer(localeStorage: delayed);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: LocalizedTestApp(home: _sidebarOnlyHome),
        ),
      );
      await tester.pumpAndSettle();
      final notifier = container.read(localePreferenceProvider.notifier);

      // Three rapid selects while each write is still in flight.
      notifier.select(LocalePreference.simplifiedChinese);
      notifier.select(LocalePreference.english);
      notifier.select(LocalePreference.system);
      // UI state is immediate even though persistence lags.
      expect(container.read(localePreferenceProvider), LocalePreference.system);

      await tester.pump(const Duration(milliseconds: 500));
      // Writes ran strictly in order; the last one wins.
      expect(delayed.writes, ['zh', 'en', 'system']);
      expect(delayed.read(), LocalePreference.system);

      // A fresh controller restores the final persisted choice.
      final fresh = ProviderContainer(
        overrides: [localeStorageProvider.overrideWithValue(delayed)],
      );
      addTearDown(fresh.dispose);
      expect(fresh.read(localePreferenceProvider), LocalePreference.system);

      // An async write failure must not break the chain: the next select
      // still persists.
      delayed.asyncFailuresRemaining = 1;
      notifier.select(LocalePreference.simplifiedChinese);
      await tester.pump(const Duration(milliseconds: 200));
      expect(delayed.read(), LocalePreference.system); // zh write failed
      notifier.select(LocalePreference.english);
      await tester.pump(const Duration(milliseconds: 200));
      expect(delayed.read(), LocalePreference.english);

      // A synchronous throw from write() is contained the same way.
      delayed.syncError = StateError('sync failure');
      notifier.select(LocalePreference.simplifiedChinese);
      await tester.pump(const Duration(milliseconds: 200));
      expect(delayed.read(), LocalePreference.english);
      delayed.syncError = null;
      notifier.select(LocalePreference.system);
      await tester.pump(const Duration(milliseconds: 200));
      expect(delayed.read(), LocalePreference.system);
    },
  );

  testWidgets('follow-system resolves a zh system locale and tracks changes', (
    tester,
  ) async {
    final dispatcher = tester.binding.platformDispatcher;
    dispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(dispatcher.clearLocalesTestValue);

    await bootApp(tester);
    expect(find.text('欢迎使用 Relay Desk'), findsOneWidget);

    // While following the system, an OS locale change relabels the UI.
    dispatcher.localesTestValue = const [Locale('en')];
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Relay Desk'), findsOneWidget);
    expect(find.text('欢迎使用 Relay Desk'), findsNothing);
  });

  testWidgets('explicit English overrides a zh system locale', (tester) async {
    final dispatcher = tester.binding.platformDispatcher;
    dispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(dispatcher.clearLocalesTestValue);

    storage = FakeLocaleStorage('en');
    await bootApp(tester);
    expect(find.text('Welcome to Relay Desk'), findsOneWidget);
    expect(find.text('欢迎使用 Relay Desk'), findsNothing);
  });
}
