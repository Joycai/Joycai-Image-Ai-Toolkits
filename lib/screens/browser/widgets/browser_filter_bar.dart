import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/browser_file.dart';
import '../../../state/file_browser_state.dart';
import '../../../widgets/dialogs/thumbnail_size_dialog.dart';
import '../../../widgets/glass/glass_controls.dart' show measureGlassText;
import '../../../widgets/thumbnail_fit_toggle.dart';

/// The 40px control row under the header — `B1a · 1a`.
///
/// Category segments on the left (All / Images / Videos / Audio / Text /
/// Other, 24 tall, the chosen one on the 12% wash), then the sort button, then
/// — in grid view only — the thumbnail-size slider and the fit toggle.
///
/// When the row cannot hold the slider beside the categories and the sort
/// button (measured, not a breakpoint), the slider gives way to a size button
/// that opens the same control in a dialog, so the setting is never lost.
class BrowserFilterBar extends StatelessWidget {
  final FileBrowserState state;

  const BrowserFilterBar({
    super.key,
    required this.state,
  });

  static const double height = 40;

  static const double _chipGap = 2;
  static const double _groupGap = 12;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isGrid = state.viewMode == BrowserViewMode.grid;

          double chipsWidth = 0;
          for (final cat in FileCategory.values) {
            chipsWidth += _CategoryChip.widthFor(context, _categoryLabel(cat, l10n)) + _chipGap;
          }
          final sortWidth = _SortChip.widthFor(context, _sortFieldLabel(state.sortField, l10n));
          final sliderWidth = _ThumbnailSizeSlider.widthFor(context);
          final showSlider = isGrid &&
              chipsWidth + _groupGap + sortWidth + _groupGap + sliderWidth + AppSpace.s4 + AppSize.compact <=
                  constraints.maxWidth;

          return Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final cat in FileCategory.values) ...[
                          _CategoryChip(
                            label: _categoryLabel(cat, l10n),
                            selected: state.currentFilter == cat,
                            onTap: () => state.setFilter(cat),
                          ),
                          const SizedBox(width: _chipGap),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: _groupGap),
              _buildSortControl(context, l10n),
              if (isGrid) ...[
                const SizedBox(width: _groupGap),
                if (showSlider)
                  _ThumbnailSizeSlider(state: state)
                else
                  SizedBox.square(
                    dimension: AppSize.compact,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.photo_size_select_large, size: AppSize.iconMd),
                      tooltip: l10n.thumbnailSize,
                      onPressed: () => showThumbnailSizeDialog(
                        context,
                        initialSize: state.thumbnailSize,
                        onChanged: state.setThumbnailSize,
                        onChangeEnd: state.persistThumbnailSize,
                      ),
                    ),
                  ),
                const SizedBox(width: AppSpace.s4),
                const ThumbnailFitToggle(size: AppSize.compact, iconSize: AppSize.iconMd),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Sort field and direction in one menu (Name / Modify Date / File Type,
  /// then ascending / descending).
  Widget _buildSortControl(BuildContext context, AppLocalizations l10n) {
    return PopupMenuButton<Object>(
      tooltip: l10n.sortBy,
      position: PopupMenuPosition.under,
      onSelected: (value) {
        if (value is BrowserSortField) {
          state.setSortField(value);
        } else if (value is bool) {
          state.setSortAscending(value);
        }
      },
      itemBuilder: (context) => [
        for (final field in BrowserSortField.values)
          CheckedPopupMenuItem(
            value: field,
            checked: state.sortField == field,
            child: Text(
              _sortFieldLabel(field, l10n),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          value: true,
          checked: state.sortAscending,
          child: Text(l10n.sortAsc, style: Theme.of(context).textTheme.labelLarge),
        ),
        CheckedPopupMenuItem(
          value: false,
          checked: !state.sortAscending,
          child: Text(l10n.sortDesc, style: Theme.of(context).textTheme.labelLarge),
        ),
      ],
      child: _SortChip(
        label: _sortFieldLabel(state.sortField, l10n),
        ascending: state.sortAscending,
      ),
    );
  }

  static String _sortFieldLabel(BrowserSortField field, AppLocalizations l10n) {
    switch (field) {
      case BrowserSortField.name:
        return l10n.sortName;
      case BrowserSortField.date:
        return l10n.sortDate;
      case BrowserSortField.type:
        return l10n.sortType;
    }
  }

  static String _categoryLabel(FileCategory cat, AppLocalizations l10n) {
    switch (cat) {
      case FileCategory.all:
        return l10n.catAll;
      case FileCategory.image:
        return l10n.catImages;
      case FileCategory.video:
        return l10n.catVideos;
      case FileCategory.audio:
        return l10n.catAudio;
      case FileCategory.text:
        return l10n.catText;
      case FileCategory.other:
        return l10n.catOthers;
    }
  }
}

/// One category segment: 24 tall at r6. Only the chosen one is drawn — the
/// 12% wash under the deep ink — so six options do not read as six buttons.
class _CategoryChip extends StatefulWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const double _height = 24;
  static const double _padding = AppSpace.s10;

  static TextStyle _style(BuildContext context, {required bool selected}) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          );

  /// Measured at the selected weight, so choosing one never widens the row.
  static double widthFor(BuildContext context, String label) =>
      (_padding * 2 + measureGlassText(context, label, _style(context, selected: true))).ceilToDouble();

  @override
  State<_CategoryChip> createState() => _CategoryChipState();
}

