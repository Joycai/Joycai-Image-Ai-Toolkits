import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_shortcuts.dart';
import '../../core/design_tokens.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../glass/app_glass.dart';
import '../ui/app_key_label.dart';
import '../ui/focus_pane.dart';
import 'shortcut_labels.dart';

/// The `⌘/` panel (`00f` 帧 1–2): every key that works right now, in one
/// float.
///
/// Its entries come from [AppShortcuts.all] and nowhere else, so what it
/// promises and what the app answers cannot drift — the thing that had
/// already gone wrong before this round, when the only places a shortcut was
/// mentioned were three hard-coded strings in one context menu.
///
/// Three groups: what this page answers, what the *active focus region*
/// answers, and what works anywhere. The middle one is the reason the panel
/// exists in this shape — it names the region that owns the keyboard and
/// dims the regions that do not, so the rule (a selection key belongs to one
/// region at a time) is visible rather than explained.
const double _kPanelWideWidth = 720;
const double _kPanelNarrowWidth = 560;

/// Whether the panel is up, tracked by the panel's own lifetime.
///
/// Deliberately not "did I await a `showDialog` future": that future does not
/// complete when the tree is torn down without popping, so the flag survived
/// the panel and the next `⌘/` popped whatever route happened to be on top.
/// A `State`'s `dispose` runs either way.
int _openPanels = 0;
bool get isShortcutPanelOpen => _openPanels > 0;

/// Opens the panel, or closes it if it is already up — `⌘/` is a toggle.
void toggleShortcutPanel(
  BuildContext context, {
  required ShortcutScreen? screen,
}) {
  final navigator = Navigator.of(context);
  if (isShortcutPanelOpen) {
    navigator.popUntil((route) => route.settings.name != _routeName);
    return;
  }
  showDialog<void>(
    context: context,
    barrierColor: Theme.of(context).colorScheme.scrim,
    routeSettings: const RouteSettings(name: _routeName),
    // Read *now*, not inside the panel: opening it takes the keyboard, so
    // by the time the panel builds every region has honestly let go of its
    // claim. What the user is asking about is the region that was live when
    // they pressed the key, and while the panel is up nothing underneath can
    // change it.
    builder: (_) =>
        ShortcutPanel(screen: screen, activePane: FocusPane.active.value),
  );
}

/// Named so the toggle closes *this* route and never something under it.
const String _routeName = 'shortcut-panel';

class ShortcutPanel extends StatefulWidget {
  const ShortcutPanel({super.key, required this.screen, this.activePane});

  /// The screen the keys of which to show, or null on a screen that claims
  /// none — the panel then lists only what works anywhere.
  final ShortcutScreen? screen;

  /// The region that held the keyboard when the panel was asked for.
  final ShortcutPane? activePane;

  @override
  State<ShortcutPanel> createState() => _ShortcutPanelState();
}

class _ShortcutPanelState extends State<ShortcutPanel> {
  @override
  void initState() {
    super.initState();
    _openPanels++;
  }

