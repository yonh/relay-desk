/// Management sidebar: project list + identity list with full CRUD
/// (create / edit / delete) and isolation-mode selection.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/localization.dart';
import '../../app/providers.dart';
import '../../core/platform/domain.dart';
import '../../core/url_input.dart';
import '../../data/device_presets.dart';
import '../common/empty_state_guide.dart';
import '../common/language_menu.dart';

class ManagementScreen extends ConsumerWidget {
  const ManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final projects = ref.watch(projectsProvider);
    final selectedId = ref.watch(selectedProjectIdProvider);

    return SizedBox(
      width: 300,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Row(
              children: [
                Text(
                  'Relay Desk',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const Spacer(),
                LanguageMenuButton(
                  iconColor: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  onPressed: () => _showProjectDialog(context, ref),
                  tooltip: l10n.newProject,
                ),
              ],
            ),
          ),
          Expanded(
            child: projects.when(
              data: (list) {
                if (list.isEmpty) {
                  return EmptyStateGuide(
                    icon: Icons.create_new_folder_outlined,
                    title: l10n.welcomeTitle,
                    description: l10n.welcomeDescription,
                    actionLabel: l10n.createProject,
                    onAction: () => _showProjectDialog(context, ref),
                  );
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final project = list[i];
                    final isSelected = project.id == selectedId;
                    return ListTile(
                      selected: isSelected,
                      leading: const Icon(Icons.folder),
                      title: Text(project.name),
                      subtitle: Text(
                        project.targetUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => ref
                          .read(selectedProjectIdProvider.notifier)
                          .select(project.id),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: l10n.editProjectTooltip,
                            icon: const Icon(Icons.edit, size: 16),
                            onPressed: () => _showProjectDialog(
                              context,
                              ref,
                              existing: project,
                            ),
                          ),
                          IconButton(
                            tooltip: l10n.deleteProjectTooltip,
                            icon: const Icon(Icons.delete_outline, size: 16),
                            onPressed: () =>
                                _confirmDeleteProject(context, ref, project),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text(l10n.errorMessage(e.toString()))),
            ),
          ),
          if (selectedId != null) const IdentityListSection(),
        ],
      ),
    );
  }

  void _showProjectDialog(
    BuildContext context,
    WidgetRef ref, {
    Project? existing,
  }) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final urlCtrl = TextEditingController(text: existing?.targetUrl ?? '');
    var allowPrivate = existing?.allowPrivateNetwork ?? false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(
            existing == null ? ctx.l10n.newProject : ctx.l10n.editProject,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(labelText: ctx.l10n.fieldName),
              ),
              TextField(
                controller: urlCtrl,
                decoration: InputDecoration(labelText: ctx.l10n.fieldTargetUrl),
              ),
              SwitchListTile(
                title: Text(ctx.l10n.allowPrivateNetwork),
                value: allowPrivate,
                onChanged: (v) => setState(() => allowPrivate = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.l10n.cancel),
            ),
            FilledButton(
              onPressed: () async {
                final targetUrl = normalizeUrlInput(urlCtrl.text);
                if (nameCtrl.text.isEmpty || targetUrl == null) return;
                final repo = await ref.read(projectRepositoryProvider.future);
                if (existing == null) {
                  await repo.create(
                    name: nameCtrl.text,
                    targetUrl: targetUrl,
                    allowPrivateNetwork: allowPrivate,
                  );
                } else {
                  await repo.update(
                    existing.copyWith(
                      name: nameCtrl.text,
                      targetUrl: targetUrl,
                      allowPrivateNetwork: allowPrivate,
                    ),
                  );
                }
                ref.invalidate(projectsProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(ctx.l10n.save),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteProject(
    BuildContext context,
    WidgetRef ref,
    Project project,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.deleteProjectTitle(project.name)),
        content: Text(ctx.l10n.deleteProjectBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final repo = await ref.read(projectRepositoryProvider.future);
              await repo.delete(project.id);
              if (ref.read(selectedProjectIdProvider) == project.id) {
                ref.read(selectedProjectIdProvider.notifier).select(null);
              }
              ref.invalidate(projectsProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(ctx.l10n.delete),
          ),
        ],
      ),
    );
  }
}

