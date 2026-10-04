/// Widget tests for the workspace screen: Canvas/Grid/Focus layout modes,
/// per-panel navigation toolbar driving the concrete adapter, and named
/// workspace save/load/delete through the real Riverpod + drift wiring
/// (E-IMPL-WORKSPACE / E-IMPL-NAVIGATION).
///
/// `webviewPlatformSupportedProvider` is overridden to false so `_PanelBody`
/// renders a placeholder instead of an AppKitView (no platform view factory
/// exists under `flutter test`); the navigation/layout/workspace logic still
/// runs through the real controller and a real HeadlessWebviewAdapter.
library;

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_desk/app/providers.dart';
import 'package:relay_desk/core/platform/domain.dart';
import 'package:relay_desk/core/platform/webview_adapter.dart';
import 'package:relay_desk/data/database/database.dart';
import 'package:relay_desk/data/repositories/project_repository.dart';
import 'package:relay_desk/features/workspace/workspace_controller.dart';
import 'package:relay_desk/features/workspace/workspace_screen.dart';
import 'package:relay_desk/platform/webview/headless_webview_adapter.dart';

import '../test_app.dart';

void main() {
  late RelayDatabase db;
  late HeadlessWebviewAdapter adapter;

  setUp(() {
    resetQuickSiteHostGlobals();
    db = RelayDatabase(NativeDatabase.memory());
    adapter = HeadlessWebviewAdapter(
      capabilities: const RuntimeCapabilities(
        devtools: true,
        nativeProfiles: true,
        customUserAgent: true,
      ),
    );
  });

  tearDown(() async {
    adapter.dispose();
    await db.close();
  });

  /// Boots the workspace screen with a project + 3 identities pre-seeded and
  /// selected. Returns the container so the test can read controller state.
  Future<ProviderContainer> boot(
    WidgetTester tester, {
    Size surfaceSize = const Size(1440, 900),
  }) async {
    // Relay Desk is a desktop app; render at a realistic desktop surface so
    // the toolbar Row does not overflow the default 800x600 test canvas.
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final projectRepo = ProjectRepository(db);
    final identityRepo = IdentityRepository(db);
    final project = await projectRepo.create(
      name: 'Demo',
      targetUrl: 'https://demo.app',
    );
    for (final name in ['Alpha', 'Bravo', 'Charlie']) {
      await identityRepo.create(
        projectId: project.id,
        name: name,
        color: '#FF0000',
        isolationMode: IsolationMode.nativeProfile,
      );
    }

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async {
          ref.onDispose(db.close);
          return db;
        }),
        webviewAdapterProvider.overrideWithValue(adapter),
        webviewPlatformSupportedProvider.overrideWithValue(false),
      ],
    );
    container.read(selectedProjectIdProvider.notifier).select(project.id);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(
          locale: Locale('en'),
          home: Scaffold(body: WorkspaceScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('three identity panels render via the controller', (
    tester,
  ) async {
    await boot(tester);
    // The headless adapter received openEmbedded for each of the 3 identities.
    final opens = adapter.methodLog
        .where((m) => m.startsWith('openEmbedded('))
        .toList();
    expect(opens, hasLength(3));
    // Each panel renders its identity name in the header.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Bravo'), findsOneWidget);
    expect(find.text('Charlie'), findsOneWidget);
  });

  testWidgets('workspace toolbar fills the width and starts from the left', (
    tester,
  ) async {
    await boot(tester);

    final toolbar = find.byKey(const ValueKey('workspace-toolbar'));
    final layoutToggle = find.byKey(const ValueKey('workspace-layout-toggle'));
    expect(tester.getSize(toolbar).width, 1440);
    expect(tester.getTopLeft(layoutToggle).dx, lessThan(160));
  });

  testWidgets('layout toggle switches Canvas -> Grid -> Focus', (tester) async {
    final container = await boot(tester);
    // Default is grid.
    expect(
      container.read(workspaceControllerProvider).layoutMode,
      LayoutMode.grid,
    );

    await tester.tap(find.text('Canvas'));
    await tester.pumpAndSettle();
    expect(
      container.read(workspaceControllerProvider).layoutMode,
      LayoutMode.canvas,
    );

    await tester.tap(find.text('Focus'));
    await tester.pumpAndSettle();
    expect(
      container.read(workspaceControllerProvider).layoutMode,
      LayoutMode.focus,
    );
    adapter.methodLog.clear();
    await tester.tap(find.text('Bravo'));
    await tester.pumpAndSettle();
    expect(
      container.read(workspaceControllerProvider).selectedPanelId,
      isNotNull,
    );
    expect(
      adapter.methodLog.where((entry) => entry.startsWith('navigate(')),
      isEmpty,
    );
    expect(
      adapter.methodLog.where((entry) => entry.startsWith('reload(')),
      isEmpty,
    );
  });

  testWidgets(
    'narrow Focus keeps vertical scrolling available to the focused page',
    (tester) async {
      await boot(tester, surfaceSize: const Size(700, 900));

      await tester.tap(find.text('Focus'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('focus-narrow-layout')), findsOneWidget);
      final secondaryStrip = tester.widget<ListView>(
        find.byKey(const ValueKey('focus-secondary-strip')),
      );
      expect(secondaryStrip.scrollDirection, Axis.horizontal);

      final verticalScrollable = find.descendant(
        of: find.byKey(const ValueKey('focus-narrow-layout')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              (widget.axisDirection == AxisDirection.down ||
                  widget.axisDirection == AxisDirection.up),
        ),
      );
      expect(verticalScrollable, findsNothing);
    },
  );

  testWidgets(
    'per-panel navigation toolbar forwards back/forward/stop/reload/mute to the adapter',
    (tester) async {
      await boot(tester);
      adapter.methodLog.clear();

      // The first panel's nav toolbar buttons (tooltips are unique per panel
      // only via the widget tree; tap the first occurrence of each).
      await tester.tap(find.byTooltip('Back').first);
      await tester.tap(find.byTooltip('Forward').first);
      await tester.tap(find.byTooltip('Stop').first);
      await tester.tap(find.byTooltip('Reload').first);
      await tester.tap(find.byTooltip('Mute media').first);
      await tester.pumpAndSettle();

      expect(
        adapter.methodLog.any((m) => m.contains('browserAction(')),
        isTrue,
      );
      expect(adapter.methodLog.any((m) => m.contains('reload(')), isTrue);
      expect(adapter.methodLog.any((m) => m.contains('toggleMute(')), isTrue);
      expect(find.byTooltip('Unmute media').first, findsOneWidget);
    },
  );

  testWidgets('detach button drives the embedded/detached state machine', (
    tester,
  ) async {
    final container = await boot(tester);
    await tester.tap(find.byTooltip('Detach to window').first);
    await tester.pumpAndSettle();
    // The adapter received detach; the controller state reflects detached.
    expect(adapter.methodLog.any((m) => m.startsWith('detach(')), isTrue);
    final anyDetached = container
        .read(workspaceControllerProvider)
        .panels
        .values
        .any((p) => p.state == WebviewState.detached);
    expect(anyDetached, isTrue);
  });

  // Ticket 02: editing an existing identity's isolation mode must re-sync the
  // workspace so ensurePanel detects the fingerprint change and rebuilds the
  // WebView (before the fix, didUpdateWidget only compared identity id sets,
  // so a mode edit silently kept the old store).
  testWidgets('editing an identity isolation mode rebuilds its panel', (
    tester,
  ) async {
    final container = await boot(tester);
    final projectId = container.read(selectedProjectIdProvider)!;
    final identityRepo = IdentityRepository(db);
    final identity = (await identityRepo.getByProject(
      projectId,
    )).firstWhere((i) => i.name == 'Alpha');

    adapter.methodLog.clear();

    await identityRepo.update(
      identity.copyWith(isolationMode: IsolationMode.sharedSession),
    );
    container.invalidate(identitiesProvider(projectId));
    await tester.pumpAndSettle();

    // The panel was closed and reopened under the sharedSession fingerprint.
    expect(
      adapter.methodLog.any((m) => m.startsWith('close(${identity.id})')),
      isTrue,
    );
    final reopen = adapter.methodLog.firstWhere(
      (m) => m.startsWith('openEmbedded(${identity.id},'),
      orElse: () => '',
    );
    expect(reopen, contains('sharedSession'));

    final panel = container
        .read(workspaceControllerProvider)
        .panels[identity.id]!;
    expect(panel.isolationMode, IsolationMode.sharedSession);
    // The NOT ISOLATED badge is rendered for sharedSession identities.
    expect(find.textContaining('NOT ISOLATED'), findsWidgets);
  });

  testWidgets('save a named workspace, then delete it', (tester) async {
    final container = await boot(tester);

    // Save.
    await tester.tap(find.byTooltip('Save workspace'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Layout A');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final savedId = container
        .read(workspaceControllerProvider)
        .selectedWorkspaceId;
    expect(savedId, isNotNull);

    // Delete.
    await tester.tap(find.byTooltip('Delete workspace'));
    await tester.pumpAndSettle();
    final wsRepo = await container.read(workspaceRepositoryProvider.future);
    expect(await wsRepo.getById(savedId!), isNull);
  });

  testWidgets(
    'QuickSites launcher is visible in the toolbar and opens Google Translate',
    (tester) async {
      await boot(tester);

      // The launcher button is rendered in the toolbar with the localized
      // Quick Sites label and a bolt icon; it must be visible at desktop size.
      final launcher = find.byKey(const ValueKey('quick-sites-trigger'));
      expect(launcher, findsOneWidget);
      expect(
        tester.getCenter(launcher).dx,
        greaterThan(900),
        reason: 'launcher should sit on the right side of the toolbar',
      );
      expect(
        find.descendant(of: launcher, matching: find.byIcon(Icons.bolt)),
        findsOneWidget,
      );

      // Before tapping, the menu (and thus 'Google Translate') is NOT
      // present in the overlay.
      expect(find.text('Google Translate'), findsNothing);

      // Tapping the launcher opens the QuickSitesMenu overlay surface.
      await tester.tap(launcher);
      await tester.pumpAndSettle();

      // The default quick-sites list includes Google Translate as the
      // first entry; it must now be visible in the overlay.
      expect(find.text('Google Translate'), findsOneWidget);
    },
  );

  testWidgets(
    'quick sites menu shows search field, All sites, and all required sites',
    (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const ValueKey('quick-sites-trigger')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('quick-sites-search')), findsOneWidget);
      expect(find.text('All sites'), findsOneWidget);
      for (final name in [
        'Google Translate',
        'ChatGPT',
        'Grok',
        'Notion',
        'Dictionary',
      ]) {
        expect(find.text(name), findsOneWidget);
      }
      // Each default row exposes the three typed actions.
      expect(
        find.byKey(const ValueKey('quick-sites-action-overlay')),
        findsNWidgets(5),
      );
      expect(
        find.byKey(const ValueKey('quick-sites-action-sideDock')),
        findsNWidgets(5),
      );
      expect(
        find.byKey(const ValueKey('quick-sites-action-newWindow')),
        findsNWidgets(5),
      );
    },
  );

  testWidgets(
    'quick site overlay action renders the in-app host with site chrome',
    (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const ValueKey('quick-sites-trigger')));
      await tester.pumpAndSettle();

      // Before launching, no quick-site host is rendered.
      expect(
        find.byKey(const ValueKey('quick-site-host-chrome')),
        findsNothing,
      );

      // Tap "Open overlay" on the Google Translate row (first default site).
      await tester.tap(
        find.byKey(const ValueKey('quick-sites-action-overlay')).at(0),
      );
      await tester.pumpAndSettle();

      // The overlay host is now rendered above the workspace layout with
      // app-owned chrome (title + reload + close). The live InAppWebView is
      // replaced by a placeholder because webviewPlatformSupportedProvider is
      // overridden to false, so we assert the chrome rather than web content.
      expect(
        find.byKey(const ValueKey('quick-site-host-chrome')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('quick-site-host-title')),
        findsOneWidget,
      );
      // The host title defaults to the site name until the WebView reports
      // a document title.
      expect(find.text('Google Translate'), findsOneWidget);
      final hostChrome = find.byKey(const ValueKey('quick-site-host-chrome'));
      expect(
        find.descendant(of: hostChrome, matching: find.byTooltip('Reload')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: hostChrome, matching: find.byTooltip('Close')),
        findsOneWidget,
      );

      // Closing the host removes it from the tree.
      await tester.tap(
        find.descendant(of: hostChrome, matching: find.byTooltip('Close')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('quick-site-host-chrome')),
        findsNothing,
      );

      // Reopening the menu still shows Google Translate as a recent entry.
      await tester.tap(find.byKey(const ValueKey('quick-sites-trigger')));
      await tester.pumpAndSettle();
      expect(find.text('Recently used'), findsOneWidget);
    },
  );

  testWidgets(
    'quick site sideDock action renders the host pinned to the right dock',
    (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const ValueKey('quick-sites-trigger')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('quick-sites-action-sideDock')).at(2),
      ); // Grok row
      await tester.pumpAndSettle();

      final host = find.byKey(const ValueKey('quick-site-host-chrome'));
      expect(host, findsOneWidget);
      // The sideDock host sits at the far right of the workspace body.
      final hostRect = tester.getRect(host);
      expect(hostRect.right, closeTo(1440, 16));
    },
  );

  testWidgets(
    'quick site newWindow action shows a local failure message under test '
    '(no native browser available)',
    (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const ValueKey('quick-sites-trigger')));
      await tester.pumpAndSettle();

      // The newWindow path calls InAppBrowser().openUrlRequest which throws
      // under widget test; the toolbar surfaces a compact error string.
      await tester.tap(
        find.byKey(const ValueKey('quick-sites-action-newWindow')).at(0),
      );
      await tester.pumpAndSettle();
      await tester.pump();

      expect(find.textContaining('Unable to open new window'), findsOneWidget);
    },
  );

  testWidgets('quick site keep-alive hides and restores the same host', (
    tester,
  ) async {
    await boot(tester);
    await tester.tap(find.byKey(const ValueKey('quick-sites-trigger')));
    await tester.pumpAndSettle();

    // The `常驻` toggle is per-site; each row exposes its own switch keyed
    // by the site id. Enabling Google Translate must not flip any other
    // site's toggle.
    final keepAlive = find.byKey(
      const ValueKey('quick-sites-keep-alive-google-translate'),
    );
    expect(keepAlive, findsOneWidget);
    expect(tester.widget<Switch>(keepAlive).value, isFalse);
    await tester.tap(keepAlive);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(keepAlive).value, isTrue);

    final chatgptKeepAlive = find.byKey(
      const ValueKey('quick-sites-keep-alive-chatgpt'),
    );
    expect(chatgptKeepAlive, findsOneWidget);
    expect(tester.widget<Switch>(chatgptKeepAlive).value, isFalse);

    await tester.tap(
      find.byKey(const ValueKey('quick-sites-action-overlay')).first,
    );
    await tester.pumpAndSettle();
    final chrome = find.byKey(const ValueKey('quick-site-host-chrome'));
    expect(chrome, findsOneWidget);
    final originalChromeElement = tester.element(chrome);

    await tester.tap(
      find.descendant(of: chrome, matching: find.byTooltip('Close')),
    );
    await tester.pumpAndSettle();
    expect(chrome, findsNothing);
    final hiddenChrome = find.byKey(
      const ValueKey('quick-site-host-chrome'),
      skipOffstage: false,
    );
    expect(hiddenChrome, findsOneWidget);
    expect(
      tester
          .widget<Offstage>(
            find.byKey(
              const ValueKey('quick-site-host-offstage'),
              skipOffstage: false,
            ),
          )
          .offstage,
      isTrue,
    );
    final residentTrigger = find.byKey(
      const ValueKey('resident-quick-site-trigger'),
    );
    expect(residentTrigger, findsOneWidget);

    await tester.tap(residentTrigger);
    await tester.pumpAndSettle();
    expect(chrome, findsOneWidget);
    expect(identical(tester.element(chrome), originalChromeElement), isTrue);
    expect(residentTrigger, findsNothing);

    await tester.tap(
      find.descendant(of: chrome, matching: find.byTooltip('Close')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-sites-trigger')));
    await tester.pumpAndSettle();
    await tester.tap(keepAlive);
    await tester.pumpAndSettle();
    expect(hiddenChrome, findsNothing);
    expect(residentTrigger, findsNothing);
  });

  testWidgets(
    'multiple resident quick sites keep independent instances and can be released',
    (tester) async {
      await boot(tester);

      // Open and hide Google Translate as a resident host.
      await tester.tap(find.byKey(const ValueKey('quick-sites-trigger')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('quick-sites-keep-alive-google-translate')),
      );
      await tester.tap(
        find.byKey(const ValueKey('quick-sites-action-overlay')).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      // Open and hide ChatGPT independently; it must not replace Google's
      // offstage WebView.
      await tester.tap(find.byKey(const ValueKey('quick-sites-trigger')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('quick-sites-keep-alive-chatgpt')),
      );
      await tester.tap(find.text('ChatGPT').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('quick-sites-actions-chatgpt')),
          matching: find.byKey(const ValueKey('quick-sites-action-overlay')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey(
            'resident-quick-site-trigger-google-translate-overlay',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('resident-quick-site-trigger-chatgpt-overlay'),
        ),
        findsOneWidget,
      );

      // Explicitly close just Google's resident entry. Its preference remains
      // enabled, while ChatGPT stays resident and its WebView remains mounted.
      // The release button lives in the hover-expanded resident row, so the
      // pointer must hover the row first.
      final googleRow = find.byKey(
        const ValueKey('resident-quick-site-trigger-google-translate-overlay'),
      );
      final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await hover.addPointer();
      await hover.moveTo(tester.getCenter(googleRow));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Release resident Google Translate'));
      await hover.removePointer();
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey(
            'resident-quick-site-trigger-google-translate-overlay',
          ),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('resident-quick-site-trigger-chatgpt-overlay'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('quick-sites-trigger')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Switch>(
              find.byKey(
                const ValueKey('quick-sites-keep-alive-google-translate'),
              ),
            )
            .value,
        isTrue,
      );
    },
  );

  testWidgets(
    'quick site overlay is draggable from the chrome and resizable from the bottom-right handle',
    (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const ValueKey('quick-sites-trigger')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('quick-sites-action-overlay')).at(0),
      );
      await tester.pumpAndSettle();

      final hostChrome = find.byKey(const ValueKey('quick-site-host-chrome'));
      expect(hostChrome, findsOneWidget);
      // The chrome bar shares the card's left/top; the card Material carries
      // the full floating geometry, so measure width/height on it.
      final hostCard = find.byKey(
        const ValueKey('quick-site-host-google-translate-overlay'),
      );
      expect(hostCard, findsOneWidget);
      final initialRect = tester.getRect(hostChrome);

      // A visible resize affordance sits at the bottom-right of the host.
      final resizeHandle = find.byKey(
        const ValueKey('quick-site-host-resize-handle'),
      );
      expect(resizeHandle, findsOneWidget);

      // Drag the chrome title to the left/down; the host moves with it.
      final titleCenter = tester.getCenter(
        find.byKey(const ValueKey('quick-site-host-title')),
      );
      final gesture = await tester.startGesture(titleCenter);
      await gesture.moveBy(const Offset(-120, 60));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();

      final draggedRect = tester.getRect(hostChrome);
      expect(
        draggedRect.left,
        lessThan(initialRect.left - 100),
        reason: 'overlay should move left when the chrome is dragged left',
      );
      expect(
        draggedRect.top,
        greaterThan(initialRect.top + 40),
        reason: 'overlay should move down when the chrome is dragged down',
      );

      // Resizing from the bottom-right handle grows the host. Dragging the
      // handle right widens, dragging it up shortens.
      final draggedCardRect = tester.getRect(hostCard);
      final handleCenter = tester.getCenter(resizeHandle);
      final resizeGesture = await tester.startGesture(handleCenter);
      await resizeGesture.moveBy(const Offset(80, -40));
      await tester.pumpAndSettle();
      await resizeGesture.up();
      await tester.pumpAndSettle();

      final resizedCardRect = tester.getRect(hostCard);
      expect(
        resizedCardRect.width,
        greaterThan(draggedCardRect.width + 60),
        reason: 'overlay should widen when the handle is dragged right',
      );
      expect(
        resizedCardRect.height,
        lessThan(draggedCardRect.height - 20),
        reason: 'overlay should shorten when the handle is dragged up',
      );
    },
  );

  testWidgets(
    'quick site sideDock host has no resize handle and stays pinned right',
    (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const ValueKey('quick-sites-trigger')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('quick-sites-action-sideDock')).at(2),
      ); // Grok row
      await tester.pumpAndSettle();

      final host = find.byKey(const ValueKey('quick-site-host-chrome'));
      expect(host, findsOneWidget);
      // The sideDock host sits at the far right of the workspace body.
      expect(tester.getRect(host).right, closeTo(1440, 16));
      // The side dock is fixed: no floating resize affordance is rendered.
      expect(
        find.byKey(const ValueKey('quick-site-host-resize-handle')),
        findsNothing,
      );
    },
  );

  testWidgets('quick sites menu closes on outside click', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const ValueKey('quick-sites-trigger')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-sites-menu')), findsOneWidget);

    // Tap an unobstructed point outside the menu card. The overlay's
    // transparent barrier receives this event and dismisses the menu.
    await tester.tapAt(const Offset(16, 70));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-sites-menu')), findsNothing);
  });

  testWidgets('mouse side buttons route to the active panel (back/forward)', (
    tester,
  ) async {
    final container = await boot(tester);
    // The foreground side-button listener is mounted over the layout area.
    final listenerFinder = find.byKey(
      const ValueKey('workspace-side-button-listener'),
    );
    expect(listenerFinder, findsOneWidget);

    // Promote the second panel to active; side buttons must follow it.
    final ids = container
        .read(workspaceControllerProvider)
        .panels
        .keys
        .toList();
    expect(ids, hasLength(3));
    container.read(workspaceControllerProvider.notifier).selectPanel(ids[1]);
    await tester.pumpAndSettle();
    adapter.methodLog.clear();

    final listener = tester.widget<Listener>(listenerFinder);
    listener.onPointerDown!(const PointerDownEvent(buttons: kBackMouseButton));
    await tester.pumpAndSettle();
    expect(
      adapter.methodLog,
      contains('browserAction(${ids[1]},BrowserAction.back)'),
    );

    listener.onPointerDown!(
      const PointerDownEvent(buttons: kForwardMouseButton),
    );
    await tester.pumpAndSettle();
    expect(
      adapter.methodLog,
      contains('browserAction(${ids[1]},BrowserAction.forward)'),
    );

    // Non-active panels must not receive the side-button action.
    expect(
      adapter.methodLog.any((m) => m.contains('browserAction(${ids[0]},')),
      isFalse,
    );
    expect(
      adapter.methodLog.any((m) => m.contains('browserAction(${ids[2]},')),
      isFalse,
    );
  });

  testWidgets('primary mouse button does not trigger navigation', (
    tester,
  ) async {
    await boot(tester);
    adapter.methodLog.clear();

    final listener = tester.widget<Listener>(
      find.byKey(const ValueKey('workspace-side-button-listener')),
    );
    listener.onPointerDown!(
      const PointerDownEvent(buttons: kPrimaryMouseButton),
    );
    await tester.pumpAndSettle();
    expect(
      adapter.methodLog.any((m) => m.startsWith('browserAction(')),
      isFalse,
    );
  });

  testWidgets('side-button Listener does not block taps on child panels', (
    tester,
  ) async {
    final container = await boot(tester);
    final ids = container
        .read(workspaceControllerProvider)
        .panels
        .keys
        .toList();
    expect(ids, hasLength(3));

    // Tapping a non-active panel header must still reach the child's
    // InkWell and move selection away from the first panel, proving the
    // translucent Listener wrapping the layout does not swallow child
    // gestures. (Asserted as "not the initial panel" rather than a
    // specific id so the test does not depend on identity ordering.)
    await tester.tap(find.text('Charlie'));
    await tester.pumpAndSettle();
    expect(
      container.read(workspaceControllerProvider).selectedPanelId,
      isNot(ids[0]),
    );
  });

  testWidgets(
    'panel toolbar device menu writes the preset back and rebuilds the view',
    (tester) async {
      final container = await boot(tester);
      final identityId = container
          .read(workspaceControllerProvider)
          .panels
          .keys
          .first;
      final before = container
          .read(workspaceControllerProvider)
          .panels[identityId]!
          .fingerprint;

      // The quick switch is keyed per panel and listed in the nav toolbar.
      await tester.tap(find.byKey(ValueKey('device-preset-menu-$identityId')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('device-preset-item-iphone-15')),
      );
      await tester.pumpAndSettle();

      // Write-back semantics: the preset persisted on the identity record —
      // the same field the management dialog edits.
      final identityRepo = IdentityRepository(db);
      final identity = await identityRepo.getById(identityId);
      expect(identity!.devicePresetId, 'iphone-15');

      // The identity-signature sync re-ran ensurePanel: fingerprint flipped
      // and the headless adapter saw the close + reopen pair.
      final panel = container
          .read(workspaceControllerProvider)
          .panels[identityId]!;
      expect(panel.devicePresetId, 'iphone-15');
      expect(panel.fingerprint, isNot(before));
      expect(adapter.methodLog, contains('close($identityId)'));
    },
  );
}
