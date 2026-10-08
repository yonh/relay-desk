/// P0 read-only metadata queries for the local automation transport.
/// Implements the contract in design/automation-roadmap.md "P0 协议 v1：读取".
///
/// Every operation is a pure read: repositories, UI selection, browser
/// profiles and native windows are never mutated here. All workspace and
/// native data enters through injected snapshot callbacks so the query layer
/// stays testable and free of provider/global state.
library;

import '../../core/platform/domain.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/workspace_repository.dart';
import '../workspace/workspace_controller.dart';
import 'automation_server.dart';

/// Read-only dispatcher for `POST /v1/command` payloads.
///
/// The native snapshot callback returns:
/// ```
/// {
///   currentWindowId: int|null, mainWindowId: int|null,
///   windows: [{windowId, title, isKey, isMain, isVisible, isMiniaturized,
///              bounds: {x, y, width, height}}],
///   views: [{viewId, identityId, windowId: int|null, hasKeyboardFocus}],
/// }
/// ```
class AutomationQueries {
  AutomationQueries({
    required this.projects,
    required this.identities,
    required this.workspaces,
    required this.readWorkspace,
    required this.readSelectedProjectId,
    required this.readNativeWindows,
  });

  final ProjectRepository projects;
  final IdentityRepository identities;
  final WorkspaceRepository workspaces;

  /// Live immutable workspace snapshot (panels, selection, layout mode).
  final WorkspaceState Function() readWorkspace;

  /// The project the UI has selected. This is the only current-project
  /// source; `WorkspaceState.selectedProjectId` can lag a project switch.
  final String? Function() readSelectedProjectId;

  /// One-shot native window/view inventory sampled by the platform side.
  final Future<Map<String, dynamic>> Function() readNativeWindows;

  Future<Object?> dispatch(Map<String, dynamic> command) async {
    final op = command['op'];
    if (op is! String) {
      throw const AutomationFailure('invalid_argument', 'op must be a string');
    }
    if (!automationReadOperations.contains(op)) {
      throw const AutomationFailure(
        'unsupported_operation',
        'P0 only serves read operations',
      );
    }
    switch (op) {
      case 'capabilities':
        return _capabilities();
      case 'state':
        return _state();
      case 'projects':
        final all = await projects.getAll();
        return {
          'projects': [for (final p in all) _projectJson(p)],
        };
      case 'project':
        return _project(command);
      case 'identities':
        return _identities(command);
      case 'identity':
        return _identity(command);
      case 'panels':
        return _panels(command);
      case 'panel':
        return _panel(command);
      case 'windows':
        return _windowsJson(await readNativeWindows());
      case 'window':
        return _window(command);
      case 'workspaces':
        return _workspaces(command);
      case 'workspace':
        return _workspace(command);
    }
    throw const AutomationFailure(
      'unsupported_operation',
      'P0 only serves read operations',
    );
  }

  // ---- operations ----

  Map<String, Object?> _capabilities() => {
    'protocolVersion': 1,
    'readOnly': true,
    'engine': 'WKWebView',
    'operations': automationReadOperations.toList(),
    'limitations': {
      'dom': false,
      'screenshot': false,
      'eval': false,
      'actions': false,
      'console': false,
      'network': false,
      'cdp': false,
    },
  };

  /// Reads the UI selection sources together, without awaiting between them.
  ///
  /// Every operation that combines the selected project with the workspace
  /// snapshot captures both here first: `selectedProjectId` and
  /// `WorkspaceState` describe one moment, and re-reading either after an await
  /// could pair a new project with a stale panel selection.
  ({WorkspaceState workspace, String? projectId}) _captureUiState() =>
      (workspace: readWorkspace(), projectId: readSelectedProjectId());

  Future<Map<String, Object?>> _state() async {
    final ui = _captureUiState();
    final workspace = ui.workspace;
    final projectId = ui.projectId;
    final native = await readNativeWindows();
    final views = _nativeList(native, 'views');
    final selection = await _selection(workspace, projectId);
    final project = projectId == null
        ? null
        : await projects.getById(projectId);
    final selectedPanel = selection.consistent
        ? workspace.panels[workspace.selectedPanelId]
        : null;
    return {
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'project': project == null ? null : _projectJson(project),
      'identity': selection.identity == null
          ? null
          : _identityJson(selection.identity!),
      'panel': selectedPanel == null
          ? null
          : await _panelJson(selectedPanel, workspace, views),
      'window': _windowJsonOrNull(_keyWindow(native), views),
      'workspaceId': await _currentWorkspaceId(workspace, projectId),
      'layoutMode': workspace.layoutMode.name,
      'selectedIdentityId': workspace.selectedPanelId,
      'focusedIdentityId': _focusedIdentityId(views),
      'selectionConsistent': selection.consistent,
    };
  }

