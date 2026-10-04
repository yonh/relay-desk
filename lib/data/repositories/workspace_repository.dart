/// Workspace layout repository with single-transaction panel save.
library;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../../core/platform/domain.dart';

class WorkspaceRepository {
  final RelayDatabase _db;
  final Uuid _uuid;

  WorkspaceRepository(this._db, [Uuid? uuid]) : _uuid = uuid ?? const Uuid();

  Future<List<WorkspaceLayout>> getByProject(String projectId) async {
    final wsRows = await (_db.select(
      _db.savedWorkspaces,
    )..where((t) => t.projectId.equals(projectId))).get();
    final result = <WorkspaceLayout>[];
    for (final ws in wsRows) {
      final panels = await (_db.select(
        _db.savedPanelLayouts,
      )..where((t) => t.workspaceId.equals(ws.id))).get();
      result.add(_toDomain(ws, panels));
    }
    return result;
  }

  Future<WorkspaceLayout?> getById(String id) async {
    final ws = await (_db.select(
      _db.savedWorkspaces,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (ws == null) return null;
    final panels = await (_db.select(
      _db.savedPanelLayouts,
    )..where((t) => t.workspaceId.equals(id))).get();
    return _toDomain(ws, panels);
  }

  /// Save or update a workspace and its panels in a single transaction.
  /// All panels must belong to the same project; this is verified atomically.
  Future<WorkspaceLayout> save(WorkspaceLayout workspace) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.savedWorkspaces,
      )..where((t) => t.id.equals(workspace.id))).getSingleOrNull();
      if (existing == null) {
        await _db
            .into(_db.savedWorkspaces)
            .insert(
              SavedWorkspacesCompanion.insert(
                id: workspace.id,
                projectId: workspace.projectId,
                name: workspace.name,
                viewportX: Value(workspace.viewportX),
                viewportY: Value(workspace.viewportY),
                zoom: Value(workspace.zoom),
                layoutMode: Value(workspace.layoutMode.name),
                updatedAt: now,
              ),
            );
      } else {
        await (_db.update(
          _db.savedWorkspaces,
        )..where((t) => t.id.equals(workspace.id))).write(
          SavedWorkspacesCompanion(
            name: Value(workspace.name),
            viewportX: Value(workspace.viewportX),
            viewportY: Value(workspace.viewportY),
            zoom: Value(workspace.zoom),
            layoutMode: Value(workspace.layoutMode.name),
            updatedAt: Value(now),
          ),
        );
        // Delete existing panels before re-inserting.
        await (_db.delete(
          _db.savedPanelLayouts,
        )..where((t) => t.workspaceId.equals(workspace.id))).go();
      }
      // Verify all panels belong to identities in this project.
      for (final panel in workspace.panels) {
        final identity = await (_db.select(
          _db.identities,
        )..where((t) => t.id.equals(panel.identityId))).getSingleOrNull();
        if (identity == null || identity.projectId != workspace.projectId) {
          throw StateError(
            'panel identity ${panel.identityId} does not belong to project ${workspace.projectId}',
          );
        }
        await _db
            .into(_db.savedPanelLayouts)
            .insert(
              SavedPanelLayoutsCompanion.insert(
                workspaceId: workspace.id,
                identityId: panel.identityId,
                x: panel.x,
                y: panel.y,
                width: panel.width,
                height: panel.height,
                zIndex: Value(panel.zIndex),
                minimized: Value(panel.minimized),
                detached: Value(panel.detached),
              ),
            );
      }
    });
    return (await getById(workspace.id))!;
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.savedWorkspaces)..where((t) => t.id.equals(id))).go();
  }

  String generateId() => _uuid.v4();

  WorkspaceLayout _toDomain(WorkspaceRow ws, List<PanelRow> panels) =>
      WorkspaceLayout(
        id: ws.id,
        projectId: ws.projectId,
        name: ws.name,
        viewportX: ws.viewportX,
        viewportY: ws.viewportY,
        zoom: ws.zoom,
        layoutMode: LayoutMode.values.byName(ws.layoutMode),
        updatedAt: ws.updatedAt,
        panels: panels
            .map(
              (p) => PanelLayout(
                identityId: p.identityId,
                x: p.x,
                y: p.y,
                width: p.width,
                height: p.height,
                zIndex: p.zIndex,
                minimized: p.minimized,
                detached: p.detached,
              ),
            )
            .toList(),
      );
}
