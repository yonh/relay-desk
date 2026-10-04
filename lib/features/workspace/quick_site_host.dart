/// In-app host for 快捷站点 (Quick Sites) overlay/right-dock launches.
///
/// Renders an [InAppWebView] with app-owned chrome (site title, loading
/// indicator, reload button, close button) above the workspace layout. The
/// `overlay` mode is a floating/elevated card roughly 45% of the workspace
/// width; the `sideDock` mode is a ~360px right-side dock.
///
/// The host owns a stable [ValueKey] derived from the launch request so that
/// choosing another shortcut (or the same shortcut with a different mode)
/// replaces the host rather than reusing stale WebView state. Remote pages are
/// isolated from Flutter method channels: no project WebView adapter state is
/// exposed to them.
///
/// Under widget tests (where `webviewPlatformSupportedProvider` is overridden
/// to false) the live [InAppWebView] is replaced by a placeholder so the host
/// chrome (title, reload, close) can still be asserted without instantiating a
/// native platform view.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../app/localization.dart';
import 'quick_sites_menu.dart';
import 'workspace_controller.dart';

/// A resolved quick-site launch request rendered by [QuickSiteHost].
@immutable
class QuickSiteLaunchRequest {
  final QuickSite site;
  final QuickSiteOpenMode mode;

  const QuickSiteLaunchRequest({required this.site, required this.mode});

  @override
  bool operator ==(Object other) =>
      other is QuickSiteLaunchRequest &&
      other.site.id == site.id &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(site.id, mode);
}

/// Hosts a single quick-site launch request as an overlay or right-side dock.
///
/// The host is meant to be placed in a [Stack] above the workspace layout. It
/// positions itself according to [QuickSiteLaunchRequest.mode] and reports
/// close/reload through callbacks. WebView failures surface as a compact
/// inline error inside the host chrome.
class QuickSiteHost extends ConsumerStatefulWidget {
  final QuickSiteLaunchRequest request;
  final ValueChanged<QuickSiteLaunchRequest> onClose;

  /// Whether the host is currently shown. When `false` the host remains
  /// mounted (so its StatefulWidget and InAppWebView Element are preserved)
  /// but is wrapped in [Offstage] + [IgnorePointer], so it is neither
  /// painted nor hit-testable. This is used by the workspace to implement
  /// the `常驻内存` (keep-alive) behavior: closing only hides the host,
  /// reopening restores the same loaded WebView and page state.
  final bool visible;

  const QuickSiteHost({
    super.key,
    required this.request,
    required this.onClose,
    this.visible = true,
  });

  @override
  ConsumerState<QuickSiteHost> createState() => _QuickSiteHostState();
}

class _QuickSiteHostState extends ConsumerState<QuickSiteHost> {
  InAppWebViewController? _controller;
  String _title = '';
  bool _loading = true;

  /// Raw error detail from the WebView (never localized here); the message
  /// wrapper is applied at render time so locale switches relabel it.
  String? _errorDetail;

  // Floating overlay geometry (overlay mode only). Initialized lazily from
  // the first LayoutBuilder constraints we see, then mutated by drag/resize
  // gestures. Kept as instance state so the live WebView Element (stable
  // ValueKey below) is preserved across drag/resize rebuilds.
  Offset _position = Offset.zero;
  Size _size = Size.zero;
  Size _stackSize = Size.zero;
  bool _geometryInitialized = false;

  static const double _minWidth = 320;
  static const double _maxWidth = 720;
  static const double _minHeight = 360;
  static const double _maxHeight = 1200;

  QuickSiteLaunchRequest get _request => widget.request;

  @override
  void initState() {
    super.initState();
    _title = _request.site.name;
  }

