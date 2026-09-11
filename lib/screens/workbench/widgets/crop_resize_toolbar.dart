import 'dart:math' as math;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../services/image_metadata_service.dart';
import '../../../services/image_processing_service.dart';
import '../../../state/app_state.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_dropdown.dart';
import '../../../widgets/app_field_size.dart';
import '../../../widgets/app_setting_row.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/glass/app_glass.dart';
import '../../../widgets/glass/glass_controls.dart';

/// The fixed set of ratio presets shown as segments, plus a `custom` mode
/// whose X:Y fields only appear once it's selected — folding them into the
/// segmented control instead of always occupying toolbar width.
enum _RatioPreset { free, r1x1, r4x3, r16x9, r3x4, r9x16, custom }

/// Resampling algorithms by the id [WorkbenchUIState.samplingMethod] stores.
/// Proper names of algorithms, not prose — the same in every language.
const Map<String, String> _kSamplingLabels = {
  'lanczos': 'Lanczos',
  'cubic': 'Cubic',
  'linear': 'Linear',
  'nearest': 'Nearest',
};

/// The glass bar's gap between groups.
const double _kGap = 4;

/// `A4 · 1a`: a 72×32 dimension input either side of a 28px link lens, 2px
/// apart — one group, measured as one.
const double _kFieldWidth = 72;
const double _kLinkSize = AppSize.compact;
const double _kFieldGap = 2;
const double _kSizeGroupWidth = _kFieldWidth + _kFieldGap + _kLinkSize + _kFieldGap + _kFieldWidth;

/// The X:Y pair that unfolds beside the ratio switch under "Custom".
const double _kCustomFieldsWidth = 80;

/// The least the flexible gap before the actions may shrink to.
const double _kMinSpacer = AppSpace.s6;

/// Mono 11 in the glass bar's secondary ink: the source's size and weight.
TextStyle _infoStyle(BuildContext context) =>
    Theme.of(context).textTheme.labelSmall!.metricsOnly.mono.copyWith(fontWeight: FontWeight.w400);

/// Mono 12: a number the user types.
TextStyle _valueStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall!.metricsOnly.mono;

/// Save Copy's two lines (`1a`: 600 label over an 11px subtitle, 1.15 apart).
TextStyle _saveLabelStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .bodySmall!
    .metricsOnly
    .copyWith(fontWeight: FontWeight.w600, height: 1.15);

TextStyle _saveSubtitleStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .labelSmall!
    .metricsOnly
    .copyWith(fontWeight: FontWeight.w400, height: 1.15);

/// Whether Save Copy's two lines stand inside the 32px control at the user's
/// text scale. Measured, like everything else here: at a large enough scale
/// the pair is taller than the button, and the subtitle has to go before it
/// overflows vertically, whatever the width.
bool _saveSubtitleFitsHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  double lineHeight(TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: 'Hg', style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  return lineHeight(_saveLabelStyle(context)) + lineHeight(_saveSubtitleStyle(context)) <=
      AppSize.control - 2;
}

List<GlassSegment<_RatioPreset>> _ratioSegments(
  AppLocalizations l10n, {
  required bool portrait,
  required bool icons,
}) =>
    [
      GlassSegment(
        value: _RatioPreset.free,
        label: l10n.cropResizeFreeRatio,
        icon: icons ? Icons.crop_free : null,
      ),
      const GlassSegment(value: _RatioPreset.r1x1, label: '1:1'),
      const GlassSegment(value: _RatioPreset.r4x3, label: '4:3'),
      const GlassSegment(value: _RatioPreset.r16x9, label: '16:9'),
      if (portrait) ...const [
        GlassSegment(value: _RatioPreset.r3x4, label: '3:4'),
        GlassSegment(value: _RatioPreset.r9x16, label: '9:16'),
      ],
      GlassSegment(
        value: _RatioPreset.custom,
        label: l10n.custom,
        icon: icons ? Icons.edit_outlined : null,
      ),
    ];