  @override
  void dispose() {
    _openPanels = _openPanels > 0 ? _openPanels - 1 : 0;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final bool narrow = Responsive.isNarrow(context);
    final double width = narrow ? _kPanelNarrowWidth : _kPanelWideWidth;

    final screenRows = widget.screen == null
        ? const <AppShortcut>[]
        : AppShortcuts.forScreen(widget.screen!).toList();

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          maxHeight: MediaQuery.sizeOf(context).height - AppSpace.s28 * 2,
        ),
        child: AppGlass(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(l10n: l10n),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpace.s16, AppSpace.s10, AppSpace.s16, AppSpace.s6),
                  child: narrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ..._fileGroups(context, l10n),
                            if (screenRows.isNotEmpty)
                              _Group(
                                title: l10n.shortcutsGroupScreen,
                                rows: screenRows,
                              ),
                            _Group(
                              title: l10n.shortcutsGroupGlobal,
                              rows: AppShortcuts.appLevel.toList(),
                            ),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (screenRows.isNotEmpty)
                                    _Group(
                                      title: l10n.shortcutsGroupScreen,
                                      rows: screenRows,
                                    ),
                                  _Group(
                                    title: l10n.shortcutsGroupGlobal,
                                    rows: AppShortcuts.appLevel.toList(),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpace.s16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: _fileGroups(context, l10n),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              _Footer(l10n: l10n, scheme: scheme),
            ],
          ),
        ),
      ),
    );
  }

  /// The file-operation groups, one per focus region, the active one first
  /// and the rest dimmed.
  ///
  /// The panel is teaching the rule by obeying it: the region that owns the
  /// keyboard is named, and the keys of the others are visibly out of reach.
  List<Widget> _fileGroups(BuildContext context, AppLocalizations l10n) {
    final s = widget.screen;
    if (s == null) return const <Widget>[];

    final active = widget.activePane;
    final panes = <ShortcutPane>[
      for (final pane in ShortcutPane.values)
        if (AppShortcuts.forPane(s, pane).isNotEmpty) pane,
    ]..sort((a, b) {
        if (a == active) return -1;
        if (b == active) return 1;
        return a.index.compareTo(b.index);
      });

    return <Widget>[
      for (final (index, pane) in panes.indexed)
        _Group(
          // The heading once, over the group that is listening; the rest are
          // named by their region alone.
          title: index == 0 ? l10n.shortcutsGroupFiles : '',
          subtitle: pane == active
              ? l10n.shortcutsActiveRegion(shortcutPaneLabel(l10n, s, pane))
              : '${shortcutPaneLabel(l10n, s, pane)} · '
                  '${l10n.shortcutsInactiveRegion}',
          dimmed: active != null && pane != active,
          rows: AppShortcuts.forPane(s, pane).toList(),
        ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s10, 0),
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            Icon(Icons.keyboard_outlined, size: AppSize.iconLg, color: scheme.primary),
            const SizedBox(width: AppSpace.s10),
            Expanded(
              child: Text(
                l10n.shortcutsTitle,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              l10n.shortcutsClose,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: AppSpace.s6),
            const AppKeyLabel(chord: ShortcutKey(LogicalKeyboardKey.escape)),
            const SizedBox(width: AppSpace.s4),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.l10n, required this.scheme});

  final AppLocalizations l10n;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
          AppSpace.s16, AppSpace.s10, AppSpace.s16, AppSpace.s10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.my_location_outlined,
              size: AppSize.iconSm, color: scheme.primary),
          const SizedBox(width: AppSpace.s6),
          Expanded(
            child: Text(
              l10n.shortcutsActiveRegionNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: AppType.proseHeight,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.rows,
    this.subtitle,
    this.dimmed = false,
  });

  final String title;
  final String? subtitle;
  final List<AppShortcut> rows;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.s10, AppSpace.s10, AppSpace.s10, AppSpace.s4),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: scheme.outline,
                      ),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(width: AppSpace.s6),
                Flexible(
                  child: Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: scheme.outline),
                  ),
                ),
              ],
            ],
          ),
        ),
        for (final row in rows)
          _Row(label: shortcutLabel(l10n, row), shortcut: row),
      ],
    );
    return dimmed
        ? Opacity(opacity: AppAlpha.disabled, child: body)
        : body;
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.shortcut});

  final String label;
  final AppShortcut shortcut;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
      child: SizedBox(
        height: 28,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: AppSpace.s10),
            _Keys(shortcut: shortcut),
          ],
        ),
      ),
    );
  }
}

/// The chords, with the two ranges written as ranges.
///
/// `⌘1…8` is eight chords in the table and one thing to a reader; drawing
/// eight badges would be technically true and useless.
class _Keys extends StatelessWidget {
  const _Keys({required this.shortcut});

  final AppShortcut shortcut;

  @override
  Widget build(BuildContext context) {
    final int count = shortcut.keys.length;
    final bool isRange = count > 3 &&
        (shortcut.id == AppShortcutIds.navigateToDestination ||
            shortcut.id == AppShortcutIds.selectWorkbenchTool);
    if (!isRange) return AppShortcutKeys(shortcut);

    final pieces = AppKeyLabel.spell(shortcut.keys.first);
    if (pieces == null) return const SizedBox.shrink();
    final collapsed = <String>[...pieces];
    collapsed[collapsed.length - 1] =
        '${collapsed.last.substring(0, collapsed.last.length - 1)}1…$count';
    return AppKeyBadges(pieces: collapsed);
  }
}

