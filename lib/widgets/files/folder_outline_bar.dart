import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../glass/app_glass.dart';
import '../glass/app_glass_menu.dart';
import '../glass/glass_controls.dart' show measureGlassText;
import '../ui/scroll_edge_fade.dart';

/// One folder of the outline: the chip's text, the folder it stands for,
/// how many files its section holds, and whether the last scan could read it.
@immutable
class FolderOutlineEntry {
  const FolderOutlineEntry({
    required this.path,
    required this.label,
    required this.count,
    this.unreachable = false,
  });

  final String path;
  final String label;
  final int count;
  final bool unreachable;

  @override
  bool operator ==(Object other) =>
      other is FolderOutlineEntry &&
      path == other.path &&
      label == other.label &&
      count == other.count &&
      unreachable == other.unreachable;

  @override
  int get hashCode => Object.hash(path, label, count, unreachable);
}

/// What the bar sits on, which decides its chrome and its inks.
enum FolderOutlineHost {
  /// The gallery on a desktop or tablet window: a second bar-grade glass
  /// under the floating toolbar, same inset, concentric radius (`A1b · 1a`).
  glassBar,

  /// The gallery on a phone: the collapsed chip alone in a small float-grade
  /// glass, because the top bar already spent the bar grade (`1c`).
  glassFloat,

  /// The file browser: fixed chrome under the filter bar, on the column
  /// colour with a hairline beneath — not glass (`1d`).
  opaque,
}

/// How much of the bar fits. Each step is chosen for the whole row at once,
/// so a chip is never half-drawn (`A1b` 宽度降级).
enum FolderOutlineLevel {
  /// Every chip with its count.
  full,

  /// The counts dropped, together.
  noCounts,

  /// Chips scroll sideways under a 24px fade at each end.
  scroll,

  /// One chip — the current folder and `i/n` — opening a menu of the rest.
  collapsed,
}

/// The folder outline (`A1b`): one chip per folder of a grouped view, the
/// one under the top of the viewport lit, a tap scrolling to that folder's
/// header. An index of the section headers, not a filter — tapping changes
/// nothing but the scroll position.
///
/// The bar reads [currentIndex] and nothing else that moves while the user
/// scrolls; the host owns the `FolderOutlineSpy` that feeds it.
class FolderOutlineBar extends StatefulWidget {
  const FolderOutlineBar({
    super.key,
    required this.entries,
    required this.currentIndex,
    required this.onJump,
    required this.host,
    this.onShowOnly,
    this.onRemove,
    this.onReveal,
    this.onReAuthorize,
    this.forceCollapsed = false,
  });

  final List<FolderOutlineEntry> entries;
  final ValueListenable<int> currentIndex;
  final ValueChanged<int> onJump;
  final FolderOutlineHost host;

  /// The chip menu's rows; a null callback leaves its row out.
  final ValueChanged<String>? onShowOnly;
  final ValueChanged<String>? onRemove;
  final ValueChanged<String>? onReveal;
  final ValueChanged<String>? onReAuthorize;

  /// Skip the measured levels and collapse — the phone.
  final bool forceCollapsed;

  /// The bar's outer height in every host: 28 of chip in 6 of padding.
  static const double height = 40;
  static const double chipHeight = AppSize.compact;

  static const double _chipGap = AppSpace.s6;
  static const double _fade = 24;
  static const double _menuWidth = 220;
  static const double _menuWidthPhone = 290;

  static TextStyle labelStyle(BuildContext context, {required bool lit}) => Theme.of(context)
      .textTheme
      .labelMedium!
      .metricsOnly
      .copyWith(fontWeight: lit ? FontWeight.w600 : FontWeight.w500);

  static TextStyle countStyle(BuildContext context) => Theme.of(
    context,
  ).textTheme.labelSmall!.mono.metricsOnly.copyWith(fontWeight: FontWeight.w400);

  /// The width one chip takes, measured at the lit weight so lighting one
  /// never widens the row.
  static double chipWidth(
    BuildContext context,
    FolderOutlineEntry entry, {
    required bool withCount,
  }) {
    final label = measureGlassText(context, entry.label, labelStyle(context, lit: true));
    final count = withCount && !entry.unreachable
        ? AppSpace.s6 + measureGlassText(context, '${entry.count}', countStyle(context))
        : 0.0;
    return (_ChipLayout.padLeft +
            AppSize.iconMd +
            AppSpace.s6 +
            label +
            count +
            _ChipLayout.padRight)
        .ceilToDouble();
  }

