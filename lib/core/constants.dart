class AppConstants {
  // Workbench Configs
  static const List<String> aspectRatios = [
    "not_set", "1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9"
  ];

  static const List<String> resolutions = ['1K', '2K', '4K'];

  // Billing & Models
  static const List<String> billingModes = ['token', 'request'];
  static const List<String> modelTags = ['image', 'multimodal', 'chat', 'refiner'];

  // UI Defaults
  static const double defaultThumbnailSize = 150.0;
  static const int maxConcurrency = 8;
  static const Duration animationDuration = Duration(milliseconds: 200);

  // Opacity levels
  static const double opacityLow = 0.05;
  static const double opacityMedium = 0.3;
  static const double opacityHigh = 0.5;
}