/// What the single row is currently allowed to show. Starts with everything
/// and is stepped down in [_CropResizeToolbarState._fitRow].
class _Fit {
  bool info = true;
  bool samplingName = true;
  bool saveSubtitle = true;
  bool portraitPresets = true;
  bool ratioWords = true;
  bool resetLabel = true;
  bool overwriteLabel = true;
  bool folded = false;
}

/// The width the single row takes under [f].
double _measureRow(
  BuildContext context,
  _Fit f, {
  required String? info,
  required bool customMode,
  required String samplingLabel,
}) {
  final l10n = AppLocalizations.of(context)!;
  final parts = <double>[
    if (f.info && info != null) ...[
      measureGlassText(context, info, _infoStyle(context)).ceilToDouble(),
      GlassDivider.extent,
    ],
    GlassSegmented.widthFor(
      context,
      _ratioSegments(l10n, portrait: f.portraitPresets, icons: !f.ratioWords),
      showLabels: f.ratioWords,
    ),
    if (customMode) _kCustomFieldsWidth,
    _kSizeGroupWidth,
    if (!f.folded) _GlassMenuButton.widthFor(context, f.samplingName ? samplingLabel : null),
    _kMinSpacer,
    if (f.folded)
      AppSize.control
    else ...[
      GlassIconButton.widthFor(context, label: f.resetLabel ? l10n.reset : null, hasIcon: false),
      GlassIconButton.widthFor(
        context,
        label: f.overwriteLabel ? l10n.overwriteSource : null,
        hasIcon: false,
      ),
    ],
    _TintedButton.widthFor(
      context,
      label: l10n.saveCopy,
      subtitle: f.saveSubtitle ? l10n.cropResizeSaveDestinationHint : null,
    ),
  ];
  return parts.fold<double>(0, (a, b) => a + b) + _kGap * (parts.length - 1);
}

