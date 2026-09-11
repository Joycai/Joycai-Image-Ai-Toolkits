import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import '../../../state/downloader_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/dashed_border.dart';
import '../../../widgets/glass/glass_controls.dart';
import 'downloader_image_card.dart';
import 'downloader_inputs.dart';

/// Everything under the log panel (`B3`): the 48px results header, the grid —
/// or the analyzing state, the manual-HTML prompt or the three-step guide in
/// its place — and the 36px status row.
///
/// The header and status row are opaque column strips; the grid between them
/// is transparent over the window's backdrop, as the workbench gallery is.
class DownloaderResultsArea extends StatelessWidget {
  final VoidCallback onAddToQueue;

  const DownloaderResultsArea({super.key, required this.onAddToQueue});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DownloaderState>();
    final images = state.discoveredImages;
    final selectedCount = images.where((i) => i.isSelected).length;

    final Widget body;
    if (images.isNotEmpty) {
      body = _ResultsGrid(state: state);
    } else if (state.isAnalyzing) {
      body = _AnalyzingState(logs: state.logs);
    } else if (state.isManualHtml && state.manualHtml.trim().isEmpty) {
      body = const _ManualHtmlEmptyState();
    } else {
      body = const _EmptyGuide();
    }

    return Column(
      children: [
        if (images.isNotEmpty)
          _ResultsHeader(state: state, selectedCount: selectedCount, onAddToQueue: onAddToQueue),
        Expanded(child: body),
        _StatusRow(found: images.length, selected: selectedCount, prefix: state.prefix),
      ],
    );
  }
}

/// `选择要下载的图片 (8 selected)` · Select All · Add to Queue. Select All
/// gives up its label (`1c`: a 32 icon button) when the row measures short.
class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({
    required this.state,
    required this.selectedCount,
    required this.onAddToQueue,
  });

  final DownloaderState state;
  final int selectedCount;
  final VoidCallback onAddToQueue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final titleStyle = textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600);
    final countStyle = textTheme.bodyMedium!.mono.copyWith(
      color: scheme.accentText,
      fontWeight: FontWeight.w500,
    );
    final count = '(${l10n.imagesSelected(selectedCount)})';
    final images = state.discoveredImages;
    final allSelected = selectedCount == images.length;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: kDownloaderGutter),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final addWidth = AppSpace.s16 * 2 +
              AppSize.iconMd +
              8 +
              measureGlassText(context, l10n.addToQueue, textTheme.labelLarge!);
          final fullWidth = measureGlassText(context, l10n.selectImagesToDownload, titleStyle) +
              8 +
              measureGlassText(context, count, countStyle) +
              AppSpace.s16 +
              DownloaderActionButton.widthFor(context, label: l10n.selectAll, height: AppSize.compact) +
              8 +
              addWidth;
          final labelled = fullWidth <= constraints.maxWidth;

          return Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        l10n.selectImagesToDownload,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        count,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: countStyle,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.s16),
              DownloaderActionButton(
                icon: Icons.select_all,
                label: labelled ? l10n.selectAll : null,
                tooltip: labelled ? null : l10n.selectAll,
                height: labelled ? AppSize.compact : AppSize.control,
                onPressed: allSelected
                    ? null
                    : () {
                        for (final img in images) {
                          img.isSelected = true;
                        }
                        state.notify();
                      },
              ),
              const SizedBox(width: 8),
              AppButton(
                label: l10n.addToQueue,
                icon: Icons.playlist_add,
                onPressed: selectedCount > 0 ? onAddToQueue : null,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Fixed-size tiles (`卡 168`, tablet 150) laid from the left with the slack
/// on the right, rather than stretched to fill the row.
class _ResultsGrid extends StatelessWidget {
  const _ResultsGrid({required this.state});

  final DownloaderState state;

  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    final cell = Responsive.isDesktop(context) ? 168.0 : 150.0;
    final images = state.discoveredImages;

    return LayoutBuilder(
      builder: (context, constraints) {
        final inner = math.max(0.0, constraints.maxWidth - 2 * kDownloaderGutter);
        final columns = math.max(1, ((inner + _gap) / (cell + _gap)).floor());
        final extent = math.min(cell, inner);
        final used = columns * extent + (columns - 1) * _gap;
        final slack = math.max(0.0, inner - used);

        return GridView.builder(
          padding: EdgeInsets.fromLTRB(kDownloaderGutter, 14, kDownloaderGutter + slack, 14),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: _gap,
            crossAxisSpacing: _gap,
          ),
          itemCount: images.length,
          itemBuilder: (context, index) {
            final img = images[index];
            return DownloaderImageCard(
              key: ObjectKey(img),
              image: img,
              extent: extent,
              onToggle: () {
                img.isSelected = !img.isSelected;
                state.notify();
              },
            );
          },
        );
      },
    );
  }
}

