import 'package:flutter/material.dart';

import '../models/app_image.dart';

class WorkbenchUIState extends ChangeNotifier {
  // Preview State
  List<AppImage> previewImages = [];
  int activePreviewIndex = 0;

  // Comparator State
  bool isComparatorOpen = false; 
  String? comparatorRawPath;
  String? comparatorAfterPath;
  bool isComparatorSyncMode = true; // true: Sync side-by-side, false: Hover swap

  // Mask Editor State
  AppImage? maskEditorSourceImage;

  // Prompt Optimizer State
  String optimizerRoughPrompt = "";
  List<AppImage> optimizerReferenceImages = [];

  // Preview Methods
  void setPreviewList(List<AppImage> images, int initialIndex) {
    previewImages = List.from(images);
    activePreviewIndex = initialIndex.clamp(0, previewImages.isEmpty ? 0 : previewImages.length - 1);
    notifyListeners();
  }

  void setActivePreview(int index) {
    if (index >= 0 && index < previewImages.length) {
      activePreviewIndex = index;
      notifyListeners();
    }
  }

  void clearAllPreviews() {
    activePreviewIndex = 0;
    notifyListeners();
  }

  // Optimizer Methods
  void sendToOptimizer(String prompt, List<AppImage> images) {
    optimizerRoughPrompt = prompt;
    optimizerReferenceImages = List.from(images);
    notifyListeners();
  }

  // Comparator Methods
  void sendToComparator(String path, {bool isAfter = false}) {
    if (isAfter) {
      comparatorAfterPath = path;
    } else {
      comparatorRawPath = path;
    }
    isComparatorOpen = true; // Signal that we have data
    notifyListeners();
  }

  void clearComparator() {
    comparatorRawPath = null;
    comparatorAfterPath = null;
    notifyListeners();
  }

  void toggleComparatorMode() {
    isComparatorSyncMode = !isComparatorSyncMode;
    notifyListeners();
  }

  void setMaskEditorSourceImage(AppImage? image) {
    maskEditorSourceImage = image;
    notifyListeners();
  }

  void setCropResizeSourceImage(AppImage? image) {
    cropResizeSourceImage = image;
    notifyListeners();
  }

  // Crop & Resize State
  AppImage? cropResizeSourceImage;
  double? cropAspectRatio; 
  int? targetWidth;
  int? targetHeight;
  bool maintainAspectRatio = true;
  String samplingMethod = 'lanczos';
  final GlobalKey<State> cropKey = GlobalKey<State>();

  void setCropAspectRatio(double? ratio) {
    cropAspectRatio = ratio;
    notifyListeners();
  }

  void setTargetDimensions(int? width, int? height) {
    targetWidth = width;
    targetHeight = height;
    notifyListeners();
  }

  void setMaintainAspectRatio(bool maintain) {
    maintainAspectRatio = maintain;
    notifyListeners();
  }

  void setSamplingMethod(String method) {
    samplingMethod = method;
    notifyListeners();
  }
}