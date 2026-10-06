# relay_desk

A new Flutter project.

## App icons

Open **Settings** at the bottom of the sidebar to choose A1, A2, B1, B2,
C1, or C3. B2 is the default. The app logo and the running macOS Dock icon
update together, and the choice is restored on the next launch. Use
**Restore B2 default** to reset it. Finder uses the bundled B2 icon.
While the app is running, right-click its macOS Dock icon and choose
**Switch Icon** to select the same six icons without opening Settings.

The transparent 1024×1024 PNGs are in `assets/logos/`. To reproduce their
extraction from the original design board and regenerate the bundled macOS
B2 icon sizes, run `swift tool/extract_logos.swift` from the repo root.

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

## Downloads & automated builds

`.github/workflows/release.yml` builds the app on GitHub Actions for all three
desktop platforms:

| Platform | Artifact | Runner |
| --- | --- | --- |
| Windows x64 | `RelayDesk-<ver>-windows-x64.zip` (portable, MSVC runtime bundled) | `windows-latest` |
| macOS (Apple Silicon + Intel) | `RelayDesk-<ver>-macos-universal.dmg` / `.zip` | `macos-latest` |
| Linux x64 | `RelayDesk-<ver>-linux-x64.tar.gz` (needs GTK 3) | `ubuntu-22.04` |

- **Pull requests / pushes to `main`**: analyze + test, then build all three
  platforms; packages are attached to the workflow run as artifacts.
- **Release**: push a tag `vX.Y.Z` (e.g. `git tag v1.0.0 && git push origin v1.0.0`).
  The tag becomes the app version, and the packages are published to a GitHub
  Release. Tags containing `-` (e.g. `v1.1.0-beta.1`) are marked pre-release.

Notes:

- The macOS build is ad-hoc signed, not notarized. On first launch macOS blocks
  it: right-click → Open (or System Settings → Privacy & Security → Open
  Anyway), or run `xattr -dr com.apple.quarantine /Applications/relay_desk.app`.
- The multi-profile WebView is a macOS-native plugin. On Windows and Linux the
  app runs with the management UI, but panels show a "WebView not supported"
  placeholder.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
