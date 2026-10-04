/// Platform adapter contracts per docs/rewrite-plan-comparison.md §4.6.
/// Remote business pages must NOT receive JavaScript/Method Channel access.
library;

import 'domain.dart';

/// Native bounds in platform coordinates.
class NativeBounds {
  final double x;
  final double y;
  final double width;
  final double height;
  const NativeBounds(this.x, this.y, this.width, this.height);
}

/// Configuration for opening an embedded WebView panel.
class PanelRuntimeConfig {
  final String identityId;
  final String url;
  final IsolationMode isolationMode;
  final String? userAgent;
  final String? devicePresetId;

  const PanelRuntimeConfig({
    required this.identityId,
    required this.url,
    required this.isolationMode,
    this.userAgent,
    this.devicePresetId,
  });

  /// A fingerprint of immutable runtime config. If this changes, the WebView
  /// must be destroyed and recreated (rewrite-plan §4.8).
  String get fingerprint =>
      '$identityId|$url|$isolationMode|$userAgent|$devicePresetId';
}

/// Browser actions for navigation control.
enum BrowserAction { back, forward, stop }

/// WebView lifecycle states (rewrite-plan §4.8 state machine).
enum WebviewState {
  closed,
  openingEmbedded,
  embedded,
  detaching,
  detached,
  attaching,
  closing,
  failed,
}

/// Events emitted by the platform adapter.
sealed class WebviewEvent {
  final String identityId;
  WebviewEvent(this.identityId);
}

class WebviewStateChanged extends WebviewEvent {
  final WebviewState state;
  WebviewStateChanged(super.identityId, this.state);
}

class WebviewLoadComplete extends WebviewEvent {
  final Uri uri;
  final bool canGoBack;
  final bool canGoForward;
  WebviewLoadComplete(
    super.identityId,
    this.uri, {
    this.canGoBack = false,
    this.canGoForward = false,
  });
}

class WebviewLoadStarted extends WebviewEvent {
  final Uri uri;
  WebviewLoadStarted(super.identityId, this.uri);
}

/// The browser URL changed without a full document load, for example through
/// a single-page application's History API. Keep the address bar current
/// without changing the panel's loading state.
class WebviewUrlChanged extends WebviewEvent {
  final Uri uri;
  final bool canGoBack;
  final bool canGoForward;
  WebviewUrlChanged(
    super.identityId,
    this.uri, {
    this.canGoBack = false,
    this.canGoForward = false,
  });
}

class WebviewNavigationBlocked extends WebviewEvent {
  final Uri uri;
  final String reason;
  WebviewNavigationBlocked(super.identityId, this.uri, this.reason);
}

/// Abstract WebView adapter. Platform implementations provide the actual
/// WKWebView/WebView2 embedding. Remote pages cannot call any method here.
abstract interface class WebviewAdapter {
  Future<RuntimeCapabilities> probe();
  Future<void> openEmbedded(PanelRuntimeConfig config, NativeBounds bounds);
  Future<void> updateBounds(
    String identityId,
    int revision,
    NativeBounds bounds,
  );
  Future<void> detach(String identityId);
  Future<void> attach(String identityId, NativeBounds bounds);
  Future<void> close(String identityId);
  Future<void> navigate(String identityId, Uri uri);
  Future<void> browserAction(String identityId, BrowserAction action);
  Future<void> reload(String identityId);

  /// Opens DevTools / Web Inspector for the identity's WebView where the
  /// platform supports it. On WKWebView the inspector is gated by
  /// `developerExtrasEnabled` (enabled in DEBUG builds) and surfaced to the
  /// user via right-click → Inspect Element; the native side reports
  /// `available`/`howToOpen` rather than pretending a programmatic
  /// Chromium-style window exists.
  Future<DevToolsReport> openDevTools(String identityId);

  /// Toggles media mute state and returns whether media is now muted.
  Future<bool> toggleMute(String identityId);
  Future<void> toggleFullscreen(String identityId);
  Stream<WebviewEvent> get events;
}