/// Lays [children] out with the bar's gap between each.
List<Widget> _spaced(List<Widget> children) => [
      for (int i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(width: _kGap),
        children[i],
      ],
    ];

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
    // `.mono` over the bare generic: the confirm dialog puts the before and
    // after dimensions one above the other, which only reads as a comparison
    // if the digits line up.
    final mono = textTheme.labelMedium?.mono;

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
                      height: AppType.looseHeight,
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
    final uiState = Provider.of<WorkbenchUIState>(context);
    _syncSizeFields(uiState.cropPixelSize);

    final source = uiState.cropResizeSourceImage;
    if (source != null) _loadMeta(source.path);

    return LayoutBuilder(
      builder: (context, constraints) => _buildSlot(context, uiState, constraints.maxWidth),
    );
  }

  /// Steps [f] down until the row fits [width], and reports whether it does.
  bool _fitRow(BuildContext context, _Fit f, double width, {required String? info, required String samplingLabel}) {
    double measure() => _measureRow(
          context,
          f,
          info: info,
          customMode: _customRatioMode,
          samplingLabel: samplingLabel,
        );

    final steps = <VoidCallback>[
      // 1 · decoration.
      () => f.info = false,
      () => f.samplingName = false,
      // 2 · labels. The subtitle is the two-line button folding to one, which
      // the spec files here; the action labels go last — telling copy from
      // overwrite is the whole point of the bar.
      () => f.saveSubtitle = false,
      () => f.portraitPresets = false,
      () => f.ratioWords = false,
      () => f.resetLabel = false,
      () => f.overwriteLabel = false,
      // 3 · the ⋮ menu.
      () => f.folded = true,
    ];
    for (final step in steps) {
      if (measure() <= width) return true;
      step();
    }
    return measure() <= width;
  }

  Widget _buildSlot(BuildContext context, WorkbenchUIState uiState, double width) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final ink2 = GlassInk.maybeOf(context)?.ink2 ?? scheme.onSurfaceVariant;
    final source = uiState.cropResizeSourceImage;
    final meta = _meta;
    final info = source != null && meta != null && meta.width > 0
        ? l10n.cropResizeOriginalInfo(meta.width, meta.height, meta.sizeString)
        : null;
    final samplingLabel = _kSamplingLabels[uiState.samplingMethod] ?? uiState.samplingMethod;

    final f = _Fit()..saveSubtitle = _saveSubtitleFitsHeight(context);
    if (!_fitRow(context, f, width, info: info, samplingLabel: samplingLabel)) {
      return _buildStepFlow(context, l10n, uiState, width);
    }

    final busy = _processingAction != null;
    final children = <Widget>[
      if (f.info && info != null) ...[
        Text(info, maxLines: 1, softWrap: false, style: _infoStyle(context).copyWith(color: ink2)),
        const GlassDivider(),
      ],
      GlassSegmented<_RatioPreset>(
        segments: _ratioSegments(l10n, portrait: f.portraitPresets, icons: !f.ratioWords),
        value: _currentPreset(uiState.cropAspectRatio),
        onChanged: _selectRatioPreset,
        showLabels: f.ratioWords,
      ),
      if (_customRatioMode) _buildCustomRatioFields(context),
      _buildSizeGroup(context, l10n, uiState),
      if (!f.folded)
        MenuAnchor(
          menuChildren: _samplingMenuItems(context, uiState),
          builder: (context, controller, _) => _GlassMenuButton(
            label: f.samplingName ? samplingLabel : null,
            icon: Icons.grain,
            tooltip: l10n.cropResizeResample,
            open: controller.isOpen,
            onPressed: () => controller.isOpen ? controller.close() : controller.open(),
          ),
        ),
      const Expanded(child: SizedBox()),
      if (f.folded)
        _buildOverflowMenu(context, l10n, uiState, busy)
      else ...[
        // Ghost text: reset must not read as a peer of the two actions that
        // write a file.
        GlassIconButton(
          icon: f.resetLabel ? null : Icons.restart_alt,
          label: f.resetLabel ? l10n.reset : null,
          tooltip: f.resetLabel ? null : l10n.reset,
          onPressed: busy ? null : _handleReset,
        ),
        // The destructive action is named and red, and quieter than the safe
        // one beside it: text, never a fill.
        _Spinning(
          on: _processingAction == 'overwrite',
          color: scheme.error,
          child: GlassIconButton(
            icon: f.overwriteLabel ? null : Icons.warning_amber_rounded,
            label: f.overwriteLabel ? l10n.overwriteSource : null,
            tooltip: f.overwriteLabel ? null : l10n.overwriteSource,
            danger: true,
            onPressed: busy ? null : () => _handleSave(overwrite: true),
          ),
        ),
      ],
      // Never gives way.
      _TintedButton(
        label: l10n.saveCopy,
        subtitle: f.saveSubtitle ? l10n.cropResizeSaveDestinationHint : null,
        tooltip: f.saveSubtitle ? null : l10n.saveToTemp,
        loading: _processingAction == 'save',
        onPressed: busy ? null : () => _handleSave(overwrite: false),
      ),
    ];

    return Row(children: _spaced(children));
  }

  /// Width, the aspect link, height (`1a`: 72×32 inputs on the glass edge,
  /// mono values, a 28px lens between them that is the accent when on).
  ///
  /// The link sits between the two fields, not after both — it is the control
  /// that links them.
  Widget _buildSizeGroup(BuildContext context, AppLocalizations l10n, WorkbenchUIState uiState) {
    final maintain = uiState.maintainAspectRatio;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GlassNumberField(controller: _widthController, label: l10n.width, width: _kFieldWidth),
        const SizedBox(width: _kFieldGap),
        GlassIconButton(
          icon: maintain ? Icons.link : Icons.link_off,
          size: _kLinkSize,
          active: maintain,
          tooltip: l10n.maintainAspectRatio,
          onPressed: () => uiState.setMaintainAspectRatio(!maintain),
        ),
        const SizedBox(width: _kFieldGap),
        _GlassNumberField(controller: _heightController, label: l10n.height, width: _kFieldWidth),
      ],
    );
  }

  /// Only rendered once the "Custom" segment is selected — folded away
  /// otherwise instead of permanently occupying toolbar width.
  Widget _buildCustomRatioFields(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = GlassInk.maybeOf(context);
    final edge = glass?.edge ?? scheme.outlineVariant;
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;

    return Container(
      width: _kCustomFieldsWidth,
      height: AppSize.control,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: edge),
      ),
      child: Row(
        children: [
          Expanded(child: _BareNumberField(controller: _ratioXController, textAlign: TextAlign.center)),
          Text(':', style: _valueStyle(context).copyWith(color: ink2)),
          Expanded(child: _BareNumberField(controller: _ratioYController, textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  List<Widget> _samplingMenuItems(BuildContext context, WorkbenchUIState uiState) {
    final scheme = Theme.of(context).colorScheme;
    return [
      for (final entry in _kSamplingLabels.entries)
        MenuItemButton(
          leadingIcon: Icon(
            Icons.check,
            size: AppSize.iconMd,
            color: entry.key == uiState.samplingMethod ? scheme.primary : Colors.transparent,
          ),
          onPressed: () => uiState.setSamplingMethod(entry.key),
          child: Text(entry.value),
        ),
    ];
  }

  /// Step 3: reset, overwrite and the resampler behind one ⋮.
  Widget _buildOverflowMenu(
    BuildContext context,
    AppLocalizations l10n,
    WorkbenchUIState uiState,
    bool busy,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      menuChildren: [
        SubmenuButton(
          leadingIcon: const Icon(Icons.grain, size: AppSize.iconLg),
          menuChildren: _samplingMenuItems(context, uiState),
          child: Text(l10n.cropResizeResample),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.restart_alt, size: AppSize.iconLg),
          onPressed: busy ? null : _handleReset,
          child: Text(l10n.reset),
        ),
        const Divider(height: 9),
        MenuItemButton(
          leadingIcon: Icon(Icons.warning_amber_rounded, size: AppSize.iconLg, color: scheme.error),
          onPressed: busy ? null : () => _handleSave(overwrite: true),
          child: Text(l10n.overwriteSource, style: TextStyle(color: scheme.error)),
        ),
      ],
      builder: (context, controller, _) => _Spinning(
        on: _processingAction == 'overwrite',
        color: scheme.error,
        child: GlassIconButton(
          icon: Icons.more_vert,
          tooltip: l10n.more,
          active: controller.isOpen,
          onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        ),
      ),
    );
  }

  /// The narrow step flow (`A4 · 1b`): what the slot shows when even the most
  /// degraded single row does not fit. The glass bar's own back button leads
  /// the row, so this starts at Aspect Ratio.
  Widget _buildStepFlow(
    BuildContext context,
    AppLocalizations l10n,
    WorkbenchUIState uiState,
    double width,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final busy = _processingAction != null;

    bool labels = true;
    bool saveLabel = true;
    double measure() {
      final parts = <double>[
        GlassIconButton.widthFor(context, label: labels ? l10n.aspectRatio : null),
        GlassIconButton.widthFor(context, label: labels ? l10n.resize : null),
        _kMinSpacer,
        saveLabel ? _TintedButton.widthFor(context, label: l10n.save, icon: true) : AppSize.control,
      ];
      return parts.fold<double>(0, (a, b) => a + b) + _kGap * (parts.length - 1);
    }

    if (measure() > width) labels = false;
    if (measure() > width) saveLabel = false;

    return Row(
      children: _spaced([
        GlassIconButton(
          icon: Icons.aspect_ratio,
          label: labels ? l10n.aspectRatio : null,
          tooltip: labels ? null : l10n.aspectRatio,
          onPressed: () => _showRatioSheet(context, l10n, uiState),
        ),
        GlassIconButton(
          icon: Icons.photo_size_select_large,
          label: labels ? l10n.resize : null,
          tooltip: labels ? null : l10n.resize,
          onPressed: () => _showResizeDialog(context, l10n, uiState),
        ),
        const Expanded(child: SizedBox()),
        MenuAnchor(
          menuChildren: [
            MenuItemButton(
              leadingIcon: const Icon(Icons.save_alt, size: AppSize.iconLg),
              onPressed: busy ? null : () => _handleSave(overwrite: false),
              child: Text(l10n.saveToTemp),
            ),
            MenuItemButton(
              leadingIcon: Icon(Icons.warning_amber_rounded, size: AppSize.iconLg, color: scheme.error),
              onPressed: busy ? null : () => _handleSave(overwrite: true),
              child: Text(l10n.overwriteSource, style: TextStyle(color: scheme.error)),
            ),
            const Divider(height: 9),
            MenuItemButton(
              leadingIcon: const Icon(Icons.restart_alt, size: AppSize.iconLg),
              onPressed: busy ? null : _handleReset,
              child: Text(l10n.reset),
            ),
          ],
          builder: (context, controller, _) => _TintedButton(
            icon: Icons.save_outlined,
            label: l10n.save,
            showLabel: saveLabel,
            tooltip: saveLabel ? null : l10n.save,
            loading: busy,
            onPressed: busy ? null : () => controller.isOpen ? controller.close() : controller.open(),
          ),
        ),
      ]),
    );
  }

  /// The step flow's ratio sheet (`1b` 「比例表」). Custom stays on the wide
  /// bar, where its X:Y fields have room.
  void _showRatioSheet(BuildContext context, AppLocalizations l10n, WorkbenchUIState uiState) {
    final current = _currentPreset(uiState.cropAspectRatio);
    final options = <(_RatioPreset, String)>[
      (_RatioPreset.free, l10n.cropResizeFreeRatio),
      (_RatioPreset.r1x1, '1:1'),
      (_RatioPreset.r4x3, '4:3'),
      (_RatioPreset.r16x9, '16:9'),
      (_RatioPreset.r3x4, '3:4'),
      (_RatioPreset.r9x16, '9:16'),
    ];

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final textTheme = Theme.of(sheetContext).textTheme;
        final scheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s10, AppSpace.s6, AppSpace.s10, AppSpace.s10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Text(l10n.aspectRatio, style: textTheme.titleLarge),
                ),
                for (final (preset, label) in options)
                  ListTile(
                    selected: preset == current,
                    title: Text(
                      label,
                      style: preset == _RatioPreset.free
                          ? textTheme.bodyMedium!.metricsOnly
                          : textTheme.bodyMedium!.metricsOnly.mono,
                    ),
                    trailing: preset == current
                        ? Icon(Icons.check, size: AppSize.iconMd, color: scheme.primary)
                        : null,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _selectRatioPreset(preset);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The step flow's resize dialog (`1b` 「调整尺寸」): the two fields with the
  /// link between them, the aspect toggle, the resampler. The fields are the
  /// bar's own controllers, so what is typed here is live.
  void _showResizeDialog(BuildContext context, AppLocalizations l10n, WorkbenchUIState uiState) {
    final meta = _meta;
    AppDialog.show<void>(
      context,
      title: l10n.resize,
      subtitle: meta != null && meta.width > 0
          ? l10n.cropResizeOriginalInfo(meta.width, meta.height, meta.sizeString)
          : null,
      maxWidth: 380,
      content: ListenableBuilder(
        listenable: uiState,
        builder: (context, _) {
          final scheme = Theme.of(context).colorScheme;
          final textTheme = Theme.of(context).textTheme;
          final maintain = uiState.maintainAspectRatio;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: _DialogNumberField(controller: _widthController, label: l10n.width)),
                  const SizedBox(width: AppSpace.s6),
                  Tooltip(
                    message: l10n.maintainAspectRatio,
                    child: Semantics(
                      button: true,
                      toggled: maintain,
                      label: l10n.maintainAspectRatio,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => uiState.setMaintainAspectRatio(!maintain),
                          child: Container(
                            width: AppSize.large,
                            height: AppSize.large,
                            decoration: BoxDecoration(
                              color: maintain ? scheme.accentTint : Colors.transparent,
                              borderRadius: BorderRadius.circular(AppRadius.control),
                            ),
                            child: Icon(
                              maintain ? Icons.link : Icons.link_off,
                              size: AppSize.iconMd,
                              color: maintain ? scheme.primary : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.s6),
                  Expanded(child: _DialogNumberField(controller: _heightController, label: l10n.height)),
                ],
              ),
              const SizedBox(height: AppSpace.s10),
              AppToggleRow(
                title: l10n.maintainAspectRatio,
                value: maintain,
                onChanged: uiState.setMaintainAspectRatio,
              ),
              const Divider(),
              Row(
                children: [
                  Expanded(child: Text(l10n.cropResizeResample, style: textTheme.bodyMedium)),
                  SizedBox(
                    width: 140,
                    child: AppDropdown<String>(
                      size: AppFieldSize.regular,
                      height: appButtonMinHeight,
                      value: uiState.samplingMethod,
                      items: [
                        for (final entry in _kSamplingLabels.entries)
                          AppDropdownItem(value: entry.key, label: entry.value),
                      ],
                      onChanged: (v) {
                        if (v != null) uiState.setSamplingMethod(v);
                      },
                    ),
                  ),
                ],
              ),
            ],
          );
        },
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
}

/// A number field with no chrome of its own — the value, in mono, in the
/// glass ink.
class _BareNumberField extends StatelessWidget {
  const _BareNumberField({required this.controller, this.textAlign = TextAlign.start});

  final TextEditingController controller;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = GlassInk.maybeOf(context)?.ink ?? scheme.onSurface;
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: textAlign,
      maxLines: 1,
      cursorColor: scheme.primary,
      style: _valueStyle(context).copyWith(color: ink),
      decoration: const InputDecoration.collapsed(hintText: null),
    );
  }
}

/// `1a`: a 72×32 input on the glass edge at r10, the value in mono 12.
///
/// No visible label, as the design draws it: the pair reads as W × H beside
/// the link, and the name is carried by the tooltip and the semantics.
class _GlassNumberField extends StatelessWidget {
  const _GlassNumberField({required this.controller, required this.label, required this.width});

  final TextEditingController controller;
  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final edge = GlassInk.maybeOf(context)?.edge ?? Theme.of(context).colorScheme.outlineVariant;
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        textField: true,
        child: Container(
          width: width,
          height: AppSize.control,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: edge),
          ),
          child: _BareNumberField(controller: controller),
        ),
      ),
    );
  }
}

