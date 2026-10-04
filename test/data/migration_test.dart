/// Real file-based Tauri -> Flutter migration tests (E-IMPL-MIGRATION).
///
/// These tests back up a real on-disk SQLite source, migrate it into a real
/// on-disk target, and assert idempotency by re-running. They do NOT skip —
/// the backup file is verified to exist on disk and to be byte-identical to
/// the source, satisfying the "真实文件备份与幂等迁移 integration test，不得
/// skip" requirement in REQUIRED.md D2.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:relay_desk/data/database/database.dart';
import 'package:relay_desk/data/database/migration.dart';
import 'package:relay_desk/data/repositories/project_repository.dart';
import 'package:relay_desk/core/platform/domain.dart';
import 'package:uuid/uuid.dart';

void main() {
  late Directory tempDir;
  late String sourceDbPath;
  late String targetDbPath;
  late RelayDatabase source;
  late RelayDatabase target;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('relay_migration_test_');
    sourceDbPath = p.join(tempDir.path, 'tauri_source.db');
    targetDbPath = p.join(tempDir.path, 'flutter_target.db');
    source = RelayDatabase(NativeDatabase(File(sourceDbPath)));
  });

  // tearDown tolerates: a test that closes `source` early (double close), and a
  // test that never opens `target` (LateInitializationError on access). Both
  // are caught so the temp dir is still cleaned up.
  tearDown(() async {
    try {
      await source.close();
    } catch (_) {}
    try {
      await target.close();
    } catch (_) {}
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'backupTauriDatabase copies the source file to a real backup file',
    () async {
      // Seed a real source DB with one project + one identity.
      final projectRepo = ProjectRepository(source, const Uuid());
      final identityRepo = IdentityRepository(source, const Uuid());
      final project = await projectRepo.create(
        name: 'Tauri Project',
        targetUrl: 'https://tauri.app',
      );
      await identityRepo.create(
        projectId: project.id,
        name: 'Alpha',
        color: '#FF0000',
        isolationMode: IsolationMode.sharedSession,
      );
      await source.close();

      final backupDir = p.join(tempDir.path, 'backups');
      final backupPath = await TauriMigration.backupTauriDatabase(
        sourceDbPath,
        backupDir: backupDir,
      );

      // The backup file must exist on disk and be byte-identical to the source.
      expect(await File(backupPath).exists(), isTrue);
      final sourceBytes = await File(sourceDbPath).readAsBytes();
      final backupBytes = await File(backupPath).readAsBytes();
      expect(backupBytes, sourceBytes);
      // The backup must live under the requested backup dir.
      expect(p.isWithin(backupDir, backupPath), isTrue);
    },
  );

  test('backupTauriDatabase fails when the source does not exist', () async {
    final missing = p.join(tempDir.path, 'does_not_exist.db');
    expect(
      () => TauriMigration.backupTauriDatabase(
        missing,
        backupDir: p.join(tempDir.path, 'backups'),
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'migrateFromTauri copies projects+identities into a real target DB and is idempotent on re-run',
    () async {
      // Seed the real source DB.
      final projectRepo = ProjectRepository(source, const Uuid());
      final identityRepo = IdentityRepository(source, const Uuid());
      final project = await projectRepo.create(
        name: 'Tauri Project',
        targetUrl: 'https://tauri.app',
        allowPrivateNetwork: true,
      );
      final identityA = await identityRepo.create(
        projectId: project.id,
        name: 'Alpha',
        color: '#FF0000',
        isolationMode: IsolationMode.nativeProfile,
        startPath: '/admin',
      );
      final identityB = await identityRepo.create(
        projectId: project.id,
        name: 'Bravo',
        color: '#00FF00',
        isolationMode: IsolationMode.sharedSession,
      );
      // Touch the handles so the analyzer does not flag them unused; their
      // field values are re-verified after migration below.
      expect(identityA.startPath, '/admin');
      expect(identityB.isolationMode, IsolationMode.sharedSession);
      // Flush + close so the source file is a stable on-disk DB.
      await source.close();

      // Reopen the source read-only-ish (drift opens it again for migration).
      target = RelayDatabase(NativeDatabase(File(targetDbPath)));
      // First ensure the target schema exists.
      await target.customSelect('SELECT 1').get();

      // Back up first (real file copy).
      final backupPath = await TauriMigration.backupTauriDatabase(
        sourceDbPath,
        backupDir: p.join(tempDir.path, 'backups'),
      );
      expect(await File(backupPath).exists(), isTrue);

      // Migrate.
      final migrated = await TauriMigration.migrateFromTauri(
        tauriDbPath: sourceDbPath,
        target: target,
      );
      expect(migrated, 1);

      // Verify target has the project and both identities with field fidelity.
      final targetProjectRepo = ProjectRepository(target, const Uuid());
      final targetIdentityRepo = IdentityRepository(target, const Uuid());
      final projects = await targetProjectRepo.getAll();
      expect(projects, hasLength(1));
      expect(projects.first.name, 'Tauri Project');
      expect(projects.first.targetUrl, 'https://tauri.app');
      expect(projects.first.allowPrivateNetwork, isTrue);

      final identities = await targetIdentityRepo.getByProject(
        projects.first.id,
      );
      expect(identities, hasLength(2));
      final a = identities.firstWhere((i) => i.name == 'Alpha');
      expect(a.isolationMode, IsolationMode.nativeProfile);
      expect(a.startPath, '/admin');
      expect(a.color, '#FF0000');
      final b = identities.firstWhere((i) => i.name == 'Bravo');
      expect(b.isolationMode, IsolationMode.sharedSession);

      // Re-run migration: idempotent (no duplicate rows, returns 0 new projects).
      final migratedAgain = await TauriMigration.migrateFromTauri(
        tauriDbPath: sourceDbPath,
        target: target,
      );
      expect(migratedAgain, 0);
      final projectsAfterRerun = await targetProjectRepo.getAll();
      expect(projectsAfterRerun, hasLength(1));
      final identitiesAfterRerun = await targetIdentityRepo.getByProject(
        projectsAfterRerun.first.id,
      );
      expect(identitiesAfterRerun, hasLength(2));

      // The backup file must still be intact after migration (not deleted).
      expect(await File(backupPath).exists(), isTrue);
    },
  );

  test(
    'migrateFromTauri is a no-op (idempotent) when target already has data',
    () async {
      final projectRepo = ProjectRepository(source, const Uuid());
      final identityRepo = IdentityRepository(source, const Uuid());
      final project = await projectRepo.create(
        name: 'Solo',
        targetUrl: 'https://solo.app',
      );
      await identityRepo.create(
        projectId: project.id,
        name: 'Only',
        color: '#0000FF',
        isolationMode: IsolationMode.nativeProfile,
      );
      await source.close();

      target = RelayDatabase(NativeDatabase(File(targetDbPath)));
      await TauriMigration.migrateFromTauri(
        tauriDbPath: sourceDbPath,
        target: target,
      );
      // Immediately re-run; the second pass must not duplicate.
      final second = await TauriMigration.migrateFromTauri(
        tauriDbPath: sourceDbPath,
        target: target,
      );
      expect(second, 0);
      final targetProjectRepo = ProjectRepository(target, const Uuid());
      final all = await targetProjectRepo.getAll();
      expect(all, hasLength(1));
    },
  );
}
