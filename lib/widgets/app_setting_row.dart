import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/design_tokens.dart';
import 'app_switch.dart';

/// One setting: what it is, what it does, and the control that changes it.
///
/// `E1 · 1a / 1c`: a box on the column colour at r10 with a hairline — the
/// grouping container every settings frame draws — holding a 13/500 title, a
/// quieter description and the control. A settings page is a stack of
/// unrelated decisions, and the box is what says "read each one".
///
/// [framed] false drops the box, for a row that sits inside a group which
/// already draws it (`1c` puts three toggles in one box, ruled by hairlines).
class AppSettingRow extends StatelessWidget {
  const AppSettingRow({
    super.key,
    required this.title,
    this.description,
    this.monoDescription = false,
    this.descriptionColor,
    this.trailing,
    this.footer,
    this.onTap,
    this.framed = true,
    this.enabled = true,
    this.borderColor,
    this.badge,
  });

  final String title;

  /// A small tag after the title — `E1 · 1c`'s 「实验性」.
  final Widget? badge;

  /// Overrides the frame's hairline — `E1 · 1c` rules a path that no longer
  /// resolves in the error colour. Ignored when not [framed].
  final Color? borderColor;

  /// One line on what the setting does. Not a repeat of the title in other
  /// words — a row whose description says nothing is better off without one.
  final String? description;

  /// Sets [description] in the mono face, for a value rather than a sentence:
  /// the output and knowledge-base paths, the GPU name.
  final bool monoDescription;

  /// Overrides the description's colour — for a row whose description is
  /// reporting a fault rather than explaining the setting (a path that no
  /// longer resolves, say).
  final Color? descriptionColor;

  /// The control. An [AppSwitch], a compact button, a dropdown — whatever the
  /// decision is made with.
  final Widget? trailing;

  /// A secondary action belonging to this setting, inside the same box and
  /// below the row — it acts on what the setting produces.
  final Widget? footer;

  /// Makes the whole box the target, for a row whose "control" is the act of
  /// opening something — a directory picker, a sub-page.
  final VoidCallback? onTap;

  /// Whether the row draws its own box. False inside a group that draws one.
  final bool framed;

  /// False greys the title and description to the muted ink without moving
  /// anything (`1c`: a sub-setting of a switch that is off stays in place).
  /// The caller still disables the control itself.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final Widget body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            title,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: enabled ? null : colorScheme.outline,
                            ),
                          ),
                          ?badge,
                        ],
                      ),
                      if (description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          description!,
                          style: (monoDescription ? textTheme.bodySmall?.mono : textTheme.bodySmall)?.copyWith(
                            color: !enabled
                                ? colorScheme.outline
                                : descriptionColor ?? colorScheme.onSurfaceVariant,
                            height: monoDescription ? null : AppType.proseHeight,
                          ),
                          maxLines: monoDescription ? 1 : null,
                          overflow: monoDescription ? TextOverflow.ellipsis : null,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  trailing!,
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Align(alignment: Alignment.centerLeft, child: footer!),
            ),
        ],
      ),
    );

    return Material(
      color: framed ? colorScheme.surfaceContainerLow : Colors.transparent,
      shape: framed
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
              side: BorderSide(color: borderColor ?? colorScheme.outlineVariant),
            )
          : null,
      clipBehavior: framed ? Clip.antiAlias : Clip.none,
      child: onTap == null ? body : InkWell(onTap: onTap, child: body),
    );
  }
}

/// A setting inside a form: an optional glyph, what it is, what it does, and
/// the switch that turns it on.
///
/// [AppSettingRow]'s borderless sibling. The box that one draws is what tells
/// a *settings page* its rows are unrelated decisions; inside a card or a
/// dialog the card is already saying that, and a second outline around each
/// row reads as a box in a box. `A1 16a`'s two request toggles, `17a`'s
/// compress toggle and `D2 13c`'s capability rows are all this shape.
class AppToggleRow extends StatelessWidget {
  const AppToggleRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.description,
    this.icon,
  });

  final String title;
  final String? description;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppSize.iconMd, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                if (description != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    description!,
                    style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          AppSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// The read-only pill a setting shows its current value in — a count, a
/// percentage — when tapping the row opens the picker that changes it.
///
/// Input-shaped on purpose: the 32px height, radius and hairline every field
/// wears, on the panel colour a field takes inside a column-coloured group
/// (`E1 · 1c`), the value in mono and a chevron after it.
class AppSettingValue extends StatelessWidget {
  const AppSettingValue({super.key, required this.value, this.onTap});

  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: AppSize.control,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodySmall?.mono,
                ),
                const SizedBox(width: 6),
                Icon(Icons.expand_more, size: AppSize.iconSm, color: colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
