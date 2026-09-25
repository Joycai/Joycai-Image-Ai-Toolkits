import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/browser_file.dart';
import '../../../state/file_browser_state.dart';
import '../../../widgets/dialogs/thumbnail_size_dialog.dart';
import '../../../widgets/files/thumbnail_fit_toggle.dart';
import '../../../widgets/glass/app_glass_menu.dart';
import '../../../widgets/glass/glass_controls.dart' show measureGlassText;

/// The 40px control row under the header — `B1a · 1a`.
///
/// Category segments on the left (All / Images / Videos / Audio / Text /
/// Other, 24 tall, the chosen one on the 12% wash), the sort button right
/// beside them (`1f`), then — in grid view only, at the far right — the
/// thumbnail-size slider and the fit toggle.
///
/// When the row cannot hold the slider beside the categories and the sort
/// button (measured, not a breakpoint), the slider gives way to a size button
/// that opens the same control in a dialog, so the setting is never lost.
/// The five things this bar draws out of the state. Not the selection, not
/// the file list — a bar of filters must not rebuild because a file was
/// picked.
typedef _FilterInputs = ({
  BrowserViewMode viewMode,
  FileCategory currentFilter,
  BrowserSortField sortField,
  bool sortAscending,
  double thumbnailSize,
  bool groupByFolder,
  bool canGroup,
});

_FilterInputs _filterInputs(FileBrowserState s) => (
      viewMode: s.viewMode,
      currentFilter: s.currentFilter,
      sortField: s.sortField,
      sortAscending: s.sortAscending,
      thumbnailSize: s.thumbnailSize,
      groupByFolder: s.groupByFolder,
      canGroup: s.activeDirectories.length > 1,
    );


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
    final inputs = context.select<FileBrowserState, _FilterInputs>(_filterInputs);

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isGrid = inputs.viewMode == BrowserViewMode.grid;

          double chipsWidth = 0;
          for (final cat in FileCategory.values) {
            chipsWidth += _CategoryChip.widthFor(context, _categoryLabel(cat, l10n)) + _chipGap;
          }
          final sortWidth = _SortChip.widthFor(context, _sortFieldLabel(inputs.sortField, l10n));
          final sliderWidth = _ThumbnailSizeSlider.widthFor(context);
          final showSlider = isGrid &&
              chipsWidth + _groupGap + sortWidth + _groupGap + sliderWidth + AppSpace.s4 + AppSize.compact <=
                  constraints.maxWidth;

          return Row(
            children: [
              // Categories and sort share one Expanded, so the size controls
              // are pinned to the row's end. A Flexible beside a Spacer would
              // split the spare room with it and leave them short of the edge
              // on a wide window.
              Expanded(
                child: Row(
                  children: [
                    // The categories take what they need and no more, so the sort
                    // button sits right after them rather than at the row's end.
                    // Capped at the chips' measured width: a horizontal scroll
                    // view sizes to all it is offered, which would push the
                    // sort button to the far end of the Expanded.
                    Flexible(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: chipsWidth),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final cat in FileCategory.values) ...[
                                _CategoryChip(
                                  label: _categoryLabel(cat, l10n),
                                  selected: inputs.currentFilter == cat,
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
                    _SortButton(state: state, inputs: inputs),
                  ],
                ),
              ),
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
                        initialSize: inputs.thumbnailSize,
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

/// The sort button and its menu (`B1a · 1f`): field, direction and the
/// folder grouping in one glass float, 220 wide, hanging off the button's
/// left edge. Choice rows draw radios and a checkbox rather than Material's
/// check marks, and the grouping row explains itself under its label.
class _SortButton extends StatefulWidget {
  const _SortButton({required this.state, required this.inputs});

  final FileBrowserState state;
  final _FilterInputs inputs;

  static const double menuWidth = 220;

  @override
  State<_SortButton> createState() => _SortButtonState();
}

class _SortButtonState extends State<_SortButton> {
  bool _open = false;

  Future<void> _openMenu() async {
    final l10n = AppLocalizations.of(context)!;
    final state = widget.state;
    final inputs = widget.inputs;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    setState(() => _open = true);
    try {
      await showAppGlassMenu(
        context,
        position: box.localToGlobal(Offset(0, box.size.height + AppSpace.s4)),
        width: _SortButton.menuWidth,
        entries: [
          for (final field in BrowserSortField.values)
            AppGlassMenuItem(
              label: BrowserFilterBar._sortFieldLabel(field, l10n),
              checked: inputs.sortField == field,
              radio: true,
              onSelected: () => state.setSortField(field),
            ),
          const AppGlassMenuDivider(),
          AppGlassMenuItem(
            label: l10n.sortAsc,
            checked: inputs.sortAscending,
            radio: true,
            onSelected: () => state.setSortAscending(true),
          ),
          AppGlassMenuItem(
            label: l10n.sortDesc,
            checked: !inputs.sortAscending,
            radio: true,
            onSelected: () => state.setSortAscending(false),
          ),
          const AppGlassMenuDivider(),
          // Folder by folder, or one interleaved run. The row stays with one
          // folder listed — it has nothing to do until a second is — and
          // the hint says so.
          AppGlassMenuItem(
            label: l10n.browserGroupByFolder,
            hint: l10n.browserGroupByFolderHint,
            checked: inputs.groupByFolder,
            onSelected: () => state.setGroupByFolder(!inputs.groupByFolder),
          ),
        ],
      );
    } finally {
      if (mounted) setState(() => _open = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Tooltip(
      message: l10n.sortBy,
      child: Semantics(
        button: true,
        expanded: _open,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openMenu,
            child: _SortChip(
              label: BrowserFilterBar._sortFieldLabel(widget.inputs.sortField, l10n),
              ascending: widget.inputs.sortAscending,
              open: _open,
            ),
          ),
        ),
      ),
    );
  }
}

/// The sort button's face: 28 tall at r10 on the panel colour with a
/// hairline — `sort`, the field, and the direction's arrow. While its menu
/// is open the hairline turns accent inside the 32% ring (`1f`).
class _SortChip extends StatelessWidget {
  const _SortChip({required this.label, required this.ascending, this.open = false});

  final String label;
  final bool ascending;
  final bool open;

  static TextStyle _style(BuildContext context) => Theme.of(context).textTheme.bodySmall!;

  static double widthFor(BuildContext context, String label) =>
      (2 + AppSpace.s10 + AppSize.iconSm + AppSpace.s6 + measureGlassText(context, label, _style(context)) +
              AppSpace.s4 + AppSize.iconSm + AppSpace.s10)
          .ceilToDouble();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.hover),
      curve: AppMotion.quick,
      height: AppSize.compact,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: open ? scheme.primary : scheme.outlineVariant),
        boxShadow: open ? [BoxShadow(color: scheme.accentRing, spreadRadius: 3)] : const [],
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