  /// The level the row takes at [available] width, in the declared order.
  static FolderOutlineLevel levelFor(
    BuildContext context,
    List<FolderOutlineEntry> entries,
    double available, {
    bool forceCollapsed = false,
  }) {
    if (forceCollapsed || entries.isEmpty) return FolderOutlineLevel.collapsed;
    double sum({required bool withCount}) {
      var w = _chipGap * (entries.length - 1);
      for (final e in entries) {
        w += chipWidth(context, e, withCount: withCount);
      }
      return w;
    }

    if (sum(withCount: true) <= available) return FolderOutlineLevel.full;
    final bare = sum(withCount: false);
    if (bare <= available) return FolderOutlineLevel.noCounts;
    final average = (bare - _chipGap * (entries.length - 1)) / entries.length;
    if (available >= average * 3) return FolderOutlineLevel.scroll;
    return FolderOutlineLevel.collapsed;
  }

  @override
  State<FolderOutlineBar> createState() => _FolderOutlineBarState();
}

class _FolderOutlineBarState extends State<FolderOutlineBar> {
  final ScrollController _scroll = ScrollController();
  List<GlobalKey> _chipKeys = const [];

  @override
  void initState() {
    super.initState();
    _syncKeys();
    widget.currentIndex.addListener(_onCurrentChanged);
  }

  @override
  void didUpdateWidget(FolderOutlineBar old) {
    super.didUpdateWidget(old);
    if (old.entries.length != widget.entries.length) _syncKeys();
    if (!identical(old.currentIndex, widget.currentIndex)) {
      old.currentIndex.removeListener(_onCurrentChanged);
      widget.currentIndex.addListener(_onCurrentChanged);
    }
  }

  @override
  void dispose() {
    widget.currentIndex.removeListener(_onCurrentChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _syncKeys() {
    _chipKeys = List.generate(widget.entries.length, (_) => GlobalKey());
  }

  /// Keeps the lit chip inside the scrolling row's visible span (`③`).
  void _onCurrentChanged() {
    final index = widget.currentIndex.value;
    if (index < 0 || index >= _chipKeys.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _chipKeys[index].currentContext;
      if (!mounted || ctx == null || !_scroll.hasClients) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: AppMotion.durationOf(context, AppMotion.state),
        curve: AppMotion.enter,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final Widget row = LayoutBuilder(
      builder: (context, constraints) {
        final level = FolderOutlineBar.levelFor(
          context,
          widget.entries,
          constraints.maxWidth,
          forceCollapsed: widget.forceCollapsed,
        );
        return AnimatedSwitcher(
          duration: AppMotion.durationOf(context, AppMotion.state),
          switchInCurve: AppMotion.enter,
          switchOutCurve: AppMotion.enter,
          layoutBuilder: (current, previous) =>
              Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
          child: KeyedSubtree(key: ValueKey(level), child: _buildLevel(context, level)),
        );
      },
    );

    final Widget content = Semantics(
      container: true,
      label: l10n.folderOutlineLabel,
      child: SizedBox(height: FolderOutlineBar.chipHeight, child: row),
    );

    final scheme = Theme.of(context).colorScheme;
    switch (widget.host) {
      case FolderOutlineHost.glassBar:
        return AppGlass(
          grade: GlassGrade.bar,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          padding: const EdgeInsets.all(AppSpace.s6),
          child: content,
        );
      case FolderOutlineHost.glassFloat:
        return AppGlass(
          grade: GlassGrade.float,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          padding: const EdgeInsets.all(AppSpace.s6),
          child: content,
        );
      case FolderOutlineHost.opaque:
        return Container(
          height: FolderOutlineBar.height,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: content,
        );
    }
  }

  Widget _buildLevel(BuildContext context, FolderOutlineLevel level) {
    if (level == FolderOutlineLevel.collapsed) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ValueListenableBuilder<int>(
          valueListenable: widget.currentIndex,
          builder: (context, current, _) => _CollapsedChip(
            entries: widget.entries,
            current: current,
            onOpen: (anchor) => _openCollapsedMenu(anchor, current),
          ),
        ),
      );
    }

    final chips = FocusTraversalGroup(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < widget.entries.length; i++) ...[
            if (i > 0) const SizedBox(width: FolderOutlineBar._chipGap),
            ValueListenableBuilder<int>(
              valueListenable: widget.currentIndex,
              builder: (context, current, _) => _OutlineChip(
                key: level == FolderOutlineLevel.scroll ? _chipKeys[i] : null,
                entry: widget.entries[i],
                lit: current == i,
                withCount: level == FolderOutlineLevel.full,
                onGlass: widget.host != FolderOutlineHost.opaque,
                onTap: () => widget.onJump(i),
                onMenu: (position) => _openChipMenu(position, widget.entries[i]),
              ),
            ),
          ],
        ],
      ),
    );

    if (level != FolderOutlineLevel.scroll) {
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: 0,
          maxWidth: double.infinity,
          child: chips,
        ),
      );
    }
    return ScrollEdgeFade(
      axis: Axis.horizontal,
      extent: FolderOutlineBar._fade,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        // The fade is the edge; no glow on top of it.
        physics: const ClampingScrollPhysics(),
        child: chips,
      ),
    );
  }

  Future<void> _openChipMenu(Offset position, FolderOutlineEntry entry) {
    final l10n = AppLocalizations.of(context)!;
    final phone = Responsive.isMobile(context);
    return showAppGlassMenu(
      context,
      position: position,
      width: phone ? FolderOutlineBar._menuWidthPhone : FolderOutlineBar._menuWidth,
      entries: [
        if (entry.unreachable && widget.onReAuthorize != null)
          AppGlassMenuItem(
            icon: Icons.lock_open,
            label: l10n.folderOutlineReauthorize,
            onSelected: () => widget.onReAuthorize!(entry.path),
          )
        else if (widget.onShowOnly != null)
          AppGlassMenuItem(
            icon: Icons.visibility_outlined,
            label: l10n.folderOutlineShowOnly,
            onSelected: () => widget.onShowOnly!(entry.path),
          ),
        if (widget.onRemove != null)
          AppGlassMenuItem(
            icon: Icons.deselect,
            label: l10n.folderOutlineRemove,
            onSelected: () => widget.onRemove!(entry.path),
          ),
        if (widget.onReveal != null)
          AppGlassMenuItem(
            icon: Icons.my_location,
            label: l10n.folderOutlineReveal,
            onSelected: () => widget.onReveal!(entry.path),
          ),
        const AppGlassMenuDivider(),
        AppGlassMenuHeading(
          entry.unreachable
              ? entry.path
              : '${entry.path} · ${l10n.folderOutlineFilesCount(entry.count)}',
        ),
      ],
    );
  }

  Future<void> _openCollapsedMenu(BuildContext anchor, int current) {
    final phone = Responsive.isMobile(context);
    return showAppGlassMenuBelow(
      anchor,
      width: phone ? FolderOutlineBar._menuWidthPhone : FolderOutlineBar._menuWidth,
      entries: [
        for (var i = 0; i < widget.entries.length; i++)
          AppGlassMenuItem(
            icon: i == current
                ? Icons.check
                : widget.entries[i].unreachable
                ? Icons.lock_person
                : Icons.folder_outlined,
            label: widget.entries[i].label,
            trailing: widget.entries[i].unreachable ? null : '${widget.entries[i].count}',
            onSelected: () => widget.onJump(i),
          ),
      ],
    );
  }
}

