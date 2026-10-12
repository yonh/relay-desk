/// Workspace controller: the Riverpod state machine the UI calls to drive the
/// concrete WebviewAdapter. It owns per-identity panel runtime state, bounds
/// revision counters, fingerprint tracking, layout mode, and named workspace
/// save/load/delete.
///
/// The UI never calls the adapter directly — it goes through this controller so
/// state stays consistent with platform events (rewrite-plan §4.5/§4.8).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/platform/domain.dart';
import '../../core/platform/webview_adapter.dart';
import '../../core/url_input.dart';
import '../../data/device_presets.dart';
import '../../platform/webview/macos_profiled_webview_adapter.dart';
import '../../platform/webview/headless_webview_adapter.dart';
import 'dart:io' show Platform;

/// Per-identity panel runtime state (the live, in-memory view of a panel).
class PanelRuntime {
  final String identityId;
  final PanelLayout layout;
  final WebviewState state;
  final String url;
  final String fingerprint;

  /// The isolation mode the native WebView was created with. Forwarded into
  /// the AppKitView creationParams so the platform side selects the matching
  /// WKWebsiteDataStore (per-identity store vs the shared default store).
  final IsolationMode isolationMode;
  final bool canGoBack;
  final bool canGoForward;
  final bool loading;
  final int revision;

  /// Bumped to force the embedded platform view to be recreated while the
  /// runtime config (fingerprint) stays the same. Used to self-heal after the
  /// native side tears the WKWebView down (e.g. the user closed a detached
  /// window): without a new AppKitView the panel keeps a dead surface whose
  /// navigate/reload calls go nowhere.
  final int viewNonce;

  /// The identity's device-emulation preset id at the time the panel was
  /// (re)configured. Drives the UA override, mobile viewport clamp, and
  /// touch-surface injection in the platform-view creation params.
  final String? devicePresetId;

  /// The configured start URL (project targetUrl + identity startPath) the
  /// current fingerprint was computed from. Unlike [url] — which tracks the
  /// live page — this does not drift with navigation, so a rebuild can tell
  /// "config URL changed" apart from "only the device preset changed" and
  /// resume the live page in the latter case.
  final String configUrl;

  /// Whether the in-page measure overlay (element highlight + rulers) is
  /// armed on this panel's WebView. Driven by platform
  /// `measureModeChanged` events — including the overlay's own Escape exit
  /// — so it always reflects the real state.
  final bool measureMode;

  const PanelRuntime({
    required this.identityId,
    required this.layout,
    required this.state,
    required this.url,
    required this.fingerprint,
    required this.isolationMode,
    this.canGoBack = false,
    this.canGoForward = false,
    this.loading = false,
    this.revision = 0,
    this.viewNonce = 0,
    this.devicePresetId,
    this.configUrl = '',
    this.measureMode = false,
  });

  PanelRuntime copyWith({
    PanelLayout? layout,
    WebviewState? state,
    String? url,
    String? fingerprint,
    IsolationMode? isolationMode,
    bool? canGoBack,
    bool? canGoForward,
    bool? loading,
    int? revision,
    int? viewNonce,
    String? devicePresetId,
    String? configUrl,
    bool? measureMode,
  }) => PanelRuntime(
    identityId: identityId,
    layout: layout ?? this.layout,
    state: state ?? this.state,
    url: url ?? this.url,
    fingerprint: fingerprint ?? this.fingerprint,
    isolationMode: isolationMode ?? this.isolationMode,
    canGoBack: canGoBack ?? this.canGoBack,
    canGoForward: canGoForward ?? this.canGoForward,
    loading: loading ?? this.loading,
    revision: revision ?? this.revision,
    viewNonce: viewNonce ?? this.viewNonce,
    devicePresetId: devicePresetId ?? this.devicePresetId,
    configUrl: configUrl ?? this.configUrl,
    measureMode: measureMode ?? this.measureMode,
  );
}

/// Immutable workspace state surfaced to the UI.
class WorkspaceState {
  final LayoutMode layoutMode;
  final Map<String, PanelRuntime> panels;

  /// The panel promoted to the primary area in Focus layout.
  final String? selectedPanelId;
  final String? selectedWorkspaceId;
  final String? selectedProjectId;
  const WorkspaceState({
    this.layoutMode = LayoutMode.grid,
    this.panels = const {},
    this.selectedPanelId,
    this.selectedWorkspaceId,
    this.selectedProjectId,
  });

