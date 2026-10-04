/// Device-emulation presets for per-identity UA / viewport / touch-surface
/// overrides — the Dart counterpart of the Tauri baseline catalog in
/// `src/data/devices.ts`. Preset ids are identical on both sides so a
/// `device_preset_id` stored by either implementation resolves to the same
/// behavior (field-level contract, rewrite-plan §4.7).
///
/// What a preset actually does on desktop WKWebView:
/// - `userAgent` → `WKWebView.customUserAgent` (HTTP UA + navigator.userAgent).
///   `null` means "no override" — the view keeps its default desktop UA.
/// - `mobile` → the embedded panel's platform view is clamped to
///   `viewportWidth` CSS px (innerWidth/media queries see the emulated
///   width; innerHeight/devicePixelRatio follow the real surface) and the
///   detached window opens at the preset size.
/// - `touch` → a document-start JS property override injects
///   `navigator.maxTouchPoints` / `ontouchstart` (detection surface only —
///   no touch-event synthesis).
library;

/// How the embedded panel sizes the platform view for a preset.
enum ViewportSizing {
  /// No clamp — the view fills the panel, so `window.innerWidth` /
  /// `innerHeight` follow the real surface (desktop default and `custom`).
  free,

  /// Only the CSS width is clamped to the preset (mobile device
  /// emulation); the height follows the real surface.
  widthOnly,

  /// Both CSS dimensions are clamped to the preset — a fixed window-size
  /// viewport, letterboxed inside the panel when it is larger.
  fixed,
}

class DevicePreset {
  final String id;
  final String name;
  final int viewportWidth;
  final int viewportHeight;
  final double scaleFactor;
  final String? userAgent;
  final bool mobile;
  final bool touch;
  final ViewportSizing sizing;

  const DevicePreset({
    required this.id,
    required this.name,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.scaleFactor,
    required this.userAgent,
    required this.mobile,
    required this.touch,
    required this.sizing,
  });

  /// Whether the preset carries an emulated viewport size that should be
  /// forwarded to the native side (embedded clamp + detached window
  /// content size).
  bool get emulatedViewport => sizing != ViewportSizing.free;
}

