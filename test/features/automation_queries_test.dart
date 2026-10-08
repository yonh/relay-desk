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
  }) => AutomationQueries(
    projects: projects,
    identities: identities,
    workspaces: workspaces,
    readWorkspace: () => workspace,
    readSelectedProjectId: () => selectedProjectId,
    readNativeWindows: nativeReader ?? () async => native,
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

  test('capabilities reports the read-only P0 contract', () async {
    final data = await run({'op': 'capabilities'});
    expect(data['protocolVersion'], 1);
    expect(data['readOnly'], true);
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
      'dom',
      'screenshot',
      'eval',
      'actions',
      'console',
      'network',
      'cdp',
    ]) {
      expect(limitations[unsupported], false, reason: unsupported);
    }
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
    for (final op in ['navigate', 'eval', 'screenshot', 'click', 'nope']) {
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
      for (final op in ['navigate', 'reload', 'eval', 'screenshot']) {
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
