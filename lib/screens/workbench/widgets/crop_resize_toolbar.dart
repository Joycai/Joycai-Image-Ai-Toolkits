import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../services/image_metadata_service.dart';
import '../../../services/image_processing_service.dart';
import '../../../state/app_state.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_icon_button.dart';
import '../../../widgets/app_segmented_control.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/app_tool_button.dart';

/// The fixed set of ratio presets shown as segments, plus a `custom` mode
/// whose X:Y fields only appear once it's selected — folding them into the
/// segmented control instead of always occupying toolbar width.
enum _RatioPreset { free, r1x1, r4x3, r16x9, r3x4, r9x16, custom }

/// Everything the bar spends before any group gets a say: its own horizontal
/// padding, the back button, the two dividers, and the gap before the
/// actions.
const double _kFixedChrome = 32 + 48 + 25 + 25 + 12;

/// The file caption is given a fixed column so a long filename ellipsizes
/// rather than pushing the controls along.
const double _kFileInfoWidth = 190;

/// Room for the number inside a dimension field — wide enough for five
/// digits, which covers any image the editor can open.
const double _kNumberFieldWidth = 46;

/// The X:Y pair that unfolds under the "Custom" segment.
const double _kCustomRatioFieldsWidth = 80;

class CropResizeToolbar extends StatefulWidget {
  const CropResizeToolbar({super.key});

  @override
  State<CropResizeToolbar> createState() => _CropResizeToolbarState();
}

class _CropResizeToolbarState extends State<CropResizeToolbar> {
  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _ratioXController = TextEditingController();
  final TextEditingController _ratioYController = TextEditingController();

  /// null: no save in flight, otherwise 'save' or 'overwrite' — tracks which
  /// button to spin rather than blanking the whole action group.
  String? _processingAction;
  bool _isAutoUpdating = false;
  bool _customRatioMode = false;

  /// Source dimensions for the toolbar caption. The view loads this too;
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
  void initState() {
    super.initState();
    _widthController.addListener(_onWidthChanged);
    _heightController.addListener(_onHeightChanged);
    _ratioXController.addListener(_onRatioChanged);
    _ratioYController.addListener(_onRatioChanged);
  }

  void _onRatioChanged() {
    if (_isAutoUpdating) return;
    final x = double.tryParse(_ratioXController.text);
    final y = double.tryParse(_ratioYController.text);
    if (x != null && y != null && y != 0) {
      Provider.of<WorkbenchUIState>(context, listen: false).setCropAspectRatio(x / y);
    }
  }

  void _onWidthChanged() {
    if (_isAutoUpdating) return;
    final uiState = Provider.of<WorkbenchUIState>(context, listen: false);
    final w = int.tryParse(_widthController.text);

    if (uiState.maintainAspectRatio) {
      final state = uiState.cropKey.currentState as ExtendedImageEditorState?;
      final cropRect = state?.getCropRect();
      if (cropRect != null && w != null) {
        final double ratio = cropRect.width / cropRect.height;
        _isAutoUpdating = true;
        _heightController.text = (w / ratio).round().toString();
        _isAutoUpdating = false;
      }
    }
    uiState.setTargetDimensions(w, int.tryParse(_heightController.text));
  }

  void _onHeightChanged() {
    if (_isAutoUpdating) return;
    final uiState = Provider.of<WorkbenchUIState>(context, listen: false);
    final h = int.tryParse(_heightController.text);

    if (uiState.maintainAspectRatio) {
      final state = uiState.cropKey.currentState as ExtendedImageEditorState?;
      final cropRect = state?.getCropRect();
      if (cropRect != null && h != null) {
        final double ratio = cropRect.width / cropRect.height;
        _isAutoUpdating = true;
        _widthController.text = (h * ratio).round().toString();
        _isAutoUpdating = false;
      }
    }
    uiState.setTargetDimensions(int.tryParse(_widthController.text), h);
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _ratioXController.dispose();
    _ratioYController.dispose();
    super.dispose();
  }

