import 'package:flutter/material.dart';

class PreviewWindowState {
  final String id;
  final String imagePath;
  Offset position;
  Size size;

  PreviewWindowState({
    required this.id,
    required this.imagePath,
    this.position = const Offset(100, 100),
    this.size = const Size(400, 300),
  });
}

class WindowState extends ChangeNotifier {
  final List<PreviewWindowState> floatingPreviews = [];

  // Comparator State
  bool isComparatorOpen = false;
  String? comparatorRawPath;
  String? comparatorAfterPath;
  bool isComparatorSyncMode = true; // true: Sync side-by-side, false: Hover swap
  Offset comparatorPosition = const Offset(150, 150);
  Size comparatorSize = const Size(800, 500);

  void openFloatingPreview(String path) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    // Offset each new window slightly
    final offset = Offset(
      100.0 + (floatingPreviews.length % 5) * 30,
      100.0 + (floatingPreviews.length % 5) * 30,
    );
    floatingPreviews.add(PreviewWindowState(id: id, imagePath: path, position: offset));
    notifyListeners();
  }

  void closeFloatingPreview(String id) {
    floatingPreviews.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  void bringToFront(String id) {
    final index = floatingPreviews.indexWhere((p) => p.id == id);
    if (index != -1 && index != floatingPreviews.length - 1) {
      final preview = floatingPreviews.removeAt(index);
      floatingPreviews.add(preview);
      notifyListeners();
    }
  }

  void updateFloatingPreviewPosition(String id, Offset newPosition) {
    final index = floatingPreviews.indexWhere((p) => p.id == id);
    if (index != -1) {
      floatingPreviews[index].position = newPosition;
      notifyListeners();
    }
  }

  void updateFloatingPreviewSize(String id, Size newSize) {
    final index = floatingPreviews.indexWhere((p) => p.id == id);
    if (index != -1) {
      floatingPreviews[index].size = newSize;
      notifyListeners();
    }
  }

  void sendToComparator(String path, {bool isAfter = false}) {
    if (!isComparatorOpen) {
      isComparatorOpen = true;
      comparatorRawPath = path;
      comparatorAfterPath = null;
    } else {
      if (isAfter) {
        comparatorAfterPath = path;
      } else {
        comparatorRawPath = path;
      }
    }
    notifyListeners();
  }

  void closeComparator() {
    isComparatorOpen = false;
    notifyListeners();
  }

  void toggleComparatorMode() {
    isComparatorSyncMode = !isComparatorSyncMode;
    notifyListeners();
  }

  void updateComparatorPosition(Offset newPosition) {
    comparatorPosition = newPosition;
    notifyListeners();
  }

  void updateComparatorSize(Size newSize) {
    comparatorSize = newSize;
    notifyListeners();
  }
}