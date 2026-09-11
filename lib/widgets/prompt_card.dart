import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../core/app_theme.dart';
import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../l10n/app_localizations.dart';
import '../models/prompt.dart';
import '../models/tag.dart';
import 'glass/glass_controls.dart';

/// One action a [PromptCard] offers — drawn as a 28px glyph when the card has
/// room, and as a row of its overflow menu when it does not.
@immutable
class PromptCardAction {
  const PromptCardAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;

  /// Null draws the action disabled.
  final VoidCallback? onPressed;
  final bool danger;
}

/// A prompt in the library's list (`C1 · 1a` 卡片).
///
/// An opaque panel card at r10 with a hairline: an optional leading grip,
/// type glyph or selection circle, then the title with its category chips on
/// one line and two lines of the content under it, and the move glyphs (up,
/// down, top, bottom) at the trailing edge. Tapping discloses the whole
/// prompt; in selection mode the card is the checkbox.
///
/// Category chips carry the category's identity colour as a 6px dot only —
/// never as a fill, which would read as a state.
class PromptCard extends StatelessWidget {
  final Prompt prompt;
  final bool isExpanded;
  final VoidCallback onToggle;

  /// Extra trailing widgets, drawn inline after [menuActions].
  final List<Widget>? actions;

  /// A leading widget after the grip — a template's type glyph.
  final Widget? leading;
  final bool showCategory;

  /// Move one place up / down, and to the top / bottom (`00d` 行尾菜单). The
  /// four are drawn together once any of them is given; a null one is drawn
  /// disabled — the card is already at that end — so the row does not shift.
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onMoveToTop;
  final VoidCallback? onMoveToBottom;

  /// The drag grip at the leading edge. Hidden in [selectionMode].
  final Widget? dragHandle;

  /// Draws the selection circle in place of the grip, and hides the actions.
  final bool selectionMode;

  /// Whether this card is one of the selection.
  final bool selected;

  /// A small badge after the title — a template's type.
  final Widget? badge;

  final VoidCallback? onLongPress;

  /// Copy, edit, delete and the like.
  final List<PromptCardAction> menuActions;

  const PromptCard({
    super.key,
    required this.prompt,
    required this.isExpanded,
    required this.onToggle,
    this.actions,
    this.leading,
    this.showCategory = true,
    this.onMoveUp,
    this.onMoveDown,
    this.onMoveToTop,
    this.onMoveToBottom,
    this.dragHandle,
    this.selectionMode = false,
    this.selected = false,
    this.badge,
    this.onLongPress,
    this.menuActions = const [],
  });

  /// Width of one trailing glyph.
  static const double _action = AppSize.compact;

  /// What the title and its chips are never squeezed below before the actions
  /// fold into the menu. A floor for the text column, not a breakpoint.
  static const double _minContent = 200;

  static const double _padH = 14;
  static const double _padV = 12;
  static const double _gap = 12;

  /// The grip's own width.
  static const double _grip = 20;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final phone = Responsive.isMobile(context);
    final radius = BorderRadius.circular(AppRadius.control);

    final double borderWidth = selected ? 2 : 1;
    final Color borderColor = selected
        ? scheme.primary
        : isExpanded
            ? scheme.accentRing
            : scheme.outlineVariant;
    // The selected edge is a pixel heavier; the inset gives that pixel back so
    // the content does not shift when a card is picked.
    final inset = borderWidth - 1;
    // `00d · 1f`: on a phone the grip is hit across the card's leading inset
    // too, so the row starts at the card's edge and the grip takes the inset.
    final double? gripInset = phone && !selectionMode && dragHandle != null ? _padH - inset : null;