  void _updateAspectRatio(double? ratio) {
    _isAutoUpdating = true;
    if (ratio != null) {
      if (ratio == 1.0) {
        _ratioXController.text = "1"; _ratioYController.text = "1";
      } else if (ratio > 1.3 && ratio < 1.4) {
        _ratioXController.text = "4"; _ratioYController.text = "3";
      } else if (ratio > 1.7 && ratio < 1.8) {
        _ratioXController.text = "16"; _ratioYController.text = "9";
      } else if (ratio > 0.7 && ratio < 0.8) {
        _ratioXController.text = "3"; _ratioYController.text = "4";
      } else if (ratio > 0.5 && ratio < 0.6) {
        _ratioXController.text = "9"; _ratioYController.text = "16";
      }
    } else {
      _ratioXController.clear();
      _ratioYController.clear();
    }
    _isAutoUpdating = false;
    Provider.of<WorkbenchUIState>(context, listen: false).setCropAspectRatio(ratio);
  }

  void _selectRatioPreset(_RatioPreset preset) {
    setState(() => _customRatioMode = preset == _RatioPreset.custom);
    switch (preset) {
      case _RatioPreset.free:
        _updateAspectRatio(null);
      case _RatioPreset.r1x1:
        _updateAspectRatio(1.0);
      case _RatioPreset.r4x3:
        _updateAspectRatio(4 / 3);
      case _RatioPreset.r16x9:
        _updateAspectRatio(16 / 9);
      case _RatioPreset.r3x4:
        _updateAspectRatio(3 / 4);
      case _RatioPreset.r9x16:
        _updateAspectRatio(9 / 16);
      case _RatioPreset.custom:
        // Expands the X:Y fields only; the ratio itself changes once the
        // user actually types into them (via _onRatioChanged).
        break;
    }
  }

  _RatioPreset _currentPreset(double? ratio) {
    if (_customRatioMode) return _RatioPreset.custom;
    if (ratio == null) return _RatioPreset.free;
    if (ratio == 1.0) return _RatioPreset.r1x1;
    if (ratio > 1.3 && ratio < 1.4) return _RatioPreset.r4x3;
    if (ratio > 1.7 && ratio < 1.8) return _RatioPreset.r16x9;
    if (ratio > 0.7 && ratio < 0.8) return _RatioPreset.r3x4;
    if (ratio > 0.5 && ratio < 0.6) return _RatioPreset.r9x16;
    return _RatioPreset.custom;
  }

  void _handleReset() {
    final uiState = Provider.of<WorkbenchUIState>(context, listen: false);
    final state = uiState.cropKey.currentState as ExtendedImageEditorState?;
    state?.reset();

    _isAutoUpdating = true;
    _widthController.clear();
    _heightController.clear();
    _ratioXController.clear();
    _ratioYController.clear();
    _isAutoUpdating = false;

    setState(() => _customRatioMode = false);
    uiState.setCropAspectRatio(null);
    uiState.setTargetDimensions(null, null);
  }

