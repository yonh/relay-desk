/// Concrete macOS WebView adapter backed by the native `ProfiledWebViewPlugin`
/// (thin WKWebsiteDataStore(forIdentifier:) adapter, ADR-0001/0002).
///
/// This is the control plane for embedded WKWebViews. The platform view itself
/// is created by the widget tree via `AppKitView`; the adapter links the
/// identityId to the native viewId once the platform view is created
/// (`registerView`), and then drives navigation, bounds, lifecycle and
/// capability probes through the `profiled_webview` MethodChannel.
///
/// Responsibilities (rewrite-plan §4.6 / §4.8):
/// - probe runtime capabilities from native.
/// - openEmbedded: record runtime config + fingerprint; the widget rebuilds the
///   AppKitView and calls registerView.
/// - updateBounds: drop stale revisions (monotonic revision per identity).
/// - navigate / browserAction / reload / openDevTools / toggleMute.
/// - embedded/detached/closed state machine driven by native event channel
///   (`profiled_webview_events`); the UI must not guess these states.
/// - fingerprint reconstruction: when the immutable runtime config changes,
///   close the old view and signal rebuild.
///
/// Remote business pages never receive a JavaScript/Method Channel handle.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/platform/domain.dart';
import '../../core/platform/webview_adapter.dart';

/// The native method/event channel names. Kept in sync with
/// ProfiledWebViewPlugin.swift.
const _methodChannelName = 'profiled_webview';
const _eventChannelName = 'profiled_webview_events';

/// Concrete WebviewAdapter for macOS 14+ using the in-repo thin native adapter.
class MacosProfiledWebviewAdapter implements WebviewAdapter {
  MacosProfiledWebviewAdapter({Duration? snapshotTimeout})
    : _snapshotTimeout = snapshotTimeout ?? const Duration(seconds: 9),
      _channel = const MethodChannel(_methodChannelName),
      _eventChannel = const EventChannel(_eventChannelName) {
    _startEventListener();
    _channel.setMethodCallHandler(_handleNativeMethodCall);
  }

  final MethodChannel _channel;
  // App-layer bound for one snapshot request: the native side answers inside
  // 8 s, so a wedged callback still lets this Future complete instead of
  // holding the caller's per-target busy marker forever.
  final Duration _snapshotTimeout;
  final EventChannel _eventChannel;
  StreamSubscription<dynamic>? _eventSub;

  // identityId -> native viewId (set when the platform view is created).
  final Map<String, int> _viewIdByIdentity = {};
  // identityId -> close epoch. openEmbedded/registerView bump it so the async
  // tail of a stale close() cannot drop a re-registered view's mapping or
  // report "closed" for a panel that has already reopened.
  final Map<String, int> _closeEpochByIdentity = {};

  /// Bumps the identity's close epoch and returns it. An in-flight `close`'s
  /// async tail consults its captured epoch to detect that a newer view was
  /// registered in the meantime (stale close must not unmap the new view).
  int _bumpCloseEpoch(String identityId) {
    final epoch = (_closeEpochByIdentity[identityId] ?? 0) + 1;
    _closeEpochByIdentity[identityId] = epoch;
    return epoch;
  }

  // identityId -> last applied revision (monotonic; stale revisions dropped).
  final Map<String, int> _lastRevisionByIdentity = {};
  // identityId -> runtime config fingerprint (immutable parts).
  final Map<String, String> _fingerprintByIdentity = {};
  // identityId -> current state machine state.
  final Map<String, WebviewState> _stateByIdentity = {};
  // identityId -> latest navigation info (canGoBack/Forward/url).
  final Map<String, WebviewNavInfo> _navInfoByIdentity = {};

  final _events = StreamController<WebviewEvent>.broadcast();

  // Breadcrumbs appended to the native diagnostics log so one timeline covers
  // both sides of the channel. Failures stop retrying — a dead channel must
  // not get hammered by the logger itself.
  int _logFailures = 0;

