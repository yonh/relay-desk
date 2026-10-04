/// Integration test for the Shared Session isolation fix
/// (.scratch/shared-session/issues/01 + 02), run on real macOS via
///   `flutter test integration_test/shared_session_test.dart -d macos`
///
/// It drives the REAL ProfiledWebViewPlugin through the app's own widget tree
/// — no mocks — and proves, end to end:
///
///   - two sharedSession identities' panels share one persistent store
///     (`WKWebsiteDataStore.default()`): a cookie + localStorage written
///     through one panel's page is visible in the other panel's page;
///   - a nativeProfile identity stays isolated from that shared data;
///   - editing an identity's mode sharedSession -> nativeProfile rebuilds its
///     WebView onto a per-identity store, and switching back restores it;
///   - closing and reopening a shared panel preserves the shared session.
///
/// Cold-restart persistence is verified by running the file twice:
///   `--dart-define=RESTART_PHASE=write` records a marker cookie in the shared
///   store; `--dart-define=RESTART_PHASE=read` in a fresh process asserts the
///   marker survived the restart. With no dart-define the full in-session
///   flow runs (write -> close -> reopen -> read).
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:relay_desk/app/localization.dart';
import 'package:relay_desk/app/providers.dart';
import 'package:relay_desk/core/platform/domain.dart';
import 'package:relay_desk/data/database/database.dart';
import 'package:relay_desk/features/workspace/workspace_controller.dart';
import 'package:relay_desk/main.dart';
import 'package:relay_desk/platform/webview/macos_profiled_webview_adapter.dart';

