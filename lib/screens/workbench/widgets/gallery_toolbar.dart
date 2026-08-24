import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/design_tokens.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../state/gallery_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/dialogs/thumbnail_size_dialog.dart';

class GalleryToolbar extends StatelessWidget {
  const GalleryToolbar({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    // Everything this bar shows is gallery state, so it subscribes there
    // rather than through AppState, which no longer forwards it.
    final galleryState = context.watch<GalleryState>();
    final isDesktop = Responsive.isDesktop(context);
    final isNarrow = Responsive.isNarrow(context);

    final selectedCount = galleryState.selectedImages.length;
    final selectableCount = galleryState.galleryImages.where((img) => !AppConstants.isVideoFile(img.path)).length;
    final thumbnailSize = galleryState.thumbnailSize;

    // Measured against this bar, not the window. The centre panel is what
    // squeezes here -- open both side panels on a wide screen and the screen
    // is still "desktop" while this bar has a few hundred pixels, which is how
    // the view toggle ended up clipped mid-word.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Measured, not a constant. The labels here are localised and the
        // user can scale text, so no fixed pixel threshold is right in every
        // case -- one tuned to English clips Japanese, and one padded for
        // Japanese collapses an English bar that had room to spare.
        final canInline =
            constraints.maxWidth >= _inlineWidthNeeded(context, l10n, selectedCount, isDesktop);

        // The toggle keeps its natural width in every case the trailing
        // controls can resolve by collapsing. Only once they have collapsed
        // as far as they go -- one menu, plus the camera on touch -- and the
        // bar is *still* too narrow does it give up space, and then it scrolls
        // rather than overflowing. That floor is far below any width the panel
        // minimums allow; it exists so a pathological layout degrades quietly.
        // The overflow menu, plus the camera button that stays inline on touch.
        final collapsedTrailing = _kIconButton * (isDesktop ? 1 : 2) + _kFitMargin;
        final toggleCap = math.max(
          0.0,
          constraints.maxWidth - _kBarPadding - _kToggleGap - collapsedTrailing,
        );
        final toggleWidth = math.min(_toggleNaturalWidth(context, l10n), toggleCap);

        // Controls that act on the grid as a whole: what is selected, and how
        // big the tiles are. Kept to the right beside refresh and import, so
        // the left of the bar carries only the view state.
        final gridControls = <Widget>[
          IconButton(
            onPressed: () => galleryState.selectAllImages(),
            icon: const Icon(Icons.select_all, size: 20),
            tooltip: '${l10n.selectAll} ($selectableCount)',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: selectedCount == 0 ? null : () => galleryState.clearImageSelection(),
            icon: const Icon(Icons.deselect, size: 20),
            tooltip: l10n.clear,
            visualDensity: VisualDensity.compact,
          ),
          if (!isDesktop && galleryState.droppedImages.isNotEmpty) ...[
            _divider(colorScheme),
            AppButton(
              label: l10n.clearTempWorkspace,
              icon: Icons.delete_sweep_outlined,
              variant: AppButtonVariant.destructiveText,
              onPressed: () => galleryState.clearDroppedImages(),
            ),
          ],
          _divider(colorScheme),
          _buildZoomSlider(context, galleryState, colorScheme, thumbnailSize),
        ];

        return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        // The centre column's own header. Opaque #FAFBFF over a transparent
        // column, matching the toolbar above and the two side columns beside
        // it — the gallery below is the only part of this screen the spec
        // leaves bare.
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        // A full pixel, and the panel edge tone rather than the theme divider.
        // At 0.5 this landed on a half pixel and rendered as a grey smear on
        // some scale factors and as nothing at all on others.
        border: Border(
          bottom: BorderSide(color: Theme.of(context).colorScheme.surfaceContainerHigh),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: toggleWidth,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildViewToggle(context, galleryState, colorScheme, l10n),
            ),
          ),
          const SizedBox(width: _kToggleGap),
          // Expanded, so the slack lands here and never on the toggle.
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildSelectionChip(
                context,
                colorScheme,
                l10n,
                selectedCount,
                isNarrow || !canInline,
              ),
            ),
          ),

          if (canInline) ...[
            ...gridControls,
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () => galleryState.refreshImages(),
              tooltip: l10n.refresh,
            ),
            _divider(colorScheme),
          ],

          // Capture stays a direct target on touch layouts even when the bar
          // is tight -- it is the one action with no keyboard equivalent.
          if (!isDesktop)
            IconButton(
              icon: const Icon(Icons.camera_alt_outlined, size: 22),
              onPressed: () => _pickFromCamera(galleryState),
              tooltip: l10n.takePhoto,
            ),

          if (canInline)
            AppButton(
              label: l10n.importFromGallery,
              icon: Icons.photo_library_outlined,
              variant: AppButtonVariant.text,
              onPressed: () => _pickFromGallery(galleryState),
            )
          else
            _buildOverflowMenu(context, galleryState, l10n, selectedCount, thumbnailSize, isDesktop),
        ],
      ),
        );
      },
    );
  }

  /// Everything that did not fit, in one menu.
  ///
  /// The view toggle is the only control this bar will not give up, so when
  /// the centre panel narrows the rest collapses here rather than each item
  /// shrinking until the labels break. The thumbnail slider becomes a dialog
  /// entry: a slider inside a popup menu is not draggable in any useful way.
  Widget _buildOverflowMenu(
    BuildContext context,
    GalleryState galleryState,
    AppLocalizations l10n,
    int selectedCount,
    double thumbnailSize,
    bool isDesktop,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      tooltip: l10n.more,
      onSelected: (val) async {
        switch (val) {
          case 'select_all':
            galleryState.selectAllImages();
          case 'clear_selection':
            galleryState.clearImageSelection();
          case 'thumbnail_size':
            if (context.mounted) {
              _showThumbnailSizeDialog(context, galleryState, thumbnailSize, l10n);
            }
          case 'refresh':
            galleryState.refreshImages();
          case 'clear_temp':
            galleryState.clearDroppedImages();
          case 'camera':
            await _pickFromCamera(galleryState);
          case 'import':
            await _pickFromGallery(galleryState);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'select_all',
          child: ListTile(
            leading: const Icon(Icons.select_all),
            title: Text(l10n.selectAll),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: 'clear_selection',
          enabled: selectedCount > 0,
          child: ListTile(
            leading: const Icon(Icons.deselect),
            title: Text(l10n.clear),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: 'thumbnail_size',
          child: ListTile(
            leading: const Icon(Icons.grid_view),
            title: Text(l10n.thumbnailSize),
            dense: true,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'refresh',
          child: ListTile(
            leading: const Icon(Icons.refresh),
            title: Text(l10n.refresh),
            dense: true,
          ),
        ),
        if (galleryState.droppedImages.isNotEmpty)
          PopupMenuItem(
            value: 'clear_temp',
            child: ListTile(
              leading: Icon(Icons.delete_sweep_outlined, color: colorScheme.error),
              title: Text(l10n.clearTempWorkspace, style: TextStyle(color: colorScheme.error)),
              dense: true,
            ),
          ),
        const PopupMenuDivider(),
        if (!isDesktop)
          PopupMenuItem(
            value: 'camera',
            child: ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(l10n.takePhoto),
              dense: true,
            ),
          ),
        PopupMenuItem(
          value: 'import',
          child: ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(l10n.importFromGallery),
            dense: true,
          ),
        ),
      ],
    );
  }

  Future<void> _pickFromCamera(GalleryState galleryState) async {
    final photo = await ImagePicker().pickImage(source: ImageSource.camera);
    if (photo == null) return;
    galleryState.addDroppedFiles([AppImage(path: photo.path, name: photo.name)]);
    galleryState.setViewMode(GalleryViewMode.temp);
  }

  Future<void> _pickFromGallery(GalleryState galleryState) async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty) return;
    galleryState.addDroppedFiles(
      picked.map((f) => AppImage(path: f.path, name: f.name)).toList(),
    );
    galleryState.setViewMode(GalleryViewMode.temp);
  }

  /// The width this bar needs before the controls right of the view toggle
  /// can sit inline instead of collapsing into the overflow menu.
  ///
  /// Built up from the actual text rather than a magic number: see the call
  /// site. The fixed parts are the paddings and icon buttons, which do not
  /// move with the locale; everything with a label is measured.
  double _measureText(BuildContext context, String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }

  /// The view toggle at its natural size: two labels, each in its own padded
  /// button, inside a padded track. Measured at the selected weight, which is
  /// the wider of the two the label can take.
  double _toggleNaturalWidth(BuildContext context, AppLocalizations l10n) {
    final label = Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600);
    return _measureText(context, l10n.allSources, label) +
        _measureText(context, l10n.allResults, label) +
        _kToggleChrome;
  }

  double _inlineWidthNeeded(
    BuildContext context,
    AppLocalizations l10n,
    int selectedCount,
    bool isDesktop,
  ) {
    final textTheme = Theme.of(context).textTheme;

    final chip =
        _measureText(context, l10n.selectedCount(selectedCount), textTheme.labelMedium) + _kChipChrome;
    final import =
        _measureText(context, l10n.importFromGallery, textTheme.labelLarge) + _kLabelledButtonChrome;

    return _kBarPadding +
        _toggleNaturalWidth(context, l10n) +
        _kToggleGap +
        chip +
        _kIconButtonCompact * 2 + // select all, deselect
        _kDivider +
        _kZoomSlider +
        _kIconButton + // refresh
        _kDivider +
        (isDesktop ? 0 : _kIconButton) + // camera stays inline on touch
        import +
        _kFitMargin;
  }

  // Widths of the parts that carry no text, so they do not shift with locale.
  static const double _kBarPadding = 32; // Container's horizontal padding
  static const double _kToggleChrome = 50; // two button paddings + track padding
  static const double _kToggleGap = 10;
  static const double _kChipChrome = 20;
  static const double _kLabelledButtonChrome = 50; // icon + gap + button padding
  static const double _kIconButton = 48; // Material's default tap target
  static const double _kIconButtonCompact = 40; // visualDensity: compact
  static const double _kDivider = 17;
  static const double _kZoomSlider = 139; // small icon + track + large icon
  static const double _kFitMargin = 12; // so the last pixel is never the deciding one

  /// Hairline between control groups.
  ///
  /// An explicit box, not [VerticalDivider]: that one takes its height from
  /// the parent, and a [Row] hands its children loose vertical constraints —
  /// so every divider in this bar was collapsing to nothing and the groups
  /// ran together.
  Widget _divider(ColorScheme colorScheme) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Container(width: 1, height: 20, color: colorScheme.outlineVariant),
      );

  /// How many pictures are picked.
  ///
  /// A chip rather than a run of plain text: this is the count the Process
  /// button and the reference strip both act on, and as bare grey text beside
  /// a segmented control it read as a caption for the control instead of a
  /// state of its own. Accented only while something *is* selected — at zero
  /// there is no state to announce, so it stays neutral.
  Widget _buildSelectionChip(
    BuildContext context,
    ColorScheme colorScheme,
    AppLocalizations l10n,
    int selectedCount,
    bool isNarrow,
  ) {
    final active = selectedCount > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active
            ? colorScheme.primary.withValues(alpha: 0.12)
            : colorScheme.surfaceContainerHighest.withAlpha(140),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isNarrow ? '$selectedCount' : l10n.selectedCount(selectedCount),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: active ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  /// Tile-size control: small square, track, large square.
  ///
  /// The track is neutral. A thumbnail size is a viewing preference, not a
  /// choice about the work, and leaving it accented put the brightest thing
  /// in the bar on the one control that changes nothing about the output.
  Widget _buildZoomSlider(
    BuildContext context,
    GalleryState galleryState,
    ColorScheme colorScheme,
    double thumbnailSize,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.crop_square, size: 13, color: colorScheme.onSurfaceVariant),
        SizedBox(
          width: 100,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              // `10e` 「滑杆」 splits the family in two: a *parameter* slider
              // changes a value and takes the accent, a *neutral* one changes
              // how you are looking at something and stays greyscale. A
              // thumbnail size is the second kind — the app-wide
              // [SliderThemeData] is the first, so this row states its own.
              // Thinner and smaller-thumbed than the accent one, too: 3 and
              // 12 against 4 and 14.
              trackHeight: 3,
              activeTrackColor: colorScheme.onSurfaceVariant,
              inactiveTrackColor: colorScheme.outlineVariant,
              thumbColor: colorScheme.onSurfaceVariant,
              overlayColor: colorScheme.onSurface.withValues(alpha: 0.08),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: thumbnailSize,
              min: 80,
              max: 400,
              onChanged: galleryState.setThumbnailSize,
              // Persisted on release, not per frame: the setter is called
              // sixty times a second while this is dragged.
              onChangeEnd: (_) => galleryState.persistThumbnailSize(),
            ),
          ),
        ),
        Icon(Icons.crop_square, size: 18, color: colorScheme.onSurfaceVariant),
      ],
    );
  }

  /// Source / Results segmented toggle — replaces the old breadcrumb.
  Widget _buildViewToggle(BuildContext context, GalleryState gs, ColorScheme colorScheme, AppLocalizations l10n) {
    final isSource = gs.viewMode == GalleryViewMode.all ||
        gs.viewMode == GalleryViewMode.folder;
    final isResult = gs.viewMode == GalleryViewMode.processed ||
        gs.viewMode == GalleryViewMode.temp;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(140),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleButton(
            context: context,
            label: l10n.allSources,
            selected: isSource,
            colorScheme: colorScheme,
            onTap: () => gs.setViewMode(GalleryViewMode.all),
          ),
          _buildToggleButton(
            context: context,
            label: l10n.allResults,
            selected: isResult,
            colorScheme: colorScheme,
            onTap: () => gs.setViewMode(GalleryViewMode.processed),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required BuildContext context,
    required String label,
    required bool selected,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
  }) {
    return AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.state),
      curve: AppMotion.enter,
      decoration: BoxDecoration(
        color: selected ? colorScheme.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        boxShadow: selected ? colorScheme.shadowRaised : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ),
      ),
    );
  }

  void _showThumbnailSizeDialog(BuildContext context, GalleryState state, double current, AppLocalizations l10n) {
    showThumbnailSizeDialog(
      context,
      initialSize: current,
      onChanged: state.setThumbnailSize,
      onChangeEnd: state.persistThumbnailSize,
    );
  }
}