  WorkspaceState copyWith({
    LayoutMode? layoutMode,
    Map<String, PanelRuntime>? panels,
    String? selectedPanelId,
    String? selectedWorkspaceId,
    String? selectedProjectId,
  }) => WorkspaceState(
    layoutMode: layoutMode ?? this.layoutMode,
    panels: panels ?? this.panels,
    selectedPanelId: selectedPanelId ?? this.selectedPanelId,
    selectedWorkspaceId: selectedWorkspaceId ?? this.selectedWorkspaceId,
    selectedProjectId: selectedProjectId ?? this.selectedProjectId,
  );
}

/// Concrete WebviewAdapter singleton. On macOS the real thin native adapter is
/// used; elsewhere a headless adapter keeps the UI testable and degrades
/// gracefully on NOT_TESTED platforms (it never claims isolation).
final webviewAdapterProvider = Provider<WebviewAdapter>((ref) {
  if (Platform.isMacOS) {
    return MacosProfiledWebviewAdapter();
  }
  return HeadlessWebviewAdapter();
});

/// Convenience accessor for the headless adapter in tests.
final headlessAdapterProvider = Provider<HeadlessWebviewAdapter>((ref) {
  return HeadlessWebviewAdapter();
});

/// Whether the current platform embeds a real native WebView (AppKitView on
/// macOS). False on non-macOS and overridable in widget tests so `_PanelBody`
/// renders a placeholder instead of an AppKitView that has no platform view
/// factory under `flutter test`.
final webviewPlatformSupportedProvider = Provider<bool>((ref) {
  return Platform.isMacOS;
});

/// Runtime capabilities probed from the adapter.
final capabilitiesProvider = FutureProvider<RuntimeCapabilities>((ref) async {
  final adapter = ref.watch(webviewAdapterProvider);
  return adapter.probe();
});

/// The workspace controller. Methods are called by the UI; state is rebuilt
/// from platform events and UI actions.
class WorkspaceController extends Notifier<WorkspaceState> {
  StreamSubscription<WebviewEvent>? _eventSub;
  int _projectRestoreGeneration = 0;
  WebviewAdapter get _adapter => ref.read(webviewAdapterProvider);

  /// User-defined window-size presets — resolved through
  /// `devicePresetFor(id, customs)` wherever a stored `devicePresetId`
  /// needs a preset. Read (not watched): panel sizing snapshots the list
  /// at call time; a stale read only misses a preset added mid-action.
  List<DevicePreset> get _customPresets =>
      ref.read(customDevicePresetsProvider).valueOrEmpty;

  @override
  WorkspaceState build() {
    _eventSub = _adapter.events.listen(_onEvent);
    ref.onDispose(() => _eventSub?.cancel());
    return const WorkspaceState();
  }

  void _onEvent(WebviewEvent event) {
    final panels = Map<String, PanelRuntime>.from(state.panels);
    final existing = panels[event.identityId];
    if (existing == null) return;
    switch (event) {
      case WebviewStateChanged(:final state):
        if (state == WebviewState.closed &&
            existing.state == WebviewState.detached) {
          // The user closed the detached window: the native side tore the
          // WKWebView down. Rebuild the platform view so the panel re-embeds
          // and reloads its last URL instead of keeping a dead surface whose
          // navigate/reload calls spin forever. (Bumping viewNonce changes
          // the AppKitView ValueKey, which recreates the platform view.)
          panels[event.identityId] = existing.copyWith(
            state: WebviewState.openingEmbedded,
            viewNonce: existing.viewNonce + 1,
          );
        } else {
          panels[event.identityId] = existing.copyWith(state: state);
        }
        break;
      case WebviewLoadStarted(:final uri):
        panels[event.identityId] = existing.copyWith(
          url: uri.toString(),
          loading: true,
        );
        break;
      case WebviewLoadCommitted(
        :final uri,
        :final canGoBack,
        :final canGoForward,
      ):
        // The main document committed: the URL/history flags are already
        // real, but the page keeps loading until didFinish/didFail.
        panels[event.identityId] = existing.copyWith(
          url: uri.toString(),
          canGoBack: canGoBack,
          canGoForward: canGoForward,
        );
        break;
      case WebviewLoadComplete(
        :final uri,
        :final canGoBack,
        :final canGoForward,
      ):
        panels[event.identityId] = existing.copyWith(
          url: uri.toString(),
          loading: false,
          canGoBack: canGoBack,
          canGoForward: canGoForward,
        );
        break;
      case WebviewUrlChanged(:final uri, :final canGoBack, :final canGoForward):
        panels[event.identityId] = existing.copyWith(
          url: uri.toString(),
          canGoBack: canGoBack,
          canGoForward: canGoForward,
        );
        break;
      case WebviewNavigationBlocked():
        panels[event.identityId] = existing.copyWith(loading: false);
        break;
      case WebviewMeasureModeChanged(:final enabled):
        panels[event.identityId] = existing.copyWith(measureMode: enabled);
        break;
    }
    state = state.copyWith(panels: panels);
  }

