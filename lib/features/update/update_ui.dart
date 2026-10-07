import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/localization.dart';
import '../../core/update/models.dart';
import '../../l10n/app_localizations.dart';
import 'update_controller.dart';

/// Wraps the home screen: runs the silent auto-check shortly after launch
/// and pops [UpdatePromptDialog] when a release needs attention.
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  /// Delay before the launch check — lets the window settle and keeps the
  /// API call off the critical startup path.
  static const startupDelay = Duration(seconds: 4);

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  /// Tags already prompted this session — "稍后" must not re-pop instantly,
  /// and a finished flow should not resurrect the dialog.
  final _promptedTags = <String>{};
  Timer? _startupTimer;

  @override
  void initState() {
    super.initState();
    _startupTimer = Timer(UpdateGate.startupDelay, () {
      if (!mounted) return;
      final settings = ref.read(updateSettingsProvider);
      if (settings.autoCheck) {
        unawaited(ref.read(updateStatusProvider.notifier).check());
      }
    });
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UpdateStatus>(updateStatusProvider, (previous, next) {
      final tag = next.release?.tag;
      // With auto-download on, `available` is only a transit state — the
      // prompt appears once the package is actually ready to install. The
      // exemption must not apply when there is nothing to download: a
      // release without a matching asset would otherwise stall silently.
      final autoDl = ref.read(updateSettingsProvider).autoDownload;
      final wantsPrompt = next.phase == UpdatePhase.ready ||
          (next.phase == UpdatePhase.available &&
              (!autoDl || next.asset == null));
      if (tag == null ||
          !wantsPrompt ||
          previous?.phase == next.phase ||
          !_promptedTags.add(tag)) {
        return;
      }
      // Listeners can fire mid-build; defer the dialog to the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showUpdatePrompt(context);
      });
    });
    return widget.child;
  }
}

var _updatePromptOpen = false;

Future<void> showUpdatePrompt(BuildContext context) {
  // Singleton: the settings "查看" action and the gate listener must not
  // stack a second dialog over an open one.
  if (_updatePromptOpen) return Future.value();
  _updatePromptOpen = true;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const UpdatePromptDialog(),
  ).whenComplete(() => _updatePromptOpen = false);
}

/// Live dialog — watches [updateStatusProvider] and morphs through
/// available → downloading → verifying → ready without reopening.
class UpdatePromptDialog extends ConsumerWidget {
  const UpdatePromptDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final status = ref.watch(updateStatusProvider);
    final release = status.release;
    if (release == null) {
      // The state reset underneath us (e.g. skip settled) — close.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.maybePop(context);
      });
      return const SizedBox.shrink();
    }
    final controller = ref.read(updateStatusProvider.notifier);
    final title = switch (status.phase) {
      UpdatePhase.ready => l10n.updateDownloadedTitle(
        release.version.toString(),
      ),
      _ => l10n.updateAvailableTitle(release.version.toString()),
    };
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 480,
        child: switch (status.phase) {
          UpdatePhase.downloading => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.updateDownloading(
                  (status.progress * 100).round().toString(),
                ),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: status.progress > 0 ? status.progress : null,
              ),
            ],
          ),
          UpdatePhase.verifying => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(l10n.updateVerifying),
            ],
          ),
          UpdatePhase.installing => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(l10n.updateInstalling),
            ],
          ),
          UpdatePhase.failed => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.updateFailed(status.error ?? ''),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
          _ => _ReleaseBody(status: status, l10n: l10n),
        },
      ),
      actions: switch (status.phase) {
        UpdatePhase.downloading => [
          TextButton(
            onPressed: controller.cancelDownload,
            child: Text(l10n.updateCancel),
          ),
        ],
        UpdatePhase.failed => [
          TextButton(
            onPressed: controller.dismiss,
            child: Text(l10n.settingsDone),
          ),
          FilledButton(
            onPressed: controller.retry,
            child: Text(l10n.updateRetry),
          ),
        ],
        UpdatePhase.ready => [
          TextButton(
            onPressed: () {
              controller.skipVersion();
              Navigator.pop(context);
            },
            child: Text(l10n.updateSkipVersion),
          ),
          TextButton(
            onPressed: () {
              controller.dismiss();
              Navigator.pop(context);
            },
            child: Text(l10n.updateLater),
          ),
          FilledButton(
            onPressed: controller.installAndRelaunch,
            child: Text(l10n.updateInstallRestart),
          ),
        ],
        UpdatePhase.available => [
          TextButton(
            onPressed: () {
              controller.skipVersion();
              Navigator.pop(context);
            },
            child: Text(l10n.updateSkipVersion),
          ),
          TextButton(
            onPressed: () {
              controller.dismiss();
              Navigator.pop(context);
            },
            child: Text(l10n.updateLater),
          ),
          if (status.asset != null)
            FilledButton(
              onPressed: controller.download,
              child: Text(l10n.updateDownload),
            )
          else
            FilledButton(
              onPressed: () {
                unawaited(openExternalUrl(release.htmlUrl));
                Navigator.pop(context);
              },
              child: Text(l10n.updateOpenReleasePage),
            ),
        ],
        // verifying / installing / checking / idle / upToDate: no actions —
        // a "跳过" or "下载" tap mid-install could delete the payload the
        // helper is about to copy.
        _ => const [],
      },
    );
  }
}

