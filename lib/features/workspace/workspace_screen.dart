/// Workspace canvas: shows identity WebView panels driven by the concrete
/// WebviewAdapter via [WorkspaceController]. Supports Canvas/Grid/Focus layout
/// modes, per-panel navigation (back/forward/stop/reload/URL), drag
/// and resize with monotonic bounds revision, fingerprint reconstruction, and
/// named workspace save/load/delete.
///
/// On macOS the panels embed the native `profiled_webview` platform view
/// (WKWebsiteDataStore(forIdentifier:) per identity). On other platforms a
/// placeholder is shown and the platform is recorded as NOT_TESTED.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/localization.dart';
import '../../app/providers.dart';
import '../../core/platform/domain.dart';
import '../../core/platform/webview_adapter.dart';
import '../../data/device_presets.dart';
import '../../platform/webview/macos_profiled_webview_adapter.dart';
import '../common/empty_state_guide.dart';
import 'quick_site_host.dart';
import 'quick_sites_menu.dart';
import 'workspace_controller.dart';

// Resident quick-site hosts live above an individual project page so a
// project switch does not discard their hidden/visible state.
final Map<String, Map<QuickSiteLaunchRequest, bool>>
_residentQuickSitesByProject = {};
final Map<String, Set<String>> _quickSiteKeepAliveByProject = {};
final ValueNotifier<int> _residentQuickSitesRevision = ValueNotifier<int>(0);

/// Widget tests boot a fresh project per test; without clearing these
/// project-keyed globals, resident hosts left by earlier tests leak into the
/// widget tree as offstage zombies and break finders.
@visibleForTesting
void resetQuickSiteHostGlobals() {
  _residentQuickSitesByProject.clear();
  _quickSiteKeepAliveByProject.clear();
  _residentQuickSitesRevision.value++;
}

