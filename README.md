# relay_desk

A new Flutter project.

## Localization

The app UI is localized with `flutter gen-l10n` (ARB resources + generated
`AppLocalizations`). Supported languages:

- **English** (`en`) — template and fallback locale
- **Simplified Chinese** (`zh`, 简体中文)

The sidebar header language menu offers **Follow system** (default),
**简体中文**, and **English**. An explicit choice is persisted via
`shared_preferences` (key `app.locale`) and applies on the first frame;
`Follow system` resolves the OS locale against `supportedLocales` and falls
back to English when unsupported. Unknown/corrupt stored values also fall
back to system.

### Adding or editing strings

1. Add the key (with typed `placeholders` metadata if it interpolates) to
   `lib/l10n/app_en.arb` and translate it in `lib/l10n/app_zh.arb`.
2. Run `flutter gen-l10n` (or `flutter pub get` — `generate: true` regenerates
   automatically). Generated classes land in `lib/l10n/app_localizations*.dart`.
3. Reference it via `context.l10n.yourKey` (see
   `lib/app/localization.dart`, which also holds the `LocalePreference`
   controller and the injectable `LocaleStorage` seam).

### Adding a new language

1. Add `lib/l10n/app_<locale>.arb` with the full key set from `app_en.arb`.
2. Run `flutter gen-l10n`, add a menu entry in
   `lib/features/common/language_menu.dart`, and map its storage value in
   `LocalePreference.parse` / `storageValue` / `locale`
   (`lib/app/localization.dart`).

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
