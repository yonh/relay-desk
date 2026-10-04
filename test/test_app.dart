/// Shared test harness: a MaterialApp wired with the app's localization
/// delegates and supported locales. Pass an explicit [locale] to pin the
/// language (existing suites run in English); leave it null to let
/// [localePreferenceProvider] drive the locale, as production does.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:relay_desk/app/localization.dart';
import 'package:relay_desk/l10n/app_localizations.dart';

class LocalizedTestApp extends ConsumerWidget {
  const LocalizedTestApp({super.key, required this.home, this.locale});

  final Widget home;

  /// When non-null, pins `MaterialApp.locale` (independent of the locale
  /// preference provider). When null, the provider's preference applies.
  final Locale? locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      locale: locale ?? ref.watch(localePreferenceProvider).locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: home,
    );
  }
}
