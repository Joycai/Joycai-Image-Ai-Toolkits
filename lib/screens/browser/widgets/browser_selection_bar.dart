import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/file_browser_state.dart';
import '../../../widgets/app_button.dart';

/// Floating contextual action bar shown at the bottom center of the file
/// area while files are selected. Slides away when the selection is empty,
/// so selection actions never take up permanent chrome.
class BrowserSelectionBar extends StatelessWidget {
  final FileBrowserState state;
  final VoidCallback onAiRename;

  const BrowserSelectionBar({
    super.key,
    required this.state,
    required this.onAiRename,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final visible = state.selectedFiles.isNotEmpty;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 2),
        duration: AppMotion.durationOf(context, AppMotion.state),
        curve: AppMotion.enter,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: AppMotion.durationOf(context, AppMotion.state),
          curve: AppMotion.enter,
          // One spec for both bulk-selection bars (this one and the prompts
          // screen's): neutral surface, pill ends, the overlay rung — not
          // Material elevation with a black literal that vanishes on a dark
          // canvas. Neutral because a selection bar is chrome: the accent is
          // reserved for selection, the primary CTA and badges.
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: colorScheme.shadowOverlay,
            ),
            child: Material(
              type: MaterialType.transparency,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.imagesSelected(state.selectedFiles.length),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(width: 12),
                  AppButton(
                    label: l10n.selectAll,
                    variant: AppButtonVariant.text,
                    onPressed: () => state.selectAll(),
                  ),
                  AppButton(
                    label: l10n.clear,
                    variant: AppButtonVariant.text,
                    onPressed: () => state.clearSelection(),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    height: 20,
                    child: VerticalDivider(width: 1, color: colorScheme.outlineVariant),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: onAiRename,
                    icon: const Icon(Icons.auto_fix_high, size: 17),
                    label: Text(l10n.aiBatchRename, style: Theme.of(context).textTheme.bodySmall?.metricsOnly),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    ),
                  ),
                ],
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
