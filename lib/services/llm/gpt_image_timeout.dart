/// Shared settings/option contract for GPT Image's slow-response threshold.
/// This is a soft deadline: retain the accepted request and save late results.
abstract final class GptImageTimeout {
  static const settingKey = 'gpt_image_timeout_minutes';
  static const defaultMinutes = 25;
  static const choices = [5, 10, 15, 25, 30, 45, 60, 120];

  static int normalize(Object? value) {
    final minutes = value is int ? value : int.tryParse('$value');
    return minutes != null && minutes >= 1 && minutes <= 120 ? minutes : defaultMinutes;
  }

  static Duration fromOptions(Map<String, dynamic>? options) =>
      Duration(minutes: normalize(options?[settingKey]));
}
