import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design_tokens.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/image_metadata_service.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_icon_button.dart';
import 'workbench_tool_header.dart';

/// The mask editor's header: leave, see what is being masked, pick a colour
/// and a brush, undo, and save.
///
/// Built on [WorkbenchToolHeader], which owns the back button — file caption,
/// hairline dividers between groups, the two save actions at the right.
class MaskEditorToolbar extends StatefulWidget {
  final VoidCallback onUndo;
  final VoidCallback onClear;
  final VoidCallback onSave;
  final VoidCallback onSaveMask;
  final Function(Color) onColorChanged;
  final Function(double) onBrushSizeChanged;
  final Function(double) onOpacityChanged;
  final VoidCallback onToggleBinary;
  final Color selectedColor;
  final double brushSize;
  final double opacity;
  final bool isBinaryMode;
  final bool hasPaths;

  const MaskEditorToolbar({
    super.key,
    required this.onUndo,
    required this.onClear,
    required this.onSave,
    required this.onSaveMask,
    required this.onColorChanged,
    required this.onBrushSizeChanged,
    required this.onOpacityChanged,
    required this.onToggleBinary,
    required this.selectedColor,
    required this.brushSize,
    required this.opacity,
    required this.isBinaryMode,
    required this.hasPaths,
  });

  @override
  State<MaskEditorToolbar> createState() => _MaskEditorToolbarState();
}

class _MaskEditorToolbarState extends State<MaskEditorToolbar> {
  /// Source dimensions for the caption. The view loads this too;
  /// [ImageMetadataService] caches by path, so the second reader costs a map
  /// lookup rather than a second decode.
  ImageMetadata? _meta;
  String? _metaPath;

