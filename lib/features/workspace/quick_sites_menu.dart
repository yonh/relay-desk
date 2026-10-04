/// 快捷站点 (Quick Sites) launcher.
///
/// A custom, reusable toolbar widget that opens an app-designed anchored
/// surface for launching preset websites. The widget owns its own in-memory
/// state (recents, search, selected site, open mode, open/close) and emits
/// [onLaunch] callbacks. It deliberately avoids `PopupMenuButton`,
/// `DropdownButton`, and any native/system menu in favor of an Overlay-based
/// surface built from ordinary Material widgets.
///
/// This slice only adds the launcher UI. Project WebViews are not touched and
/// no native/macOS integration is performed; [onLaunch] may be a no-op but
/// still updates recent usage so `最近使用` appears after the first launch.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/localization.dart';

/// How a [QuickSite] should be opened when launched.
enum QuickSiteOpenMode {
  /// Open as a floating overlay panel (`打开浮层`).
  overlay,

  /// Dock the site to the right side of the workspace (`固定到右侧`).
  sideDock,

  /// Open in a new window (`在新窗口打开`).
  newWindow,
}

/// A preset website entry shown in the [QuickSitesMenu].
@immutable
class QuickSite {
  final String id;
  final String name;
  final String host;

  /// Exact HTTPS URL used to launch the site in a WebView/browser window.
  final String url;
  final Color color;

  const QuickSite({
    required this.id,
    required this.name,
    required this.host,
    required this.url,
    required this.color,
  });

  @override
  bool operator ==(Object other) => other is QuickSite && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Built-in preset sites shown under `所有站点`.
const List<QuickSite> kQuickSitePresets = [
  QuickSite(
    id: 'google-translate',
    name: 'Google Translate',
    host: 'translate.google.com',
    url: 'https://translate.google.com',
    color: Color(0xFF4285F4),
  ),
  QuickSite(
    id: 'chatgpt',
    name: 'ChatGPT',
    host: 'chat.openai.com',
    url: 'https://chat.openai.com',
    color: Color(0xFF10A37F),
  ),
  QuickSite(
    id: 'grok',
    name: 'Grok',
    host: 'grok.com',
    url: 'https://grok.com',
    color: Color(0xFF111111),
  ),
  QuickSite(
    id: 'notion',
    name: 'Notion',
    host: 'notion.so',
    url: 'https://www.notion.so',
    color: Color(0xFF000000),
  ),
  QuickSite(
    id: 'dictionary',
    name: 'Dictionary',
    host: 'dictionary.com',
    url: 'https://www.dictionary.com',
    color: Color(0xFF6750A4),
  ),
];

/// Signature of the launch callback emitted by [QuickSitesMenu].
typedef QuickSiteLaunch = void Function(QuickSite site, QuickSiteOpenMode mode);

/// Signature of the per-site keep-alive toggle callback emitted by
/// [QuickSitesMenu]. The owning workspace adds/removes the site id from its
/// resident set and decides whether to dispose or merely hide that host.
typedef QuickSiteKeepAliveChanged = void Function(QuickSite site, bool value);

/// A toolbar trigger + custom anchored surface for 快捷站点.
///
/// Insert at the far right of the workspace toolbar. The trigger shows a
/// lightning/bolt icon and the localized Quick Sites label. Tapping opens an
/// Overlay-based surface anchored below the trigger; the surface supports
/// search, recents (after a launch), all sites, and per-site action rows.
class QuickSitesMenu extends StatefulWidget {
  final QuickSiteLaunch? onLaunch;

  /// Site ids whose hosts should stay resident in memory (`常驻`) when closed.
  /// Each site owns an independent toggle; enabling one site does not affect
  /// any other. The owning workspace uses this set to decide, per site,
  /// whether to dispose or merely hide that host.
  final Set<String> keepAliveSiteIds;

  /// Invoked when the user toggles a site's `常驻` switch on the menu surface.
  final QuickSiteKeepAliveChanged? onKeepAliveChanged;

  const QuickSitesMenu({
    super.key,
    this.onLaunch,
    this.keepAliveSiteIds = const {},
    this.onKeepAliveChanged,
  });

