/// Unit tests for the device-emulation preset catalog
/// (lib/data/device_presets.dart). The catalog is a verbatim port of the
/// Tauri baseline `src/data/devices.ts` — ids, UA strings, viewport sizes and
/// the mobile/touch flags must stay aligned, since persisted identities refer
/// to presets by id.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:relay_desk/data/device_presets.dart';

void main() {
  test('catalog contains the three baseline presets verbatim', () {
    expect(devicePresets.map((p) => p.id), [
      'iphone-15',
      'pixel-9',
      'desktop-1920',
    ]);
  });

  test('iphone-15 preset carries the mobile Safari surface', () {
    final p = devicePresetFor('iphone-15')!;
    expect(p.name, 'iPhone 15');
    expect(p.mobile, isTrue);
    expect(p.touch, isTrue);
    expect(p.viewportWidth, 393);
    expect(p.viewportHeight, 852);
    expect(p.scaleFactor, 3);
    expect(p.userAgent, contains('iPhone'));
    expect(p.userAgent, contains('Mobile/15E148'));
  });

  test('pixel-9 preset carries the Android Chrome surface', () {
    final p = devicePresetFor('pixel-9')!;
    expect(p.name, 'Pixel 9');
    expect(p.mobile, isTrue);
    expect(p.touch, isTrue);
    expect(p.viewportWidth, 412);
    expect(p.viewportHeight, 915);
    expect(p.userAgent, contains('Android 14'));
    expect(p.userAgent, contains('Pixel 9'));
  });

  test('desktop preset has no UA override (WKWebView default)', () {
    final p = devicePresetFor('desktop-1920')!;
    expect(p.mobile, isFalse);
    expect(p.touch, isFalse);
    expect(p.userAgent, isNull);
  });

  test('devicePresetFor resolves only known ids; unknown/null -> null', () {
    expect(devicePresetFor('iphone-15'), isNotNull);
    expect(devicePresetFor('bogus'), isNull);
    expect(devicePresetFor(''), isNull);
    expect(devicePresetFor(null), isNull);
  });

  test('effectiveDevicePreset normalizes unknown/absent ids to desktop', () {
    expect(effectiveDevicePreset('iphone-15').id, 'iphone-15');
    expect(effectiveDevicePreset('bogus').id, kDefaultDevicePresetId);
    expect(effectiveDevicePreset(null).id, kDefaultDevicePresetId);
    expect(effectiveDevicePreset('').id, kDefaultDevicePresetId);
  });

  test('isValidDevicePresetId matches the baseline validation rule', () {
    expect(isValidDevicePresetId('iphone-15'), isTrue);
    expect(isValidDevicePresetId('a_b-C9'), isTrue);
    expect(isValidDevicePresetId('with space'), isFalse);
    expect(isValidDevicePresetId('with/slash'), isFalse);
    expect(isValidDevicePresetId('with:colon'), isFalse);
    expect(isValidDevicePresetId(''), isFalse);
    expect(isValidDevicePresetId('a' * 64), isTrue);
    expect(isValidDevicePresetId('a' * 65), isFalse);
  });
}
