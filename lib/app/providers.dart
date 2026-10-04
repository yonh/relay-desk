/// Riverpod providers for the database, repositories, and management state.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../data/database/database.dart';
import '../data/repositories/project_repository.dart';
import '../data/repositories/workspace_repository.dart';
import '../core/platform/domain.dart';

/// Lazy singleton database provider.
final databaseProvider = FutureProvider<RelayDatabase>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, 'relay_desk.db'));
  final db = RelayDatabase(NativeDatabase(file));
  ref.onDispose(db.close);
  return db;
});

final projectRepositoryProvider = FutureProvider<ProjectRepository>((
  ref,
) async {
  final db = await ref.watch(databaseProvider.future);
  return ProjectRepository(db);
});

final identityRepositoryProvider = FutureProvider<IdentityRepository>((
  ref,
) async {
  final db = await ref.watch(databaseProvider.future);
  return IdentityRepository(db);
});

final workspaceRepositoryProvider = FutureProvider<WorkspaceRepository>((
  ref,
) async {
  final db = await ref.watch(databaseProvider.future);
  return WorkspaceRepository(db);
});

/// All projects list.
final projectsProvider = FutureProvider<List<Project>>((ref) async {
  final repo = await ref.watch(projectRepositoryProvider.future);
  return repo.getAll();
});

/// Identities for a project.
final identitiesProvider = FutureProvider.family<List<Identity>, String>((
  ref,
  projectId,
) async {
  final repo = await ref.watch(identityRepositoryProvider.future);
  return repo.getByProject(projectId);
});

/// Selected project id.
final selectedProjectIdProvider =
    NotifierProvider<SelectedProjectIdNotifier, String?>(
      SelectedProjectIdNotifier.new,
    );

class SelectedProjectIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

/// Selected project.
final selectedProjectProvider = FutureProvider<Project?>((ref) async {
  final id = ref.watch(selectedProjectIdProvider);
  if (id == null) return null;
  final repo = await ref.watch(projectRepositoryProvider.future);
  return repo.getById(id);
});

/// Workspaces for a project.
final workspacesProvider = FutureProvider.family<List<WorkspaceLayout>, String>(
  (ref, projectId) async {
    final repo = await ref.watch(workspaceRepositoryProvider.future);
    return repo.getByProject(projectId);
  },
);
