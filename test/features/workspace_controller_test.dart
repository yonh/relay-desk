/// Tests that the WorkspaceController drives the concrete WebviewAdapter
/// through the real Riverpod wiring (E-IMPL-WEBVIEW-LIFECYCLE /
/// E-IMPL-NAVIGATION). The UI never calls the adapter directly; it goes
/// through the controller, and these tests assert the controller forwards
/// every user action to a real adapter instance and maintains the
/// revision/fingerprint/state-machine invariants from rewrite-plan §4.8.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_desk/app/providers.dart';
import 'package:relay_desk/core/platform/domain.dart';
import 'package:relay_desk/core/platform/webview_adapter.dart';
import 'package:relay_desk/data/database/database.dart';
import 'package:relay_desk/features/workspace/workspace_controller.dart';
import 'package:relay_desk/features/workspace/workspace_screen.dart';
import 'package:relay_desk/platform/webview/headless_webview_adapter.dart';

void main() {
  late RelayDatabase db;
  late HeadlessWebviewAdapter adapter;
  late ProviderContainer container;

  setUp(() async {
    db = RelayDatabase(NativeDatabase.memory());
    adapter = HeadlessWebviewAdapter(
      capabilities: const RuntimeCapabilities(
        devtools: true,
        nativeProfiles: true,
        customUserAgent: true,
      ),
    );
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async {
          ref.onDispose(db.close);
          return db;
        }),
        webviewAdapterProvider.overrideWithValue(adapter),
      ],
    );
  });

  tearDown(() {
    adapter.dispose();
    container.dispose();
  });

  Project makeProject() => const Project(
    id: 'pid',
    name: 'P',
    targetUrl: 'https://example.com',
    createdAt: 1,
    updatedAt: 1,
  );

  Identity makeIdentity({
    String id = 'iid-a',
    String name = 'Alpha',
    IsolationMode mode = IsolationMode.nativeProfile,
    String startPath = '/',
    String? devicePresetId,
  }) => Identity(
    id: id,
    projectId: 'pid',
    name: name,
    color: '#FF0000',
    isolationMode: mode,
    startPath: startPath,
    devicePresetId: devicePresetId,
  );

  test('ensurePanel calls adapter.openEmbedded and records fingerprint', () {
    final controller = container.read(workspaceControllerProvider.notifier);
    final config = controller.ensurePanel(makeIdentity(), makeProject());

    expect(
      adapter.methodLog,
      contains('openEmbedded(iid-a,${config.fingerprint})'),
    );
    final panel = container.read(workspaceControllerProvider).panels['iid-a']!;
    expect(panel.state, WebviewState.openingEmbedded);
    expect(panel.fingerprint, config.fingerprint);
    expect(panel.url, 'https://example.com/');
  });

  test('updateBounds forwards monotonic revision to adapter', () {
    final controller = container.read(workspaceControllerProvider.notifier);
    controller.ensurePanel(makeIdentity(), makeProject());
    adapter.methodLog.clear();

    controller.updateBounds(
      'iid-a',
      const PanelLayout(
        identityId: 'iid-a',
        x: 10,
        y: 20,
        width: 400,
        height: 300,
      ),
    );
    controller.updateBounds(
      'iid-a',
      const PanelLayout(
        identityId: 'iid-a',
        x: 12,
        y: 22,
        width: 400,
        height: 300,
      ),
    );

    // Two updates => two adapter calls with increasing revisions.
    final boundsCalls = adapter.methodLog
        .where((m) => m.startsWith('updateBounds('))
        .toList();
    expect(boundsCalls, hasLength(2));
    expect(boundsCalls.first, contains('iid-a,1,'));
    expect(boundsCalls.last, contains('iid-a,2,'));
  });

  test('navigate/reload/back/forward/stop are forwarded to the adapter', () {
    final controller = container.read(workspaceControllerProvider.notifier);
    controller.ensurePanel(makeIdentity(), makeProject());
    adapter.methodLog.clear();

    controller.navigate('iid-a', 'https://example.com/page');
    controller.reload('iid-a');
    controller.back('iid-a');
    controller.forward('iid-a');
    controller.stop('iid-a');

    expect(
      adapter.methodLog,
      contains('navigate(iid-a,https://example.com/page)'),
    );
    expect(adapter.methodLog, contains('reload(iid-a)'));
    expect(
      adapter.methodLog,
      contains('browserAction(iid-a,BrowserAction.back)'),
    );
    expect(
      adapter.methodLog,
      contains('browserAction(iid-a,BrowserAction.forward)'),
    );
    expect(
      adapter.methodLog,
      contains('browserAction(iid-a,BrowserAction.stop)'),
    );
  });

  test(
    'stop unlatches the loading flag without waiting for a native event',
    () {
      final controller = container.read(workspaceControllerProvider.notifier);
      controller.ensurePanel(makeIdentity(), makeProject());
      // reload() latches loading; the headless adapter emits no load events, so
      // this stands in for a wedged WebKit pipeline that never calls back.
      controller.reload('iid-a');
      expect(
        container.read(workspaceControllerProvider).panels['iid-a']!.loading,
        isTrue,
      );

      controller.stop('iid-a');

      expect(
        container.read(workspaceControllerProvider).panels['iid-a']!.loading,
        isFalse,
      );
      expect(
        adapter.methodLog,
        contains('browserAction(iid-a,BrowserAction.stop)'),
      );
    },
  );

  test(
    'a native closed writeback on a detached panel rebuilds the view',
    () async {
      final controller = container.read(workspaceControllerProvider.notifier);
      controller.ensurePanel(makeIdentity(), makeProject());
      adapter.registerView('iid-a', adapter.allocateViewId());
      controller.detach('iid-a');
      await pumpEventQueue();
      expect(
        container.read(workspaceControllerProvider).panels['iid-a']!.state,
        WebviewState.detached,
      );

      // The detached-window user close tears the WKWebView down natively and
      // writes back `closed` with no preceding `closing`. The panel must
      // re-embed (viewNonce bump recreates the platform view) instead of
      // keeping a dead surface that can never navigate again.
      adapter.simulateClosed('iid-a');
      await pumpEventQueue();

      final panel = container
          .read(workspaceControllerProvider)
          .panels['iid-a']!;
      expect(panel.state, WebviewState.openingEmbedded);
      expect(panel.viewNonce, 1);
    },
  );

  test(
    'a closed writeback on an embedded panel just marks it closed',
    () async {
      final controller = container.read(workspaceControllerProvider.notifier);
      controller.ensurePanel(makeIdentity(), makeProject());
      adapter.registerView('iid-a', adapter.allocateViewId());
      await pumpEventQueue();

      adapter.simulateClosed('iid-a');
      await pumpEventQueue();

      final panel = container
          .read(workspaceControllerProvider)
          .panels['iid-a']!;
      expect(panel.state, WebviewState.closed);
      expect(panel.viewNonce, 0);
    },
  );

  test(
    'URL change event updates the panel without changing its load state',
    () async {
      final controller = container.read(workspaceControllerProvider.notifier);
      controller.ensurePanel(makeIdentity(), makeProject());
      await pumpEventQueue();

      // The headless adapter emits a completed navigation event. The controller
      // uses the same URL-only state update that the macOS SPA URL observer uses.
      controller.navigate(
        'iid-a',
        'https://example.com/dashboard?tab=activity',
      );
      await pumpEventQueue();

      final panel = container
          .read(workspaceControllerProvider)
          .panels['iid-a']!;
      expect(panel.url, 'https://example.com/dashboard?tab=activity');
      expect(panel.loading, isFalse);
    },
  );

  test('toggleMute is forwarded to the adapter', () {
    final controller = container.read(workspaceControllerProvider.notifier);
    controller.ensurePanel(makeIdentity(), makeProject());
    adapter.methodLog.clear();
    controller.toggleMute('iid-a');
    expect(adapter.methodLog, contains('toggleMute(iid-a)'));
  });

  test(
    'detach/attach drive the embedded/detached state machine via adapter',
    () async {
      final controller = container.read(workspaceControllerProvider.notifier);
      controller.ensurePanel(makeIdentity(), makeProject());
      adapter.methodLog.clear();

      controller.detach('iid-a');
      // The headless adapter emits detaching->detached synchronously; the
      // controller's event listener updates panel state from the event stream.
      await pumpEventQueue();
      expect(adapter.methodLog, contains('detach(iid-a)'));
      expect(
        container.read(workspaceControllerProvider).panels['iid-a']!.state,
        WebviewState.detached,
      );

      controller.attach('iid-a');
      await pumpEventQueue();
      expect(adapter.methodLog, contains('attach(iid-a)'));
      expect(
        container.read(workspaceControllerProvider).panels['iid-a']!.state,
        WebviewState.embedded,
      );
    },
  );

  test('removePanel closes the adapter view and drops the panel', () async {
    final controller = container.read(workspaceControllerProvider.notifier);
    controller.ensurePanel(makeIdentity(), makeProject());
    adapter.methodLog.clear();

    controller.removePanel('iid-a');
    await pumpEventQueue();
    expect(adapter.methodLog, contains('close(iid-a)'));
    expect(container.read(workspaceControllerProvider).panels['iid-a'], isNull);
  });

  test(
    'fingerprint reconstruction: changing isolationMode closes the old view and reopens',
    () async {
      final controller = container.read(workspaceControllerProvider.notifier);
      // Open with nativeProfile.
      controller.ensurePanel(
        makeIdentity(mode: IsolationMode.nativeProfile),
        makeProject(),
      );
      final firstFingerprint = container
          .read(workspaceControllerProvider)
          .panels['iid-a']!
          .fingerprint;
      await pumpEventQueue();
      adapter.methodLog.clear();

      // Same identity, different isolation mode -> fingerprint changes ->
      // controller must close the old view and openEmbedded a new one.
      controller.ensurePanel(
        makeIdentity(mode: IsolationMode.originProxy),
        makeProject(),
      );
      await pumpEventQueue();

      expect(adapter.methodLog, contains('close(iid-a)'));
      expect(
        adapter.methodLog.any((m) => m.startsWith('openEmbedded(iid-a,')),
        isTrue,
      );
      final newFingerprint = container
          .read(workspaceControllerProvider)
          .panels['iid-a']!
          .fingerprint;
      expect(newFingerprint, isNot(firstFingerprint));
    },
  );

  test('stale revision is dropped by the adapter (monotonic guard)', () {
    final controller = container.read(workspaceControllerProvider.notifier);
    controller.ensurePanel(makeIdentity(), makeProject());
    adapter.methodLog.clear();

    // Drive two real updates (revisions 1, 2).
    controller.updateBounds(
      'iid-a',
      const PanelLayout(
        identityId: 'iid-a',
        x: 1,
        y: 1,
        width: 400,
        height: 300,
      ),
    );
    controller.updateBounds(
      'iid-a',
      const PanelLayout(
        identityId: 'iid-a',
        x: 2,
        y: 2,
        width: 400,
        height: 300,
      ),
    );
    // Manually push a stale revision (1 < 2) directly to the adapter to prove
    // the monotonic guard drops it.
    adapter.updateBounds('iid-a', 1, const NativeBounds(99, 99, 400, 300));
    final dropped = adapter.methodLog
        .where((m) => m.contains('DROPPED stale'))
        .toList();
    expect(dropped, isNotEmpty);
  });

  test('setLayoutMode reflows panels to grid and updates state', () {
    final controller = container.read(workspaceControllerProvider.notifier);
    controller.ensurePanel(makeIdentity(id: 'a'), makeProject());
    controller.ensurePanel(makeIdentity(id: 'b'), makeProject());
    controller.setLayoutMode(LayoutMode.grid);
    expect(
      container.read(workspaceControllerProvider).layoutMode,
      LayoutMode.grid,
    );
  });

  test('each project restores its own persisted default layout mode', () async {
    final projectRepo = await container.read(projectRepositoryProvider.future);
    final projectA = await projectRepo.create(
      name: 'A',
      targetUrl: 'https://a.example.com',
    );
    final projectB = await projectRepo.create(
      name: 'B',
      targetUrl: 'https://b.example.com',
    );
    final controller = container.read(workspaceControllerProvider.notifier);

    container.read(selectedProjectIdProvider.notifier).select(projectA.id);
    await controller.restoreProjectLayoutMode(projectA.id);
    expect(
      container.read(workspaceControllerProvider).layoutMode,
      LayoutMode.grid,
    );
    await controller.setLayoutMode(LayoutMode.canvas);
    expect(
      (await projectRepo.getById(projectA.id))!.defaultLayoutMode,
      LayoutMode.canvas,
    );

    container.read(selectedProjectIdProvider.notifier).select(projectB.id);
    await controller.restoreProjectLayoutMode(projectB.id);
    expect(
      container.read(workspaceControllerProvider).layoutMode,
      LayoutMode.grid,
    );
    await controller.setLayoutMode(LayoutMode.focus);
    expect(
      (await projectRepo.getById(projectB.id))!.defaultLayoutMode,
      LayoutMode.focus,
    );

    container.read(selectedProjectIdProvider.notifier).select(projectA.id);
    await controller.restoreProjectLayoutMode(projectA.id);
    expect(
      container.read(workspaceControllerProvider).layoutMode,
      LayoutMode.canvas,
    );
  });

  test(
    'saveWorkspace persists layout and reloads it via loadWorkspace',
    () async {
      // Seed a real project + identity so loadWorkspace can resolve them.
      final projectRepo = await container.read(
        projectRepositoryProvider.future,
      );
      final identityRepo = await container.read(
        identityRepositoryProvider.future,
      );
      final project = await projectRepo.create(
        name: 'P',
        targetUrl: 'https://example.com',
      );
      final identity = await identityRepo.create(
        projectId: project.id,
        name: 'Alpha',
        color: '#FF0000',
        isolationMode: IsolationMode.nativeProfile,
      );

      final controller = container.read(workspaceControllerProvider.notifier);
      controller.ensurePanel(identity, project);
      adapter.registerView(identity.id, adapter.allocateViewId());
      controller.navigate(identity.id, 'https://example.com/current-page');
      await pumpEventQueue();
      controller.updateBounds(
        identity.id,
        PanelLayout(
          identityId: identity.id,
          x: 7,
          y: 9,
          width: 500,
          height: 400,
        ),
      );

      await controller.saveWorkspace('My Layout');
      final savedId = container
          .read(workspaceControllerProvider)
          .selectedWorkspaceId;
      expect(savedId, isNotNull);

      // The workspace must be persisted with the panel bound to the real identity.
      final wsRepo = await container.read(workspaceRepositoryProvider.future);
      final saved = await wsRepo.getById(savedId!);
      expect(saved, isNotNull);
      expect(saved!.name, 'My Layout');
      expect(saved.panels, hasLength(1));
      expect(saved.panels.first.identityId, identity.id);
      expect(saved.panels.first.x, 7);

      // Move away from the saved position, then load the workspace. Loading a
      // layout must keep the live browser session and native view registered.
      controller.updateBounds(
        identity.id,
        PanelLayout(
          identityId: identity.id,
          x: 100,
          y: 120,
          width: 640,
          height: 480,
        ),
      );
      adapter.methodLog.clear();
      await controller.loadWorkspace(savedId);
      await pumpEventQueue();

      final restored = container
          .read(workspaceControllerProvider)
          .panels[identity.id]!;
      expect(restored.layout.x, 7);
      expect(restored.layout.y, 9);
      expect(restored.url, 'https://example.com/current-page');
      expect(restored.state, WebviewState.embedded);
      expect(adapter.viewIdFor(identity.id), isNotNull);
      expect(adapter.methodLog.any((m) => m.startsWith('close(')), isFalse);
      expect(
        adapter.methodLog.any((m) => m.startsWith('openEmbedded(')),
        isFalse,
      );

      // Delete it.
      await controller.deleteWorkspace(savedId);
      final after = await wsRepo.getById(savedId);
      expect(after, isNull);
    },
  );

  test('backActive/forwardActive route to the selected (active) panel', () {
    final controller = container.read(workspaceControllerProvider.notifier);
    controller.ensurePanel(makeIdentity(id: 'a', name: 'A'), makeProject());
    controller.ensurePanel(makeIdentity(id: 'b', name: 'B'), makeProject());
    // ensurePanel selects the first panel; explicitly promote 'b'.
    controller.selectPanel('b');
    adapter.methodLog.clear();

    expect(controller.backActive(), isTrue);
    expect(controller.forwardActive(), isTrue);
    expect(adapter.methodLog, contains('browserAction(b,BrowserAction.back)'));
    expect(
      adapter.methodLog,
      contains('browserAction(b,BrowserAction.forward)'),
    );
    // The non-active panel must not receive the action.
    expect(
      adapter.methodLog.any((m) => m.contains('browserAction(a,')),
      isFalse,
    );
  });

  test('backActive is a no-op without a selectable panel', () async {
    final controller = container.read(workspaceControllerProvider.notifier);
    // No panels at all: no selection exists.
    expect(controller.backActive(), isFalse);
    expect(controller.forwardActive(), isFalse);
    expect(adapter.methodLog, isEmpty);

    controller.ensurePanel(makeIdentity(), makeProject());
    await pumpEventQueue();
    controller.removePanel('iid-a');
    await pumpEventQueue();
    adapter.methodLog.clear();
    // Panel removed (selection cleared): still a no-op.
    expect(controller.backActive(), isFalse);
    expect(adapter.methodLog, isEmpty);
  });

  test('backActive is a no-op when the active panel is closed', () async {
    final controller = container.read(workspaceControllerProvider.notifier);
    controller.ensurePanel(makeIdentity(), makeProject());
    await pumpEventQueue();
    // Simulate the native side reporting a failed/closed view.
    adapter.close('iid-a');
    await pumpEventQueue();
    adapter.methodLog.clear();
    expect(controller.backActive(), isFalse);
    expect(
      adapter.methodLog.any((m) => m.startsWith('browserAction(')),
      isFalse,
    );
  });

  test('loadComplete syncs canGoBack/canGoForward into the panel', () async {
    final controller = container.read(workspaceControllerProvider.notifier);
    controller.ensurePanel(makeIdentity(), makeProject());
    await pumpEventQueue();

    adapter.simulateLoadComplete(
      'iid-a',
      Uri.parse('https://example.com/page'),
      canGoBack: true,
      canGoForward: false,
    );
    await pumpEventQueue();

    final panel = container.read(workspaceControllerProvider).panels['iid-a']!;
    expect(panel.url, 'https://example.com/page');
    expect(panel.loading, isFalse);
    expect(panel.canGoBack, isTrue);
    expect(panel.canGoForward, isFalse);
  });

  // Ticket 01/02: the runtime must carry the identity's isolationMode so the
  // AppKitView creationParams can pass it to the native factory — without it
  // a sharedSession identity silently gets a per-identity WKWebsiteDataStore.
  test('panel runtime carries the identity isolationMode', () {
    final controller = container.read(workspaceControllerProvider.notifier);
    controller.ensurePanel(
      makeIdentity(mode: IsolationMode.sharedSession),
      makeProject(),
    );
    final panel = container.read(workspaceControllerProvider).panels['iid-a']!;
    expect(panel.isolationMode, IsolationMode.sharedSession);
    expect(panel.fingerprint, contains('sharedSession'));
  });

  test('platform view creationParams carry isolationMode and fingerprint', () {
    final controller = container.read(workspaceControllerProvider.notifier);
    final config = controller.ensurePanel(
      makeIdentity(mode: IsolationMode.sharedSession),
      makeProject(),
    );
    final panel = container.read(workspaceControllerProvider).panels['iid-a']!;
    final params = panelCreationParams(panel);
    expect(params['identityId'], 'iid-a');
    expect(params['isolationMode'], 'sharedSession');
    expect(params['fingerprint'], config.fingerprint);
    expect(params['url'], panel.url);
  });

  // ---- device emulation ----

  test(
    'mobile preset lands in the runtime config: UA + preset id + fingerprint',
    () {
      final controller = container.read(workspaceControllerProvider.notifier);
      final config = controller.ensurePanel(
        makeIdentity(devicePresetId: 'iphone-15'),
        makeProject(),
      );
      final panel = container
          .read(workspaceControllerProvider)
          .panels['iid-a']!;

      expect(config.userAgent, contains('iPhone'));
      expect(config.devicePresetId, 'iphone-15');
      expect(panel.devicePresetId, 'iphone-15');
      expect(panel.fingerprint, contains('iphone-15'));

      // Same identity without the preset produces a different fingerprint —
      // the WebView must be rebuilt, never silently reused under the old UA.
      controller.ensurePanel(makeIdentity(), makeProject());
      final plain = container
          .read(workspaceControllerProvider)
          .panels['iid-a']!;
      expect(plain.fingerprint, isNot(panel.fingerprint));
      expect(plain.devicePresetId, isNull);
    },
  );

  test('creationParams carry the emulation surface to the native side', () {
    final controller = container.read(workspaceControllerProvider.notifier);
    controller.ensurePanel(
      makeIdentity(devicePresetId: 'iphone-15'),
      makeProject(),
    );
    final panel = container.read(workspaceControllerProvider).panels['iid-a']!;
    final params = panelCreationParams(panel);
    expect(params['devicePresetId'], 'iphone-15');
    expect(params['userAgent'], contains('iPhone'));
    expect(params['touchEmulation'], isTrue);
    expect(params['viewportWidth'], 393);
    expect(params['viewportHeight'], 852);
  });

  test('desktop preset emits no UA/touch overrides', () {
    final controller = container.read(workspaceControllerProvider.notifier);
    controller.ensurePanel(
      makeIdentity(devicePresetId: 'desktop-1920'),
      makeProject(),
    );
    final panel = container.read(workspaceControllerProvider).panels['iid-a']!;
    final params = panelCreationParams(panel);
    expect(params['devicePresetId'], 'desktop-1920');
    expect(params['userAgent'], isNull);
    expect(params['touchEmulation'], isFalse);
    expect(params['viewportWidth'], isNull);
  });

  test('switching preset rebuilds the view but resumes the live URL', () async {
    final controller = container.read(workspaceControllerProvider.notifier);
    controller.ensurePanel(makeIdentity(), makeProject());
    await pumpEventQueue();

    // User navigates away from the configured start URL.
    controller.navigate('iid-a', 'https://example.com/dashboard');
    await pumpEventQueue();
    adapter.methodLog.clear();

    // Device-preset-only change: fingerprint flips -> close + reopen, but
    // the panel keeps the page under test instead of bouncing back to the
    // configured start URL.
    controller.ensurePanel(
      makeIdentity(devicePresetId: 'iphone-15'),
      makeProject(),
    );
    await pumpEventQueue();

    expect(adapter.methodLog, contains('close(iid-a)'));
    expect(
      adapter.methodLog.any((m) => m.startsWith('openEmbedded(iid-a,')),
      isTrue,
    );
    final panel = container.read(workspaceControllerProvider).panels['iid-a']!;
    expect(panel.url, 'https://example.com/dashboard');
    expect(panel.devicePresetId, 'iphone-15');
  });

  test('a changed start URL wins over the live URL on rebuild', () async {
    final controller = container.read(workspaceControllerProvider.notifier);
    controller.ensurePanel(makeIdentity(), makeProject());
    await pumpEventQueue();
    controller.navigate('iid-a', 'https://example.com/dashboard');
    await pumpEventQueue();

    // The configured start URL changed (project target or identity
    // startPath edit): the rebuild must load the NEW start URL, not resume
    // the stale page.
    controller.ensurePanel(
      makeIdentity(devicePresetId: 'iphone-15', startPath: '/new'),
      makeProject(),
    );
    await pumpEventQueue();

    final panel = container.read(workspaceControllerProvider).panels['iid-a']!;
    expect(panel.url, 'https://example.com/new');
  });

  test(
    'fixed window-size preset carries preset dims to native and sizes the panel',
    () {
      final controller = container.read(workspaceControllerProvider.notifier);
      controller.ensurePanel(
        makeIdentity(devicePresetId: 'size-iphone-14-390x844'),
        makeProject(),
      );
      final panel = container
          .read(workspaceControllerProvider)
          .panels['iid-a']!;
      final params = panelCreationParams(panel);
      expect(params['viewportWidth'], 390);
      expect(params['viewportHeight'], 844);
      expect(params['userAgent'], isNull);
      expect(params['touchEmulation'], isFalse);
      expect(params['viewportFollowsSurface'], isFalse);
      // Panel opens at the preset size plus panel chrome (header + toolbar).
      expect(panel.layout.width, 390);
      expect(panel.layout.height, 844 + 96);
    },
  );

  test('custom preset follows the panel surface size', () {
    final controller = container.read(workspaceControllerProvider.notifier);
    controller.ensurePanel(
      makeIdentity(devicePresetId: 'custom'),
      makeProject(),
    );
    final panel = container.read(workspaceControllerProvider).panels['iid-a']!;
    final params = panelCreationParams(panel);
    expect(params['viewportFollowsSurface'], isTrue);
    // The initial detached-window size seeds from the panel layout; the
    // native side keeps it tracking the live surface via setBounds.
    expect(params['viewportWidth'], panel.layout.width.round());
    expect(params['viewportHeight'], panel.layout.height.round());
    // No emulation: desktop UA and surface — the panel keeps default sizing.
    expect(params['userAgent'], isNull);
    expect(params['touchEmulation'], isFalse);
    expect(panel.layout.width, 480);
  });

  test('mobile presets get phone-shaped default layouts', () {
    final controller = container.read(workspaceControllerProvider.notifier);
    controller.ensurePanel(
      makeIdentity(id: 'iid-phone', devicePresetId: 'iphone-15'),
      makeProject(),
    );
    controller.ensurePanel(makeIdentity(id: 'iid-desk'), makeProject());

    final panels = container.read(workspaceControllerProvider).panels;
    // Tauri baseline defaults: mobile ~375x700, desktop 480x360 cell.
    expect(panels['iid-phone']!.layout.width, 375);
    expect(panels['iid-phone']!.layout.height, 700);
    expect(panels['iid-desk']!.layout.width, 480);
  });

  test('setDevicePreset persists the preset on the identity record', () async {
    final projectRepo = await container.read(projectRepositoryProvider.future);
    final identityRepo = await container.read(
      identityRepositoryProvider.future,
    );
    final project = await projectRepo.create(
      name: 'P',
      targetUrl: 'https://example.com',
    );
    final identity = await identityRepo.create(
      projectId: project.id,
      name: 'Alpha',
      color: '#FF0000',
      isolationMode: IsolationMode.nativeProfile,
    );

    final controller = container.read(workspaceControllerProvider.notifier);
    await controller.setDevicePreset(identity.id, 'iphone-15');

    final persisted = await identityRepo.getById(identity.id);
    expect(persisted!.devicePresetId, 'iphone-15');

    // Invalid ids are rejected without touching the record.
    await controller.setDevicePreset(identity.id, 'not a preset');
    expect(
      (await identityRepo.getById(identity.id))!.devicePresetId,
      'iphone-15',
    );

    // The next ensurePanel against the persisted identity rebuilds under the
    // new emulation surface.
    controller.ensurePanel(persisted, project);
    final panel = container
        .read(workspaceControllerProvider)
        .panels[identity.id]!;
    expect(panel.devicePresetId, 'iphone-15');
    expect(panel.fingerprint, contains('iphone-15'));
  });

  test('unknown preset id degrades to the desktop surface', () {
    final controller = container.read(workspaceControllerProvider.notifier);
    // A malformed/unknown persisted id must not inject a guessed UA — it
    // resolves to "no overrides" while keeping the raw id for round-tripping.
    controller.ensurePanel(
      makeIdentity(devicePresetId: 'bogus-preset'),
      makeProject(),
    );
    final panel = container.read(workspaceControllerProvider).panels['iid-a']!;
    final params = panelCreationParams(panel);
    expect(params['userAgent'], isNull);
    expect(params['touchEmulation'], isFalse);
    expect(params['viewportWidth'], isNull);
    expect(params['devicePresetId'], 'bogus-preset');
  });
}