  Future<Map<String, Object?>> _project(Map<String, dynamic> command) async {
    final id = _optionalString(command, 'projectId');
    if (id != null) {
      final project = await projects.getById(id);
      if (project == null) throw _notFound('project');
      return {'project': _projectJson(project)};
    }
    final currentId = readSelectedProjectId();
    if (currentId == null) return {'project': null};
    final project = await projects.getById(currentId);
    return {'project': project == null ? null : _projectJson(project)};
  }

  Future<Map<String, Object?>> _identities(Map<String, dynamic> command) async {
    final explicit = _optionalString(command, 'projectId');
    final id = explicit ?? readSelectedProjectId();
    if (id == null) {
      return {'projectId': null, 'identities': <Object?>[]};
    }
    if (explicit != null && await projects.getById(id) == null) {
      throw _notFound('project');
    }
    final list = await identities.getByProject(id);
    return {
      'projectId': id,
      'identities': [for (final i in list) _identityJson(i)],
    };
  }

  Future<Map<String, Object?>> _identity(Map<String, dynamic> command) async {
    final id = _optionalString(command, 'identityId');
    if (id != null) {
      final identity = await identities.getById(id);
      if (identity == null) throw _notFound('identity');
      return {'identity': _identityJson(identity)};
    }
    final ui = _captureUiState();
    final selection = await _selection(ui.workspace, ui.projectId);
    return {
      'identity': selection.identity == null
          ? null
          : _identityJson(selection.identity!),
    };
  }

  Future<Map<String, Object?>> _panels(Map<String, dynamic> command) async {
    final projectId = _optionalString(command, 'projectId');
    if (projectId != null && await projects.getById(projectId) == null) {
      throw _notFound('project');
    }
    final workspace = readWorkspace();
    final native = await readNativeWindows();
    final views = _nativeList(native, 'views');
    final result = <Map<String, Object?>>[];
    for (final panel in workspace.panels.values) {
      if (projectId != null) {
        final identity = await identities.getById(panel.identityId);
        if (identity?.projectId != projectId) continue;
      }
      result.add(await _panelJson(panel, workspace, views));
    }
    return {'panels': result};
  }

  Future<Map<String, Object?>> _panel(Map<String, dynamic> command) async {
    final ui = _captureUiState();
    final workspace = ui.workspace;
    final native = await readNativeWindows();
    final views = _nativeList(native, 'views');
    final id = _optionalString(command, 'identityId');
    if (id != null) {
      final panel = workspace.panels[id];
      if (panel == null) throw _notFound('panel');
      return {'panel': await _panelJson(panel, workspace, views)};
    }
    final selection = await _selection(workspace, ui.projectId);
    final panel = selection.consistent
        ? workspace.panels[workspace.selectedPanelId]
        : null;
    return {
      'panel': panel == null ? null : await _panelJson(panel, workspace, views),
    };
  }

  Future<Map<String, Object?>> _window(Map<String, dynamic> command) async {
    final raw = command['windowId'];
    int? id;
    if (raw != null) {
      if (raw is! int) {
        throw const AutomationFailure(
          'invalid_argument',
          'windowId must be an integer',
        );
      }
      id = raw;
    }
    final native = await readNativeWindows();
    final views = _nativeList(native, 'views');
    if (id != null) {
      final window = _windowList(
        native,
      ).where((w) => w['windowId'] == id).firstOrNull;
      if (window == null) throw _notFound('window');
      return {'window': _windowJson(window, views)};
    }
    // The current window is the one the native side sampled as current — never
    // a mainWindow fallback. No current window is a legal state and null.
    return {'window': _windowJsonOrNull(_keyWindow(native), views)};
  }

  Future<Map<String, Object?>> _workspaces(Map<String, dynamic> command) async {
    final explicit = _optionalString(command, 'projectId');
    final id = explicit ?? readSelectedProjectId();
    if (id == null) {
      return {'projectId': null, 'workspaces': <Object?>[]};
    }
    if (explicit != null && await projects.getById(id) == null) {
      throw _notFound('project');
    }
    final list = await workspaces.getByProject(id);
    return {
      'projectId': id,
      'workspaces': [for (final w in list) _workspaceJson(w)],
    };
  }