/// `1b`'s dialog field: an 11px label over a 40px input on the column colour.
class _DialogNumberField extends StatelessWidget {
  const _DialogNumberField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: textTheme.labelSmall!.copyWith(fontWeight: FontWeight.w400, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 3),
        Container(
          height: AppSize.large,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            maxLines: 1,
            style: _valueStyle(context).copyWith(color: scheme.onSurface),
            decoration: const InputDecoration.collapsed(hintText: null),
          ),
        ),
      ],
    );
  }
}

/// A 32px ghost button that opens a menu: `1a`'s 「lanczos ▾」. With no
/// [label] it is the glyph and the chevron.
class _GlassMenuButton extends StatefulWidget {
  const _GlassMenuButton({
    required this.label,
    required this.icon,
    required this.tooltip,
    required this.open,
    required this.onPressed,
  });

  final String? label;
  final IconData icon;
  final String tooltip;
  final bool open;
  final VoidCallback? onPressed;

  static double widthFor(BuildContext context, String? label) => label == null
      ? 8 + AppSize.iconLg + 2 + AppSize.iconSm + 8
      : (10 + measureGlassText(context, label, GlassIconButton.labelStyle(context)) + 4 + AppSize.iconSm + 10)
          .ceilToDouble();

  @override
  State<_GlassMenuButton> createState() => _GlassMenuButtonState();
}

