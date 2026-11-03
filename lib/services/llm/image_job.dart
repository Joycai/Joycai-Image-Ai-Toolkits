/// Persisted recovery information. No credentials or reference bytes are stored.
class ImageJob {
  const ImageJob({
    required this.id,
    required this.base,
    required this.model,
    required this.inputImages,
    this.sentSize,
  });
  static const taskKey = '_imageJob';
  static const callbackKey = '_onImageJobSubmitted';
  static const resumeKey = '_resumeImageJob';
  static const surface = 'dashscope-images-async';
  final String id;
  final String base;
  final String model;
  final int inputImages;
  final String? sentSize;

  Map<String, dynamic> toJson() => {
    'id': id,
    'base': base,
    'model': model,
    'inputImages': inputImages,
    'sentSize': sentSize,
  };
  static ImageJob? fromJson(dynamic value) {
    if (value is! Map ||
        value['id'] is! String ||
        value['id'] == '' ||
        value['base'] is! String ||
        value['model'] is! String ||
        value['inputImages'] is! int ||
        (value['sentSize'] != null && value['sentSize'] is! String)) {
      return null;
    }
    return ImageJob(
      id: value['id'],
      base: value['base'],
      model: value['model'],
      inputImages: value['inputImages'],
      sentSize: value['sentSize'] as String?,
    );
  }
}
