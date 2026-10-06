import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_desk/app/icon_settings.dart';
import 'package:relay_desk/features/common/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_app.dart';

class FakeNativeIcon implements NativeAppIcon {
  final applied = <AppIconChoice>[];
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<void> apply(AppIconChoice icon) async {
    if (fail) throw PlatformException(code: 'test_failure');
    applied.add(icon);
    await gate?.future;
  }
}

class FailingStorage extends MemoryIconStorage {
  @override
  Future<void> write(AppIconChoice icon) async =>
      throw StateError('disk failure');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'icon selection keeps the dialog and cards stationary while saving and on failure',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final native = FakeNativeIcon()..gate = Completer<void>();
      final container = ProviderContainer(
        overrides: [nativeAppIconProvider.overrideWithValue(native)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const LocalizedTestApp(
            locale: Locale('en'),
            home: SettingsDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dialog = tester.getRect(find.byType(AlertDialog));
      final card = tester.getRect(find.byKey(const ValueKey('icon-option-A1')));
      final done = tester.getRect(find.widgetWithText(FilledButton, 'Done'));
      await tester.tap(find.byKey(const ValueKey('icon-option-A1')));
      await tester.pump();
      expect(container.read(iconSettingsProvider).saving, isTrue);
      expect(tester.getRect(find.byType(AlertDialog)), dialog);
      expect(
        tester.getRect(find.byKey(const ValueKey('icon-option-A1'))),
        card,
      );
      expect(tester.getRect(find.widgetWithText(FilledButton, 'Done')), done);
      native.gate!.complete();
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(AlertDialog)), dialog);
      expect(
        tester.getRect(find.byKey(const ValueKey('icon-option-A1'))),
        card,
      );
      native.fail = true;
      await tester.tap(find.byKey(const ValueKey('icon-option-C3')));
      await tester.pumpAndSettle();
      expect(container.read(iconSettingsProvider).failed, isTrue);
      expect(tester.getRect(find.byType(AlertDialog)), dialog);
      expect(
        tester.getRect(find.byKey(const ValueKey('icon-option-A1'))),
        card,
      );
      expect(tester.getRect(find.widgetWithText(FilledButton, 'Done')), done);
    },
  );

  test(
    'B2 is the default for missing, obsolete and corrupted preferences',
    () async {
      for (final value in [null, 'unknown', 42]) {
        SharedPreferences.setMockInitialValues({
          SharedPreferencesIconStorage.key: ?value,
        });
        final prefs = await SharedPreferences.getInstance();
        expect(SharedPreferencesIconStorage(prefs).read(), AppIconChoice.b2);
      }
    },
  );

  test('selection updates the Dock and survives a new controller', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = SharedPreferencesIconStorage(
      await SharedPreferences.getInstance(),
    );
    final native = FakeNativeIcon();
    final container = ProviderContainer(
      overrides: [
        iconStorageProvider.overrideWithValue(storage),
        nativeAppIconProvider.overrideWithValue(native),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(iconSettingsProvider.notifier)
        .select(AppIconChoice.c3);
    expect(native.applied, [AppIconChoice.c3]);
    final fresh = ProviderContainer(
      overrides: [iconStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(fresh.dispose);
    expect(fresh.read(iconSettingsProvider).icon, AppIconChoice.c3);
  });

  test(
    'failed save restores the previous native icon and exposes retry',
    () async {
      final native = FakeNativeIcon();
      final container = ProviderContainer(
        overrides: [
          iconStorageProvider.overrideWithValue(FailingStorage()),
          nativeAppIconProvider.overrideWithValue(native),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(iconSettingsProvider.notifier)
          .select(AppIconChoice.a1);
      expect(native.applied, [AppIconChoice.a1, AppIconChoice.b2]);
      expect(container.read(iconSettingsProvider).icon, AppIconChoice.b2);
      expect(container.read(iconSettingsProvider).failed, isTrue);
      expect(container.read(iconSettingsProvider).saving, isFalse);
    },
  );

  test(
    'native failure does not persist an unapplied icon; retry succeeds',
    () async {
      final native = FakeNativeIcon()..fail = true;
      final storage = MemoryIconStorage();
      final container = ProviderContainer(
        overrides: [
          iconStorageProvider.overrideWithValue(storage),
          nativeAppIconProvider.overrideWithValue(native),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(iconSettingsProvider.notifier)
          .select(AppIconChoice.a2);
      expect(storage.value, AppIconChoice.b2);
      native.fail = false;
      await container
          .read(iconSettingsProvider.notifier)
          .select(AppIconChoice.a2);
      expect(storage.value, AppIconChoice.a2);
      expect(container.read(iconSettingsProvider).failed, isFalse);
    },
  );

  test('concurrent taps cannot overtake an in-flight change', () async {
    final native = FakeNativeIcon()..gate = Completer<void>();
    final storage = MemoryIconStorage();
    final container = ProviderContainer(
      overrides: [
        iconStorageProvider.overrideWithValue(storage),
        nativeAppIconProvider.overrideWithValue(native),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(iconSettingsProvider.notifier);
    final pending = controller.select(AppIconChoice.a1);
    await controller.select(AppIconChoice.c1);
    native.gate!.complete();
    await pending;
    expect(storage.value, AppIconChoice.a1);
    expect(native.applied, [AppIconChoice.a1]);
  });

  test('macOS bridge sends a decodable transparent B2 PNG', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    Uint8List? png;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PlatformAppIcon.channel, (call) async {
          expect(call.method, 'setIcon');
          png = (call.arguments as Map)['png'] as Uint8List;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PlatformAppIcon.channel, null),
    );
    await PlatformAppIcon().apply(AppIconChoice.b2);
    final codec = await ui.instantiateImageCodec(png!);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1024);
    expect(frame.image.height, 1024);
    final rgba = await frame.image.toByteData();
    expect(rgba!.getUint8(3), 0);
    expect(rgba.getUint8((512 * 1024 + 512) * 4 + 3), 255);
    frame.image.dispose();
    codec.dispose();
  });

  testWidgets(
    'six options, live logo switch, default reset and compact layout',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final storage = MemoryIconStorage();
      final native = FakeNativeIcon();
      final container = ProviderContainer(
        overrides: [
          iconStorageProvider.overrideWithValue(storage),
          nativeAppIconProvider.overrideWithValue(native),
        ],
      );
      addTearDown(container.dispose);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: boundaryKey,
            child: LocalizedTestApp(
              locale: const Locale('zh'),
              home: Scaffold(
                body: Builder(
                  builder: (context) => Column(
                    children: [
                      const AppLogo(),
                      TextButton(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => const SettingsDialog(),
                        ),
                        child: const Text('open'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('app-logo-B2')), findsOneWidget);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (final icon in AppIconChoice.values) {
        expect(find.byKey(ValueKey('icon-option-${icon.id}')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('icon-option-A1')));
      await tester.pumpAndSettle();
      expect(storage.value, AppIconChoice.a1);
      expect(find.byKey(const ValueKey('app-logo-A1')), findsOneWidget);
      await tester.tap(find.text('恢复默认 B2'));
      await tester.pumpAndSettle();
      expect(storage.value, AppIconChoice.b2);
      await tester.binding.setSurfaceSize(const Size(360, 640));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('icon-option-C3')),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('icon-option-C3')));
      await tester.pumpAndSettle();
      expect(storage.value, AppIconChoice.c3);
      expect(tester.takeException(), isNull);
    },
  );
}