  // ---- project / panel lifecycle ----

  /// Open a panel for an identity if not already open, or reconstruct the
  /// WebView if the immutable runtime config (fingerprint) changed.
  PanelRuntimeConfig ensurePanel(Identity identity, Project project) {
    final url = _computeUrl(project, identity);
    final preset = devicePresetFor(identity.devicePresetId, _customPresets);
    final config = PanelRuntimeConfig(
      identityId: identity.id,
      url: url,
      isolationMode: identity.isolationMode,
      userAgent: preset?.userAgent,
      devicePresetId: identity.devicePresetId,
    );
    final existing = state.panels[identity.id];
    if (existing != null && existing.fingerprint == config.fingerprint) {
      return config;
    }
    // Fingerprint changed (or first open): reconstruct.
    final panels = Map<String, PanelRuntime>.from(state.panels);
    if (existing != null) {
      // Best-effort close of the old view before reopening.
      _adapter.close(identity.id);
    }
    _adapter.openEmbedded(config, _defaultBounds(identity.id));
    // A rebuild triggered by a non-URL config change (e.g. switching the
    // device preset or isolation mode while testing a page) resumes the
    // page the panel is currently on — destroying the tested page on every
    // emulation toggle would defeat the feature's purpose. A change to the
    // configured start URL itself (project targetUrl / startPath edit)
    // still loads the new start URL.
    final openUrl =
        existing != null && existing.configUrl == url && existing.url.isNotEmpty
        ? existing.url
        : url;
    final layout =
        existing?.layout ??
        _defaultPanelLayout(
          identity.id,
          state.layoutMode,
          state.panels.length,
          preset: preset,
        );
    panels[identity.id] = PanelRuntime(
      identityId: identity.id,
      layout: layout,
      state: WebviewState.openingEmbedded,
      url: openUrl,
      configUrl: url,
      fingerprint: config.fingerprint,
      isolationMode: identity.isolationMode,
      devicePresetId: identity.devicePresetId,
    );
    state = state.copyWith(
      panels: panels,
      selectedPanelId: state.selectedPanelId ?? identity.id,
      selectedProjectId: project.id,
    );
    return config;
  }

  /// Register a freshly-created platform view (called from AppKitView
  /// onPlatformViewCreated). The adapter links the viewId; we just record that
  /// the panel is now embedded.
  void registerView(String identityId, int viewId) {
    final adapter = _adapter;
    if (adapter is MacosProfiledWebviewAdapter) {
      adapter.registerView(identityId, viewId);
    } else if (adapter is HeadlessWebviewAdapter) {
      adapter.registerView(identityId, viewId);
    }
    final panels = Map<String, PanelRuntime>.from(state.panels);
    final existing = panels[identityId];
    if (existing != null) {
      panels[identityId] = existing.copyWith(state: WebviewState.embedded);
      state = state.copyWith(panels: panels);
    }
  }

  void removePanel(String identityId) {
    _adapter.close(identityId);
    final panels = Map<String, PanelRuntime>.from(state.panels);
    panels.remove(identityId);
    state = WorkspaceState(
      layoutMode: state.layoutMode,
      panels: panels,
      selectedPanelId: state.selectedPanelId == identityId
          ? (panels.isEmpty ? null : panels.keys.first)
          : state.selectedPanelId,
      selectedWorkspaceId: state.selectedWorkspaceId,
      selectedProjectId: state.selectedProjectId,
    );
  }

  // ---- layout mode ----

