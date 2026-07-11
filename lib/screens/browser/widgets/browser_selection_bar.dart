import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/file_browser_state.dart';

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
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: Material(
            color: colorScheme.surfaceContainerHigh,
            elevation: 4,
            shadowColor: Colors.black.withAlpha(60),
            borderRadius: BorderRadius.circular(28),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.imagesSelected(state.selectedFiles.length),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => state.selectAll(),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: Text(l10n.selectAll, style: const TextStyle(fontSize: 12.5)),
                  ),
                  TextButton(
                    onPressed: () => state.clearSelection(),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: Text(l10n.clear, style: const TextStyle(fontSize: 12.5)),
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
                    label: Text(l10n.aiBatchRename, style: const TextStyle(fontSize: 12.5)),
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
    );
  }
}
