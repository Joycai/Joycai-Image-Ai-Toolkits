import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import '../../../widgets/app_icon_button.dart';

/// Height of a workbench tool's header row.
///
/// The design spec draws the comparator, the mask editor and the crop editor
/// at 58 and the prompt assistant's chat header at 50. Taken as one number:
/// all four are reached from the same tab strip, and a header that changes
/// height as the user moves between them makes the canvas below jump.
const double kToolHeaderHeight = 58;

/// The header every workbench tool opens with.
///
/// Exists so the *leaving* control cannot drift. The four tools each grew
/// their own back button — an outlined [AppIconButton] in two of them, a bare
/// [IconButton] tooltipped "Cancel" in the crop editor, and nothing at all in
/// the prompt assistant — which is three different answers to the one question
/// a user asks on every one of these screens. It is owned here instead, so
/// there is exactly one.
///
/// [children] is everything after it: the tool's own controls, laid out by the
/// tool. Groups inside them are separated with [ToolHeaderDivider].
class WorkbenchToolHeader extends StatelessWidget {
  final List<Widget> children;

  const WorkbenchToolHeader({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: kToolHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(80))),
      ),
      child: Row(
        children: [
          AppIconButton(
            icon: Icons.arrow_back,
            tooltip: l10n.back,
            // Tab 0 is the gallery, which is where all four tools are opened
            // from — so back is "back to the pictures", not a route pop.
            onPressed: () => Provider.of<AppState>(context, listen: false).setWorkbenchTab(0),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// The hairline between two groups of controls in a [WorkbenchToolHeader].
///
/// An explicit box rather than [VerticalDivider], which collapses to nothing
/// under a [Row]'s loose height constraint.
class ToolHeaderDivider extends StatelessWidget {
  const ToolHeaderDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 26,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.7),
    );
  }
}
