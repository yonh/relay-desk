/// User-defined window-size presets — CRUD over the `custom_device_presets`
/// table, mapped to the `DevicePreset` domain shape the workspace consumes.
library;

import 'package:drift/drift.dart';

import '../database/database.dart';
import '../device_presets.dart';

class DevicePresetRepository {
  final RelayDatabase _db;
  DevicePresetRepository(this._db);

  /// All user-defined presets, oldest first (stable menu ordering).
  Future<List<DevicePreset>> listCustom() async {
    final rows = await (_db.select(
      _db.customDevicePresets,
    )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
    return [
      for (final r in rows)
        customSizePreset(
          id: r.id,
          name: r.name,
          width: r.width,
          height: r.height,
        ),
    ];
  }

  /// Adds a user-defined fixed-size preset. `id` must satisfy
  /// `isValidDevicePresetId` — generated as `user-<timestamp>` by callers.
  Future<void> addCustom({
    required String id,
    required String name,
    required int width,
    required int height,
  }) async {
    await _db
        .into(_db.customDevicePresets)
        .insert(
          CustomDevicePresetsCompanion.insert(
            id: id,
            name: name,
            width: width,
            height: height,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  Future<void> removeCustom(String id) =>
      (_db.delete(_db.customDevicePresets)..where((t) => t.id.equals(id))).go();
}