/// `24 found · 8 selected` on the left with the selection in the deep ink;
/// the filename prefix and output folder on the right.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.found, required this.selected, required this.prefix});

  final int found;
  final int selected;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelSmall!.mono.copyWith(
          fontWeight: FontWeight.w400,
          color: scheme.onSurfaceVariant,
        );
    final output = Provider.of<AppState>(context, listen: false).galleryState.outputDirectory;

    Widget? counts;
    if (found > 0) {
      final full = l10n.downloaderFoundSelected(found, selected);
      final part = l10n.imagesSelected(selected);
      final at = full.lastIndexOf(part);
      counts = Text.rich(
        TextSpan(
          style: base,
          children: at < 0
              ? [TextSpan(text: full)]
              : [
                  TextSpan(text: full.substring(0, at)),
                  TextSpan(
                    text: part,
                    style: TextStyle(color: scheme.accentText, fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: full.substring(at + part.length)),
                ],
        ),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      );
    }

    final destination = [
      if (prefix.isNotEmpty) '${l10n.prefix} $prefix',
      if (output != null && output.isNotEmpty) '${l10n.outputDirectory} $output',
    ].join(' · ');

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: kDownloaderGutter),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          if (counts != null) ...[
            Flexible(child: counts),
            const SizedBox(width: AppSpace.s16),
          ],
          Expanded(
            child: Text(
              destination,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: base,
            ),
          ),
        ],
      ),
    );
  }
}

/// `1b`: nothing found yet and the model still looking.
class _AnalyzingState extends StatelessWidget {
  const _AnalyzingState({required this.logs});

  final List<String> logs;

  static final RegExp _timestamp = RegExp(r'^\[[^\]]*\]\s*');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tail = logs.isEmpty ? null : logs.last.replaceFirst(_timestamp, '');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(kDownloaderGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: AppSize.iconLg,
              child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.analyzing,
              textAlign: TextAlign.center,
              style: textTheme.titleSmall!.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (tail != null) ...[
              const SizedBox(height: AppSpace.s4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  tail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: textTheme.labelSmall!.mono.copyWith(
                    fontWeight: FontWeight.w400,
                    color: scheme.outline,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// `1d` 退化态: manual mode is on and there is no page source to read yet.
class _ManualHtmlEmptyState extends StatelessWidget {
  const _ManualHtmlEmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(kDownloaderGutter),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: DashedBorder(
            color: scheme.outlineVariant,
            radius: AppRadius.control,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s22, vertical: AppSpace.s28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.content_paste_off, size: 28, color: scheme.outline),
                  const SizedBox(height: AppSpace.s10),
                  Text(
                    l10n.manualHtmlEmptyTitle,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: AppSpace.s4),
                  Text(
                    l10n.manualHtmlEmptyDesc,
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
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

/// The three-step guide (`1b` 空态): a sentence over three 220px cards, each
/// with its step number on the accent wash.
class _EmptyGuide extends StatelessWidget {
  const _EmptyGuide();

  /// The localised titles carry their own `1 · ` prefix; the card sets the
  /// number in its badge, so it is lifted off the front when present.
  static final RegExp _numbered = RegExp(r'^\s*(\d+)\s*·\s*(.+)$');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final steps = [
      (l10n.guideStep1Title, l10n.guideStep1Desc),
      (l10n.guideStep2Title, l10n.guideStep2Desc),
      (l10n.guideStep3Title, l10n.guideStep3Desc),
    ];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(kDownloaderGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.noImagesDiscovered,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium!.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpace.s16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                for (final (i, (title, description)) in steps.indexed)
                  () {
                    final match = _numbered.firstMatch(title);
                    return _GuideCard(
                      number: match?.group(1) ?? '${i + 1}',
                      title: match?.group(2) ?? title,
                      description: description,
                    );
                  }(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.number, required this.title, required this.description});

  final String number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppSize.compact,
            height: AppSize.compact,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.accentTint,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              number,
              maxLines: 1,
              style: textTheme.labelLarge!.mono.copyWith(
                color: scheme.onAccentTint,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: AppSpace.s10),
          Text(title, style: textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpace.s4),
          Text(
            description,
            style: textTheme.bodySmall!.copyWith(
              color: scheme.onSurfaceVariant,
              height: AppType.looseHeight,
            ),
          ),
        ],
      ),
    );
  }
}
