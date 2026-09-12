import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/browser_file.dart';
import '../../../state/file_browser_state.dart';
import '../../../state/file_staging_state.dart';
import '../../../widgets/glass/app_glass.dart';
import '../../../widgets/glass/glass_controls.dart';

/// The floating bar shown at the bottom centre of the file area while files
/// are selected — `B1a · 1a`.
///
/// G2 glass, 44 tall at r16, 16 above the bottom: "3 selected" in the deep
/// ink · Select All · Clear | Add to Staging · AI Batch Rename on tinted
/// glass. Enters from below on M3 and leaves the same way. Under *reduce
/// visual effects* it is the opaque panel of the same size (`1d`).
///
/// When the column is too narrow for the labels — measured, not guessed —
/// every action keeps only its glyph and names itself in a tooltip.
/// What the bar states: how many files are picked, and whether the staging
/// button has anything left to do.
///
/// Read here, off both notifiers, rather than handed down. It used to be
/// computed by the screen, which meant the screen had to watch the selection
/// to draw a bar that floats over the grid — and so every file picked rebuilt
/// the header, the filter bar, the folder tree and every visible tile.
typedef _BarInputs = ({int count, bool allStaged});

_BarInputs _barInputs(FileBrowserState browser, FileStagingState staging) {
  final Set<BrowserFile> selected = browser.selectedFiles;
  return (
    count: selected.length,
    allStaged: selected.isNotEmpty &&
        selected.every((BrowserFile f) => staging.contains(f.path)),
  );
}

class BrowserSelectionBar extends StatelessWidget {
  final VoidCallback onAiRename;
  final VoidCallback onAddToStaging;

  const BrowserSelectionBar({
    super.key,
    required this.onAiRename,
    required this.onAddToStaging,
  });

  static const double height = 44;

  /// Distance from the bottom of the file area.
  static const double bottomInset = AppSpace.s16;

  /// Space the file area leaves below its last row so the bar never covers
  /// it.
  static const double clearance = height + bottomInset + AppSpace.s10;

  @override
  Widget build(BuildContext context) {
    return Selector2<FileBrowserState, FileStagingState, _BarInputs>(
      selector: (_, browser, staging) => _barInputs(browser, staging),
      builder: (context, bar, _) => _buildBar(context, bar),
    );
  }

  Widget _buildBar(BuildContext context, _BarInputs bar) {
    final count = bar.count;
    final visible = count > 0;
    final duration = AppMotion.sceneOf(context);

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 0.3),
        duration: duration,
        curve: AppMotion.emphasized,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: visible
              ? duration
              : Duration(milliseconds: (duration.inMilliseconds * AppMotion.exitFactor).round()),
          curve: AppMotion.emphasized,
          child: LayoutBuilder(
            builder: (context, constraints) => _BarContent(
              state: Provider.of<FileBrowserState>(context, listen: false),
              count: count,
              maxWidth: constraints.maxWidth,
              onAiRename: onAiRename,
              onAddToStaging: onAddToStaging,
              allSelectionStaged: bar.allStaged,
            ),
          ),
        ),
      ),
    );
  }
}

class _BarContent extends StatelessWidget {
  const _BarContent({
    required this.state,
    required this.count,
    required this.maxWidth,
    required this.onAiRename,
    required this.onAddToStaging,
    required this.allSelectionStaged,
  });

  final FileBrowserState state;
  final int count;
  final double maxWidth;
  final VoidCallback onAiRename;
  final VoidCallback onAddToStaging;
  final bool allSelectionStaged;

  static const double _padStart = 14;
  static const double _padEnd = AppSpace.s6;
  static const double _gap = AppSpace.s6;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    final countLabel = l10n.imagesSelected(count);
    final countStyle = Theme.of(context).textTheme.bodySmall!.metricsOnly.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onAccentTint,
        );

    final double fullWidth = _padStart +
        measureGlassText(context, countLabel, countStyle) +
        _gap +
        GlassIconButton.widthFor(context, label: l10n.selectAll, hasIcon: false) +
        GlassIconButton.widthFor(context, label: l10n.clear, hasIcon: false) +
        GlassDivider.extent +
        GlassIconButton.widthFor(context, label: l10n.addToStaging) +
        _gap +
        _AiRenameButton.widthFor(context, l10n.aiBatchRename, compact: false) +
        _padEnd;
    final compact = fullWidth > maxWidth;

    return SizedBox(
      height: BrowserSelectionBar.height,
      child: AppGlass(
        grade: GlassGrade.float,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        padding: const EdgeInsets.fromLTRB(_padStart, 0, _padEnd, 0),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(countLabel, style: countStyle),
              const SizedBox(width: _gap),
              GlassIconButton(
                icon: compact ? Icons.select_all : null,
                label: compact ? null : l10n.selectAll,
                tooltip: compact ? l10n.selectAll : null,
                onPressed: state.selectAll,
              ),
              GlassIconButton(
                icon: compact ? Icons.deselect : null,
                label: compact ? null : l10n.clear,
                tooltip: compact ? l10n.clear : null,
                onPressed: state.clearSelection,
              ),
              const GlassDivider(),
              GlassIconButton(
                icon: Icons.inbox_outlined,
                label: compact ? null : l10n.addToStaging,
                tooltip: compact ? l10n.addToStaging : null,
                onPressed: allSelectionStaged ? null : onAddToStaging,
              ),
              const SizedBox(width: _gap),
              _AiRenameButton(
                label: l10n.aiBatchRename,
                compact: compact,
                onPressed: onAiRename,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bar's one committing action: the accent's solid form, which on a
/// glass bar wears tinted glass ([AppTintedGlass]) — `auto_awesome` and a
/// 600 label, 32 tall at r10.
class _AiRenameButton extends StatelessWidget {
  const _AiRenameButton({required this.label, required this.compact, required this.onPressed});

  final String label;
  final bool compact;
  final VoidCallback onPressed;

  static TextStyle _labelStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!.metricsOnly.copyWith(fontWeight: FontWeight.w600);

  static double widthFor(BuildContext context, String label, {required bool compact}) {
    if (compact) return AppSize.control;
    return (12 + AppSize.iconMd + AppSpace.s6 + measureGlassText(context, label, _labelStyle(context)) + 12)
        .ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final content = SizedBox(
      height: AppSize.control,
      width: compact ? AppSize.control : null,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome, size: AppSize.iconMd),
            if (!compact) ...[
              const SizedBox(width: AppSpace.s6),
              Text(label, maxLines: 1, style: _labelStyle(context)),
            ],
          ],
        ),
      ),
    );

    Widget result = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: AppTintedGlass(
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: content,
        ),
      ),
    );
    if (compact) result = Tooltip(message: label, child: result);
    return Semantics(button: true, label: label, child: result);
  }
}
