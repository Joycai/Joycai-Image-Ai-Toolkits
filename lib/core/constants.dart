enum AppAspectRatio {
  notSet('not_set'),
  r1_1('1:1'),
  r2_3('2:3'),
  r3_2('3:2'),
  r3_4('3:4'),
  r4_3('4:3'),
  r4_5('4:5'),
  r5_4('5:4'),
  r9_16('9:16'),
  r16_9('16:9');

  final String value;
  const AppAspectRatio(this.value);

  static AppAspectRatio fromString(String? val) {
    return AppAspectRatio.values.firstWhere((e) => e.value == val, orElse: () => AppAspectRatio.notSet);
  }
}

enum AppResolution {
  r1K('1K'),
  r2K('2K'),
  r4K('4K');

  final String value;
  const AppResolution(this.value);

  static AppResolution fromString(String? val) {
    return AppResolution.values.firstWhere((e) => e.value == val, orElse: () => AppResolution.r1K);
  }
}

enum BillingMode {
  token('token'),
  request('request');

  final String value;
  const BillingMode(this.value);

  static BillingMode fromString(String? val) {
    return BillingMode.values.firstWhere((e) => e.value == val, orElse: () => BillingMode.token);
  }
}

enum ModelTag {
  image('image'),
  multimodal('multimodal'),
  chat('chat'),
  refiner('refiner');

  final String value;
  const ModelTag(this.value);

  static ModelTag fromString(String? val) {
    return ModelTag.values.firstWhere((e) => e.value == val, orElse: () => ModelTag.chat);
  }
}

class AppConstants {
  // UI Defaults
  static const double defaultThumbnailSize = 150.0;
  static const int maxConcurrency = 8;
  static const Duration animationDuration = Duration(milliseconds: 200);

  // Opacity levels
  static const double opacityLow = 0.05;
  static const double opacityMedium = 0.3;
  static const double opacityHigh = 0.5;

  static bool isImageFile(String path) {
    final ext = path.toLowerCase();
    return ext.endsWith('.jpg') || 
           ext.endsWith('.jpeg') || 
           ext.endsWith('.png') || 
           ext.endsWith('.webp') || 
           ext.endsWith('.bmp');
  }
}
