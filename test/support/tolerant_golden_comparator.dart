import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [LocalFileComparator] that allows a bounded per-pixel difference ratio to
/// absorb minor cross-platform font/Skia rasterization variance while still
/// failing on genuine layout, color, or component regressions.
class TolerantGoldenFileComparator extends LocalFileComparator {
  TolerantGoldenFileComparator(super.testFile, {this.precisionTolerance = 0.015});

  /// Maximum fraction of differing pixels (0.0–1.0) tolerated before failing.
  final double precisionTolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final ComparisonResult result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );

    if (result.passed) {
      result.dispose();
      return true;
    }

    if (result.diffPercent <= precisionTolerance) {
      debugPrint(
        '[golden] ${golden.path} within tolerance: '
        '${(result.diffPercent * 100).toStringAsFixed(3)}% <= '
        '${(precisionTolerance * 100).toStringAsFixed(2)}%',
      );
      result.dispose();
      return true;
    }

    final String error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(
      '$error\nDiff ${(result.diffPercent * 100).toStringAsFixed(3)}% '
      'exceeded tolerance ${(precisionTolerance * 100).toStringAsFixed(2)}%.',
    );
  }
}
