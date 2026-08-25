import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/design_tokens.dart';
import 'app_switch.dart';

/// One setting: what it is, what it does, and the control that changes it.
///
/// `D1 12a` draws the settings body as a stack of individually outlined rows
/// rather than as a list. The difference is not decoration — a list says
/// "these are items of one kind, scan them"; a stack of boxes says "these are
/// unrelated decisions, read each one". A settings page is the second thing,
/// and every row on it had been a [SwitchListTile] or a [ListTile], which
/// brought Material's list geometry, its 52×32 switch and its 16px gutters to
/// a page that is not a list.
///
/// The box carries no fill. It sits on the content card's own ground, and a
/// second surface inside that one would read as a card in a card.
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
  });

  final String title;

  /// One line on what the setting does. Not a repeat of the title in other
  /// words — a row whose description says nothing is better off without one.
  final String? description;

  /// Sets [description] in the mono face, for a value rather than a sentence:
  /// `D1` writes the output and knowledge-base paths this way.
  final bool monoDescription;

  /// Overrides the description's colour — for a row whose description is
  /// reporting a fault rather than explaining the setting (a path that no
  /// longer resolves, say).
  final Color? descriptionColor;

  /// The control. An [AppSwitch], a value pill, a chevron — whatever the
  /// decision is made with.
  final Widget? trailing;

  /// A secondary action belonging to this setting, inside the same box and
  /// below the row — `D1` puts 「打开日志文件夹」 under the debug-log toggle
  /// rather than beside it, because it acts on what the toggle produces and
  /// only exists while the toggle is on.
  final Widget? footer;

  /// Makes the whole box the target, for a row whose "control" is the act of
  /// opening something — a directory picker, a sub-page.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        description!,
                        style: (monoDescription
                                ? textTheme.bodySmall?.mono
                                : textTheme.bodySmall)
                            ?.copyWith(
                          color: descriptionColor ?? colorScheme.onSurfaceVariant,
                        ),
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
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Align(alignment: Alignment.centerLeft, child: footer!),
          ),
      ],
    );

    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
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
///
/// Six copies of it existed — two in the image panel, one in the video panel,
/// four in the model editor, one in the channel editor — as [SwitchListTile]s
/// with `contentPadding: zero`, `visualDensity: compact` and a hand-restated
/// subtitle colour, because that widget's own subtitle style is overridden by
/// any scale slot the caller names. Each also carried Material's 52×32 switch,
/// which is the one thing none of those frames draw.
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
                // 500, as `16a` sets it and as [AppSettingRow] above sets
                // its own title. The six copies this replaces used three
                // weights between them: `titleSmall`'s 600 in the image panel,
                // `bodyMedium`'s 400 in the model editor, and Material's own
                // bold 13 wherever a caller named nothing.
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
/// `D1` draws it as an input-shaped box: the same 32px height, radius and
/// hairline every field on the page wears, with the value in mono and a
/// chevron after it. It is not an input, and deliberately looks like one:
/// the row is telling you this number is editable.
class AppSettingValue extends StatelessWidget {
  const AppSettingValue({super.key, required this.value, this.onTap});

  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.mono
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 7),
              Icon(Icons.expand_more, size: 13, color: colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
