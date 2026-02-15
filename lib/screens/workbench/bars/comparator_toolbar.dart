import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/window_state.dart';
import '../workbench_layout.dart';

class ComparatorToolbar extends StatelessWidget {
  const ComparatorToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final windowState = Provider.of<WindowState>(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: colorScheme.surface,
      child: Row(
        children: [
          // Comparator Controls
          ToggleButtons(
            isSelected: [windowState.isComparatorSyncMode, !windowState.isComparatorSyncMode],
            onPressed: (index) {
              if (windowState.isComparatorSyncMode != (index == 0)) {
                windowState.toggleComparatorMode();
              }
            },
            borderRadius: BorderRadius.circular(8),
            constraints: const BoxConstraints(minHeight: 32, minWidth: 48),
            children: [
              Tooltip(message: l10n.compareModeSync, child: const Icon(Icons.view_column, size: 18)),
              Tooltip(message: l10n.compareModeSwap, child: const Icon(Icons.view_stream, size: 18)),
            ],
          ),
          const SizedBox(width: 16),
          
          // Clear Button
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined, size: 20),
            onPressed: () => windowState.clearComparator(),
            tooltip: l10n.clear,
            visualDensity: VisualDensity.compact,
          ),
          
          const Spacer(),

          // Right Panel Trigger (if needed, but usually panel state is handled elsewhere)
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => context.read<WorkbenchLayoutState>().openRightPanel(),
            tooltip: "Metadata",
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
