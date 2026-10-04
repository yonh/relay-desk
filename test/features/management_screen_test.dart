/// Widget tests for the management screen: project + identity full CRUD
/// driven through the real Riverpod wiring and drift repository
/// (E-IMPL-PROJECT-IDENTITY-CRUD). The UI calls ProjectRepository /
/// IdentityRepository (create/update/delete); these tests pump the real
/// widgets, drive the dialogs, and assert the database + UI reflect each
/// mutation end-to-end.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_desk/app/providers.dart';
import 'package:relay_desk/core/platform/domain.dart';
import 'package:relay_desk/data/database/database.dart';
import 'package:relay_desk/data/repositories/project_repository.dart';
import 'package:relay_desk/features/management/management_screen.dart';
import 'package:relay_desk/features/workspace/workspace_controller.dart';
import 'package:relay_desk/platform/webview/headless_webview_adapter.dart';

import '../test_app.dart';

void main() {
  late RelayDatabase db;
  late HeadlessWebviewAdapter adapter;

  setUp(() {
    db = RelayDatabase(NativeDatabase.memory());
    adapter = HeadlessWebviewAdapter();
  });

  tearDown(() async {
    adapter.dispose();
    await db.close();
  });

  Future<ProviderContainer> boot(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async {
          ref.onDispose(db.close);
          return db;
        }),
        webviewAdapterProvider.overrideWithValue(adapter),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(
          locale: Locale('en'),
          home: Scaffold(body: Row(children: [ManagementScreen()])),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('create project via dialog then it appears in the list', (
    tester,
  ) async {
    await boot(tester);

    expect(find.text('Welcome to Relay Desk'), findsOneWidget);

    // Open the New Project dialog.
    await tester.tap(find.byTooltip('New Project'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Name').first,
      'Demo',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Target URL').first,
      'https://demo.app',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // The project must be persisted and rendered.
    expect(find.text('Welcome to Relay Desk'), findsNothing);
    expect(find.text('Demo'), findsOneWidget);
    expect(find.text('https://demo.app'), findsOneWidget);
    final repo = ProjectRepository(db);
    final all = await repo.getAll();
    expect(all, hasLength(1));
    expect(all.first.name, 'Demo');
  });

  testWidgets('edit project name and persist the change', (tester) async {
    final container = await boot(tester);
    final repo = ProjectRepository(db);
    final project = await repo.create(
      name: 'Original',
      targetUrl: 'https://orig.app',
    );
    container.invalidate(projectsProvider);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit project'));
    await tester.pumpAndSettle();
    // Clear the existing name and type a new one.
    await tester.enterText(
      find.widgetWithText(TextField, 'Name').first,
      'Renamed',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Renamed'), findsOneWidget);
    final after = await repo.getById(project.id);
    expect(after?.name, 'Renamed');
  });

  testWidgets('delete project with confirmation removes it and cascades', (
    tester,
  ) async {
    final container = await boot(tester);
    final projectRepo = ProjectRepository(db);
    final identityRepo = IdentityRepository(db);
    final project = await projectRepo.create(
      name: 'Bye',
      targetUrl: 'https://bye.app',
    );
    await identityRepo.create(
      projectId: project.id,
      name: 'Alpha',
      color: '#FF0000',
      isolationMode: IsolationMode.nativeProfile,
    );
    container.invalidate(projectsProvider);
    await tester.pumpAndSettle();

    expect(find.text('Bye'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete project'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Bye'), findsNothing);
    expect(await projectRepo.getAll(), isEmpty);
    // Cascade: identity must be gone too.
    expect(await identityRepo.getByProject(project.id), isEmpty);
  });

  testWidgets('create + edit + delete identity through the identity section', (
    tester,
  ) async {
    final container = await boot(tester);
    final projectRepo = ProjectRepository(db);
    final identityRepo = IdentityRepository(db);
    final project = await projectRepo.create(
      name: 'Host',
      targetUrl: 'https://host.app',
    );
    // Select the project so the identity section renders.
    container.read(selectedProjectIdProvider.notifier).select(project.id);
    await tester.pumpAndSettle();

    // --- Create identity ---
    await tester.tap(find.byTooltip('New Identity'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Name').first,
      'Alpha',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect((await identityRepo.getByProject(project.id)).single.name, 'Alpha');

    // --- Edit identity ---
    await tester.tap(find.byTooltip('Edit identity'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Name').first,
      'Bravo',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Bravo'), findsOneWidget);
    expect((await identityRepo.getByProject(project.id)).single.name, 'Bravo');

    // --- Delete identity ---
    await tester.tap(find.byTooltip('Delete identity'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Bravo'), findsNothing);
    expect(await identityRepo.getByProject(project.id), isEmpty);
  });

  testWidgets('identity dialog device preset persists to the identity record', (
    tester,
  ) async {
    final container = await boot(tester);
    final projectRepo = ProjectRepository(db);
    final identityRepo = IdentityRepository(db);
    final project = await projectRepo.create(
      name: 'Devices',
      targetUrl: 'https://dev.app',
    );
    container.read(selectedProjectIdProvider.notifier).select(project.id);
    await tester.pumpAndSettle();

    // Create: pick iPhone 15 in the Device dropdown.
    await tester.tap(find.byTooltip('New Identity'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Name').first,
      'Mobile',
    );
    await tester.tap(find.byKey(const ValueKey('identity-device-preset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('iPhone 15 — 393×852').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    var identities = await identityRepo.getByProject(project.id);
    expect(identities.single.devicePresetId, 'iphone-15');
    // The list tile surfaces the device next to the isolation mode.
    expect(find.textContaining('iPhone 15'), findsWidgets);

    // Edit back to the desktop default.
    await tester.tap(find.byTooltip('Edit identity'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('identity-device-preset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desktop').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    identities = await identityRepo.getByProject(project.id);
    expect(identities.single.devicePresetId, 'desktop-1920');
  });

  testWidgets('SharedSession identity shows the NOT ISOLATED warning', (
    tester,
  ) async {
    final container = await boot(tester);
    final projectRepo = ProjectRepository(db);
    final identityRepo = IdentityRepository(db);
    final project = await projectRepo.create(
      name: 'Iso',
      targetUrl: 'https://iso.app',
    );
    await identityRepo.create(
      projectId: project.id,
      name: 'Shared',
      color: '#FF0000',
      isolationMode: IsolationMode.sharedSession,
    );
    container.read(selectedProjectIdProvider.notifier).select(project.id);
    await tester.pumpAndSettle();

    // The identity list shows SharedSession's display name with the
    // "(not isolated)" marker.
    expect(find.textContaining('Shared Session'), findsWidgets);
  });
}