    return AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.hover),
      curve: AppMotion.quick,
      decoration: BoxDecoration(
        color: selected ? scheme.accentTint : scheme.surface,
        borderRadius: radius,
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onToggle,
          onLongPress: onLongPress,
          child: Padding(
            padding: gripInset != null
                ? EdgeInsetsDirectional.fromSTEB(0, _padV - inset, _padH - inset, _padV - inset)
                : EdgeInsets.symmetric(horizontal: _padH - inset, vertical: _padV - inset),
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  _buildBody(context, scheme, constraints.maxWidth, phone, gripInset),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme scheme, double width, bool phone, double? gripInset) {
    final l10n = AppLocalizations.of(context)!;
    final showActions = !selectionMode;

    // `00d · 1f` 左侧 44 宽命中区: the grip is picked up anywhere across the
    // card's leading inset, the grip and the gap after it (46), while the glyph
    // stays exactly where it was drawn — the handle is laid out centred on the
    // glyph, running past the hit-tested slot by the inset's excess over the
    // gap.
    final Widget? wideGrip = gripInset == null
        ? null
        : SizedBox(
            width: gripInset + _grip + _gap,
            height: AppSize.compact,
            child: OverflowBox(
              minWidth: 2 * gripInset + _grip,
              maxWidth: 2 * gripInset + _grip,
              alignment: AlignmentDirectional.centerStart,
              child: dragHandle,
            ),
          );

    final lead = <Widget>[
      if (selectionMode) _SelectionCircle(selected: selected) else if (wideGrip == null) ?dragHandle,
      ?leading,
    ];
    final leadWidth = (wideGrip != null ? gripInset! + _grip + _gap : 0.0) +
        (selectionMode || (dragHandle != null && wideGrip == null) ? _grip : 0.0) +
        (leading != null ? AppSize.compact : 0.0) +
        _gap * lead.length;

    final bool hasMoves = onMoveUp != null || onMoveDown != null || onMoveToTop != null || onMoveToBottom != null;
    final moves = <PromptCardAction>[
      if (hasMoves) ...[
        PromptCardAction(icon: Icons.keyboard_arrow_up_rounded, label: l10n.moveUp, onPressed: onMoveUp),
        PromptCardAction(icon: Icons.keyboard_arrow_down_rounded, label: l10n.moveDown, onPressed: onMoveDown),
        PromptCardAction(icon: Icons.vertical_align_top_rounded, label: l10n.moveToTop, onPressed: onMoveToTop),
        PromptCardAction(icon: Icons.vertical_align_bottom_rounded, label: l10n.moveToBottom, onPressed: onMoveToBottom),
      ],
    ];
    final moveCount = moves.length;
    final extraCount = actions?.length ?? 0;
    final inlineWidth = (menuActions.length + moveCount + extraCount) * _action +
        (menuActions.isNotEmpty && moveCount > 0 ? GlassDivider.extent : 0);
    final hasTrailing = showActions && (menuActions.isNotEmpty || moveCount > 0 || extraCount > 0);
    final inline = !phone && width - leadWidth - _gap - inlineWidth >= _minContent;

    final trailing = <Widget>[];
    if (hasTrailing) {
      if (inline) {
        for (final a in menuActions) {
          trailing.add(_ActionGlyph(icon: a.icon, tooltip: a.label, danger: a.danger, onPressed: a.onPressed));
        }
        if (menuActions.isNotEmpty && moveCount > 0) {
          trailing.add(const GlassDivider(height: 16));
        }
        for (final m in moves) {
          trailing.add(_ActionGlyph(icon: m.icon, tooltip: m.label, onPressed: m.onPressed));
        }
      } else {
        trailing.add(_OverflowMenu(
          actions: [...menuActions, ...moves],
          dividerAt: menuActions.isNotEmpty && moveCount > 0 ? menuActions.length : null,
        ));
      }
      if (actions != null) trailing.addAll(actions!);
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTitleLine(context, scheme, phone),
        if (showCategory && phone && prompt.tags.isNotEmpty) ...[
          const SizedBox(height: AppSpace.s6),
          Wrap(
            spacing: AppSpace.s4,
            runSpacing: AppSpace.s4,
            children: [for (final t in prompt.tags) _TagChip(tag: t)],
          ),
        ],
        if (!isExpanded) ...[
          const SizedBox(height: AppSpace.s4),
          Text(
            prompt.content.replaceAll('\n', ' '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: (phone ? Theme.of(context).textTheme.bodyMedium : Theme.of(context).textTheme.bodySmall)
                ?.copyWith(color: scheme.onSurfaceVariant, height: AppType.proseHeight),
          ),
        ],
      ],
    );

    final row = Row(
      children: [
        ?wideGrip,
        for (final w in lead) ...[w, const SizedBox(width: _gap)],
        Expanded(child: content),
        if (trailing.isNotEmpty) ...[
          const SizedBox(width: _gap),
          ...trailing,
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        ClipRect(
          child: AnimatedSize(
            duration: AppMotion.durationOf(context, AppMotion.reveal),
            curve: AppMotion.enter,
            alignment: Alignment.topCenter,
            child: isExpanded
                ? Padding(
                    padding: EdgeInsetsDirectional.only(top: AppSpace.s10, start: leadWidth),
                    child: _buildExpandedContent(context, scheme),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ),
      ],
    );
  }

  Widget _buildTitleLine(BuildContext context, ColorScheme scheme, bool phone) {
    final base = phone ? Theme.of(context).textTheme.titleMedium! : Theme.of(context).textTheme.bodyMedium!;
    final titleStyle = base.copyWith(
      fontWeight: FontWeight.w600,
      color: selected ? scheme.onAccentTint : scheme.onSurface,
    );
    final title = Text(prompt.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle);
    final chipsInline = showCategory && !phone && prompt.tags.isNotEmpty;

    if (badge == null && !chipsInline) return title;

    // Title and chips share the line in proportion to what each needs, so a
    // short title leaves the chips room and a long one yields only its share.
    final titleWidth = measureGlassText(context, prompt.title, titleStyle);
    final chipsWidth = chipsInline ? _TagChip.lineWidth(context, prompt.tags) : 0.0;

    return Row(
      children: [
        Flexible(flex: math.max(1, titleWidth.round()), child: title),
        if (badge != null) ...[
          const SizedBox(width: 8),
          badge!,
        ],
        if (chipsInline) ...[
          const SizedBox(width: 8),
          Flexible(
            flex: math.max(1, chipsWidth.round()),
            child: _TagChipLine(tags: prompt.tags),
          ),
        ],
      ],
    );
  }

  Widget _buildExpandedContent(BuildContext context, ColorScheme scheme) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: prompt.isMarkdown
          ? SelectionArea(
              child: MarkdownBody(
                data: prompt.content,
                styleSheet: MarkdownStyleSheet(
                  p: textTheme.bodyMedium?.copyWith(height: AppType.looseHeight, color: scheme.onSurface),
                  code: TextStyle(backgroundColor: scheme.surfaceContainerHighest).mono,
                ),
              ),
            )
          : SelectionArea(
              child: Text(
                prompt.content,
                style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: AppType.looseHeight),
              ),
            ),
    );
  }
}

