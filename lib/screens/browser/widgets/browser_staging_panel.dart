import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/constants.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/browser_file.dart';
import '../../../services/file_transfer_service.dart';
import '../../../state/file_staging_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/dashed_border.dart';
import '../../../widgets/glass/glass_controls.dart';
import 'transfer_dialog_parts.dart';

/// Width the staging column takes when its parent does not bound it (`B1b`:
/// 320, the same as the narrow-window slide-out panel).
const double kStagingPanelWidth = 320;

/// The file browser's staging column — `B1b 1a`.
///
/// An opaque column, not a floating layer: staging only keeps marks, so it
/// survives folder switches, filters and restarts, and the user keeps coming
/// back to read it. Header, destination, the list, and a footer fixed to the
/// bottom whose actions apply to the whole column.
///
/// Reads [FileStagingState] and nothing else about the browser. The paste
/// itself belongs to the caller: this panel reports which way the user pressed
/// and against which destination, because the transfer needs a conflict pass
/// and a progress surface that outlive the panel's own build.
///
/// Fills whatever width it is given; only an unbounded parent (a bare row)
/// gets [kStagingPanelWidth].
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
    final target = destination;

    // Staged files already sitting in the destination: a move there is a
    // no-op, so they are called out per row and left out of the commit.
    final Set<String> atTarget = target == null
        ? const <String>{}
        : {
            for (final f in staging.items)
              if (p.equals(p.dirname(f.path), target)) f.path,
          };

    final panel = DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(left: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(staging: staging, atTargetCount: atTarget.length),
          // The destination and the footer stay on an empty panel, the
          // buttons disabled: they are what the panel *is*, and hiding them
          // until something is staged would make the empty state a smaller,
          // different feature. Empty, the destination drops to the bottom
          // under the explanation, as `1a`'s empty frame draws it.
          if (staging.isEmpty) ...[
            const Expanded(child: _EmptyState()),
            _DestinationSection(destination: target, restoredCount: 0, ruleOnTop: true),
          ] else ...[
            _DestinationSection(destination: target, restoredCount: staging.restoredCount, ruleOnTop: false),
            Expanded(child: _ItemList(staging: staging, atTarget: atTarget)),
          ],
          _Footer(staging: staging, destination: target, atTargetCount: atTarget.length, onPaste: onPaste),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.hasBoundedWidth ? panel : SizedBox(width: kStagingPanelWidth, child: panel),
    );
  }
}

/// `1a` 头 72: title, a single mono summary line, and Clear.
class _Header extends StatelessWidget {
  final FileStagingState staging;
  final int atTargetCount;

  const _Header({required this.staging, required this.atTargetCount});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final summary = _summary(l10n);