class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final projectId = ref.watch(selectedProjectIdProvider);
    if (projectId == null) {
      return EmptyStateGuide(
        icon: Icons.dashboard_outlined,
        title: l10n.noProjectSelectedTitle,
        description: l10n.noProjectSelectedDescription,
      );
    }
    final project = ref.watch(selectedProjectProvider);
    final identities = ref.watch(identitiesProvider(projectId));

    final content = project.when(
      data: (proj) => identities.when(
        data: (list) {
          if (proj == null) {
            return _EmptyState(message: l10n.projectNotFound);
          }
          if (list.isEmpty) {
            return EmptyStateGuide(
              icon: Icons.person_add_outlined,
              title: l10n.noIdentitiesInProjectTitle(proj.name),
              description: l10n.noIdentitiesInProjectDescription,
            );
          }
          return _WorkspaceBody(project: proj, identities: list);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _EmptyState(message: l10n.errorMessage(e.toString())),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _EmptyState(message: l10n.errorMessage(e.toString())),
    );
    return Stack(
      children: [
        Positioned.fill(child: content),
        Positioned.fill(
          child: ValueListenableBuilder<int>(
            valueListenable: _residentQuickSitesRevision,
            builder: (context, _, _) => Stack(
              children: [
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: _GlobalResidentQuickSiteTrigger(
                    residents: _residentQuickSitesByProject.values
                        .expand((items) => items.entries)
                        .where((entry) => !entry.value)
                        .map((entry) => entry.key)
                        .toList(growable: false),
                  ),
                ),
                for (final projectEntry in _residentQuickSitesByProject.entries)
                  for (final entry in projectEntry.value.entries)
                    QuickSiteHost(
                      key: ValueKey(
                        'global-quick-site-${projectEntry.key}-${entry.key.site.id}-${entry.key.mode.name}',
                      ),
                      request: entry.key,
                      visible: entry.value,
                      onClose: (_) =>
                          _closeGlobalQuickSite(projectEntry.key, entry.key),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Mutates the shared per-project host map. Because [_persistQuickSites]
/// aliases the workspace's local map into [_residentQuickSitesByProject]
/// (rather than copying), this mutation is visible to the owning workspace —
/// no local shadow state can resurrect a closed host.
void _closeGlobalQuickSite(String projectId, QuickSiteLaunchRequest request) {
  final hosts = _residentQuickSitesByProject[projectId];
  if (hosts == null) return;
  if (_quickSiteKeepAliveByProject[projectId]?.contains(request.site.id) ??
      false) {
    hosts[request] = false;
  } else {
    hosts.remove(request);
  }
  _residentQuickSitesRevision.value++;
}

/// Foreground mouse side-button dispatcher: X1 (back) / X2 (forward) presses
/// over Flutter-rendered workspace chrome act on the active panel. Does
/// nothing when the press is not a side button or there is no routable panel.
void _handleMouseSideButton(WidgetRef ref, PointerDownEvent event) {
  final controller = ref.read(workspaceControllerProvider.notifier);
  if ((event.buttons & kBackMouseButton) != 0) {
    controller.backActive();
  } else if ((event.buttons & kForwardMouseButton) != 0) {
    controller.forwardActive();
  }
}

class _GlobalResidentQuickSiteTrigger extends StatelessWidget {
  final List<QuickSiteLaunchRequest> residents;
  const _GlobalResidentQuickSiteTrigger({required this.residents});

  static String? _projectKeyFor(QuickSiteLaunchRequest request) {
    for (final entry in _residentQuickSitesByProject.entries) {
      if (entry.value.containsKey(request)) return entry.key;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (residents.isEmpty) return const SizedBox.shrink();
    return _ResidentQuickSiteTrigger(
      residents: residents,
      onRestore: (request) {
        final key = _projectKeyFor(request);
        if (key != null) {
          _residentQuickSitesByProject[key]?[request] = true;
          _residentQuickSitesRevision.value++;
        }
      },
      onDispose: (request) {
        final key = _projectKeyFor(request);
        if (key != null) {
          _residentQuickSitesByProject[key]?.remove(request);
          _residentQuickSitesRevision.value++;
        }
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.dashboard, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(message, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

Color _tagColor(String? value) {
  if (value == null) return const Color(0xff4c8dff);
  final hex = value.replaceFirst('#', '');
  final parsed = int.tryParse(hex.length == 6 ? 'ff$hex' : hex, radix: 16);
  return parsed == null ? const Color(0xff4c8dff) : Color(parsed);
}

class _TagDock extends StatefulWidget {
  final List<PanelRuntime> panels;
  final List<Identity> identities;
  final String? selectedPanelId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;

  const _TagDock({
    required this.panels,
    required this.identities,
    required this.selectedPanelId,
    required this.onSelect,
    required this.onClose,
  });

  @override
  State<_TagDock> createState() => _TagDockState();
}

class _TagDockState extends State<_TagDock> {
  bool _hovered = false;

  Identity? _identity(String id) {
    for (final identity in widget.identities) {
      if (identity.id == id) return identity;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.bottomRight,
            child: _hovered
                ? Container(
                    width: math.min(360, MediaQuery.sizeOf(context).width - 88),
                    constraints: const BoxConstraints(maxHeight: 240),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .98),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xffe4e7ed)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x261e2532),
                          blurRadius: 20,
                          offset: Offset(0, 9),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: widget.panels.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: Color(0xffeceef2)),
                        itemBuilder: (context, index) {
                          final panel = widget.panels[index];
                          final identity = _identity(panel.identityId);
                          final color = _tagColor(identity?.color);
                          return Container(
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(color: color, width: 6),
                              ),
                            ),
                            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                            child: Row(
                              children: [
                                Icon(Icons.bolt, size: 16, color: color),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: InkWell(
                                    onTap: () =>
                                        widget.onSelect(panel.identityId),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          identity?.name ?? panel.identityId,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        Text(
                                          widget.selectedPanelId ==
                                                  panel.identityId
                                              ? context.l10n.tagSelectedHint
                                              : context.l10n.tagResidentHint,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: const Color(0xff737b88),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: context.l10n.closeTabTooltip,
                                  onPressed: () =>
                                      widget.onClose(panel.identityId),
                                  icon: const Icon(Icons.close, size: 16),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.white,
            elevation: 8,
            shadowColor: const Color(0x331e2532),
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(14),
            ),
            child: InkWell(
              onTap: () => setState(() => _hovered = !_hovered),
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(14),
              ),
              child: Container(
                width: 44,
                height: 66,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xffe4e7ed)),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(14),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.bookmark_border,
                      size: 18,
                      color: Color(0xffff5b3e),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xffff5b3e),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '${widget.panels.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceBody extends ConsumerStatefulWidget {
  final Project project;
  final List<Identity> identities;
  const _WorkspaceBody({required this.project, required this.identities});

  @override
  ConsumerState<_WorkspaceBody> createState() => _WorkspaceBodyState();
}

class _WorkspaceBodyState extends ConsumerState<_WorkspaceBody> {
  // Last runtime-affecting identity signature we synced against, so
  // didUpdateWidget only re-syncs when the identities actually change
  // (avoiding redundant post-frame work). The signature includes the fields
  // that feed PanelRuntimeConfig — editing isolationMode or startPath on an
  // existing identity must re-run _syncPanels so ensurePanel sees the
  // fingerprint change and rebuilds the WebView (only comparing id sets
  // silently kept the old isolation store alive).
  String _lastSyncedSignature = '';
  int _syncGeneration = 0;

  // Keep every platform view's element identity as it moves between layout
  // slots. This prevents Focus selection from recreating a native WebView.
  final Map<String, GlobalKey> _panelKeys = {};

  GlobalKey _panelKey(String identityId) =>
      _panelKeys.putIfAbsent(identityId, GlobalKey.new);

  /// Allocated quick-site hosts, keyed by site and open mode. A false value is
  /// an independently resident/offstage WebView; it is not a global state.
  late Map<QuickSiteLaunchRequest, bool> _quickSiteHosts;

  void _persistQuickSites({bool notify = true}) {
    // Alias (not copy): the global registry and this workspace's local fields
    // intentionally share one map/set so global-side mutations (close from the
    // resident strip, restore, dispose) and local mutations (launch, keep-alive
    // toggle) can never diverge. Snapshotting into a Map.from copy was the bug:
    // a host closed globally would be resurrected on the next persist.
    _residentQuickSitesByProject[widget.project.id] = _quickSiteHosts;
    _quickSiteKeepAliveByProject[widget.project.id] =
        _quickSiteKeepAliveSiteIds;
    if (notify) _residentQuickSitesRevision.value++;
  }

  /// Site ids whose hosts should stay resident in memory (`常驻内存`) when
  /// closed. Each site owns an independent toggle; when a site's id is in
  /// this set, closing its host only hides it ([_quickSiteVisible] = false)
  /// so the underlying WebView Element and its loaded page state survive;
  /// reopening the same site/mode restores them.
  late Set<String> _quickSiteKeepAliveSiteIds;

  /// Raw failure detail for the `newWindow` mode (which has no in-app host
  /// to render into). Stored untranslated and localized at render time so a
  /// locale switch relabels the message; cleared on the next launch.
  String? _newWindowErrorDetail;

  @override
  void initState() {
    super.initState();
    _quickSiteHosts = _residentQuickSitesByProject.putIfAbsent(
      widget.project.id,
      () => <QuickSiteLaunchRequest, bool>{},
    );
    _quickSiteKeepAliveSiteIds = _quickSiteKeepAliveByProject.putIfAbsent(
      widget.project.id,
      () => <String>{},
    );
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant _WorkspaceBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.id != widget.project.id) {
      // Deliberate snapshot: the old project's entry is detached here because
      // the local fields are rebound to the *new* project's shared maps below.
      _residentQuickSitesByProject[oldWidget.project.id] =
          Map<QuickSiteLaunchRequest, bool>.from(_quickSiteHosts);
      _quickSiteKeepAliveByProject[oldWidget.project.id] = Set<String>.from(
        _quickSiteKeepAliveSiteIds,
      );
      _quickSiteHosts = _residentQuickSitesByProject.putIfAbsent(
        widget.project.id,
        () => <QuickSiteLaunchRequest, bool>{},
      );
      _quickSiteKeepAliveSiteIds = _quickSiteKeepAliveByProject.putIfAbsent(
        widget.project.id,
        () => <String>{},
      );
    }
    final newIds = widget.identities.map((i) => i.id).toSet();
    _panelKeys.removeWhere((identityId, _) => !newIds.contains(identityId));
    if (_identitySignature() != _lastSyncedSignature ||
        oldWidget.project.id != widget.project.id) {
      _scheduleSync();
    }
  }

  /// Covers every field that flows (or is defined to flow) into
  /// PanelRuntimeConfig.fingerprint: identity id + isolationMode + startPath +
  /// devicePresetId, and the project target URL.
  String _identitySignature() =>
      '${widget.identities.map((i) => '${i.id}:${i.isolationMode.dbValue}:${i.startPath}:${i.devicePresetId ?? ''}').join('|')}@${widget.project.targetUrl}';

  @override
  void dispose() {
    // The widget tree is locked during dispose; notifying the global
    // ValueNotifier here would make its listeners call setState too early.
    _persistQuickSites(notify: false);
    super.dispose();
  }

  void _onQuickSiteLaunch(QuickSite site, QuickSiteOpenMode mode) {
    switch (mode) {
      case QuickSiteOpenMode.overlay:
      case QuickSiteOpenMode.sideDock:
        setState(() {
          _newWindowErrorDetail = null;
          // The site/mode pair owns an independent WebView instance.
          _quickSiteHosts[QuickSiteLaunchRequest(site: site, mode: mode)] =
              true;
          _persistQuickSites();
        });
      case QuickSiteOpenMode.newWindow:
        _openQuickSiteInNewWindow(site);
    }
  }

  void _onQuickSiteKeepAliveChanged(QuickSite site, bool value) {
    setState(() {
      if (value) {
        _quickSiteKeepAliveSiteIds = {..._quickSiteKeepAliveSiteIds, site.id};
      } else {
        _quickSiteKeepAliveSiteIds = _quickSiteKeepAliveSiteIds
            .where((id) => id != site.id)
            .toSet();
        // Disabling keep-alive while the matching host is already hidden
        // releases the resident WebView immediately rather than retaining
        // it in memory for a reopen that will never come.
        _quickSiteHosts.removeWhere(
          (request, visible) => request.site.id == site.id && !visible,
        );
      }
      _persistQuickSites();
    });
  }

  Future<void> _openQuickSiteInNewWindow(QuickSite site) async {
    setState(() => _newWindowErrorDetail = null);
    try {
      await InAppBrowser().openUrlRequest(
        urlRequest: URLRequest(url: WebUri(site.url)),
      );
      _persistQuickSites();
    } catch (e) {
      if (!mounted) return;
      // Keep the raw detail; the localized wrapper is applied at render.
      setState(() => _newWindowErrorDetail = e.toString());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Syncing panels mutates the WorkspaceController notifier; doing that
    // synchronously inside a build life-cycle would throw "Tried to modify a
    // provider while the widget tree was building". Defer to the end of the
    // current frame so the mutation happens after the build phase completes.
    _scheduleSync();
  }

  void _scheduleSync() {
    final generation = ++_syncGeneration;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncPanels(generation),
    );
  }

  Future<void> _syncPanels(int generation) async {
    if (!mounted) return;
    final controller = ref.read(workspaceControllerProvider.notifier);
    final projectId = widget.project.id;
    await controller.restoreProjectLayoutMode(projectId);
    if (!mounted ||
        generation != _syncGeneration ||
        widget.project.id != projectId) {
      return;
    }
    final ws = ref.read(workspaceControllerProvider);
    final liveIds = widget.identities.map((i) => i.id).toSet();
    // Remove panels whose identities were deleted.
    for (final id in ws.panels.keys.toList()) {
      if (!liveIds.contains(id)) {
        controller.removePanel(id);
      }
    }
    // Ensure panels for current identities (fingerprint reconstruction is
    // handled inside ensurePanel).
    for (final identity in widget.identities) {
      controller.ensurePanel(identity, widget.project);
    }
    _lastSyncedSignature = _identitySignature();
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(workspaceControllerProvider);
    final capabilities = ref.watch(capabilitiesProvider);
    return Column(
      children: [
        _WorkspaceToolbar(
          project: widget.project,
          identities: widget.identities,
          layoutMode: ws.layoutMode,
          capabilities: capabilities,
          onQuickSiteLaunch: _onQuickSiteLaunch,
          newWindowError: _newWindowErrorDetail == null
              ? null
              : context.l10n.newWindowError(_newWindowErrorDetail!),
          // Pass an unmodifiable view so the menu cannot mutate the
          // workspace's resident set; only [_onQuickSiteKeepAliveChanged]
          // mutates state.
          quickSiteKeepAliveSiteIds: Set<String>.unmodifiable(
            _quickSiteKeepAliveSiteIds,
          ),
          onQuickSiteKeepAliveChanged: _onQuickSiteKeepAliveChanged,
        ),
        // Foreground-only mouse side-button routing (X1=back / X2=forward)
        // for Flutter-rendered chrome (toolbar, gaps). A Flutter Listener
        // only fires while this window is focused, so no OS-level background
        // hook or permission is involved. Presses landing on web content are
        // handled natively by ProfiledWebView (AppKit never forwards those
        // to the framework) and act on the page under the cursor —
        // standard browser behavior, also correct for detached windows.
        // Only presses over non-WebView areas reach here, and those are
        // routed to the active panel (selectedPanelId) in every layout mode.
        // Deliberately placed here instead of inside _TagDock (currently
        // unmounted, and its hover area would be too small to be useful).
        Expanded(
          child: Listener(
            key: const ValueKey('workspace-side-button-listener'),
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) => _handleMouseSideButton(ref, event),
            child: Stack(children: [_layoutFor(ws)]),
          ),
        ),
      ],
    );
  }

  Widget _layoutFor(WorkspaceState ws) {
    final panels = ws.panels.values.where((p) => !p.layout.minimized).toList();
    if (panels.isEmpty) {
      return EmptyStateGuide(
        icon: Icons.web_outlined,
        title: context.l10n.noPanelsTitle,
        description: context.l10n.noPanelsDescription,
      );
    }
    switch (ws.layoutMode) {
      case LayoutMode.grid:
        return _grid(panels);
      case LayoutMode.columns:
        return _columns(panels);
      case LayoutMode.canvas:
        return _canvas(panels);
      case LayoutMode.focus:
        return _focus(panels);
    }
  }

  Widget _grid(List<PanelRuntime> panels) {
    final count = panels.length;
    final cross = count <= 1 ? 1 : (count <= 4 ? 2 : 3);
    return GridView.count(
      crossAxisCount: cross,
      childAspectRatio: 1.25,
      children: panels
          .map((p) => _PanelView(key: _panelKey(p.identityId), runtime: p))
          .toList(),
    );
  }

  /// Columns layout: each panel occupies one vertical column, side by side
  /// from left to right. All columns share the full available height.
  Widget _columns(List<PanelRuntime> panels) {
    return Row(
      children: [
        for (final p in panels)
          Expanded(
            child: _PanelView(key: _panelKey(p.identityId), runtime: p),
          ),
      ],
    );
  }

  Widget _canvas(List<PanelRuntime> panels) {
    return Stack(
      children: [
        for (final p in panels)
          Positioned(
            left: p.layout.x,
            top: p.layout.y,
            width: p.layout.width,
            height: p.layout.height,
            child: _PanelView(
              key: _panelKey(p.identityId),
              runtime: p,
              draggable: true,
            ),
          ),
      ],
    );
  }

  Widget _focus(List<PanelRuntime> panels) {
    final selectedId = ref.watch(workspaceControllerProvider).selectedPanelId;
    final focusedId = panels.any((panel) => panel.identityId == selectedId)
        ? selectedId!
        : panels.first.identityId;
    final focused = panels.firstWhere(
      (p) => p.identityId == focusedId,
      orElse: () => panels.first,
    );
    final secondary = panels
        .where((panel) => panel.identityId != focused.identityId)
        .toList();

    // The desktop composition mirrors the original Focus workspace: the
    // active role gets a large canvas at left, while all other roles remain
    // visible in a narrow, vertically stacked strip at right.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760 || secondary.isEmpty) {
          return _focusNarrow(focused, secondary);
        }
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _PanelView(
                  key: _panelKey(focused.identityId),
                  runtime: focused,
                  selected: true,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 320,
                child: Column(
                  children: [
                    for (final panel in secondary)
                      Expanded(
                        child: _PanelView(
                          key: _panelKey(panel.identityId),
                          runtime: panel,
                          selected: false,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _focusNarrow(PanelRuntime focused, List<PanelRuntime> secondary) {
    return Padding(
      key: const ValueKey('focus-narrow-layout'),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Expanded(
            flex: 3,
            child: _PanelView(
              key: _panelKey(focused.identityId),
              runtime: focused,
              selected: true,
            ),
          ),
          if (secondary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                key: const ValueKey('focus-secondary-strip'),
                scrollDirection: Axis.horizontal,
                itemCount: secondary.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final panel = secondary[index];
                  return SizedBox(
                    width: 340,
                    child: _PanelView(
                      key: _panelKey(panel.identityId),
                      runtime: panel,
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom-right resident shortcuts. Each row maps to one independently kept
/// WebView and can either restore it or explicitly release its memory.
class _ResidentQuickSiteTrigger extends StatefulWidget {
  final List<QuickSiteLaunchRequest> residents;
  final ValueChanged<QuickSiteLaunchRequest> onRestore;
  final ValueChanged<QuickSiteLaunchRequest> onDispose;

  const _ResidentQuickSiteTrigger({
    required this.residents,
    required this.onRestore,
    required this.onDispose,
  });

  @override
  State<_ResidentQuickSiteTrigger> createState() =>
      _ResidentQuickSiteTriggerState();
}

class _ResidentQuickSiteTriggerState extends State<_ResidentQuickSiteTrigger> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: context.l10n.residentQuickSitesLabel,
      child: Material(
        key: const ValueKey('resident-quick-site-trigger'),
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 270),
          child: SizedBox(
            width: 220,
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: widget.residents.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final request = widget.residents[index];
                final site = request.site;
                return SizedBox(
                  key: ValueKey(
                    'resident-quick-site-trigger-'
                    '${request.site.id}-${request.mode.name}',
                  ),
                  width: 220,
                  height: 52,
                  // Tap anywhere on the row to restore that resident host; the
                  // collapsed pill alone is otherwise dead space.
                  child: InkWell(
                    onTap: () => widget.onRestore(request),
                    child: MouseRegion(
                      onEnter: (_) => setState(() => _hoveredIndex = index),
                      onExit: (_) {
                        if (_hoveredIndex == index) {
                          setState(() => _hoveredIndex = null);
                        }
                      },
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          width: _hoveredIndex == index ? 212 : 42,
                          height: 52,
                          child: ClipRect(
                            child: _hoveredIndex == index
                                ? OverflowBox(
                                    maxWidth: 212,
                                    alignment: Alignment.centerRight,
                                    child: _ResidentExpandedRow(
                                      site: site,
                                      theme: theme,
                                      onRestore: () =>
                                          widget.onRestore(request),
                                      onDispose: () =>
                                          widget.onDispose(request),
                                    ),
                                  )
                                : _CollapsedResidentTab(accent: site.color),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ResidentExpandedRow extends StatelessWidget {
  final QuickSite site;
  final ThemeData theme;
  final VoidCallback onRestore;
  final VoidCallback onDispose;
  const _ResidentExpandedRow({
    required this.site,
    required this.theme,
    required this.onRestore,
    required this.onDispose,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: theme.colorScheme.surface,
    elevation: 8,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      onTap: onRestore,
      child: SizedBox(
        width: 212,
        height: 52,
        child: Row(
          children: [
            IconButton(
              tooltip: context.l10n.releaseResidentTooltip(site.name),
              icon: const Icon(Icons.close, size: 16),
              onPressed: onDispose,
            ),
            Container(width: 6, height: 52, color: site.color),
            const SizedBox(width: 10),
            Icon(Icons.bolt, size: 15, color: site.color),
            const SizedBox(width: 7),
            Expanded(
              // The 52px row is too short for two label lines under test-font
              // metrics; scale the text block down rather than overflow.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      site.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      context.l10n.tagResidentHint,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CollapsedResidentTab extends StatelessWidget {
  final Color accent;
  const _CollapsedResidentTab({required this.accent});

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    elevation: 8,
    borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
    child: Container(
      width: 42,
      height: 52,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xffe4e7ed)),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [Icon(Icons.bolt, size: 16, color: accent)],
      ),
    ),
  );
}

class _WorkspaceToolbar extends ConsumerWidget {
  final Project project;
  final List<Identity> identities;
  final LayoutMode layoutMode;
  final AsyncValue<RuntimeCapabilities> capabilities;
  final QuickSiteLaunch onQuickSiteLaunch;
  final String? newWindowError;
  final Set<String> quickSiteKeepAliveSiteIds;
  final QuickSiteKeepAliveChanged? onQuickSiteKeepAliveChanged;

  const _WorkspaceToolbar({
    required this.project,
    required this.identities,
    required this.layoutMode,
    required this.capabilities,
    required this.onQuickSiteLaunch,
    required this.newWindowError,
    required this.quickSiteKeepAliveSiteIds,
    required this.onQuickSiteKeepAliveChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(workspaceControllerProvider);
    final workspaces = project.id == ws.selectedProjectId
        ? ref.watch(workspacesProvider(project.id))
        : const AsyncValue<List<WorkspaceLayout>>.data([]);
    return Container(
      key: const ValueKey('workspace-toolbar'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Use the actual toolbar constraints instead of MediaQuery. Widget
          // tests (and some desktop embeddings) can expose a different view
          // size through MediaQuery than the toolbar's allocated width.
          final compact = constraints.maxWidth < 900;
          return Row(
            children: [
              // Project/layout/workspace controls may scroll horizontally when the
              // toolbar is narrow; the quick-site trigger is intentionally kept
              // OUTSIDE this scroll view so it stays pinned in a fixed rightmost
              // toolbar slot at desktop widths.
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        project.name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(width: 8),
                      _capabilityBadge(context, capabilities),
                      const SizedBox(width: 8),
                      _layoutToggle(context, ref),
                      const SizedBox(width: 8),
                      _workspaceControls(context, ref, workspaces),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.identityCount(identities.length),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.panelCount(ws.panels.length),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 8),
                if (newWindowError != null)
                  SizedBox(
                    width: 180,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        newWindowError!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                QuickSitesMenu(
                  onLaunch: onQuickSiteLaunch,
                  keepAliveSiteIds: quickSiteKeepAliveSiteIds,
                  onKeepAliveChanged: onQuickSiteKeepAliveChanged,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _capabilityBadge(
    BuildContext context,
    AsyncValue<RuntimeCapabilities> cap,
  ) {
    return cap.when(
      data: (c) => Tooltip(
        message: c.nativeProfiles
            ? context.l10n.nativeProfilesAvailable
            : context.l10n.nativeProfilesUnavailable,
        child: Icon(
          c.nativeProfiles ? Icons.verified_user : Icons.warning,
          size: 16,
          color: c.nativeProfiles ? Colors.green : Colors.orange,
        ),
      ),
      loading: () => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, _) => const Icon(Icons.error, size: 16),
    );
  }

  Widget _layoutToggle(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return SegmentedButton<LayoutMode>(
      key: const ValueKey('workspace-layout-toggle'),
      segments: [
        ButtonSegment(
          value: LayoutMode.canvas,
          label: Text(l10n.layoutCanvas),
          icon: const Icon(Icons.view_quilt),
        ),
        ButtonSegment(
          value: LayoutMode.grid,
          label: Text(l10n.layoutGrid),
          icon: const Icon(Icons.grid_view),
        ),
        ButtonSegment(
          value: LayoutMode.columns,
          label: Text(l10n.layoutColumns),
          icon: const Icon(Icons.view_column),
        ),
        ButtonSegment(
          value: LayoutMode.focus,
          label: Text(l10n.layoutFocus),
          icon: const Icon(Icons.center_focus_strong),
        ),
      ],
      selected: {layoutMode},
      onSelectionChanged: (s) =>
          ref.read(workspaceControllerProvider.notifier).setLayoutMode(s.first),
    );
  }

  Widget _workspaceControls(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<WorkspaceLayout>> workspaces,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        workspaces.when(
          data: (list) {
            final selectedId = ref
                .watch(workspaceControllerProvider)
                .selectedWorkspaceId;
            // After saveWorkspace invalidates workspacesProvider, the list
            // reloads asynchronously; selectedId may briefly reference a
            // workspace not yet in `list`. DropdownButton asserts that `value`
            // matches exactly one item, so fall back to null until the reload
            // catches up (the next frame shows the saved workspace selected).
            final knownIds = list.map((w) => w.id).toSet();
            final effectiveValue =
                (selectedId != null && knownIds.contains(selectedId))
                ? selectedId
                : null;
            return DropdownButton<String?>(
              hint: Text(context.l10n.workspaceHint),
              value: effectiveValue,
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(context.l10n.workspaceNone),
                ),
                ...list.map(
                  (w) => DropdownMenuItem(value: w.id, child: Text(w.name)),
                ),
              ],
              onChanged: (id) {
                if (id != null) {
                  ref
                      .read(workspaceControllerProvider.notifier)
                      .loadWorkspace(id);
                }
              },
            );
          },
          loading: () => const SizedBox(
            width: 24,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (_, _) => Text(context.l10n.workspaceLoadError),
        ),
        IconButton(
          tooltip: context.l10n.saveWorkspaceTooltip,
          icon: const Icon(Icons.save, size: 18),
          onPressed: () => _showSaveDialog(context, ref),
        ),
        IconButton(
          tooltip: context.l10n.deleteWorkspaceTooltip,
          icon: const Icon(Icons.delete_outline, size: 18),
          onPressed: () {
            final id = ref
                .read(workspaceControllerProvider)
                .selectedWorkspaceId;
            if (id != null) {
              ref
                  .read(workspaceControllerProvider.notifier)
                  .deleteWorkspace(id);
            }
          },
        ),
        IconButton(
          tooltip: context.l10n.diagnosticsLogTooltip,
          icon: const Icon(Icons.bug_report_outlined, size: 18),
          onPressed: () => _copyDiagnosticsLogPath(context, ref),
        ),
      ],
    );
  }

  /// Copies the native diagnostics-log path to the clipboard so a "loading
  /// spins forever / stop does nothing" report can be diagnosed from
  /// `webview.log` instead of needing a debugger attached.
  Future<void> _copyDiagnosticsLogPath(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final adapter = ref.read(webviewAdapterProvider);
    final path = adapter is MacosProfiledWebviewAdapter
        ? await adapter.diagnosticsLogPath()
        : null;
    if (!context.mounted) return;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.diagnosticsLogUnavailable)),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: path));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.diagnosticsLogCopied(path))),
    );
  }

  void _showSaveDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController(text: context.l10n.workspaceHint);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.saveWorkspaceTitle),
        content: TextField(
          controller: nameCtrl,
          decoration: InputDecoration(labelText: ctx.l10n.fieldName),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty) return;
              await ref
                  .read(workspaceControllerProvider.notifier)
                  .saveWorkspace(nameCtrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(ctx.l10n.save),
          ),
        ],
      ),
    );
  }
}

/// A single panel: header + nav toolbar + embedded WebView.
class _PanelView extends ConsumerWidget {
  final PanelRuntime runtime;
  final bool draggable;
  final bool selected;
  const _PanelView({
    super.key,
    required this.runtime,
    this.draggable = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = _lookupIdentity(ref, runtime.identityId);
    final color = identity != null
        ? _parseColor(identity.color)
        : Colors.indigo;

    Widget header = _PanelHeader(
      identity: identity,
      runtime: runtime,
      color: color,
      draggable: draggable,
      selected: selected,
    );

    Widget body = _PanelBody(runtime: runtime);

    Widget card = Card(
      margin: const EdgeInsets.all(4),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          header,
          _PanelNavToolbar(runtime: runtime, identity: identity),
          Expanded(child: body),
        ],
      ),
    );

    if (!draggable) return card;

    // Canvas drag/resize with bounds revision.
    return GestureDetector(
      onPanUpdate: (d) {
        final newLayout = runtime.layout.copyWith(
          x: runtime.layout.x + d.delta.dx,
          y: runtime.layout.y + d.delta.dy,
        );
        ref
            .read(workspaceControllerProvider.notifier)
            .updateBounds(runtime.identityId, newLayout);
      },
      onPanEnd: (_) {
        ref
            .read(workspaceControllerProvider.notifier)
            .updateBounds(
              runtime.identityId,
              runtime.layout,
              finalCommit: true,
            );
      },
      child: Stack(
        children: [
          card,
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onPanUpdate: (d) {
                // Mobile presets keep the Tauri baseline's 320px panel
                // minimum so the emulated viewport stays usable.
                final minWidth =
                    (devicePresetFor(
                          identity?.devicePresetId,
                          ref.read(customDevicePresetsProvider).valueOrEmpty,
                        )?.mobile ??
                        false)
                    ? 320.0
                    : 240.0;
                final newLayout = runtime.layout.copyWith(
                  width: (runtime.layout.width + d.delta.dx).clamp(
                    minWidth,
                    4000,
                  ),
                  height: (runtime.layout.height + d.delta.dy).clamp(200, 4000),
                );
                ref
                    .read(workspaceControllerProvider.notifier)
                    .updateBounds(runtime.identityId, newLayout);
              },
              onPanEnd: (_) {
                ref
                    .read(workspaceControllerProvider.notifier)
                    .updateBounds(
                      runtime.identityId,
                      runtime.layout,
                      finalCommit: true,
                    );
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeDownRight,
                child: Container(
                  width: 16,
                  height: 16,
                  color: Colors.black.withValues(alpha: 0.2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Identity? _lookupIdentity(WidgetRef ref, String identityId) {
    final projectId = ref.watch(selectedProjectIdProvider);
    if (projectId == null) return null;
    final identities = ref.watch(identitiesProvider(projectId));
    return identities.maybeWhen(
      data: (list) => list.where((i) => i.id == identityId).firstOrNull,
      orElse: () => null,
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.indigo;
    }
  }
}

class _PanelHeader extends ConsumerWidget {
  final Identity? identity;
  final PanelRuntime runtime;
  final Color color;
  final bool draggable;
  final bool selected;
  const _PanelHeader({
    required this.identity,
    required this.runtime,
    required this.color,
    required this.draggable,
    required this.selected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => ref
          .read(workspaceControllerProvider.notifier)
          .selectPanel(runtime.identityId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: color,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 400;
            return Row(
              children: [
                Icon(
                  draggable
                      ? Icons.drag_indicator
                      : selected
                      ? Icons.center_focus_strong
                      : Icons.web,
                  size: 14,
                  color: Colors.white70,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    identity?.name ?? runtime.identityId.substring(0, 8),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 8),
                  Text(
                    identity?.isolationMode.label(context.l10n) ?? '',
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _DevicePresetMenu.iconFor(
                      identity?.devicePresetId,
                      ref.watch(customDevicePresetsProvider).valueOrEmpty,
                    ),
                    size: 10,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      effectiveDevicePreset(
                        identity?.devicePresetId,
                        ref.watch(customDevicePresetsProvider).valueOrEmpty,
                      ).name,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StateBadge(state: runtime.state),
                ],
                const Spacer(),
                if (!compact &&
                    identity?.isolationMode == IsolationMode.sharedSession)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      context.l10n.notIsolatedBadge,
                      style: const TextStyle(
                        color: Colors.yellow,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: context.l10n.detachToWindowTooltip,
                  iconSize: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  icon: const Icon(Icons.open_in_new, color: Colors.white),
                  onPressed: () => ref
                      .read(workspaceControllerProvider.notifier)
                      .detach(runtime.identityId),
                ),
                IconButton(
                  tooltip: context.l10n.clearIdentityDataTooltip,
                  iconSize: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  icon: const Icon(
                    Icons.cleaning_services,
                    color: Colors.white,
                  ),
                  onPressed: () => ref
                      .read(workspaceControllerProvider.notifier)
                      .clearIdentity(runtime.identityId),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  final WebviewState state;
  const _StateBadge({required this.state});
  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      WebviewState.closed => Colors.grey,
      WebviewState.openingEmbedded => Colors.amber,
      WebviewState.embedded => Colors.greenAccent,
      WebviewState.detaching => Colors.amber,
      WebviewState.detached => Colors.lightBlueAccent,
      WebviewState.attaching => Colors.amber,
      WebviewState.closing => Colors.amber,
      WebviewState.failed => Colors.redAccent,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        state.label(context.l10n),
        style: const TextStyle(color: Colors.white, fontSize: 9),
      ),
    );
  }
}

class _PanelNavToolbar extends ConsumerStatefulWidget {
  final PanelRuntime runtime;

  /// The identity backing this panel — resolved by `_PanelView`. Carries the
  /// persisted `devicePresetId` the device-emulation menu displays and edits.
  final Identity? identity;
  const _PanelNavToolbar({required this.runtime, required this.identity});

  @override
  ConsumerState<_PanelNavToolbar> createState() => _PanelNavToolbarState();
}

/// Compact toolbar button. Plain IconButton enforces a ~48px interactive
/// minimum, which overflows narrow grid/focus panels (8 buttons + URL field).
/// shrinkWrap removes the tap-target floor so the toolbar fits ~300px cells.
const ButtonStyle _navButtonStyle = ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size(24, 24)),
  fixedSize: WidgetStatePropertyAll(Size(24, 24)),
  padding: WidgetStatePropertyAll(EdgeInsets.zero),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

class _PanelNavToolbarState extends ConsumerState<_PanelNavToolbar> {
  late final TextEditingController _urlCtrl;
  bool _mediaMuted = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.runtime.url);
  }

  @override
  void didUpdateWidget(covariant _PanelNavToolbar old) {
    super.didUpdateWidget(old);
    if (old.runtime.url != widget.runtime.url &&
        _urlCtrl.text != widget.runtime.url) {
      _urlCtrl.text = widget.runtime.url;
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = ref.read(workspaceControllerProvider.notifier);
    // Capability UI: the Web Inspector only exists in DEBUG builds, so the
    // button disables itself instead of silently doing nothing.
    final devtoolsEnabled =
        ref.watch(capabilitiesProvider).asData?.value.devtools ?? false;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Row(
        children: [
          IconButton(
            tooltip: l10n.navBack,
            iconSize: 16,
            style: _navButtonStyle,
            icon: const Icon(Icons.arrow_back),
            onPressed: () => controller.back(widget.runtime.identityId),
          ),
          IconButton(
            tooltip: l10n.navForward,
            iconSize: 16,
            style: _navButtonStyle,
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => controller.forward(widget.runtime.identityId),
          ),
          IconButton(
            tooltip: l10n.navStop,
            iconSize: 16,
            style: _navButtonStyle,
            icon: const Icon(Icons.close),
            onPressed: () => controller.stop(widget.runtime.identityId),
          ),
          IconButton(
            tooltip: l10n.navReload,
            iconSize: 16,
            style: _navButtonStyle,
            icon: const Icon(Icons.refresh),
            onPressed: () => controller.reload(widget.runtime.identityId),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextField(
                controller: _urlCtrl,
                style: const TextStyle(fontSize: 11),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (v) =>
                    controller.navigate(widget.runtime.identityId, v),
              ),
            ),
          ),
          _DevicePresetMenu(
            identityId: widget.runtime.identityId,
            currentPresetId:
                widget.identity?.devicePresetId ?? kDefaultDevicePresetId,
          ),
          IconButton(
            tooltip: l10n.devtools,
            iconSize: 16,
            style: _navButtonStyle,
            icon: const Icon(Icons.developer_mode),
            onPressed: devtoolsEnabled
                ? () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final report = await controller.openDevTools(
                      widget.runtime.identityId,
                    );
                    if (!mounted) return;
                    final message =
                        report.howToOpen ??
                        (report.opened
                            ? l10n.devtoolsOpened
                            : l10n.devtoolsUnavailable);
                    messenger.showSnackBar(SnackBar(content: Text(message)));
                  }
                : null,
          ),
          IconButton(
            tooltip: l10n.copyLink,
            iconSize: 16,
            style: _navButtonStyle,
            icon: const Icon(Icons.content_copy),
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: _urlCtrl.text)),
          ),
          IconButton(
            tooltip: _mediaMuted ? l10n.unmuteMedia : l10n.muteMedia,
            iconSize: 16,
            style: _navButtonStyle,
            icon: Icon(
              _mediaMuted ? Icons.volume_off : Icons.volume_up,
              color: _mediaMuted ? Theme.of(context).colorScheme.error : null,
            ),
            onPressed: () async {
              final muted = await controller.toggleMute(
                widget.runtime.identityId,
              );
              if (!mounted) return;
              setState(() => _mediaMuted = muted);
            },
          ),
          IconButton(
            key: ValueKey('measure-mode-${widget.runtime.identityId}'),
            tooltip: l10n.measureMode,
            iconSize: 16,
            style: _navButtonStyle,
            icon: Icon(
              Icons.straighten,
              color: widget.runtime.measureMode
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            onPressed: () =>
                controller.toggleMeasureMode(widget.runtime.identityId),
          ),
          IconButton(
            tooltip: l10n.fullscreenPanel,
            iconSize: 16,
            style: _navButtonStyle,
            icon: const Icon(Icons.fullscreen),
            onPressed: () =>
                controller.toggleFullscreen(widget.runtime.identityId),
          ),
          IconButton(
            tooltip: l10n.closePanel,
            iconSize: 16,
            style: _navButtonStyle,
            icon: const Icon(Icons.cancel_presentation),
            onPressed: () => controller.removePanel(widget.runtime.identityId),
          ),
        ],
      ),
    );
  }
}

/// Per-panel device-emulation switch. Selecting a preset writes it back to
/// the identity record (`WorkspaceController.setDevicePreset`) — persisted,
/// matching the management dialog — and the identity-signature sync rebuilds
/// the panel's WebView under the new UA / viewport / touch surface.
class _DevicePresetMenu extends ConsumerWidget {
  final String identityId;
  final String currentPresetId;
  const _DevicePresetMenu({
    required this.identityId,
    required this.currentPresetId,
  });

  static IconData iconFor(String? presetId, [List<DevicePreset>? custom]) {
    final preset = devicePresetFor(presetId, custom);
    if (preset == null) return Icons.desktop_windows;
    if (preset.mobile) {
      // Tablet-class mobile presets (iPad mini, 768px) get the tablet icon.
      return preset.viewportWidth >= 600 ? Icons.tablet_mac : Icons.smartphone;
    }
    if (preset.id == kCustomDevicePresetId) return Icons.open_in_full;
    if (preset.sizing == ViewportSizing.fixed) return Icons.aspect_ratio;
    return Icons.desktop_windows;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // Live size label for `custom` — like responsive design mode's
    // "Custom (W × H)", it reports the panel's current size.
    final layout = ref.watch(
      workspaceControllerProvider.select((s) => s.panels[identityId]?.layout),
    );
    // User-defined window sizes (persisted in `custom_device_presets`).
    final customs = ref.watch(customDevicePresetsProvider).valueOrEmpty;
    PopupMenuItem<String> item(DevicePreset preset, [String? label]) =>
        PopupMenuItem<String>(
          key: ValueKey('device-preset-item-${preset.id}'),
          value: preset.id,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(iconFor(preset.id, customs), size: 16),
              const SizedBox(width: 8),
              // No Expanded/Flexible here: PopupMenu sizes its route via
              // IntrinsicWidth, and a flexible child collapses the menu
              // to its minimum width. A bounded box + ellipsis keeps the
              // longest "W × H (name)" label inside the 256px popup cap.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  label ?? preset.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (preset.id == currentPresetId) ...[
                const SizedBox(width: 8),
                const Icon(Icons.check, size: 14),
              ],
            ],
          ),
        );
    final custom = devicePresets.firstWhere(
      (p) => p.id == kCustomDevicePresetId,
    );
    final customLabel = layout == null
        ? custom.name
        : '${custom.name} (${layout.width.round()} × '
              '${layout.height.round()})';
    final sizePresets = devicePresets.where(
      (p) => p.sizing == ViewportSizing.fixed,
    );
    final deviceEntries = devicePresets.where(
      (p) => p.sizing != ViewportSizing.fixed && p.id != custom.id,
    );
    return PopupMenuButton<String>(
      key: ValueKey('device-preset-menu-$identityId'),
      tooltip: l10n.devicePresetTooltip,
      iconSize: 16,
      // No `constraints:` here — PopupMenuButton forwards it to the popup
      // route's items too, collapsing the menu width and making entries
      // unhittable. iconSize + zero padding keep the trigger compact.
      padding: EdgeInsets.zero,
      icon: Icon(iconFor(currentPresetId, customs)),
      onSelected: (presetId) {
        if (presetId == _kManageCustomSizes) {
          _showCustomSizesDialog(context, ref);
          return;
        }
        ref
            .read(workspaceControllerProvider.notifier)
            .setDevicePreset(identityId, presetId);
      },
      itemBuilder: (context) => [
        item(custom, customLabel),
        const PopupMenuDivider(),
        for (final preset in sizePresets)
          item(
            preset,
            '${preset.viewportWidth} × ${preset.viewportHeight} '
            '(${preset.name})',
          ),
        if (customs.isNotEmpty) ...[
          const PopupMenuDivider(),
          for (final preset in customs)
            item(
              preset,
              '${preset.viewportWidth} × ${preset.viewportHeight} '
              '(${preset.name})',
            ),
        ],
        const PopupMenuDivider(),
        for (final preset in deviceEntries) item(preset),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          key: const ValueKey('device-preset-manage-custom'),
          value: _kManageCustomSizes,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tune, size: 16),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  l10n.manageCustomSizes,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sentinel menu value that opens the custom-size management dialog instead
/// of selecting a preset.
const String _kManageCustomSizes = '__manage_custom_sizes__';

/// "Custom sizes" manager: lists user-defined presets with delete buttons
/// and a W×H (+ optional name) form to add one.
Future<void> _showCustomSizesDialog(BuildContext context, WidgetRef ref) {
  return showDialog(
    context: context,
    builder: (ctx) => const _CustomSizesDialog(),
  );
}

class _CustomSizesDialog extends ConsumerStatefulWidget {
  const _CustomSizesDialog();

  @override
  ConsumerState<_CustomSizesDialog> createState() => _CustomSizesDialogState();
}

class _CustomSizesDialogState extends ConsumerState<_CustomSizesDialog> {
  final _nameCtrl = TextEditingController();
  final _widthCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  bool _invalid = false;

  static const int _minSide = 120;
  static const int _maxSide = 3840;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final w = int.tryParse(_widthCtrl.text.trim());
    final h = int.tryParse(_heightCtrl.text.trim());
    final ok =
        w != null &&
        h != null &&
        w >= _minSide &&
        w <= _maxSide &&
        h >= _minSide &&
        h <= _maxSide;
    setState(() => _invalid = !ok);
    if (!ok) return;
    final name = _nameCtrl.text.trim();
    final repo = await ref.read(devicePresetRepositoryProvider.future);
    await repo.addCustom(
      id: 'user-${DateTime.now().millisecondsSinceEpoch}',
      name: name.isEmpty ? '$w × $h' : name,
      width: w,
      height: h,
    );
    ref.invalidate(customDevicePresetsProvider);
    _nameCtrl.clear();
    _widthCtrl.clear();
    _heightCtrl.clear();
    if (mounted) setState(() => _invalid = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final customs = ref.watch(customDevicePresetsProvider);
    return AlertDialog(
      title: Text(l10n.manageCustomSizes),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            customs.when(
              data: (list) => list.isEmpty
                  ? const SizedBox.shrink()
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final p in list)
                            ListTile(
                              key: ValueKey('custom-size-${p.id}'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${p.viewportWidth} × '
                                '${p.viewportHeight} (${p.name})',
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                iconSize: 16,
                                icon: const Icon(Icons.delete_outline),
                                tooltip: l10n.delete,
                                onPressed: () async {
                                  final repo = await ref.read(
                                    devicePresetRepositoryProvider.future,
                                  );
                                  await repo.removeCustom(p.id);
                                  ref.invalidate(customDevicePresetsProvider);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: l10n.customSizeName,
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _widthCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: l10n.customSizeWidth,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _heightCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: l10n.customSizeHeight,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            if (_invalid)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.customSizeInvalid(_minSide, _maxSide),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _add, child: Text(l10n.addCustomSize)),
      ],
    );
  }
}

/// The platform-view creation params for a panel. The native factory selects
/// the WKWebsiteDataStore from these: sharedSession -> the shared default
/// store; anything else -> per-identity WKWebsiteDataStore(forIdentifier:).
/// The fingerprint gates native reuse paths so a rebuilt view never keeps a
/// stale store (see ProfiledWebViewPlugin.registerWebView).
///
/// Device emulation fields: `userAgent` maps to `WKWebView.customUserAgent`
/// (nil = desktop default), `touchEmulation` injects the maxTouchPoints /
/// ontouchstart detection surface, and `viewportWidth/Height` size the
/// detached window (the embedded panel's CSS viewport is clamped by
/// `_PanelBody` instead — the platform view is smaller than the panel).
/// For the `custom` preset the panel's own layout size seeds the detached
/// window and `viewportFollowsSurface` keeps it tracking live bounds.
@visibleForTesting
Map<String, Object?> panelCreationParams(
  PanelRuntime runtime, [
  List<DevicePreset>? customPresets,
]) {
  final preset = devicePresetFor(runtime.devicePresetId, customPresets);
  final follows = preset?.id == kCustomDevicePresetId;
  return {
    'identityId': runtime.identityId,
    'url': runtime.url,
    'isolationMode': runtime.isolationMode.dbValue,
    'fingerprint': runtime.fingerprint,
    'userAgent': preset?.userAgent,
    'devicePresetId': runtime.devicePresetId,
    'touchEmulation': preset?.touch ?? false,
    'viewportWidth': preset?.emulatedViewport == true
        ? preset!.viewportWidth
        : (follows ? runtime.layout.width.round() : null),
    'viewportHeight': preset?.emulatedViewport == true
        ? preset!.viewportHeight
        : (follows ? runtime.layout.height.round() : null),
    'viewportFollowsSurface': follows,
  };
}

/// Ruler chrome drawn around the platform view while measure mode is on —
/// kept on the Flutter side so the page's own UI stays unobstructed
/// (the in-page overlay only carries the element highlight + size badge).
/// The child gets the remaining space, subject to the same preset clamp
/// `_PanelBody` applies normally; the letterbox color fills around the
/// unit for viewport-clamped presets. The view shrinks by `rulerExtent`
/// on both axes — DevTools-dock semantics — so the rulers never cover
/// page content and never inject anything into the page DOM.
class _MeasureFramedView extends StatelessWidget {
  final Widget child;
  final DevicePreset? preset;
  const _MeasureFramedView({required this.child, required this.preset});

  static const double rulerExtent = 20;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        final availW = math.max(0.0, cons.maxWidth - rulerExtent);
        final availH = math.max(0.0, cons.maxHeight - rulerExtent);
        final w = preset != null && preset!.sizing != ViewportSizing.free
            ? math.min(preset!.viewportWidth.toDouble(), availW)
            : availW;
        final h = preset?.sizing == ViewportSizing.fixed
            ? math.min(preset!.viewportHeight.toDouble(), availH)
            : availH;
        return ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          child: Center(
            child: SizedBox(
              width: w + rulerExtent,
              height: h + rulerExtent,
              child: Column(
                children: [
                  SizedBox(
                    height: rulerExtent,
                    child: Row(
                      children: [
                        Container(
                          width: rulerExtent,
                          height: rulerExtent,
                          color: const Color(0xFF1B1B1F),
                        ),
                        SizedBox(
                          width: w,
                          height: rulerExtent,
                          child: CustomPaint(
                            painter: _RulerPainter(
                              horizontal: true,
                              label: '${w.round()} × ${h.round()}',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      SizedBox(
                        width: rulerExtent,
                        height: h,
                        child: const CustomPaint(
                          painter: _RulerPainter(horizontal: false),
                        ),
                      ),
                      SizedBox(width: w, height: h, child: child),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints one ruler strip: dark background, 10px minor / 50px mid / 100px
/// major ticks with numeric labels, in CSS pixels (1:1 with the panel's
/// logical pixels). The horizontal ruler additionally hosts the live
/// viewport "W × H" label at its left end.
class _RulerPainter extends CustomPainter {
  final bool horizontal;
  final String? label;
  const _RulerPainter({required this.horizontal, this.label});

  static const _bg = Color(0xFF1B1B1F);
  static const _tick = Color(0xFF55555C);
  static const _text = TextStyle(
    color: Color(0xFF9A9AA0),
    fontSize: 9,
    fontFamily: 'Menlo',
    height: 1,
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _bg);
    final tickPaint = Paint()
      ..color = _tick
      ..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);

    double labelEnd = 0;
    if (horizontal && label != null) {
      tp.text = TextSpan(text: label, style: _text);
      tp.layout();
      canvas.drawRect(
        Rect.fromLTWH(0, 2, tp.width + 12, size.height - 4),
        Paint()..color = const Color(0xFF26262B),
      );
      tp.paint(canvas, const Offset(6, 5));
      labelEnd = tp.width + 12;
    }

    final len = horizontal ? size.width : size.height;
    for (var x = 0.0; x <= len; x += 10) {
      final major = x % 100 == 0;
      final mid = x % 50 == 0;
      final t = major ? 11.0 : (mid ? 7.0 : 4.0);
      if (horizontal) {
        canvas.drawLine(
          Offset(x, size.height),
          Offset(x, size.height - t),
          tickPaint,
        );
        if (major && x >= labelEnd && x + 26 <= len) {
          tp.text = TextSpan(text: '${x.round()}', style: _text);
          tp.layout();
          tp.paint(canvas, Offset(x + 3, 3));
        }
      } else {
        canvas.drawLine(
          Offset(size.width, x),
          Offset(size.width - t, x),
          tickPaint,
        );
        if (major && x + 26 <= len) {
          tp.text = TextSpan(text: '${x.round()}', style: _text);
          tp.layout();
          canvas.save();
          canvas.translate(6, x + 3 + tp.width);
          canvas.rotate(-math.pi / 2);
          tp.paint(canvas, Offset.zero);
          canvas.restore();
        }
      }
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.horizontal != horizontal || old.label != label;
}

/// The embedded WebView body. On macOS uses the native platform view keyed by
/// the runtime fingerprint so config changes reconstruct the WebView. On other
/// platforms (and in widget tests, where the provider is overridden) a
/// placeholder is shown and the platform is recorded as NOT_TESTED.
class _PanelBody extends ConsumerWidget {
  final PanelRuntime runtime;
  const _PanelBody({required this.runtime});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nativeSupported = ref.watch(webviewPlatformSupportedProvider);
    if (!nativeSupported) {
      return Center(
        child: Text(
          context.l10n.webviewNotSupported(Platform.operatingSystem),
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }
    final customs = ref.watch(customDevicePresetsProvider).valueOrEmpty;
    Widget view = AppKitView(
      key: ValueKey(
        'pwv-${runtime.identityId}-${runtime.fingerprint}-n${runtime.viewNonce}',
      ),
      viewType: 'profiled_webview',
      creationParams: panelCreationParams(runtime, customs),
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (viewId) {
        ref
            .read(workspaceControllerProvider.notifier)
            .registerView(runtime.identityId, viewId);
      },
    );
    // Viewport emulation: clamp the platform view to the preset's CSS
    // viewport size so `window.innerWidth` and media queries resolve to the
    // emulated surface even when the outer panel is larger (grid/focus cells
    // typically are). Mobile presets clamp only the width; fixed window-size
    // presets clamp both dimensions. WKWebView on macOS has no CDP-style
    // Emulation.setDeviceMetricsOverride — sizing the view is the honest
    // mechanism; devicePixelRatio always follows the real surface.
    // ConstrainedBox, not LayoutBuilder around an unconstrained view:
    // AppKitView already embeds its own LayoutBuilder, and nesting one here
    // recurses infinitely during layout. `_MeasureFramedView` is safe only
    // because it hands the view a tight, fully-computed size.
    final preset = devicePresetFor(runtime.devicePresetId, customs);
    if (runtime.measureMode) {
      // Measure mode: rulers are Flutter chrome around the view — the view
      // shrinks by the 20px strips (DevTools-dock semantics), so page UI is
      // never covered and the page DOM stays untouched.
      view = _MeasureFramedView(preset: preset, child: view);
    } else if (preset != null && preset.sizing != ViewportSizing.free) {
      view = ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: Center(
          child: ConstrainedBox(
            constraints: preset.sizing == ViewportSizing.fixed
                ? BoxConstraints(
                    maxWidth: preset.viewportWidth.toDouble(),
                    maxHeight: preset.viewportHeight.toDouble(),
                  )
                : BoxConstraints(maxWidth: preset.viewportWidth.toDouble()),
            child: view,
          ),
        ),
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: view),
        if (runtime.loading)
          const Positioned(
            top: 6,
            right: 6,
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }
}
