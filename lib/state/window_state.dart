import 'package:flutter/material.dart';

import '../models/app_file.dart';

class WindowState extends ChangeNotifier {
  // Preview State
  final List<String> openedPreviewPaths = [];
  int activePreviewIndex = 0;

  // Comparator State
  bool isComparatorOpen = false; // Kept for logic, but might be redundant if we just use the tab
  String? comparatorRawPath;
  String? comparatorAfterPath;
  bool isComparatorSyncMode = true; // true: Sync side-by-side, false: Hover swap

  // Mask Editor State
  AppFile? maskEditorSourceImage;

  // Preview Methods
  void openPreview(String path) {
    if (!openedPreviewPaths.contains(path)) {
      openedPreviewPaths.add(path);
      activePreviewIndex = openedPreviewPaths.length - 1;
    } else {
      activePreviewIndex = openedPreviewPaths.indexOf(path);
    }
    notifyListeners();
  }

  void closePreview(int index) {
    if (index < 0 || index >= openedPreviewPaths.length) return;
    
    openedPreviewPaths.removeAt(index);
    if (activePreviewIndex >= openedPreviewPaths.length) {
      activePreviewIndex = openedPreviewPaths.length - 1;
    }
    if (activePreviewIndex < 0) activePreviewIndex = 0;
    
    notifyListeners();
  }
  
  void setActivePreview(int index) {
    if (index >= 0 && index < openedPreviewPaths.length) {
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