  Future<Map<String, Object?>> _workspace(Map<String, dynamic> command) async {
    final id = _optionalString(command, 'workspaceId');
    if (id != null) {
      // An explicit workspaceId addresses the row itself and stays valid even
      // when it belongs to a project the UI has since left.
      final workspace = await workspaces.getById(id);
      if (workspace == null) throw _notFound('workspace');
      return {'workspace': _workspaceJson(workspace)};
    }
    final ui = _captureUiState();
    final saved = await _savedWorkspaceFor(
      ui.projectId,
      ui.workspace.selectedWorkspaceId,
    );
    return {'workspace': saved == null ? null : _workspaceJson(saved)};
  }

  /// The saved workspace the UI has loaded, only when it belongs to the
  /// currently selected project. A layout left loaded across a project switch
  /// is not the current project's named workspace, so it reads as absent.
  Future<WorkspaceLayout?> _savedWorkspaceFor(
    String? projectId,
    String? workspaceId,
  ) async {
    if (projectId == null || workspaceId == null) return null;
    final saved = await workspaces.getById(workspaceId);
    return saved != null && saved.projectId == projectId ? saved : null;
  }

  Future<String?> _currentWorkspaceId(
    WorkspaceState workspace,
    String? projectId,
  ) async =>
      (await _savedWorkspaceFor(projectId, workspace.selectedWorkspaceId))?.id;

  // ---- selection ----

  /// The UI-selected identity, or null when the selection is empty or stale.
  /// A selected identity that does not belong to the currently selected UI
  /// project, or that has no panel in [workspace], is reported as inconsistent
  /// rather than impersonated.
  ///
  /// [projectId] is the project captured together with [workspace]; passing
  /// the captured value keeps a project switch that lands mid-query from
  /// turning the answer into a claim about the new project.
  Future<({Identity? identity, bool consistent})> _selection(
    WorkspaceState workspace,
    String? projectId,
  ) async {
    final selectedId = workspace.selectedPanelId;
    if (selectedId == null) {
      return (identity: null, consistent: true);
    }
    if (!workspace.panels.containsKey(selectedId)) {
      return (identity: null, consistent: false);
    }
    final identity = await identities.getById(selectedId);
    if (identity == null || identity.projectId != projectId) {
      return (identity: null, consistent: false);
    }
    return (identity: identity, consistent: true);
  }

  String? _focusedIdentityId(List<Map<String, dynamic>> views) {
    for (final view in views) {
      if (view['hasKeyboardFocus'] == true) {
        return view['identityId'] as String?;
      }
    }
    return null;
  }

  // ---- native snapshot helpers ----