/// The baseline catalog (src/data/devices.ts). Ids are persisted in
/// `identities.device_preset_id` — never rename them.
const List<DevicePreset> devicePresets = [
  DevicePreset(
    id: 'iphone-15',
    name: 'iPhone 15',
    viewportWidth: 393,
    viewportHeight: 852,
    scaleFactor: 3,
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
        'Mobile/15E148 Safari/604.1',
    mobile: true,
    touch: true,
    sizing: ViewportSizing.widthOnly,
  ),
  DevicePreset(
    id: 'pixel-9',
    name: 'Pixel 9',
    viewportWidth: 412,
    viewportHeight: 915,
    scaleFactor: 2.625,
    userAgent:
        'Mozilla/5.0 (Linux; Android 14; Pixel 9) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/120.0.6099.144 Mobile Safari/537.36',
    mobile: true,
    touch: true,
    sizing: ViewportSizing.widthOnly,
  ),
  DevicePreset(
    id: 'desktop-1920',
    name: 'Desktop',
    viewportWidth: 1920,
    viewportHeight: 1080,
    scaleFactor: 1,
    userAgent: null,
    mobile: false,
    touch: false,
    sizing: ViewportSizing.free,
  ),
  // Free sizing — the platform view fills the panel and the detached window
  // follows the live surface size (see `viewportFollowsSurface` in
  // panelCreationParams). 0x0 because there is nothing to emulate.
  DevicePreset(
    id: kCustomDevicePresetId,
    name: 'Custom',
    viewportWidth: 0,
    viewportHeight: 0,
    scaleFactor: 1,
    userAgent: null,
    mobile: false,
    touch: false,
    sizing: ViewportSizing.free,
  ),
  // Fixed window-size presets (responsive-design-mode style): pure viewport
  // sizes on the desktop UA — no UA spoofing or touch surface.
  DevicePreset(
    id: 'size-widget-320x400',
    name: 'Widget',
    viewportWidth: 320,
    viewportHeight: 400,
    scaleFactor: 1,
    userAgent: null,
    mobile: false,
    touch: false,
    sizing: ViewportSizing.fixed,
  ),
  DevicePreset(
    id: 'size-iphone-se-320x568',
    name: 'iPhone SE',
    viewportWidth: 320,
    viewportHeight: 568,
    scaleFactor: 1,
    userAgent: null,
    mobile: false,
    touch: false,
    sizing: ViewportSizing.fixed,
  ),
  DevicePreset(
    id: 'size-nexus-5-360x640',
    name: 'Google Nexus 5',
    viewportWidth: 360,
    viewportHeight: 640,
    scaleFactor: 1,
    userAgent: null,
    mobile: false,
    touch: false,
    sizing: ViewportSizing.fixed,
  ),
  DevicePreset(
    id: 'size-iphone-8-375x667',
    name: 'iPhone 8',
    viewportWidth: 375,
    viewportHeight: 667,
    scaleFactor: 1,
    userAgent: null,
    mobile: false,
    touch: false,
    sizing: ViewportSizing.fixed,
  ),
  DevicePreset(
    id: 'size-iphone-14-390x844',
    name: 'iPhone 14',
    viewportWidth: 390,
    viewportHeight: 844,
    scaleFactor: 1,
    userAgent: null,
    mobile: false,
    touch: false,
    sizing: ViewportSizing.fixed,
  ),
  DevicePreset(
    id: 'size-iphone-11-414x896',
    name: 'iPhone 11',
    viewportWidth: 414,
    viewportHeight: 896,
    scaleFactor: 1,
    userAgent: null,
    mobile: false,
    touch: false,
    sizing: ViewportSizing.fixed,
  ),
  DevicePreset(
    id: 'size-iphone-14-pro-max-430x932',
    name: 'iPhone 14 Pro Max',
    viewportWidth: 430,
    viewportHeight: 932,
    scaleFactor: 1,
    userAgent: null,
    mobile: false,
    touch: false,
    sizing: ViewportSizing.fixed,
  ),
  DevicePreset(
    id: 'size-desktop-mini-640x500',
    name: 'Desktop Mini',
    viewportWidth: 640,
    viewportHeight: 500,
    scaleFactor: 1,
    userAgent: null,
    mobile: false,
    touch: false,
    sizing: ViewportSizing.fixed,
  ),
  DevicePreset(
    id: 'size-ipad-mini-768x1024',
    name: 'iPad mini',
    viewportWidth: 768,
    viewportHeight: 1024,
    scaleFactor: 1,
    userAgent: null,
    mobile: false,
    touch: false,
    sizing: ViewportSizing.fixed,
  ),
  DevicePreset(
    id: 'size-desktop-1024x768',
    name: 'Desktop 1024',
    viewportWidth: 1024,
    viewportHeight: 768,
    scaleFactor: 1,
    userAgent: null,
    mobile: false,
    touch: false,
    sizing: ViewportSizing.fixed,
  ),
  DevicePreset(
    id: 'size-macbook-air-1280x832',
    name: 'MacBook Air',
    viewportWidth: 1280,
    viewportHeight: 832,
    scaleFactor: 1,
    userAgent: null,
    mobile: false,
    touch: false,
    sizing: ViewportSizing.fixed,
  ),
];

/// The identity-form default — matches the Tauri management sidebar
/// (`devicePresetId ?? 'desktop-1920'`). A null/unknown stored id behaves
/// exactly like this preset: no UA override, no touch surface.
const String kDefaultDevicePresetId = 'desktop-1920';

/// The "follow the window" preset: free sizing with no overrides, and the
/// detached window tracks the live panel surface size via
/// `viewportFollowsSurface` (panelCreationParams → ProfiledWebViewPlugin).
const String kCustomDevicePresetId = 'custom';

/// Well-formedness for preset ids — the same rule as the Tauri
/// `validate_device_preset` (non-empty, <=64 chars, [A-Za-z0-9_-]).
bool isValidDevicePresetId(String value) {
  if (value.isEmpty || value.length > 64) return false;
  for (final c in value.codeUnits) {
    final ok =
        (c >= 0x30 && c <= 0x39) || // 0-9
        (c >= 0x41 && c <= 0x5A) || // A-Z
        (c >= 0x61 && c <= 0x7A) || // a-z
        c == 0x2D || // -
        c == 0x5F; // _
    if (!ok) return false;
  }
  return true;
}

/// Resolve a stored preset id to a catalog entry. Returns null for null,
/// empty, malformed, or unknown-but-well-formed ids — callers treat null as
/// "desktop / no overrides" (fail toward the default, never toward a
/// guessed mobile UA).
DevicePreset? devicePresetFor(String? id) {
  if (id == null || !isValidDevicePresetId(id)) return null;
  for (final preset in devicePresets) {
    if (preset.id == id) return preset;
  }
  return null;
}

/// The preset the UI should display: unknown/missing ids fall back to the
/// desktop preset so a badge/icon always renders.
DevicePreset effectiveDevicePreset(String? id) =>
    devicePresetFor(id) ??
    devicePresets.firstWhere((p) => p.id == kDefaultDevicePresetId);
