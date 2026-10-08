import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/icon_settings.dart';
import '../../app/localization.dart';
import '../../l10n/app_localizations.dart';
import '../update/update_ui.dart';

extension AppIconLabel on AppIconChoice {
  String label(AppLocalizations l10n) => switch (this) {
    AppIconChoice.a1 => l10n.iconA1,
    AppIconChoice.a2 => l10n.iconA2,
    AppIconChoice.b1 => l10n.iconB1,
    AppIconChoice.b2 => l10n.iconB2,
    AppIconChoice.c1 => l10n.iconC1,
    AppIconChoice.c3 => l10n.iconC3,
  };
}

class AppLogo extends ConsumerWidget {
  const AppLogo({super.key, this.size = 32});
  final double size;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icon = ref.watch(iconSettingsProvider.select((state) => state.icon));
    return Image.asset(
      icon.assetPath,
      key: ValueKey('app-logo-${icon.id}'),
      width: size,
      height: size,
      semanticLabel: 'Relay Desk',
    );
  }
}

class SettingsDialog extends ConsumerWidget {
  const SettingsDialog({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(iconSettingsProvider);
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(l10n.settingsTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.appIconTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(l10n.appIconDescription),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth < 360 ? 2 : 3;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final icon in AppIconChoice.values)
                        SizedBox(
                          width: width,
                          child: Semantics(
                            selected: settings.icon == icon,
                            button: true,
                            label: '${icon.id} ${icon.label(l10n)}',
                            child: Material(
                              color: settings.icon == icon
                                  ? colors.secondaryContainer
                                  : colors.surfaceContainerLow,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: settings.icon == icon
                                      ? colors.primary
                                      : colors.outlineVariant,
                                  width: settings.icon == icon ? 2 : 1,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                key: ValueKey('icon-option-${icon.id}'),
                                onTap: settings.saving
                                    ? null
                                    : () => ref
                                          .read(iconSettingsProvider.notifier)
                                          .select(icon),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    children: [
                                      Image.asset(
                                        icon.assetPath,
                                        width: 72,
                                        height: 72,
                                        excludeFromSemantics: true,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        icon.id,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelLarge,
                                      ),
                                      Text(
                                        icon.label(l10n),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 6),
                                      SizedBox(
                                        height: 20,
                                        child: settings.icon == icon
                                            ? Icon(
                                                Icons.check_circle,
                                                size: 20,
                                                color: colors.primary,
                                              )
                                            : icon == AppIconChoice.b2
                                            ? Text(
                                                l10n.defaultIcon,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.labelSmall,
                                              )
                                            : null,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              // Keep the same footprint in idle, saving and error states so
              // the centered dialog and its cards never jump during a save.
              Stack(
                alignment: Alignment.center,
                children: [
                  Visibility(
                    visible: settings.failed,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: Text(
                      l10n.iconSaveFailed,
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                  if (settings.saving)
                    const Positioned.fill(
                      child: Center(child: LinearProgressIndicator()),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l10n.appIconPlatformNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 16),
              const UpdateSettingsSection(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: settings.saving || settings.icon == AppIconChoice.b2
              ? null
              : () => ref
                    .read(iconSettingsProvider.notifier)
                    .select(AppIconChoice.b2),
          child: Text(l10n.restoreDefaultIcon),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.settingsDone),
        ),
      ],
    );
  }
}