  @override
  State<QuickSitesMenu> createState() => _QuickSitesMenuState();
}

class _QuickSitesMenuState extends State<QuickSitesMenu> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  // In-memory interaction state owned by this widget.
  final List<QuickSite> _recents = [];
  String _search = '';
  QuickSite? _selectedSite;
  QuickSiteOpenMode _selectedMode = QuickSiteOpenMode.overlay;

  bool get _isOpen => _overlayEntry != null;

  @override
  void didUpdateWidget(covariant QuickSitesMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The custom menu lives in a separate OverlayEntry, so it does not
    // automatically rebuild when the toolbar parent updates the set.
    if (oldWidget.keepAliveSiteIds != widget.keepAliveSiteIds) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _overlayEntry?.markNeedsBuild();
      });
    }
  }

  void _toggle() {
    if (_isOpen) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    if (_isOpen) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (ctx) => _QuickSitesSurface(
        layerLink: _layerLink,
        recents: List<QuickSite>.of(_recents),
        search: _search,
        selectedSite: _selectedSite,
        selectedMode: _selectedMode,
        keepAliveSiteIds: widget.keepAliveSiteIds,
        onKeepAliveChanged: widget.onKeepAliveChanged,
        onSearchChanged: (v) {
          _search = v;
          _overlayEntry?.markNeedsBuild();
        },
        onSelectSite: (site) {
          _selectedSite = site;
          _overlayEntry?.markNeedsBuild();
        },
        onSelectMode: (mode) {
          _selectedMode = mode;
          _overlayEntry?.markNeedsBuild();
        },
        onLaunch: _launch,
        onClose: _close,
      ),
    );
    overlay.insert(entry);
    setState(() => _overlayEntry = entry);
  }

  void _close() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() {});
  }

  void _launch(QuickSite site, QuickSiteOpenMode mode) {
    _selectedSite = site;
    _selectedMode = mode;
    _recents
      ..removeWhere((s) => s.id == site.id)
      ..insert(0, site);
    if (_recents.length > 8) _recents.removeRange(8, _recents.length);
    widget.onLaunch?.call(site, mode);
    _close();
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: context.l10n.quickSites,
      child: CompositedTransformTarget(
        link: _layerLink,
        child: _TriggerButton(
          key: const ValueKey('quick-sites-trigger'),
          isOpen: _isOpen,
          onTap: _toggle,
          theme: theme,
        ),
      ),
    );
  }
}

class _TriggerButton extends StatelessWidget {
  final bool isOpen;
  final VoidCallback onTap;
  final ThemeData theme;

