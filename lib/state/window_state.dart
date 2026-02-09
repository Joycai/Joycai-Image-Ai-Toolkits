import 'package:flutter/material.dart';

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
