import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/app_icon_button.dart';
import '../../../widgets/app_segmented_control.dart';
import '../../../widgets/app_tool_button.dart';
import '../workbench_layout.dart';

/// The comparator's header: leave, choose an arrangement, decide whether the
/// two panes move together, clear, and show or hide the metadata panel.
///
/// Built to the design spec's tool-toolbar shape — back button, hairline
/// divider, a raised segmented track for the arrangement, then the switches —
/// which is the same row the crop editor already draws, so switching between
/// the two workbench tools doesn't move the furniture.
class ComparatorToolbar extends StatelessWidget {
  const ComparatorToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final uiState = Provider.of<WorkbenchUIState>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isNarrow = Responsive.isNarrow(context);

    final hasImages =
        uiState.comparatorRawPath != null || uiState.comparatorAfterPath != null;
    // The curtain layers both images through one transform, so there is
    // nothing left for a sync switch to decide.
    final syncApplies = uiState.comparatorLayout != ComparatorLayout.slider;

    return Container(
      height: 58,
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
            onPressed: () => Provider.of<AppState>(context, listen: false).setWorkbenchTab(0),
          ),
          _divider(colorScheme),

          // The arrangement and the switches share one scroller: a narrow
          // window scrolls them out of reach rather than clipping them.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  AppSegmentedControl<ComparatorLayout>(
                    value: uiState.comparatorLayout,
                    onChanged: uiState.setComparatorLayout,
                    style: AppSegmentStyle.raised,
                    compact: true,
                    // A phone has room for the three arrangements or for their
                    // names, not both.
                    iconOnly: isNarrow,
                    segments: [
                      AppSegment(
                        value: ComparatorLayout.sideBySide,
                        label: l10n.compareLayoutSideBySide,
                        icon: Icons.vertical_split,
                      ),
                      AppSegment(
                        value: ComparatorLayout.stacked,
                        label: l10n.compareLayoutStacked,
                        icon: Icons.horizontal_split,
                      ),
                      AppSegment(
                        value: ComparatorLayout.slider,
                        label: l10n.compareLayoutSlider,
                        icon: Icons.compare,
                      ),
                    ],
                  ),
                  _divider(colorScheme),
                  AppToolButton(
                    icon: Icons.link,
                    label: l10n.compareSyncTransform,
                    showLabel: !isNarrow,
                    active: syncApplies && uiState.comparatorSyncTransform,
                    onPressed: syncApplies ? uiState.toggleComparatorSyncTransform : null,
                  ),
                  const SizedBox(width: 4),
                  AppToolButton(
                    icon: Icons.delete_outline,
                    label: l10n.clear,
                    showLabel: !isNarrow,
                    onPressed: hasImages ? uiState.clearComparator : null,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 12),
          AppIconButton(
            icon: Icons.info_outline,
            tooltip: l10n.metadata,
            // On desktop the panel is part of the layout and this switches it;
            // on narrow it is a drawer, which is opened rather than toggled —
            // so "on" is only ever claimed where it is true.
            selected: !isNarrow && uiState.comparatorShowMetadata,
            onPressed: () {
              if (isNarrow) {
                context.read<WorkbenchLayoutState>().openRightPanel();
              } else {
                uiState.toggleComparatorMetadata();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _divider(ColorScheme colorScheme) => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        // An explicit box rather than VerticalDivider, which collapses to
        // nothing under a Row's loose height constraint.
        color: colorScheme.outlineVariant.withValues(alpha: 0.7),
      );
}
