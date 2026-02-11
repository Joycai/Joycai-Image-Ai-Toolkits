import 'package:flutter/material.dart';

import '../core/responsive.dart';

class PreviewWindowState {
  final String id;
  final String imagePath;
  Offset position;
  Size size;
  bool isMaximized;
  Offset restorePosition;
  Size restoreSize;

  PreviewWindowState({
    required this.id,
    required this.imagePath,
    this.position = const Offset(100, 100),
    this.size = const Size(400, 300),
    this.isMaximized = false,
  })  : restorePosition = position,
        restoreSize = size;
}

class WindowState extends ChangeNotifier {
  final List<PreviewWindowState> floatingPreviews = [];
  Size _lastScreenSize = Size.zero;

  // Comparator State
  bool isComparatorOpen = false;
  String? comparatorRawPath;
  String? comparatorAfterPath;
  bool isComparatorSyncMode = true; // true: Sync side-by-side, false: Hover swap
  Offset comparatorPosition = const Offset(150, 150);
  Size comparatorSize = const Size(800, 500);
  bool isComparatorMaximized = false;
  Offset comparatorRestorePosition = const Offset(150, 150);
  Size comparatorRestoreSize = const Size(800, 500);

  void updateScreenSize(Size size) {
    if (_lastScreenSize == size) return;
    
    final oldSize = _lastScreenSize;
    _lastScreenSize = size;

    if (oldSize == Size.zero) return;

    // Boundary enforcement for existing windows
    for (var preview in floatingPreviews) {
      if (preview.isMaximized) {
        preview.size = size;
      } else {
        _ensurePreviewInBounds(preview, size);
      }
    }

    if (isComparatorMaximized) {
      comparatorSize = size;
    } else {
      _ensureComparatorInBounds(size);
    }

    notifyListeners();
  }

  void _ensurePreviewInBounds(PreviewWindowState preview, Size screenSize) {
    // Basic clamping
    double x = preview.position.dx;
    double y = preview.position.dy;
    
    if (x + 50 > screenSize.width) x = screenSize.width - 100;
    if (y + 50 > screenSize.height) y = screenSize.height - 100;
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    
    preview.position = Offset(x, y);
    
    // Size clamping
    double w = preview.size.width;
    double h = preview.size.height;
    if (w > screenSize.width) w = screenSize.width;
    if (h > screenSize.height) h = screenSize.height;
    preview.size = Size(w, h);
  }

  void _ensureComparatorInBounds(Size screenSize) {
    double x = comparatorPosition.dx;
    double y = comparatorPosition.dy;
    
    if (x + 50 > screenSize.width) x = screenSize.width - 100;
    if (y + 50 > screenSize.height) y = screenSize.height - 100;
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    
    comparatorPosition = Offset(x, y);

    double w = comparatorSize.width;
    double h = comparatorSize.height;
    if (w > screenSize.width) w = screenSize.width;
    if (h > screenSize.height) h = screenSize.height;
    comparatorSize = Size(w, h);
  }

  void openFloatingPreview(String path) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final isMobile = _lastScreenSize.width < Responsive.mobileBreakpoint;

    // Offset each new window slightly
    final offset = Offset(
      50.0 + (floatingPreviews.length % 5) * 30,
      50.0 + (floatingPreviews.length % 5) * 30,
    );

    final preview = PreviewWindowState(
      id: id, 
      imagePath: path, 
      position: isMobile ? Offset.zero : offset,
      size: isMobile ? _lastScreenSize : const Size(400, 300),
      isMaximized: isMobile,
    );
    
    floatingPreviews.add(preview);
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
      if (!floatingPreviews[index].isMaximized) {
        floatingPreviews[index].restorePosition = newPosition;
      }
      notifyListeners();
    }
  }

  void updateFloatingPreviewSize(String id, Size newSize) {
    final index = floatingPreviews.indexWhere((p) => p.id == id);
    if (index != -1) {
      floatingPreviews[index].size = newSize;
      if (!floatingPreviews[index].isMaximized) {
        floatingPreviews[index].restoreSize = newSize;
      }
      notifyListeners();
    }
  }

  void toggleMaximizeFloatingPreview(String id, Size maxSize) {
    final index = floatingPreviews.indexWhere((p) => p.id == id);
    if (index != -1) {
      final preview = floatingPreviews[index];
      if (preview.isMaximized) {
        preview.isMaximized = false;
        preview.position = preview.restorePosition;
        preview.size = preview.restoreSize;
      } else {
        preview.restorePosition = preview.position;
        preview.restoreSize = preview.size;
        preview.isMaximized = true;
        preview.position = Offset.zero;
        preview.size = maxSize;
      }
      notifyListeners();
    }
  }

  void sendToComparator(String path, {bool isAfter = false}) {
    if (!isComparatorOpen) {
      isComparatorOpen = true;
      comparatorRawPath = path;
      comparatorAfterPath = null;
      
      final isMobile = _lastScreenSize.width < Responsive.mobileBreakpoint;
      if (isMobile) {
        isComparatorMaximized = true;
        comparatorPosition = Offset.zero;
        comparatorSize = _lastScreenSize;
      }
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
    if (!isComparatorMaximized) {
      comparatorRestorePosition = newPosition;
    }
    notifyListeners();
  }

  void updateComparatorSize(Size newSize) {
    comparatorSize = newSize;
    if (!isComparatorMaximized) {
      comparatorRestoreSize = newSize;
    }
    notifyListeners();
  }

  void toggleMaximizeComparator(Size maxSize) {
    if (isComparatorMaximized) {
      isComparatorMaximized = false;
      comparatorPosition = comparatorRestorePosition;
      comparatorSize = comparatorRestoreSize;
    } else {
      comparatorRestorePosition = comparatorPosition;
      comparatorRestoreSize = comparatorSize;
      isComparatorMaximized = true;
      comparatorPosition = Offset.zero;
      comparatorSize = maxSize;
    }
    notifyListeners();
  }
}