  Future<void> setLayoutMode(LayoutMode mode) async {
    final panels = Map<String, PanelRuntime>.from(state.panels);
    if (mode == LayoutMode.grid || mode == LayoutMode.columns) {
      // Reflow into the target layout. Preserve each panel's identityId so the
      // layout can be saved (the repository verifies panel.identityId belongs
      // to the project).
      final ids = panels.keys.toList();
      for (var i = 0; i < ids.length; i++) {
        final preset = devicePresetFor(
          panels[ids[i]]!.devicePresetId,
          _customPresets,
        );
        final layout = mode == LayoutMode.grid
            ? _gridPanelLayout(ids[i], i, ids.length, preset: preset)
            : _columnPanelLayout(ids[i], i, ids.length, preset: preset);
        panels[ids[i]] = panels[ids[i]]!.copyWith(layout: layout);
      }
    }
    state = state.copyWith(layoutMode: mode, panels: panels);
    final projectId = state.selectedProjectId;
    if (projectId == null) return;
    try {
      final repo = await ref.read(projectRepositoryProvider.future);
      await repo.updateDefaultLayoutMode(projectId, mode);
    } catch (_) {
      // The layout has already changed locally. A transient persistence error
      // must not interrupt the user's current workspace interaction.
    }
  }

  /// Applies the persisted layout preference for [projectId] before that
  /// project's panels are opened. The generation check prevents a delayed
  /// read for a project the user has already left from overwriting the newer
  /// project's layout.
  Future<void> restoreProjectLayoutMode(String projectId) async {
    final generation = ++_projectRestoreGeneration;
    final repo = await ref.read(projectRepositoryProvider.future);
    final project = await repo.getById(projectId);
    if (project == null ||
        generation != _projectRestoreGeneration ||
        ref.read(selectedProjectIdProvider) != projectId) {
      return;
    }
    state = WorkspaceState(
      layoutMode: project.defaultLayoutMode,
      panels: state.panels,
      selectedPanelId: state.selectedPanelId,
      selectedProjectId: projectId,
      selectedWorkspaceId: null,
    );
  }

  /// Promotes a panel to the primary position when Focus layout is active.
  void selectPanel(String identityId) {
    if (!state.panels.containsKey(identityId)) return;
    state = state.copyWith(selectedPanelId: identityId);
  }

  // ---- bounds / revision ----

  /// Update bounds for a panel with a monotonic revision. Stale revisions are
  /// dropped by the adapter. Set `finalCommit` to ensure this update carries a
  /// new (non-stale) revision even if values are unchanged.
  void updateBounds(
    String identityId,
    PanelLayout layout, {
    bool finalCommit = false,
  }) {
    final panels = Map<String, PanelRuntime>.from(state.panels);
    final existing = panels[identityId];
    if (existing == null) return;
    final nextRevision = existing.revision + 1;
    panels[identityId] = existing.copyWith(
      layout: layout,
      revision: nextRevision,
    );
    state = state.copyWith(panels: panels);
    _adapter.updateBounds(
      identityId,
      nextRevision,
      NativeBounds(layout.x, layout.y, layout.width, layout.height),
    );
  }

  // ---- navigation ----

  void navigate(String identityId, String input) {
    final url = normalizeUrlInput(input);
    final uri = url == null ? null : Uri.tryParse(url);
    if (url == null || uri == null) return;
    final panels = Map<String, PanelRuntime>.from(state.panels);
    final existing = panels[identityId];
    if (existing == null) return;
    panels[identityId] = existing.copyWith(url: url, loading: true);
    state = state.copyWith(panels: panels);
    _adapter.navigate(identityId, uri);
  }

  void back(String identityId) =>
      _adapter.browserAction(identityId, BrowserAction.back);
  void forward(String identityId) =>
      _adapter.browserAction(identityId, BrowserAction.forward);

  /// Routes a mouse side button (X1=back / X2=forward) to the currently
  /// active panel ([selectedPanelId]). Foreground-only: the caller must be a
  /// Flutter pointer handler, so no OS-level background hook is involved.
  /// Returns true if an action was forwarded, false when there was no active
  /// panel (or it is already closed/failed) and the press must be ignored.
  /// Detached panels are allowed: their native view is still live in the
  /// detached window. The native side treats goBack/goForward as a safe
  /// no-op when history does not allow it, so no canGo guard here.
  bool backActive() => _browserActionActive(BrowserAction.back);
  bool forwardActive() => _browserActionActive(BrowserAction.forward);

