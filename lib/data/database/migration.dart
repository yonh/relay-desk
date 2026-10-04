/// Tauri SQLite migration strategy: backup before migration, idempotent.
///
/// The Tauri app stores its SQLite at a known path. Before the Flutter app
/// reads or migrates it, it creates a timestamped backup. Migration is
/// idempotent — running it twice produces the same result.
///
/// Browser profiles are NOT migrated across engines (per rewrite-plan §4.7).
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database.dart';

class TauriMigration {
  /// Creates a backup of the Tauri SQLite file before migration.
  /// Returns the backup file path.
  ///
  /// [backupDir] is optional: in production it defaults to
  /// `<app documents>/migrations/backups`; tests pass a temp directory so the
  /// backup is a real file copy on disk without path_provider.
  static Future<String> backupTauriDatabase(
    String tauriDbPath, {
    String? backupDir,
  }) async {
    final source = File(tauriDbPath);
    if (!await source.exists()) {
      throw FileSystemException('Tauri database not found', tauriDbPath);
    }
    final resolvedDir =
        backupDir ??
        p.join(
          (await getApplicationDocumentsDirectory()).path,
          'migrations',
          'backups',
        );
    await Directory(resolvedDir).create(recursive: true);
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final backupPath = p.join(resolvedDir, 'tauri-$timestamp.db');
    await source.copy(backupPath);
    return backupPath;
  }

  /// Checks if the Tauri database has the expected schema.
  /// Returns true if the database has the projects and identities tables.
  static Future<bool> isTauriSchema(String tauriDbPath) async {
    final file = File(tauriDbPath);
    if (!await file.exists()) return false;
    final db = RelayDatabase(NativeDatabase(file));
    try {
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('projects','identities')",
          )
          .get();
      return tables.length >= 2;
    } finally {
      await db.close();
    }
  }

  /// Migrates projects and identities from the Tauri database to the Flutter
  /// database. Idempotent: if a project with the same ID already exists, it
  /// is skipped.
  static Future<int> migrateFromTauri({
    required String tauriDbPath,
    required RelayDatabase target,
  }) async {
    final source = RelayDatabase(NativeDatabase(File(tauriDbPath)));
    var migrated = 0;
    try {
      final projects = await source.select(source.projects).get();
      for (final project in projects) {
        final existing = await (target.select(
          target.projects,
        )..where((t) => t.id.equals(project.id))).getSingleOrNull();
        if (existing != null) continue; // idempotent skip

        await target
            .into(target.projects)
            .insert(
              ProjectsCompanion.insert(
                id: project.id,
                name: project.name,
                targetUrl: project.targetUrl,
                allowPrivateNetwork: Value(project.allowPrivateNetwork),
                createdAt: project.createdAt,
                updatedAt: project.updatedAt,
              ),
            );
        migrated++;

        final identities = await (source.select(
          source.identities,
        )..where((t) => t.projectId.equals(project.id))).get();
        for (final id in identities) {
          final existingId = await (target.select(
            target.identities,
          )..where((t) => t.id.equals(id.id))).getSingleOrNull();
          if (existingId != null) continue;

          await target
              .into(target.identities)
              .insert(
                IdentitiesCompanion.insert(
                  id: id.id,
                  projectId: id.projectId,
                  name: id.name,
                  color: id.color,
                  isolationMode: id.isolationMode,
                  devicePresetId: Value(id.devicePresetId),
                  startPath: Value(id.startPath),
                ),
              );
        }
      }
    } finally {
      await source.close();
    }
    return migrated;
  }
}