  @override
  void didUpdateWidget(covariant QuickSiteHost old) {
    super.didUpdateWidget(old);
    if (old.request != _request) {
      // A different shortcut/mode was chosen: reset chrome state and the
      // floating geometry so a new overlay starts at the default top-right
      // placement. The InAppWebView itself is replaced via the stable
      // ValueKey below.
      _title = _request.site.name;
      _loading = true;
      _errorDetail = null;
      _geometryInitialized = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = ref.watch(webviewPlatformSupportedProvider);
    return _positioned(context: context, child: _card(context, supported));
  }

  Widget _positioned({required BuildContext context, required Widget child}) {
    final mode = _request.mode;
    if (mode == QuickSiteOpenMode.sideDock) {
      // The side dock is a fixed 360px right-side dock: not draggable and
      // not resizable.
      return Positioned(
        top: 0,
        right: 0,
        bottom: 0,
        width: 360,
        child: _visibilityGate(
          Padding(padding: const EdgeInsets.all(8), child: child),
        ),
      );
    }
    // `Positioned` must be a direct Stack child. The LayoutBuilder therefore
    // lives inside a Positioned.fill and only calculates the floating card
    // geometry. A nested Stack positions the card by absolute offset; empty
    // areas pass through to the workspace layout beneath.
    return Positioned.fill(
      child: _visibilityGate(
        LayoutBuilder(
          builder: (context, constraints) {
            _stackSize = Size(constraints.maxWidth, constraints.maxHeight);
            if (!_geometryInitialized) {
              final width = (constraints.maxWidth * 0.45).clamp(
                _minWidth,
                _maxWidth,
              );
              final height = (constraints.maxHeight * 0.8).clamp(
                _minHeight,
                _maxHeight,
              );
              _size = Size(width, height);
              _position = Offset(
                (constraints.maxWidth - width - 16).clamp(0.0, double.infinity),
                16,
              );
              _geometryInitialized = true;
            }
            final w = _size.width.clamp(_minWidth, constraints.maxWidth);
            final h = _size.height.clamp(_minHeight, constraints.maxHeight);
            final maxLeft = (constraints.maxWidth - w).clamp(
              0.0,
              double.infinity,
            );
            final maxTop = (constraints.maxHeight - h).clamp(
              0.0,
              double.infinity,
            );
            final left = _position.dx.clamp(0.0, maxLeft);
            final top = _position.dy.clamp(0.0, maxTop);
            return Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  width: w,
                  height: h,
                  child: child,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _visibilityGate(Widget child) => IgnorePointer(
    ignoring: !widget.visible,
    child: Offstage(
      key: const ValueKey('quick-site-host-offstage'),
      offstage: !widget.visible,
      child: child,
    ),
  );

  Widget _card(BuildContext context, bool supported) {
    final theme = Theme.of(context);
    final isOverlay = _request.mode == QuickSiteOpenMode.overlay;
    return Material(
      key: ValueKey(
        'quick-site-host-${_request.site.id}-${_request.mode.name}',
      ),
      elevation: isOverlay ? 12 : 4,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surface,
      surfaceTintColor: theme.colorScheme.surfaceTint,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _chrome(theme, supported),
              Divider(height: 1, color: theme.dividerColor),
              Expanded(child: _body(theme, supported)),
            ],
          ),
          if (isOverlay)
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                key: const ValueKey('quick-site-host-resize-handle'),
                behavior: HitTestBehavior.opaque,
                onPanUpdate: _onResizeUpdate,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpLeftDownRight,
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: Center(
                      child: Icon(
                        Icons.aspect_ratio,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chrome(ThemeData theme, bool supported) {
    final isOverlay = _request.mode == QuickSiteOpenMode.overlay;
    final leading = _chromeLeading(theme, supported);
    return Container(
      key: const ValueKey('quick-site-host-chrome'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Row(
        children: [
          // The leading area (icon + title + loading spinner) is the drag
          // affordance for overlay mode. The reload/close IconButtons are
          // siblings so their taps are not claimed by the drag gesture.
          Expanded(
            child: isOverlay
                ? GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanUpdate: _onDragUpdate,
                    child: leading,
                  )
                : leading,
          ),
          // Quick-site hosts run on the unmodified InAppWebView shared default
          // store (SharedSession) — mark them as not isolated per GOAL.md §5.
          Tooltip(
            message: context.l10n.isolationSharedSession,
            child: const Icon(Icons.lock_open_outlined, size: 12),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: context.l10n.reloadTooltip,
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28),
            icon: const Icon(Icons.refresh),
            onPressed: _onReload,
          ),
          IconButton(
            tooltip: context.l10n.closeTooltip,
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28),
            icon: const Icon(Icons.close),
            onPressed: () => widget.onClose(_request),
          ),
        ],
      ),
    );
  }

  Widget _chromeLeading(ThemeData theme, bool supported) {
    return Row(
      children: [
        Icon(Icons.bolt, size: 14, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _title.isNotEmpty ? _title : _request.site.name,
            key: const ValueKey('quick-site-host-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (_loading && supported)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!mounted || _stackSize == Size.zero) return;
    final w = _size.width.clamp(_minWidth, _stackSize.width);
    final h = _size.height.clamp(_minHeight, _stackSize.height);
    final maxLeft = (_stackSize.width - w).clamp(0.0, double.infinity);
    final maxTop = (_stackSize.height - h).clamp(0.0, double.infinity);
    final newLeft = (_position.dx + details.delta.dx).clamp(0.0, maxLeft);
    final newTop = (_position.dy + details.delta.dy).clamp(0.0, maxTop);
    setState(() {
      _position = Offset(newLeft, newTop);
    });
  }

  void _onResizeUpdate(DragUpdateDetails details) {
    if (!mounted || _stackSize == Size.zero) return;
    final maxW = _stackSize.width - _position.dx;
    final maxH = _stackSize.height - _position.dy;
    final newWidth = (_size.width + details.delta.dx).clamp(
      _minWidth,
      _maxWidth < maxW ? _maxWidth : maxW,
    );
    final newHeight = (_size.height + details.delta.dy).clamp(
      _minHeight,
      _maxHeight < maxH ? _maxHeight : maxH,
    );
    setState(() {
      _size = Size(newWidth, newHeight);
    });
  }

  Widget _body(ThemeData theme, bool supported) {
    final detail = _errorDetail;
    if (detail != null) {
      return _ErrorView(
        message: context.l10n.quickSiteLoadFailed(detail),
        onRetry: _onReload,
      );
    }
    if (!supported) {
      // Widget tests / unsupported platforms: show a placeholder so the host
      // chrome can be asserted without instantiating a native platform view.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            context.l10n.quickSiteHostUnsupported(_request.site.name),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
        ),
      );
    }
    return InAppWebView(
      key: ValueKey(
        'quick-site-webview-${_request.site.id}-${_request.mode.name}',
      ),
      initialUrlRequest: URLRequest(url: WebUri(_request.site.url)),
      onWebViewCreated: (controller) {
        _controller = controller;
      },
      onLoadStart: (controller, uri) {
        if (!mounted) return;
        setState(() {
          _loading = true;
          _errorDetail = null;
        });
      },
      onLoadStop: (controller, uri) {
        if (!mounted) return;
        setState(() => _loading = false);
        controller.getTitle().then((t) {
          if (mounted && t != null && t.isNotEmpty) {
            setState(() => _title = t);
          }
        });
      },
      onReceivedError: (controller, request, error) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _errorDetail = error.description;
        });
      },
      onTitleChanged: (controller, title) {
        if (!mounted) return;
        if (title != null && title.isNotEmpty) {
          setState(() => _title = title);
        }
      },
    );
  }

  void _onReload() {
    final controller = _controller;
    if (controller != null) {
      controller.reload();
    } else {
      // No live controller (e.g. unsupported platform): just reset the chrome
      // state so the reload affordance has an observable effect.
      if (mounted) {
        setState(() {
          _loading = true;
          _errorDetail = null;
        });
      }
    }
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 28),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(context.l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}