    return Container(
      height: 72,
      padding: const EdgeInsets.only(left: 16, right: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.stagingArea,
                  style: textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // One line, never wrapped: the header does not change height
                // with the list. The whole line is a hover away.
                Tooltip(
                  message: summary,
                  child: Text(
                    summary,
                    style: textTheme.bodySmall!.mono.copyWith(color: colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // The error colour at the weight of a link: emptying the list costs
          // nothing on disk — the marks are only marks. Kept in place on an
          // empty panel, disabled, so the header does not change shape.
          AppButton(
            label: l10n.clearStaging,
            variant: AppButtonVariant.destructiveText,
            size: AppButtonSize.compact,
            onPressed: staging.isEmpty ? null : staging.clear,
          ),
        ],
      ),
    );
  }

  /// Assembled from parts rather than one plural string so the clauses that
  /// do not apply are absent, not zeroed.
  String _summary(AppLocalizations l10n) {
    if (staging.isEmpty) return l10n.stagingItemsCount(0);
    return <String>[
      l10n.stagingItemsCount(staging.count),
      AppConstants.formatFileSize(staging.totalBytes),
      if (staging.hasMissing) l10n.stagingMissingCount(staging.missingPaths.length),
      if (atTargetCount > 0) l10n.stagingAtTargetCount(atTargetCount),
    ].join(' · ');
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s22, vertical: AppSpace.s16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined, size: 28, color: colorScheme.outline),
                  const SizedBox(height: AppSpace.s10),
                  Text(
                    l10n.stagingEmptyTitle,
                    style: textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpace.s6),
                  Text(
                    l10n.stagingEmptyDesc,
                    style: textTheme.bodySmall!.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: AppType.proseHeight,
                    ),
                    textAlign: TextAlign.center,
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

/// Where a paste lands, echoed back permanently — `1a` DESTINATION.
///
/// The one control this feature cannot do without. The browser lists several
/// active directories merged, so there is no "current folder" to paste into —
/// the destination has to be named, and named visibly, or the user is
/// guessing where their files went.
class _DestinationSection extends StatelessWidget {
  final String? destination;
  final int restoredCount;

  /// Drawn under the empty state, so the rule is above it; otherwise below.
  final bool ruleOnTop;

  const _DestinationSection({
    required this.destination,
    required this.restoredCount,
    required this.ruleOnTop,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final target = destination;
    final hair = BorderSide(color: colorScheme.outlineVariant);

    final Widget card;
    if (target == null) {
      card = DashedBorder(
        color: colorScheme.outline,
        radius: AppRadius.control,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.folder_outlined, size: 18, color: colorScheme.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.stagingNoTarget,
                      style: textTheme.bodyMedium!.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.s4),
              Text(
                l10n.stagingTargetHint,
                style: textTheme.bodySmall!.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: AppType.proseHeight,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      card = Tooltip(
        message: target,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Row(
            children: [
              Icon(Icons.folder_open, size: AppSize.iconLg, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.basename(target).isEmpty ? target : p.basename(target),
                      style: textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      target,
                      style: textTheme.labelSmall!.mono.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: AppSpace.s10),
      decoration: BoxDecoration(
        border: Border(top: ruleOnTop ? hair : BorderSide.none, bottom: ruleOnTop ? BorderSide.none : hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.stagingTarget.toUpperCase(),
            style: textTheme.labelSmall!.copyWith(
              color: colorScheme.onAccentTint,
              letterSpacing: AppType.trackedLabelSpacing,
            ),
          ),
          const SizedBox(height: AppSpace.s6),
          card,
          if (restoredCount > 0) ...[
            const SizedBox(height: AppSpace.s6),
            TransferNote(
              text: l10n.stagingRestored(restoredCount),
              tone: TransferTone.ok,
              icon: Icons.restore,
              compact: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _ItemList extends StatelessWidget {
  final FileStagingState staging;
  final Set<String> atTarget;

  const _ItemList({required this.staging, required this.atTarget});

  @override
  Widget build(BuildContext context) {
    final items = staging.items;
    return ListView.builder(
      padding: EdgeInsets.zero,
      // One past the rows: the list-end note on how else files get here.
      itemCount: items.length + 1,
      itemBuilder: (context, index) {
        if (index == items.length) {
          final colorScheme = Theme.of(context).colorScheme;
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, AppSpace.s10, 12, AppSpace.s16),
            child: Text(
              AppLocalizations.of(context)!.stagingDropHint,
              style: Theme.of(context).textTheme.labelSmall!.mono.copyWith(
                    color: colorScheme.outline,
                    fontWeight: FontWeight.w400,
                  ),
            ),
          );
        }
        final file = items[index];
        return _StagedRow(
          key: ValueKey(file.path),
          file: file,
          missing: staging.isMissing(file.path),
          atTarget: atTarget.contains(file.path),
          onRemove: () => staging.remove(file.path),
        );
      },
    );
  }
}

/// `1a` 条目行 56: thumbnail, mono name, and a second line that is either the
/// size and date, *Missing*, or *Already here*.
class _StagedRow extends StatelessWidget {
  final BrowserFile file;
  final bool missing;
  final bool atTarget;
  final VoidCallback onRemove;

  const _StagedRow({
    super.key,
    required this.file,
    required this.missing,
    required this.atTarget,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mono11 = textTheme.labelSmall!.mono.copyWith(fontWeight: FontWeight.w400);

    final Widget detail;
    if (missing) {
      detail = Row(
        children: [
          Icon(Icons.link_off, size: 12, color: colorScheme.error),
          const SizedBox(width: AppSpace.s4),
          Flexible(
            child: Text(
              l10n.stagingMissing,
              style: mono11.copyWith(color: colorScheme.onErrorContainer),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    } else if (atTarget) {
      detail = Align(
        alignment: Alignment.centerLeft,
        child: TransferBadge(label: l10n.stagingSameAsTarget, tone: TransferTone.track, icon: Icons.block),
      );
    } else {
      detail = Text(
        '${AppConstants.formatFileSize(file.size)} · ${_date(file.modified)}',
        style: mono11.copyWith(color: colorScheme.onSurfaceVariant),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Container(
      height: 56,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: missing ? 0.45 : 1,
            child: TransferThumb(
              path: file.path,
              size: 36,
              // A missing file has nothing to decode; its glyph stands in.
              imageProvider: missing ? null : file.imageProvider,
            ),
          ),
          const SizedBox(width: AppSpace.s10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The full path is a hover away: rows carry the name only, and
                // two staged files of one name from two folders are told apart
                // here.
                Tooltip(
                  message: file.path,
                  waitDuration: const Duration(milliseconds: 500),
                  child: Text(
                    file.name,
                    style: textTheme.bodySmall!.mono.copyWith(
                      color: missing ? colorScheme.outline : colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 3),
                detail,
              ],
            ),
          ),
          const SizedBox(width: AppSpace.s4),
          IconButton(
            icon: const Icon(Icons.close, size: AppSize.iconMd),
            tooltip: l10n.removeFromStaging,
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: AppSize.compact, height: AppSize.compact),
            style: IconButton.styleFrom(
              foregroundColor: colorScheme.outline,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
          ),
        ],
      ),
    );
  }

  static String _date(DateTime when) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${when.year}-${two(when.month)}-${two(when.day)}';
  }
}

/// `1a` 底部固定区: Remove missing (an action on the whole column, so it does
/// not scroll with the list), then Move here and Copy here side by side.
class _Footer extends StatelessWidget {
  final FileStagingState staging;
  final String? destination;
  final int atTargetCount;
  final void Function(FileTransferMode mode) onPaste;

  const _Footer({
    required this.staging,
    required this.destination,
    required this.atTargetCount,
    required this.onPaste,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final enabled = destination != null && staging.count > atTargetCount + staging.missingPaths.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: AppSpace.s10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (staging.hasMissing) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: staging.removeMissing,
                icon: const Icon(Icons.delete_sweep_outlined, size: AppSize.iconSm),
                label: Text(
                  l10n.stagingClearMissing(staging.missingPaths.length),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.error,
                  backgroundColor: colorScheme.surface,
                  side: BorderSide(color: colorScheme.outlineVariant),
                  minimumSize: const Size(0, AppSize.compact),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
                  textStyle: textTheme.labelMedium,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: _PasteButton(
                  label: l10n.moveHere,
                  icon: Icons.drive_file_move_outlined,
                  primary: true,
                  onPressed: enabled ? () => onPaste(FileTransferMode.move) : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PasteButton(
                  label: l10n.copyHere,
                  icon: Icons.content_copy_outlined,
                  primary: false,
                  onPressed: enabled ? () => onPaste(FileTransferMode.copy) : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A 40px half-width paste button. Drops its glyph — measured, not guessed —
/// when the label and the glyph no longer fit the half it is given.
class _PasteButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback? onPressed;

  const _PasteButton({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onPressed,
  });

  /// `AppButtonSize.large`'s horizontal padding, twice, plus Material's gap
  /// between a button's glyph and its label.
  static const double _chrome = 40;
  static const double _glyphGap = 8;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final textWidth = measureGlassText(context, label, textTheme.titleMedium!);
        final fits = textWidth + AppSize.iconLg + _glyphGap + _chrome <= constraints.maxWidth;

        final button = AppButton(
          label: label,
          icon: fits ? icon : null,
          variant: primary ? AppButtonVariant.primary : AppButtonVariant.secondary,
          size: AppButtonSize.large,
          fullWidth: true,
          onPressed: onPressed,
        );
        if (!primary || onPressed == null) return button;

        // `0 4 12 ring`: the commit button carries a glow in its own hue.
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            boxShadow: [BoxShadow(color: colorScheme.accentRing, blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: button,
        );
      },
    );
  }
}