  void _loadMeta(String path) {
    if (_metaPath == path) return;
    _metaPath = path;
    ImageMetadataService().getMetadata(path).then((meta) {
      if (mounted && _metaPath == path) setState(() => _meta = meta);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isNarrow = Responsive.isNarrow(context);
    final source = Provider.of<WorkbenchUIState>(context).maskEditorSourceImage;

    if (source != null) _loadMeta(source.path);

    return WorkbenchToolHeader(
      children: [
        if (!isNarrow && source != null) ...[
          const SizedBox(width: 10),
          _buildFileInfo(source.name, l10n, colorScheme),
        ],
        const ToolHeaderDivider(),

        // Every editing control shares one scroller: a window too narrow for
        // them scrolls rather than clipping, the same as the crop toolbar.
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildColorGroup(l10n, colorScheme, isNarrow),
                // A phone scrolls nothing but the swatches — a homogeneous
                // row where a half-cut circle at the edge says plainly that
                // there is more. Everything else moves to a fixed position
                // or into the overflow menu, rather than off the end of a
                // scroller with nothing to say it scrolls, which is where
                // clear and binary mode were disappearing to.
                if (!isNarrow) ...[
                  const ToolHeaderDivider(),
                  _buildSlider(
                    label: l10n.brushSize,
                    icon: Icons.brush_outlined,
                    value: widget.brushSize,
                    min: 1,
                    max: 100,
                    width: 110,
                    readout: widget.brushSize.round().toString(),
                    onChanged: widget.onBrushSizeChanged,
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(width: 16),
                  _buildSlider(
                    label: l10n.maskOpacity,
                    icon: Icons.opacity,
                    value: widget.opacity,
                    min: 0.1,
                    max: 1.0,
                    width: 84,
                    readout: '${(widget.opacity * 100).round()}%',
                    onChanged: widget.onOpacityChanged,
                    colorScheme: colorScheme,
                  ),
                  const ToolHeaderDivider(),
                  _buildActionIcons(l10n, colorScheme),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(width: 12),
        _buildSaveActions(l10n, colorScheme, isNarrow),
      ],
    );
  }

  /// Filename over what the export will be — the canvas only ever shows a
  /// fitted preview, so without this the mask's real resolution is invisible.
  Widget _buildFileInfo(String name, AppLocalizations l10n, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    final meta = _meta;

    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name, style: textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (meta != null && meta.width > 0)
            Text(
              l10n.maskSourceCaption(meta.width, meta.height),
              style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  /// The brush colours. Binary mode drops red and green: they would be
  /// flattened to one of the two extremes on export, so offering them there
  /// would be offering a choice the file cannot keep.
  Widget _buildColorGroup(AppLocalizations l10n, ColorScheme colorScheme, bool isNarrow) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isNarrow) ...[
          Text(
            l10n.maskColor,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
        ],
        _buildColorCircle(Colors.white, l10n.white),
        _buildColorCircle(Colors.black, l10n.black),
        if (!widget.isBinaryMode) ...[
          _buildColorCircle(Colors.red, l10n.red),
          _buildColorCircle(Colors.green, l10n.green),
        ],
      ],
    );
  }

  Widget _buildColorCircle(Color color, String tooltip) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = widget.selectedColor == color;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: () => widget.onColorChanged(color),
          child: Container(
            width: 26,
            height: 26,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // The selection ring stands off the swatch rather than thickening
              // its edge — a heavier border on a white swatch reads as a
              // different colour, not as a selection.
              border: Border.all(
                color: isSelected ? colorScheme.primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.outlineVariant),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Label, track and the value it is currently at. The number is the point:
  /// a brush slider with no readout can only be set by drawing and undoing.
  Widget _buildSlider({
    required String label,
    required IconData icon,
    required double value,
    required double min,
    required double max,
    required double width,
    required String readout,
    required ValueChanged<double> onChanged,
    required ColorScheme colorScheme,
  }) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Glyph and readout, no spelled-out label: the words are what pushed
        // the clear button off the end of the row, and between the icon, the
        // tooltip and the live number the control is not ambiguous.
        Tooltip(
          message: label,
          child: Icon(icon, size: AppSize.iconSm, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: width,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              overlayColor: colorScheme.primary.withValues(alpha: 0.08),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(value: value, min: min, max: max, onChanged: onChanged, label: label),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          readout,
          style: textTheme.labelMedium?.copyWith(fontFamily: 'monospace', fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildActionIcons(AppLocalizations l10n, ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconButton(
          icon: Icons.undo,
          tooltip: l10n.undo,
          onPressed: widget.hasPaths ? widget.onUndo : null,
        ),
        const SizedBox(width: 6),
        AppIconButton(
          icon: widget.isBinaryMode ? Icons.contrast : Icons.image_outlined,
          tooltip: l10n.binaryMode,
          selected: widget.isBinaryMode,
          onPressed: widget.onToggleBinary,
        ),
        const SizedBox(width: 6),
        AppIconButton(
          icon: Icons.delete_outline,
          tooltip: l10n.clear,
          color: widget.hasPaths ? colorScheme.error : null,
          onPressed: widget.hasPaths ? widget.onClear : null,
        ),
      ],
    );
  }

  Widget _buildSaveActions(AppLocalizations l10n, ColorScheme colorScheme, bool isNarrow) {
    if (isNarrow) {
      // Everything the narrow row dropped, spelled out. The mask save stays a
      // button of its own: it is what the screen is for, and a phone has room
      // for exactly one such button.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Undo keeps a fixed place of its own: it is the one control a hand
          // reaches for mid-stroke, and a menu is two taps too many for it.
          AppIconButton(
            icon: Icons.undo,
            tooltip: l10n.undo,
            onPressed: widget.hasPaths ? widget.onUndo : null,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            onSelected: (value) {
              switch (value) {
                case 'brush':
                  _showSliderDialog(
                    l10n.brushSize,
                    widget.brushSize,
                    1,
                    100,
                    widget.onBrushSizeChanged,
                    (val) => '${val.toInt()}px',
                  );
                case 'opacity':
                  _showSliderDialog(
                    l10n.maskOpacity,
                    widget.opacity,
                    0.1,
                    1.0,
                    widget.onOpacityChanged,
                    (val) => '${(val * 100).toInt()}%',
                  );
                case 'binary':
                  widget.onToggleBinary();
                case 'composite':
                  widget.onSave();
                case 'clear':
                  widget.onClear();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'brush',
                child: ListTile(
                  leading: const Icon(Icons.brush_outlined),
                  title: Text(l10n.brushSize),
                  trailing: Text(widget.brushSize.round().toString()),
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'opacity',
                child: ListTile(
                  leading: const Icon(Icons.opacity),
                  title: Text(l10n.maskOpacity),
                  trailing: Text('${(widget.opacity * 100).round()}%'),
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'binary',
                child: ListTile(
                  leading: Icon(
                    widget.isBinaryMode ? Icons.contrast : Icons.image_outlined,
                    color: widget.isBinaryMode ? colorScheme.primary : null,
                  ),
                  title: Text(l10n.binaryMode),
                  dense: true,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'composite',
                child: ListTile(
                  leading: const Icon(Icons.layers_outlined),
                  title: Text(l10n.maskSaveComposite),
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                enabled: widget.hasPaths,
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: colorScheme.error),
                  title: Text(l10n.clear, style: TextStyle(color: colorScheme.error)),
                  dense: true,
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
          // No icon on a phone: the glyph is the first thing worth spending
          // for the swatches beside it, and the verb is not.
          AppButton(label: l10n.maskSaveMask, onPressed: widget.onSaveMask),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppButton(
          label: l10n.maskSaveComposite,
          icon: Icons.save_outlined,
          variant: AppButtonVariant.secondary,
          onPressed: widget.onSave,
        ),
        const SizedBox(width: 8),
        AppButton(
          label: l10n.maskSaveMask,
          secondaryLabel: l10n.cropResizeSaveDestinationHint,
          icon: Icons.save_outlined,
          onPressed: widget.onSaveMask,
        ),
      ],
    );
  }

  void _showSliderDialog(
    String title,
    double currentValue,
    double min,
    double max,
    Function(double) onChanged,
    String Function(double) displayConverter,
  ) {
    // Outside the builder, so it survives the rebuilds the drag causes.
    var val = currentValue;

    AppDialog.show<void>(
      context,
      title: title,
      content: StatefulBuilder(
        builder: (context, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Slider(
              value: val,
              min: min,
              max: max,
              onChanged: (newVal) {
                onChanged(newVal);
                setState(() => val = newVal);
              },
            ),
            Text(displayConverter(val)),
          ],
        ),
      ),
      actions: [
        // Same wording the thumbnail-size dialog dismisses with: both are
        // live-preview sliders where the change has already happened, so the
        // button only closes.
        AppButton(
          label: AppLocalizations.of(context)!.confirm,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
