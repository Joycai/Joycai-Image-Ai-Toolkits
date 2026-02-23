import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/app_paths.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../services/image_processing_service.dart';
import '../../../state/app_state.dart';
import '../../../state/workbench_ui_state.dart';

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
  bool _isProcessing = false;
  bool _isAutoUpdating = false;

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
    if (!uiState.maintainAspectRatio) return;

    final state = uiState.cropKey.currentState as ExtendedImageEditorState?;
    if (state == null) return;
    final cropRect = state.getCropRect();
    if (cropRect == null) return;

    final double ratio = cropRect.width / cropRect.height;
    final int? w = int.tryParse(_widthController.text);
    if (w != null) {
      _isAutoUpdating = true;
      _heightController.text = (w / ratio).round().toString();
      _isAutoUpdating = false;
    }
  }

  void _onHeightChanged() {
    if (_isAutoUpdating) return;
    final uiState = Provider.of<WorkbenchUIState>(context, listen: false);
    if (!uiState.maintainAspectRatio) return;

    final state = uiState.cropKey.currentState as ExtendedImageEditorState?;
    if (state == null) return;
    final cropRect = state.getCropRect();
    if (cropRect == null) return;

    final double ratio = cropRect.width / cropRect.height;
    final int? h = int.tryParse(_heightController.text);
    if (h != null) {
      _isAutoUpdating = true;
      _widthController.text = (h * ratio).round().toString();
      _isAutoUpdating = false;
    }
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

  Future<void> _handleSave({bool overwrite = false}) async {
    final l10n = AppLocalizations.of(context)!;
    final uiState = Provider.of<WorkbenchUIState>(context, listen: false);
    final appState = Provider.of<AppState>(context, listen: false);

    if (overwrite) {
      final confirmTitle = l10n.overwriteConfirmTitle;
      final confirmMessage = l10n.overwriteConfirmMessage;
      final cancelLabel = l10n.cancel;
      final overwriteLabel = l10n.overwriteSource;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(confirmTitle),
          content: Text(confirmMessage),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(cancelLabel)),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: Text(overwriteLabel),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (!mounted) return;
    setState(() => _isProcessing = true);

    try {
      final sourceImage = uiState.cropResizeSourceImage;
      if (sourceImage == null) return;

      final state = uiState.cropKey.currentState as ExtendedImageEditorState?;
      if (state == null) return;
      
      final cropRect = state.getCropRect();
      if (cropRect == null) return;

      final int? w = int.tryParse(_widthController.text);
      final int? h = int.tryParse(_heightController.text);
      
      SamplingMethod sampling;
      switch (uiState.samplingMethod) {
        case 'nearest': sampling = SamplingMethod.nearest; break;
        case 'linear': sampling = SamplingMethod.linear; break;
        case 'cubic': sampling = SamplingMethod.cubic; break;
        default: sampling = SamplingMethod.lanczos;
      }

      final processedBytes = await ImageProcessingService().processImage(
        sourcePath: sourceImage.path,
        cropX: cropRect.left.toInt(),
        cropY: cropRect.top.toInt(),
        cropWidth: cropRect.width.toInt(),
        cropHeight: cropRect.height.toInt(),
        width: w,
        height: h,
        maintainAspectRatio: uiState.maintainAspectRatio,
        sampling: sampling,
      );

      String targetPath;
      String targetName;

      if (overwrite) {
        targetPath = sourceImage.path;
        targetName = sourceImage.name;
      } else {
        final tempDir = await AppPaths.getTempDirectory();
        final outputDir = Directory(p.join(tempDir, 'joycai', 'processed'));
        if (!outputDir.existsSync()) outputDir.createSync(recursive: true);
        
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        targetName = 'crop_${p.basenameWithoutExtension(sourceImage.path)}_$timestamp.png';
        targetPath = p.join(outputDir.path, targetName);
      }

      await ImageProcessingService().saveImage(bytes: processedBytes, targetPath: targetPath);

      final successMessage = overwrite ? l10n.overwriteSuccess : l10n.saveToTempSuccess;

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: Colors.green,
        ),
      );

      if (!overwrite) {
        final newFile = AppImage(path: targetPath, name: targetName);
        appState.galleryState.addDroppedFiles([newFile]);
      }
      
      appState.galleryState.refreshImages();
      appState.setWorkbenchTab(0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final bool isMedium = width < 1250;
        final bool isSmall = width < 1050;

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
              VerticalDivider(width: isSmall ? 16 : 24, indent: 16, endIndent: 16),
              
              // Aspect Ratio Section
              Flexible(
                flex: 4,
                child: _buildDesktopRatioSelector(l10n, uiState, colorScheme, isSmall),
              ),
              
              VerticalDivider(width: isSmall ? 24 : 32, indent: 16, endIndent: 16),

              // Resize Section
              Flexible(
                flex: 3,
                child: _buildDesktopResizeControls(l10n, uiState, colorScheme, isSmall),
              ),

              const SizedBox(width: 8),

              // Actions Section
              if (_isProcessing)
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              else
                _buildDesktopSaveActions(l10n, colorScheme, isMedium),
            ],
          ),
        );
      }
    );
  }

  Widget _buildDesktopSaveActions(AppLocalizations l10n, ColorScheme colorScheme, bool compact) {
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.outlined(
            onPressed: () => _handleSave(overwrite: false),
            icon: const Icon(Icons.save_alt, size: 20),
            tooltip: l10n.saveToTemp,
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: () => _handleSave(overwrite: true),
            icon: const Icon(Icons.save, size: 20),
            tooltip: l10n.overwriteSource,
            style: IconButton.styleFrom(backgroundColor: colorScheme.error),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: () => _handleSave(overwrite: false),
          icon: const Icon(Icons.save_alt, size: 18),
          label: Text(l10n.saveToTemp, style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: () => _handleSave(overwrite: true),
          icon: const Icon(Icons.save, size: 18),
          label: Text(l10n.overwriteSource, style: const TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
        ),
      ],
    );
  }

  Widget _buildDesktopRatioSelector(AppLocalizations l10n, WorkbenchUIState uiState, ColorScheme colorScheme, bool compact) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.aspect_ratio, size: 20, color: Colors.grey),
        const SizedBox(width: 12),
        Flexible(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildRatioItem("Free", null, uiState.cropAspectRatio),
                _buildRatioItem("1:1", 1.0, uiState.cropAspectRatio),
                _buildRatioItem("4:3", 4/3, uiState.cropAspectRatio),
                _buildRatioItem("16:9", 16/9, uiState.cropAspectRatio),
                if (!compact) ...[
                  _buildRatioItem("3:4", 3/4, uiState.cropAspectRatio),
                  _buildRatioItem("9:16", 9/16, uiState.cropAspectRatio),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Custom Ratio Inputs
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha(100),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildRatioField(_ratioXController),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 2), child: Text(":", style: TextStyle(fontSize: 12))),
              _buildRatioField(_ratioYController),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRatioItem(String label, double? ratio, double? current) {
    final isSelected = ratio == current;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: isSelected,
        onSelected: (v) => _updateAspectRatio(ratio),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildRatioField(TextEditingController ctrl) {
    return SizedBox(
      width: 24,
      child: TextField(
        controller: ctrl,
        decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildDesktopResizeControls(AppLocalizations l10n, WorkbenchUIState uiState, ColorScheme colorScheme, bool compact) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.photo_size_select_large, size: 20, color: Colors.grey),
        const SizedBox(width: 12),
        _buildDimensionField(_widthController, compact ? null : l10n.width),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text("×", style: TextStyle(color: Colors.grey))),
        _buildDimensionField(_heightController, compact ? null : l10n.height),
        const SizedBox(width: 4),
        IconButton(
          icon: Icon(uiState.maintainAspectRatio ? Icons.lock : Icons.lock_open, size: 18),
          onPressed: () => uiState.setMaintainAspectRatio(!uiState.maintainAspectRatio),
          tooltip: l10n.maintainAspectRatio,
          color: uiState.maintainAspectRatio ? colorScheme.primary : null,
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 4),
        
        if (!compact)
          DropdownButton<String>(
            value: uiState.samplingMethod,
            underline: const SizedBox(),
            style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
            items: const [
              DropdownMenuItem(value: 'lanczos', child: Text("Lanczos")),
              DropdownMenuItem(value: 'cubic', child: Text("Cubic")),
              DropdownMenuItem(value: 'linear', child: Text("Linear")),
              DropdownMenuItem(value: 'nearest', child: Text("Nearest")),
            ],
            onChanged: (v) => uiState.setSamplingMethod(v!),
          )
        else
          PopupMenuButton<String>(
            icon: const Icon(Icons.tune, size: 18),
            tooltip: l10n.sampling,
            onSelected: (v) => uiState.setSamplingMethod(v),
            itemBuilder: (context) => [
              _buildSamplingItem('lanczos', 'Lanczos', uiState.samplingMethod),
              _buildSamplingItem('cubic', 'Cubic', uiState.samplingMethod),
              _buildSamplingItem('linear', 'Linear', uiState.samplingMethod),
              _buildSamplingItem('nearest', 'Nearest', uiState.samplingMethod),
            ],
          ),
      ],
    );
  }

  PopupMenuItem<String> _buildSamplingItem(String value, String label, String current) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          if (value == current) ...[
            const Spacer(),
            const Icon(Icons.check, size: 16, color: Colors.blue),
          ],
        ],
      ),
    );
  }

  Widget _buildDimensionField(TextEditingController ctrl, String? label) {
    return SizedBox(
      width: label == null ? 50 : 70,
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          labelStyle: const TextStyle(fontSize: 10),
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        style: const TextStyle(fontSize: 12),
        keyboardType: TextInputType.number,
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
              icon: Icons.close, 
              label: l10n.cancel, 
              onTap: () => Provider.of<AppState>(context, listen: false).setWorkbenchTab(0),
            ),
            _buildMobileAction(
              icon: Icons.aspect_ratio, 
              label: l10n.aspectRatio, 
              onTap: () => _showMobileRatioSheet(context, l10n, uiState),
            ),
            _buildMobileAction(
              icon: Icons.photo_size_select_large, 
              label: l10n.resize, 
              onTap: () => _showMobileResizeDialog(context, l10n, uiState),
            ),
            _buildMobileAction(
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

  Widget _buildMobileAction({required IconData icon, required String label, required VoidCallback onTap, Color? color}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color ?? Colors.grey[700], size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 10, color: color ?? Colors.grey[700], fontWeight: FontWeight.w500)),
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
      label: Text(label, style: const TextStyle(fontSize: 11)),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.resize),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: _buildDimensionField(_widthController, l10n.width)),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("×")),
                  Expanded(child: _buildDimensionField(_heightController, l10n.height)),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: Text(l10n.maintainAspectRatio, style: const TextStyle(fontSize: 13)),
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
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.close)),
        ],
      ),
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
              leading: const Icon(Icons.save, color: Colors.red),
              title: Text(l10n.overwriteSource, style: const TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _handleSave(overwrite: true);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
