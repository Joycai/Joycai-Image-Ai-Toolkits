import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/constants.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/llm_channel.dart';
import '../../../widgets/models/channel_avatar.dart';
import '../../../widgets/models/model_tag_chip.dart';

/// What a channel row shows at its right edge while hovered.
enum ChannelHandle {
  /// Nothing — a single channel has nothing to be reordered against.
  none,

  /// The drag grip (`D1a · 1b` 悬停).
  drag,

  /// The lock a filtered rail shows in the grip's place (`1b` 边界).
  locked,
}

/// Marks a subtree as the lifted proxy of a channel drag, with how far the
/// lift has ramped in.
class ChannelDragLift extends InheritedWidget {
  const ChannelDragLift({super.key, required this.progress, required super.child});

  final double progress;

  static double? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChannelDragLift>()?.progress;

  @override
  bool updateShouldNotify(ChannelDragLift oldDelegate) => oldDelegate.progress != progress;
}

/// The `proxyDecorator` for a reorderable channel list: the row paints its own
/// lifted form (panel ground, 1px accent edge, `0 12 28` shadow, grip in the
/// accent) once it finds a [ChannelDragLift] above it.
///
/// Painted by the row rather than wrapped around it here, because the list
/// item carries the row's 4px bottom margin and a decoration around the item
/// would include it.
Widget channelDragProxy(Widget child, int index, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) => ChannelDragLift(
      progress: AppMotion.quick.transform(animation.value),
      child: Material(type: MaterialType.transparency, child: child),
    ),
  );
}

/// [ReorderableDelayedDragStartListener] at 300 ms instead of the framework's
/// 500 ms long-press timeout: half a second of holding still before a row
/// lifts reads as the app not having noticed the touch.
class ChannelLongPressDragListener extends ReorderableDelayedDragStartListener {
  const ChannelLongPressDragListener({
    super.key,
    required super.index,
    required super.child,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() => DelayedMultiDragGestureRecognizer(
        delay: const Duration(milliseconds: 300),
        debugOwner: this,
      );
}

/// One channel (`D1a · 1a`): the identity plate, the name, and a subline
/// pairing the channel's own tag with its model count.
///
/// Hover is the row's own state, never the screen's: on the screen it rebuilt
/// both columns on every pointer crossing. At rest a draggable row and a
/// locked or single one are pixel-identical (`1b`) — the grip slot is always
/// reserved and only filled on hover.
class ChannelRow extends StatefulWidget {
  const ChannelRow({
    super.key,
    required this.channel,
    required this.modelCount,
    this.selected = false,
    this.dense = false,
    this.filled = false,
    this.handle = ChannelHandle.none,
    this.onTap,
    this.onContextMenu,
    this.trailing,
  });

  final LLMChannel channel;
  final int modelCount;
  final bool selected;

  /// The tablet row: 52 tall with a 28 plate (`1c`).
  final bool dense;

  /// Paints the panel ground and a hairline at rest — for rows laid straight
  /// on the window backdrop (the phone tab) rather than on a column.
  final bool filled;

  final ChannelHandle handle;
  final VoidCallback? onTap;

  /// Right-click, with the pointer's global position.
  final ValueChanged<Offset>? onContextMenu;

  /// A trailing control in place of the grip slot — the phone row's ⋮.
  final Widget? trailing;

  @override
  State<ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends State<ChannelRow> {
  bool _hovering = false;
  bool _handleHovering = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final channel = widget.channel;

    final double? lift = ChannelDragLift.maybeOf(context);
    final bool lifted = lift != null;
    final bool selected = widget.selected && !lifted;

    final Color background = lifted
        ? scheme.surface
        : selected
            ? scheme.accentTint
            : _hovering
                ? scheme.surfaceContainer
                : (widget.filled ? scheme.surface : Colors.transparent);
    final BorderSide side = lifted || selected
        ? BorderSide(color: scheme.primary)
        : (widget.filled ? BorderSide(color: scheme.outlineVariant) : BorderSide.none);
    final radius = BorderRadius.circular(AppRadius.control);

    final bool showHandle = widget.handle != ChannelHandle.none && (_hovering || lifted);
    final bool locked = widget.handle == ChannelHandle.locked;
    final Color handleColor = locked
        ? scheme.outline
        : (lifted || _handleHovering ? scheme.primary : scheme.onSurfaceVariant);

    final String? tag = channel.tag;
    final Widget subline = Row(
      children: [
        if (tag != null && tag.isNotEmpty) ...[
          Flexible(
            child: ModelTagChip(
              tag,
              color: Color(channel.tagColor ?? AppConstants.defaultTagColor),
              uppercase: false,
              mono: true,
            ),
          ),
          const SizedBox(width: AppSpace.s6),
        ],
        Flexible(
          child: Text(
            l10n.countModels(widget.modelCount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.mono.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );

    final Widget handleSlot = SizedBox(
      width: AppSize.iconMd,
      child: showHandle
          ? MouseRegion(
              onEnter: (_) => setState(() => _handleHovering = true),
              onExit: (_) => setState(() => _handleHovering = false),
              child: Tooltip(
                message: locked ? l10n.reorderDisabledWhileFiltered : l10n.channelReorderHandleTooltip,
                child: Icon(
                  locked ? Icons.lock_outline : Icons.drag_indicator,
                  size: AppSize.iconMd,
                  color: handleColor,
                ),
              ),
            )
          : null,
    );

    final content = Padding(
      padding: const EdgeInsets.only(left: AppSpace.s10, right: 8),
      child: Row(
        children: [
          ChannelAvatar(channel, size: widget.dense ? AppSize.compact : AppSize.control),
          const SizedBox(width: AppSpace.s10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    color: selected ? scheme.onAccentTint : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                subline,
              ],
            ),
          ),
          const SizedBox(width: AppSpace.s6),
          if (widget.trailing != null) widget.trailing! else handleSlot,
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: lifted
            ? [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.28 * lift),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(borderRadius: radius, side: side),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onSecondaryTapUp: widget.onContextMenu == null
              ? null
              : (details) => widget.onContextMenu!(details.globalPosition),
          onHover: (hovering) {
            if (hovering != _hovering) setState(() => _hovering = hovering);
          },
          hoverColor: Colors.transparent,
          mouseCursor: widget.handle == ChannelHandle.drag ? SystemMouseCursors.grab : SystemMouseCursors.click,
          child: SizedBox(height: widget.dense ? 52 : 56, child: content),
        ),
      ),
    );
  }
}

/// The 48px entry to fee management pinned under the channel list (`D1a ·
/// 1a` 左栏底): payments glyph, the label, the group count, a chevron.
class FeeManagementEntry extends StatelessWidget {
  const FeeManagementEntry({
    super.key,
    required this.groupCount,
    required this.onTap,
    this.filled = false,
  });

  final int groupCount;
  final VoidCallback onTap;

  /// A panel card of its own rather than a hairline-topped band — for the
  /// phone tab, where it ends a list instead of closing a column.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final row = SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
        child: Row(
          children: [
            Icon(Icons.payments_outlined, size: AppSize.iconMd, color: scheme.onSurfaceVariant),
            const SizedBox(width: AppSpace.s10),
            Expanded(
              child: Text(
                l10n.feeManagement,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelLarge?.copyWith(color: scheme.onSurface),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.countGroups(groupCount),
              style: textTheme.labelSmall?.mono.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: AppSpace.s4),
            Icon(Icons.chevron_right, size: AppSize.iconMd, color: scheme.outline),
          ],
        ),
      ),
    );

    if (filled) {
      return Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: row),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant))),
      child: InkWell(onTap: onTap, child: row),
    );
  }
}
