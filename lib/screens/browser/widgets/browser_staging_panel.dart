import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/constants.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/browser_file.dart';
import '../../../services/file_transfer_service.dart';
import '../../../state/file_staging_state.dart';
import '../../workbench/directory_tree_item.dart' show kFolderAmber;

/// Width the staging column takes when it is open.
///
/// `12a` draws 300 and states the cost outright: the grid goes from six
/// columns to four. That is the trade the frame is recommending, so the number
/// is fixed rather than resizable — a column the user can drag to 180 would
/// truncate every file name in it, which is the one thing this list is for.
const double kStagingPanelWidth = 300;

/// The file browser's staging column — `B1 12a`.
///
/// Reads [FileStagingState] and nothing else about the browser. The paste
/// itself belongs to the caller: this panel reports which way the user pressed
/// and against which destination, because the transfer needs a conflict pass
/// and a progress surface that outlive the panel's own build.
class BrowserStagingPanel extends StatelessWidget {
  /// Where a paste would land. Null until the user names one — see
  /// [FileStagingState] for why this screen cannot infer it.
  final String? destination;

  final void Function(FileTransferMode mode) onPaste;

  const BrowserStagingPanel({
    super.key,
    required this.destination,
    required this.onPaste,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final staging = context.watch<FileStagingState>();

    return Container(
      width: kStagingPanelWidth,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(left: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        children: [
          _Header(staging: staging),
          // `12c` keeps the destination card and the footer on an empty panel,
          // with the buttons disabled. They are what the panel *is*; hiding
          // them until something is staged would make the empty state a
          // different, smaller feature.
          _DestinationCard(destination: destination),
          Expanded(
            child: staging.isEmpty
                ? const _EmptyState()
                : _ItemList(staging: staging, destination: destination),
          ),
          _Footer(staging: staging, destination: destination, onPaste: onPaste),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final FileStagingState staging;

  const _Header({required this.staging});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(Icons.inbox_outlined, size: 17, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 9),
          Text(l10n.stagingArea, style: textTheme.titleSmall),
          if (staging.isNotEmpty) ...[
            const SizedBox(width: 9),
            _CountBadge(count: staging.count),
          ],
          const Spacer(),
          if (staging.isNotEmpty)
            // A text button in the error colour, not an outlined destructive
            // one: `12a` keeps it at the weight of a link because emptying the
            // list costs nothing on disk — the marks are only marks.
            TextButton(
              onPressed: staging.clear,
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.error,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(l10n.clearStaging, style: textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

/// The accent pill carrying the staged count, in the panel header and on the
/// toolbar button that opens it.
class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 19),
      height: 19,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
              color: colorScheme.onPrimary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 34, color: colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Text(
            l10n.stagingEmptyTitle,
            style: textTheme.titleSmall?.copyWith(color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.stagingEmptyDesc,
            style: textTheme.labelMedium?.copyWith(color: colorScheme.outline, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Where a paste lands, echoed back permanently.
///
/// The one control this feature cannot do without. The browser lists several
/// active directories merged, so there is no "current folder" to paste into —
/// the destination has to be named, and named visibly, or the user is
/// guessing where their files went.
class _DestinationCard extends StatelessWidget {
  final String? destination;

  const _DestinationCard({required this.destination});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final target = destination;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.stagingTarget,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.outline,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.folder_rounded,
                size: 16,
                color: target == null ? colorScheme.outlineVariant : kFolderAmber,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  target == null ? l10n.stagingNoTarget : _shortPath(target),
                  style: textTheme.labelMedium?.mono.copyWith(
                    color: target == null ? colorScheme.outline : colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  // Truncates at the *front*: the tail of a path is the part
                  // that identifies the folder, and it is the half a
                  // left-truncating ellipsis would eat.
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.stagingTargetHint,
            style: textTheme.labelSmall?.copyWith(color: colorScheme.outline, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// Last two segments — a full path does not fit in 300px and the leading half
/// is the same for every entry anyway.
String _shortPath(String path) {
  final parts = p.split(path).where((s) => s.isNotEmpty).toList();
  if (parts.length <= 2) return path;
  return parts.sublist(parts.length - 2).join(' / ');
}

class _ItemList extends StatelessWidget {
  final FileStagingState staging;
  final String? destination;

  const _ItemList({required this.staging, required this.destination});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Grouped by source folder, which is also the shape that makes the
    // "already at the destination" case legible: it lands on a whole group at
    // once rather than being scattered down the list.
    final groups = <String, List<BrowserFile>>{};
    for (final file in staging.items) {
      groups.putIfAbsent(p.dirname(file.path), () => []).add(file);
    }

    final children = <Widget>[
      if (staging.restoredCount > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 9, 8, 0),
          child: Row(
            children: [
              Icon(Icons.history, size: 12, color: colorScheme.outline),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  l10n.stagingRestored(staging.restoredCount),
                  style: textTheme.labelSmall?.copyWith(color: colorScheme.outline),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
    ];

    for (final entry in groups.entries) {
      final atDestination = destination != null && p.equals(entry.key, destination!);
      children.add(_GroupHeader(
        label: p.basename(entry.key),
        fullPath: entry.key,
        count: entry.value.length,
        atDestination: atDestination,
      ));
      for (final file in entry.value) {
        children.add(_StagedRow(
          file: file,
          missing: staging.isMissing(file.path),
          onRemove: () => staging.remove(file.path),
        ));
      }
    }

    if (staging.hasMissing) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: staging.removeMissing,
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              l10n.stagingClearMissing(staging.missingPaths.length),
              style: textTheme.bodySmall,
            ),
          ),
        ),
      ));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
      children: children,
    );
  }
}

class _GroupHeader extends StatelessWidget {
  /// The folder's own name, not its path.
  ///
  /// A 300px column cannot hold a path, and the half an ellipsis would take is
  /// the half that says which folder this is — `12a` labels these groups
  /// `ai_res`, `下载`, and so on for the same reason. The path is still one
  /// hover away.
  final String label;

  final String fullPath;
  final int count;
  final bool atDestination;

  const _GroupHeader({
    required this.label,
    required this.fullPath,
    required this.count,
    required this.atDestination,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: Row(
        children: [
          Flexible(
            child: Tooltip(
              message: fullPath,
              child: Text(
              label,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.outline,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '$count',
            style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.outline),
          ),
          if (atDestination) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                l10n.stagingSameAsTarget,
                style: textTheme.labelSmall?.copyWith(color: colorScheme.outline),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StagedRow extends StatefulWidget {
  final BrowserFile file;
  final bool missing;
  final VoidCallback onRemove;

  const _StagedRow({
    required this.file,
    required this.missing,
    required this.onRemove,
  });

  @override
  State<_StagedRow> createState() => _StagedRowState();
}

class _StagedRowState extends State<_StagedRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final semantic = AppSemanticColors.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          // Hover is greyscale, never the accent — the accent in this panel
          // means the count and the commit button, and a hovered row is
          // neither.
          color: _hovered ? colorScheme.surfaceContainerHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          children: [
            _Thumb(file: widget.file, missing: widget.missing),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                widget.file.name,
                style: textTheme.labelMedium?.mono.copyWith(
                  color: widget.missing ? colorScheme.outline : colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.missing) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: semantic.warningContainer,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  l10n.stagingMissing,
                  style: textTheme.labelSmall?.copyWith(color: semantic.onWarningContainer),
                ),
              ),
            ],
            const SizedBox(width: 4),
            // Shown on hover only. Twelve rows each carrying a permanent ✕
            // reads as a list of delete buttons that happen to have file names
            // beside them; the reserved width keeps the names from reflowing
            // as the pointer moves down the list.
            SizedBox(
              width: 20,
              height: 20,
              child: _hovered
                  ? Tooltip(
                      message: l10n.removeFromStaging,
                      child: InkWell(
                        onTap: widget.onRemove,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        child: Icon(
                          Icons.close,
                          size: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final BrowserFile file;
  final bool missing;

  const _Thumb({required this.file, required this.missing});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isImage = file.category == FileCategory.image && !missing;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Container(
        width: 26,
        height: 26,
        color: colorScheme.surfaceContainerHighest,
        child: isImage
            // 26px on screen, so decoded at 52 for a 2x display and no more —
            // the grid's own cache entries are far larger and a second full
            // decode per staged file would be paid for nothing.
            ? Image(
                image: ResizeImage(file.imageProvider, width: 52),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => Icon(file.icon, size: 13, color: colorScheme.outline),
              )
            : Icon(
                file.icon,
                size: 13,
                color: missing ? colorScheme.outlineVariant : file.color.withAlpha(180),
              ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final FileStagingState staging;
  final String? destination;
  final void Function(FileTransferMode mode) onPaste;

  const _Footer({
    required this.staging,
    required this.destination,
    required this.onPaste,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final atTarget = destination == null
        ? 0
        : staging.items.where((f) => p.equals(p.dirname(f.path), destination!)).length;
    final enabled = destination != null && staging.count > atTarget + staging.missingPaths.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: enabled ? () => onPaste(FileTransferMode.move) : null,
                  icon: const Icon(Icons.arrow_forward, size: 14),
                  label: Text(l10n.moveHere, style: textTheme.bodySmall?.metricsOnly),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, AppSize.control),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: enabled ? () => onPaste(FileTransferMode.copy) : null,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, AppSize.control),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: Text(l10n.copyHere, style: textTheme.bodySmall?.metricsOnly),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _summary(l10n, atTarget),
            style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.outline),
          ),
        ],
      ),
    );
  }

  /// The one line that says what pressing either button will actually do.
  /// Assembled from parts rather than one plural string so the clauses that
  /// do not apply are absent, not zeroed.
  String _summary(AppLocalizations l10n, int atTarget) {
    if (staging.isEmpty) return l10n.stagingItemsCount(0);

    final parts = <String>[
      l10n.stagingItemsCount(staging.count),
      AppConstants.formatFileSize(staging.totalBytes),
      if (staging.hasMissing) l10n.stagingMissingCount(staging.missingPaths.length),
      if (atTarget > 0) l10n.stagingAtTargetCount(atTarget),
    ];
    return parts.join(' · ');
  }
}