  const _TriggerButton({
    super.key,
    required this.isOpen,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 900;
    return Tooltip(
      message: context.l10n.quickSites,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt, size: 18, color: theme.colorScheme.primary),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(
                    context.l10n.quickSites,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(
                  isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The anchored overlay surface containing search, recents, all sites and
/// per-site action rows. Built from ordinary Material widgets.
class _QuickSitesSurface extends StatefulWidget {
  final LayerLink layerLink;
  final List<QuickSite> recents;
  final String search;
  final QuickSite? selectedSite;
  final QuickSiteOpenMode selectedMode;
  final Set<String> keepAliveSiteIds;
  final QuickSiteKeepAliveChanged? onKeepAliveChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<QuickSite> onSelectSite;
  final ValueChanged<QuickSiteOpenMode> onSelectMode;
  final QuickSiteLaunch onLaunch;
  final VoidCallback onClose;

  const _QuickSitesSurface({
    required this.layerLink,
    required this.recents,
    required this.search,
    required this.selectedSite,
    required this.selectedMode,
    required this.keepAliveSiteIds,
    required this.onKeepAliveChanged,
    required this.onSearchChanged,
    required this.onSelectSite,
    required this.onSelectMode,
    required this.onLaunch,
    required this.onClose,
  });

  @override
  State<_QuickSitesSurface> createState() => _QuickSitesSurfaceState();
}

class _QuickSitesSurfaceState extends State<_QuickSitesSurface> {
  late final FocusNode _searchFocusNode;
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode();
    _searchCtrl = TextEditingController(text: widget.search);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = widget.search.trim().toLowerCase();
    bool matches(QuickSite s) =>
        query.isEmpty ||
        s.name.toLowerCase().contains(query) ||
        s.host.toLowerCase().contains(query);

    final filteredRecents = widget.recents
        .where(matches)
        .toList(growable: false);
    final filteredPresets = kQuickSitePresets
        .where(matches)
        .toList(growable: false);

    return Stack(
      children: [
        // Outside-tap dismissal barrier.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => widget.onClose(),
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link: widget.layerLink,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 6),
          child: TapRegion(
            onTapOutside: (_) => widget.onClose(),
            child: Focus(
              canRequestFocus: false,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey.keyLabel == 'Escape') {
                  widget.onClose();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Material(
                key: const ValueKey('quick-sites-menu'),
                elevation: 12,
                borderRadius: BorderRadius.circular(12),
                color: theme.colorScheme.surface,
                surfaceTintColor: theme.colorScheme.surfaceTint,
                shadowColor: Colors.black.withValues(alpha: 0.3),
                child: SizedBox(
                  width: 360,
                  height: 444,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(onClose: widget.onClose),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: TextField(
                          key: const ValueKey('quick-sites-search'),
                          controller: _searchCtrl,
                          focusNode: _searchFocusNode,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: context.l10n.quickSitesSearchHint,
                            prefixIcon: const Icon(Icons.search, size: 18),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                          onChanged: widget.onSearchChanged,
                        ),
                      ),
                      Divider(height: 1, color: theme.dividerColor),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          children: [
                            if (filteredRecents.isNotEmpty) ...[
                              _SectionHeader(
                                label: context.l10n.quickSitesRecent,
                              ),
                              for (final site in filteredRecents)
                                _SiteRow(
                                  site: site,
                                  selected: widget.selectedSite?.id == site.id,
                                  selectedMode: widget.selectedMode,
                                  onSelectSite: widget.onSelectSite,
                                  onSelectMode: widget.onSelectMode,
                                  onLaunch: widget.onLaunch,
                                  keepAlive: widget.keepAliveSiteIds.contains(
                                    site.id,
                                  ),
                                  onKeepAliveChanged: widget.onKeepAliveChanged,
                                  isRecent: true,
                                ),
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Divider(
                                  height: 1,
                                  color: theme.dividerColor,
                                ),
                              ),
                            ],
                            _SectionHeader(label: context.l10n.quickSitesAll),
                            if (filteredPresets.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                child: Text(context.l10n.quickSitesNoMatch),
                              )
                            else
                              for (final site in filteredPresets)
                                _SiteRow(
                                  site: site,
                                  selected: widget.selectedSite?.id == site.id,
                                  selectedMode: widget.selectedMode,
                                  onSelectSite: widget.onSelectSite,
                                  onSelectMode: widget.onSelectMode,
                                  onLaunch: widget.onLaunch,
                                  keepAlive: widget.keepAliveSiteIds.contains(
                                    site.id,
                                  ),
                                  onKeepAliveChanged: widget.onKeepAliveChanged,
                                ),
                          ],
                        ),
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
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onClose;
  const _Header({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Icon(Icons.bolt, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            context.l10n.quickSites,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Semantics(
            label: context.l10n.quickSitesClose,
            button: true,
            child: IconButton(
              key: const ValueKey('quick-sites-close'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18),
              onPressed: onClose,
            ),
          ),
        ],
      ),
    );
  }
}

/// The `常驻` switch row embedded inside each [_SiteRow]. Deliberately uses a
/// plain [Switch] (no [Tooltip]) inside the follower surface, with a stable
/// per-site key so widget tests can find and toggle it without resorting to
/// Tooltip finders.
class _SiteKeepAliveToggle extends StatelessWidget {
  final QuickSite site;
  final bool value;
  final QuickSiteKeepAliveChanged? onChanged;
  final bool isRecent;

  const _SiteKeepAliveToggle({
    required this.site,
    required this.value,
    required this.onChanged,
    required this.isRecent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.quickSitesKeepAlive,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            height: 24,
            child: Switch(
              key: ValueKey(
                'quick-sites-keep-alive-${site.id}'
                '${isRecent ? '-recent' : ''}',
              ),
              value: value,
              onChanged: onChanged == null ? null : (v) => onChanged!(site, v),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _SiteRow extends StatelessWidget {
  final QuickSite site;
  final bool selected;
  final QuickSiteOpenMode selectedMode;
  final ValueChanged<QuickSite> onSelectSite;
  final ValueChanged<QuickSiteOpenMode> onSelectMode;
  final QuickSiteLaunch onLaunch;
  final bool keepAlive;
  final QuickSiteKeepAliveChanged? onKeepAliveChanged;
  final bool isRecent;

  const _SiteRow({
    required this.site,
    required this.selected,
    required this.selectedMode,
    required this.onSelectSite,
    required this.onSelectMode,
    required this.onLaunch,
    required this.keepAlive,
    required this.onKeepAliveChanged,
    this.isRecent = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
          : Colors.transparent,
      child: InkWell(
        onTap: () => onSelectSite(site),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _Monogram(site: site),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            site.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isRecent) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.history,
                            size: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      site.host,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ModeActions(
                siteId: site.id,
                selectedMode: selectedMode,
                onSelectMode: onSelectMode,
                onLaunch: (mode) => onLaunch(site, mode),
              ),
              const SizedBox(width: 6),
              _SiteKeepAliveToggle(
                site: site,
                value: keepAlive,
                onChanged: onKeepAliveChanged,
                isRecent: isRecent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Monogram extends StatelessWidget {
  final QuickSite site;
  const _Monogram({required this.site});

  @override
  Widget build(BuildContext context) {
    final initial = site.name.isNotEmpty ? site.name.characters.first : '?';
    final fg = _contrastColor(site.color);
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: site.color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        initial,
        style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
  }

  Color _contrastColor(Color bg) {
    final luminance = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
    return luminance > 0.55 ? Colors.black : Colors.white;
  }
}

class _ModeActions extends StatelessWidget {
  final String siteId;
  final QuickSiteOpenMode selectedMode;
  final ValueChanged<QuickSiteOpenMode> onSelectMode;
  final ValueChanged<QuickSiteOpenMode> onLaunch;

  const _ModeActions({
    required this.siteId,
    required this.selectedMode,
    required this.onSelectMode,
    required this.onLaunch,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      key: ValueKey('quick-sites-actions-$siteId'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _ModeChip(
          key: const ValueKey('quick-sites-action-overlay'),
          label: l10n.quickSitesOpenOverlay,
          icon: Icons.picture_in_picture_alt,
          selected: selectedMode == QuickSiteOpenMode.overlay,
          onTap: () {
            onSelectMode(QuickSiteOpenMode.overlay);
            onLaunch(QuickSiteOpenMode.overlay);
          },
        ),
        const SizedBox(width: 4),
        _ModeChip(
          key: const ValueKey('quick-sites-action-sideDock'),
          label: l10n.quickSitesDockRight,
          icon: Icons.view_sidebar,
          selected: selectedMode == QuickSiteOpenMode.sideDock,
          onTap: () {
            onSelectMode(QuickSiteOpenMode.sideDock);
            onLaunch(QuickSiteOpenMode.sideDock);
          },
        ),
        const SizedBox(width: 4),
        _ModeChip(
          key: const ValueKey('quick-sites-action-newWindow'),
          label: l10n.quickSitesOpenNewWindow,
          icon: Icons.open_in_new,
          selected: selectedMode == QuickSiteOpenMode.newWindow,
          onTap: () {
            onSelectMode(QuickSiteOpenMode.newWindow);
            onLaunch(QuickSiteOpenMode.newWindow);
          },
        ),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurfaceVariant;
    final bg = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    return Semantics(
      label: label,
      button: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Icon(icon, size: 14, color: fg),
          ),
        ),
      ),
    );
  }
}
