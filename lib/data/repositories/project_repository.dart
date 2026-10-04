/// Project and Identity repositories using drift.
library;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../../core/platform/domain.dart';

class ProjectRepository {
  final RelayDatabase _db;
  final Uuid _uuid;

  ProjectRepository(this._db, [Uuid? uuid]) : _uuid = uuid ?? const Uuid();

  Future<List<Project>> getAll() async {
    final rows = await _db.select(_db.projects).get();
    return rows.map(_toDomain).toList();
  }

  Future<Project?> getById(String id) async {
    final row = await (_db.select(
      _db.projects,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row != null ? _toDomain(row) : null;
  }

  Future<Project> create({
    required String name,
    required String targetUrl,
    bool allowPrivateNetwork = false,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _uuid.v4();
    await _db
        .into(_db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: id,
            name: name,
            targetUrl: targetUrl,
            allowPrivateNetwork: Value(allowPrivateNetwork),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await getById(id))!;
  }

  Future<Project> update(Project project) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(
      _db.projects,
    )..where((t) => t.id.equals(project.id))).write(
      ProjectsCompanion(
        name: Value(project.name),
        targetUrl: Value(project.targetUrl),
        allowPrivateNetwork: Value(project.allowPrivateNetwork),
        defaultLayoutMode: Value(project.defaultLayoutMode.dbValue),
        updatedAt: Value(now),
      ),
    );
    return (await getById(project.id))!;
  }

  /// Update only the project's default layout preference, bumping `updatedAt`.
  /// Used by the workspace controller when the user changes the layout mode so
  /// the choice persists across switch-away/switch-back and app restarts.
  Future<Project> updateDefaultLayoutMode(
    String projectId,
    LayoutMode mode,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(
      _db.projects,
    )..where((t) => t.id.equals(projectId))).write(
      ProjectsCompanion(
        defaultLayoutMode: Value(mode.dbValue),
        updatedAt: Value(now),
      ),
    );
    return (await getById(projectId))!;
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.projects)..where((t) => t.id.equals(id))).go();
  }

  Project _toDomain(ProjectRow r) => Project(
    id: r.id,
    name: r.name,
    targetUrl: r.targetUrl,
    allowPrivateNetwork: r.allowPrivateNetwork,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
    defaultLayoutMode: LayoutModeDb.fromDb(r.defaultLayoutMode),
  );
}

class IdentityRepository {
  final RelayDatabase _db;
  final Uuid _uuid;

  IdentityRepository(this._db, [Uuid? uuid]) : _uuid = uuid ?? const Uuid();

  Future<List<Identity>> getByProject(String projectId) async {
    final rows = await (_db.select(
      _db.identities,
    )..where((t) => t.projectId.equals(projectId))).get();
    return rows.map(_toDomain).toList();
  }

  Future<Identity?> getById(String id) async {
    final row = await (_db.select(
      _db.identities,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row != null ? _toDomain(row) : null;
  }

  Future<Identity> create({
    required String projectId,
    required String name,
    required String color,
    required IsolationMode isolationMode,
    String? devicePresetId,
    String startPath = '/',
    String? id,
  }) async {
    final identityId = id ?? _uuid.v4();
    await _db
        .into(_db.identities)
        .insert(
          IdentitiesCompanion.insert(
            id: identityId,
            projectId: projectId,
            name: name,
            color: color,
            isolationMode: isolationMode.dbValue,
            devicePresetId: Value(devicePresetId),
            startPath: Value(startPath),
          ),
        );
    return (await getById(identityId))!;
  }

  Future<Identity> update(Identity identity) async {
    await (_db.update(
      _db.identities,
    )..where((t) => t.id.equals(identity.id))).write(
      IdentitiesCompanion(
        name: Value(identity.name),
        color: Value(identity.color),
        isolationMode: Value(identity.isolationMode.dbValue),
        devicePresetId: Value(identity.devicePresetId),
        startPath: Value(identity.startPath),
      ),
    );
    return (await getById(identity.id))!;
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.identities)..where((t) => t.id.equals(id))).go();
  }

  Identity _toDomain(IdentityRow r) => Identity(
    id: r.id,
    projectId: r.projectId,
    name: r.name,
    color: r.color,
    isolationMode: IsolationMode.fromDb(r.isolationMode),
    devicePresetId: r.devicePresetId,
    startPath: r.startPath,
  );
}