class IdentityListSection extends ConsumerWidget {
  const IdentityListSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final projectId = ref.watch(selectedProjectIdProvider)!;
    final identities = ref.watch(identitiesProvider(projectId));

    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Text(
                    l10n.identitiesTitle,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.person_add, size: 20),
                    onPressed: () =>
                        _showIdentityDialog(context, ref, projectId),
                    tooltip: l10n.newIdentity,
                  ),
                ],
              ),
            ),
            Expanded(
              child: identities.when(
                data: (list) {
                  if (list.isEmpty) {
                    return EmptyStateGuide(
                      icon: Icons.person_add_outlined,
                      title: l10n.noIdentitiesTitle,
                      description: l10n.noIdentitiesDescription,
                      actionLabel: l10n.createIdentity,
                      onAction: () =>
                          _showIdentityDialog(context, ref, projectId),
                    );
                  }
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final id = list[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _parseColor(id.color),
                          radius: 12,
                        ),
                        title: Text(id.name),
                        subtitle: Text(
                          '${id.isolationMode.label(l10n)} · '
                          '${effectiveDevicePreset(id.devicePresetId).name}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        dense: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: l10n.editIdentityTooltip,
                              icon: const Icon(Icons.edit, size: 16),
                              onPressed: () => _showIdentityDialog(
                                context,
                                ref,
                                projectId,
                                existing: id,
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.deleteIdentityTooltip,
                              icon: const Icon(Icons.delete_outline, size: 16),
                              onPressed: () => _confirmDeleteIdentity(
                                context,
                                ref,
                                projectId,
                                id,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text(l10n.errorMessage(e.toString()))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showIdentityDialog(
    BuildContext context,
    WidgetRef ref,
    String projectId, {
    Identity? existing,
  }) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final colorCtrl = TextEditingController(text: existing?.color ?? '#E53935');
    final startPathCtrl = TextEditingController(
      text: existing?.startPath ?? '/',
    );
    var mode = existing?.isolationMode ?? IsolationMode.nativeProfile;
    // Unknown/absent preset ids normalize to the desktop default.
    var presetId = effectiveDevicePreset(existing?.devicePresetId).id;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(
            existing == null ? ctx.l10n.newIdentity : ctx.l10n.editIdentity,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(labelText: ctx.l10n.fieldName),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<IsolationMode>(
                initialValue: mode,
                decoration: InputDecoration(labelText: ctx.l10n.fieldIsolation),
                items: IsolationMode.values
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(m.label(ctx.l10n)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => mode = v!),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const ValueKey('identity-device-preset'),
                initialValue: presetId,
                decoration: InputDecoration(
                  labelText: ctx.l10n.fieldDevicePreset,
                ),
                items: devicePresets
                    .map(
                      (p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(
                          p.sizing != ViewportSizing.free
                              ? '${p.name} — ${p.viewportWidth}×${p.viewportHeight}'
                              : p.name,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => presetId = v!),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: colorCtrl,
                decoration: InputDecoration(labelText: ctx.l10n.fieldColor),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: startPathCtrl,
                decoration: InputDecoration(labelText: ctx.l10n.fieldStartPath),
              ),
              if (mode == IsolationMode.sharedSession)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    ctx.l10n.sharedSessionWarning,
                    style: const TextStyle(color: Colors.orange, fontSize: 11),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.l10n.cancel),
            ),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.isEmpty) return;
                final repo = await ref.read(identityRepositoryProvider.future);
                if (existing == null) {
                  await repo.create(
                    projectId: projectId,
                    name: nameCtrl.text,
                    color: colorCtrl.text,
                    isolationMode: mode,
                    startPath: startPathCtrl.text,
                    devicePresetId: presetId,
                  );
                } else {
                  await repo.update(
                    existing.copyWith(
                      name: nameCtrl.text,
                      color: colorCtrl.text,
                      isolationMode: mode,
                      startPath: startPathCtrl.text,
                      devicePresetId: presetId,
                    ),
                  );
                }
                ref.invalidate(identitiesProvider(projectId));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(ctx.l10n.save),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteIdentity(
    BuildContext context,
    WidgetRef ref,
    String projectId,
    Identity identity,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.deleteIdentityTitle(identity.name)),
        content: Text(ctx.l10n.deleteIdentityBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final repo = await ref.read(identityRepositoryProvider.future);
              await repo.delete(identity.id);
              ref.invalidate(identitiesProvider(projectId));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(ctx.l10n.delete),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.grey;
    }
  }
}
