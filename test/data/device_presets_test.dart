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
    expect(
      devicePresets.map((p) => p.id),
      containsAllInOrder(['iphone-15', 'pixel-9', 'desktop-1920']),
    );
    expect(
      devicePresets.firstWhere((p) => p.id == 'iphone-15').sizing,
      ViewportSizing.widthOnly,
    );
    expect(
      devicePresets.firstWhere((p) => p.id == 'pixel-9').sizing,
      ViewportSizing.widthOnly,
    );
    expect(
      devicePresets.firstWhere((p) => p.id == 'desktop-1920').sizing,
      ViewportSizing.free,
    );
  });

  test('custom preset is free sizing with no overrides', () {
    final p = devicePresetFor(kCustomDevicePresetId)!;
    expect(p.sizing, ViewportSizing.free);
    expect(p.emulatedViewport, isFalse);
    expect(p.userAgent, isNull);
    expect(p.mobile, isFalse);
    expect(p.touch, isFalse);
  });

  test('fixed presets clamp both dims and stay well-formed', () {
    final fixed = devicePresets.where((p) => p.sizing == ViewportSizing.fixed);
    expect(fixed.length, 11);
    for (final p in fixed) {
      expect(p.emulatedViewport, isTrue, reason: p.id);
      expect(p.viewportWidth, greaterThan(0), reason: p.id);
      expect(p.viewportHeight, greaterThan(0), reason: p.id);
      expect(isValidDevicePresetId(p.id), isTrue, reason: p.id);
    }
    expect(
      fixed
          .firstWhere((p) => p.id == 'size-macbook-air-1280x832')
          .viewportWidth,
      1280,
    );
  });

  test('device-named fixed presets are full mobile/tablet emulation', () {
    // A preset named after a phone or tablet must serve the mobile site:
    // real device UA + touch surface + device DPR, with the viewport pinned
    // to the device's exact CSS resolution (fixed sizing).
    const deviceIds = {
      'size-iphone-se-320x568': ('iPhone', 2.0),
      'size-nexus-5-360x640': ('Nexus 5', 3.0),
      'size-iphone-8-375x667': ('iPhone', 2.0),
      'size-iphone-14-390x844': ('iPhone', 3.0),
      'size-iphone-11-414x896': ('iPhone', 2.0),
      'size-iphone-14-pro-max-430x932': ('iPhone', 3.0),
      'size-ipad-mini-768x1024': ('iPad', 2.0),
    };
    for (final entry in deviceIds.entries) {
      final p = devicePresetFor(entry.key)!;
      expect(p.mobile, isTrue, reason: p.id);
      expect(p.touch, isTrue, reason: p.id);
      expect(p.userAgent, contains(entry.value.$1), reason: p.id);
      expect(p.scaleFactor, entry.value.$2, reason: p.id);
    }
    final iphone14 = devicePresetFor('size-iphone-14-390x844')!;
    expect(iphone14.userAgent, contains('Mobile/15E148'));
    final nexus5 = devicePresetFor('size-nexus-5-360x640')!;
    expect(nexus5.userAgent, contains('Android'));
    expect(nexus5.userAgent, contains('Mobile Safari'));
  });

  test('generic fixed presets stay pure window sizes (desktop UA)', () {
    // Widget/Desktop/MacBook form factors ARE desktop surfaces — no UA
    // spoofing or touch injection.
    const pureSizeIds = [
      'size-widget-320x400',
      'size-desktop-mini-640x500',
      'size-desktop-1024x768',
      'size-macbook-air-1280x832',
    ];
    for (final id in pureSizeIds) {
      final p = devicePresetFor(id)!;
      expect(p.sizing, ViewportSizing.fixed, reason: id);
      expect(p.userAgent, isNull, reason: id);
      expect(p.mobile, isFalse, reason: id);
      expect(p.touch, isFalse, reason: id);
    }
  });

  test('all preset ids are unique and well-formed', () {
    final ids = devicePresets.map((p) => p.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final id in ids) {
      expect(isValidDevicePresetId(id), isTrue, reason: id);
    }
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

  test('devicePresetFor resolves user-defined sizes before the catalog', () {
    final custom = customSizePreset(
      id: 'user-1',
      name: 'My Kiosk',
      width: 480,
      height: 800,
    );
    expect(devicePresetFor('user-1'), isNull);
    expect(devicePresetFor('user-1', [custom]), same(custom));
    // Catalog ids still resolve with a custom list present.
    expect(devicePresetFor('iphone-15', [custom])?.id, 'iphone-15');
    // Custom presets are fixed-sizing window sizes, never UA overrides.
    expect(custom.sizing, ViewportSizing.fixed);
    expect(custom.userAgent, isNull);
    expect(custom.touch, isFalse);
    expect(effectiveDevicePreset('user-1', [custom]).name, 'My Kiosk');
    expect(
      effectiveDevicePreset('user-gone', [custom]).id,
      kDefaultDevicePresetId,
    );
  });
}
