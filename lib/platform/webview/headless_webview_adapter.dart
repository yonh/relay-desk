/// Headless WebviewAdapter used in `flutter test` (no native plugin is
/// available) and as a non-macOS fallback. It implements the full
/// WebviewAdapter contract in pure Dart so widget/controller logic can be
/// tested without a real WKWebView, and so the UI degrades gracefully on
/// platforms that are NOT_TESTED.
///
/// This is NOT used on macOS in production — the real
/// `MacosProfiledWebviewAdapter` is. It never claims isolation capabilities it
/// does not have.
library;

import 'dart:async';

import '../../core/platform/domain.dart';
import '../../core/platform/webview_adapter.dart';

class HeadlessWebviewAdapter implements WebviewAdapter {
  HeadlessWebviewAdapter({RuntimeCapabilities? capabilities})
    : _capabilities = capabilities ?? const RuntimeCapabilities();

  final RuntimeCapabilities _capabilities;
  final _events = StreamController<WebviewEvent>.broadcast();

  final Map<String, int> _viewIdByIdentity = {};
  final Map<String, int> _lastRevisionByIdentity = {};
  final Map<String, String> _fingerprintByIdentity = {};
  final Map<String, WebviewState> _stateByIdentity = {};
  final Map<String, _HeadlessNav> _navByIdentity = {};
  final Map<String, Uri> _urlByIdentity = {};
  final Map<String, bool> _mutedByIdentity = {};
  final Map<String, bool> _measureModeByIdentity = {};
  final List<String> methodLog = [];
  int _nextViewId = 1;

  @override
  Stream<WebviewEvent> get events => _events.stream;

  int? viewIdFor(String identityId) => _viewIdByIdentity[identityId];
  WebviewState stateFor(String identityId) =>
      _stateByIdentity[identityId] ?? WebviewState.closed;
  String? fingerprintFor(String identityId) =>
      _fingerprintByIdentity[identityId];
  Uri? urlFor(String identityId) => _urlByIdentity[identityId];

  void _log(String m) {
    methodLog.add(m);
  }

  void _setState(String identityId, WebviewState s) {
    _stateByIdentity[identityId] = s;
    _events.add(WebviewStateChanged(identityId, s));
  }

  @override
  Future<RuntimeCapabilities> probe() async => _capabilities;

  @override
  Future<void> openEmbedded(
    PanelRuntimeConfig config,
    NativeBounds bounds,
  ) async {
    _log('openEmbedded(${config.identityId},${config.fingerprint})');
    _fingerprintByIdentity[config.identityId] = config.fingerprint;
    _urlByIdentity[config.identityId] = Uri.parse(config.url);
    _setState(config.identityId, WebviewState.openingEmbedded);
  }

  void registerView(String identityId, int viewId) {
    _viewIdByIdentity[identityId] = viewId;
    _setState(identityId, WebviewState.embedded);
    _navByIdentity[identityId] = _HeadlessNav(
      url: _urlByIdentity[identityId]?.toString() ?? '',
    );
  }

  @override
  Future<void> updateBounds(
    String identityId,
    int revision,
    NativeBounds bounds,
  ) async {
    final last = _lastRevisionByIdentity[identityId] ?? 0;
    if (revision < last) {
      _log('updateBounds($identityId,$revision) DROPPED stale (<$last)');
      return;
    }
    _lastRevisionByIdentity[identityId] = revision;
    _log(
      'updateBounds($identityId,$revision,${bounds.x},${bounds.y},${bounds.width},${bounds.height})',
    );
  }

  @override
  Future<void> navigate(String identityId, Uri uri) async {
    _log('navigate($identityId,$uri)');
    _urlByIdentity[identityId] = uri;
    _navByIdentity[identityId] = _HeadlessNav(
      url: uri.toString(),
      loading: false,
    );
    _events.add(WebviewLoadComplete(identityId, uri));
  }

  @override
  Future<void> browserAction(String identityId, BrowserAction action) async {
    _log('browserAction($identityId,$action)');
  }

  @override
  Future<void> reload(String identityId) async {
    _log('reload($identityId)');
  }

  @override
  Future<DevToolsReport> openDevTools(String identityId) async {
    _log('openDevTools($identityId)');
    return const DevToolsReport();
  }

  @override
  Future<bool> toggleMute(String identityId) async {
    _log('toggleMute($identityId)');
    final muted = !(_mutedByIdentity[identityId] ?? false);
    _mutedByIdentity[identityId] = muted;
    return muted;
  }

  @override
  Future<bool> setMeasureMode(
    String identityId,
    bool enabled, {
    bool inPageRulers = false,
  }) async {
    _log('setMeasureMode($identityId,$enabled,rulers:$inPageRulers)');
    _measureModeByIdentity[identityId] = enabled;
    _events.add(WebviewMeasureModeChanged(identityId, enabled));
    return enabled;
  }

  /// Test/sim helper: the overlay's own exit path (Escape key) reports
  /// `enabled: false` through the same event as a programmatic disable.
  void simulateMeasureModeExit(String identityId) {
    _measureModeByIdentity[identityId] = false;
    _events.add(WebviewMeasureModeChanged(identityId, false));
  }

  @override
  Future<void> toggleFullscreen(String identityId) async {
    _log('toggleFullscreen($identityId)');
  }

  @override
  Future<void> detach(String identityId) async {
    _log('detach($identityId)');
    _setState(identityId, WebviewState.detaching);
    _setState(identityId, WebviewState.detached);
  }

  @override
  Future<void> attach(String identityId, NativeBounds bounds) async {
    _log('attach($identityId)');
    _setState(identityId, WebviewState.attaching);
    _setState(identityId, WebviewState.embedded);
  }

  @override
  Future<void> close(String identityId) async {
    _log('close($identityId)');
    _viewIdByIdentity.remove(identityId);
    _navByIdentity.remove(identityId);
    _setState(identityId, WebviewState.closing);
    _setState(identityId, WebviewState.closed);
  }

  int allocateViewId() => _nextViewId++;

  /// Test/sim helper: emit a native-initiated `closed` writeback with no
  /// preceding `closing` — what the native side sends when the user closes a
  /// detached window (the teardown happens natively, Dart only learns of the
  /// resulting state).
  void simulateClosed(String identityId) {
    _setState(identityId, WebviewState.closed);
  }

  /// Test/sim helper: emit a load-complete carrying explicit history flags so
  /// controller sync of canGoBack/canGoForward can be verified without a
  /// native WKWebView.
  void simulateLoadComplete(
    String identityId,
    Uri uri, {
    bool canGoBack = false,
    bool canGoForward = false,
  }) {
    _urlByIdentity[identityId] = uri;
    _events.add(
      WebviewLoadComplete(
        identityId,
        uri,
        canGoBack: canGoBack,
        canGoForward: canGoForward,
      ),
    );
  }

  void dispose() {
    _events.close();
  }
}

class _HeadlessNav {
  final String url;
  final bool loading;
  _HeadlessNav({this.url = '', this.loading = false});
}