  List<Map<String, dynamic>> _nativeList(
    Map<String, dynamic> native,
    String key,
  ) {
    final raw = native[key];
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (entry is Map) Map<String, dynamic>.from(entry),
    ];
  }

  List<Map<String, dynamic>> _windowList(Map<String, dynamic> native) =>
      _nativeList(native, 'windows');

  /// The current window, identified solely by the native `currentWindowId`
  /// sample.
  ///
  /// `isKey` is deliberately never consulted: an NSWindow can still report
  /// `isKey == true` after the app has lost key status, and honouring that
  /// stale flag would report a window the user is no longer focused on. A null
  /// `currentWindowId` therefore means "no current window" even when a
  /// window claims to be key, and there is never a main-window fallback.
  Map<String, dynamic>? _keyWindow(Map<String, dynamic> native) {
    final currentId = native['currentWindowId'];
    if (currentId is! int) return null;
    for (final window in _windowList(native)) {
      if (window['windowId'] == currentId) return window;
    }
    return null;
  }

  Map<String, dynamic>? _viewFor(
    List<Map<String, dynamic>> views,
    String identityId,
  ) {
    for (final view in views) {
      if (view['identityId'] == identityId) return view;
    }
    return null;
  }

  // ---- serializers ----

  Map<String, Object?> _projectJson(Project project) => {
    'id': project.id,
    'name': project.name,
    'targetUrl': _stripUrl(project.targetUrl),
    'allowPrivateNetwork': project.allowPrivateNetwork,
    'defaultLayoutMode': project.defaultLayoutMode.name,
  };

  Map<String, Object?> _identityJson(Identity identity) => {
    'id': identity.id,
    'projectId': identity.projectId,
    'name': identity.name,
    'isolationMode': identity.isolationMode.name,
    'isIsolated': identity.isolationMode.isIsolated,
    'devicePresetId': identity.devicePresetId,
    'startPath': _stripUrl(identity.startPath),
  };

  Future<Map<String, Object?>> _panelJson(
    PanelRuntime panel,
    WorkspaceState workspace,
    List<Map<String, dynamic>> views,
  ) async {
    final identity = await identities.getById(panel.identityId);
    final view = _viewFor(views, panel.identityId);
    return {
      'identityId': panel.identityId,
      'projectId': identity?.projectId,
      'identityName': identity?.name,
      'state': panel.state.name,
      'url': _stripUrl(panel.url),
      'loading': panel.loading,
      'selected': workspace.selectedPanelId == panel.identityId,
      'devicePresetId': panel.devicePresetId ?? identity?.devicePresetId,
      'isolationMode': panel.isolationMode.name,
      'layout': _layoutJson(panel.layout),
      'nativeViewId': view?['viewId'],
      'windowId': view?['windowId'],
      'hasKeyboardFocus': view?['hasKeyboardFocus'] == true,
    };
  }

  Map<String, Object?> _windowsJson(Map<String, dynamic> native) {
    final views = _nativeList(native, 'views');
    return {
      'currentWindowId': native['currentWindowId'],
      'mainWindowId': native['mainWindowId'],
      'windows': [
        for (final window in _windowList(native)) _windowJson(window, views),
      ],
      'views': [for (final view in views) _viewJson(view)],
    };
  }

  Map<String, Object?>? _windowJsonOrNull(
    Map<String, dynamic>? window,
    List<Map<String, dynamic>> views,
  ) => window == null ? null : _windowJson(window, views);

  Map<String, Object?> _windowJson(
    Map<String, dynamic> window,
    List<Map<String, dynamic>> views,
  ) => {
    'windowId': window['windowId'],
    'title': window['title'],
    'isKey': window['isKey'] == true,
    'isMain': window['isMain'] == true,
    'isVisible': window['isVisible'] == true,
    'isMiniaturized': window['isMiniaturized'] == true,
    'bounds': window['bounds'],
    'identityIds': [
      for (final view in views)
        if (view['windowId'] == window['windowId']) view['identityId'],
    ],
  };

  Map<String, Object?> _viewJson(Map<String, dynamic> view) => {
    'viewId': view['viewId'],
    'identityId': view['identityId'],
    'windowId': view['windowId'],
    'hasKeyboardFocus': view['hasKeyboardFocus'] == true,
  };

  Map<String, Object?> _workspaceJson(WorkspaceLayout workspace) => {
    'id': workspace.id,
    'projectId': workspace.projectId,
    'name': workspace.name,
    'viewportX': workspace.viewportX,
    'viewportY': workspace.viewportY,
    'zoom': workspace.zoom,
    'layoutMode': workspace.layoutMode.name,
    'updatedAt': workspace.updatedAt,
    'panels': [
      for (final panel in workspace.panels)
        {'identityId': panel.identityId, ..._layoutJson(panel)},
    ],
  };

  Map<String, Object?> _layoutJson(PanelLayout layout) => {
    'x': layout.x,
    'y': layout.y,
    'width': layout.width,
    'height': layout.height,
    'zIndex': layout.zIndex,
    'minimized': layout.minimized,
    'detached': layout.detached,
  };

  // ---- validation / redaction ----

  String? _optionalString(Map<String, dynamic> command, String key) {
    final value = command[key];
    if (value == null) return null;
    if (value is! String || value.isEmpty) {
      throw AutomationFailure(
        'invalid_argument',
        '$key must be a non-empty string',
      );
    }
    return value;
  }

  AutomationFailure _notFound(String what) => AutomationFailure(
    'not_found',
    'Requested $what does not exist',
    status: 404,
  );

  /// Removes userinfo, query and fragment while keeping scheme, host, explicit
  /// port and path. A relative path (identity startPath) keeps only its path
  /// component.
  ///
  /// The raw input is never returned. A value that cannot be reduced to a safe
  /// shape — unparsable text, an authority whose userinfo could not be
  /// separated from a host, or a relative reference with no path such as
  /// `?token=secret` — redacts to the empty string, because echoing the input
  /// would publish the very query, fragment or credentials being removed.
  String _stripUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return '';
    if (uri.hasAuthority) {
      final host = uri.host;
      // An authority with no host (e.g. `https://user:secret@`) has nothing
      // safe left once the userinfo is dropped.
      if (uri.scheme.isEmpty || host.isEmpty) return '';
      // Uri.host removes IPv6 brackets; restore them to keep the host usable.
      final safeHost = host.contains(':') ? '[$host]' : host;
      final port = uri.hasPort ? ':${uri.port}' : '';
      return '${uri.scheme}://$safeHost$port${uri.path}';
    }
    // No authority: only the path survives. Empty means nothing but query or
    // fragment, so there is no safe remainder to return.
    return uri.path;
  }
}
