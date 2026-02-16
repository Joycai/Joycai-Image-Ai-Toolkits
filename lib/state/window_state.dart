import 'package:flutter/material.dart';

import '../models/app_file.dart';

class WindowState extends ChangeNotifier {
  // Preview State
  List<AppFile> previewImages = [];
  int activePreviewIndex = 0;
  final List<String> openedPreviewPaths = []; // Kept for minimal compatibility if needed

  // Comparator State
  bool isComparatorOpen = false; 
  String? comparatorRawPath;
  String? comparatorAfterPath;
  bool isComparatorSyncMode = true; // true: Sync side-by-side, false: Hover swap

  // Mask Editor State
  AppFile? maskEditorSourceImage;

  // Preview Methods
  void setPreviewList(List<AppFile> images, int initialIndex) {
    previewImages = List.from(images);
    activePreviewIndex = initialIndex.clamp(0, previewImages.isEmpty ? 0 : previewImages.length - 1);
    notifyListeners();
  }

  void openPreview(String path) {
    // Legacy support logic
    if (!openedPreviewPaths.contains(path)) {
      openedPreviewPaths.add(path);
    }
    // We now prefer setPreviewList
  }

  void closePreview(int index) {
    // No-op for the new browsing logic
  }
  
  void setActivePreview(int index) {
    if (index >= 0 && index < previewImages.length) {
      activePreviewIndex = index;
      notifyListeners();
    }
  }

  void clearAllPreviews() {
    openedPreviewPaths.clear();
    activePreviewIndex = 0;
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

  void setMaskEditorSourceImage(AppFile? image) {
    maskEditorSourceImage = image;
    notifyListeners();
  }
}