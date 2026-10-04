/// Tests for MacosProfiledWebviewAdapter against a mocked `profiled_webview`
/// MethodChannel. Covers the stale-close race from .scratch/shared-session
/// issue 02: an async close issued for the OLD view must not drop the mapping
/// or report `closed` once a new view has been registered for the identity.
library;

import 'dart:async';

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
