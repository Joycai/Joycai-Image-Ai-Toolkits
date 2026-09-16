import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../core/responsive.dart';
import '../../widgets/glass/glass_controls.dart' show measureGlassText;
import '../../widgets/ui/app_disclosure_chevron.dart';

/// What a folder row shows while something is dragged over it (`00d · 1d`).
enum FolderDropTone {
  /// A release moves it here: `--tint` and the accent ring.
  move,

  /// A release copies it here: the success container and ring.
  copy,

  /// This row will not take it: the error container and ring.
  reject,
}

/// Whether a tree row draws a disclosure chevron, and which way it points.
///
/// A row with no disclosure *slot* at all — a fixed node such as All Sources —
/// passes null instead of [none].
enum TreeDisclosure {
  /// The slot is kept, empty, so a leaf's name lines up with its siblings'.
  none,
  collapsed,
  expanded,
  loading,
}

/// The geometry of one row of the folder column: `A1 1a` under a pointer,
/// `A1 1e`'s drawer below the phone breakpoint.
///
/// Shared by the source tree, the result tree and the fixed nodes above them,
/// so the three read as one list.
@immutable
class FolderTreeMetrics {
  const FolderTreeMetrics._({
    required this.touch,
    required this.height,
    required this.margin,
    required this.padding,
    required this.gap,
    required this.fixedGap,
    required this.icon,
    required this.markerBox,
    required this.markerGap,
    required this.markerDensity,
    required this.headerInset,
  });

  /// Whether this is the phone drawer's variant.
  final bool touch;

  /// Row height: 32, or 44 for a finger.
  final double height;

  /// Horizontal gap between the row's ground and the column's edge.
  final double margin;

  /// Horizontal padding inside the ground, before any indent.
  final double padding;

  /// Gap between a row's pieces when it has a disclosure slot.
  final double gap;

  /// Gap between a fixed node's icon and label (`1a`: 8 there, 6 in the tree).
  final double fixedGap;

  /// The row's leading glyph.
  final double icon;

  /// The square the checkbox (or its blank stand-in) occupies.
  final double markerBox;

  /// Space after the marker. The checkbox's box already pads its glyph.
  final double markerGap;

  final VisualDensity markerDensity;

  /// Horizontal inset of a group caption.
  final double headerInset;

  /// Content indent per nesting level (`A1` `srcFolders`: 10 → 26).
  static const double indentStep = 16;

  /// The chevron glyph, and the width its slot reserves.
  static const double disclosureSize = AppSize.iconSm;

  static const FolderTreeMetrics _pointer = FolderTreeMetrics._(
    touch: false,
    height: AppSize.control,
    margin: AppSpace.s6,
    padding: AppSpace.s10,
    gap: AppSpace.s6,
    fixedGap: 8,
    icon: AppSize.iconMd,
    markerBox: 24,
    markerGap: 2,
    markerDensity: VisualDensity(
      horizontal: VisualDensity.minimumDensity,
      vertical: VisualDensity.minimumDensity,
    ),
    headerInset: AppSpace.s16,
  );

  static const FolderTreeMetrics _touch = FolderTreeMetrics._(
    touch: true,
    height: AppSize.touch,
    margin: 8,
    padding: 12,
    gap: AppSpace.s10,
    fixedGap: AppSpace.s10,
    icon: AppSize.iconLg,
    markerBox: 32,
    markerGap: 0,
    markerDensity: VisualDensity.compact,
    headerInset: 18,
  );

  /// A touch tablet keeps the pointer geometry at a finger's 40
  /// (`B1a · 1c`: drawer rows 40).
  static const FolderTreeMetrics _tablet = FolderTreeMetrics._(
    touch: false,
    height: AppSize.large,
    margin: AppSpace.s6,
    padding: AppSpace.s10,
    gap: AppSpace.s6,
    fixedGap: 8,
    icon: AppSize.iconMd,
    markerBox: 24,
    markerGap: 2,
    markerDensity: VisualDensity(
      horizontal: VisualDensity.minimumDensity,
      vertical: VisualDensity.minimumDensity,
    ),
    headerInset: AppSpace.s16,
  );

  static FolderTreeMetrics of(BuildContext context) {
    if (Responsive.isMobile(context)) return _touch;
    if (Platform.isAndroid || Platform.isIOS) return _tablet;
    return _pointer;
  }

  /// The row's name: 13, or the drawer's 14.
  TextStyle labelStyle(TextTheme textTheme) =>
      (touch ? textTheme.bodyLarge : textTheme.bodyMedium) ?? const TextStyle();

  /// A row's count: mono 11 (12 in the drawer) at regular weight, untracked.
  TextStyle countStyle(TextTheme textTheme) =>
      ((touch ? textTheme.bodySmall : textTheme.labelSmall) ?? const TextStyle())
          .mono
          .copyWith(fontWeight: FontWeight.w400, letterSpacing: 0);
}