class _CategoryChipState extends State<_CategoryChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;

    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: selected ? SystemMouseCursors.basic : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: selected ? null : widget.onTap,
          child: AnimatedContainer(
            duration: AppMotion.durationOf(context, AppMotion.hover),
            curve: AppMotion.quick,
            height: _CategoryChip._height,
            padding: const EdgeInsets.symmetric(horizontal: _CategoryChip._padding),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? scheme.accentTint
                  : (_hovered ? scheme.onSurface.withValues(alpha: 0.06) : scheme.onSurface.withValues(alpha: 0)),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              widget.label,
              maxLines: 1,
              style: _CategoryChip._style(context, selected: selected).copyWith(
                color: selected ? scheme.onAccentTint : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The sort button's face: 28 tall at r10 on the panel colour with a
/// hairline — `sort`, the field, and the direction's arrow.
class _SortChip extends StatelessWidget {
  const _SortChip({required this.label, required this.ascending});

  final String label;
  final bool ascending;

  static TextStyle _style(BuildContext context) => Theme.of(context).textTheme.bodySmall!;

  static double widthFor(BuildContext context, String label) =>
      (2 + AppSpace.s10 + AppSize.iconSm + AppSpace.s6 + measureGlassText(context, label, _style(context)) +
              AppSpace.s4 + AppSize.iconSm + AppSpace.s10)
          .ceilToDouble();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: AppSize.compact,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sort, size: AppSize.iconSm, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpace.s6),
          Text(label, maxLines: 1, style: _style(context).copyWith(color: scheme.onSurface)),
          const SizedBox(width: AppSpace.s4),
          Icon(
            ascending ? Icons.arrow_upward : Icons.arrow_downward,
            size: AppSize.iconSm,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

/// The thumbnail-size slider (`1a`): an 80×4 track, filled in the accent, a
/// 16px panel-coloured handle ringed 2px in the accent, and the size in mono.
class _ThumbnailSizeSlider extends StatelessWidget {
  const _ThumbnailSizeSlider({required this.state});

  final FileBrowserState state;

  static const double _min = 80;
  static const double _max = 400;
  static const double _trackWidth = 80;
  static const double _thumbDiameter = 16;

  static TextStyle _valueStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall!.mono.copyWith(fontWeight: FontWeight.w400);

  static double _valueWidth(BuildContext context) =>
      measureGlassText(context, '${_max.round()}', _valueStyle(context)).ceilToDouble();

  static double widthFor(BuildContext context) =>
      _trackWidth + _thumbDiameter + AppSpace.s6 + _valueWidth(context);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final value = state.thumbnailSize.clamp(_min, _max);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          // The handle overhangs both ends of the track by its radius.
          width: _trackWidth + _thumbDiameter,
          height: AppSize.compact,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              padding: EdgeInsets.zero,
              activeTrackColor: scheme.primary,
              inactiveTrackColor: scheme.surfaceContainerHighest,
              thumbColor: scheme.primary,
              overlayColor: Colors.transparent,
              trackShape: const RoundedRectSliderTrackShape(),
              thumbShape: _RingThumbShape(fill: scheme.surface, ring: scheme.primary),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
              tickMarkShape: SliderTickMarkShape.noTickMark,
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              value: value,
              min: _min,
              max: _max,
              semanticFormatterCallback: (v) => '${l10n.thumbnailSize} ${v.round()}',
              onChanged: state.setThumbnailSize,
              onChangeEnd: (_) => state.persistThumbnailSize(),
            ),
          ),
        ),
        const SizedBox(width: AppSpace.s6),
        SizedBox(
          width: _valueWidth(context),
          child: Text(
            '${value.round()}',
            maxLines: 1,
            textAlign: TextAlign.right,
            style: _valueStyle(context).copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// A 16px handle: the panel colour ringed 2px in the accent.
class _RingThumbShape extends SliderComponentShape {
  const _RingThumbShape({required this.fill, required this.ring});

  final Color fill;
  final Color ring;

  static const double _radius = _ThumbnailSizeSlider._thumbDiameter / 2;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size.fromRadius(_radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(center, _radius, Paint()..color = fill);
    canvas.drawCircle(
      center,
      _radius - 1,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}