class _GlassMenuButtonState extends State<_GlassMenuButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;
    final label = widget.label;

    final content = SizedBox(
      height: AppSize.control,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: label == null ? 8 : 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label == null)
              Icon(widget.icon, size: AppSize.iconLg, color: ink)
            else
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: GlassIconButton.labelStyle(context).copyWith(color: ink),
              ),
            SizedBox(width: label == null ? 2 : 4),
            Icon(Icons.expand_more, size: AppSize.iconSm, color: ink2),
          ],
        ),
      ),
    );

    final radius = BorderRadius.circular(AppRadius.control);
    final Widget box = widget.open
        ? AppGlass(
            grade: GlassGrade.lens,
            borderRadius: radius,
            reducedColor: scheme.accentTint,
            child: content,
          )
        : AnimatedContainer(
            duration: AppMotion.durationOf(context, AppMotion.hover),
            curve: AppMotion.quick,
            decoration: BoxDecoration(
              color: _hovering ? ink.withValues(alpha: 0.08) : Colors.transparent,
              borderRadius: radius,
            ),
            child: content,
          );

    return Semantics(
      button: true,
      label: widget.tooltip,
      child: Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: box,
          ),
        ),
      ),
    );
  }
}

/// The accent's solid form on the glass bar: tinted glass, 32 tall, r10.
///
/// With a [subtitle] it is `1a`'s two-line Save Copy — the 600 label over an
/// 11px destination at 85% opacity. While [loading], the label keeps its room
/// and a spinner stands over it, so the row does not reflow mid-save.
class _TintedButton extends StatelessWidget {
  const _TintedButton({
    required this.label,
    required this.onPressed,
    this.subtitle,
    this.icon,
    this.showLabel = true,
    this.tooltip,
    this.loading = false,
  });

