/// Compact language switcher for the management sidebar header: a translate
/// icon opening a menu with Follow system / 简体中文 / English. The selected
/// option shows a check mark; selection updates `MaterialApp.locale`
/// immediately through [localePreferenceProvider] without rebuilding the
/// widget tree from scratch, so open panels, selections, and adapter
/// instances are preserved.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/localization.dart';

class LanguageMenuButton extends ConsumerWidget {
  const LanguageMenuButton({super.key, this.iconColor});

  /// Optional icon color (defaults to the ambient icon theme).
  final Color? iconColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final selected = ref.watch(localePreferenceProvider);
    return PopupMenuButton<LocalePreference>(
      key: const ValueKey('language-menu'),
      tooltip: l10n.languageMenuTooltip,
      icon: Icon(Icons.translate, color: iconColor),
      onSelected: (preference) =>
          ref.read(localePreferenceProvider.notifier).select(preference),
      itemBuilder: (context) => [
        _item(
          selected,
          LocalePreference.system,
          l10n.languageFollowSystem,
          'language-option-system',
        ),
        _item(
          selected,
          LocalePreference.simplifiedChinese,
          l10n.languageChinese,
          'language-option-zh',
        ),
        _item(
          selected,
          LocalePreference.english,
          l10n.languageEnglish,
          'language-option-en',
        ),
      ],
    );
  }

  PopupMenuItem<LocalePreference> _item(
    LocalePreference selected,
    LocalePreference value,
    String label,
    String key,
  ) {
    return PopupMenuItem<LocalePreference>(
      key: ValueKey(key),
      value: value,
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: value == selected ? const Icon(Icons.check, size: 18) : null,
          ),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
    );
  }
}
