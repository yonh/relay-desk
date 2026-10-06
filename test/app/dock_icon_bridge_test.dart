import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_desk/app/icon_settings.dart';
import 'package:relay_desk/app/localization.dart';
import 'package:relay_desk/features/common/dock_icon_bridge.dart';
import 'package:relay_desk/features/common/settings_dialog.dart';

import '../test_app.dart';

class RecordingNativeIcon implements NativeAppIcon {
  final applied = <AppIconChoice>[];
  bool fail = false;
  @override
  Future<void> apply(AppIconChoice icon) async {
    if (fail) throw PlatformException(code: 'native_failure');
    applied.add(icon);
  }
}

Future<Object?> selectFromDock(String id) async {
  const codec = StandardMethodCodec();
  final reply = Completer<ByteData?>();
  ServicesBinding.instance.channelBuffers.push(
    PlatformAppIcon.channel.name,
    codec.encodeMethodCall(MethodCall('selectIcon', {'id': id})),
    reply.complete,
  );
  return codec.decodeEnvelope((await reply.future)!);
}

void main() {
  testWidgets(
    'Dock choices share settings, persist, reject unknown IDs and follow language',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final storage = MemoryIconStorage();
      final native = RecordingNativeIcon();
      final container = ProviderContainer(
        overrides: [
          iconStorageProvider.overrideWithValue(storage),
          nativeAppIconProvider.overrideWithValue(native),
        ],
      );
      addTearDown(container.dispose);
      final configurations = <Map>[];
      var configured = Completer<void>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        PlatformAppIcon.channel,
        (call) async {
          if (call.method == 'configureDockMenu') {
            configurations.add(call.arguments as Map);
            if (!configured.isCompleted) configured.complete();
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          PlatformAppIcon.channel,
          null,
        ),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const LocalizedTestApp(home: DockIconBridge(child: AppLogo())),
        ),
      );
      await tester.runAsync(
        () => configured.future.timeout(const Duration(seconds: 10)),
      );
      expect(configurations.last['title'], 'Switch Icon');
      final choices = configurations.last['choices'] as List;
      expect(choices.map((choice) => (choice as Map)['id']), [
        'A1',
        'A2',
        'B1',
        'B2',
        'C1',
        'C3',
      ]);
      expect(
        choices.every((choice) => (choice as Map)['png'] is Uint8List),
        isTrue,
      );

      expect(await selectFromDock('A2'), isTrue);
      await tester.pumpAndSettle();
      expect(storage.value, AppIconChoice.a2);
      expect(native.applied, [AppIconChoice.a2]);
      expect(find.byKey(const ValueKey('app-logo-A2')), findsOneWidget);
      expect(await selectFromDock('invalid'), isFalse);
      expect(storage.value, AppIconChoice.a2);

      native.fail = true;
      expect(await selectFromDock('C3'), isFalse);
      expect(storage.value, AppIconChoice.a2);
      native.fail = false;
      expect(await selectFromDock('B2'), isTrue);
      expect(storage.value, AppIconChoice.b2);

      configured = Completer<void>();
      container
          .read(localePreferenceProvider.notifier)
          .select(LocalePreference.simplifiedChinese);
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => configured.future.timeout(const Duration(seconds: 10)),
      );
      expect(configurations.last['title'], '切换图标');
      expect((configurations.last['choices'] as List)[1]['title'], 'A2 · 火星');
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