  final String label;
  final String? subtitle;
  final IconData? icon;
  final bool showLabel;
  final String? tooltip;
  final bool loading;
  final VoidCallback? onPressed;

  static double widthFor(BuildContext context, {required String label, String? subtitle, bool icon = false}) {
    var text = measureGlassText(context, label, _saveLabelStyle(context));
    if (subtitle != null) {
      text = math.max(text, measureGlassText(context, subtitle, _saveSubtitleStyle(context)));
    }
    return (12 + (icon ? AppSize.iconMd + 6 : 0) + text + 12).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A save in flight keeps its fill: the spinner is the state, and a CTA
    // that greys out the moment it is pressed reads as having failed.
    final lit = onPressed != null || loading;

    final Widget text = subtitle == null
        ? Text(label, maxLines: 1, softWrap: false, style: _saveLabelStyle(context))
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, maxLines: 1, softWrap: false, style: _saveLabelStyle(context)),
              Opacity(
                opacity: 0.85,
                child: Text(subtitle!, maxLines: 1, softWrap: false, style: _saveSubtitleStyle(context)),
              ),
            ],
          );

    Widget content;
    if (!showLabel && icon != null) {
      content = SizedBox(
        width: AppSize.control - 24,
        child: Icon(icon, size: AppSize.iconMd),
      );
    } else {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppSize.iconMd),
            const SizedBox(width: 6),
          ],
          text,
        ],
      );
    }
    content = _Spinning(on: loading, color: scheme.onPrimary, child: content);

    Widget button = MouseRegion(
      cursor: onPressed != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onPressed,
        child: AppTintedGlass(
          enabled: lit,
          child: SizedBox(
            height: AppSize.control,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(widthFactor: 1, child: content),
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip ?? label,
      child: button,
    );
  }
}

/// [child] with a small spinner over it while [on], keeping its size.
class _Spinning extends StatelessWidget {
  const _Spinning({required this.on, required this.color, required this.child});

  final bool on;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!on) return child;
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(opacity: 0, child: child),
        SizedBox(
          width: AppSize.iconSm,
          height: AppSize.iconSm,
          child: CircularProgressIndicator(strokeWidth: 2, color: color),
        ),
      ],
    );
  }
}
