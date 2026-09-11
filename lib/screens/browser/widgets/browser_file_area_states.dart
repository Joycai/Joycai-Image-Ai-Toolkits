import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';

/// What the file area shows when there is nothing to list — `B1a · 1d`.
///
/// Two cases. With no folder registered at all it repeats the directory
/// column's own empty state, because on a narrow window that column is
/// behind a drawer and this is the only thing on screen. Otherwise nothing
/// matched: `search_off` and "No files found".
class BrowserFilesEmptyState extends StatelessWidget {
  const BrowserFilesEmptyState({super.key, required this.noFolders});

  /// Whether the browser has no source folder registered.
  final bool noFolders;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.s22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                noFolders ? Icons.folder_off_outlined : Icons.search_off,
                size: 28,
                color: scheme.outline,
              ),
              const SizedBox(height: AppSpace.s10),
              Text(
                noFolders ? l10n.noFolders : l10n.noFilesFound,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              ...[
                const SizedBox(height: AppSpace.s4),
                Text(
                  noFolders ? l10n.clickAddFolder : l10n.browserNoFilesHint,
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: AppType.proseHeight,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A scan in progress over an empty file area — `B1a · 1d`: a 28px ring on
/// the track with the accent running on it, and the status in mono.
class BrowserScanningState extends StatelessWidget {
  const BrowserScanningState({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: scheme.primary,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.galleryScanning,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall!.mono.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