  @override
  Stream<WebviewEvent> get events => _events.stream;

  void _log(String event, [Map<String, Object?> fields = const {}]) {
    if (!Platform.isMacOS || _logFailures >= 3) return;
    unawaited(
      _channel
          .invokeMethod<void>('appendLog', {'event': event, ...fields})
          .catchError((_) => _logFailures++),
    );
  }

  /// Absolute path of the native diagnostics log file, or null when the log
  /// could not be opened / the platform has no diagnostics channel.
  Future<String?> diagnosticsLogPath() async {
    if (!Platform.isMacOS) return null;
    try {
      return await _channel.invokeMethod<String>('logPath');
    } on PlatformException {
      return null;
    }
  }

  /// Current viewId for an identity (null if not embedded).
  int? viewIdFor(String identityId) => _viewIdByIdentity[identityId];

  /// Current state for an identity (defaults to closed).
  WebviewState stateFor(String identityId) =>
      _stateByIdentity[identityId] ?? WebviewState.closed;

  /// Latest navigation info (canGoBack/Forward/currentUrl) for an identity.
  WebviewNavInfo navInfoFor(String identityId) =>
      _navInfoByIdentity[identityId] ?? const WebviewNavInfo();

  /// Methods invoked FROM the native side. `webviewPointerDown` fires when a
  /// click lands on an embedded WKWebView while a foreign responder owns the
  /// window's keyboard focus — typically Flutter's hidden text-input plugin
  /// while a Dart TextField is focused, which would otherwise receive the
  /// Cmd+C/V/X/A menu actions meant for the page. Dropping widget focus here
  /// lets the native side claim first responder for the webview.
  Future<Object?> _handleNativeMethodCall(MethodCall call) async {
    if (call.method == 'webviewPointerDown') {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    return null;
  }

  void _startEventListener() {
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        // StandardMessageCodec decodes dictionaries as Map<Object?,
        // Object?> on some Flutter engine versions. Do not cast the
        // entire map to Map<String, dynamic>, or navigation events are
        // silently delivered to the stream error handler and discarded.
        if (event is! Map) return;
        _handleNativeEvent(
          event.map((key, value) => MapEntry(key.toString(), value)),
        );
      },
      onError: (e) {
        // Event channel errors are non-fatal; the adapter keeps operating.
      },
    );
  }

  void _handleNativeEvent(Map<String, dynamic> payload) {
    final identityId = payload['identityId'] as String? ?? '';
    if (identityId.isEmpty) return;
    final type = payload['event'] as String?;
    _log('nativeEvent', {
      'type': type,
      'identityId': identityId,
      'url': payload['url'],
      'state': payload['state'],
      'error': payload['error'],
      'code': payload['code'],
      'isLoading': payload['isLoading'],
    });
    switch (type) {
      case 'loadStarted':
        _navInfoByIdentity[identityId] = WebviewNavInfo(
          url: payload['url'] as String? ?? '',
          loading: true,
        );
        _events.add(
          WebviewLoadStarted(
            identityId,
            Uri.parse(payload['url'] as String? ?? 'about:blank'),
          ),
        );
        break;
      case 'stateChanged':
        final raw = payload['state'] as String? ?? '';
        final state = _parseState(raw);
        if (state == WebviewState.closed) {
          // 'closed' carries the viewId that was torn down (close(), or the
          // user closing a detached window). If a newer view has already been
          // registered for this identity, the event is stale — drop it so it
          // cannot strip the live view's mapping or corrupt its state.
          final closedViewId = payload['viewId'] as int?;
          final currentViewId = _viewIdByIdentity[identityId];
          if (closedViewId != null &&
              currentViewId != null &&
              closedViewId != currentViewId) {
            _log('staleClosedIgnored', {
              'identityId': identityId,
              'closedViewId': closedViewId,
              'currentViewId': currentViewId,
            });
            return;
          }
          // Drop the viewId/nav bookkeeping so a later navigate/reload can
          // never target a dead view and spin forever.
          _viewIdByIdentity.remove(identityId);
          _navInfoByIdentity.remove(identityId);
          _lastRevisionByIdentity.remove(identityId);
        }
        _stateByIdentity[identityId] = state;
        _events.add(WebviewStateChanged(identityId, state));
        break;
      case 'loadComplete':
        final nav = WebviewNavInfo(
          url: payload['url'] as String? ?? '',
          canGoBack: payload['canGoBack'] as bool? ?? false,
          canGoForward: payload['canGoForward'] as bool? ?? false,
          loading: false,
        );
        _navInfoByIdentity[identityId] = nav;
        _events.add(
          WebviewLoadComplete(
            identityId,
            Uri.parse(nav.url.isEmpty ? 'about:blank' : nav.url),
            canGoBack: nav.canGoBack,
            canGoForward: nav.canGoForward,
          ),
        );
        break;
      case 'urlChanged':
        final rawUrl = payload['url'] as String? ?? '';
        if (rawUrl.isEmpty) return;
        final previous = _navInfoByIdentity[identityId];
        final nextCanGoBack =
            payload['canGoBack'] as bool? ?? previous?.canGoBack ?? false;
        final nextCanGoForward =
            payload['canGoForward'] as bool? ?? previous?.canGoForward ?? false;
        _navInfoByIdentity[identityId] = WebviewNavInfo(
          url: rawUrl,
          canGoBack: nextCanGoBack,
          canGoForward: nextCanGoForward,
          loading: previous?.loading ?? false,
        );
        _events.add(
          WebviewUrlChanged(
            identityId,
            Uri.parse(rawUrl),
            canGoBack: nextCanGoBack,
            canGoForward: nextCanGoForward,
          ),
        );
        break;
      case 'loadFailed':
        _navInfoByIdentity[identityId] = const WebviewNavInfo(loading: false);
        _events.add(
          WebviewNavigationBlocked(
            identityId,
            Uri.parse(payload['url'] as String? ?? 'about:blank'),
            payload['error'] as String? ?? 'load failed',
          ),
        );
        break;
      case 'measureModeChanged':
        _events.add(
          WebviewMeasureModeChanged(
            identityId,
            payload['enabled'] as bool? ?? false,
          ),
        );
        break;
    }
  }

  WebviewState _parseState(String raw) => switch (raw) {
    'openingEmbedded' => WebviewState.openingEmbedded,
    'embedded' => WebviewState.embedded,
    'detaching' => WebviewState.detaching,
    'detached' => WebviewState.detached,
    'attaching' => WebviewState.attaching,
    'closing' => WebviewState.closing,
    'failed' => WebviewState.failed,
    _ => WebviewState.closed,
  };

  @override
  Future<RuntimeCapabilities> probe() async {
    if (!Platform.isMacOS) {
      return const RuntimeCapabilities();
    }
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('probe');
      return RuntimeCapabilities(
        devtools: res?['devtools'] as bool? ?? false,
        nativeProfiles: res?['nativeProfiles'] as bool? ?? false,
        customUserAgent: res?['customUserAgent'] as bool? ?? false,
        deviceMetricsOverride: res?['deviceMetricsOverride'] as bool? ?? false,
        touchEmulation: res?['touchEmulation'] as bool? ?? false,
        networkThrottling: res?['networkThrottling'] as bool? ?? false,
        clearProfileData: res?['clearProfileData'] as bool? ?? false,
      );
    } on PlatformException {
      return const RuntimeCapabilities();
    }
  }

  @override
  Future<void> openEmbedded(
    PanelRuntimeConfig config,
    NativeBounds bounds,
  ) async {
    // The platform view is created by the widget tree (AppKitView). We record
    // the immutable fingerprint and mark the state machine; registerView links
    // the native viewId once the platform view is live.
    final previous = _fingerprintByIdentity[config.identityId];
    _fingerprintByIdentity[config.identityId] = config.fingerprint;
    _bumpCloseEpoch(config.identityId);
    _log('openEmbedded', {
      'identityId': config.identityId,
      'fingerprint': config.fingerprint,
      'previousFingerprint': previous,
      'url': config.url,
      'isolationMode': config.isolationMode.dbValue,
    });
    _stateByIdentity[config.identityId] = WebviewState.openingEmbedded;
    _events.add(
      WebviewStateChanged(config.identityId, WebviewState.openingEmbedded),
    );
    // If the fingerprint changed while a view exists, the widget layer will
    // rebuild the AppKitView (signaled by fingerprintFor). The native side
    // reuses the existing WKWebView only for detach->attach reattach, not for
    // fingerprint changes, so a stale viewId will be replaced on rebuild.
    if (previous != null && previous != config.fingerprint) {
      await close(config.identityId);
    }
  }

  /// Links the native viewId to an identity once the platform view is created.
  /// Called from the widget's `onPlatformViewCreated` callback.
  void registerView(String identityId, int viewId) {
    _bumpCloseEpoch(identityId);
    _log('registerView', {'identityId': identityId, 'viewId': viewId});
    _viewIdByIdentity[identityId] = viewId;
    _stateByIdentity[identityId] = WebviewState.embedded;
    _events.add(WebviewStateChanged(identityId, WebviewState.embedded));
  }

  /// The immutable fingerprint for an identity (null if never opened).
  String? fingerprintFor(String identityId) =>
      _fingerprintByIdentity[identityId];

  @override
  Future<void> updateBounds(
    String identityId,
    int revision,
    NativeBounds bounds,
  ) async {
    // Monotonic revision: drop stale bounds (rewrite-plan §4.8).
    final last = _lastRevisionByIdentity[identityId] ?? 0;
    if (revision < last) return;
    _lastRevisionByIdentity[identityId] = revision;
    final viewId = _viewIdByIdentity[identityId];
    if (viewId == null) return;
    try {
      await _channel.invokeMethod('setBounds', {
        'viewId': viewId,
        'x': bounds.x,
        'y': bounds.y,
        'width': bounds.width,
        'height': bounds.height,
      });
    } on PlatformException {
      // View may have been closed concurrently; ignore.
    }
  }

  @override
  Future<void> navigate(String identityId, Uri uri) async {
    final viewId = _viewIdByIdentity[identityId];
    if (viewId == null) {
      // View not registered yet — emit a blocked event so the controller
      // resets its loading flag instead of spinning forever.
      _log('navigateNoView', {'identityId': identityId, 'url': uri.toString()});
      _events.add(
        WebviewNavigationBlocked(identityId, uri, 'view not registered'),
      );
      return;
    }
    _navInfoByIdentity[identityId] = const WebviewNavInfo(loading: true);
    _log('navigate', {
      'identityId': identityId,
      'viewId': viewId,
      'url': uri.toString(),
    });
    try {
      await _channel.invokeMethod('loadUrl', {
        'viewId': viewId,
        'url': uri.toString(),
      });
    } on PlatformException catch (e) {
      _navInfoByIdentity[identityId] = const WebviewNavInfo(loading: false);
      _log('navigateFailed', {
        'identityId': identityId,
        'viewId': viewId,
        'url': uri.toString(),
        'error': e.message ?? e.code,
      });
      // The channel call itself failed (typically a stale viewId pointing at
      // a torn-down native view). Unlatch the spinner — no delegate callback
      // can arrive for a load that never reached the webview.
      _events.add(
        WebviewNavigationBlocked(
          identityId,
          uri,
          e.message ?? 'loadUrl failed',
        ),
      );
    }
  }

  @override
  Future<void> browserAction(String identityId, BrowserAction action) async {
    final viewId = _viewIdByIdentity[identityId];
    if (viewId == null) {
      _log('browserActionNoView', {
        'identityId': identityId,
        'action': action.name,
      });
      return;
    }
    final method = switch (action) {
      BrowserAction.back => 'goBack',
      BrowserAction.forward => 'goForward',
      BrowserAction.stop => 'stopLoading',
    };
    _log('browserAction', {
      'identityId': identityId,
      'viewId': viewId,
      'action': action.name,
    });
    try {
      await _channel.invokeMethod(method, {'viewId': viewId});
    } on PlatformException catch (e) {
      _log('browserActionFailed', {
        'identityId': identityId,
        'viewId': viewId,
        'action': action.name,
        'error': e.message ?? e.code,
      });
    }
  }

  @override
  Future<void> reload(String identityId) async {
    final viewId = _viewIdByIdentity[identityId];
    if (viewId == null) {
      _log('reloadNoView', {'identityId': identityId});
      _events.add(
        WebviewNavigationBlocked(
          identityId,
          Uri.parse(_navInfoByIdentity[identityId]?.url ?? 'about:blank'),
          'view not registered',
        ),
      );
      return;
    }
    _navInfoByIdentity[identityId] = const WebviewNavInfo(loading: true);
    _log('reload', {'identityId': identityId, 'viewId': viewId});
    try {
      await _channel.invokeMethod('reload', {'viewId': viewId});
    } on PlatformException catch (e) {
      _navInfoByIdentity[identityId] = const WebviewNavInfo(loading: false);
      _log('reloadFailed', {
        'identityId': identityId,
        'viewId': viewId,
        'error': e.message ?? e.code,
      });
      _events.add(
        WebviewNavigationBlocked(
          identityId,
          Uri.parse(_navInfoByIdentity[identityId]?.url ?? 'about:blank'),
          e.message ?? 'reload failed',
        ),
      );
    }
  }

  @override
  Future<DevToolsReport> openDevTools(String identityId) async {
    final viewId = _viewIdByIdentity[identityId];
    if (viewId == null) return const DevToolsReport();
    try {
      // The native side reports inspector availability; WKWebView has no
      // programmatic Chromium-style DevTools window — the user opens Safari
      // Web Inspector via right-click → Inspect Element (DEBUG builds).
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'openDevTools',
        {'viewId': viewId},
      );
      return DevToolsReport(
        opened: res?['opened'] as bool? ?? false,
        available: res?['available'] as bool? ?? false,
        howToOpen: res?['howToOpen'] as String?,
      );
    } on PlatformException {
      // The native view may be closing concurrently.
      return const DevToolsReport();
    }
  }

  @override
  Future<bool> toggleMute(String identityId) async {
    final viewId = _viewIdByIdentity[identityId];
    if (viewId == null) return false;
    try {
      return await _channel.invokeMethod<bool>('toggleMute', {
            'viewId': viewId,
          }) ??
          false;
    } on PlatformException {
      // The native view may be closing concurrently.
      return false;
    }
  }

  @override
  Future<bool> setMeasureMode(
    String identityId,
    bool enabled, {
    bool inPageRulers = false,
  }) async {
    final viewId = _viewIdByIdentity[identityId];
    if (viewId == null) return false;
    try {
      return await _channel.invokeMethod<bool>('setMeasureMode', {
            'viewId': viewId,
            'enabled': enabled,
            'inPageRulers': inPageRulers,
          }) ??
          false;
    } on PlatformException {
      // The native view may be closing concurrently.
      return false;
    }
  }

  @override
  Future<void> toggleFullscreen(String identityId) async {
    try {
      await _channel.invokeMethod('toggleInAppFullscreen', {
        'identityId': identityId,
      });
    } on PlatformException {
      // The native view may be closing concurrently.
    }
  }

  @override
  Future<void> detach(String identityId) async {
    final viewId = _viewIdByIdentity[identityId];
    if (viewId == null) return;
    _stateByIdentity[identityId] = WebviewState.detaching;
    _events.add(WebviewStateChanged(identityId, WebviewState.detaching));
    _log('detach', {'identityId': identityId, 'viewId': viewId});
    try {
      await _channel.invokeMethod('detach', {'identityId': identityId});
    } on PlatformException {
      _stateByIdentity[identityId] = WebviewState.failed;
      _events.add(WebviewStateChanged(identityId, WebviewState.failed));
    }
  }

  @override
  Future<void> attach(String identityId, NativeBounds bounds) async {
    _stateByIdentity[identityId] = WebviewState.attaching;
    _events.add(WebviewStateChanged(identityId, WebviewState.attaching));
    _log('attach', {'identityId': identityId});
    try {
      await _channel.invokeMethod('attach', {'identityId': identityId});
    } on PlatformException {
      _stateByIdentity[identityId] = WebviewState.failed;
      _events.add(WebviewStateChanged(identityId, WebviewState.failed));
    }
    // The widget layer rebuilds the AppKitView; registerView re-links the
    // viewId and the native side reclaims the existing WKWebView.
  }

  @override
  Future<void> close(String identityId) async {
    final epoch = _bumpCloseEpoch(identityId);
    final viewId = _viewIdByIdentity[identityId];
    _log('close', {'identityId': identityId, 'viewId': viewId});
    _stateByIdentity[identityId] = WebviewState.closing;
    _events.add(WebviewStateChanged(identityId, WebviewState.closing));
    try {
      final args = <String, dynamic>{'identityId': identityId};
      if (viewId != null) args['viewId'] = viewId;
      await _channel.invokeMethod('close', args);
    } on PlatformException {
      // ignore
    }
    // Stale-close guard: a reopen (openEmbedded/registerView) or a newer
    // close superseded this one while the platform call was in flight.
    // Dropping the maps here would orphan the newer view's viewId and the
    // "closed" event would corrupt the reopened panel's state.
    if (_closeEpochByIdentity[identityId] != epoch) return;
    _viewIdByIdentity.remove(identityId);
    _navInfoByIdentity.remove(identityId);
    _lastRevisionByIdentity.remove(identityId);
    _stateByIdentity[identityId] = WebviewState.closed;
    _events.add(WebviewStateChanged(identityId, WebviewState.closed));
  }

  /// Clear all stored data for one identity only (delegates to native
  /// `WKWebsiteDataStore.removeData` on that identity's store).
  Future<void> clearIdentityData(String identityId) async {
    try {
      await _channel.invokeMethod('clearIdentityData', {
        'identityId': identityId,
      });
    } on PlatformException {
      // ignore
    }
  }

  /// Read the cookie string for an identity's current view (used by isolation
  /// evidence harness; not exposed to remote pages).
  Future<String> getCookieString(String identityId) async {
    final viewId = _viewIdByIdentity[identityId];
    if (viewId == null) return '';
    try {
      final res = await _channel.invokeMethod<String>('getCookieString', {
        'viewId': viewId,
      });
      return res ?? '';
    } on PlatformException {
      return '';
    }
  }

  /// Which store kind the identity's live view uses: "shared" (default
  /// WKWebsiteDataStore), "perIdentity" (WKWebsiteDataStore(forIdentifier:)),
  /// or "none" (no live view). Evidence harness only.
  Future<String> storeKindFor(String identityId) async {
    try {
      return await _channel.invokeMethod<String>('storeKind', {
            'identityId': identityId,
          }) ??
          'none';
    } on PlatformException {
      return 'none';
    }
  }

  /// Write a cookie into the identity's live data store (evidence harness).
  /// Pass [expires] for a persistent cookie — session cookies never reach
  /// disk and cannot verify cold-restart persistence.
  Future<bool> setCookie(
    String identityId,
    String name,
    String value, {
    String domain = '127.0.0.1',
    DateTime? expires,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('setCookie', {
            'identityId': identityId,
            'name': name,
            'value': value,
            'domain': domain,
            if (expires != null)
              'expiresSeconds': expires.millisecondsSinceEpoch / 1000.0,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// Remove a cookie from the identity's live data store (evidence harness;
  /// used to clean up shared-store markers left by tests).
  Future<int> deleteCookie(
    String identityId,
    String name, {
    String domain = '127.0.0.1',
  }) async {
    try {
      return await _channel.invokeMethod<int>('deleteCookie', {
            'identityId': identityId,
            'name': name,
            'domain': domain,
          }) ??
          0;
    } on PlatformException {
      return 0;
    }
  }

  /// Evaluate JS in the identity's live view (evidence harness; the business
  /// page itself never receives a channel — this is the control plane).
  Future<String> evaluateJs(String identityId, String js) async {
    final viewId = _viewIdByIdentity[identityId];
    if (viewId == null) return '';
    try {
      final res = await _channel.invokeMethod<dynamic>('evaluateJs', {
        'viewId': viewId,
        'js': js,
      });
      return res?.toString() ?? '';
    } on PlatformException {
      return '';
    }
  }

  /// One-shot AppKit window/view inventory for the read-only automation
  /// transport. The native side samples NSApp.windows plus the plugin's own
  /// view maps. Errors propagate: a failed or malformed sample surfaces as a
  /// command failure, never as a fabricated empty inventory.
  Future<Map<String, dynamic>> windowInventory() async {
    final raw = await _channel.invokeMethod<dynamic>('windowInventory');
    if (raw is! Map) {
      throw PlatformException(code: 'window_inventory_failed');
    }
    return _jsonCompatible(raw) as Map<String, dynamic>;
  }

  /// Read-only viewport snapshot of the web view bound to [viewId].
  ///
  /// The native side binds the request to [expectedIdentityId] and re-verifies
  /// the view instance, identity mapping, window and navigation generation
  /// when the async capture completes; any drift surfaces as a
  /// `target_changed` [PlatformException]. The returned map carries `png`
  /// (Uint8List), `width`, `height`, `url` and `windowId`.
  Future<Map<String, dynamic>> takeSnapshot(
    int viewId,
    String expectedIdentityId,
  ) async {
    final pending = _channel.invokeMethod<dynamic>('takeSnapshot', {
      'viewId': viewId,
      'expectedIdentityId': expectedIdentityId,
    });
    final raw = await pending.timeout(
      _snapshotTimeout,
      onTimeout: () {
        // The channel call may still resolve after the deadline (a wedged
        // WebKit callback): stop listening so its late result — success or
        // error — is discarded instead of completing twice or surfacing as
        // an unhandled zone error.
        pending.ignore();
        throw PlatformException(
          code: 'snapshot_timeout',
          message: 'Native snapshot did not complete within the deadline',
        );
      },
    );
    if (raw is! Map) {
      throw PlatformException(code: 'snapshot_failed');
    }
    return _jsonCompatible(raw) as Map<String, dynamic>;
  }

  /// Read-only media-state sample of the page in the web view bound to
  /// [viewId].
  ///
  /// Same native binding discipline as [takeSnapshot]: the target is
  /// re-verified against [expectedIdentityId], the live view instance, window
  /// and navigation generations when the fixed probe script finishes; drift
  /// surfaces as `target_changed`. The returned map carries `json` (the fixed
  /// probe's JSON string — decoded by the query layer), `url` and `windowId`.
  /// Shares [_snapshotTimeout]: it is the generic deadline for bounded native
  /// reads, matching the native-side deadline.
  Future<Map<String, dynamic>> sampleMedia(
    int viewId,
    String expectedIdentityId,
  ) async {
    final pending = _channel.invokeMethod<dynamic>('sampleMedia', {
      'viewId': viewId,
      'expectedIdentityId': expectedIdentityId,
    });
    final raw = await pending.timeout(
      _snapshotTimeout,
      onTimeout: () {
        pending.ignore();
        throw PlatformException(
          code: 'media_timeout',
          message: 'Native media probe did not complete within the deadline',
        );
      },
    );
    if (raw is! Map) {
      throw PlatformException(code: 'media_failed');
    }
    return _jsonCompatible(raw) as Map<String, dynamic>;
  }

  /// Read-only drain of the in-page JS error buffer of the view bound to
  /// [viewId] (issue #17). Same binding and deadline discipline as
  /// [sampleMedia]; the buffer only exists on pages created with the
  /// automation error-capture flag — `installed:false` frames tell that
  /// apart from a genuinely empty buffer.
  Future<Map<String, dynamic>> drainJsErrors(
    int viewId,
    String expectedIdentityId,
  ) async {
    final pending = _channel.invokeMethod<dynamic>('drainJsErrors', {
      'viewId': viewId,
      'expectedIdentityId': expectedIdentityId,
    });
    final raw = await pending.timeout(
      _snapshotTimeout,
      onTimeout: () {
        pending.ignore();
        throw PlatformException(
          code: 'errors_timeout',
          message: 'Native error drain did not complete within the deadline',
        );
      },
    );
    if (raw is! Map) {
      throw PlatformException(code: 'errors_failed');
    }
    return _jsonCompatible(raw) as Map<String, dynamic>;
  }

  /// Read-only DOM summary of the view bound to [viewId] (issue #20). Same
  /// binding and deadline discipline as [sampleMedia]; only the fixed probe
  /// runs natively — the caller cannot inject script.
  Future<Map<String, dynamic>> probeDom(
    int viewId,
    String expectedIdentityId,
  ) async {
    final pending = _channel.invokeMethod<dynamic>('probeDom', {
      'viewId': viewId,
      'expectedIdentityId': expectedIdentityId,
    });
    final raw = await pending.timeout(
      _snapshotTimeout,
      onTimeout: () {
        pending.ignore();
        throw PlatformException(
          code: 'dom_timeout',
          message: 'Native DOM probe did not complete within the deadline',
        );
      },
    );
    if (raw is! Map) {
      throw PlatformException(code: 'dom_failed');
    }
    return _jsonCompatible(raw) as Map<String, dynamic>;
  }

  /// StandardMessageCodec decodes native dictionaries as
  /// `Map<Object?, Object?>` on some engine versions. Normalize recursively
  /// so the query layer and jsonEncode only see `Map<String, dynamic>` and
  /// `List<dynamic>`.
  static Object? _jsonCompatible(Object? value) => switch (value) {
    Map map => {
      for (final entry in map.entries)
        entry.key.toString(): _jsonCompatible(entry.value),
    },
    // A typed-data payload (e.g. snapshot PNG bytes) is a List but must not
    // be walked element-by-element into a List<Object?>.
    Uint8List bytes => bytes,
    List list => [for (final item in list) _jsonCompatible(item)],
    _ => value,
  };

  /// App RSS / webview / datastore counts for resource evidence.
  Future<Map<String, dynamic>> getProcessInfo() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'getProcessInfo',
      );
      return res ?? {};
    } on PlatformException {
      return {};
    }
  }

  /// Dispose the event subscription. The adapter is a singleton in practice,
  /// but this keeps tests and lifecycle clean.
  void dispose() {
    _eventSub?.cancel();
    _eventSub = null;
    _events.close();
  }
}

/// Immutable navigation info snapshot for a panel.
class WebviewNavInfo {
  final String url;
  final bool canGoBack;
  final bool canGoForward;
  final bool loading;
  const WebviewNavInfo({
    this.url = '',
    this.canGoBack = false,
    this.canGoForward = false,
    this.loading = false,
  });
}