/// The chip's fixed metrics (`A1b` 规格: 内距 左 8 右 10 · gap 6 · 图标 16).
abstract final class _ChipLayout {
  static const double padLeft = 8;
  static const double padRight = 10;
}

/// The inks a chip draws with on its host: the glass palette's on glass,
/// the scheme's on the column.
({Color ink, Color ink2}) _inksOf(BuildContext context, {required bool onGlass}) {
  final scheme = Theme.of(context).colorScheme;
  final glass = onGlass ? GlassInk.maybeOf(context) : null;
  return (ink: glass?.ink ?? scheme.onSurface, ink2: glass?.ink2 ?? scheme.onSurfaceVariant);
}

class _OutlineChip extends StatefulWidget {
  const _OutlineChip({
    super.key,
    required this.entry,
    required this.lit,
    required this.withCount,
    required this.onGlass,
    required this.onTap,
    required this.onMenu,
  });

  final FolderOutlineEntry entry;
  final bool lit;
  final bool withCount;
  final bool onGlass;
  final VoidCallback onTap;
  final ValueChanged<Offset> onMenu;

  @override
  State<_OutlineChip> createState() => _OutlineChipState();
}

class _OutlineChipState extends State<_OutlineChip> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  /// Opens the menu at the chip itself — the keyboard and long-press cases.
  void _menuHere() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    widget.onMenu(box.localToGlobal(Offset(0, box.size.height + AppSpace.s4)));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      widget.onTap();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.contextMenu ||
        (key == LogicalKeyboardKey.f10 && HardwareKeyboard.instance.isShiftPressed)) {
      _menuHere();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inks = _inksOf(context, onGlass: widget.onGlass);
    final entry = widget.entry;
    final lit = widget.lit;
    final unreachable = entry.unreachable;

    final Color textColor = lit
        ? scheme.onAccentTint
        : unreachable
        ? inks.ink2
        : inks.ink;
    final Color iconColor = lit
        ? scheme.primary
        : unreachable
        ? inks.ink2.withValues(alpha: inks.ink2.a * 0.7)
        : inks.ink2;
    final Color countColor = lit ? scheme.onAccentTint : inks.ink2;

    final Color fill = lit
        ? scheme.accentTint
        : _pressed && !widget.onGlass
        ? inks.ink.withValues(alpha: 0.12)
        : _hovered
        ? inks.ink.withValues(alpha: widget.onGlass ? 0.08 : 0.06)
        : inks.ink.withValues(alpha: 0);

    final radius = BorderRadius.circular(AppRadius.control);

    Widget face = AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.hover),
      curve: AppMotion.quick,
      height: FolderOutlineBar.chipHeight,
      padding: const EdgeInsets.only(left: _ChipLayout.padLeft, right: _ChipLayout.padRight),
      decoration: BoxDecoration(color: fill, borderRadius: radius),
      // The focus ring paints over the face — inset 1px accent, 3px ring
      // outside — rather than in the decoration, where a border would add
      // 2px to a width the row was measured without.
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: _focused ? scheme.primary : Colors.transparent),
        boxShadow: _focused ? [BoxShadow(color: scheme.accentRing, spreadRadius: 3)] : const [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            unreachable ? Icons.lock_person : Icons.folder_outlined,
            size: AppSize.iconMd,
            color: iconColor,
          ),
          const SizedBox(width: AppSpace.s6),
          Text(
            entry.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FolderOutlineBar.labelStyle(context, lit: lit).copyWith(color: textColor),
          ),
          if (widget.withCount && !unreachable) ...[
            const SizedBox(width: AppSpace.s6),
            Text(
              '${entry.count}',
              maxLines: 1,
              style: FolderOutlineBar.countStyle(context).copyWith(color: countColor),
            ),
          ],
        ],
      ),
    );

    // On glass the pressed state is the lens itself, dimmed (`G3 Lens
    // pressed`); on the column it is a darker wash, handled above.
    if (_pressed && widget.onGlass && !lit) {
      face = AppGlass(grade: GlassGrade.lens, pressed: true, borderRadius: radius, child: face);
    }

    return Tooltip(
      message: entry.path,
      waitDuration: const Duration(milliseconds: 600),
      child: Semantics(
        button: true,
        selected: lit,
        label: entry.path,
        child: Focus(
          onKeyEvent: _onKey,
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Listener(
              onPointerDown: (_) => setState(() => _pressed = true),
              onPointerUp: (_) => setState(() => _pressed = false),
              onPointerCancel: (_) => setState(() => _pressed = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                onSecondaryTapUp: (details) => widget.onMenu(details.globalPosition),
                onLongPress: _menuHere,
                child: face,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The collapsed form (`1c`, `1g` 折叠): the current folder in the lit look
/// — it always means "here" — with `i/n` and a chevron, opening the list.
class _CollapsedChip extends StatelessWidget {
  const _CollapsedChip({required this.entries, required this.current, required this.onOpen});

  final List<FolderOutlineEntry> entries;
  final int current;
  final ValueChanged<BuildContext> onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final index = current.clamp(0, entries.length - 1);
    final entry = entries[index];
    return Builder(
      builder: (anchor) => Semantics(
        button: true,
        label: entry.path,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onOpen(anchor),
            child: Container(
              height: FolderOutlineBar.chipHeight,
              padding: const EdgeInsets.symmetric(horizontal: _ChipLayout.padLeft),
              decoration: BoxDecoration(
                color: scheme.accentTint,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              // The label gives way first; below what even the glyph, the
              // count and the chevron need, the chip is clipped rather than
              // thrown — a column that narrow is not a layout to design for.
              clipBehavior: Clip.hardEdge,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const fixed =
                      AppSize.iconMd + AppSpace.s6 + AppSpace.s6 + AppSpace.s4 + AppSize.iconSm;
                  final countWidth = measureGlassText(
                    context,
                    '${index + 1}/${entries.length}',
                    FolderOutlineBar.countStyle(context),
                  );
                  final tight = constraints.maxWidth < fixed + countWidth;
                  final row = _row(context, scheme, entry, index);
                  return tight
                      ? OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: 0,
                          maxWidth: double.infinity,
                          child: row,
                        )
                      : row;
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, ColorScheme scheme, FolderOutlineEntry entry, int index) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          entry.unreachable ? Icons.lock_person : Icons.folder_outlined,
          size: AppSize.iconMd,
          color: scheme.primary,
        ),
        const SizedBox(width: AppSpace.s6),
        Flexible(
          child: Text(
            entry.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FolderOutlineBar.labelStyle(
              context,
              lit: true,
            ).copyWith(color: scheme.onAccentTint),
          ),
        ),
        const SizedBox(width: AppSpace.s6),
        Text(
          '${index + 1}/${entries.length}',
          style: FolderOutlineBar.countStyle(context).copyWith(color: scheme.onAccentTint),
        ),
        const SizedBox(width: AppSpace.s4),
        Icon(Icons.expand_more, size: AppSize.iconSm, color: scheme.onAccentTint),
      ],
    );
  }
}
