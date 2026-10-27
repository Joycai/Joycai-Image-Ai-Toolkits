import 'dart:convert';

import 'spec_rate.dart';

/// Optional modality prices, in USD per million tokens. Missing is unknown,
/// never an implicit zero. Video input rates match the output specification.
class MediaPricing {
  final double? imageInput;
  final double? imageCache;
  final double? imageOutput;
  final List<SpecRate> videoInputRates;
  const MediaPricing({
    this.imageInput,
    this.imageCache,
    this.imageOutput,
    this.videoInputRates = const [],
  });
  Map<String, dynamic> toMap() => {
    'imageInput': imageInput,
    'imageCache': imageCache,
    'imageOutput': imageOutput,
    'videoInputRates': videoInputRates.map((r) => r.toJson()).toList(),
  };
  factory MediaPricing.fromMap(Map<String, dynamic> map) => MediaPricing(
    imageInput: (map['imageInput'] as num?)?.toDouble(),
    imageCache: (map['imageCache'] as num?)?.toDouble(),
    imageOutput: (map['imageOutput'] as num?)?.toDouble(),
    videoInputRates: (map['videoInputRates'] as List? ?? [])
        .map((r) => SpecRate.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList(),
  );
  static MediaPricing decode(Object? raw) {
    if (raw is! String) return const MediaPricing();
    try {
      return MediaPricing.fromMap(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return const MediaPricing();
    }
  }
}