  /// Cmd+R pressed while Flutter chrome holds keyboard focus: reload the
  /// active panel ([selectedPanelId]). When a page's WKWebView holds the
  /// window's first responder instead, ProfiledWebView handles Cmd+R
  /// natively and this is never reached.
  bool reloadActive() {
    final activeId = state.selectedPanelId;
    if (activeId == null) return false;
    final panel = state.panels[activeId];
    if (panel == null) return false;
    switch (panel.state) {
      case WebviewState.closed:
      case WebviewState.closing:
      case WebviewState.failed:
        return false;
      case WebviewState.openingEmbedded:
      case WebviewState.embedded:
      case WebviewState.detaching:
      case WebviewState.detached:
      case WebviewState.attaching:
        break;
    }
    reload(activeId);
    return true;
  }

  bool _browserActionActive(BrowserAction action) {
    final activeId = state.selectedPanelId;
    if (activeId == null) return false;
    final panel = state.panels[activeId];
    if (panel == null) return false;
    switch (panel.state) {
      case WebviewState.closed:
      case WebviewState.closing:
      case WebviewState.failed:
        return false;
      case WebviewState.openingEmbedded:
      case WebviewState.embedded:
      case WebviewState.detaching:
      case WebviewState.detached:
      case WebviewState.attaching:
        break;
    }
    _adapter.browserAction(activeId, action);
    return true;
  }

  void stop(String identityId) {
    // Unlatch the spinner immediately: stop is a user abort, and when the
    // WebKit pipeline is wedged the native loadFailed callback may never
    // arrive — the loading flag cannot wait for it.
    final panels = Map<String, PanelRuntime>.from(state.panels);
    final existing = panels[identityId];
    if (existing != null && existing.loading) {
      panels[identityId] = existing.copyWith(loading: false);
      state = state.copyWith(panels: panels);
    }
    _adapter.browserAction(identityId, BrowserAction.stop);
  }

  void reload(String identityId) {
    final panels = Map<String, PanelRuntime>.from(state.panels);
    final existing = panels[identityId];
    if (existing == null) return;
    panels[identityId] = existing.copyWith(loading: true);
    state = state.copyWith(panels: panels);
    _adapter.reload(identityId);
  }

  Future<DevToolsReport> openDevTools(String identityId) =>
      _adapter.openDevTools(identityId);

  Future<bool> toggleMute(String identityId) => _adapter.toggleMute(identityId);

  /// Toggle the in-page measure overlay. The applied state flows back via
  /// `WebviewMeasureModeChanged` into `PanelRuntime.measureMode` — the UI
  /// reflects the platform's answer (and the overlay's own Escape exit),
  /// not the button press. While detached, the view lives in its own window
  /// the Flutter ruler chrome cannot reach, so the overlay draws its rulers
  /// inside the page instead.
  Future<void> toggleMeasureMode(String identityId) async {
    final panel = state.panels[identityId];
    if (panel == null) return;
    await _adapter.setMeasureMode(
      identityId,
      !panel.measureMode,
      inPageRulers: panel.state == WebviewState.detached,
    );
  }

  void toggleFullscreen(String identityId) =>
      _adapter.toggleFullscreen(identityId);

  // ---- embedded/detached state machine ----

  void detach(String identityId) => _adapter.detach(identityId);
  void attach(String identityId) =>
      _adapter.attach(identityId, _defaultBounds(identityId));

  // ---- device emulation ----

  /// Persist a new device preset for [identityId] — the panel toolbar quick
  /// switch writes back to the identity record, same as editing the preset
  /// in the management dialog. The `_identitySignature` sync path then sees
  /// the changed `devicePresetId` and routes it through the normal
  /// fingerprint-rebuild in `ensurePanel`, recreating the panel's WebView
  /// under the new UA / viewport / touch surface while resuming the live
  /// page (see [ensurePanel]'s openUrl rule).
  Future<void> setDevicePreset(String identityId, String presetId) async {
    if (!isValidDevicePresetId(presetId)) return;
    final repo = await ref.read(identityRepositoryProvider.future);
    final identity = await repo.getById(identityId);
    if (identity == null || identity.devicePresetId == presetId) return;
    await repo.update(identity.copyWith(devicePresetId: presetId));
    ref.invalidate(identitiesProvider(identity.projectId));
  }

  // ---- identity clear ----

  Future<void> clearIdentity(String identityId) async {
    final adapter = _adapter;
    if (adapter is MacosProfiledWebviewAdapter) {
      await adapter.clearIdentityData(identityId);
      await _adapter.reload(identityId);
    }
  }

