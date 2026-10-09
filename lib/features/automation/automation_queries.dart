/// Automation queries for the local automation transport.
/// Implements the contract in design/automation-roadmap.md "P0 协议 v1：读取"
/// plus the write slices added per issue (issue #31: activate_project).
///
/// Read operations are pure snapshots: repositories, UI selection, browser
/// profiles and native windows are never mutated by them. Write operations
/// mutate exactly the same provider entry points the UI calls — never the
/// data layer directly. All workspace and native data enters through
/// injected callbacks so the query layer stays testable and free of
/// provider/global state.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../../core/platform/domain.dart';
import '../../core/platform/webview_adapter.dart';
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
    required this.captureScreenshot,
    required this.sampleMedia,
    required this.drainJsErrors,
    required this.probeDom,
    required this.domFind,
    required this.domInspect,
    required this.selectProject,
    required this.ensurePanel,
    required this.awaitFrame,
    this.settleBudget = const Duration(seconds: 2),
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

  /// One-shot viewport PNG capture of the web view bound to `viewId`,
  /// re-validated natively against `expectedIdentityId`. Returns `png`
  /// (Uint8List), `width`, `height`, `url`, `windowId`.
  final Future<Map<String, dynamic>> Function(
    int viewId,
    String expectedIdentityId,
  )
  captureScreenshot;

  /// One-shot media-state sample of the page in the web view bound to
  /// `viewId`, re-validated natively the same way. Returns `json` (the fixed
  /// probe's JSON string), `url`, `windowId`.
  final Future<Map<String, dynamic>> Function(
    int viewId,
    String expectedIdentityId,
  )
  sampleMedia;

  /// Read-only drain of the in-page JS error buffer of the view bound to
  /// `viewId`, re-validated natively the same way. Returns `json`, `url`,
  /// `windowId`.
  final Future<Map<String, dynamic>> Function(
    int viewId,
    String expectedIdentityId,
  )
  drainJsErrors;

  /// Read-only DOM summary probe of the view bound to `viewId`, re-validated
  /// natively the same way. Returns `json`, `url`, `windowId`.
  final Future<Map<String, dynamic>> Function(
    int viewId,
    String expectedIdentityId,
  )
  probeDom;

  /// Read-only DOM element search of the view bound to `viewId`. The third
  /// argument is a JSON string of the validated criteria, embedded natively
  /// as data ahead of the fixed script. Returns `json`, `url`, `windowId`.
  final Future<Map<String, dynamic>> Function(
    int viewId,
    String expectedIdentityId,
    String query,
  )
  domFind;

  /// Read-only DOM element inspection of the view bound to `viewId`. The
  /// third argument is a JSON string of `{ref, documentId}`.
  final Future<Map<String, dynamic>> Function(
    int viewId,
    String expectedIdentityId,
    String query,
  )
  domInspect;

  /// Switches the UI's selected project — wired to the very provider call
  /// the sidebar makes (`selectedProjectIdProvider.notifier.select`), never
  /// to a data-layer shortcut. Injected so tests can observe the call.
  final void Function(String projectId) selectProject;

  /// Opens (or refreshes the runtime of) a panel — wired to the very
  /// `WorkspaceController.ensurePanel` the workspace sync calls, never to
  /// a second WebView lifecycle. Injected so tests can observe the call.
  final void Function(Identity identity, Project project) ensurePanel;

  /// Waits for the UI to present the next frame after a mutation. In the
  /// app this is `SchedulerBinding.instance.endOfFrame`; the workspace
  /// post-frame sync (layout restore + panel ensure) runs inside it.
  final Future<void> Function() awaitFrame;

  /// Extra settle budget after the first frame for the workspace marker
  /// (`WorkspaceState.selectedProjectId`) to catch up with the UI
  /// selection; layout restore reads the repository asynchronously.
  final Duration settleBudget;

  /// Decoded PNG size bound for `screenshot`: a full-viewport capture should
  /// stay far below this; anything larger is refused rather than shipped
  /// over the transport unboundedly.
  static const int screenshotPngLimit = 16 * 1024 * 1024;

  Future<Object?> dispatch(Map<String, dynamic> command) async {
    final op = command['op'];
    if (op is! String) {
      throw const AutomationFailure('invalid_argument', 'op must be a string');
    }
    if (!automationOperations.contains(op)) {
      throw const AutomationFailure(
        'unsupported_operation',
        'Operation is not on the automation whitelist',
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
      case 'screenshot':
        return _screenshot(command);
      case 'media':
        return _media(command);
      case 'errors':
        return _errors(command);
      case 'dom':
        return _dom(command);
      case 'dom_find':
        return _domFind(command);
      case 'dom_inspect':
        return _domInspect(command);
      case 'activate_project':
        return _activateProject(command);
      case 'open_panel':
        return _openPanel(command);
    }
    throw const AutomationFailure(
      'unsupported_operation',
      'Operation is not on the automation whitelist',
    );
  }

  // ---- operations ----

  Map<String, Object?> _capabilities() => {
    'protocolVersion': 2,
    // The transport is no longer read-only since issue #31; `operations`
    // stays the read list for consumers that enumerate pure queries, and
    // writes are listed separately so nothing confuses the two.
    'readOnly': false,
    'engine': 'WKWebView',
    'operations': automationReadOperations.toList(),
    'writeOperations': automationWriteOperations.toList(),
    'limitations': {
      'dom': true,
      'screenshot': true,
      'media': true,
      'errors': true,
      'projectActivation': true,
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

  /// Viewport PNG of the panel bound to an explicit `identityId`.
  ///
  /// There is no selection fallback: omitting the id is `invalid_argument`,
  /// an unknown id is `not_found`, and an identity with no live native view
  /// is `no_native_view`. The native side binds the capture to (viewId,
  /// identity, web view instance, navigation generation) and re-validates
  /// after the async snapshot — drift arrives here as a `target_changed`
  /// PlatformException, which is re-raised as an AutomationFailure so the
  /// wire error stays distinguishable instead of a generic command_failed.
  Future<Map<String, Object?>> _screenshot(Map<String, dynamic> command) async {
    final id = _optionalString(command, 'identityId');
    if (id == null) {
      throw const AutomationFailure(
        'invalid_argument',
        'screenshot requires an explicit identityId',
      );
    }
    final identity = await identities.getById(id);
    if (identity == null) throw _notFound('identity');
    final native = await readNativeWindows();
    final views = _nativeList(native, 'views');
    final view = _viewFor(views, id);
    final viewId = view?['viewId'];
    if (viewId is! int) {
      throw const AutomationFailure(
        'no_native_view',
        'Identity has no live native web view',
        status: 409,
      );
    }
    final Map<String, dynamic> shot;
    try {
      shot = await captureScreenshot(viewId, id);
    } on PlatformException catch (error) {
      // Distinguishable native failures keep their code over the transport
      // instead of collapsing into command_failed: target_changed means the
      // binding drifted mid-capture and must not be mistaken for success on
      // a different target.
      const codes = {
        'target_changed',
        'snapshot_failed',
        'snapshot_timeout',
        'snapshot_too_large',
      };
      if (codes.contains(error.code)) {
        throw AutomationFailure(
          error.code,
          error.message ?? 'Screenshot target could not be captured',
          status: error.code == 'target_changed' ? 409 : 500,
        );
      }
      rethrow;
    }
    final png = shot['png'];
    if (png is! Uint8List) {
      throw AutomationFailure(
        'snapshot_failed',
        'Native snapshot returned no image data: ${png.runtimeType}',
        status: 500,
      );
    }
    if (png.length > screenshotPngLimit) {
      throw const AutomationFailure(
        'snapshot_too_large',
        'Snapshot exceeded the 16 MiB bound',
        status: 500,
      );
    }
    return {
      'identityId': id,
      'projectId': identity.projectId,
      'nativeViewId': viewId,
      'windowId': shot['windowId'] ?? view?['windowId'],
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'format': 'png',
      'width': shot['width'],
      'height': shot['height'],
      'url': _stripUrl(shot['url'] as String? ?? ''),
      'pngBase64': base64Encode(png),
    };
  }

  /// Read-only media-state sample of the page bound to an explicit
  /// `identityId`.
  ///
  /// Same target discipline as `screenshot`: no id is `invalid_argument`, an
  /// unknown id is `not_found`, and no live view is `no_native_view`. The
  /// native side runs one fixed probe script (never caller JS) that reads
  /// `video`/`audio` state in the main document plus every reachable
  /// same-origin iframe, and re-checks the (view, identity, instance,
  /// window, navigation generations) binding when evaluation completes —
  /// drift returns `target_changed` so results never mix across targets.
  /// Unreachable frames arrive marked `reachable: false`, never probed.
  Future<Map<String, Object?>> _media(Map<String, dynamic> command) async {
    final id = _optionalString(command, 'identityId');
    if (id == null) {
      throw const AutomationFailure(
        'invalid_argument',
        'media requires an explicit identityId',
      );
    }
    final identity = await identities.getById(id);
    if (identity == null) throw _notFound('identity');
    final native = await readNativeWindows();
    final views = _nativeList(native, 'views');
    final view = _viewFor(views, id);
    final viewId = view?['viewId'];
    if (viewId is! int) {
      throw const AutomationFailure(
        'no_native_view',
        'Identity has no live native web view',
        status: 409,
      );
    }
    final Map<String, dynamic> sample;
    try {
      sample = await sampleMedia(viewId, id);
    } on PlatformException catch (error) {
      const codes = {'target_changed', 'media_failed', 'media_timeout'};
      if (codes.contains(error.code)) {
        throw AutomationFailure(
          error.code,
          error.message ?? 'Media state could not be sampled',
          status: error.code == 'target_changed' ? 409 : 500,
        );
      }
      rethrow;
    }
    final Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(sample['json'] is String ? sample['json'] as String : '');
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      payload = decoded;
    } on FormatException {
      throw const AutomationFailure(
        'media_failed',
        'Native media probe returned malformed JSON',
        status: 500,
      );
    }
    // Every URL the probe reports goes through the same sanitizer as all
    // other transport URLs: scheme, host, port and path only.
    final frames = <Map<String, dynamic>>[
      for (final f in payload['frames'] is List ? payload['frames'] as List : const [])
        if (f is Map) Map<String, dynamic>.from(f),
    ];
    for (final frame in frames) {
      frame['url'] = _stripUrl(frame['url'] as String? ?? '');
    }
    return {
      'identityId': id,
      'projectId': identity.projectId,
      'nativeViewId': viewId,
      'windowId': sample['windowId'] ?? view?['windowId'],
      'sampledAt': DateTime.now().toUtc().toIso8601String(),
      'url': _stripUrl(sample['url'] as String? ?? ''),
      'frames': frames,
      // Probe budgets: a truncated walk is surfaced, never read as "no media".
      'truncated': payload['truncated'] == true,
      'skippedFrames': payload['skippedFrames'] ?? 0,
      'depthLimitSkipped': payload['depthLimitSkipped'] ?? 0,
    };
  }

  /// Read-only dump of the JS errors captured for an explicit `identityId`
  /// (issue #17). Same target discipline as `media`: no id is
  /// `invalid_argument`, unknown id is `not_found`, no live view is
  /// `no_native_view`, drift mid-read is `target_changed`. The buffer only
  /// records `error`/`unhandledrejection` events from injection time onward —
  /// `collectedAt` marks that start, `installed:false` marks a page created
  /// without the capture flag, and per-document `bufferId` separates
  /// navigation batches. Rejection reasons and stacks are already bounded
  /// and reduced by the page-side buffer; every URL (frame `url`, entry
  /// `source`) is sanitized here the same way as all transport URLs.
  Future<Map<String, Object?>> _errors(Map<String, dynamic> command) async {
    final id = _optionalString(command, 'identityId');
    if (id == null) {
      throw const AutomationFailure(
        'invalid_argument',
        'errors requires an explicit identityId',
      );
    }
    final identity = await identities.getById(id);
    if (identity == null) throw _notFound('identity');
    final native = await readNativeWindows();
    final views = _nativeList(native, 'views');
    final view = _viewFor(views, id);
    final viewId = view?['viewId'];
    if (viewId is! int) {
      throw const AutomationFailure(
        'no_native_view',
        'Identity has no live native web view',
        status: 409,
      );
    }
    final Map<String, dynamic> drained;
    try {
      drained = await drainJsErrors(viewId, id);
    } on PlatformException catch (error) {
      const codes = {'target_changed', 'errors_failed', 'errors_timeout'};
      if (codes.contains(error.code)) {
        throw AutomationFailure(
          error.code,
          error.message ?? 'JS errors could not be drained',
          status: error.code == 'target_changed' ? 409 : 500,
        );
      }
      rethrow;
    }
    final Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(drained['json'] is String ? drained['json'] as String : '');
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      payload = decoded;
    } on FormatException {
      throw const AutomationFailure(
        'errors_failed',
        'Native error drain returned malformed JSON',
        status: 500,
      );
    }
    final frames = <Map<String, dynamic>>[
      for (final f in payload['frames'] is List ? payload['frames'] as List : const [])
        if (f is Map) Map<String, dynamic>.from(f),
    ];
    for (final frame in frames) {
      frame['url'] = _stripUrl(frame['url'] as String? ?? '');
      final errors = frame['errors'];
      if (errors is List) {
        for (var i = 0; i < errors.length; i++) {
          final e = errors[i];
          if (e is Map) {
            final entry = Map<String, dynamic>.from(e);
            entry['source'] = _stripUrl(entry['source'] as String? ?? '');
            errors[i] = entry;
          }
        }
      }
    }
    return {
      'identityId': id,
      'projectId': identity.projectId,
      'nativeViewId': viewId,
      'windowId': drained['windowId'] ?? view?['windowId'],
      'sampledAt': DateTime.now().toUtc().toIso8601String(),
      'url': _stripUrl(drained['url'] as String? ?? ''),
      'frames': frames,
    };
  }

  /// Read-only DOM summary for an explicit `identityId` (issue #20). Same
  /// target discipline as `errors`/`media`: no id is `invalid_argument`,
  /// unknown id is `not_found`, no live view is `no_native_view`, drift
  /// mid-read is `target_changed`. The fixed probe walks the main document
  /// plus same-origin iframes under hard budgets; `truncated`/`skipped`
  /// are surfaced verbatim so a bounded walk is never mistaken for an
  /// empty page. Every URL (frame `url`, element `href`, top `url`)
  /// goes through the transport sanitizer — scheme, host, port, path only.
  Future<Map<String, Object?>> _dom(Map<String, dynamic> command) async {
    final id = _optionalString(command, 'identityId');
    if (id == null) {
      throw const AutomationFailure(
        'invalid_argument',
        'dom requires an explicit identityId',
      );
    }
    final identity = await identities.getById(id);
    if (identity == null) throw _notFound('identity');
    final native = await readNativeWindows();
    final views = _nativeList(native, 'views');
    final view = _viewFor(views, id);
    final viewId = view?['viewId'];
    if (viewId is! int) {
      throw const AutomationFailure(
        'no_native_view',
        'Identity has no live native web view',
        status: 409,
      );
    }
    final Map<String, dynamic> probed;
    try {
      probed = await probeDom(viewId, id);
    } on PlatformException catch (error) {
      const codes = {'target_changed', 'dom_failed', 'dom_timeout'};
      if (codes.contains(error.code)) {
        throw AutomationFailure(
          error.code,
          error.message ?? 'DOM summary could not be produced',
          status: error.code == 'target_changed' ? 409 : 500,
        );
      }
      rethrow;
    }
    final Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(probed['json'] is String ? probed['json'] as String : '');
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      payload = decoded;
    } on FormatException {
      throw const AutomationFailure(
        'dom_failed',
        'Native DOM probe returned malformed JSON',
        status: 500,
      );
    }
    final frames = <Map<String, dynamic>>[
      for (final f in payload['frames'] is List ? payload['frames'] as List : const [])
        if (f is Map) Map<String, dynamic>.from(f),
    ];
    for (final frame in frames) {
      frame['url'] = _stripUrl(frame['url'] as String? ?? '');
      final elements = frame['elements'];
      if (elements is List) {
        for (var i = 0; i < elements.length; i++) {
          final e = elements[i];
          if (e is Map) {
            final el = Map<String, dynamic>.from(e);
            if (el['href'] is String) {
              el['href'] = _stripUrl(el['href'] as String);
            }
            elements[i] = el;
          }
        }
      }
    }
    return {
      'identityId': id,
      'projectId': identity.projectId,
      'nativeViewId': viewId,
      'windowId': probed['windowId'] ?? view?['windowId'],
      'sampledAt': DateTime.now().toUtc().toIso8601String(),
      'url': _stripUrl(probed['url'] as String? ?? ''),
      'documentId': payload['documentId'],
      'title': payload['title'],
      'frames': frames,
      'truncated': payload['truncated'] == true,
      'skipped': payload['skipped'] ?? const {},
    };
  }

  /// Element search for an explicit `identityId` (issue #21). Exactly one
  /// criterion is required: `text` (with `match: 'exact'|'contains'`,
  /// default contains), `role` (optional `name`), or `selector`. Optional
  /// `frame` restricts to one frame label (`main`, `f0`, …). Zero matches
  /// are `not_found`(404); a bounded `matches` list is returned verbatim —
  /// multi-match is never auto-picked. Invalid selector maps to
  /// `invalid_selector`, an unreachable named frame to `frame_unreachable`.
  /// Criteria travel as JSON data — no caller JavaScript ever runs.
  Future<Map<String, Object?>> _domFind(Map<String, dynamic> command) async {
    final id = _optionalString(command, 'identityId');
    if (id == null) {
      throw const AutomationFailure(
        'invalid_argument',
        'dom_find requires an explicit identityId',
      );
    }
    final identity = await identities.getById(id);
    if (identity == null) throw _notFound('identity');
    final text = _optionalString(command, 'text');
    final role = _optionalString(command, 'role');
    final selector = _optionalString(command, 'selector');
    final kinds = [if (text != null) 'text', if (role != null) 'role', if (selector != null) 'selector'];
    if (kinds.length != 1) {
      throw const AutomationFailure(
        'invalid_argument',
        'dom_find requires exactly one of text, role or selector',
      );
    }
    final match = _optionalString(command, 'match') ?? 'contains';
    if (match != 'exact' && match != 'contains') {
      throw const AutomationFailure(
        'invalid_argument',
        "match must be 'exact' or 'contains'",
      );
    }
    final query = <String, Object?>{
      'kind': kinds.single,
      'match': match,
      'text': ?text,
      'role': ?role,
      'selector': ?selector,
      'name': ?_optionalString(command, 'name'),
      'frame': ?_optionalString(command, 'frame'),
    };
    final native = await readNativeWindows();
    final views = _nativeList(native, 'views');
    final view = _viewFor(views, id);
    final viewId = view?['viewId'];
    if (viewId is! int) {
      throw const AutomationFailure(
        'no_native_view',
        'Identity has no live native web view',
        status: 409,
      );
    }
    final Map<String, dynamic> probed;
    try {
      probed = await domFind(viewId, id, jsonEncode(query));
    } on PlatformException catch (error) {
      const codes = {'target_changed', 'dom_find_failed', 'dom_find_timeout'};
      if (codes.contains(error.code)) {
        throw AutomationFailure(
          error.code,
          error.message ?? 'DOM find could not run',
          status: error.code == 'target_changed' ? 409 : 500,
        );
      }
      rethrow;
    }
    final Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(probed['json'] is String ? probed['json'] as String : '');
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      payload = decoded;
    } on FormatException {
      throw const AutomationFailure(
        'dom_find_failed',
        'Native DOM find returned malformed JSON',
        status: 500,
      );
    }
    final error = payload['error'];
    if (error is String) {
      throw AutomationFailure(
        error,
        payload['message'] as String? ?? 'DOM find failed',
        status: error == 'invalid_selector' ? 400 : (error == 'not_found' ? 404 : 409),
      );
    }
    final count = payload['count'];
    final complete = payload['complete'] != false;
    if (count is! int) {
      throw const AutomationFailure('not_found', 'No element matches', status: 404);
    }
    // A zero-count is `not_found` only when the walk actually covered the
    // searchable range — an incomplete scan must never claim "no match".
    if (count == 0 && complete) {
      throw const AutomationFailure('not_found', 'No element matches', status: 404);
    }
    final matches = <Map<String, dynamic>>[
      for (final m in payload['matches'] is List ? payload['matches'] as List : const [])
        if (m is Map) Map<String, dynamic>.from(m),
    ];
    return {
      'identityId': id,
      'projectId': identity.projectId,
      'nativeViewId': viewId,
      'windowId': probed['windowId'] ?? view?['windowId'],
      'sampledAt': DateTime.now().toUtc().toIso8601String(),
      'url': _stripUrl(probed['url'] as String? ?? ''),
      'documentId': payload['documentId'],
      'matchCount': count,
      // Coverage honesty: `complete:false` means candidates may exist
      // beyond the scanned range — `matchCount` is then a lower bound and
      // an empty list is not "no match".
      'complete': complete,
      if (!complete) 'countIsLowerBound': true,
      'scannedTotal': payload['scannedTotal'],
      'scanTruncated': payload['scanTruncated'] == true,
      'unreachableFrames': payload['unreachableFrames'],
      'truncated': payload['truncated'] == true,
      'matches': matches,
    };
  }

  /// Element inspection by `ref` (issue #22). `identityId`, `ref`
  /// (`<frame>.<position>`) and `documentId` are required — a ref is
  /// meaningless without the document nonce that issued it. The fixed
  /// probe proves freshness via page-side marker expandos; any document
  /// change is `stale_element`(409), never silently re-aimed. Read-only:
  /// whitelisted non-sensitive attributes only — no values, no innerHTML.
  Future<Map<String, Object?>> _domInspect(Map<String, dynamic> command) async {
    final id = _optionalString(command, 'identityId');
    final ref = _optionalString(command, 'ref');
    final documentId = _optionalString(command, 'documentId');
    if (id == null || ref == null || documentId == null) {
      throw const AutomationFailure(
        'invalid_argument',
        'dom_inspect requires identityId, ref and documentId',
      );
    }
    final identity = await identities.getById(id);
    if (identity == null) throw _notFound('identity');
    final native = await readNativeWindows();
    final views = _nativeList(native, 'views');
    final view = _viewFor(views, id);
    final viewId = view?['viewId'];
    if (viewId is! int) {
      throw const AutomationFailure(
        'no_native_view',
        'Identity has no live native web view',
        status: 409,
      );
    }
    final Map<String, dynamic> probed;
    try {
      probed = await domInspect(
        viewId,
        id,
        jsonEncode({'ref': ref, 'documentId': documentId}),
      );
    } on PlatformException catch (error) {
      const codes = {
        'target_changed',
        'dom_inspect_failed',
        'dom_inspect_timeout',
      };
      if (codes.contains(error.code)) {
        throw AutomationFailure(
          error.code,
          error.message ?? 'DOM inspect could not run',
          status: error.code == 'target_changed' ? 409 : 500,
        );
      }
      rethrow;
    }
    final Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(probed['json'] is String ? probed['json'] as String : '');
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      payload = decoded;
    } on FormatException {
      throw const AutomationFailure(
        'dom_inspect_failed',
        'Native DOM inspect returned malformed JSON',
        status: 500,
      );
    }
    final error = payload['error'];
    if (error is String) {
      throw AutomationFailure(
        error,
        payload['message'] as String? ?? 'DOM inspect failed',
        status: error == 'invalid_argument'
            ? 400
            : (error == 'not_found' ? 404 : 409),
      );
    }
    final attrs = payload['attrs'];
    if (attrs is Map) {
      for (final key in const ['href', 'src', 'action']) {
        final v = attrs[key];
        if (v is String) attrs[key] = _stripUrl(v);
      }
    }
    return {
      'identityId': id,
      'projectId': identity.projectId,
      'nativeViewId': viewId,
      'windowId': probed['windowId'] ?? view?['windowId'],
      'sampledAt': DateTime.now().toUtc().toIso8601String(),
      'url': _stripUrl(probed['url'] as String? ?? ''),
      'element': payload,
    };
  }

  /// Switches the UI to an existing project (issue #31).
  ///
  /// The mutation is the same provider call the sidebar click makes, so
  /// layout restore, panel sync and all other activation semantics are the
  /// UI's own. Validation is explicit: no `projectId` is
  /// `invalid_argument`, an unknown id is `not_found`, and an activation
  /// already in flight is rejected by the transport's `_project` lock as
  /// `panel_busy` — a concurrent switch can never silently last-writer-wins
  /// here.
  ///
  /// After the provider call the workspace converges asynchronously
  /// (post-frame sync + repository read in `restoreProjectLayoutMode`). The
  /// op waits one UI frame plus [settleBudget] for the workspace marker to
  /// reach the requested id and reports `settled` honestly — a false
  /// `settled` is "still converging, re-query", never a failure claim
  /// either way. Native focus is reported separately because it need not
  /// follow the UI selection.
  Future<Map<String, Object?>> _activateProject(
    Map<String, dynamic> command,
  ) async {
    final id = _optionalString(command, 'projectId');
    if (id == null) {
      throw const AutomationFailure(
        'invalid_argument',
        'activate_project requires an explicit projectId',
      );
    }
    final project = await projects.getById(id);
    if (project == null) throw _notFound('project');
    final alreadyActive = readSelectedProjectId() == id;
    if (!alreadyActive) selectProject(id);
    // One frame lets the post-frame workspace sync run; the workspace
    // marker can still lag on the repository read inside
    // restoreProjectLayoutMode, so poll briefly past it.
    var frameSeen = true;
    try {
      await awaitFrame().timeout(const Duration(seconds: 4));
    } on TimeoutException {
      frameSeen = false;
    }
    var settled = readWorkspace().selectedProjectId == id;
    final deadline = DateTime.now().add(settleBudget);
    while (!settled && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      settled = readWorkspace().selectedProjectId == id;
    }
    // Final sample must prove BOTH the UI selection and the workspace
    // marker are still bound to the requested project — a settled flag
    // sampled before a user switch (or another automation write) is
    // stale and must not be reported.
    final ui = _captureUiState();
    if (ui.projectId != id) {
      throw AutomationFailure(
        'target_changed',
        'UI selection moved to ${ui.projectId ?? 'none'} during activation',
        status: 409,
      );
    }
    settled = settled && ui.workspace.selectedProjectId == id;
    final native = await readNativeWindows();
    final views = _nativeList(native, 'views');
    final selection = await _selection(ui.workspace, ui.projectId);
    return {
      'projectId': id,
      'project': _projectJson(project),
      'alreadyActive': alreadyActive,
      'activatedAt': DateTime.now().toUtc().toIso8601String(),
      'selectedProjectId': ui.projectId,
      'workspaceSelectedProjectId': ui.workspace.selectedProjectId,
      'selectedPanelId': ui.workspace.selectedPanelId,
      'selectionConsistent': selection.consistent,
      // Native focus is a different signal from UI selection; it may still
      // point at a panel of the previous project or nothing at all.
      'focusedIdentityId': _focusedIdentityId(views),
      'frameSettled': frameSeen,
      'settled': settled,
      // Resident panels as they stand right now — panels of the previous
      // project may still be listed until the sync finishes re-keying.
      'panels': [
        for (final panel in ui.workspace.panels.values)
          await _panelJson(panel, ui.workspace, views),
      ],
    };
  }

  /// Opens (or returns the live) panel of an existing identity (issue #32).
  ///
  /// Explicit `identityId` is required; the identity must belong to the
  /// currently active project — a mismatch is `project_not_active` (409),
  /// never an implicit switch of another project. The mutation is the
  /// controller's `ensurePanel` — the same entry point the workspace sync
  /// uses — so fingerprints, isolation, start-URL and layout rules are the
  /// UI's own; nothing constructs a second WebView lifecycle here.
  ///
  /// Already-open panels return idempotently (`alreadyOpen:true`) without
  /// a redundant ensure call. The returned binding is honest about
  /// readiness: `state`/`loading`/`nativeViewId` describe the panel at
  /// answer time — an `openingEmbedded` panel with `nativeViewId:null`
  /// means the platform view has not registered yet, never "page ready".
  Future<Map<String, Object?>> _openPanel(
    Map<String, dynamic> command,
  ) async {
    final id = _optionalString(command, 'identityId');
    if (id == null) {
      throw const AutomationFailure(
        'invalid_argument',
        'open_panel requires an explicit identityId',
      );
    }
    final identity = await identities.getById(id);
    if (identity == null) throw _notFound('identity');
    final activeProjectId = readSelectedProjectId();
    if (identity.projectId != activeProjectId) {
      throw const AutomationFailure(
        'project_not_active',
        "Identity's project is not the active project",
        status: 409,
      );
    }
    final project = await projects.getById(identity.projectId);
    if (project == null) throw _notFound('project');
    // Critical section: re-validate the active project immediately before
    // the mutation — the repository awaits above are suspension points
    // where a user switch (or another automation write) can move the
    // selection, and `ensurePanel` writes workspace.selectedProjectId =
    // project.id, which would split the UI/workspace markers onto
    // different projects.
    if (readSelectedProjectId() != identity.projectId) {
      throw const AutomationFailure(
        'target_changed',
        'Active project changed before the panel mutation',
        status: 409,
      );
    }
    final before = readWorkspace().panels[id];
    final alreadyOpen =
        before != null &&
        before.state != WebviewState.closed &&
        before.state != WebviewState.closing;
    if (!alreadyOpen) ensurePanel(identity, project);
    // Give the widget tree one frame to mount the AppKitView and register
    // the native view; report whatever binding exists when the budget ends.
    var frameSeen = true;
    try {
      await awaitFrame().timeout(const Duration(seconds: 4));
    } on TimeoutException {
      frameSeen = false;
    }
    // Drift check: a user-driven project switch during the frame wait must
    // not be reported as a successful open of the old project's panel.
    if (readSelectedProjectId() != identity.projectId) {
      throw const AutomationFailure(
        'target_changed',
        'Active project changed while the panel was opening',
        status: 409,
      );
    }
    final workspace = readWorkspace();
    final panel = workspace.panels[id];
    if (panel == null) {
      // Destroy race: the identity/panel vanished between ensure and read —
      // distinguishable, never a silent claim of success.
      throw const AutomationFailure(
        'panel_not_open',
        'Panel was not open after ensure (identity may have been removed)',
        status: 409,
      );
    }
    final native = await readNativeWindows();
    final views = _nativeList(native, 'views');
    final view = _viewFor(views, id);
    return {
      'identityId': id,
      'projectId': identity.projectId,
      'alreadyOpen': alreadyOpen,
      'openedAt': DateTime.now().toUtc().toIso8601String(),
      'panel': await _panelJson(panel, workspace, views),
      'nativeViewId': view?['viewId'],
      'windowId': view?['windowId'],
      // Selection is UI state; native focus is a separate signal and may
      // not follow the panel that was just opened.
      'selected': workspace.selectedPanelId == id,
      'hasKeyboardFocus': view?['hasKeyboardFocus'] == true,
      'viewReady': view?['viewId'] is int && panel.state == WebviewState.embedded,
      'frameSettled': frameSeen,
    };
  }

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
    // Opaque absolute URI (`scheme:` with no authority): the path is payload,
    // not a locator — `data:text/html,<markup>` and `javascript:…` would ship
    // page content or code verbatim. Only the scheme marker survives, e.g.
    // `data:`, so the URL stays identifiable without its body.
    if (uri.scheme.isNotEmpty) return '${uri.scheme}:';
    // Relative reference (identity startPath, `page.html`, `dir/x`): only the
    // path survives. Empty means nothing but query or fragment, so there is
    // no safe remainder to return.
    return uri.path;
  }
}
