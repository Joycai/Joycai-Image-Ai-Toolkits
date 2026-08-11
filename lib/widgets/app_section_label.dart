import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

/// How loudly a section label speaks.
enum AppSectionTone {
  /// Inside a dialog or a config panel, where the label is the only structure
  /// the form has — the design spec draws these in the accent.
  accent,

  /// On a page that already has a heading of its own, where an accented label
  /// under it would read as a second title. The spec's one page-level use
  /// (the prompt library's category list) is this one.
  neutral,
}

/// The small tracked caption that names a group of controls.
///
/// Three copies of this existed: `ConfigSectionHeader` in the workbench folder,
/// a private `_sectionHeader` in the fee-group editor, and a `_Label` in the
/// component gallery — same idea, three weights, three colours, and only the
/// first was reachable from outside `screens/workbench/`, which is why the
/// dialog grew its own.
///
/// The accent tone takes [AppAccent.onAccentTint] rather than `primary`, which
/// is what the workbench copy used. `primary` is tuned to be seen as a *fill*;
/// at 11.5px semibold on `surface` it is thin, and on the warmer seeds (Orange,
/// Green) it lands near the 4.5:1 floor while `onAccentTint` clears it at every
/// seed by construction — see docs/architecture/design-tokens.md.
class AppSectionLabel extends StatelessWidget {
  const AppSectionLabel(
    this.label, {
    super.key,
    this.trailing,
    this.tone = AppSectionTone.accent,
    this.padding = const EdgeInsets.only(top: 18, bottom: 6),
  });

  final String label;

  /// An action belonging to this group — the prompt library button beside
  /// "Prompt", say. Sits on the label's baseline row, not below it.
  final Widget? trailing;

  final AppSectionTone tone;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              // A no-op on the CJK these labels are usually written in, and
              // deliberately kept anyway: the app ships English and Japanese
              // too, and the spec's caption is upper case there.
              label.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: AppType.trackedLabelSpacing,
                    color: tone == AppSectionTone.accent
                        ? colorScheme.onAccentTint
                        : colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