/// One row of the folder column — `A1 1a`.
///
/// Draws its own ground (selected wash, hover wash, drop-target edge) inside
/// the margin its caller gives it, so a drop target wrapped around it frames
/// the ground and not the gutter.
class FolderTreeRow extends StatefulWidget {
  const FolderTreeRow({
    super.key,
    required this.icon,
    required this.label,
    this.depth = 0,
    this.disclosure,
    this.onToggle,
    this.marker,
    this.iconColor,
    this.labelColor,
    this.count,
    this.hoverAction,
    this.editor,
    this.selected = false,
    this.dropTone,
    this.dropNote,
    this.onTap,
    this.onSecondaryTapDown,
  });

  final IconData icon;
  final String label;
  final int depth;

  /// Null for a row with no disclosure slot at all.
  final TreeDisclosure? disclosure;

  final VoidCallback? onToggle;

  /// Drawn between the chevron and the icon — the tree's checkbox.
  final Widget? marker;

  /// Overrides the icon's colour, which otherwise follows [selected]. A
  /// [dropTone] outranks it.
  final Color? iconColor;

  /// Overrides the label's colour, which otherwise follows [selected]. A
  /// [dropTone] outranks it.
  final Color? labelColor;

  final String? count;

  /// Revealed while the row is hovered or selected, and always on a phone.
  final Widget? hoverAction;

  /// Replaces the label, count and action — the in-row name field.
  final Widget? editor;

  final bool selected;

  /// Something is dragged over this row (`00d · 1d`): what a release does,
  /// or that it is refused. Null at rest.
  final FolderDropTone? dropTone;

  /// The destination wording or the reason for a refusal, set at the row's
  /// end in place of the count and action — while the row has room for it
  /// beside the name.
  final String? dropNote;

  final VoidCallback? onTap;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  State<FolderTreeRow> createState() => _FolderTreeRowState();
}

class _FolderTreeRowState extends State<FolderTreeRow> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered != value) setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final metrics = FolderTreeMetrics.of(context);
    final duration = AppMotion.durationOf(context, AppMotion.hover);
    final selected = widget.selected;
    final editing = widget.editor != null;

    // In an editing row the leading pieces sit level with the 32px field
    // rather than centred on a row the error line may have made taller.
    final double band = editing ? AppSize.control : metrics.height;
    final double gap = widget.disclosure == null ? metrics.fixedGap : metrics.gap;

    // `00d · 1d`: the ground, ring and ink of a row something is dragged over.
    // Move is `--tint` under the accent ring and the deep ink; copy swaps the
    // set for the success colours, a refusal for the error colours.
    final semantic = context.semantic;
    final (Color? dropGround, Color? dropEdge, Color? dropInk) = switch (widget.dropTone) {
      null => (null, null, null),
      FolderDropTone.move => (colorScheme.accentTint, colorScheme.primary, colorScheme.onAccentTint),
      FolderDropTone.copy => (semantic.successContainer, semantic.success, semantic.onSuccessContainer),
      FolderDropTone.reject => (colorScheme.errorContainer, colorScheme.error, colorScheme.onErrorContainer),
    };

    final Color ground = dropGround ??
        (selected
            ? colorScheme.accentTint
            : (_hovered && !editing
                ? colorScheme.onSurface.withValues(alpha: 0.06)
                : colorScheme.onSurface.withValues(alpha: 0)));
    final Color iconColor =
        dropEdge ?? widget.iconColor ?? (selected ? colorScheme.primary : colorScheme.onSurfaceVariant);
    final Color labelColor =
        dropInk ?? widget.labelColor ?? (selected ? colorScheme.onAccentTint : colorScheme.onSurface);
    final Color countColor = selected ? colorScheme.onAccentTint : colorScheme.onSurfaceVariant;

    final bool showAction =
        _hovered || selected || metrics.touch || Platform.isIOS || Platform.isAndroid;

    final children = <Widget>[
      if (widget.disclosure != null) _disclosure(colorScheme, band, gap),
      if (widget.marker != null) ...[
        SizedBox(height: band, child: Center(child: widget.marker)),
        if (metrics.markerGap > 0) SizedBox(width: metrics.markerGap),
      ],
      SizedBox(
        height: band,
        child: Center(child: Icon(widget.icon, size: metrics.icon, color: iconColor)),
      ),
      SizedBox(width: gap),
      if (editing)
        Expanded(child: widget.editor!)
      else if (widget.dropNote != null && dropInk != null)
        Expanded(
          child: _DropNoteSlot(
            label: widget.label,
            labelStyle: metrics.labelStyle(theme.textTheme).copyWith(color: labelColor),
            note: widget.dropNote!,
            ink: dropInk,
            gap: gap,
          ),
        )
      else ...[
        Expanded(
          child: Text(
            widget.label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: metrics.labelStyle(theme.textTheme).copyWith(
                  color: labelColor,
                  fontWeight: selected ? FontWeight.w500 : null,
                ),
          ),
        ),
        if (widget.count != null) ...[
          SizedBox(width: gap),
          Text(widget.count!, style: metrics.countStyle(theme.textTheme).copyWith(color: countColor)),
        ],
        if (widget.hoverAction != null) ...[
          const SizedBox(width: AppSpace.s4),
          ExcludeSemantics(
            excluding: !showAction,
            child: IgnorePointer(
              ignoring: !showAction,
              child: AnimatedOpacity(
                opacity: showAction ? 1 : 0,
                duration: duration,
                curve: AppMotion.quick,
                child: widget.hoverAction,
              ),
            ),
          ),
        ],
      ],
    ];

    final double vertical = editing ? AppSpace.s4 : 0;
    final body = AnimatedContainer(
      duration: duration,
      curve: AppMotion.quick,
      constraints: BoxConstraints(minHeight: metrics.height),
      padding: EdgeInsets.fromLTRB(
        metrics.padding + widget.depth * FolderTreeMetrics.indentStep,
        vertical,
        metrics.padding,
        vertical,
      ),
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      // Foreground, so the edge does not push the content over by its width;
      // drawn inside the ground (`outline-offset: -2`), so it frames the row
      // and not the gutter. Always 2px, only the colour changes, so the M1
      // transition fades the ring rather than growing it.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: dropEdge ?? colorScheme.primary.withValues(alpha: 0),
          width: 2,
        ),
      ),
      child: Row(
        crossAxisAlignment: editing ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: children,
      ),
    );

    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: Semantics(
        button: widget.onTap != null,
        selected: selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onSecondaryTapDown: widget.onSecondaryTapDown,
          child: body,
        ),
      ),
    );
  }

  Widget _disclosure(ColorScheme colorScheme, double band, double gap) {
    final disclosure = widget.disclosure!;
    final Widget glyph = switch (disclosure) {
      TreeDisclosure.none => const SizedBox.shrink(),
      TreeDisclosure.loading => SizedBox.square(
          dimension: 10,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: colorScheme.outline),
        ),
      TreeDisclosure.collapsed || TreeDisclosure.expanded => AppDisclosureChevron(
          open: disclosure == TreeDisclosure.expanded,
          size: FolderTreeMetrics.disclosureSize,
          color: colorScheme.outline,
        ),
    };

    // The gap after the chevron is part of its hit area: a 14px glyph alone
    // is too small a target.
    final slot = SizedBox(
      width: FolderTreeMetrics.disclosureSize + gap,
      height: band,
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox.square(
          dimension: FolderTreeMetrics.disclosureSize,
          child: Center(child: glyph),
        ),
      ),
    );

    final interactive = widget.onToggle != null &&
        (disclosure == TreeDisclosure.collapsed || disclosure == TreeDisclosure.expanded);
    if (!interactive) return slot;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggle,
        child: slot,
      ),
    );
  }
}