  // ---- named workspaces ----

  Future<void> saveWorkspace(String name) async {
    final projectId = state.selectedProjectId;
    if (projectId == null) return;
    final repo = await ref.read(workspaceRepositoryProvider.future);
    final id = state.selectedWorkspaceId ?? repo.generateId();
    final now = DateTime.now().millisecondsSinceEpoch;
    final workspace = WorkspaceLayout(
      id: id,
      projectId: projectId,
      name: name,
      layoutMode: state.layoutMode,
      updatedAt: now,
      panels: state.panels.values
          .map(
            (p) =>
                p.layout.copyWith(detached: p.state == WebviewState.detached),
          )
          .toList(),
    );
    await repo.save(workspace);
    ref.invalidate(workspacesProvider(projectId));
    state = state.copyWith(selectedWorkspaceId: id);
  }

  Future<void> loadWorkspace(String id) async {
    final repo = await ref.read(workspaceRepositoryProvider.future);
    final ws = await repo.getById(id);
    if (ws == null) return;
    final projectId = ws.projectId;
    final identityRepo = await ref.read(identityRepositoryProvider.future);
    final identities = await identityRepo.getByProject(projectId);
    final identityById = {for (final i in identities) i.id: i};
    final projectRepo = await ref.read(projectRepositoryProvider.future);
    final project = await projectRepo.getById(projectId);
    if (project == null) return;

    // A workspace is a layout snapshot, not a browser-session snapshot. When
    // loading a workspace for the current project, preserve every live
    // WebView, its current URL/history, native viewId, and loading state. The
    // previous close/reopen flow removed the native viewId while Flutter kept
    // the same AppKitView element, leaving a permanently blank panel that
    // reload could no longer address.
    final sameProject = state.selectedProjectId == projectId;
    final panels = sameProject
        ? Map<String, PanelRuntime>.from(state.panels)
        : <String, PanelRuntime>{};
    if (!sameProject) {
      for (final identityId in state.panels.keys.toList()) {
        await _adapter.close(identityId);
      }
    }

    for (final panel in ws.panels) {
      final identity = identityById[panel.identityId];
      if (identity == null) continue;
      final url = _computeUrl(project, identity);
      final preset = devicePresetFor(identity.devicePresetId, _customPresets);
      final config = PanelRuntimeConfig(
        identityId: identity.id,
        url: url,
        isolationMode: identity.isolationMode,
        userAgent: preset?.userAgent,
        devicePresetId: identity.devicePresetId,
      );
      final existing = panels[identity.id];
      if (existing != null && existing.fingerprint == config.fingerprint) {
        panels[identity.id] = existing.copyWith(layout: panel);

        if (panel.detached && existing.state == WebviewState.embedded) {
          await _adapter.detach(identity.id);
        } else if (!panel.detached && existing.state == WebviewState.detached) {
          await _adapter.attach(
            identity.id,
            NativeBounds(panel.x, panel.y, panel.width, panel.height),
          );
        }
      } else {
        if (existing != null) {
          await _adapter.close(identity.id);
        }
        await _adapter.openEmbedded(
          config,
          NativeBounds(panel.x, panel.y, panel.width, panel.height),
        );
        // Same resume rule as ensurePanel: a preset/isolation rebuild keeps
        // the page under test; a start-URL change loads the new start URL.
        final openUrl =
            existing != null &&
                existing.configUrl == url &&
                existing.url.isNotEmpty
            ? existing.url
            : url;
        panels[identity.id] = PanelRuntime(
          identityId: identity.id,
          layout: panel,
          state: WebviewState.openingEmbedded,
          url: openUrl,
          configUrl: url,
          fingerprint: config.fingerprint,
          isolationMode: identity.isolationMode,
          devicePresetId: identity.devicePresetId,
        );
      }
    }

    final previousSelectedPanelId = state.selectedPanelId;
    state = WorkspaceState(
      layoutMode: ws.layoutMode,
      panels: panels,
      selectedPanelId:
          previousSelectedPanelId != null &&
              panels.containsKey(previousSelectedPanelId)
          ? previousSelectedPanelId
          : panels.keys.firstOrNull,
      selectedWorkspaceId: id,
      selectedProjectId: projectId,
    );
    ref.read(selectedProjectIdProvider.notifier).select(projectId);
  }