  /// The last stop before an original is replaced.
  ///
  /// Three outcomes, not two: `true` overwrite, `false` save a copy instead,
  /// `null` cancelled. The middle one is the point of the dialog — a confirm
  /// that only offers "yes" and "no" leaves someone who wanted to keep the
  /// original with nothing to do but start over, so the safe alternative is
  /// offered here, in the moment they are thinking about it.
  Future<bool?> _confirmOverwrite({
    required AppLocalizations l10n,
    required String fileName,
    required String originalSize,
    required String outputSize,
    required String copyDestination,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mono = textTheme.labelMedium?.copyWith(fontFamily: 'monospace');

    return AppDialog.show<bool>(
      context,
      icon: Icons.warning_amber_rounded,
      // Carries the whole dialog's mood: AppDialog tints the heading's icon
      // plate from this, so naming the error colour here is what makes the
      // plate red rather than the accent.
      iconColor: colorScheme.error,
      title: l10n.overwriteConfirmTitle,
      subtitle: l10n.overwriteConfirmSubtitle,
      maxWidth: 480,
      onClose: () => Navigator.pop(context, null),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.overwriteConfirmMessage, style: textTheme.bodyMedium),
          const SizedBox(height: 12),
          // What is being replaced, and what it becomes. The old→new pair is
          // the one fact that makes this decision answerable, so it gets a
          // surface of its own instead of a line of body text.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(Icons.image_outlined, size: 18, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    fileName,
                    style: mono,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 12),
                Text(originalSize, style: mono?.copyWith(color: colorScheme.onSurfaceVariant)),
                const SizedBox(width: 7),
                Icon(Icons.arrow_forward, size: 14, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 7),
                Text(
                  outputSize,
                  // The new dimensions in the error colour: this number is the
                  // irreversible part, and it is what someone scanning the
                  // dialog should land on.
                  style: mono?.copyWith(color: colorScheme.error, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: colorScheme.accentTint,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: colorScheme.onAccentTint),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${l10n.overwriteConfirmKeepOriginalHint}'
                    '${l10n.cropResizeWillSaveTo(copyDestination)}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onAccentTint,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context, null),
        ),
        AppButton(
          label: l10n.overwriteConfirmSaveCopyInstead,
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton(
          label: l10n.overwriteSource,
          variant: AppButtonVariant.destructive,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }

  Future<void> _handleSave({bool overwrite = false}) async {
    final l10n = AppLocalizations.of(context)!;
    final uiState = Provider.of<WorkbenchUIState>(context, listen: false);
    final appState = Provider.of<AppState>(context, listen: false);

    final sourceImage = uiState.cropResizeSourceImage;
    if (sourceImage == null) return;

    final editorState = uiState.cropKey.currentState as ExtendedImageEditorState?;
    if (editorState == null) return;

    final cropRect = editorState.getCropRect();
    if (cropRect == null) return;

    final int? w = int.tryParse(_widthController.text);
    final int? h = int.tryParse(_heightController.text);
    final outputWidth = w ?? cropRect.width.round();
    final outputHeight = h ?? cropRect.height.round();

    if (overwrite) {
      final originalMeta = await ImageMetadataService().getMetadata(sourceImage.path);
      // Resolved, not guessed: the hint below names the file the copy would
      // become, so it asks the same resolver the save will use.
      final copyTarget = await ImageProcessingService().resolveCropCopyTarget(sourceImage.path);
      if (!mounted) return;

      final confirmed = await _confirmOverwrite(
        l10n: l10n,
        fileName: sourceImage.name,
        originalSize:
            originalMeta != null ? '${originalMeta.width}×${originalMeta.height}' : '–',
        outputSize: '$outputWidth×$outputHeight',
        copyDestination:
            '${l10n.cropResizeTempWorkspaceLabel} / ${copyTarget.fileName}',
      );

      if (confirmed == null) return;
      if (confirmed == false) return _handleSave(overwrite: false);
    }

    if (!mounted) return;
    setState(() => _processingAction = overwrite ? 'overwrite' : 'save');

    try {
      SamplingMethod sampling;
      switch (uiState.samplingMethod) {
        case 'nearest': sampling = SamplingMethod.nearest; break;
        case 'linear': sampling = SamplingMethod.linear; break;
        case 'cubic': sampling = SamplingMethod.cubic; break;
        default: sampling = SamplingMethod.lanczos;
      }

      // Resolved before the work, not after: the encoder is chosen from the
      // target's extension, so the destination has to be known by the time
      // the bytes are produced.
      String targetPath;
      String targetName;

      if (overwrite) {
        targetPath = sourceImage.path;
        targetName = sourceImage.name;
      } else {
        final target = await ImageProcessingService().resolveCropCopyTarget(sourceImage.path);
        target.ensureExists();
        targetName = target.fileName;
        targetPath = target.path;
      }

      final processedBytes = await ImageProcessingService().processImage(
        sourcePath: sourceImage.path,
        targetPath: targetPath,
        cropX: cropRect.left.toInt(),
        cropY: cropRect.top.toInt(),
        cropWidth: cropRect.width.toInt(),
        cropHeight: cropRect.height.toInt(),
        width: w,
        height: h,
        maintainAspectRatio: uiState.maintainAspectRatio,
        sampling: sampling,
      );

      await ImageProcessingService().saveImage(
        bytes: processedBytes,
        targetPath: targetPath,
        // The dialog above is the only thing that can produce `overwrite:
        // true`, so this is where the user's answer reaches the file system.
        // The service refuses to clobber anything without it.
        allowOverwrite: overwrite,
      );

      final successMessage = overwrite ? l10n.overwriteSuccess : l10n.saveToTempSuccess;

      if (!mounted) return;

      AppSnackBar.success(context, successMessage);

      if (!overwrite) {
        final newFile = AppImage(path: targetPath, name: targetName);
        appState.galleryState.addDroppedFiles([newFile]);
      }

      appState.galleryState.refreshImages();
      appState.setWorkbenchTab(0);
    } on UnsupportedImageFormatException {
      // Named separately from the generic catch: this one is not a failure the
      // user can retry, it is a fact about their file, and the message has to
      // point them at the copy path that does work.
      if (mounted) {
        final ext = p.extension(sourceImage.path).replaceFirst('.', '').toUpperCase();
        AppSnackBar.error(context, l10n.overwriteUnsupportedFormat(ext));
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, "Error: $e");
      }
    } finally {
      if (mounted) setState(() => _processingAction = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final uiState = Provider.of<WorkbenchUIState>(context);
    final isNarrow = Responsive.isNarrow(context);
    final colorScheme = Theme.of(context).colorScheme;

    if (isNarrow) {
      return _buildMobileToolbar(context, l10n, uiState, colorScheme);
    }

    final source = uiState.cropResizeSourceImage;
    if (source != null) _loadMeta(source.path);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final busy = _processingAction != null;

        // Degradation order, loosest thing first: the file caption (the
        // canvas repeats the name anyway), then the sampler's own label,
        // then the two portrait presets, then the save button's destination
        // hint. The action *labels* go last — telling copy from overwrite is
        // the whole point of the bar, and three unlabelled icons is exactly
        // what this redesign set out to remove.
        //
        // Each step is taken only if what is left still does not fit, and
        // "fit" is measured rather than guessed. A pixel threshold tuned
        // against English collapses the bar far too early in Japanese, and
        // far too late once the user scales text up.
        var showFileInfo = source != null;
        var showSamplingLabel = true;
        var showAllRatios = true;
        var showSaveHint = true;
        var labelledActions = true;

        double needed() =>
            _kFixedChrome +
            (showFileInfo ? _kFileInfoWidth + 4 : 0) +
            _ratioGroupWidth(l10n, showAllRatios) +
            _sizeGroupWidth(l10n, showSamplingLabel) +
            _actionsWidth(l10n, labelledActions, showSaveHint);

        if (needed() > width) showFileInfo = false;
        if (needed() > width) showSamplingLabel = false;
        if (needed() > width) showAllRatios = false;
        if (needed() > width) showSaveHint = false;
        if (needed() > width) labelledActions = false;

        return Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(80))),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Provider.of<AppState>(context, listen: false).setWorkbenchTab(0),
                tooltip: l10n.cancel,
              ),
              if (showFileInfo && source != null) ...[
                const SizedBox(width: 4),
                _buildFileInfo(source, l10n, colorScheme),
              ],
              _divider(colorScheme),

              // Ratio and size share one scroller: whatever the breakpoints
              // fail to predict scrolls out of reach instead of clipping,
              // which is how the gallery toolbar's overflow bug read.
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildDesktopRatioSelector(l10n, uiState, colorScheme, !showAllRatios),
                      _divider(colorScheme),
                      _buildDesktopResizeControls(l10n, uiState, colorScheme, !showSamplingLabel),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 12),
              _buildDesktopSaveActions(l10n, colorScheme, !labelledActions, showSaveHint, busy),
            ],
          ),
        );
      }
    );
  }

  Widget _divider(ColorScheme colorScheme) => Container(
        width: 1,
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        // An explicit box, not VerticalDivider: a Row centres its children by
        // default, so the divider gets a loose height constraint and collapses
        // to nothing.
        color: colorScheme.outlineVariant.withValues(alpha: 0.7),
      );

  /// Natural width of [text] at [style], honouring the user's text scale.
  double _textWidth(String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }

  /// Width the ratio segments occupy. 20 is a segment's own compact padding,
  /// 8 the track's — see [AppSegmentedControl]. Measured at the selected
  /// weight, which is the wider of the two.
  double _ratioGroupWidth(AppLocalizations l10n, bool allRatios) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700);
    final labels = <String>[
      l10n.cropResizeFreeRatio,
      '1:1',
      '4:3',
      '16:9',
      if (allRatios) ...['3:4', '9:16'],
      l10n.custom,
    ];

    var width = 8.0;
    for (final label in labels) {
      width += 20 + _textWidth(label, style);
    }
    if (_customRatioMode) width += 8 + _kCustomRatioFieldsWidth;
    return width;
  }

  double _sizeGroupWidth(AppLocalizations l10n, bool samplingLabel) {
    final textTheme = Theme.of(context).textTheme;

    double field(String label) =>
        22 + _textWidth(label, textTheme.bodySmall) + 8 + _kNumberFieldWidth + _textWidth('px', textTheme.bodySmall);

    var width = 28.0 + field(l10n.width) + 6 + 28 + 6 + field(l10n.height) + 10;
    if (samplingLabel) width += _textWidth(l10n.cropResizeResample, textTheme.bodySmall) + 6;
    // The dropdown sizes to its widest option, plus its box and chevron.
    width += 38 + _textWidth('Lanczos', textTheme.bodyMedium);
    return width;
  }

  /// Material's own icon-button padding, spelled out so the estimate tracks
  /// what the buttons actually render: text 12/16, filled and outlined 16/24,
  /// each around an 18px icon with an 8px gap.
  double _actionsWidth(AppLocalizations l10n, bool labelled, bool saveHint) {
    if (!labelled) return appButtonMinHeight * 3 + 16;

    final style = Theme.of(context).textTheme.labelLarge;
    // AppToolButton pads 12 a side; the two AppButtons take Material's
    // icon-button padding of 16/24 around an 18px icon and its 8px gap.
    final reset = 44 + _textWidth(l10n.reset, style);
    final overwrite = 68 + _textWidth(l10n.overwriteSource, style);
    var save = 66 + _textWidth(l10n.saveCopy, style);
    if (saveHint) save += 6 + _textWidth(l10n.cropResizeSaveDestinationHint, style);
    return reset + 8 + overwrite + 12 + save;
  }

  /// Filename over its native resolution and weight — the crop is always
  /// expressed against these numbers, and the canvas only ever shows a
  /// fitted preview, so without them the source's real size is invisible.
  Widget _buildFileInfo(AppImage source, AppLocalizations l10n, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    final meta = _meta;

    return SizedBox(
      width: _kFileInfoWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            source.name,
            style: textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (meta != null && meta.width > 0)
            Text(
              l10n.cropResizeOriginalInfo(meta.width, meta.height, meta.sizeString),
              style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopSaveActions(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    bool compact,
    bool showSaveHint,
    bool busy,
  ) {
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppToolButton(
            icon: Icons.restart_alt,
            label: l10n.reset,
            showLabel: false,
            onPressed: busy ? null : _handleReset,
          ),
          const SizedBox(width: 8),
          AppIconButton(
            icon: Icons.warning_amber_rounded,
            tooltip: l10n.overwriteSource,
            color: colorScheme.error,
            onPressed: busy ? null : () => _handleSave(overwrite: true),
          ),
          const SizedBox(width: 8),
          AppIconButton(
            icon: Icons.save_outlined,
            tooltip: l10n.saveCopy,
            selected: true,
            onPressed: busy ? null : () => _handleSave(overwrite: false),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Not AppButton's text variant: that one keeps Material's accent
        // tint, which would put reset at the same visual weight as the two
        // actions that actually write a file.
        AppToolButton(
          icon: Icons.restart_alt,
          label: l10n.reset,
          onPressed: busy ? null : _handleReset,
        ),
        const SizedBox(width: 8),
        AppButton(
          label: l10n.overwriteSource,
          icon: Icons.warning_amber_rounded,
          variant: AppButtonVariant.destructiveOutline,
          loading: _processingAction == 'overwrite',
          onPressed: busy ? null : () => _handleSave(overwrite: true),
        ),
        const SizedBox(width: 12),
        AppButton(
          label: l10n.saveCopy,
          secondaryLabel: showSaveHint ? l10n.cropResizeSaveDestinationHint : null,
          icon: Icons.save_outlined,
          variant: AppButtonVariant.primary,
          loading: _processingAction == 'save',
          onPressed: busy ? null : () => _handleSave(overwrite: false),
        ),
      ],
    );
  }

  Widget _buildDesktopRatioSelector(AppLocalizations l10n, WorkbenchUIState uiState, ColorScheme colorScheme, bool compact) {
    final preset = _currentPreset(uiState.cropAspectRatio);
    final segments = <AppSegment<_RatioPreset>>[
      AppSegment(value: _RatioPreset.free, label: l10n.cropResizeFreeRatio),
      AppSegment(value: _RatioPreset.r1x1, label: "1:1"),
      AppSegment(value: _RatioPreset.r4x3, label: "4:3"),
      AppSegment(value: _RatioPreset.r16x9, label: "16:9"),
      if (!compact) ...[
        AppSegment(value: _RatioPreset.r3x4, label: "3:4"),
        AppSegment(value: _RatioPreset.r9x16, label: "9:16"),
      ],
      AppSegment(value: _RatioPreset.custom, label: l10n.custom),
    ];

    // No leading icon: the segments are self-describing ("1:1", "16:9"), and
    // an aspect-ratio glyph in front of them only competes with the track's
    // own edge for the eye.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSegmentedControl<_RatioPreset>(
          segments: segments,
          value: preset,
          onChanged: _selectRatioPreset,
          style: AppSegmentStyle.raised,
          compact: true,
        ),
        if (_customRatioMode) ...[
          const SizedBox(width: 8),
          _buildCustomRatioFields(colorScheme),
        ],
      ],
    );
  }

  /// Only rendered once the "Custom" segment is selected — folded away
  /// otherwise instead of permanently occupying toolbar width next to the
  /// preset chips.
  Widget _buildCustomRatioFields(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(150),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRatioField(_ratioXController),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(":", style: Theme.of(context).textTheme.bodySmall)),
          _buildRatioField(_ratioYController),
        ],
      ),
    );
  }

  Widget _buildRatioField(TextEditingController ctrl) {
    return SizedBox(
      width: 24,
      child: TextField(
        controller: ctrl,
        decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.zero),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildDesktopResizeControls(AppLocalizations l10n, WorkbenchUIState uiState, ColorScheme colorScheme, bool compact) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.photo_size_select_large, size: 18, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        _buildDimensionField(_widthController, l10n.width, colorScheme),
        const SizedBox(width: 6),
        // Between the two fields, not after both — this is the control that
        // links them, so it reads as sitting on the link rather than as a
        // third, unrelated field.
        Tooltip(
          message: l10n.maintainAspectRatio,
          child: InkWell(
            onTap: () => uiState.setMaintainAspectRatio(!uiState.maintainAspectRatio),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: uiState.maintainAspectRatio
                    ? colorScheme.primary.withValues(alpha: 0.14)
                    : Colors.transparent,
              ),
              child: Icon(
                uiState.maintainAspectRatio ? Icons.link : Icons.link_off,
                size: 15,
                color: uiState.maintainAspectRatio ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _buildDimensionField(_heightController, l10n.height, colorScheme),
        const SizedBox(width: 10),
        if (!compact) ...[
          Text(
            l10n.cropResizeResample,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 6),
        ],
        Container(
          height: appButtonMinHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(appButtonRadius),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: uiState.samplingMethod,
              isDense: true,
              icon: Icon(Icons.expand_more, size: 16, color: colorScheme.onSurfaceVariant),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
              items: const [
                DropdownMenuItem(value: 'lanczos', child: Text("Lanczos")),
                DropdownMenuItem(value: 'cubic', child: Text("Cubic")),
                DropdownMenuItem(value: 'linear', child: Text("Linear")),
                DropdownMenuItem(value: 'nearest', child: Text("Nearest")),
              ],
              onChanged: (v) => uiState.setSamplingMethod(v!),
            ),
          ),
        ),
      ],
    );
  }

  /// A boxed "W [1200] px" cell.
  ///
  /// Built by hand rather than from [InputDecoration]: Material only reveals
  /// `prefixText`/`suffixText` once a field has focus or content, so an empty
  /// box would lose both its "width" label and its unit — exactly when the
  /// user most needs to be told what the box is for. Drawing the chrome here
  /// keeps the label and the unit standing regardless of state, and leaves a
  /// borderless field to hold just the number.
  Widget _buildDimensionField(TextEditingController ctrl, String label, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      height: appButtonMinHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(appButtonRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
          const SizedBox(width: 8),
          SizedBox(
            width: _kNumberFieldWidth,
            child: TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              keyboardType: TextInputType.number,
            ),
          ),
          Text(
            'px',
            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileToolbar(BuildContext context, AppLocalizations l10n, WorkbenchUIState uiState, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 4, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildMobileAction(
              context,
              icon: Icons.close,
              label: l10n.cancel,
              onTap: () => Provider.of<AppState>(context, listen: false).setWorkbenchTab(0),
            ),
            _buildMobileAction(
              context,
              icon: Icons.aspect_ratio,
              label: l10n.aspectRatio,
              onTap: () => _showMobileRatioSheet(context, l10n, uiState),
            ),
            _buildMobileAction(
              context,
              icon: Icons.photo_size_select_large,
              label: l10n.resize,
              onTap: () => _showMobileResizeDialog(context, l10n, uiState),
            ),
            _buildMobileAction(
              context,
              icon: Icons.check_circle_outline,
              label: l10n.save,
              color: colorScheme.primary,
              onTap: () => _showMobileSaveSheet(context, l10n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileAction(BuildContext context, {required IconData icon, required String label, required VoidCallback onTap, Color? color}) {
    final fg = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fg, size: 24),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  void _showMobileRatioSheet(BuildContext context, AppLocalizations l10n, WorkbenchUIState uiState) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.aspectRatio, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildRatioChip("Free", null, uiState.cropAspectRatio),
                      _buildRatioChip("1:1", 1.0, uiState.cropAspectRatio),
                      _buildRatioChip("4:3", 4/3, uiState.cropAspectRatio),
                      _buildRatioChip("16:9", 16/9, uiState.cropAspectRatio),
                      _buildRatioChip("3:4", 3/4, uiState.cropAspectRatio),
                      _buildRatioChip("9:16", 9/16, uiState.cropAspectRatio),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatioChip(String label, double? ratio, double? current) {
    final selected = ratio == current;
    return ChoiceChip(
      label: Text(label, style: Theme.of(context).textTheme.labelMedium?.metricsOnly),
      selected: selected,
      onSelected: (v) {
        _updateAspectRatio(ratio);
        Navigator.pop(context);
      },
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }

  void _showMobileResizeDialog(BuildContext context, AppLocalizations l10n, WorkbenchUIState uiState) {
    final colorScheme = Theme.of(context).colorScheme;
    AppDialog.show<void>(
      context,
      title: l10n.resize,
      content: StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: _buildDimensionField(_widthController, l10n.width, colorScheme)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("×")),
                Expanded(child: _buildDimensionField(_heightController, l10n.height, colorScheme)),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: Text(l10n.maintainAspectRatio, style: Theme.of(context).textTheme.bodyMedium),
              value: uiState.maintainAspectRatio,
              onChanged: (v) {
                uiState.setMaintainAspectRatio(v);
                setDialogState(() {});
              },
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ],
        ),
      ),
      actions: [
        AppButton(
          label: l10n.close,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  void _showMobileSaveSheet(BuildContext context, AppLocalizations l10n) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: Text(l10n.saveToTemp),
              onTap: () {
                Navigator.pop(context);
                _handleSave(overwrite: false);
              },
            ),
            ListTile(
              leading: Icon(Icons.restore_page_outlined, color: Theme.of(context).colorScheme.error),
              title: Text(l10n.overwriteSource, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(context);
                _handleSave(overwrite: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: Text(l10n.reset),
              onTap: () {
                Navigator.pop(context);
                _handleReset();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
