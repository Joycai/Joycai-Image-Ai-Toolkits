import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/file_browser_state.dart';

/// Floating contextual action bar shown at the bottom center of the file
/// area while files are selected. Slides away when the selection is empty,
/// so selection actions never take up permanent chrome.
class BrowserSelectionBar extends StatelessWidget {
  final FileBrowserState state;
  final VoidCallback onAiRename;
  final VoidCallback onAddToStaging;

  /// Whether every selected file is already staged, which is when the staging
  /// button has nothing left to do.
  final bool allSelectionStaged;

  const BrowserSelectionBar({
    super.key,
    required this.state,
    required this.onAiRename,
    required this.onAddToStaging,
    required this.allSelectionStaged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final visible = state.selectedFiles.isNotEmpty;

    // Labels on the ink, one step down from [AppOverlay.onInk]. The quiet
    // verbs have to sit under the count without going illegible on a ground
    // that is the same in both themes.
    final onInkMuted = AppOverlay.onInk.withValues(alpha: 0.68);

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
          // The overlay ink, not a surface tone. `11b` draws this bar dark in
          // both themes, which is the same argument the tooltips and toasts
          // already make: it is not a panel within the page but a label laid
          // over it, and the file grid it floats on is now transparent — a
          // neutral surface pill would have read as one more card.
          child: Container(
            height: 54,
            padding: const EdgeInsets.fromLTRB(18, 0, 10, 0),
            decoration: BoxDecoration(
              color: AppOverlay.ink,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0A1028).withValues(alpha: 0.55),
                  blurRadius: 44,
                  spreadRadius: -12,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.imagesSelected(state.selectedFiles.length),
                  style: textTheme.bodyMedium?.metricsOnly.copyWith(
                    color: AppOverlay.onInk,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                _InkTextAction(label: l10n.selectAll, color: onInkMuted, onTap: state.selectAll),
                const SizedBox(width: 4),
                _InkTextAction(label: l10n.clear, color: onInkMuted, onTap: state.clearSelection),
                const SizedBox(width: 10),
                Container(width: 1, height: 22, color: Colors.white.withValues(alpha: 0.16)),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: allSelectionStaged ? null : onAddToStaging,
                  icon: const Icon(Icons.inbox_outlined, size: 14),
                  label: Text(l10n.addToStaging, style: textTheme.bodySmall?.metricsOnly),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppOverlay.onInk,
                    disabledForegroundColor: AppOverlay.onInk.withValues(alpha: AppAlpha.disabled),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    minimumSize: const Size(0, AppSize.control),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onAiRename,
                  icon: const Icon(Icons.auto_fix_high, size: 15),
                  label: Text(l10n.aiBatchRename, style: textTheme.bodySmall?.metricsOnly),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    minimumSize: const Size(0, 38),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A bare verb on the ink. Not [TextButton]: its theme is tuned for surfaces
/// and would repaint the label in the accent against a ground the accent is
/// not legible on.
class _InkTextAction extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _InkTextAction({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
        ),
      ),
    );
  }
}
