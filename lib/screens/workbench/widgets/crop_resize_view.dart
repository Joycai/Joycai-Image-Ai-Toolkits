import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/app_state.dart';
import '../../../state/workbench_ui_state.dart';

class CropResizeView extends StatefulWidget {
  const CropResizeView({super.key});

  @override
  State<CropResizeView> createState() => _CropResizeViewState();
}

class _CropResizeViewState extends State<CropResizeView> {
  @override
  Widget build(BuildContext context) {
    final uiState = Provider.of<WorkbenchUIState>(context);
    final sourceImage = uiState.cropResizeSourceImage;

    if (sourceImage == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.crop, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text("No image selected for cropping"),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Provider.of<AppState>(context, listen: false).setWorkbenchTab(0),
              child: const Text("Go to Gallery"),
            ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.black87,
      child: ExtendedImage.file(
        File(sourceImage.path),
        key: ValueKey("${sourceImage.path}_${uiState.cropAspectRatio}"),
        fit: BoxFit.contain,
        mode: ExtendedImageMode.editor,
        enableLoadState: true,
        extendedImageEditorKey: uiState.cropKey,
        initEditorConfigHandler: (state) {
          return EditorConfig(
            maxScale: 8.0,
            cropRectPadding: const EdgeInsets.all(20.0),
            hitTestSize: 20.0,
            cropAspectRatio: uiState.cropAspectRatio,
          );
        },
      ),
    );
  }
}
