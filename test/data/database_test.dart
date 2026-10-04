import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_desk/data/database/database.dart';
import 'package:relay_desk/data/repositories/project_repository.dart';
import 'package:relay_desk/data/repositories/workspace_repository.dart';
import 'package:relay_desk/core/platform/domain.dart';
import 'package:uuid/uuid.dart';

void main() {
  late RelayDatabase db;
  late ProjectRepository projectRepo;
  late IdentityRepository identityRepo;
  late WorkspaceRepository workspaceRepo;

  setUp(() {
    db = RelayDatabase(NativeDatabase.memory());
    projectRepo = ProjectRepository(db, const Uuid());
    identityRepo = IdentityRepository(db, const Uuid());
    workspaceRepo = WorkspaceRepository(db, const Uuid());
  });

  tearDown(() => db.close());

  test('project CRUD and identity cascade', () async {
    final project = await projectRepo.create(
      name: 'Test',
      targetUrl: 'https://example.com',
    );
    expect(project.name, 'Test');
    expect(project.id, isNotEmpty);

    final fetched = await projectRepo.getById(project.id);
    expect(fetched?.name, 'Test');

    final updated = await projectRepo.update(project.copyWith(name: 'Updated'));
    expect(updated.name, 'Updated');

    final all = await projectRepo.getAll();
    expect(all, hasLength(1));

    // Identity
    final identity = await identityRepo.create(
      projectId: project.id,
      name: 'Alpha',
      color: '#FF0000',
      isolationMode: IsolationMode.nativeProfile,
    );
    expect(identity.name, 'Alpha');
    expect(identity.isolationMode, IsolationMode.nativeProfile);

    final identities = await identityRepo.getByProject(project.id);
    expect(identities, hasLength(1));

    // Cascade delete
    await projectRepo.delete(project.id);
    final afterDelete = await identityRepo.getByProject(project.id);
    expect(afterDelete, isEmpty);
  });

  test('identity name unique within project', () async {
    final project = await projectRepo.create(
      name: 'P',
      targetUrl: 'https://example.com',
    );
    await identityRepo.create(
      projectId: project.id,
      name: 'Alpha',
      color: '#FF0000',
      isolationMode: IsolationMode.nativeProfile,
    );
    expect(
      () => identityRepo.create(
        projectId: project.id,
        name: 'Alpha',
        color: '#00FF00',
        isolationMode: IsolationMode.nativeProfile,
      ),
      throwsA(isA<Object>()),
    );
  });

  test('workspace save/load with panels in single transaction', () async {
    final project = await projectRepo.create(
      name: 'P',
      targetUrl: 'https://example.com',
    );
    final id1 = await identityRepo.create(
      projectId: project.id,
      name: 'A',
      color: '#FF0000',
      isolationMode: IsolationMode.nativeProfile,
    );
    final id2 = await identityRepo.create(
      projectId: project.id,
      name: 'B',
      color: '#00FF00',
      isolationMode: IsolationMode.nativeProfile,
    );

    final wsId = workspaceRepo.generateId();
    final workspace = WorkspaceLayout(
      id: wsId,
      projectId: project.id,
      name: 'Default',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      panels: [
        PanelLayout(identityId: id1.id, x: 0, y: 0, width: 400, height: 300),
        PanelLayout(identityId: id2.id, x: 400, y: 0, width: 400, height: 300),
      ],
    );

    final saved = await workspaceRepo.save(workspace);
    expect(saved.panels, hasLength(2));
    expect(saved.name, 'Default');

    final loaded = await workspaceRepo.getById(wsId);
    expect(loaded?.panels, hasLength(2));

    final byProject = await workspaceRepo.getByProject(project.id);
    expect(byProject, hasLength(1));
  });

  test('workspace rejects foreign identity atomically', () async {
    final project1 = await projectRepo.create(
      name: 'P1',
      targetUrl: 'https://a.com',
    );
    final project2 = await projectRepo.create(
      name: 'P2',
      targetUrl: 'https://b.com',
    );
    final identityInP2 = await identityRepo.create(
      projectId: project2.id,
      name: 'X',
      color: '#FF0000',
      isolationMode: IsolationMode.nativeProfile,
    );

    final wsId = workspaceRepo.generateId();
    expect(
      () => workspaceRepo.save(
        WorkspaceLayout(
          id: wsId,
          projectId: project1.id,
          name: 'Bad',
          updatedAt: 0,
          panels: [PanelLayout(identityId: identityInP2.id)],
        ),
      ),
      throwsA(isA<StateError>()),
    );

    // Workspace should not exist after rollback.
    final after = await workspaceRepo.getById(wsId);
    expect(after, isNull);
  });

  test('foreign keys are enabled', () async {
    final result = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(result.read<int>('foreign_keys'), 1);
  });
}
