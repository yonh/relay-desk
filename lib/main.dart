import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/localization.dart';
import 'app/icon_settings.dart';
import 'features/automation/automation_provider.dart';
import 'core/update/settings_storage.dart';
import 'features/management/management_screen.dart';
import 'features/common/dock_icon_bridge.dart';
import 'features/update/update_controller.dart';
import 'features/update/update_ui.dart';
import 'features/workspace/workspace_screen.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Resolve prefs before runApp so the persisted locale applies to the first
  // frame (no startup language flicker). If prefs are unavailable the
  // in-memory default keeps the app running on the system locale.
  LocaleStorage localeStorage = InMemoryLocaleStorage();
  IconStorage iconStorage = MemoryIconStorage();
  UpdateStorage updateStorage = MemoryUpdateStorage();
  try {
    final preferences = await SharedPreferences.getInstance();
    localeStorage = SharedPreferencesLocaleStorage(preferences);
    iconStorage = SharedPreferencesIconStorage(preferences);
    updateStorage = SharedPreferencesUpdateStorage(preferences);
  } catch (_) {}
  try {
    await PlatformAppIcon().apply(iconStorage.read());
  } catch (_) {
    // The bundled B2 icon remains available if the native bridge fails.
  }
  runApp(
    ProviderScope(
      overrides: [
        localeStorageProvider.overrideWithValue(localeStorage),
        iconStorageProvider.overrideWithValue(iconStorage),
        updateStorageProvider.overrideWithValue(updateStorage),
      ],
      child: const RelayDeskApp(),
    ),
  );
}

class RelayDeskApp extends ConsumerWidget {
  const RelayDeskApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // An explicit preference pins the locale; `system` leaves it null so the
    // platform locale resolves against supportedLocales (en fallback).
    final preference = ref.watch(localePreferenceProvider);
    return MaterialApp(
      title: 'Relay Desk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      locale: preference.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const DockIconBridge(child: RelayDeskHome()),
    );
  }
}

class RelayDeskHome extends ConsumerWidget {
  const RelayDeskHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(automationServerProvider);
    return const Scaffold(
      body: UpdateGate(
        child: Row(
          children: [
            ManagementScreen(),
            VerticalDivider(width: 1),
            Expanded(child: WorkspaceScreen()),
          ],
        ),
      ),
    );
  }
}
