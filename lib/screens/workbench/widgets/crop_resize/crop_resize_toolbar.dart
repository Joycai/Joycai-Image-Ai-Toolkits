import 'dart:async';
import 'dart:math' as math;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../../core/app_theme.dart';
import '../../../../core/design_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/app_image.dart';
import '../../../../services/media/image_metadata_service.dart';
import '../../../../services/media/image_processing_service.dart';
import '../../../../state/app_state.dart';
import '../../../../state/workbench_ui_state.dart';
import '../../../../widgets/glass/app_glass.dart';
import '../../../../widgets/glass/glass_controls.dart';
import '../../../../widgets/ui/app_button.dart';
import '../../../../widgets/ui/app_dialog.dart';
import '../../../../widgets/ui/app_dropdown.dart';
import '../../../../widgets/ui/app_field_size.dart';
import '../../../../widgets/ui/app_setting_row.dart';
import '../../../../widgets/ui/app_snackbar.dart';

part 'crop_resize_controls.dart';
part 'crop_resize_metrics.dart';
part 'crop_resize_overwrite_confirm.dart';
part 'crop_resize_step_flow.dart';
part 'crop_resize_wide_row.dart';

/// The crop tool's controls in the workbench's floating glass toolbar
/// (`A4 · 1a`): the source's size, the ratio switch, the output size with its
/// aspect link, the resampler, and the three actions — reset, overwrite
/// original, and the one the screen builds towards, Save Copy.
///
/// It is the content of the slot the toolbar gives a tool after its back
/// button and tool switch: no ground, no border, no frame of its own — one row
/// filling the width it is handed.
///
/// Degrades inside that width by measurement, in the spec's order (`A4–A6`
/// 「工具头降级顺序」):
///
/// 1. decoration — the source's size, the resampler's name, Save Copy's
///    destination subtitle;
/// 2. labels — the portrait presets, Free and Custom become glyphs, then
///    Reset and Overwrite become glyphs with tooltips;
/// 3. reset, overwrite and the resampler fold into a ⋮ menu;
/// 4. Save Copy never gives way.
///
/// When even that row does not fit, the slot shows the narrow step flow
/// instead: Aspect Ratio and Resize open their dialogs, Save opens the save
/// menu.
///
/// "Fit" is measured with a TextPainter at the user's text scale, never a
/// pixel threshold. A width tuned against English collapses the bar far too
/// early in Japanese and far too late once the text is scaled up — and a
/// hard-coded `width < 1250` once left an ordinary maximised window with three
/// unlabelled icons, one of which overwrites the user's original.
class CropResizeToolbar extends StatefulWidget {
  const CropResizeToolbar({super.key});

  /// The width these controls take with everything shown and labelled — what
  /// the glass toolbar weighs its tool switch's labels against.
  ///
  /// Measured against a representative source size (four-digit dimensions)
  /// and the widest resampler name, with the custom X:Y pair folded: this is
  /// asked before the toolbar has laid out, so it cannot know the file.
  static double preferredWidth(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final widestSampling = _kSamplingLabels.values.reduce(
      (a, b) =>
          measureGlassText(context, a, GlassIconButton.labelStyle(context)) >=
              measureGlassText(context, b, GlassIconButton.labelStyle(context))
          ? a
          : b,
    );
    final fit = _Fit()..saveSubtitle = _saveSubtitleFitsHeight(context);
    return _measureRow(
      context,
      fit,
      info: l10n.cropResizeOriginalInfo(8888, 8888, '88.8 MB'),
      customMode: false,
      samplingLabel: widestSampling,
    ).ceilToDouble();
  }

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

  /// Whether the user has typed an output size of their own.
  ///
  /// Until they do, the two fields track the selection — the spec's "show the
  /// actual value", and the fix for a bar that read `宽度 [    ] px` over a
  /// picture whose size was known all along. Once they type, the numbers are
  /// theirs and the crop stops overwriting them; [_handleReset] hands control
  /// back.
  bool _sizeIsUserSet = false;

  /// Source dimensions for the size caption and the resize dialog. The view
  /// loads this too; [ImageMetadataService] caches by path, so the second
  /// reader costs a map lookup rather than a second decode.
  ImageMetadata? _meta;
  String? _metaPath;

  void _loadMeta(String path) {
    if (_metaPath == path) return;
    _metaPath = path;
    _meta = null;
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
    _sizeIsUserSet = true;
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
    _sizeIsUserSet = true;
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
        _ratioXController.text = '1';
        _ratioYController.text = '1';
      } else if (ratio > 1.3 && ratio < 1.4) {
        _ratioXController.text = '4';
        _ratioYController.text = '3';
      } else if (ratio > 1.7 && ratio < 1.8) {
        _ratioXController.text = '16';
        _ratioYController.text = '9';
      } else if (ratio > 0.7 && ratio < 0.8) {
        _ratioXController.text = '3';
        _ratioYController.text = '4';
      } else if (ratio > 0.5 && ratio < 0.6) {
        _ratioXController.text = '9';
        _ratioYController.text = '16';
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

    setState(() {
      _customRatioMode = false;
      _sizeIsUserSet = false;
    });
    uiState.setCropAspectRatio(null);
    uiState.setTargetDimensions(null, null);
  }

  /// Mirrors the live selection into the two size fields.
  ///
  /// Silent — through [_isAutoUpdating], so it does not read back as the user
  /// having chosen these numbers, and does not call [WorkbenchUIState]'s
  /// setters: a null `targetWidth` is what tells the save to use the crop's
  /// own size, and writing the same numbers in would only be a second copy of
  /// the same fact, free to drift.
  ///
  /// Deferred to after the frame because the caller is `build`: writing to a
  /// [TextEditingController] notifies the [TextField] listening to it, and
  /// marking that field dirty mid-build is an error. The equality check keeps
  /// it to one write per actual change rather than one per frame.
  void _syncSizeFields(Size? crop) {
    if (_sizeIsUserSet) return;
    final String width = crop == null ? '' : crop.width.round().toString();
    final String height = crop == null ? '' : crop.height.round().toString();
    if (_widthController.text == width && _heightController.text == height) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _sizeIsUserSet) return;
      _isAutoUpdating = true;
      _widthController.text = width;
      _heightController.text = height;
      _isAutoUpdating = false;
    });
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
        originalSize: originalMeta != null ? '${originalMeta.width}×${originalMeta.height}' : '–',
        outputSize: '$outputWidth×$outputHeight',
        copyDestination: '${l10n.cropResizeTempWorkspaceLabel} / ${copyTarget.fileName}',
      );

      if (confirmed == null) return;
      if (!confirmed) return _handleSave(overwrite: false);
    }

    if (!mounted) return;
    setState(() => _processingAction = overwrite ? 'overwrite' : 'save');

    try {
      SamplingMethod sampling;
      switch (uiState.samplingMethod) {
        case 'nearest':
          sampling = SamplingMethod.nearest;
        case 'linear':
          sampling = SamplingMethod.linear;
        case 'cubic':
          sampling = SamplingMethod.cubic;
        default:
          sampling = SamplingMethod.lanczos;
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

      unawaited(appState.galleryState.refreshImages());
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
        AppSnackBar.error(context, 'Error: $e');
      }
    } finally {
      if (mounted) setState(() => _processingAction = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uiState = Provider.of<WorkbenchUIState>(context);
    _syncSizeFields(uiState.cropPixelSize);

    final source = uiState.cropResizeSourceImage;
    if (source != null) _loadMeta(source.path);

    return LayoutBuilder(
      builder: (context, constraints) => _buildSlot(context, uiState, constraints.maxWidth),
    );
  }
}
