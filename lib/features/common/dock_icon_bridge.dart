import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/icon_settings.dart';
import '../../app/localization.dart';
import 'settings_dialog.dart';

/// Routes Dock selections through the same controller as the settings dialog.
class DockIconBridge extends ConsumerStatefulWidget {
  const DockIconBridge({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<DockIconBridge> createState() => _DockIconBridgeState();
}

class _DockIconBridgeState extends ConsumerState<DockIconBridge> {
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  int _configurationVersion = 0;

  @override
  void initState() {
    super.initState();
    if (supported) {
      PlatformAppIcon.channel.setMethodCallHandler(_handleDockCall);
    }
  }

  Future<bool> _handleDockCall(MethodCall call) async {
    if (call.method != 'selectIcon') {
      throw MissingPluginException('Unknown Dock action');
    }
    final arguments = call.arguments;
    final id = arguments is Map ? arguments['id'] : null;
    final matches = AppIconChoice.values.where((icon) => icon.id == id);
    if (matches.isEmpty || !mounted) return false;
    final icon = matches.single;
    await ref.read(iconSettingsProvider.notifier).select(icon);
    if (!mounted) return false;
    final settings = ref.read(iconSettingsProvider);
    return settings.icon == icon && !settings.failed && !settings.saving;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (supported) _configureMenu();
  }

  Future<void> _configureMenu() async {
    final version = ++_configurationVersion;
    final l10n = context.l10n;
    final selected = ref.read(iconSettingsProvider).icon;
    try {
      final choices = await Future.wait(
        AppIconChoice.values.map((icon) async {
          final data = await rootBundle.load(icon.assetPath);
          return {
            'id': icon.id,
            'title': '${icon.id} · ${icon.label(l10n)}',
            'png': data.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            ),
          };
        }),
      );
      if (!mounted || version != _configurationVersion) return;
      await PlatformAppIcon.channel.invokeMethod<void>('configureDockMenu', {
        'title': l10n.dockIconMenu,
        'restoreTitle': l10n.restoreDefaultIcon,
        'errorTitle': l10n.iconSaveFailed,
        'id': selected.id,
        'choices': choices,
      });
    } catch (_) {
      // App settings remain usable if Dock menu configuration is unavailable.
    }
  }

  @override
  void dispose() {
    if (supported) PlatformAppIcon.channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