/// The 20px selection circle: a hairline ring when not chosen, the solid
/// accent with a check when chosen.
class _SelectionCircle extends StatelessWidget {
  const _SelectionCircle({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.hover),
      curve: AppMotion.quick,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? scheme.primary : Colors.transparent,
        border: selected ? null : Border.all(color: scheme.outlineVariant, width: 1.5),
      ),
      child: selected ? Icon(Icons.check, size: AppSize.iconSm, color: scheme.onPrimary) : null,
    );
  }
}

/// A 28px trailing glyph in the secondary ink (the error colour when [danger]).
class _ActionGlyph extends StatelessWidget {
  const _ActionGlyph({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;

  /// Null draws the glyph disabled.
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = danger ? scheme.error : scheme.onSurfaceVariant;
    return SizedBox(
      width: PromptCard._action,
      height: PromptCard._action,
      child: IconButton(
        icon: Icon(icon, size: AppSize.iconMd),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          foregroundColor: ink,
          disabledForegroundColor: ink.withValues(alpha: AppAlpha.disabled),
          minimumSize: const Size(PromptCard._action, PromptCard._action),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        ),
        onPressed: onPressed,
      ),
    );
  }
}

/// The card's actions folded into one menu, for a card too narrow to show
/// them as glyphs.
class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({required this.actions, this.dividerAt});

  final List<PromptCardAction> actions;

  /// A divider before the action at this index.
  final int? dividerAt;

  PopupMenuItem<int> _item(BuildContext context, ColorScheme scheme, int i) {
    final action = actions[i];
    final enabled = action.onPressed != null;
    Color ink(Color c) => enabled ? c : c.withValues(alpha: AppAlpha.disabled);
    return PopupMenuItem<int>(
      value: i,
      enabled: enabled,
      height: AppSize.large,
      child: Row(
        children: [
          Icon(
            action.icon,
            size: AppSize.iconMd,
            color: ink(action.danger ? scheme.error : scheme.onSurfaceVariant),
          ),
          const SizedBox(width: AppSpace.s10),
          Text(
            action.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: ink(action.danger ? scheme.error : scheme.onSurface),
                ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      width: PromptCard._action,
      height: PromptCard._action,
      child: PopupMenuButton<int>(
        tooltip: l10n.more,
        padding: EdgeInsets.zero,
        iconSize: AppSize.iconLg,
        icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
        onSelected: (i) => actions[i].onPressed?.call(),
        itemBuilder: (context) => [
          for (int i = 0; i < actions.length; i++) ...[
            if (i == dividerAt) const PopupMenuDivider(),
            _item(context, scheme, i),
          ],
        ],
      ),
    );
  }
}

/// A category chip on a card: r4, a hairline, a 6px identity dot, 11px
/// secondary ink.
class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag});

  final PromptTag tag;

  static const double _spacing = AppSpace.s4;

  static TextStyle _style(BuildContext context) => Theme.of(context).textTheme.labelSmall!;

  /// Border 1 + pad 8 + dot 6 + gap 4 … pad 8 + border 1.
  static double widthOf(BuildContext context, PromptTag tag) =>
      (1 + 8 + 6 + 4 + measureGlassText(context, tag.name, _style(context)) + 8 + 1).ceilToDouble();

  static double lineWidth(BuildContext context, List<PromptTag> tags) {
    double w = 0;
    for (int i = 0; i < tags.length; i++) {
      w += widthOf(context, tags[i]) + (i > 0 ? _spacing : 0);
    }
    return w;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 6,
            height: 6,
            child: DecoratedBox(decoration: BoxDecoration(color: Color(tag.color), shape: BoxShape.circle)),
          ),
          const SizedBox(width: 4),
          Text(tag.name, maxLines: 1, style: _style(context).copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// As many whole chips as the width allows, then a mono `+n` for the rest.
class _TagChipLine extends StatelessWidget {
  const _TagChipLine({required this.tags});

  final List<PromptTag> tags;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scheme = Theme.of(context).colorScheme;
        final moreStyle = Theme.of(context).textTheme.labelSmall!.mono.copyWith(color: scheme.outline);
        final max = constraints.maxWidth;

        final shown = <PromptTag>[];
        double used = 0;
        for (int i = 0; i < tags.length; i++) {
          final w = _TagChip.widthOf(context, tags[i]) + (shown.isEmpty ? 0 : _TagChip._spacing);
          final remaining = tags.length - i - 1;
          final reserve = remaining > 0
              ? _TagChip._spacing + measureGlassText(context, '+$remaining', moreStyle)
              : 0.0;
          if (used + w + reserve > max) break;
          shown.add(tags[i]);
          used += w;
        }
        final hidden = tags.length - shown.length;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < shown.length; i++) ...[
              if (i > 0) const SizedBox(width: _TagChip._spacing),
              _TagChip(tag: shown[i]),
            ],
            if (hidden > 0) ...[
              if (shown.isNotEmpty) const SizedBox(width: _TagChip._spacing),
              Flexible(
                child: Text('+$hidden', maxLines: 1, overflow: TextOverflow.clip, style: moreStyle),
              ),
            ],
          ],
        );
      },
    );
  }
}
