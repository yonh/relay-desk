/// Tests for MacosProfiledWebviewAdapter against a mocked `profiled_webview`
/// MethodChannel. Covers the stale-close race from .scratch/shared-session
/// issue 02: an async close issued for the OLD view must not drop the mapping
/// or report `closed` once a new view has been registered for the identity.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_desk/core/platform/domain.dart';
import 'package:relay_desk/core/platform/webview_adapter.dart';
import 'package:relay_desk/platform/webview/macos_profiled_webview_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('profiled_webview');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late MacosProfiledWebviewAdapter adapter;

  // `variant` feeds the URL so different variants produce different
  // fingerprints (the fingerprint hashes the immutable config).
  PanelRuntimeConfig config(String variant) => PanelRuntimeConfig(
    identityId: 'iid',
    url: 'https://example.com/$variant',
    isolationMode: IsolationMode.nativeProfile,
    userAgent: '',
    devicePresetId: 'desktop-mac',
  );

  setUp(() {
    adapter = MacosProfiledWebviewAdapter();
  });

  tearDown(() {
    adapter.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'stale async close does not drop a re-registered view or emit closed',
    () async {
      // Every 'close' invoke is held until the test releases it, simulating a
      // native close that resolves AFTER a new view was already registered.
      final closeCalls = <Completer<void>>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'close') {
          final gate = Completer<void>();
          closeCalls.add(gate);
          await gate.future;
        }
        return null;
      });

      final events = <WebviewEvent>[];
      final sub = adapter.events.listen(events.add);

      await adapter.openEmbedded(config('fp-1'), _bounds());
      adapter.registerView('iid', 7);
      expect(adapter.viewIdFor('iid'), 7);
      expect(adapter.stateFor('iid'), WebviewState.embedded);

      // Close #1 (stale): channel call is held.
      final close1 = adapter.close('iid');

      // Reopen under a new fingerprint while close #1 is in flight.
      final reopen = adapter.openEmbedded(config('fp-2'), _bounds());
      adapter.registerView('iid', 8);
      expect(adapter.viewIdFor('iid'), 8);

      // Release all pending closes; their tails must not clobber the new view.
      for (final gate in closeCalls) {
        gate.complete();
      }
      await close1;
      await reopen;
      await pumpEventQueue();

      expect(adapter.viewIdFor('iid'), 8);
      expect(adapter.stateFor('iid'), WebviewState.embedded);

      final closedAfterReopen = events
          .whereType<WebviewStateChanged>()
          .toList()
          .lastIndexWhere((e) => e.state == WebviewState.closed);
      final reopenedAt = events.lastIndexWhere(
        (e) => e is WebviewStateChanged && e.state == WebviewState.embedded,
      );
      // No 'closed' event may be emitted after the reopen's embedded state.
      expect(closedAfterReopen, lessThan(reopenedAt));
      await sub.cancel();
    },
  );

  test('plain close still clears the view mapping and emits closed', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);

    await adapter.openEmbedded(config('fp-1'), _bounds());
    adapter.registerView('iid', 7);
    await adapter.close('iid');

    expect(adapter.viewIdFor('iid'), isNull);
    expect(adapter.stateFor('iid'), WebviewState.closed);
  });

  test('navigate emits blocked when loadUrl fails on a dead view', () async {
    // A stale viewId whose native view was torn down makes loadUrl throw.
    // Without the blocked event the panel's loading flag stays latched and
    // the spinner never stops.
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'loadUrl') {
        throw PlatformException(code: 'bad_args', message: 'loadUrl');
      }
      return null;
    });

    final events = <WebviewEvent>[];
    final sub = adapter.events.listen(events.add);
    await adapter.openEmbedded(config('fp-1'), _bounds());
    adapter.registerView('iid', 7);
    events.clear();

    await adapter.navigate('iid', Uri.parse('https://example.com/x'));
    await pumpEventQueue();

    expect(events.whereType<WebviewNavigationBlocked>(), hasLength(1));
    expect(adapter.navInfoFor('iid').loading, isFalse);
    await sub.cancel();
  });

  test(
    'reload on an unregistered view emits blocked instead of hanging',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      final events = <WebviewEvent>[];
      final sub = adapter.events.listen(events.add);

      await adapter.reload('iid');
      await pumpEventQueue();

      expect(events.whereType<WebviewNavigationBlocked>(), hasLength(1));
      await sub.cancel();
    },
  );

  test(
    'a matching closed event clears the mapping; a stale one is ignored',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      await adapter.openEmbedded(config('fp-1'), _bounds());
      adapter.registerView('iid', 7);

      // A 'closed' for a DIFFERENT viewId is stale (a newer view was already
      // registered) — it must not strip the live mapping or change state.
      await _emitNativeStateChanged('iid', 'closed', viewId: 5);
      await pumpEventQueue();
      expect(adapter.viewIdFor('iid'), 7);
      expect(adapter.stateFor('iid'), WebviewState.embedded);

      // A 'closed' carrying the live viewId is the real teardown writeback.
      await _emitNativeStateChanged('iid', 'closed', viewId: 7);
      await pumpEventQueue();
      expect(adapter.viewIdFor('iid'), isNull);
      expect(adapter.stateFor('iid'), WebviewState.closed);
    },
  );

  test('windowInventory only calls windowInventory, leaves view/profile state '
      'untouched, and returns json-safe string-keyed dictionaries', () async {
    final calls = <MethodCall>[];
    Object? response;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'windowInventory') return response;
      return null;
    });

    // StandardMessageCodec decodes native dictionaries as
    // Map<Object?, Object?> with nested dictionaries, lists and NSNull
    // entries — the exact shape windowInventory() has to normalize.
    response = <Object?, Object?>{
      'currentWindowId': null,
      'mainWindowId': 7,
      'windows': <Object?>[
        <Object?, Object?>{
          'windowId': 7,
          'title': 'main',
          'isKey': false,
          'isMain': true,
          'bounds': <Object?, Object?>{
            'x': 0.0,
            'y': 0.0,
            'width': 800.0,
            'height': 600.0,
          },
        },
      ],
      'views': <Object?>[
        <Object?, Object?>{
          'viewId': 7,
          'identityId': 'iid',
          'windowId': 7,
          'hasKeyboardFocus': false,
        },
      ],
    };

    final events = <WebviewEvent>[];
    final sub = adapter.events.listen(events.add);
    await adapter.openEmbedded(config('fp-1'), _bounds());
    adapter.registerView('iid', 7);
    await pumpEventQueue();
    final fingerprint = adapter.fingerprintFor('iid');
    final navUrl = adapter.navInfoFor('iid').url;
    calls.clear();
    events.clear();

    final inventory = await adapter.windowInventory();

    // Read-only sample: no arguments, and nothing else crosses the channel.
    expect(calls.map((c) => c.method), <String>['windowInventory']);
    expect(calls.single.arguments, isNull);

    // The sample must not touch the identity's view/profile bookkeeping.
    expect(adapter.viewIdFor('iid'), 7);
    expect(adapter.stateFor('iid'), WebviewState.embedded);
    expect(adapter.fingerprintFor('iid'), fingerprint);
    expect(adapter.navInfoFor('iid').url, navUrl);
    expect(events, isEmpty);

    // Semantic values (and the null that must survive as JSON null).
    expect(inventory, isA<Map<String, dynamic>>());
    expect(inventory.containsKey('currentWindowId'), isTrue);
    expect(inventory['currentWindowId'], isNull);
    expect(inventory['mainWindowId'], 7);

    expect((inventory['windows']! as List).length, 1);
    final rawWindow = (inventory['windows']! as List).single;
    expect(rawWindow, isA<Map<String, dynamic>>());
    final window = (rawWindow! as Map).cast<String, Object?>();
    expect(window['windowId'], 7);
    expect(window['isKey'], isFalse);

    final rawBounds = window['bounds'];
    expect(rawBounds, isA<Map<String, dynamic>>());
    final bounds = (rawBounds! as Map).cast<String, Object?>();
    expect(bounds['width'], 800.0);
    expect(bounds['height'], 600.0);

    expect((inventory['views']! as List).length, 1);
    final rawView = (inventory['views']! as List).single;
    expect(rawView, isA<Map<String, dynamic>>());
    final view = (rawView! as Map).cast<String, Object?>();
    expect(view['viewId'], 7);
    expect(view['identityId'], 'iid');
    expect(view['windowId'], 7);
    expect(view['hasKeyboardFocus'], isFalse);

    // Every nested map is string-keyed, which is what jsonEncode requires.
    expect(_allStringKeys(inventory), isTrue);
    final encoded = jsonEncode(inventory);
    expect(jsonDecode(encoded), equals(inventory));
    await sub.cancel();
  });

  test('windowInventory propagates a native PlatformException', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'windowInventory') {
        throw PlatformException(code: 'inventory_failed', message: 'sample');
      }
      return null;
    });

    await expectLater(
      adapter.windowInventory(),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'inventory_failed',
        ),
      ),
    );
  });

  test(
    'windowInventory rejects a null or list response with '
    'window_inventory_failed instead of reporting an empty inventory',
    () async {
      Object? response;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'windowInventory') return response;
        return null;
      });

      for (final raw in <Object?>[
        null,
        <Object?>['not', 'a', 'map'],
      ]) {
        response = raw;
        await expectLater(
          adapter.windowInventory(),
          throwsA(
            isA<PlatformException>()
                .having((e) => e.code, 'code', 'window_inventory_failed')
                .having((e) => e.message, 'message', isNull),
          ),
          reason: 'native response $raw must fail, not become {}',
        );
      }
    },
  );
}

/// Recursively asserts every map reachable from [value] has String keys.
bool _allStringKeys(Object? value) {
  if (value is Map) {
    return value.keys.every((k) => k is String) &&
        value.values.every(_allStringKeys);
  }
  if (value is List) {
    return value.every(_allStringKeys);
  }
  return true;
}

/// Delivers a native `stateChanged` event through the event channel, the same
/// envelope the real plugin's eventSink produces.
Future<void> _emitNativeStateChanged(
  String identityId,
  String state, {
  int? viewId,
}) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  await messenger.handlePlatformMessage(
    'profiled_webview_events',
    const StandardMethodCodec().encodeSuccessEnvelope(<String, dynamic>{
      'event': 'stateChanged',
      'identityId': identityId,
      'state': state,
      'viewId': ?viewId,
    }),
    (_) {},
  );
}

NativeBounds _bounds() => const NativeBounds(0, 0, 800, 600);
