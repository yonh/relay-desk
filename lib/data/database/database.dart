/// drift database schema, field-compatible with the Tauri SQLite migrations.
/// See src-tauri/migrations/0001_initial.sql and 0002_saved_workspaces.sql.
library;

// ignore_for_file: recursive_getters
// The drift check constraint idiom `x.isBiggerOrEqualValue(0)` references the
// column getter `x`, which the analyzer flags as recursive. This is a
// false positive — drift's DSL uses the column getter to build SQL expressions.

import 'package:drift/drift.dart';

part 'database.g.dart';

@DataClassName('ProjectRow')
class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get targetUrl => text()();
  BoolColumn get allowPrivateNetwork =>
      boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  // Per-project default layout mode (canvas/grid/columns/focus). New projects
  // inherit the global default `grid`; the user's last choice for a project is
  // persisted here so switching away and back (or restarting) restores it.
  TextColumn get defaultLayoutMode =>
      text().withDefault(const Constant('grid'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('IdentityRow')
class Identities extends Table {
  TextColumn get id => text()();
  TextColumn get projectId =>
      text().references(Projects, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get color => text()();
  TextColumn get isolationMode => text()();
  TextColumn get devicePresetId => text().nullable()();
  TextColumn get startPath => text().withDefault(const Constant('/'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {projectId, name},
  ];
}

@DataClassName('WorkspaceRow')
class SavedWorkspaces extends Table {
  TextColumn get id => text()();
  TextColumn get projectId =>
      text().references(Projects, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  RealColumn get viewportX => real().withDefault(const Constant(0))();
  RealColumn get viewportY => real().withDefault(const Constant(0))();
  RealColumn get zoom => real().withDefault(const Constant(1))();
  TextColumn get layoutMode => text().withDefault(const Constant('canvas'))();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {projectId, name},
  ];
}

@DataClassName('PanelRow')
class SavedPanelLayouts extends Table {
  TextColumn get workspaceId =>
      text().references(SavedWorkspaces, #id, onDelete: KeyAction.cascade)();
  TextColumn get identityId =>
      text().references(Identities, #id, onDelete: KeyAction.cascade)();
  RealColumn get x => real().check(x.isBiggerOrEqualValue(0))();
  RealColumn get y => real().check(y.isBiggerOrEqualValue(0))();
  RealColumn get width => real().check(width.isBiggerOrEqualValue(320))();
  RealColumn get height => real().check(height.isBiggerOrEqualValue(240))();
  IntColumn get zIndex => integer().withDefault(const Constant(0))();
  BoolColumn get minimized => boolean().withDefault(const Constant(false))();
  BoolColumn get detached => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {workspaceId, identityId};
}

@DriftDatabase(
  tables: [Projects, Identities, SavedWorkspaces, SavedPanelLayouts],
)
class RelayDatabase extends _$RelayDatabase {
  RelayDatabase(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 1) {
        await m.createAll();
      }
      if (from < 2) {
        await m.createTable(savedWorkspaces);
        await m.createTable(savedPanelLayouts);
      }
      if (from < 3) {
        // Add the per-project default layout mode column. Existing rows
        // backfill to the global default `grid` via the column default.
        await m.addColumn(projects, projects.defaultLayoutMode);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