const _restartPhase = String.fromEnvironment('RESTART_PHASE');
const _restartCookie = 'rd_restart_marker';
const _markerValue = 'rd_shared_cookie';
// Stable identity ids + a fixed port for the restart phases: the per-identity
// store is keyed by identity UUID and localStorage is origin-scoped, so both
// must be identical across the write and read processes.
const _restartS1Id = 'aa000000-0000-4000-8000-0000000000a1';
const _restartS2Id = 'aa000000-0000-4000-8000-0000000000a2';
const _restartIsoId = 'aa000000-0000-4000-8000-0000000000b1';
const _restartPort = 18093;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late RelayDatabase db;
  late HttpServer server;
  late String baseUrl;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('relay_desk_shared_');
    db = RelayDatabase(NativeDatabase(File(p.join(tempDir.path, 'shared.db'))));
    // Local hermetic origin — the DebugProfile entitlements grant
    // network.server + network.client, matching the Gate-0 spike setup.
    // The restart phases pin the port: localStorage is origin-scoped, so the
    // write and read processes must share the same origin.
    server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      _restartPhase.isEmpty ? 0 : _restartPort,
    );
    baseUrl = 'http://127.0.0.1:${server.port}';
    server.listen((req) {
      req.response
        ..headers.contentType = ContentType.html
        ..write('<!doctype html><title>probe</title><body>probe</body>')
        ..close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<ProviderContainer> boot(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async {
          ref.onDispose(db.close);
          return db;
        }),
        localeStorageProvider.overrideWithValue(
          InMemoryLocaleStorage(LocalePreference.english),
        ),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const RelayDeskApp(),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  MacosProfiledWebviewAdapter adapterOf(ProviderContainer container) {
    final adapter = container.read(webviewAdapterProvider);
    expect(
      adapter,
      isA<MacosProfiledWebviewAdapter>(),
      reason: 'integration test must run against the real macOS adapter',
    );
    return adapter as MacosProfiledWebviewAdapter;
  }

  Future<void> waitForView(
    WidgetTester tester,
    MacosProfiledWebviewAdapter adapter,
    String identityId,
  ) async {
    for (var i = 0; i < 200; i++) {
      if (adapter.viewIdFor(identityId) != null) return;
      await tester.pump(const Duration(milliseconds: 100));
    }
    fail('no native view registered for $identityId');
  }

  /// Poll a JS expression in the identity's live view until it returns 'true'.
  Future<void> waitForJs(
    MacosProfiledWebviewAdapter adapter,
    String identityId,
    String js, {
    String description = '',
  }) async {
    for (var i = 0; i < 100; i++) {
      final res = await adapter.evaluateJs(identityId, js);
      if (res == 'true') return;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    fail('JS probe never became true for $identityId: $description');
  }

  /// Creates a project + identities via the repositories (same path the
  /// management UI uses) and selects the project so the workspace syncs.
  /// Returns name -> created identity id. `fixedIds` pins identity UUIDs so
  /// the native per-identity store survives across processes (restart phases).
  Future<Map<String, String>> openProject(
    WidgetTester tester,
    ProviderContainer container, {
    required List<(String, IsolationMode)> identities,
    String projectName = 'SharedSess',
    Map<String, String> fixedIds = const {},
  }) async {
    final projectRepo = await container.read(projectRepositoryProvider.future);
    final identityRepo = await container.read(
      identityRepositoryProvider.future,
    );
    final project = await projectRepo.create(
      name: projectName,
      targetUrl: baseUrl,
      allowPrivateNetwork: true,
    );
    final ids = <String, String>{};
    for (final (name, mode) in identities) {
      final identity = await identityRepo.create(
        projectId: project.id,
        name: name,
        color: '#112233',
        isolationMode: mode,
        id: fixedIds[name],
      );
      ids[name] = identity.id;
    }
    container.read(selectedProjectIdProvider.notifier).select(project.id);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    return ids;
  }

  // JS probe: the shared cookie AND a localStorage marker must both be
  // visible in the reading view's page context.
  const markerJs =
      "(function(){try{return document.cookie.indexOf('$_markerValue=1')>=0"
      "&&localStorage.getItem('rd_marker')==='s'?'true':'false'}"
      "catch(e){return 'false'}})()";
  const markerWriteJs =
      "document.cookie='$_markerValue=1;path=/';"
      "localStorage.setItem('rd_marker','s');'true'";
  const markerClearJs =
      "document.cookie='$_markerValue=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=/';"
      "localStorage.removeItem('rd_marker');'true'";

  testWidgets('shared session: store kinds, sharing, isolation, mode switch', (
    tester,
  ) async {
    final container = await boot(tester);
    final adapter = adapterOf(container);

    final ids = await openProject(
      tester,
      container,
      identities: [
        ('SharedA', IsolationMode.sharedSession),
        ('SharedB', IsolationMode.sharedSession),
        ('Iso', IsolationMode.nativeProfile),
      ],
    );
    final aId = ids['SharedA']!;
    final bId = ids['SharedB']!;
    final isoId = ids['Iso']!;

    expect(
      container.read(workspaceControllerProvider).panels.length,
      3,
      reason: 'three identity panels must be open',
    );
    await waitForView(tester, adapter, aId);
    await waitForView(tester, adapter, bId);
    await waitForView(tester, adapter, isoId);

    // --- store kinds land on the right WKWebsiteDataStore ---
    expect(await adapter.storeKindFor(aId), 'shared');
    expect(await adapter.storeKindFor(bId), 'shared');
    expect(await adapter.storeKindFor(isoId), 'perIdentity');

    // --- write through A's page; B (shared) sees it, Iso does not ---
    await waitForJs(
      adapter,
      aId,
      "document.title==='probe'?'true':'false'",
      description: 'A page loaded',
    );
    await waitForJs(
      adapter,
      bId,
      "document.title==='probe'?'true':'false'",
      description: 'B page loaded',
    );
    await waitForJs(
      adapter,
      isoId,
      "document.title==='probe'?'true':'false'",
      description: 'Iso page loaded',
    );

    await adapter.evaluateJs(aId, markerWriteJs);
    await waitForJs(
      adapter,
      bId,
      markerJs,
      description: 'B reads shared cookie + localStorage',
    );
    final isoSees = await adapter.evaluateJs(isoId, markerJs);
    expect(isoSees, 'false', reason: 'nativeProfile must stay isolated');

    // --- close and reopen A's panel: same shared store, still visible ---
    final controller = container.read(workspaceControllerProvider.notifier);
    controller.removePanel(aId);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(adapter.viewIdFor(aId), isNull);

    final identityRepo = await container.read(
      identityRepositoryProvider.future,
    );
    final aRow = (await identityRepo.getByProject(
      container.read(selectedProjectIdProvider)!,
    )).firstWhere((i) => i.id == aId);
    controller.ensurePanel(
      aRow,
      (await container.read(selectedProjectProvider.future))!,
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await waitForView(tester, adapter, aId);
    expect(await adapter.storeKindFor(aId), 'shared');
    await waitForJs(
      adapter,
      aId,
      markerJs,
      description: 'reopened shared panel still sees shared data',
    );

    // --- switch B to nativeProfile: rebuild drops the shared store ---
    final oldBViewId = adapter.viewIdFor(bId);
    final bRow = (await identityRepo.getByProject(
      container.read(selectedProjectIdProvider)!,
    )).firstWhere((r) => r.id == bId);
    await identityRepo.update(
      bRow.copyWith(isolationMode: IsolationMode.nativeProfile),
    );
    container.invalidate(identitiesProvider(bRow.projectId));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    // The panel's fingerprint + isolationMode must flip before the native
    // side can rebuild — poll for it so we don't race the provider refetch.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      final p = container.read(workspaceControllerProvider).panels[bId];
      if (p != null && p.isolationMode == IsolationMode.nativeProfile) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    final bPanel = container.read(workspaceControllerProvider).panels[bId]!;
    expect(bPanel.isolationMode, IsolationMode.nativeProfile);
    expect(bPanel.fingerprint, contains('nativeProfile'));
    // Poll for a NEW viewId — the state flip only schedules a rebuild; the
    // platform view is recreated asynchronously once the AppKitView with the
    // new fingerprint key is inflated and the native factory returns.
    final viewDeadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(viewDeadline)) {
      final v = adapter.viewIdFor(bId);
      if (v != null && v != oldBViewId) break;
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      adapter.viewIdFor(bId),
      allOf(isNotNull, isNot(oldBViewId)),
      reason: 'mode switch must recreate the platform view',
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      await adapter.storeKindFor(bId),
      'perIdentity',
      reason: 'after a mode switch the view must use the per-identity store',
    );
    final bSeesNow = await adapter.evaluateJs(bId, markerJs);
    expect(
      bSeesNow,
      'false',
      reason: 'per-identity store must not contain the shared data',
    );
    // A is untouched and still sees the shared data.
    expect(await adapter.storeKindFor(aId), 'shared');
    await waitForJs(
      adapter,
      aId,
      markerJs,
      description: 'A still sees shared data after B switched away',
    );

    // --- reverse direction: Iso -> sharedSession joins the default store ---
    final oldIsoViewId = adapter.viewIdFor(isoId);
    final isoRow = (await identityRepo.getByProject(
      container.read(selectedProjectIdProvider)!,
    )).firstWhere((r) => r.id == isoId);
    await identityRepo.update(
      isoRow.copyWith(isolationMode: IsolationMode.sharedSession),
    );
    container.invalidate(identitiesProvider(isoRow.projectId));
    final isoDeadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(isoDeadline)) {
      final v = adapter.viewIdFor(isoId);
      if (v != null && v != oldIsoViewId) break;
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      adapter.viewIdFor(isoId),
      allOf(isNotNull, isNot(oldIsoViewId)),
      reason: 'mode switch to sharedSession must recreate the platform view',
    );
    expect(await adapter.storeKindFor(isoId), 'shared');
    // The previously-isolated identity now reads the shared cookie +
    // localStorage — without any data migration.
    await waitForJs(
      adapter,
      isoId,
      markerJs,
      description: 'Iso reads shared data after switching to sharedSession',
    );

    // Cleanup: drop the shared markers so subsequent runs start clean.
    await adapter.evaluateJs(aId, markerClearJs);
  });

  // Cold-restart persistence across process restarts, driven by
  // --dart-define=RESTART_PHASE=write|read. The marker cookie is written via
  // the store-level harness (setCookie) — writing through the page is proven
  // by the main test above; this phase pair isolates disk persistence.
  //
  // Ticket 02 requires BOTH shared identities to read the shared cookie AND
  // localStorage after restart, and a nativeProfile identity to keep only its
  // own data. Identity ids and the local origin are pinned so the same
  // WKWebsiteDataStores and the same localStorage origin apply in both runs.
  //
  // Note: a write-only run leaves a benign 127.0.0.1-scoped marker cookie in
  // the DEV container's shared store; the read phase removes it.
  testWidgets(
    'stores survive a cold restart',
    (tester) async {
      final container = await boot(tester);
      final adapter = adapterOf(container);

      final ids = await openProject(
        tester,
        container,
        identities: [
          ('S1', IsolationMode.sharedSession),
          ('S2', IsolationMode.sharedSession),
          ('Iso', IsolationMode.nativeProfile),
        ],
        fixedIds: const {
          'S1': _restartS1Id,
          'S2': _restartS2Id,
          'Iso': _restartIsoId,
        },
      );
      final s1 = ids['S1']!;
      final s2 = ids['S2']!;
      final iso = ids['Iso']!;
      for (final id in [s1, s2, iso]) {
        await waitForView(tester, adapter, id);
      }
      expect(await adapter.storeKindFor(s1), 'shared');
      expect(await adapter.storeKindFor(s2), 'shared');
      expect(await adapter.storeKindFor(iso), 'perIdentity');

      // Page contexts only accept storage after a load.
      for (final id in [s1, s2, iso]) {
        await waitForJs(
          adapter,
          id,
          "document.title==='probe'?'true':'false'",
          description: 'restart page loaded for $id',
        );
      }

      const sharedProbeJs =
          "(function(){try{return document.cookie.indexOf('$_restartCookie=persisted')>=0"
          "&&localStorage.getItem('rd_ls_restart')==='yes'?'true':'false'}"
          "catch(e){return 'false'}})()";
      const isoProbeJs =
          "(function(){try{return document.cookie.indexOf('$_restartCookie=')<0"
          "&&localStorage.getItem('rd_ls_restart')===null"
          "&&localStorage.getItem('rd_iso_restart')==='isolated'?'true':'false'}"
          "catch(e){return 'false'}})()";

      if (_restartPhase == 'write') {
        // Persistent expiry — a session cookie never reaches disk, so the
        // restart check would be meaningless (ticket 02 requires
        // distinguishing persistence failure from normal expiry).
        expect(
          await adapter.setCookie(
            s1,
            _restartCookie,
            'persisted',
            expires: DateTime.now().add(const Duration(days: 30)),
          ),
          isTrue,
        );
        await adapter.evaluateJs(
          s1,
          "localStorage.setItem('rd_ls_restart','yes');'true'",
        );
        await adapter.evaluateJs(
          iso,
          "localStorage.setItem('rd_iso_restart','isolated');'true'",
        );
        // Prove in-process that the second shared identity's page context
        // already sees the shared store's data (propagation is async) and
        // the isolated one does not.
        await waitForJs(
          adapter,
          s2,
          sharedProbeJs,
          description: 'S2 sees shared cookie+localStorage pre-restart',
        );
        await waitForJs(
          adapter,
          iso,
          isoProbeJs,
          description: 'Iso isolated from shared data pre-restart',
        );
        // WKHTTPCookieStore/localStorage writes flush asynchronously — the
        // process must not exit before the daemon commits them to disk.
        await Future.delayed(const Duration(seconds: 5));
        return;
      }

      // read phase: brand-new process; the persisted stores must deliver the
      // same data to the fresh views.
      for (final id in [s1, s2]) {
        await waitForJs(
          adapter,
          id,
          sharedProbeJs,
          description: '$id reads shared cookie+localStorage after restart',
        );
      }
      await waitForJs(
        adapter,
        iso,
        isoProbeJs,
        description: 'Iso keeps only its own data after restart',
      );

      // Cleanup shared-store markers so the phase pair can be re-run.
      await adapter.deleteCookie(s1, _restartCookie);
      await adapter.evaluateJs(
        s1,
        "localStorage.removeItem('rd_ls_restart');'true'",
      );
      await adapter.evaluateJs(
        iso,
        "localStorage.removeItem('rd_iso_restart');'true'",
      );
    },
    // Not run inside the ordinary suite — phases are invoked explicitly via
    // --dart-define so a plain `flutter test` run reports a skip, never a
    // vacuous pass.
    skip: _restartPhase != 'write' && _restartPhase != 'read',
  );
}