/// A small glyph action at the end of a [FolderTreeRow] — remove a folder
/// from the list.
///
/// No ink: the row paints its own ground above the nearest [Material], which
/// would hide a splash. The glyph darkens on hover instead.
class FolderTreeRowAction extends StatefulWidget {
  const FolderTreeRowAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<FolderTreeRowAction> createState() => _FolderTreeRowActionState();
}

class _FolderTreeRowActionState extends State<FolderTreeRowAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final metrics = FolderTreeMetrics.of(context);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Semantics(
          button: true,
          label: widget.tooltip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: SizedBox.square(
              dimension: metrics.touch ? AppSize.control : 20,
              child: Center(
                child: Icon(
                  widget.icon,
                  size: AppSize.iconSm,
                  color: _hovered ? colorScheme.onSurface : colorScheme.outline,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A folder row's name with the drop wording at its end (`00d · 1d`): 「移动到
/// X」, 「复制 12 项到 X」, or the reason for a refusal, on a small panel chip.
///
/// The chip takes the room the name does not need, down to half the slot;
/// past that the name matters more, and the follower already says what a
/// release does. Measured, so the rule holds in every language. Either way
/// the wording is announced.
class _DropNoteSlot extends StatelessWidget {
  const _DropNoteSlot({
    required this.label,
    required this.labelStyle,
    required this.note,
    required this.ink,
    required this.gap,
  });

  final String label;
  final TextStyle labelStyle;
  final String note;
  final Color ink;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noteStyle = theme.textTheme.labelSmall!.copyWith(
      color: ink,
      fontWeight: FontWeight.w500,
      height: AppType.tightHeight,
    );
    final name = Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: labelStyle);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double chipWidth = (measureGlassText(context, note, noteStyle) + AppSpace.s6 * 2).ceilToDouble();
        final double nameWidth = measureGlassText(context, label, labelStyle);
        final double room = constraints.maxWidth - chipWidth - gap;
        final bool fits = room >= math.min(nameWidth, constraints.maxWidth / 2);

        if (!fits) {
          return Row(
            children: [
              Expanded(child: name),
              Semantics(liveRegion: true, label: note),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: name),
            SizedBox(width: gap),
            Semantics(
              liveRegion: true,
              child: Container(
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(note, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: noteStyle),
              ),
            ),
          ],
        );
      },
    );
  }
}