class _ReleaseBody extends StatelessWidget {
  const _ReleaseBody({required this.status, required this.l10n});

  final UpdateStatus status;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final release = status.release!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (status.currentVersion != null)
          Text(
            l10n.updateVersionTransition(
              status.currentVersion.toString(),
              release.version.toString(),
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (status.currentVersion != null) const SizedBox(height: 8),
        if (status.phase == UpdatePhase.ready) Text(l10n.updateReadyHint),
        if (status.phase == UpdatePhase.ready) const SizedBox(height: 8),
        if (status.asset != null)
          Text(
            _assetSizeLabel(status.asset!),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (status.asset == null) Text(l10n.updateNoAsset),
        if (release.body.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            l10n.updateWhatsNew,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: Text(
                release.body.trim(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _assetSizeLabel(ReleaseAsset asset) {
    final mb = asset.size / (1024 * 1024);
    return '~${mb.toStringAsFixed(1)} MB';
  }
}

/// Settings dialog section — toggles plus an inline status/check row.
class UpdateSettingsSection extends ConsumerWidget {
  const UpdateSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(updateSettingsProvider);
    final status = ref.watch(updateStatusProvider);
    final settingsCtl = ref.read(updateSettingsProvider.notifier);
    final statusCtl = ref.read(updateStatusProvider.notifier);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.updateSectionTitle, style: theme.textTheme.titleMedium),
        SwitchListTile(
          key: const ValueKey('update-auto-check'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.updateAutoCheck),
          value: settings.autoCheck,
          onChanged: (v) => unawaited(settingsCtl.setAutoCheck(v)),
        ),
        SwitchListTile(
          key: const ValueKey('update-auto-download'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.updateAutoDownload),
          value: settings.autoDownload,
          onChanged: (v) => unawaited(settingsCtl.setAutoDownload(v)),
        ),
        if (settings.skippedVersion != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.updateSkippedVersion(settings.skippedVersion!),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: () => unawaited(settingsCtl.clearSkipped()),
                  child: Text(l10n.updateClearSkip),
                ),
              ],
            ),
          ),
        Row(
          children: [
            TextButton(
              key: const ValueKey('update-check-now'),
              onPressed: status.busy
                  ? null
                  : () => unawaited(statusCtl.check(manual: true)),
              child: Text(l10n.updateCheckNow),
            ),
            const SizedBox(width: 8),
            Expanded(child: _StatusLine(status: status, l10n: l10n)),
          ],
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status, required this.l10n});

  final UpdateStatus status;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (status.phase) {
      case UpdatePhase.checking:
        return Text(l10n.updateChecking, style: theme.textTheme.bodySmall);
      case UpdatePhase.upToDate:
        return Text(l10n.updateUpToDate, style: theme.textTheme.bodySmall);
      case UpdatePhase.available:
      case UpdatePhase.ready:
        final version = status.release?.version.toString() ?? '';
        return Row(
          children: [
            Flexible(
              child: Text(
                'v$version',
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: () => showUpdatePrompt(context),
              child: Text(l10n.updateViewPrompt),
            ),
          ],
        );
      case UpdatePhase.downloading:
        return Text(
          l10n.updateDownloading((status.progress * 100).round().toString()),
          style: theme.textTheme.bodySmall,
        );
      case UpdatePhase.verifying:
        return Text(l10n.updateVerifying, style: theme.textTheme.bodySmall);
      case UpdatePhase.installing:
        return Text(l10n.updateInstalling, style: theme.textTheme.bodySmall);
      case UpdatePhase.failed:
        return Text(
          l10n.updateFailed(status.error ?? ''),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        );
      case UpdatePhase.idle:
        return const SizedBox.shrink();
    }
  }
}

/// `open`-based external link — avoids pulling in url_launcher for one URL.
Future<void> openExternalUrl(String url) async {
  try {
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', url]);
    } else {
      await Process.run('xdg-open', [url]);
    }
  } catch (_) {}
}