  Future<void> deleteWorkspace(String id) async {
    final repo = await ref.read(workspaceRepositoryProvider.future);
    await repo.delete(id);
    if (state.selectedProjectId != null) {
      ref.invalidate(workspacesProvider(state.selectedProjectId!));
    }
    if (state.selectedWorkspaceId == id) {
      state = state.copyWith(selectedWorkspaceId: null);
    }
  }

  // ---- helpers ----

  String _computeUrl(Project project, Identity identity) {
    final base = normalizeUrlInput(project.targetUrl) ?? project.targetUrl;
    final startPath = identity.startPath;
    final uri = Uri.tryParse(base);
    if (uri == null) return base;
    return uri.resolve(startPath).toString();
  }

  NativeBounds _defaultBounds(String identityId) =>
      const NativeBounds(0, 0, 400, 300);

  /// Preferred panel body size for a preset. Fixed window-size presets
  /// open at the preset size plus ~96px of panel chrome (header + nav
  /// toolbar) so the view starts at the emulated viewport — this must win
  /// over the mobile branch, since a fixed mobile device (e.g. iPhone 14
  /// Pro Max, 430x932) letterboxed inside a 375-wide panel would never
  /// reach its promised resolution. Mobile width-only presets keep the
  /// Tauri baseline's phone-shaped 375x700; everything else falls back to
  /// the caller's default cell size.
  ({double width, double height}) _preferredPanelSize(
    DevicePreset? preset, {
    double fallbackWidth = 480,
    double fallbackHeight = 360,
  }) {
    if (preset?.sizing == ViewportSizing.fixed) {
      return (
        width: preset!.viewportWidth.toDouble(),
        height: preset.viewportHeight + 96,
      );
    }
    if (preset?.mobile == true) return (width: 375, height: 700);
    return (width: fallbackWidth, height: fallbackHeight);
  }

  /// Default layout for a freshly opened panel. Mobile/fixed presets get
  /// preset-shaped defaults, everything else keeps the existing cell. The
  /// CSS viewport the page sees is additionally clamped in `_PanelBody`, so
  /// grid/focus cells also render at the emulated size.
  PanelLayout _defaultPanelLayout(
    String identityId,
    LayoutMode mode,
    int index, {
    DevicePreset? preset,
  }) {
    if (mode == LayoutMode.grid) {
      return _gridPanelLayout(
        identityId,
        index,
        state.panels.length + 1,
        preset: preset,
      );
    }
    if (mode == LayoutMode.columns) {
      return _columnPanelLayout(
        identityId,
        index,
        state.panels.length + 1,
        preset: preset,
      );
    }
    // Canvas: stagger.
    final size = _preferredPanelSize(preset);
    return PanelLayout(
      identityId: identityId,
      x: 40.0 + index * 30,
      y: 40.0 + index * 30,
      width: size.width,
      height: size.height,
    );
  }

  /// Grid cell layout for [index] of [total] panels. The identityId is
  /// preserved so the layout can be persisted (the repository verifies panel
  /// identity ownership); the x/y are computed from a square-ish grid so a
  /// saved grid layout is also restorable in canvas mode.
  PanelLayout _gridPanelLayout(
    String identityId,
    int index,
    int total, {
    DevicePreset? preset,
  }) {
    final cols = total <= 1 ? 1 : (total <= 4 ? 2 : 3);
    final row = index ~/ cols;
    final col = index % cols;
    final size = _preferredPanelSize(preset);
    return PanelLayout(
      identityId: identityId,
      x: col * 480.0,
      y: row * 360.0,
      width: size.width,
      height: size.height,
    );
  }

  /// Column layout for [index] of [total] panels: each panel is one vertical
  /// column side by side, full height. The x/y are computed so a saved column
  /// layout is also restorable in canvas mode.
  PanelLayout _columnPanelLayout(
    String identityId,
    int index,
    int total, {
    DevicePreset? preset,
  }) {
    final colWidth = total > 0 ? (1440.0 / total) : 480.0;
    final size = _preferredPanelSize(
      preset,
      fallbackWidth: colWidth,
      fallbackHeight: 900,
    );
    return PanelLayout(
      identityId: identityId,
      x: index * colWidth,
      y: 0,
      width: size.width,
      height: size.height,
    );
  }
}

final workspaceControllerProvider =
    NotifierProvider<WorkspaceController, WorkspaceState>(
      WorkspaceController.new,
    );
