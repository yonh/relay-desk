/// Integration test for per-identity device emulation
/// (E-FEAT-DEVICE-EMULATION), run on real macOS via
///   `flutter test integration_test/device_emulation_test.dart -d macos`
///
/// It drives the REAL ProfiledWebViewPlugin through the app's own widget tree
/// — no mocks — and proves, end to end:
///
///   - an identity with the `iphone-15` preset sends the iPhone UA in the
///     HTTP request (server-echoed) AND reports it via `navigator.userAgent`;
///   - a `size-iphone-14-390x844` fixed preset does the same — a
///     device-named window-size preset is full emulation, not a narrow
///     desktop viewport;
///   - `navigator.maxTouchPoints` / `'ontouchstart' in window` reflect the
///     emulated touch surface;
///   - `window.innerWidth` and width media queries resolve to the emulated
///     mobile viewport (the platform view is clamped to the preset width);
///   - switching the preset back to desktop rebuilds the WebView: the same
///     identity's next page load reports the desktop UA again;
///   - the isolation guarantee is unaffected (preset does not change the
///     per-identity data store kind).
///
/// Honest boundary: `(pointer: coarse)` media queries and real touch events
/// are NOT emulated — the capability probe reports touchEmulation for the
/// JS detection surface only, and deviceMetricsOverride stays false.
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late RelayDatabase db;
  late HttpServer server;
  late String baseUrl;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('relay_desk_device_');
    db = RelayDatabase(NativeDatabase(File(p.join(tempDir.path, 'dev.db'))));
    // Local hermetic origin. The served page echoes the request's User-Agent
    // header into a data attribute so evaluateJs can read the server-seen UA
    // and the JS-reported UA from the same load.
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
    server.listen((req) {
      final ua = req.headers.value('user-agent') ?? '';
      req.response
        ..headers.contentType = ContentType.html
        ..write(
          '<!doctype html><title>ua-echo</title>'
          '<body data-server-ua="$ua">probe</body>',
        )
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
        // Pin the UI language so assertions hold regardless of host locale.
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

  /// Waits until the adapter holds a native viewId for [identityId]. When
  /// [otherThan] is given, the stale viewId from before a fingerprint rebuild
  /// does not count — the rebuild's close clears it asynchronously and a
  /// fresh platform view registers a different id shortly after.
  Future<void> waitForView(
    WidgetTester tester,
    MacosProfiledWebviewAdapter adapter,
    String identityId, {
    int? otherThan,
  }) async {
    for (var i = 0; i < 200; i++) {
      final viewId = adapter.viewIdFor(identityId);
      if (viewId != null && viewId != otherThan) return;
      await tester.pump(const Duration(milliseconds: 100));
    }
    fail('no native view registered for $identityId');
  }

  Future<void> waitForJs(
    WidgetTester tester,
    MacosProfiledWebviewAdapter adapter,
    String identityId,
    String js, {
    String description = '',
  }) async {
    for (var i = 0; i < 100; i++) {
      final res = await adapter.evaluateJs(identityId, js);
      if (res == 'true') return;
      // pump, not bare delay: platform-view recreation after a fingerprint
      // rebuild is driven by frames, so polling must keep them flowing.
      await tester.pump(const Duration(milliseconds: 100));
    }
    fail('JS probe never became true for $identityId: $description');
  }

  testWidgets(
    'iphone-15 preset: UA override, touch surface, and emulated viewport',
    (tester) async {
      final container = await boot(tester);
      final adapter = adapterOf(container);

      final projectRepo = await container.read(
        projectRepositoryProvider.future,
      );
      final identityRepo = await container.read(
        identityRepositoryProvider.future,
      );
      final project = await projectRepo.create(
        name: 'DeviceTest',
        targetUrl: baseUrl,
        allowPrivateNetwork: true,
      );
      final mobile = await identityRepo.create(
        projectId: project.id,
        name: 'Phone',
        color: '#112233',
        isolationMode: IsolationMode.nativeProfile,
        devicePresetId: 'iphone-15',
      );
      final fixedPhone = await identityRepo.create(
        projectId: project.id,
        name: 'FixedPhone',
        color: '#778899',
        isolationMode: IsolationMode.nativeProfile,
        devicePresetId: 'size-iphone-14-390x844',
      );
      final desktop = await identityRepo.create(
        projectId: project.id,
        name: 'Desk',
        color: '#445566',
        isolationMode: IsolationMode.nativeProfile,
        devicePresetId: 'desktop-1920',
      );
      container.read(selectedProjectIdProvider.notifier).select(project.id);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await waitForView(tester, adapter, mobile.id);
      await waitForView(tester, adapter, fixedPhone.id);
      await waitForView(tester, adapter, desktop.id);
      for (final id in [mobile.id, fixedPhone.id, desktop.id]) {
        await waitForJs(
          tester,
          adapter,
          id,
          "document.title==='ua-echo'?'true':'false'",
          description: 'page loaded',
        );
      }

      // --- HTTP UA (server-echoed) and JS UA both report iPhone ---
      const uaRead = "navigator.userAgent+'|'+document.body.dataset.serverUa";
      final mobileUa = await adapter.evaluateJs(mobile.id, uaRead);
      expect(
        mobileUa,
        contains('iPhone'),
        reason: 'navigator.userAgent must report the preset UA',
      );
      final mobileUaParts = mobileUa.split('|');
      expect(
        mobileUaParts[1],
        contains('iPhone'),
        reason: 'the HTTP User-Agent header must carry the preset UA',
      );

      // A device-named fixed-size preset is full emulation too: the
      // server-echoed HTTP UA and navigator.userAgent both report iPhone.
      final fixedPhoneUa = await adapter.evaluateJs(fixedPhone.id, uaRead);
      expect(
        fixedPhoneUa,
        contains('iPhone'),
        reason:
            'a device-named window-size preset must serve the mobile UA, '
            'not a narrow desktop one',
      );

      // Desktop identity keeps the WKWebView default UA (no mobile markers).
      final desktopUa = await adapter.evaluateJs(desktop.id, uaRead);
      expect(desktopUa, isNot(contains('iPhone')));
      expect(desktopUa, isNot(contains('Android')));

      // --- Touch detection surface ---
      expect(
        await adapter.evaluateJs(
          mobile.id,
          "navigator.maxTouchPoints===5?'true':'false'",
        ),
        'true',
      );
      expect(
        await adapter.evaluateJs(
          mobile.id,
          "('ontouchstart' in window)?'true':'false'",
        ),
        'true',
      );
      expect(
        await adapter.evaluateJs(
          fixedPhone.id,
          "('ontouchstart' in window)?'true':'false'",
        ),
        'true',
      );
      expect(
        await adapter.evaluateJs(
          desktop.id,
          "('ontouchstart' in window)?'true':'false'",
        ),
        'false',
      );

      // --- Emulated viewport: innerWidth + width media queries see the
      // mobile width even though the outer panel is wider. ---
      final innerWidth = int.tryParse(
        await adapter.evaluateJs(mobile.id, 'window.innerWidth.toString()'),
      );
      expect(innerWidth, isNotNull);
      expect(
        innerWidth,
        lessThanOrEqualTo(393),
        reason: 'iPhone 15 preset viewport width is 393 CSS px',
      );
      expect(
        await adapter.evaluateJs(
          mobile.id,
          "matchMedia('(max-width: 480px)').matches?'true':'false'",
        ),
        'true',
        reason: 'mobile media queries must resolve against the clamp',
      );

      // Fixed sizing pins BOTH dims to the device resolution: the iPhone 14
      // viewport is exactly 390x844 CSS px (panel is sized to fit it).
      final fixedInnerWidth = int.tryParse(
        await adapter.evaluateJs(fixedPhone.id, 'window.innerWidth.toString()'),
      );
      expect(
        fixedInnerWidth,
        lessThanOrEqualTo(390),
        reason: 'iPhone 14 fixed preset viewport width is 390 CSS px',
      );
      expect(
        await adapter.evaluateJs(
          fixedPhone.id,
          "matchMedia('(max-width: 390px)').matches?'true':'false'",
        ),
        'true',
        reason: 'fixed preset media queries resolve against the device size',
      );

      // --- Isolation is unaffected by emulation ---
      expect(await adapter.storeKindFor(mobile.id), 'perIdentity');
      expect(await adapter.storeKindFor(fixedPhone.id), 'perIdentity');
      expect(await adapter.storeKindFor(desktop.id), 'perIdentity');

      // --- Switching the preset back to desktop rebuilds the view: the
      // NEXT load reports the desktop UA again (fingerprint rebuild, not a
      // silent reuse of the iPhone-configured view). ---
      final identity = (await identityRepo.getById(mobile.id))!;
      await identityRepo.update(
        identity.copyWith(devicePresetId: 'desktop-1920'),
      );
      final preSwitchViewId = adapter.viewIdFor(mobile.id);
      container.invalidate(identitiesProvider(project.id));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      // The fingerprint rebuild closes the old view and registers a new one
      // asynchronously — wait for a DIFFERENT viewId, then for the reload.
      await waitForView(tester, adapter, mobile.id, otherThan: preSwitchViewId);
      await waitForJs(
        tester,
        adapter,
        mobile.id,
        "document.title==='ua-echo'?'true':'false'",
        description: 'rebuilt page loaded',
      );
      final backToDesktop = await adapter.evaluateJs(mobile.id, uaRead);
      expect(
        backToDesktop,
        isNot(contains('iPhone')),
        reason: 'desktop preset must restore the default UA on rebuild',
      );
    },
  );
}
