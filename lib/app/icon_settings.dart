import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppIconChoice {
  a1('A1'),
  a2('A2'),
  b1('B1'),
  b2('B2'),
  c1('C1'),
  c3('C3');

  const AppIconChoice(this.id);
  final String id;
  String get assetPath => 'assets/logos/$id.png';
  static AppIconChoice parse(String? value) =>
      values.firstWhere((icon) => icon.id == value, orElse: () => b2);
}

abstract class IconStorage {
  AppIconChoice read();
  Future<void> write(AppIconChoice icon);
}

class SharedPreferencesIconStorage implements IconStorage {
  SharedPreferencesIconStorage(this.preferences);
  static const key = 'app.icon';
  final SharedPreferences preferences;
  @override
  AppIconChoice read() {
    try {
      return AppIconChoice.parse(preferences.getString(key));
    } catch (_) {
      return AppIconChoice.b2;
    }
  }

  @override
  Future<void> write(AppIconChoice icon) async {
    if (!await preferences.setString(key, icon.id)) {
      throw StateError('Unable to save icon preference');
    }
  }
}

class MemoryIconStorage implements IconStorage {
  MemoryIconStorage([this.value = AppIconChoice.b2]);
  AppIconChoice value;
  @override
  AppIconChoice read() => value;
  @override
  Future<void> write(AppIconChoice icon) async {
    value = icon;
  }
}

abstract class NativeAppIcon {
  Future<void> apply(AppIconChoice icon);
}

class PlatformAppIcon implements NativeAppIcon {
  static const channel = MethodChannel('relay_desk/app_icon');
  @override
  Future<void> apply(AppIconChoice icon) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    final data = await rootBundle.load(icon.assetPath);
    await channel.invokeMethod<void>('setIcon', {
      'id': icon.id,
      'png': data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    });
  }
}

final iconStorageProvider = Provider<IconStorage>((ref) => MemoryIconStorage());
final nativeAppIconProvider = Provider<NativeAppIcon>(
  (ref) => PlatformAppIcon(),
);

class IconSettings {
  const IconSettings(this.icon, {this.saving = false, this.failed = false});
  final AppIconChoice icon;
  final bool saving;
  final bool failed;
}

final iconSettingsProvider =
    NotifierProvider<IconSettingsController, IconSettings>(
      IconSettingsController.new,
    );

class IconSettingsController extends Notifier<IconSettings> {
  @override
  IconSettings build() {
    try {
      return IconSettings(ref.read(iconStorageProvider).read());
    } catch (_) {
      return const IconSettings(AppIconChoice.b2);
    }
  }

  Future<void> select(AppIconChoice icon) async {
    if (state.saving || icon == state.icon) return;
    final previous = state.icon;
    final native = ref.read(nativeAppIconProvider);
    final storage = ref.read(iconStorageProvider);
    state = IconSettings(previous, saving: true);
    try {
      await native.apply(icon);
      await storage.write(icon);
      state = IconSettings(icon);
    } catch (_) {
      // Restore the Dock if persistence failed after the native icon changed.
      try {
        await native.apply(previous);
      } catch (_) {}
      state = IconSettings(previous, failed: true);
    }
  }
}
