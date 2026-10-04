import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/localization.dart';
import 'features/management/management_screen.dart';
import 'features/workspace/workspace_screen.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Resolve prefs before runApp so the persisted locale applies to the first
  // frame (no startup language flicker). If prefs are unavailable the
  // in-memory default keeps the app running on the system locale.
  LocaleStorage localeStorage = InMemoryLocaleStorage();
  try {
    localeStorage = SharedPreferencesLocaleStorage(
      await SharedPreferences.getInstance(),
    );
  } catch (_) {}
  runApp(
    ProviderScope(
      overrides: [localeStorageProvider.overrideWithValue(localeStorage)],
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
      home: const RelayDeskHome(),
    );
  }
}

class RelayDeskHome extends ConsumerWidget {
  const RelayDeskHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(
      body: Row(
        children: [
          ManagementScreen(),
          VerticalDivider(width: 1),
          Expanded(child: WorkspaceScreen()),
        ],
      ),
    );
  }
}
