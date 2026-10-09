/// Tests for the P0 read-only automation query dispatcher and the transport
/// read-operation whitelist (design/automation-roadmap.md).
///
/// Repositories run on a real in-memory database; workspace and native state
/// enter through injected immutable snapshots so selection/focus edge cases
/// can be expressed directly.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_desk/core/platform/domain.dart';
import 'package:relay_desk/core/platform/webview_adapter.dart';
import 'package:relay_desk/data/database/database.dart';
import 'package:relay_desk/data/repositories/project_repository.dart';
import 'package:relay_desk/data/repositories/workspace_repository.dart';
import 'package:relay_desk/features/automation/automation_queries.dart';
import 'package:relay_desk/features/automation/automation_server.dart';
import 'package:relay_desk/features/workspace/workspace_controller.dart';

void main() {
  late RelayDatabase db;
  late ProjectRepository projects;
  late IdentityRepository identities;
  late WorkspaceRepository workspaces;
  late AutomationQueries queries;

  // Injected snapshots — mutated per test, never by the dispatcher.
  late WorkspaceState workspace;
  late String? selectedProjectId;
  late Map<String, dynamic> native;

  late Project projectA;
  late Project projectB;

  PanelRuntime makePanel(
    String identityId, {
    String url = 'https://alpha.example.com/',
    WebviewState state = WebviewState.embedded,
    bool loading = false,
    IsolationMode isolationMode = IsolationMode.nativeProfile,
    String? devicePresetId,
  }) => PanelRuntime(
    identityId: identityId,
    layout: PanelLayout(identityId: identityId, width: 800, height: 600),
    state: state,
    url: url,
    fingerprint: 'fp-$identityId',
    isolationMode: isolationMode,
    loading: loading,
    devicePresetId: devicePresetId,
  );

  Map<String, dynamic> nativeWindow(
    int windowId, {
    bool isKey = false,
    bool isMain = false,
  }) => {
    'windowId': windowId,
    'title': 'Window $windowId',
    'isKey': isKey,
    'isMain': isMain,
    'isVisible': true,
    'isMiniaturized': false,
    'bounds': {'x': 0.0, 'y': 0.0, 'width': 1200.0, 'height': 800.0},
  };

  Map<String, dynamic> nativeView(
    int viewId,
    String identityId, {
    int? windowId,
    bool hasKeyboardFocus = false,
  }) => {
    'viewId': viewId,
    'identityId': identityId,
    'windowId': windowId,
    'hasKeyboardFocus': hasKeyboardFocus,
  };

  Map<String, dynamic> nativeSnapshot({
    int? currentWindowId,
    int? mainWindowId,
    List<Map<String, dynamic>> windows = const [],
    List<Map<String, dynamic>> views = const [],
  }) => {
    'currentWindowId': currentWindowId,
    'mainWindowId': mainWindowId,
    'windows': windows,
    'views': views,
  };

  Future<Map<String, Object?>> run(Map<String, dynamic> command) async =>
      (await queries.dispatch(command)) as Map<String, Object?>;

  /// Builds the dispatcher over the injected snapshots. Tests that need to
  /// steer a native sample (for example a project switch landing mid-query)
  /// pass their own [nativeReader] instead of mutating `native` up front.
  AutomationQueries buildQueries({
    Future<Map<String, dynamic>> Function()? nativeReader,
    Future<Map<String, dynamic>> Function(
      int viewId,
      String expectedIdentityId,
    )?
    screenshotCapturer,
    Future<Map<String, dynamic>> Function(
      int viewId,
      String expectedIdentityId,
    )?
    mediaSampler,
    Future<Map<String, dynamic>> Function(
      int viewId,
      String expectedIdentityId,
    )?
    errorsDrainer,
    Future<Map<String, dynamic>> Function(
      int viewId,
      String expectedIdentityId,
    )?
    domProber,
    Future<Map<String, dynamic>> Function(
      int viewId,
      String expectedIdentityId,
      String query,
    )?
    domFinder,
    Future<Map<String, dynamic>> Function(
      int viewId,
      String expectedIdentityId,
      String query,
    )?
    domInspector,
    void Function(String projectId)? selectProject,
    void Function(Identity identity, Project project)? ensurePanel,
    Future<void> Function()? awaitFrame,
    void Function(String identityId, String url)? navigatePanel,
    void Function(String identityId)? reloadPanel,
    Future<Map<String, dynamic>> Function(int viewId, String identityId, String query)? domClick,
    Future<Map<String, dynamic>> Function(int viewId, String identityId, String query)? domInput,
    Future<Map<String, dynamic>> Function(int viewId, String identityId, String query)? domKey,
    Future<Map<String, dynamic>> Function(int viewId, String identityId, String query)? domScroll,
    bool Function(String identityId)? isNavigating,
    Stream<WebviewEvent> Function()? navigationEvents,
    Duration? settleBudget,
    Duration? navigateWaitBudget,
    Duration? clickNavObserveBudget,
  }) => AutomationQueries(
    projects: projects,
    identities: identities,
    workspaces: workspaces,
    readWorkspace: () => workspace,
    readSelectedProjectId: () => selectedProjectId,
    readNativeWindows: nativeReader ?? () async => native,
    captureScreenshot:
        screenshotCapturer ??
        (viewId, identityId) async => throw UnimplementedError(),
    sampleMedia:
        mediaSampler ??
        (viewId, identityId) async => throw UnimplementedError(),
    drainJsErrors:
        errorsDrainer ??
        (viewId, identityId) async => throw UnimplementedError(),
    probeDom:
        domProber ??
        (viewId, identityId) async => throw UnimplementedError(),
    domFind:
        domFinder ??
        (viewId, identityId, query) async => throw UnimplementedError(),
    domInspect:
        domInspector ??
        (viewId, identityId, query) async => throw UnimplementedError(),
    // Mimic what the real wiring does: the provider selection flips
    // immediately and the workspace marker catches up inside the same
    // settle window. Tests that want a permanently-lagging workspace
    // (settled:false) pass a selectProject that leaves `workspace` alone.
    selectProject:
        selectProject ??
        (id) {
          selectedProjectId = id;
          workspace = workspace.copyWith(selectedProjectId: id);
        },
    awaitFrame: awaitFrame ?? () async {},
    settleBudget: settleBudget ?? const Duration(milliseconds: 100),
    ensurePanel:
        ensurePanel ??
        (identity, project) {
          // Mimic the controller's ensure: register a runtime whose
          // state starts at openingEmbedded.
          final panels = Map<String, PanelRuntime>.from(workspace.panels);
          panels[identity.id] = makePanel(
            identity.id,
            state: WebviewState.openingEmbedded,
          );
          workspace = workspace.copyWith(
            panels: panels,
            selectedPanelId: workspace.selectedPanelId ?? identity.id,
            selectedProjectId: project.id,
          );
        },
    navigatePanel: navigatePanel ?? (_, _) {},
    reloadPanel: reloadPanel ?? (_) {},
    domClick: domClick ?? (_, _, _) async => {'json': '{}'},
    domInput: domInput ?? (_, _, _) async => {'json': '{}'},
    domKey: domKey ?? (_, _, _) async => {'json': '{}'},
    domScroll: domScroll ?? (_, _, _) async => {'json': '{}'},
    isNavigating: isNavigating ?? (_) => false,
    navigationEvents:
        navigationEvents ?? () => const Stream<WebviewEvent>.empty(),
    navigateWaitBudget:
        navigateWaitBudget ?? const Duration(milliseconds: 100),
    clickNavObserveBudget:
        clickNavObserveBudget ?? const Duration(milliseconds: 50),
  );

  Matcher failure(String code, int status) => throwsA(
    isA<AutomationFailure>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.status, 'status', status),
  );

  setUp(() async {
    db = RelayDatabase(NativeDatabase.memory());
    projects = ProjectRepository(db);
    identities = IdentityRepository(db);
    workspaces = WorkspaceRepository(db);

    projectA = await projects.create(
      name: 'Alpha',
      targetUrl: 'https://user:secret@alpha.example.com:8443/app?t=1#frag',
    );
    projectB = await projects.create(
      name: 'Beta',
      targetUrl: 'https://beta.example.com',
    );
    await identities.create(
      id: 'id-a1',
      projectId: projectA.id,
      name: 'A1',
      color: '#111111',
      isolationMode: IsolationMode.nativeProfile,
      startPath: '/home?token=abc#x',
    );
    await identities.create(
      id: 'id-a2',
      projectId: projectA.id,
      name: 'A2',
      color: '#222222',
      isolationMode: IsolationMode.sharedSession,
    );
    await identities.create(
      id: 'id-b1',
      projectId: projectB.id,
      name: 'B1',
      color: '#333333',
      isolationMode: IsolationMode.originProxy,
    );

    workspace = const WorkspaceState();
    selectedProjectId = null;
    native = nativeSnapshot();

    queries = buildQueries();
  });

  tearDown(() => db.close());

  test('capabilities reports the read + whitelisted-write contract', () async {
    final data = await run({'op': 'capabilities'});
    expect(data['protocolVersion'], 2);
    expect(data['readOnly'], false);
    expect(data['writeOperations'], [
      'activate_project',
      'open_panel',
      'navigate',
      'reload',
      'click',
      'input',
      'key',
      'scroll',
    ]);
    expect(
      (data['limitations'] as Map)['projectActivation'],
      true,
    );
    expect(data['engine'], 'WKWebView');
    expect(
      data['operations'],
      containsAll([
        'capabilities',
        'state',
        'projects',
        'project',
        'identities',
        'identity',
        'panels',
        'panel',
        'windows',
        'window',
        'workspaces',
        'workspace',
      ]),
    );
    final limitations = data['limitations'] as Map<String, Object?>;
    for (final unsupported in [
      'eval',
      'actions',
      'console',
      'network',
      'cdp',
    ]) {
      expect(limitations[unsupported], false, reason: unsupported);
    }
    expect(limitations['screenshot'], true);
    expect(limitations['dom'], true);
  });

  test(
    'project defaults to the UI-selected project and redacts targetUrl',
    () async {
      selectedProjectId = projectA.id;
      // A stale controller value must not be trusted as the current project.
      workspace = const WorkspaceState(selectedProjectId: 'stale-id');

      final project =
          (await run({'op': 'project'}))['project']! as Map<String, Object?>;
      expect(project['id'], projectA.id);
      expect(
        project['targetUrl'],
        'https://alpha.example.com:8443/app',
        reason: 'userinfo, query and fragment must be stripped',
      );
    },
  );

  test(
    'project returns a null wrapper with no UI selection and 404 for unknown id',
    () async {
      // Every singular op keeps a stable envelope, so an absent object is
      // data rather than a null payload a client cannot attribute.
      expect(await run({'op': 'project'}), {'project': null});
      expect(
        queries.dispatch({'op': 'project', 'projectId': 'missing'}),
        failure('not_found', 404),
      );
      expect(
        queries.dispatch({'op': 'project', 'projectId': 5}),
        failure('invalid_argument', 400),
      );

      // A selection that no longer resolves still reads as an explicit null.
      selectedProjectId = 'deleted-project';
      expect(await run({'op': 'project'}), {'project': null});
    },
  );

  test(
    'singular ops wrap their value and null when nothing is selected',
    () async {
      selectedProjectId = null;
      expect(await run({'op': 'project'}), {'project': null});
      expect(await run({'op': 'identity'}), {'identity': null});
      expect(await run({'op': 'panel'}), {'panel': null});
      expect(await run({'op': 'window'}), {'window': null});
      expect(await run({'op': 'workspace'}), {'workspace': null});
    },
  );

  test(
    'identities scopes to project and marks sharedSession not isolated',
    () async {
      final data = await run({'op': 'identities', 'projectId': projectA.id});
      expect(data['projectId'], projectA.id);
      final list = (data['identities'] as List).cast<Map<String, Object?>>();
      expect(list.map((i) => i['id']), containsAll(['id-a1', 'id-a2']));

      final shared = list.firstWhere((i) => i['id'] == 'id-a2');
      expect(shared['isolationMode'], 'sharedSession');
      expect(shared['isIsolated'], false);

      final isolated = list.firstWhere((i) => i['id'] == 'id-a1');
      expect(isolated['isIsolated'], true);
      // Relative startPath is stripped of query/fragment like any URL.
      expect(isolated['startPath'], '/home');
    },
  );

  test('identities without a current project returns an empty list', () async {
    final data = await run({'op': 'identities'});
    expect(data['projectId'], isNull);
    expect(data['identities'], isEmpty);
    expect(
      queries.dispatch({'op': 'identities', 'projectId': 'missing'}),
      failure('not_found', 404),
    );
  });

  test('redaction keeps safe URL parts and drops everything else', () async {
    // A relative reference that is only a query and a fragment has no path
    // left to keep: the raw string must not be echoed back.
    await identities.create(
      id: 'id-query-only',
      projectId: projectA.id,
      name: 'Query only',
      color: '#444444',
      isolationMode: IsolationMode.nativeProfile,
      startPath: '?token=secret#x',
    );
    await identities.create(
      id: 'id-frag-only',
      projectId: projectA.id,
      name: 'Fragment only',
      color: '#555555',
      isolationMode: IsolationMode.nativeProfile,
      startPath: '#session=secret',
    );
    // An authority whose userinfo leaves no host cannot be reduced safely.
    final projectNoHost = await projects.create(
      name: 'No host',
      targetUrl: 'https://user:secret@',
    );
    final malformed = await projects.create(
      name: 'Malformed',
      targetUrl: 'http://[::1/x',
    );

    final list =
        (await run({
              'op': 'identities',
              'projectId': projectA.id,
            }))['identities']
            as List;
    final items = list.cast<Map<String, Object?>>();
    expect(
      items.firstWhere((i) => i['id'] == 'id-query-only')['startPath'],
      '',
      reason: 'a query-only startPath has no safe path component',
    );
    expect(items.firstWhere((i) => i['id'] == 'id-frag-only')['startPath'], '');

    Future<Map<String, Object?>> projectOf(String id) async =>
        (await run({'op': 'project', 'projectId': id}))['project']!
            as Map<String, Object?>;
    expect((await projectOf(projectNoHost.id))['targetUrl'], '');
    expect((await projectOf(malformed.id))['targetUrl'], '');

    // IPv6 hosts and explicit ports survive, without the userinfo.
    final projectV6 = await projects.create(
      name: 'IPv6',
      targetUrl: 'http://u:p@[2001:db8::1]:9000/app?key=v#frag',
    );
    expect(
      (await projectOf(projectV6.id))['targetUrl'],
      'http://[2001:db8::1]:9000/app',
    );
  });

  test('no read operation leaks credentials, tokens or fragments', () async {
    await identities.create(
      id: 'id-5',
      projectId: projectA.id,
      name: 'Query bearer',
      color: '#666666',
      isolationMode: IsolationMode.nativeProfile,
      startPath: '?token=topsecret#topsecret',
    );
    selectedProjectId = projectA.id;
    workspace = WorkspaceState(
      panels: {
        'id-a1': makePanel('id-a1', url: 'https://u:pw@a.example.com/x?k=v#f'),
        'id-b1': makePanel('id-b1', url: 'http://[::1/broken'),
      },
      selectedPanelId: 'id-a1',
    );
    native = nativeSnapshot(
      currentWindowId: 1,
      mainWindowId: 1,
      windows: [nativeWindow(1, isKey: true, isMain: true)],
      views: [nativeView(10, 'id-a1', windowId: 1, hasKeyboardFocus: true)],
    );

    for (final command in <Map<String, dynamic>>[
      {'op': 'state'},
      {'op': 'projects'},
      {'op': 'project'},
      {'op': 'identities'},
      {'op': 'identity'},
      {'op': 'panels'},
      {'op': 'panel'},
      {'op': 'windows'},
      {'op': 'window'},
      {'op': 'workspaces'},
      {'op': 'workspace'},
    ]) {
      final encoded = jsonEncode(await queries.dispatch(command));
      for (final secret in [
        'secret',
        'topsecret',
        'password',
        'pw@',
        'u:p@',
        'token',
      ]) {
        expect(
          encoded.contains(secret),
          isFalse,
          reason: '${command['op']} must not expose "$secret"',
        );
      }
    }
  });

  test('state reports UI selection and native focus separately', () async {
    selectedProjectId = projectA.id;
    workspace = WorkspaceState(
      layoutMode: LayoutMode.columns,
      panels: {
        'id-a1': makePanel('id-a1'),
        'id-a2': makePanel('id-a2', isolationMode: IsolationMode.sharedSession),
      },
      selectedPanelId: 'id-a1',
      selectedProjectId: projectA.id,
    );
    native = nativeSnapshot(
      currentWindowId: 1,
      mainWindowId: 1,
      windows: [nativeWindow(1, isKey: true, isMain: true)],
      views: [
        nativeView(10, 'id-a1', windowId: 1),
        nativeView(11, 'id-a2', windowId: 1, hasKeyboardFocus: true),
      ],
    );

    final data = await run({'op': 'state'});
    expect(data['selectionConsistent'], true);
    expect(data['layoutMode'], 'columns');
    expect(data['selectedIdentityId'], 'id-a1');
    expect(data['focusedIdentityId'], 'id-a2');
    expect((data['project'] as Map)['id'], projectA.id);
    expect((data['identity'] as Map)['id'], 'id-a1');
    final panel = data['panel'] as Map<String, Object?>;
    expect(panel['identityId'], 'id-a1');
    expect(panel['selected'], true);
    expect(panel['nativeViewId'], 10);
    expect(panel['windowId'], 1);
    expect(panel['hasKeyboardFocus'], false);
    expect((data['window'] as Map)['windowId'], 1);
    expect(data['capturedAt'], isA<String>());
  });

  test(
    'stale selection from another project is inconsistent, not impersonated',
    () async {
      // The UI moved to project B while a panel from project A is still
      // selected — a legal transient during project switching.
      selectedProjectId = projectB.id;
      workspace = WorkspaceState(
        panels: {'id-a1': makePanel('id-a1')},
        selectedPanelId: 'id-a1',
        selectedProjectId: projectA.id, // stale controller value
      );

      final data = await run({'op': 'state'});
      expect(data['selectionConsistent'], false);
      expect(data['selectedIdentityId'], 'id-a1');
      expect(data['identity'], isNull);
      expect(data['panel'], isNull);
      expect((data['project'] as Map)['id'], projectB.id);

      // Singular reads must not leak the stale identity either.
      expect(await run({'op': 'identity'}), {'identity': null});
      expect(await run({'op': 'panel'}), {'panel': null});
    },
  );

  test('a selected identity without a live panel is inconsistent', () async {
    // The panel has already been torn down, but the selection still names it.
    selectedProjectId = projectA.id;
    workspace = const WorkspaceState(selectedPanelId: 'id-a1');

    final data = await run({'op': 'state'});
    expect(data['selectionConsistent'], false);
    expect(data['selectedIdentityId'], 'id-a1');
    expect(data['identity'], isNull);
    expect(data['panel'], isNull);
    expect(await run({'op': 'identity'}), {'identity': null});
    expect(await run({'op': 'panel'}), {'panel': null});

    // The identity row itself is still reachable when named explicitly.
    final explicit = await run({'op': 'identity', 'identityId': 'id-a1'});
    expect((explicit['identity']! as Map)['id'], 'id-a1');
  });

  test(
    'state reports the selection captured before the native sample',
    () async {
      selectedProjectId = projectA.id;
      workspace = WorkspaceState(
        panels: {'id-a1': makePanel('id-a1')},
        selectedPanelId: 'id-a1',
        selectedProjectId: projectA.id,
      );

      // The user switches to project B while the native sample is still in
      // flight. The answer must describe the captured moment, not whatever the
      // provider says after the await.
      final pending = Completer<Map<String, dynamic>>();
      queries = buildQueries(
        nativeReader: () async {
          selectedProjectId = projectB.id;
          workspace = WorkspaceState(
            panels: {'id-b1': makePanel('id-b1')},
            selectedPanelId: 'id-b1',
            selectedProjectId: projectB.id,
          );
          return pending.future;
        },
      );
      final future = queries.dispatch({'op': 'state'});
      pending.complete(
        nativeSnapshot(
          currentWindowId: 1,
          mainWindowId: 1,
          windows: [nativeWindow(1, isKey: true, isMain: true)],
          views: [nativeView(10, 'id-a1', windowId: 1)],
        ),
      );

      final data = (await future) as Map<String, Object?>;
      expect((data['project'] as Map)['id'], projectA.id);
      expect((data['identity'] as Map)['id'], 'id-a1');
      expect(data['selectedIdentityId'], 'id-a1');
      expect(data['selectionConsistent'], isTrue);
      // The provider has moved on, which the next query observes.
      expect(selectedProjectId, projectB.id);
    },
  );

  test(
    'no current window means no current window even when a window is main',
    () async {
      selectedProjectId = projectA.id;
      workspace = WorkspaceState(
        panels: {'id-a1': makePanel('id-a1')},
        selectedPanelId: 'id-a1',
      );
      native = nativeSnapshot(
        currentWindowId: null,
        mainWindowId: 1,
        windows: [nativeWindow(1, isMain: true)],
        views: [nativeView(10, 'id-a1', windowId: 1)],
      );

      final data = await run({'op': 'state'});
      expect(data['window'], isNull);
      expect(data['focusedIdentityId'], isNull);
      expect(await run({'op': 'window'}), {'window': null});

      final windows = await run({'op': 'windows'});
      expect(windows['mainWindowId'], 1);
      expect(windows['currentWindowId'], isNull);
      final list = (windows['windows'] as List).cast<Map<String, Object?>>();
      expect(list.single['identityIds'], ['id-a1']);
    },
  );

  test('a stale isKey flag never becomes the current window', () async {
    // An NSWindow can keep isKey == true after the app has already lost key
    // status, and mainWindowId still points at the same window. Neither may
    // stand in for the current window: only currentWindowId decides.
    selectedProjectId = projectA.id;
    workspace = WorkspaceState(
      panels: {'id-a1': makePanel('id-a1')},
      selectedPanelId: 'id-a1',
    );
    native = nativeSnapshot(
      currentWindowId: null,
      mainWindowId: 1,
      windows: [nativeWindow(1, isKey: true, isMain: true)],
      views: [nativeView(10, 'id-a1', windowId: 1)],
    );

    expect(await run({'op': 'window'}), {'window': null});
    expect((await run({'op': 'state'}))['window'], isNull);

    // The flag is still reported as sampled, and the window is still listable
    // and reachable by explicit id.
    final windows = await run({'op': 'windows'});
    expect((windows['windows'] as List).single['isKey'], true);
    expect(windows['currentWindowId'], isNull);
    final explicit = await run({'op': 'window', 'windowId': 1});
    expect((explicit['window']! as Map)['isKey'], true);
  });

  test('panels lists resident panels and filters by projectId', () async {
    workspace = WorkspaceState(
      panels: {
        'id-a1': makePanel('id-a1'),
        'id-b1': makePanel(
          'id-b1',
          url: 'https://u:p@beta.example.com:9000/x?token=z#f',
        ),
      },
    );
    native = nativeSnapshot(
      windows: [nativeWindow(1, isKey: true, isMain: true)],
      views: [nativeView(10, 'id-b1', windowId: 1)],
    );

    final all = (await run({'op': 'panels'}))['panels'] as List;
    expect(all, hasLength(2));

    final filtered =
        (await run({'op': 'panels', 'projectId': projectB.id}))['panels']
            as List;
    final panel = filtered.single as Map<String, Object?>;
    expect(panel['identityId'], 'id-b1');
    expect(panel['projectId'], projectB.id);
    expect(panel['identityName'], 'B1');
    expect(panel['url'], 'https://beta.example.com:9000/x');
    expect(panel['nativeViewId'], 10);

    expect(
      queries.dispatch({'op': 'panels', 'projectId': 'missing'}),
      failure('not_found', 404),
    );
  });

  test('panel resolves explicit ids and the current selection', () async {
    selectedProjectId = projectA.id;
    workspace = WorkspaceState(
      panels: {
        'id-a1': makePanel('id-a1', loading: true),
        'id-a2': makePanel('id-a2'),
      },
      selectedPanelId: 'id-a1',
    );

    final panel =
        (await run({'op': 'panel'}))['panel']! as Map<String, Object?>;
    expect(panel['identityId'], 'id-a1');
    expect(panel['loading'], true);
    expect(panel['layout'], isA<Map>());

    final explicit =
        (await run({'op': 'panel', 'identityId': 'id-a2'}))['panel']!
            as Map<String, Object?>;
    expect(explicit['identityId'], 'id-a2');

    expect(
      queries.dispatch({'op': 'panel', 'identityId': 'not-open'}),
      failure('not_found', 404),
    );
    expect(
      queries.dispatch({'op': 'panel', 'identityId': 7}),
      failure('invalid_argument', 400),
    );
  });

  test('window resolves by id or the current window only', () async {
    native = nativeSnapshot(
      currentWindowId: 2,
      mainWindowId: 1,
      windows: [nativeWindow(1, isMain: true), nativeWindow(2, isKey: true)],
      views: [nativeView(10, 'id-a1', windowId: 2)],
    );

    final current =
        (await run({'op': 'window'}))['window']! as Map<String, Object?>;
    expect(current['windowId'], 2);
    expect(current['isKey'], true);
    expect(current['identityIds'], ['id-a1']);

    final explicit =
        (await run({'op': 'window', 'windowId': 1}))['window']!
            as Map<String, Object?>;
    expect(explicit['isMain'], true);

    expect(
      queries.dispatch({'op': 'window', 'windowId': 99}),
      failure('not_found', 404),
    );
    expect(
      queries.dispatch({'op': 'window', 'windowId': '1'}),
      failure('invalid_argument', 400),
    );

    // A currentWindowId with no matching window is not a main-window fallback.
    native = nativeSnapshot(
      currentWindowId: 7,
      mainWindowId: 1,
      windows: [nativeWindow(1, isMain: true)],
    );
    expect(await run({'op': 'window'}), {'window': null});
  });

  test('workspaces list and resolve the current named workspace', () async {
    selectedProjectId = projectA.id;
    final saved = await workspaces.save(
      WorkspaceLayout(
        id: 'ws-1',
        projectId: projectA.id,
        name: 'Main layout',
        layoutMode: LayoutMode.grid,
        updatedAt: 1,
        panels: [PanelLayout(identityId: 'id-a1', width: 640, height: 480)],
      ),
    );
    workspace = const WorkspaceState(selectedWorkspaceId: 'ws-1');

    final list = await run({'op': 'workspaces'});
    expect(list['projectId'], projectA.id);
    expect((list['workspaces'] as List).single, isA<Map>());

    final current =
        (await run({'op': 'workspace'}))['workspace']! as Map<String, Object?>;
    expect(current['id'], saved.id);
    expect(current['layoutMode'], 'grid');
    expect(((current['panels'] as List).single as Map)['identityId'], 'id-a1');
    expect((await run({'op': 'state'}))['workspaceId'], 'ws-1');

    expect(
      queries.dispatch({'op': 'workspace', 'workspaceId': 'missing'}),
      failure('not_found', 404),
    );

    workspace = const WorkspaceState();
    expect(await run({'op': 'workspace'}), {'workspace': null});
    expect((await run({'op': 'state'}))['workspaceId'], isNull);
  });

  test(
    'a loaded workspace from another project is not the current one',
    () async {
      // The layout stays loaded across a project switch, so it must not be
      // reported as project A's current named workspace.
      await workspaces.save(
        WorkspaceLayout(
          id: 'ws-b',
          projectId: projectB.id,
          name: 'Beta layout',
          layoutMode: LayoutMode.grid,
          updatedAt: 1,
          panels: [PanelLayout(identityId: 'id-b1', width: 640, height: 480)],
        ),
      );
      selectedProjectId = projectA.id;
      workspace = const WorkspaceState(selectedWorkspaceId: 'ws-b');

      expect((await run({'op': 'state'}))['workspaceId'], isNull);
      expect(await run({'op': 'workspace'}), {'workspace': null});

      // An explicit workspaceId still addresses the row it names, whatever the
      // UI currently has selected.
      final explicit =
          (await run({'op': 'workspace', 'workspaceId': 'ws-b'}))['workspace']!
              as Map<String, Object?>;
      expect(explicit['id'], 'ws-b');
      expect(explicit['projectId'], projectB.id);

      // With no project selected there is no current project to own a layout.
      selectedProjectId = null;
      expect(await run({'op': 'workspace'}), {'workspace': null});
      expect((await run({'op': 'state'}))['workspaceId'], isNull);
    },
  );

  test('mutation and unknown operations never enter dispatch', () async {
    for (final op in ['eval', 'nope']) {
      expect(
        queries.dispatch({'op': op}),
        failure('unsupported_operation', 400),
        reason: op,
      );
    }
    expect(queries.dispatch({'op': 5}), failure('invalid_argument', 400));
    expect(
      queries.dispatch(<String, dynamic>{}),
      failure('invalid_argument', 400),
    );
  });

  group('screenshot', () {
    const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3];

    Map<String, dynamic> shot({
      List<int> bytes = png,
      int width = 800,
      int height = 600,
      String? url = 'https://user:secret@a.example.com/path?q=1#f',
      Object? windowId = 83,
    }) => {
      'png': Uint8List.fromList(bytes),
      'width': width,
      'height': height,
      'url': url,
      'windowId': windowId,
    };

    test('requires an explicit identityId; no selection fallback', () async {
      workspace = WorkspaceState(
        panels: {'id-a1': makePanel('id-a1')},
        selectedPanelId: 'id-a1',
      );
      native = nativeSnapshot(views: [nativeView(9, 'id-a1', windowId: 1)]);
      // Selection exists but must not be picked up as the target.
      expect(
        queries.dispatch({'op': 'screenshot'}),
        failure('invalid_argument', 400),
      );
    });

    test('reports not_found for an unknown identity', () async {
      expect(
        queries.dispatch({'op': 'screenshot', 'identityId': 'missing'}),
        failure('not_found', 404),
      );
    });

    test('reports no_native_view when the panel has no live view', () async {
      // Identity exists and even has a panel, but the native inventory has
      // no view for it (closed panel, minimized, or view torn down).
      workspace = WorkspaceState(panels: {'id-a1': makePanel('id-a1')});
      native = nativeSnapshot();
      expect(
        queries.dispatch({'op': 'screenshot', 'identityId': 'id-a1'}),
        failure('no_native_view', 409),
      );
    });

    test('returns the captured PNG with bound metadata', () async {
      workspace = WorkspaceState(panels: {'id-a1': makePanel('id-a1')});
      native = nativeSnapshot(views: [nativeView(9, 'id-a1', windowId: 83)]);
      var boundViewId = -1;
      var boundIdentity = '';
      queries = buildQueries(
        screenshotCapturer: (viewId, expected) async {
          boundViewId = viewId;
          boundIdentity = expected;
          return shot();
        },
      );

      final data = await run({'op': 'screenshot', 'identityId': 'id-a1'});
      expect(boundViewId, 9);
      expect(boundIdentity, 'id-a1');
      expect(data['identityId'], 'id-a1');
      expect(data['projectId'], projectA.id);
      expect(data['nativeViewId'], 9);
      expect(data['windowId'], 83);
      expect(data['format'], 'png');
      expect(data['width'], 800);
      expect(data['height'], 600);
      expect(data['capturedAt'], isA<String>());
      // URL goes through the same stripping as every other field:
      // credentials, query and fragment are dropped.
      expect(data['url'], 'https://a.example.com/path');
      expect(base64Decode(data['pngBase64']! as String), png);
    });

    test('propagates target_changed as a 409, not a generic failure', () async {
      native = nativeSnapshot(views: [nativeView(9, 'id-a1', windowId: 1)]);
      queries = buildQueries(
        screenshotCapturer: (viewId, expected) async =>
            throw PlatformException(code: 'target_changed'),
      );
      expect(
        queries.dispatch({'op': 'screenshot', 'identityId': 'id-a1'}),
        failure('target_changed', 409),
      );
    });

    test('propagates snapshot_failed as a 500', () async {
      native = nativeSnapshot(views: [nativeView(9, 'id-a1', windowId: 1)]);
      queries = buildQueries(
        screenshotCapturer: (viewId, expected) async =>
            throw PlatformException(code: 'snapshot_failed'),
      );
      expect(
        queries.dispatch({'op': 'screenshot', 'identityId': 'id-a1'}),
        failure('snapshot_failed', 500),
      );
    });

    test('propagates snapshot_timeout and native too_large as 500s', () async {
      native = nativeSnapshot(views: [nativeView(9, 'id-a1', windowId: 1)]);
      for (final code in const ['snapshot_timeout', 'snapshot_too_large']) {
        queries = buildQueries(
          screenshotCapturer: (viewId, expected) async =>
              throw PlatformException(code: code),
        );
        expect(
          queries.dispatch({'op': 'screenshot', 'identityId': 'id-a1'}),
          failure(code, 500),
          reason: '$code must surface as a distinguishable wire error',
        );
      }
    });

    test('rejects a snapshot exceeding the PNG bound', () async {
      native = nativeSnapshot(views: [nativeView(9, 'id-a1', windowId: 1)]);
      final oversized = Uint8List(AutomationQueries.screenshotPngLimit + 1);
      queries = buildQueries(
        screenshotCapturer: (viewId, expected) async => shot(bytes: oversized),
      );
      expect(
        queries.dispatch({'op': 'screenshot', 'identityId': 'id-a1'}),
        failure('snapshot_too_large', 500),
      );
    });

    test('rejects a reply carrying no image data', () async {
      native = nativeSnapshot(views: [nativeView(9, 'id-a1', windowId: 1)]);
      queries = buildQueries(
        screenshotCapturer: (viewId, expected) async => {
          'width': 1,
          'height': 1,
        },
      );
      expect(
        queries.dispatch({'op': 'screenshot', 'identityId': 'id-a1'}),
        failure('snapshot_failed', 500),
      );
    });

    test(
      'capabilities advertises screenshot and the op is whitelisted',
      () async {
        final caps = await run({'op': 'capabilities'});
        expect((caps['limitations'] as Map)['screenshot'], isTrue);
        expect(
          (caps['operations'] as List).cast<String>(),
          contains('screenshot'),
        );
        // Read ops stay enumerable apart from the whitelisted writes —
        // screenshot is a read, never a write entry.
        expect(caps['readOnly'], isFalse);
        expect(
          (caps['writeOperations'] as List).cast<String>(),
          isNot(contains('screenshot')),
        );
        expect((caps['limitations'] as Map)['eval'], isFalse);
        expect((caps['limitations'] as Map)['actions'], isFalse);
      },
    );
  });

  group('media', () {
    Map<String, dynamic> sample({
      String? url = 'https://user:secret@a.example.com/page?q=1#f',
      Object? windowId = 83,
      String json = '{"frames":[]}' ,
    }) => {'json': json, 'url': url, 'windowId': windowId};

    test('requires an explicit identityId; no selection fallback', () async {
      workspace = WorkspaceState(
        panels: {'id-a1': makePanel('id-a1')},
        selectedPanelId: 'id-a1',
      );
      native = nativeSnapshot(views: [nativeView(9, 'id-a1', windowId: 1)]);
      expect(
        queries.dispatch({'op': 'media'}),
        failure('invalid_argument', 400),
      );
    });

    test('reports not_found for an unknown identity', () async {
      expect(
        queries.dispatch({'op': 'media', 'identityId': 'missing'}),
        failure('not_found', 404),
      );
    });

    test('reports no_native_view when the panel has no live view', () async {
      workspace = WorkspaceState(panels: {'id-a1': makePanel('id-a1')});
      native = nativeSnapshot();
      expect(
        queries.dispatch({'op': 'media', 'identityId': 'id-a1'}),
        failure('no_native_view', 409),
      );
    });

    test('returns frames with every URL sanitized', () async {
      workspace = WorkspaceState(panels: {'id-a1': makePanel('id-a1')});
      native = nativeSnapshot(views: [nativeView(9, 'id-a1', windowId: 83)]);
      var boundViewId = -1;
      var boundIdentity = '';
      const probeJson = '''
      {"frames":[
        {"index":0,"label":"main",
         "url":"https://u:p@a.example.com/v?tok=1#x",
         "reachable":true,
         "media":[{"index":0,"tag":"video","currentTime":12.5,
           "duration":98.0,"durationKind":"finite","paused":false,
           "ended":false,"seeking":false,"readyState":4,
           "playbackRate":1.0,"seekable":[[0,98.0]],"error":null}],
         "mediaCount":1},
        {"index":1,"label":"iframe0",
         "url":"https://ads.example.net/embed?click=2",
         "reachable":false,"reason":"unavailable","media":[],
         "mediaCount":0}
      ]}
      ''';
      queries = buildQueries(
        mediaSampler: (viewId, expected) async {
          boundViewId = viewId;
          boundIdentity = expected;
          return sample(json: probeJson);
        },
      );

      final data = await run({'op': 'media', 'identityId': 'id-a1'});
      expect(boundViewId, 9);
      expect(boundIdentity, 'id-a1');
      expect(data['identityId'], 'id-a1');
      expect(data['nativeViewId'], 9);
      expect(data['windowId'], 83);
      expect(data['sampledAt'], isA<String>());
      expect(data['url'], 'https://a.example.com/page');
      final frames = (data['frames'] as List).cast<Map<String, dynamic>>();
      expect(frames, hasLength(2));
      expect(frames[0]['url'], 'https://a.example.com/v');
      expect(frames[0]['reachable'], isTrue);
      expect((frames[0]['media'] as List), hasLength(1));
      expect(frames[1]['reachable'], isFalse);
      expect(frames[1]['url'], 'https://ads.example.net/embed');
      expect(data['truncated'], isFalse);
      expect(data['skippedFrames'], 0);
    });

    test('redacts opaque-scheme frame URLs without their payload', () async {
      workspace = WorkspaceState(panels: {'id-a1': makePanel('id-a1')});
      native = nativeSnapshot(views: [nativeView(9, 'id-a1', windowId: 83)]);
      const probeJson = '''
      {"frames":[
        {"index":0,"label":"main","url":"http://127.0.0.1/m.html",
         "reachable":true,"media":[],"mediaCount":0},
        {"index":1,"label":"f0",
         "url":"data:text/html,<p>SECRET-PAYLOAD-MARKER</p>",
         "reachable":false,"reason":"unavailable","media":[],
         "mediaCount":0},
        {"index":2,"label":"f1","url":"javascript:alert(1)",
         "reachable":false,"reason":"unavailable","media":[],
         "mediaCount":0}
      ],"truncated":true,"skippedFrames":3,"depthLimitSkipped":0}
      ''';
      queries = buildQueries(
        mediaSampler: (viewId, expected) async => sample(json: probeJson),
      );

      final data = await run({'op': 'media', 'identityId': 'id-a1'});
      final frames = (data['frames'] as List).cast<Map<String, dynamic>>();
      expect(frames[1]['url'], 'data:');
      expect(frames[2]['url'], 'javascript:');
      // The payload must not ride through on any field.
      expect(jsonEncode(data), isNot(contains('SECRET-PAYLOAD-MARKER')));
      expect(data['truncated'], isTrue);
      expect(data['skippedFrames'], 3);
    });

    test('maps target_changed to a 409 automation failure', () async {
      workspace = WorkspaceState(panels: {'id-a1': makePanel('id-a1')});
      native = nativeSnapshot(views: [nativeView(9, 'id-a1', windowId: 1)]);
      queries = buildQueries(
        mediaSampler: (viewId, expected) async =>
            throw PlatformException(code: 'target_changed'),
      );
      expect(
        queries.dispatch({'op': 'media', 'identityId': 'id-a1'}),
        failure('target_changed', 409),
      );
    });

    test('maps media_failed and media_timeout through their codes', () async {
      workspace = WorkspaceState(panels: {'id-a1': makePanel('id-a1')});
      native = nativeSnapshot(views: [nativeView(9, 'id-a1', windowId: 1)]);
      for (final code in ['media_failed', 'media_timeout']) {
        queries = buildQueries(
          mediaSampler: (viewId, expected) async =>
              throw PlatformException(code: code),
        );
        expect(
          queries.dispatch({'op': 'media', 'identityId': 'id-a1'}),
          failure(code, 500),
        );
      }
    });

    test('reports media_failed on a malformed probe payload', () async {
      workspace = WorkspaceState(panels: {'id-a1': makePanel('id-a1')});
      native = nativeSnapshot(views: [nativeView(9, 'id-a1', windowId: 1)]);
      queries = buildQueries(
        mediaSampler: (viewId, expected) async => sample(json: 'not json'),
      );
      expect(
        queries.dispatch({'op': 'media', 'identityId': 'id-a1'}),
        failure('media_failed', 500),
      );
    });

    test('capabilities advertises the media operation', () async {
      final caps = await run({'op': 'capabilities'});
      expect((caps['limitations'] as Map)['media'], isTrue);
      expect((caps['operations'] as List).cast<String>(), contains('media'));
    });
  });

  group('errors', () {
    Map<String, dynamic> drained({String json = '{"frames":[]}'}) => {
      'json': json,
      'url': 'http://127.0.0.1/e.html',
      'windowId': 83,
    };

    test('requires an explicit identityId', () async {
      queries = buildQueries();
      expect(
        queries.dispatch({'op': 'errors'}),
        failure('invalid_argument', 400),
      );
    });

    test('unknown identity is not_found', () async {
      queries = buildQueries();
      expect(
        queries.dispatch({'op': 'errors', 'identityId': 'nope'}),
        failure('not_found', 404),
      );
    });

    test('identity without live view is no_native_view', () async {
      workspace = WorkspaceState(panels: {'id-a1': makePanel('id-a1')});
      queries = buildQueries();
      expect(
        queries.dispatch({'op': 'errors', 'identityId': 'id-a1'}),
        failure('no_native_view', 409),
      );
    });

    test('returns sanitized frames and error entries', () async {
      workspace = WorkspaceState(panels: {'id-a1': makePanel('id-a1')});
      native = nativeSnapshot(views: [nativeView(9, 'id-a1', windowId: 83)]);
      const drainedJson = '''
      {"frames":[
        {"index":0,"label":"main","url":"http://x.local/e.html?sid=SECRET",
         "reachable":true,"installed":true,"bufferId":"b1",
         "collectedAt":"2026-10-08T21:00:00Z","overflow":0,"count":2,
         "errors":[
           {"t":"2026-10-08T21:00:01Z","kind":"error",
            "message":"boom","source":"http://x.local/app.js?k=TOK",
            "line":3,"col":9,"stack":"Error: boom"},
           {"t":"2026-10-08T21:00:02Z","kind":"unhandledrejection",
            "message":"p failed","source":null,"line":null,"col":null,
            "stack":null}
         ]},
        {"index":1,"label":"f0","url":"https://ads.example.net/if",
         "reachable":false,"reason":"unavailable","installed":false,
         "errors":[]}
      ]}
      ''';
      queries = buildQueries(
        errorsDrainer: (viewId, expected) async {
          expect(viewId, 9);
          expect(expected, 'id-a1');
          return drained(json: drainedJson);
        },
      );
      final data = await run({'op': 'errors', 'identityId': 'id-a1'});
      expect(data['identityId'], 'id-a1');
      expect(data['windowId'], 83);
      final frames = (data['frames'] as List).cast<Map<String, dynamic>>();
      expect(frames[0]['url'], 'http://x.local/e.html');
      expect(frames[0]['installed'], isTrue);
      expect(frames[0]['bufferId'], 'b1');
      final errors = (frames[0]['errors'] as List).cast<Map<String, dynamic>>();
      expect(errors[0]['kind'], 'error');
      expect(errors[0]['source'], 'http://x.local/app.js');
      expect(errors[1]['kind'], 'unhandledrejection');
      expect(frames[1]['reachable'], isFalse);
      expect(jsonEncode(data), isNot(contains('SECRET')));
      expect(jsonEncode(data), isNot(contains('TOK')));
    });

    test('maps target_changed to 409 and errors_failed/timeout to 500',
        () async {
      workspace = WorkspaceState(panels: {'id-a1': makePanel('id-a1')});
      native = nativeSnapshot(views: [nativeView(9, 'id-a1', windowId: 1)]);
      queries = buildQueries(
        errorsDrainer: (v, e) async => throw PlatformException(code: 'target_changed'),
      );
      expect(
        queries.dispatch({'op': 'errors', 'identityId': 'id-a1'}),
        failure('target_changed', 409),
      );
      for (final code in ['errors_failed', 'errors_timeout']) {
        queries = buildQueries(
          errorsDrainer: (v, e) async => throw PlatformException(code: code),
        );
        expect(
          queries.dispatch({'op': 'errors', 'identityId': 'id-a1'}),
          failure(code, 500),
        );
      }
    });

    test('reports errors_failed on a malformed drain payload', () async {
      workspace = WorkspaceState(panels: {'id-a1': makePanel('id-a1')});
      native = nativeSnapshot(views: [nativeView(9, 'id-a1', windowId: 1)]);
      queries = buildQueries(
        errorsDrainer: (v, e) async => drained(json: 'garbage'),
      );
      expect(
        queries.dispatch({'op': 'errors', 'identityId': 'id-a1'}),
        failure('errors_failed', 500),
      );
    });

    test('capabilities advertises the errors operation', () async {
      final caps = await run({'op': 'capabilities'});
      expect((caps['limitations'] as Map)['errors'], isTrue);
      expect((caps['operations'] as List).cast<String>(), contains('errors'));
    });
  });

  group('activate_project', () {
    test('requires an explicit projectId', () async {
      queries = buildQueries();
      expect(
        queries.dispatch({'op': 'activate_project'}),
        failure('invalid_argument', 400),
      );
    });

    test('unknown project is not_found and selects nothing', () async {
      var calls = 0;
      queries = buildQueries(selectProject: (_) => calls++);
      expect(
        queries.dispatch({'op': 'activate_project', 'projectId': 'nope'}),
        failure('not_found', 404),
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, 0);
      expect(selectedProjectId, isNull);
    });

    test('activates through the UI entry point and reports settled state',
        () async {
      workspace = WorkspaceState(
        panels: {'id-a1': makePanel('id-a1')},
        selectedPanelId: 'id-a1',
        selectedProjectId: projectA.id,
      );
      selectedProjectId = projectA.id;
      native = nativeSnapshot(
        views: [nativeView(9, 'id-a1', windowId: 83, hasKeyboardFocus: true)],
      );
      final calls = <String>[];
      queries = buildQueries(
        selectProject: (id) {
          calls.add(id);
          selectedProjectId = id;
          workspace = workspace.copyWith(selectedProjectId: id);
        },
      );
      final data = await run({
        'op': 'activate_project',
        'projectId': projectB.id,
      });
      expect(calls, [projectB.id]);
      expect(data['projectId'], projectB.id);
      expect(data['alreadyActive'], false);
      expect(data['selectedProjectId'], projectB.id);
      expect(data['workspaceSelectedProjectId'], projectB.id);
      expect(data['settled'], true);
      expect(data['frameSettled'], true);
      // The stale UI selection of project A's panel is reported, never
      // silently re-attributed to project B.
      expect(data['selectedPanelId'], 'id-a1');
      expect(data['selectionConsistent'], false);
      // Native focus is a separate signal from UI selection.
      expect(data['focusedIdentityId'], 'id-a1');
      final panels = (data['panels'] as List).cast<Map<String, dynamic>>();
      expect(panels.single['identityId'], 'id-a1');
      expect(panels.single['nativeViewId'], 9);
      expect(jsonEncode(data), isNot(contains('secret')));
      expect(jsonEncode(data), isNot(contains('token')));
    });

    test('re-activating the current project is idempotent', () async {
      workspace = WorkspaceState(selectedProjectId: projectA.id);
      selectedProjectId = projectA.id;
      var calls = 0;
      queries = buildQueries(selectProject: (_) => calls++);
      final data = await run({
        'op': 'activate_project',
        'projectId': projectA.id,
      });
      expect(data['alreadyActive'], true);
      expect(data['settled'], true);
      // No redundant provider call: an idempotent activate leaves the UI
      // untouched instead of re-running project-switch side effects.
      expect(calls, 0);
    });

    test(
      'reports settled:false when the workspace marker stays behind',
      () async {
        selectedProjectId = null;
        // selectProject updates only the provider-level selection; the
        // workspace marker never catches up inside the settle budget.
        queries = buildQueries(
          selectProject: (id) => selectedProjectId = id,
          settleBudget: const Duration(milliseconds: 150),
        );
        final data = await run({
          'op': 'activate_project',
          'projectId': projectB.id,
        });
        expect(data['selectedProjectId'], projectB.id);
        expect(data['workspaceSelectedProjectId'], isNull);
        expect(data['settled'], false);
        expect(data['frameSettled'], true);
      },
    );

    test('write ops are no longer rejected as unsupported_operation', () async {
      queries = buildQueries();
      final data = await run({
        'op': 'activate_project',
        'projectId': projectB.id,
      });
      expect(data['projectId'], projectB.id);
    });

    test('UI selection drifting away during activation is target_changed',
        () async {
      selectedProjectId = projectA.id;
      // UI-level switch to project B lands while the op waits a frame —
      // the workspace marker is left bound to A to mimic a partial switch.
      queries = buildQueries(
        awaitFrame: () async {
          selectedProjectId = projectB.id;
        },
      );
      expect(
        queries.dispatch({'op': 'activate_project', 'projectId': projectA.id}),
        failure('target_changed', 409),
      );
    });

  group('dom', () {
    Map<String, dynamic> domPayload() => {
      'documentId': 'abc123',
      'title': 'PAGE',
      'url': 'http://127.0.0.1:8901/a.html?token=x#f',
      'frames': [
        {
          'index': 0,
          'label': 'main',
          'url': 'http://127.0.0.1:8901/a.html?token=x#f',
          'documentId': 'abc123:0',
          'depth': 0,
          'reachable': true,
          'elements': [
            {
              'ref': '0.0',
              'tag': 'a',
              'label': 'Home',
              'href': 'https://u:p@ex.com:9/p?q=1#s',
            },
            {'ref': '0.1', 'tag': 'input', 'inputType': 'password', 'name': 'pw'},
          ],
          'elementCount': 2,
          'title': 'PAGE',
          'text': 'hello',
        },
        {
          'index': 1,
          'label': 'f0',
          'url': 'https://other.example/x?k=v',
          'documentId': 'abc123:1',
          'depth': 1,
          'reachable': false,
          'reason': 'unavailable',
          'elements': [],
          'elementCount': 0,
          'text': '',
        },
      ],
      'truncated': true,
      'skipped': {'nodes': 3, 'frames': 0, 'hidden': 1, 'textTruncated': 2},
    };

    test('requires an explicit identityId', () async {
      queries = buildQueries();
      expect(
        queries.dispatch({'op': 'dom'}),
        failure('invalid_argument', 400),
      );
    });

    test('unknown identity is not_found; no view is no_native_view', () async {
      queries = buildQueries();
      expect(
        queries.dispatch({'op': 'dom', 'identityId': 'nope'}),
        failure('not_found', 404),
      );
      expect(
        queries.dispatch({'op': 'dom', 'identityId': 'id-a1'}),
        failure('no_native_view', 409),
      );
    });

    test('returns the bounded document with sanitized URLs', () async {
      native = nativeSnapshot(
        views: [nativeView(9, 'id-a1', windowId: 83)],
      );
      queries = buildQueries(
        domProber: (viewId, identityId) async => {
          'json': jsonEncode(domPayload()),
          'url': 'http://127.0.0.1:8901/a.html?token=x#f',
          'windowId': 83,
        },
      );
      final data = await run({'op': 'dom', 'identityId': 'id-a1'});
      expect(data['documentId'], 'abc123');
      expect(data['title'], 'PAGE');
      expect(data['url'], 'http://127.0.0.1:8901/a.html');
      expect(data['nativeViewId'], 9);
      expect(data['windowId'], 83);
      expect(data['truncated'], true);
      expect((data['skipped'] as Map)['hidden'], 1);
      final frames = (data['frames'] as List).cast<Map>();
      expect(frames.length, 2);
      expect(frames[0]['url'], 'http://127.0.0.1:8901/a.html');
      final els = (frames[0]['elements'] as List).cast<Map>();
      expect(els[0]['href'], 'https://ex.com:9/p');
      expect(els[1]['inputType'], 'password');
      expect(frames[1]['reachable'], false);
      expect(frames[1]['reason'], 'unavailable');
      // The page's own query/fragment never crosses the transport.
      final encoded = jsonEncode(data);
      expect(encoded, isNot(contains('token=x')));
      expect(encoded, isNot(contains('?q=1')));
      expect(encoded, isNot(contains('u:p@')));
    });

    test('drift mid-probe is target_changed', () async {
      native = nativeSnapshot(
        views: [nativeView(9, 'id-a1', windowId: 83)],
      );
      queries = buildQueries(
        domProber: (viewId, identityId) async =>
            throw PlatformException(code: 'target_changed'),
      );
      expect(
        queries.dispatch({'op': 'dom', 'identityId': 'id-a1'}),
        failure('target_changed', 409),
      );
    });

    test('malformed probe JSON is dom_failed', () async {
      native = nativeSnapshot(
        views: [nativeView(9, 'id-a1', windowId: 83)],
      );
      queries = buildQueries(
        domProber: (viewId, identityId) async => {
          'json': 'not-json',
          'url': null,
          'windowId': 83,
        },
      );
      expect(
        queries.dispatch({'op': 'dom', 'identityId': 'id-a1'}),
        failure('dom_failed', 500),
      );
    });
  });

  group('dom_find', () {
    void wireView() {
      native = nativeSnapshot(
        views: [nativeView(9, 'id-a1', windowId: 83)],
      );
    }

    test('requires identityId and exactly one criterion', () async {
      queries = buildQueries();
      expect(
        queries.dispatch({'op': 'dom_find'}),
        failure('invalid_argument', 400),
      );
      expect(
        queries.dispatch({'op': 'dom_find', 'identityId': 'id-a1'}),
        failure('invalid_argument', 400),
      );
      expect(
        queries.dispatch({
          'op': 'dom_find',
          'identityId': 'id-a1',
          'text': 'x',
          'selector': 'div',
        }),
        failure('invalid_argument', 400),
      );
      expect(
        queries.dispatch({
          'op': 'dom_find',
          'identityId': 'id-a1',
          'text': 'x',
          'match': 'regex',
        }),
        failure('invalid_argument', 400),
      );
    });

    test('forwards validated criteria as JSON and returns matches', () async {
      wireView();
      String? sent;
      queries = buildQueries(
        domFinder: (viewId, identityId, query) async {
          sent = query;
          return {
            'json': jsonEncode({
              'documentId': 'doc9',
              'count': 2,
              'truncated': false,
              'matches': [
                {
                  'ref': '0.12',
                  'frame': 'main',
                  'tag': 'button',
                  'role': 'button',
                  'label': 'Save',
                  'visible': true,
                  'disabled': false,
                },
                {
                  'ref': '1.3',
                  'frame': 'f0',
                  'tag': 'button',
                  'role': 'button',
                  'label': 'Save draft',
                  'visible': true,
                  'disabled': true,
                },
              ],
            }),
            'url': 'http://127.0.0.1:8901/p?t=1',
            'windowId': 83,
          };
        },
      );
      final data = await run({
        'op': 'dom_find',
        'identityId': 'id-a1',
        'role': 'button',
        'name': 'Save',
        'frame': 'f0',
      });
      final sentQuery = jsonDecode(sent!) as Map;
      expect(sentQuery['kind'], 'role');
      expect(sentQuery['role'], 'button');
      expect(sentQuery['name'], 'Save');
      expect(sentQuery['frame'], 'f0');
      expect(sentQuery['match'], 'contains');
      expect(data['matchCount'], 2);
      expect(data['documentId'], 'doc9');
      expect(data['url'], 'http://127.0.0.1:8901/p');
      final matches = (data['matches'] as List).cast<Map>();
      expect(matches.length, 2);
      expect(matches[0]['ref'], '0.12');
      expect(matches[1]['disabled'], true);
      // Multi-match is a list — never an auto-picked first.
    });

    test('zero matches is not_found', () async {
      wireView();
      queries = buildQueries(
        domFinder: (viewId, identityId, query) async => {
          'json': jsonEncode({'documentId': 'd', 'count': 0, 'matches': []}),
          'url': null,
          'windowId': 83,
        },
      );
      expect(
        queries.dispatch({
          'op': 'dom_find',
          'identityId': 'id-a1',
          'text': 'nothing',
        }),
        failure('not_found', 404),
      );
    });

    test('invalid_selector and frame_unreachable map distinctly', () async {
      wireView();
      queries = buildQueries(
        domFinder: (viewId, identityId, query) async => {
          'json': jsonEncode({'error': 'invalid_selector', 'message': 'bad'}),
          'url': null,
          'windowId': 83,
        },
      );
      expect(
        queries.dispatch({
          'op': 'dom_find',
          'identityId': 'id-a1',
          'selector': '[[[',
        }),
        failure('invalid_selector', 400),
      );
      queries = buildQueries(
        domFinder: (viewId, identityId, query) async => {
          'json': jsonEncode({'error': 'frame_unreachable', 'message': 'xo'}),
          'url': null,
          'windowId': 83,
        },
      );
      expect(
        queries.dispatch({
          'op': 'dom_find',
          'identityId': 'id-a1',
          'text': 'x',
          'frame': 'f1',
        }),
        failure('frame_unreachable', 409),
      );
    });

    test('drift mid-find is target_changed', () async {
      wireView();
      queries = buildQueries(
        domFinder: (viewId, identityId, query) async =>
            throw PlatformException(code: 'target_changed'),
      );
      expect(
        queries.dispatch({
          'op': 'dom_find',
          'identityId': 'id-a1',
          'text': 'x',
        }),
        failure('target_changed', 409),
      );
    });
  });

  group('dom_inspect', () {
    void wireView() {
      native = nativeSnapshot(
        views: [nativeView(9, 'id-a1', windowId: 83)],
      );
    }

    test('requires identityId, ref and documentId', () async {
      queries = buildQueries();
      expect(
        queries.dispatch({'op': 'dom_inspect', 'identityId': 'id-a1'}),
        failure('invalid_argument', 400),
      );
      expect(
        queries.dispatch({
          'op': 'dom_inspect',
          'identityId': 'id-a1',
          'ref': '0.12',
        }),
        failure('invalid_argument', 400),
      );
    });

    test('forwards ref + documentId and returns the element', () async {
      wireView();
      String? sent;
      queries = buildQueries(
        domInspector: (viewId, identityId, query) async {
          sent = query;
          return {
            'json': jsonEncode({
              'ref': '0.12',
              'frame': 'main',
              'frameIndex': 0,
              'tag': 'button',
              'role': 'button',
              'name': 'Save',
              'visible': true,
              'disabled': false,
              'checked': null,
              'selected': null,
              'focused': false,
              'attrs': {
                'id': 'save-btn',
                'href': 'https://ex.com/a?token=zzz',
                'aria-disabled': 'false',
              },
              'rect': {
                'x': 10.5,
                'y': 22.0,
                'width': 90.0,
                'height': 28.0,
                'coordinateSpace': 'frame',
              },
              'documentId': 'nonce1:0',
            }),
            'url': 'http://127.0.0.1:8901/p',
            'windowId': 83,
          };
        },
      );
      final data = await run({
        'op': 'dom_inspect',
        'identityId': 'id-a1',
        'ref': '0.12',
        'documentId': 'nonce1:0',
      });
      final sentQuery = jsonDecode(sent!) as Map;
      expect(sentQuery['ref'], '0.12');
      expect(sentQuery['documentId'], 'nonce1:0');
      final el = data['element'] as Map;
      expect(el['tag'], 'button');
      expect(el['rect']['coordinateSpace'], 'frame');
      // href is sanitized like every other URL field.
      expect((el['attrs'] as Map)['href'], 'https://ex.com/a');
    });

    test('stale_element and frame_unreachable map distinctly', () async {
      wireView();
      queries = buildQueries(
        domInspector: (viewId, identityId, query) async => {
          'json': jsonEncode({'error': 'stale_element', 'message': 'moved'}),
          'url': null,
          'windowId': 83,
        },
      );
      expect(
        queries.dispatch({
          'op': 'dom_inspect',
          'identityId': 'id-a1',
          'ref': '0.12',
          'documentId': 'd',
        }),
        failure('stale_element', 409),
      );
      queries = buildQueries(
        domInspector: (viewId, identityId, query) async => {
          'json': jsonEncode({'error': 'frame_unreachable', 'message': 'xo'}),
          'url': null,
          'windowId': 83,
        },
      );
      expect(
        queries.dispatch({
          'op': 'dom_inspect',
          'identityId': 'id-a1',
          'ref': '1.3',
          'documentId': 'd',
        }),
        failure('frame_unreachable', 409),
      );
    });

    test('drift mid-inspect is target_changed', () async {
      wireView();
      queries = buildQueries(
        domInspector: (viewId, identityId, query) async =>
            throw PlatformException(code: 'target_changed'),
      );
      expect(
        queries.dispatch({
          'op': 'dom_inspect',
          'identityId': 'id-a1',
          'ref': '0.1',
          'documentId': 'd',
        }),
        failure('target_changed', 409),
      );
    });
  });

  group('open_panel', () {
    test('requires an explicit identityId', () async {
      queries = buildQueries();
      expect(
        queries.dispatch({'op': 'open_panel'}),
        failure('invalid_argument', 400),
      );
    });

    test('unknown identity is not_found', () async {
      queries = buildQueries();
      expect(
        queries.dispatch({'op': 'open_panel', 'identityId': 'nope'}),
        failure('not_found', 404),
      );
    });

    test('identity of an inactive project is project_not_active', () async {
      selectedProjectId = projectA.id;
      var calls = 0;
      queries = buildQueries(ensurePanel: (_, _) => calls++);
      expect(
        queries.dispatch({'op': 'open_panel', 'identityId': 'id-b1'}),
        failure('project_not_active', 409),
      );
      await Future<void>.delayed(Duration.zero);
      // No implicit switch of project B — nothing was ensured.
      expect(calls, 0);
      expect(selectedProjectId, projectA.id);
    });

    test('already-open panel returns idempotently without ensure', () async {
      workspace = WorkspaceState(
        panels: {'id-a1': makePanel('id-a1', state: WebviewState.embedded)},
        selectedPanelId: 'id-a1',
      );
      selectedProjectId = projectA.id;
      native = nativeSnapshot(
        views: [nativeView(9, 'id-a1', windowId: 83, hasKeyboardFocus: true)],
      );
      var calls = 0;
      queries = buildQueries(ensurePanel: (_, _) => calls++);
      final data = await run({'op': 'open_panel', 'identityId': 'id-a1'});
      expect(calls, 0);
      expect(data['alreadyOpen'], true);
      expect(data['nativeViewId'], 9);
      expect(data['windowId'], 83);
      expect(data['selected'], true);
      expect(data['hasKeyboardFocus'], true);
      expect(data['viewReady'], true);
      final panel = (data['panel'] as Map).cast<String, dynamic>();
      expect(panel['state'], 'embedded');
      expect(jsonEncode(data), isNot(contains('token=abc')));
    });

    test('closed identity is ensured through the controller entry', () async {
      workspace = const WorkspaceState();
      selectedProjectId = projectA.id;
      final calls = <String>[];
      queries = buildQueries(
        ensurePanel: (i, p) {
          calls.add('${i.id}@${p.id}');
          final panels = Map<String, PanelRuntime>.from(workspace.panels);
          panels[i.id] = makePanel(i.id, state: WebviewState.openingEmbedded);
          workspace = workspace.copyWith(
            panels: panels,
            selectedProjectId: p.id,
          );
        },
      );
      final data = await run({'op': 'open_panel', 'identityId': 'id-a1'});
      expect(calls, ['id-a1@${projectA.id}']);
      expect(data['alreadyOpen'], false);
      final panel = (data['panel'] as Map).cast<String, dynamic>();
      expect(panel['state'], 'openingEmbedded');
      // No platform view has registered yet — viewReady stays honest.
      expect(data['viewReady'], false);
      expect(data['nativeViewId'], isNull);
    });

    test('ensured panel reports live binding once the view registers',
        () async {
      workspace = const WorkspaceState();
      selectedProjectId = projectA.id;
      native = nativeSnapshot(
        views: [nativeView(9, 'id-a1', windowId: 83)],
      );
      queries = buildQueries(
        ensurePanel: (i, p) {
          final panels = Map<String, PanelRuntime>.from(workspace.panels);
          panels[i.id] = makePanel(i.id, state: WebviewState.embedded);
          workspace = workspace.copyWith(
            panels: panels,
            selectedPanelId: workspace.selectedPanelId ?? i.id,
            selectedProjectId: p.id,
          );
        },
      );
      final data = await run({'op': 'open_panel', 'identityId': 'id-a1'});
      expect(data['alreadyOpen'], false);
      expect(data['nativeViewId'], 9);
      expect(data['viewReady'], true);
      expect(data['hasKeyboardFocus'], false);
    });

    test('vanishing panel is panel_not_open, never a silent success', () async {
      workspace = const WorkspaceState();
      selectedProjectId = projectA.id;
      queries = buildQueries(ensurePanel: (_, _) {});
      expect(
        queries.dispatch({'op': 'open_panel', 'identityId': 'id-a1'}),
        failure('panel_not_open', 409),
      );
    });

    test('project switch during the frame wait is target_changed', () async {
      workspace = const WorkspaceState();
      selectedProjectId = projectA.id;
      var ensured = 0;
      queries = buildQueries(
        ensurePanel: (i, p) {
          ensured++;
          final panels = Map<String, PanelRuntime>.from(workspace.panels);
          panels[i.id] = makePanel(i.id, state: WebviewState.openingEmbedded);
          workspace = workspace.copyWith(
            panels: panels,
            selectedProjectId: p.id,
          );
        },
        // A user-driven project switch lands while the op waits a frame.
        awaitFrame: () async {
          selectedProjectId = projectB.id;
          workspace = workspace.copyWith(selectedProjectId: projectB.id);
        },
      );
      expect(
        queries.dispatch({'op': 'open_panel', 'identityId': 'id-a1'}),
        failure('target_changed', 409),
      );
      await Future<void>.delayed(Duration.zero);
      // The mutation ran (it was committed before the switch), but the
      // response never claims a successful open on the drifted project.
      expect(ensured, 1);
    });
  });

    test('capabilities lists activate_project as a write operation', () async {
      final caps = await run({'op': 'capabilities'});
      expect(
        (caps['writeOperations'] as List).cast<String>(),
        contains('activate_project'),
      );
      expect(
        (caps['operations'] as List).cast<String>(),
        isNot(contains('activate_project')),
      );
      expect((caps['limitations'] as Map)['projectActivation'], isTrue);
    });
  });

  group('navigate', () {
    void setupTarget({String url = 'https://alpha.example.com/old'}) {
      workspace = WorkspaceState(
        panels: {
          'id-a1': makePanel('id-a1', url: url, state: WebviewState.embedded),
        },
        selectedPanelId: 'id-a1',
      );
      selectedProjectId = projectA.id;
      native = nativeSnapshot(
        views: [nativeView(9, 'id-a1', windowId: 83)],
      );
    }

    test('requires an explicit identityId', () async {
      queries = buildQueries();
      expect(
        queries.dispatch({'op': 'navigate', 'url': 'https://x.example.com'}),
        failure('invalid_argument', 400),
      );
    });

    test('requires an explicit url', () async {
      queries = buildQueries();
      expect(
        queries.dispatch({'op': 'navigate', 'identityId': 'id-a1'}),
        failure('invalid_argument', 400),
      );
    });

    test('a non-http URL is invalid_url', () async {
      setupTarget();
      queries = buildQueries();
      for (final url in ['ftp://x.example.com', 'javascript:alert(1)']) {
        expect(
          queries.dispatch({
            'op': 'navigate',
            'identityId': 'id-a1',
            'url': url,
          }),
          failure('invalid_url', 400),
          reason: url,
        );
      }
    });

    test('unknown identity is not_found', () async {
      queries = buildQueries();
      expect(
        queries.dispatch({
          'op': 'navigate',
          'identityId': 'nope',
          'url': 'https://x.example.com',
        }),
        failure('not_found', 404),
      );
    });

    test('identity of an inactive project is project_not_active', () async {
      selectedProjectId = projectA.id;
      var calls = 0;
      queries = buildQueries(navigatePanel: (_, _) => calls++);
      expect(
        queries.dispatch({
          'op': 'navigate',
          'identityId': 'id-b1',
          'url': 'https://x.example.com',
        }),
        failure('project_not_active', 409),
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, 0);
    });

    test('private host without allowPrivateNetwork is denied', () async {
      setupTarget();
      var calls = 0;
      queries = buildQueries(navigatePanel: (_, _) => calls++);
      for (final url in ['http://127.0.0.1:8901/a.html', 'localhost:8901/x']) {
        expect(
          queries.dispatch({
            'op': 'navigate',
            'identityId': 'id-a1',
            'url': url,
          }),
          failure('private_network_denied', 403),
          reason: url,
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(calls, 0);
    });

    test('private host passes when the project allows it', () async {
      final projectC = await projects.create(
        name: 'Priv',
        targetUrl: 'http://127.0.0.1:8901',
        allowPrivateNetwork: true,
      );
      await identities.create(
        id: 'id-c1',
        projectId: projectC.id,
        name: 'C1',
        color: '#333333',
        isolationMode: IsolationMode.nativeProfile,
      );
      workspace = WorkspaceState(
        panels: {
          'id-c1': makePanel('id-c1', state: WebviewState.embedded),
        },
        selectedPanelId: 'id-c1',
      );
      selectedProjectId = projectC.id;
      native = nativeSnapshot(views: [nativeView(9, 'id-c1')]);
      final controller = StreamController<WebviewEvent>();
      addTearDown(controller.close);
      queries = buildQueries(
        navigationEvents: () => controller.stream,
        navigatePanel: (id, url) {
          controller.add(WebviewLoadStarted(id, Uri.parse(url)));
          controller.add(WebviewLoadComplete(id, Uri.parse(url)));
        },
      );
      final data = await run({
        'op': 'navigate',
        'identityId': 'id-c1',
        'url': 'http://127.0.0.1:8901/a.html',
      });
      expect(data['status'], 'committed');
    });

    test('closed panel is panel_not_open', () async {
      workspace = const WorkspaceState();
      selectedProjectId = projectA.id;
      queries = buildQueries();
      expect(
        queries.dispatch({
          'op': 'navigate',
          'identityId': 'id-a1',
          'url': 'https://x.example.com',
        }),
        failure('panel_not_open', 409),
      );
    });

    test('panel without a registered view is no_native_view', () async {
      workspace = WorkspaceState(
        panels: {'id-a1': makePanel('id-a1')},
        selectedPanelId: 'id-a1',
      );
      selectedProjectId = projectA.id;
      native = nativeSnapshot();
      queries = buildQueries();
      expect(
        queries.dispatch({
          'op': 'navigate',
          'identityId': 'id-a1',
          'url': 'https://x.example.com',
        }),
        failure('no_native_view', 409),
      );
    });

    test('a navigation already in flight is navigation_in_flight', () async {
      setupTarget();
      var calls = 0;
      queries = buildQueries(
        isNavigating: (_) => true,
        navigatePanel: (_, _) => calls++,
      );
      expect(
        queries.dispatch({
          'op': 'navigate',
          'identityId': 'id-a1',
          'url': 'https://x.example.com',
        }),
        failure('navigation_in_flight', 409),
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, 0);
    });

    test('commit reports finalUrl, flags and timing fields', () async {
      setupTarget();
      final controller = StreamController<WebviewEvent>();
      addTearDown(controller.close);
      final dispatched = <String>[];
      queries = buildQueries(
        navigationEvents: () => controller.stream,
        navigatePanel: (id, url) {
          dispatched.add('$id|$url');
          controller.add(WebviewLoadStarted(id, Uri.parse(url)));
          controller.add(
            WebviewLoadComplete(
              id,
              Uri.parse('https://docs.example.com/landing'),
              canGoBack: true,
            ),
          );
        },
      );
      final data = await run({
        'op': 'navigate',
        'identityId': 'id-a1',
        'url': 'docs.example.com/landing?token=abc#frag',
      });
      // Bare host normalized to https — same rule as the address bar.
      expect(dispatched, ['id-a1|https://docs.example.com/landing?token=abc#frag']);
      expect(data['status'], 'committed');
      expect(data['finalUrl'], 'https://docs.example.com/landing');
      expect(data['canGoBack'], true);
      expect(data['canGoForward'], false);
      expect(data['sameUrl'], false);
      expect(data['nativeViewId'], 9);
      expect(data['windowId'], 83);
      expect(data['panelQueryable'], true);
      expect(data['settledAt'], isNotNull);
      expect(data['navigationId'] as String, startsWith('nav-'));
      // The request URL never leaves the interface raw — query/fragment
      // are stripped; the committed URL is what the page became.
      expect(jsonEncode(data), isNot(contains('token=abc')));
      expect(jsonEncode(data), isNot(contains('frag')));
    });

    test('same-URL navigation is flagged and still dispatched', () async {
      setupTarget(url: 'https://docs.example.com/x');
      final controller = StreamController<WebviewEvent>();
      addTearDown(controller.close);
      var calls = 0;
      queries = buildQueries(
        navigationEvents: () => controller.stream,
        navigatePanel: (id, url) {
          calls++;
          controller.add(WebviewLoadStarted(id, Uri.parse(url)));
          controller.add(WebviewLoadComplete(id, Uri.parse(url)));
        },
      );
      final data = await run({
        'op': 'navigate',
        'identityId': 'id-a1',
        'url': 'https://docs.example.com/x',
      });
      expect(calls, 1);
      expect(data['sameUrl'], true);
      expect(data['status'], 'committed');
    });

    test('a blocked navigation reports failed with a scrubbed error', () async {
      setupTarget();
      final controller = StreamController<WebviewEvent>();
      addTearDown(controller.close);
      queries = buildQueries(
        navigationEvents: () => controller.stream,
        navigatePanel: (id, url) {
          controller.add(WebviewLoadStarted(id, Uri.parse(url)));
          controller.add(
            WebviewNavigationBlocked(
              id,
              Uri.parse(url),
              'cannot open https://badsite.example.com/p?token=abc — refused',
            ),
          );
        },
      );
      final data = await run({
        'op': 'navigate',
        'identityId': 'id-a1',
        'url': 'https://badsite.example.com/p?token=abc',
      });
      expect(data['status'], 'failed');
      expect(data['error'], isA<String>());
      // The error text keeps its prose but the embedded URL is stripped
      // of its query — credentials never ride along.
      expect(data['error'] as String, contains('https://badsite.example.com/p'));
      expect(data['error'] as String, isNot(contains('token=abc')));
      expect(data['settledAt'], isNotNull);
    });

    test('a closing panel reports cancelled', () async {
      setupTarget();
      final controller = StreamController<WebviewEvent>();
      addTearDown(controller.close);
      queries = buildQueries(
        navigationEvents: () => controller.stream,
        navigatePanel: (id, url) {
          controller.add(WebviewLoadStarted(id, Uri.parse(url)));
          controller.add(WebviewStateChanged(id, WebviewState.closing));
        },
      );
      final data = await run({
        'op': 'navigate',
        'identityId': 'id-a1',
        'url': 'https://x.example.com',
      });
      expect(data['status'], 'cancelled');
      expect(data['panelQueryable'], true);
    });

    test(
      'stale events from an earlier navigation are not attributed',
      () async {
        setupTarget();
        final controller = StreamController<WebviewEvent>();
        addTearDown(controller.close);
        queries = buildQueries(
          navigationEvents: () => controller.stream,
          navigatePanel: (id, url) {
            // A leftover failure and a leftover complete from a previous
            // navigation arrive BEFORE this navigation's loadStarted —
            // neither may settle this batch.
            controller.add(
              WebviewNavigationBlocked(
                id,
                Uri.parse('https://old.example.com'),
                'old failure',
              ),
            );
            controller.add(
              WebviewLoadComplete(id, Uri.parse('https://old.example.com')),
            );
            controller.add(WebviewLoadStarted(id, Uri.parse(url)));
            controller.add(WebviewLoadComplete(id, Uri.parse(url)));
          },
        );
        final data = await run({
          'op': 'navigate',
          'identityId': 'id-a1',
          'url': 'https://x.example.com',
        });
        expect(data['status'], 'committed');
        expect(data['finalUrl'], 'https://x.example.com');
      },
    );

    test('a different loadStarted reports cancelled (superseded)', () async {
      setupTarget();
      final controller = StreamController<WebviewEvent>();
      addTearDown(controller.close);
      queries = buildQueries(
        navigationEvents: () => controller.stream,
        navigatePanel: (id, url) => controller.add(
          WebviewLoadStarted(id, Uri.parse('https://other.example.com/')),
        ),
      );
      final data = await run({
        'op': 'navigate',
        'identityId': 'id-a1',
        'url': 'https://x.example.com',
      });
      expect(data['status'], 'cancelled');
      expect(data['error'] as String, contains('superseded'));
    });

    test('a main-document commit settles before the page finishes', () async {
      setupTarget();
      final controller = StreamController<WebviewEvent>();
      addTearDown(controller.close);
      queries = buildQueries(
        navigationEvents: () => controller.stream,
        navigatePanel: (id, url) {
          controller.add(WebviewLoadStarted(id, Uri.parse(url)));
          controller.add(
            WebviewLoadCommitted(id, Uri.parse(url), canGoBack: true),
          );
          // No loadComplete: the page keeps loading resources but the
          // committed document already counts as navigated.
        },
      );
      final data = await run({
        'op': 'navigate',
        'identityId': 'id-a1',
        'url': 'https://x.example.com/slow',
      });
      expect(data['status'], 'committed');
      expect(data['canGoBack'], true);
      expect(data['finalUrl'], 'https://x.example.com/slow');
    });

    test('an http URL without a host reports invalid_url', () async {
      setupTarget();
      await expectLater(
        run({
          'op': 'navigate',
          'identityId': 'id-a1',
          'url': 'http:/x',
        }),
        failure('invalid_url', 400),
      );
    });

    test('IPv4 denotation bypasses are still private-network denied', () async {
      setupTarget();
      for (final url in [
        'http://[::ffff:127.0.0.1]/',
        'http://2130706433/',
        'http://0x7f000001/',
        'http://127.1/',
      ]) {
        await expectLater(
          run({'op': 'navigate', 'identityId': 'id-a1', 'url': url}),
          failure('private_network_denied', 403),
        );
      }
    });

    test('no settling event within the budget reports timeout', () async {
      setupTarget();
      final controller = StreamController<WebviewEvent>();
      addTearDown(controller.close);
      queries = buildQueries(
        navigationEvents: () => controller.stream,
        navigatePanel: (_, _) {},
        navigateWaitBudget: const Duration(milliseconds: 50),
      );
      final data = await run({
        'op': 'navigate',
        'identityId': 'id-a1',
        'url': 'https://slow.example.com',
      });
      expect(data['status'], 'timeout');
      expect(data['settledAt'], isNull);
      expect(data['panelQueryable'], true);
    });
  });

  group('reload', () {
    void setupTarget({String url = 'https://alpha.example.com/old'}) {
      workspace = WorkspaceState(
        panels: {
          'id-a1': makePanel('id-a1', url: url, state: WebviewState.embedded),
        },
        selectedPanelId: 'id-a1',
      );
      selectedProjectId = projectA.id;
      native = nativeSnapshot(
        views: [nativeView(9, 'id-a1', windowId: 83)],
      );
    }

    test('requires an explicit identityId', () async {
      expect(
        queries.dispatch({'op': 'reload'}),
        failure('invalid_argument', 400),
      );
    });

    test('unknown identity reports not_found', () async {
      workspace = WorkspaceState(
        panels: {'id-a1': makePanel('id-a1')},
        selectedPanelId: 'id-a1',
      );
      selectedProjectId = projectA.id;
      native = nativeSnapshot(views: [nativeView(9, 'id-a1')]);
      queries = buildQueries();
      expect(
        queries.dispatch({'op': 'reload', 'identityId': 'nope'}),
        failure('not_found', 404),
      );
    });

    test('identity of an inactive project is project_not_active', () async {
      setupTarget();
      selectedProjectId = projectB.id;
      queries = buildQueries();
      expect(
        queries.dispatch({'op': 'reload', 'identityId': 'id-a1'}),
        failure('project_not_active', 409),
      );
    });

    test('closed panel is panel_not_open', () async {
      workspace = const WorkspaceState();
      selectedProjectId = projectA.id;
      queries = buildQueries();
      expect(
        queries.dispatch({
          'op': 'reload',
          'identityId': 'id-a1',
        }),
        failure('panel_not_open', 409),
      );
    });

    test('a panel without a URL is no_current_url', () async {
      setupTarget(url: '');
      queries = buildQueries();
      expect(
        queries.dispatch({
          'op': 'reload',
          'identityId': 'id-a1',
        }),
        failure('no_current_url', 409),
      );
    });

    test('panel without a registered view is no_native_view', () async {
      setupTarget();
      native = nativeSnapshot();
      queries = buildQueries();
      expect(
        queries.dispatch({
          'op': 'reload',
          'identityId': 'id-a1',
        }),
        failure('no_native_view', 409),
      );
    });

    test('a navigation already in flight is navigation_in_flight', () async {
      setupTarget();
      var calls = 0;
      queries = buildQueries(
        isNavigating: (_) => true,
        reloadPanel: (_) => calls++,
      );
      expect(
        queries.dispatch({'op': 'reload', 'identityId': 'id-a1'}),
        failure('navigation_in_flight', 409),
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, 0);
    });

    test('reload commits a new navigation batch on the same URL', () async {
      setupTarget(url: 'https://docs.example.com/x?session=tok');
      final controller = StreamController<WebviewEvent>();
      addTearDown(controller.close);
      final dispatched = <String>[];
      queries = buildQueries(
        navigationEvents: () => controller.stream,
        reloadPanel: (id) {
          dispatched.add(id);
          // WK reload emits loadStarted for the CURRENT URL — the listener
          // arms on it, then the commit settles the batch.
          controller.add(
            WebviewLoadStarted(
              id,
              Uri.parse('https://docs.example.com/x?session=tok'),
            ),
          );
          controller.add(
            WebviewLoadCommitted(
              id,
              Uri.parse('https://docs.example.com/x?session=tok'),
              canGoBack: true,
            ),
          );
        },
      );
      final data = await run({'op': 'reload', 'identityId': 'id-a1'});
      expect(dispatched, ['id-a1']);
      expect(data['status'], 'committed');
      expect(data['navigationId'] as String, startsWith('nav-'));
      expect(data['nativeViewId'], 9);
      expect(data['windowId'], 83);
      expect(data['canGoBack'], true);
      expect(data['canGoForward'], false);
      expect(data['panelQueryable'], true);
      // The returned URL is sanitized — the session token never leaves.
      expect(data['url'], 'https://docs.example.com/x');
      expect(jsonEncode(data), isNot(contains('session=tok')));
      expect(data['settledAt'], isNotNull);
    });

    test('a loadStarted for a different URL reports superseded', () async {
      setupTarget(url: 'https://docs.example.com/x');
      final controller = StreamController<WebviewEvent>();
      addTearDown(controller.close);
      queries = buildQueries(
        navigationEvents: () => controller.stream,
        reloadPanel: (id) => controller.add(
          WebviewLoadStarted(id, Uri.parse('https://other.example.com/')),
        ),
      );
      final data = await run({'op': 'reload', 'identityId': 'id-a1'});
      expect(data['status'], 'cancelled');
      expect(data['error'] as String, contains('superseded'));
      // The URL field still reports the sanitized reload target.
      expect(data['url'], 'https://docs.example.com/x');
    });

    test('stale events of the previous batch are not attributed', () async {
      setupTarget(url: 'https://docs.example.com/x');
      final controller = StreamController<WebviewEvent>();
      addTearDown(controller.close);
      queries = buildQueries(
        navigationEvents: () => controller.stream,
        reloadPanel: (id) {
          controller.add(
            WebviewNavigationBlocked(
              id,
              Uri.parse('https://docs.example.com/x'),
              'old failure',
            ),
          );
          controller.add(
            WebviewLoadStarted(id, Uri.parse('https://docs.example.com/x')),
          );
          controller.add(
            WebviewLoadComplete(id, Uri.parse('https://docs.example.com/x')),
          );
        },
      );
      final data = await run({'op': 'reload', 'identityId': 'id-a1'});
      expect(data['status'], 'committed');
    });

    test('a blocked reload reports failed with a scrubbed error', () async {
      setupTarget(url: 'https://docs.example.com/x?token=abc');
      final controller = StreamController<WebviewEvent>();
      addTearDown(controller.close);
      queries = buildQueries(
        navigationEvents: () => controller.stream,
        reloadPanel: (id) {
          controller.add(
            WebviewLoadStarted(
              id,
              Uri.parse('https://docs.example.com/x?token=abc'),
            ),
          );
          controller.add(
            WebviewNavigationBlocked(
              id,
              Uri.parse('https://docs.example.com/x'),
              'cannot reload https://docs.example.com/x?token=abc — refused',
            ),
          );
        },
      );
      final data = await run({'op': 'reload', 'identityId': 'id-a1'});
      expect(data['status'], 'failed');
      expect(data['error'] as String, isNot(contains('token=abc')));
      expect(data['panelQueryable'], true);
    });

    test('no settling event within the budget reports timeout', () async {
      setupTarget();
      final controller = StreamController<WebviewEvent>();
      addTearDown(controller.close);
      queries = buildQueries(
        navigationEvents: () => controller.stream,
        reloadPanel: (_) {},
        navigateWaitBudget: const Duration(milliseconds: 50),
      );
      final data = await run({'op': 'reload', 'identityId': 'id-a1'});
      expect(data['status'], 'timeout');
      expect(data['settledAt'], isNull);
      expect(data['panelQueryable'], true);
    });
  });

  group('click', () {
    void setupTarget({String url = 'https://alpha.example.com/page'}) {
      workspace = WorkspaceState(
        panels: {
          'id-a1': makePanel('id-a1', url: url, state: WebviewState.embedded),
        },
        selectedPanelId: 'id-a1',
      );
      selectedProjectId = projectA.id;
      native = nativeSnapshot(
        views: [nativeView(9, 'id-a1', windowId: 83)],
      );
    }

    Map<String, dynamic> clickJson(Map<String, dynamic> payload) => {
      'json': jsonEncode(payload),
      'windowId': 83,
      'url': 'https://alpha.example.com/page',
    };

    test('requires identityId, ref and documentId', () async {
      expect(
        queries.dispatch({'op': 'click'}),
        failure('invalid_argument', 400),
      );
      expect(
        queries.dispatch({'op': 'click', 'identityId': 'id-a1'}),
        failure('invalid_argument', 400),
      );
      expect(
        queries.dispatch({
          'op': 'click',
          'identityId': 'id-a1',
          'ref': '0.3',
        }),
        failure('invalid_argument', 400),
      );
    });

    test('identity of an inactive project is project_not_active', () async {
      setupTarget();
      selectedProjectId = projectB.id;
      queries = buildQueries();
      expect(
        queries.dispatch({
          'op': 'click',
          'identityId': 'id-a1',
          'ref': '0.3',
          'documentId': 'doc:0',
        }),
        failure('project_not_active', 409),
      );
    });

    test('closed panel is panel_not_open', () async {
      workspace = const WorkspaceState();
      selectedProjectId = projectA.id;
      queries = buildQueries();
      expect(
        queries.dispatch({
          'op': 'click',
          'identityId': 'id-a1',
          'ref': '0.3',
          'documentId': 'doc:0',
        }),
        failure('panel_not_open', 409),
      );
    });

    test('panel without a registered view is no_native_view', () async {
      setupTarget();
      native = nativeSnapshot();
      queries = buildQueries();
      expect(
        queries.dispatch({
          'op': 'click',
          'identityId': 'id-a1',
          'ref': '0.3',
          'documentId': 'doc:0',
        }),
        failure('no_native_view', 409),
      );
    });

    test('payload stale_element maps to 409 and does not retry', () async {
      setupTarget();
      var calls = 0;
      queries = buildQueries(
        domClick: (_, _, _) async {
          calls++;
          return clickJson({
            'error': 'stale_element',
            'message': 'Document changed since the ref was issued',
          });
        },
      );
      expect(
        queries.dispatch({
          'op': 'click',
          'identityId': 'id-a1',
          'ref': '0.3',
          'documentId': 'doc:0',
        }),
        failure('stale_element', 409),
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1); // one dispatch, never replayed
    });

    test('not_interactable refusals carry the reason through', () async {
      setupTarget();
      for (final reason in ['hidden', 'disabled', 'invisible']) {
        queries = buildQueries(
          domClick: (_, _, _) async => clickJson({
            'error': 'not_interactable',
            'reason': reason,
            'message': 'Element is $reason',
          }),
        );
        expect(
          queries.dispatch({
            'op': 'click',
            'identityId': 'id-a1',
            'ref': '0.3',
            'documentId': 'doc:0',
          }),
          failure('not_interactable', 409),
          reason: reason,
        );
      }
    });

    test('a dispatched click reports mechanism and no navigation', () async {
      setupTarget();
      queries = buildQueries(
        domClick: (viewId, identityId, query) async {
          expect(viewId, 9);
          expect(identityId, 'id-a1');
          final q = jsonDecode(query) as Map<String, dynamic>;
          expect(q['ref'], '0.3');
          expect(q['documentId'], 'doc:0');
          return clickJson({
            'ref': '0.3',
            'frame': 'main',
            'frameIndex': 0,
            'tag': 'button',
            'role': 'button',
            'name': 'Play',
            'dispatched': true,
            'documentId': 'doc:0',
          });
        },
      );
      final data = await run({
        'op': 'click',
        'identityId': 'id-a1',
        'ref': '0.3',
        'documentId': 'doc:0',
      });
      expect(data['dispatched'], true);
      expect(data['mechanism'], 'synthetic_dom_click');
      expect(data['isTrusted'], false);
      expect(data['clickId'] as String, startsWith('clk-'));
      expect(data['tag'], 'button');
      expect(data['name'], 'Play');
      expect(data['navigationStarted'], false);
      expect(data['panelQueryable'], true);
    });

    test('a navigation started by the click reports the batch', () async {
      setupTarget();
      final controller = StreamController<WebviewEvent>();
      addTearDown(controller.close);
      queries = buildQueries(
        navigationEvents: () => controller.stream,
        domClick: (_, _, _) async {
          controller.add(
            WebviewLoadStarted(
              'id-a1',
              Uri.parse('https://alpha.example.com/next?session=tok'),
            ),
          );
          controller.add(
            WebviewLoadCommitted(
              'id-a1',
              Uri.parse('https://alpha.example.com/next?session=tok'),
              canGoBack: true,
            ),
          );
          return clickJson({
            'ref': '0.3',
            'frame': 'main',
            'frameIndex': 0,
            'tag': 'a',
            'role': 'link',
            'name': 'Back',
            'dispatched': true,
            'documentId': 'doc:0',
          });
        },
      );
      final data = await run({
        'op': 'click',
        'identityId': 'id-a1',
        'ref': '0.3',
        'documentId': 'doc:0',
      });
      expect(data['dispatched'], true);
      expect(data['navigationStarted'], true);
      expect(data['navStatus'], 'committed');
      expect(data['navigationId'] as String, startsWith('nav-'));
      expect(data['finalUrl'], 'https://alpha.example.com/next');
      expect(jsonEncode(data), isNot(contains('session=tok')));
      expect(data['canGoBack'], true);
      expect(data['settledAt'], isNotNull);
    });

    test('a started-but-uncommitted navigation reports timeout status', () async {
      setupTarget();
      final controller = StreamController<WebviewEvent>();
      addTearDown(controller.close);
      queries = buildQueries(
        navigationEvents: () => controller.stream,
        clickNavObserveBudget: const Duration(milliseconds: 50),
        domClick: (_, _, _) async {
          controller.add(
            WebviewLoadStarted(
              'id-a1',
              Uri.parse('https://alpha.example.com/slow'),
            ),
          );
          return clickJson({
            'ref': '0.3',
            'frame': 'main',
            'frameIndex': 0,
            'tag': 'a',
            'dispatched': true,
            'documentId': 'doc:0',
          });
        },
      );
      final data = await run({
        'op': 'click',
        'identityId': 'id-a1',
        'ref': '0.3',
        'documentId': 'doc:0',
      });
      expect(data['dispatched'], true);
      expect(data['navigationStarted'], true);
      expect(data['navStatus'], 'timeout');
      expect(data['settledAt'], isNull);
    });

    test('events from other identities never settle the observation', () async {
      setupTarget();
      final controller = StreamController<WebviewEvent>();
      addTearDown(controller.close);
      queries = buildQueries(
        navigationEvents: () => controller.stream,
        clickNavObserveBudget: const Duration(milliseconds: 50),
        domClick: (_, _, _) async {
          controller.add(
            WebviewLoadStarted(
              'id-b2',
              Uri.parse('https://beta.example.com/other'),
            ),
          );
          return clickJson({
            'ref': '0.3',
            'frame': 'main',
            'frameIndex': 0,
            'tag': 'button',
            'dispatched': true,
            'documentId': 'doc:0',
          });
        },
      );
      final data = await run({
        'op': 'click',
        'identityId': 'id-a1',
        'ref': '0.3',
        'documentId': 'doc:0',
      });
      expect(data['navigationStarted'], false);
    });

    test('a native failure maps dom_click_failed to 500', () async {
      setupTarget();
      queries = buildQueries(
        domClick: (_, _, _) async =>
            throw PlatformException(code: 'dom_click_failed'),
      );
      expect(
        queries.dispatch({
          'op': 'click',
          'identityId': 'id-a1',
          'ref': '0.3',
          'documentId': 'doc:0',
        }),
        failure('dom_click_failed', 500),
      );
    });
  });

  group('input', () {
    void setupTarget({String url = 'https://alpha.example.com/form'}) {
      workspace = WorkspaceState(
        panels: {
          'id-a1': makePanel('id-a1', url: url, state: WebviewState.embedded),
        },
        selectedPanelId: 'id-a1',
      );
      selectedProjectId = projectA.id;
      native = nativeSnapshot(
        views: [nativeView(9, 'id-a1', windowId: 83)],
      );
    }

    Map<String, dynamic> inputJson(Map<String, dynamic> payload) => {
      'json': jsonEncode(payload),
      'windowId': 83,
      'url': 'https://alpha.example.com/form',
    };

    test('requires identityId, ref, documentId and text', () async {
      expect(
        queries.dispatch({'op': 'input'}),
        failure('invalid_argument', 400),
      );
      expect(
        queries.dispatch({
          'op': 'input',
          'identityId': 'id-a1',
          'ref': '0.3',
          'documentId': 'doc:0',
        }),
        failure('invalid_argument', 400),
      );
      expect(
        queries.dispatch({
          'op': 'input',
          'identityId': 'id-a1',
          'ref': '0.3',
          'documentId': 'doc:0',
          'text': 'q',
          'mode': 'bogus',
        }),
        failure('invalid_argument', 400),
      );
    });

    test('closed panel is panel_not_open', () async {
      workspace = const WorkspaceState();
      selectedProjectId = projectA.id;
      queries = buildQueries();
      expect(
        queries.dispatch({
          'op': 'input',
          'identityId': 'id-a1',
          'ref': '0.3',
          'documentId': 'doc:0',
          'text': 'q',
        }),
        failure('panel_not_open', 409),
      );
    });

    test('payload not_interactable maps to 409 and does not retry', () async {
      setupTarget();
      var calls = 0;
      queries = buildQueries(
        domInput: (_, _, _) async {
          calls++;
          return inputJson({
            'error': 'not_interactable',
            'reason': 'readonly',
            'message': 'Element is readonly',
          });
        },
      );
      expect(
        queries.dispatch({
          'op': 'input',
          'identityId': 'id-a1',
          'ref': '0.3',
          'documentId': 'doc:0',
          'text': 'q',
        }),
        failure('not_interactable', 409),
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1); // one write, never replayed
    });

    test('dispatched input reports mechanism and never echoes text', () async {
      setupTarget();
      String? sentQuery;
      queries = buildQueries(
        domInput: (_, _, query) async {
          sentQuery = query;
          return inputJson({
            'ref': '0.3',
            'frame': 'main',
            'frameIndex': 0,
            'tag': 'input',
            'type': 'text',
            'mode': 'replace',
            'dispatched': true,
            'valueLength': 9,
            'eventsFired': ['input', 'change'],
            'documentId': 'doc:0',
          });
        },
      );
      final data = await run({
        'op': 'input',
        'identityId': 'id-a1',
        'ref': '0.3',
        'documentId': 'doc:0',
        'text': 'secret123',
      });
      expect(data['dispatched'], true);
      expect(data['mechanism'], 'prototype_setter_and_events');
      expect(data['mode'], 'replace');
      expect(data['valueLength'], 9);
      expect(data['eventsFired'], ['input', 'change']);
      expect(data['navigationStarted'], false);
      // The submitted text crosses as data to the page and never comes back.
      expect(jsonEncode(data), isNot(contains('secret123')));
      final sent = jsonDecode(sentQuery!) as Map<String, dynamic>;
      expect(sent['text'], 'secret123');
      expect(sent['ref'], '0.3');
    });

    test('append mode reaches the native query', () async {
      setupTarget();
      String? sentQuery;
      queries = buildQueries(
        domInput: (_, _, query) async {
          sentQuery = query;
          return inputJson({
            'ref': '0.3',
            'frame': 'main',
            'tag': 'textarea',
            'type': null,
            'mode': 'append',
            'dispatched': true,
            'valueLength': 12,
            'eventsFired': ['input', 'change'],
            'documentId': 'doc:0',
          });
        },
      );
      final data = await run({
        'op': 'input',
        'identityId': 'id-a1',
        'ref': '0.3',
        'documentId': 'doc:0',
        'text': '+more',
        'mode': 'append',
      });
      expect(data['mode'], 'append');
      final sent = jsonDecode(sentQuery!) as Map<String, dynamic>;
      expect(sent['mode'], 'append');
      expect(sent['text'], '+more');
    });

    test('post-write navigation is reported with a sanitized finalUrl', () async {
      setupTarget();
      final controller = StreamController<WebviewEvent>();
      addTearDown(controller.close);
      queries = buildQueries(
        navigationEvents: () => controller.stream,
        domInput: (_, _, _) async {
          controller.add(
            WebviewLoadStarted('id-a1', Uri.parse('https://x/r?token=s')),
          );
          controller.add(
            WebviewLoadCommitted('id-a1', Uri.parse('https://x/r?token=s')),
          );
          return inputJson({
            'ref': '0.3',
            'frame': 'main',
            'tag': 'input',
            'type': 'text',
            'mode': 'replace',
            'dispatched': true,
            'valueLength': 1,
            'eventsFired': ['input', 'change'],
            'documentId': 'doc:0',
          });
        },
      );
      final data = await run({
        'op': 'input',
        'identityId': 'id-a1',
        'ref': '0.3',
        'documentId': 'doc:0',
        'text': 'q',
      });
      expect(data['navigationStarted'], true);
      expect(data['navStatus'], 'committed');
      expect(data['finalUrl'], 'https://x/r');
      expect(jsonEncode(data), isNot(contains('token')));
    });

    test('events from another identity are not attributed', () async {
      setupTarget();
      final controller = StreamController<WebviewEvent>();
      addTearDown(controller.close);
      queries = buildQueries(
        navigationEvents: () => controller.stream,
        clickNavObserveBudget: const Duration(milliseconds: 50),
        domInput: (_, _, _) async {
          controller.add(
            WebviewLoadStarted('id-a2', Uri.parse('https://x/other')),
          );
          return inputJson({
            'ref': '0.3',
            'frame': 'main',
            'tag': 'input',
            'type': 'text',
            'mode': 'replace',
            'dispatched': true,
            'valueLength': 1,
            'eventsFired': ['input', 'change'],
            'documentId': 'doc:0',
          });
        },
      );
      final data = await run({
        'op': 'input',
        'identityId': 'id-a1',
        'ref': '0.3',
        'documentId': 'doc:0',
        'text': 'q',
      });
      expect(data['navigationStarted'], false);
    });

    test('a native failure maps dom_input_failed to 500', () async {
      setupTarget();
      queries = buildQueries(
        domInput: (_, _, _) async =>
            throw PlatformException(code: 'dom_input_failed'),
      );
      expect(
        queries.dispatch({
          'op': 'input',
          'identityId': 'id-a1',
          'ref': '0.3',
          'documentId': 'doc:0',
          'text': 'q',
        }),
        failure('dom_input_failed', 500),
      );
    });

    test('stale_element maps to 409', () async {
      setupTarget();
      queries = buildQueries(
        domInput: (_, _, _) async => inputJson({
          'error': 'stale_element',
          'message': 'Document changed since the ref was issued',
        }),
      );
      expect(
        queries.dispatch({
          'op': 'input',
          'identityId': 'id-a1',
          'ref': '0.3',
          'documentId': 'doc:0',
          'text': 'q',
        }),
        failure('stale_element', 409),
      );
    });
  });

  group('key', () {
    void setupTarget() {
      workspace = WorkspaceState(
        panels: {
          'id-a1': makePanel(
            'id-a1',
            url: 'https://alpha.example.com/form',
            state: WebviewState.embedded,
          ),
        },
        selectedPanelId: 'id-a1',
      );
      selectedProjectId = projectA.id;
      native = nativeSnapshot(views: [nativeView(9, 'id-a1', windowId: 83)]);
    }

    Map<String, dynamic> keyJson(Map<String, dynamic> payload) => {
      'json': jsonEncode(payload),
      'windowId': 83,
      'url': 'https://alpha.example.com/form',
    };

    Map<String, dynamic> keyCmd(String key) => {
      'op': 'key',
      'identityId': 'id-a1',
      'ref': '0.3',
      'documentId': 'doc:0',
      'key': key,
    };

    test('requires identityId, ref, documentId and key', () async {
      expect(queries.dispatch({'op': 'key'}), failure('invalid_argument', 400));
      expect(
        queries.dispatch(keyCmd('Enter')..remove('key')),
        failure('invalid_argument', 400),
      );
    });

    test('keys outside the whitelist are invalid_argument', () async {
      for (final k in ['cmd+q', 'a', 'Ctrl+C', 'F5', ' ', 'enter']) {
        expect(queries.dispatch(keyCmd(k)), failure('invalid_argument', 400));
      }
    });

    test('closed panel is panel_not_open', () async {
      workspace = const WorkspaceState();
      selectedProjectId = projectA.id;
      queries = buildQueries();
      expect(queries.dispatch(keyCmd('Enter')), failure('panel_not_open', 409));
    });

    test('not_interactable refusals map to 409 and do not retry', () async {
      setupTarget();
      var calls = 0;
      for (final reason in ['hidden', 'disabled']) {
        queries = buildQueries(
          domKey: (_, _, _) async {
            calls++;
            return keyJson({
              'error': 'not_interactable',
              'reason': reason,
              'message': 'Element is $reason',
            });
          },
        );
        expect(queries.dispatch(keyCmd('Tab')), failure('not_interactable', 409));
      }
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2); // one sequence per call, never replayed
    });

    test('stale_element maps to 409', () async {
      setupTarget();
      queries = buildQueries(
        domKey: (_, _, _) async => keyJson({
          'error': 'stale_element',
          'message': 'Document changed since the ref was issued',
        }),
      );
      expect(queries.dispatch(keyCmd('Enter')), failure('stale_element', 409));
    });

    test('dispatched key reports the mechanism and events', () async {
      setupTarget();
      queries = buildQueries(
        domKey: (_, _, _) async => keyJson({
          'ref': '0.3',
          'frame': 'main',
          'frameIndex': 0,
          'tag': 'input',
          'key': 'Enter',
          'dispatched': true,
          'synthetic': true,
          'eventsFired': ['keydown', 'keypress', 'keyup'],
          'documentId': 'doc:0',
        }),
      );
      final data = await run(keyCmd('Enter'));
      expect(data['dispatched'], true);
      expect(data['mechanism'], 'synthetic_keyboard_events');
      expect(data['isTrusted'], false);
      expect(data['key'], 'Enter');
      expect(data['keyId'] as String, startsWith('key-'));
      expect(data['eventsFired'], ['keydown', 'keypress', 'keyup']);
      expect(data['navigationStarted'], false);
      expect(data['panelQueryable'], true);
    });

    test('the key value reaches the native query', () async {
      setupTarget();
      String? sentQuery;
      queries = buildQueries(
        domKey: (_, _, query) async {
          sentQuery = query;
          return keyJson({
            'ref': '0.3',
            'frame': 'main',
            'tag': 'input',
            'key': 'Escape',
            'dispatched': true,
            'synthetic': true,
            'eventsFired': ['keydown', 'keyup'],
            'documentId': 'doc:0',
          });
        },
      );
      final data = await run(keyCmd('Escape'));
      expect(data['eventsFired'], ['keydown', 'keyup']);
      final sent = jsonDecode(sentQuery!) as Map<String, dynamic>;
      expect(sent['key'], 'Escape');
      expect(sent['ref'], '0.3');
      expect(sent['documentId'], 'doc:0');
    });

    test('a key-started navigation reports the sanitized batch', () async {
      setupTarget();
      final controller = StreamController<WebviewEvent>();
      addTearDown(controller.close);
      queries = buildQueries(
        navigationEvents: () => controller.stream,
        domKey: (_, _, _) async {
          controller.add(
            WebviewLoadStarted('id-a1', Uri.parse('https://x/s?token=t')),
          );
          controller.add(
            WebviewLoadCommitted('id-a1', Uri.parse('https://x/s?token=t')),
          );
          return keyJson({
            'ref': '0.3',
            'frame': 'main',
            'tag': 'input',
            'key': 'Enter',
            'dispatched': true,
            'synthetic': true,
            'eventsFired': ['keydown', 'keypress', 'keyup'],
            'documentId': 'doc:0',
          });
        },
      );
      final data = await run(keyCmd('Enter'));
      expect(data['navigationStarted'], true);
      expect(data['navStatus'], 'committed');
      expect(data['finalUrl'], 'https://x/s');
      expect(jsonEncode(data), isNot(contains('token=t')));
    });

    test('a native failure maps dom_key_failed to 500', () async {
      setupTarget();
      queries = buildQueries(
        domKey: (_, _, _) async =>
            throw PlatformException(code: 'dom_key_failed'),
      );
      expect(queries.dispatch(keyCmd('Enter')), failure('dom_key_failed', 500));
    });
  });

  group('scroll', () {
    void setupTarget() {
      workspace = WorkspaceState(
        panels: {
          'id-a1': makePanel(
            'id-a1',
            url: 'https://alpha.example.com/long',
            state: WebviewState.embedded,
          ),
        },
        selectedPanelId: 'id-a1',
      );
      selectedProjectId = projectA.id;
      native = nativeSnapshot(views: [nativeView(9, 'id-a1', windowId: 83)]);
    }

    Map<String, dynamic> scrollJson(Map<String, dynamic> payload) => {
      'json': jsonEncode(payload),
      'windowId': 83,
      'url': 'https://alpha.example.com/long',
    };

    Map<String, dynamic> scrollCmd([Map<String, dynamic>? extra]) => {
      'op': 'scroll',
      'identityId': 'id-a1',
      'documentId': 'doc:0',
      ...?extra,
    };

    test('requires identityId and documentId; into_view requires ref', () async {
      expect(
        queries.dispatch({'op': 'scroll'}),
        failure('invalid_argument', 400),
      );
      expect(
        queries.dispatch(scrollCmd()),
        failure('invalid_argument', 400),
      );
      expect(
        queries.dispatch(scrollCmd({'mode': 'bogus', 'ref': '0.3'})),
        failure('invalid_argument', 400),
      );
    });

    test('closed panel is panel_not_open', () async {
      workspace = const WorkspaceState();
      selectedProjectId = projectA.id;
      queries = buildQueries();
      expect(
        queries.dispatch(scrollCmd({'ref': '0.3'})),
        failure('panel_not_open', 409),
      );
    });

    test('delta without ref targets the frame document', () async {
      setupTarget();
      String? sentQuery;
      queries = buildQueries(
        domScroll: (_, _, query) async {
          sentQuery = query;
          return scrollJson({
            'frame': 'main',
            'frameIndex': 0,
            'mode': 'delta',
            'container': 'document',
            'unit': 'css-pixel',
            'before': {
              'top': 0,
              'left': 0,
              'maxTop': 4800,
              'maxLeft': 0,
              'clientHeight': 600,
              'clientWidth': 800,
            },
            'after': {
              'top': 500,
              'left': 0,
              'maxTop': 4800,
              'maxLeft': 0,
              'clientHeight': 600,
              'clientWidth': 800,
            },
            'movedY': 500,
            'movedX': 0,
            'dispatched': true,
            'atTop': false,
            'atBottom': false,
            'atLeft': true,
            'atRight': true,
            'documentId': 'doc:0',
          });
        },
      );
      final data = await run(scrollCmd({'mode': 'delta', 'dy': 500}));
      expect(data['dispatched'], true);
      expect(data['mechanism'], 'native_dom_scroll');
      expect(data['container'], 'document');
      expect(data['unit'], 'css-pixel');
      expect(data['movedY'], 500);
      expect(data['atTop'], false);
      expect(data['atBottom'], false);
      expect(data['panelQueryable'], true);
      expect(data.containsKey('navigationStarted'), false);
      final sent = jsonDecode(sentQuery!) as Map<String, dynamic>;
      expect(sent['mode'], 'delta');
      expect(sent['dy'], 500);
      expect(sent.containsKey('ref'), false);
      expect(sent['documentId'], 'doc:0');
    });

    test('into_view reports target rect, visibility and occlusion', () async {
      setupTarget();
      queries = buildQueries(
        domScroll: (_, _, _) async => scrollJson({
          'frame': 'main',
          'frameIndex': 0,
          'mode': 'into_view',
          'container': 'element',
          'containerTag': 'div',
          'dispatched': true,
          'before': {
            'top': 0, 'left': 0, 'maxTop': 1000, 'maxLeft': 0,
            'clientHeight': 200, 'clientWidth': 300,
          },
          'after': {
            'top': 420, 'left': 0, 'maxTop': 1000, 'maxLeft': 0,
            'clientHeight': 200, 'clientWidth': 300,
          },
          'movedY': 420,
          'movedX': 0,
          'atTop': false, 'atBottom': false, 'atLeft': true, 'atRight': true,
          'target': {
            'ref': '0.9',
            'tag': 'article',
            'rect': {'x': 10, 'y': 50, 'width': 200, 'height': 100},
            'visibleInViewport': true,
            'occludedBy': {'tag': 'header', 'id': 'sticky', 'cls': 'sticky'},
          },
          'documentId': 'doc:0',
        }),
      );
      final data = await run(scrollCmd({'ref': '0.9'}));
      expect(data['container'], 'element');
      final target = data['target'] as Map<String, dynamic>;
      expect(target['visibleInViewport'], true);
      expect((target['occludedBy'] as Map)['tag'], 'header');
      expect(data['movedY'], 420);
    });

    test('element-container delta sends the ref through', () async {
      setupTarget();
      String? sentQuery;
      queries = buildQueries(
        domScroll: (_, _, query) async {
          sentQuery = query;
          return scrollJson({
            'frame': 'f0',
            'frameIndex': 1,
            'mode': 'delta',
            'container': 'element',
            'containerTag': 'div',
            'ref': '1.4',
            'dispatched': true,
            'before': {'top': 0, 'left': 0, 'maxTop': 200, 'maxLeft': 0,
                       'clientHeight': 100, 'clientWidth': 100},
            'after': {'top': 200, 'left': 0, 'maxTop': 200, 'maxLeft': 0,
                      'clientHeight': 100, 'clientWidth': 100},
            'movedY': 200, 'movedX': 0,
            'atTop': false, 'atBottom': true, 'atLeft': true, 'atRight': true,
            'documentId': 'doc:1',
          });
        },
      );
      final data =
          await run(scrollCmd({'mode': 'delta', 'ref': '1.4', 'dy': 9999}));
      expect(data['container'], 'element');
      expect(data['containerTag'], 'div');
      expect(data['atBottom'], true);
      expect(data['frame'], 'f0');
      final sent = jsonDecode(sentQuery!) as Map<String, dynamic>;
      expect(sent['ref'], '1.4');
    });

    test('stale_element maps to 409', () async {
      setupTarget();
      queries = buildQueries(
        domScroll: (_, _, _) async => scrollJson({
          'error': 'stale_element',
          'message': 'Document changed since the ref was issued',
        }),
      );
      expect(
        queries.dispatch(scrollCmd({'ref': '0.3'})),
        failure('stale_element', 409),
      );
    });

    test('invalid_argument payloads map to 400', () async {
      setupTarget();
      queries = buildQueries(
        domScroll: (_, _, _) async => scrollJson({
          'error': 'invalid_argument',
          'message': 'dx/dy must be finite and |v| <= 20000 CSS px',
        }),
      );
      expect(
        queries.dispatch(scrollCmd({'mode': 'delta', 'dy': 999999})),
        failure('invalid_argument', 400),
      );
    });

    test('a native failure maps dom_scroll_failed to 500', () async {
      setupTarget();
      queries = buildQueries(
        domScroll: (_, _, _) async =>
            throw PlatformException(code: 'dom_scroll_failed'),
      );
      expect(
        queries.dispatch(scrollCmd({'ref': '0.3'})),
        failure('dom_scroll_failed', 500),
      );
    });
  });

  group('transport whitelist', () {
    late Directory directory;
    late AutomationServer server;
    late Map<String, dynamic> session;
    var dispatched = 0;

    Future<Map<String, dynamic>> post(Map<String, dynamic> body) async {
      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse('${session['endpoint']}/v1/command'),
        );
        request.headers.set('authorization', 'Bearer ${session['token']}');
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
        final response = await request.close();
        final text = await response.transform(utf8.decoder).join();
        return {
          'status': response.statusCode,
          ...jsonDecode(text) as Map<String, dynamic>,
        };
      } finally {
        client.close();
      }
    }

    setUp(() async {
      dispatched = 0;
      server = AutomationServer(
        dispatch: (command) async {
          dispatched++;
          return {'op': command['op']};
        },
      );
      directory = await Directory.systemTemp.createTemp('automation-test');
      await server.start(directory);
      final sessionFile = directory.listSync().whereType<File>().single;
      session =
          jsonDecode(await sessionFile.readAsString()) as Map<String, dynamic>;
    });

    tearDown(() async {
      await server.close();
      await directory.delete(recursive: true);
    });

    test('rejects non-read operations before dispatch', () async {
      for (final op in ['eval']) {
        final response = await post({'op': op, 'identityId': 'id-a1'});
        expect(response['status'], 400, reason: op);
        expect(response['ok'], false);
        expect(
          (response['error'] as Map)['code'],
          'unsupported_operation',
          reason: op,
        );
      }
      expect(dispatched, 0);
    });

    test('read operations still reach dispatch', () async {
      final response = await post({'op': 'capabilities'});
      expect(response['ok'], true);
      expect((response['data'] as Map)['op'], 'capabilities');
      expect(dispatched, 1);
    });
  });
}
