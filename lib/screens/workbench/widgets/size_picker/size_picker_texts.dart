import '../../../../l10n/app_localizations.dart';
import '../../../../services/llm/image_size_vocabulary.dart';
import '../../../../services/llm/output_spec.dart';

/// The sentinel's title and the one true sentence beside it (`A1c · 30a`):
/// gpt's `auto` is "the model decides"; qwen's and wan's `not_set` are *not*
/// automatic — the app chooses — so they say what the app sends. [long] is
/// the popover's fuller qwen wording.
(String, String) sentinelTexts(AppLocalizations l10n, SizeSentinelMeaning meaning, {bool long = false}) {
  return switch (meaning) {
    SizeSentinelMeaning.modelDecides => (l10n.imageSizeAuto, l10n.imageSizeHintGpt),
    SizeSentinelMeaning.followsInput => (
      l10n.imageSizeNotSet,
      long ? l10n.imageSizeHintQwen('1024 × 1024', '1K') : l10n.imageSizeHintQwenShort('1K'),
    ),
    SizeSentinelMeaning.sendsLowestTier => (l10n.imageSizeNotSet, l10n.imageSizeHintWan('1K')),
  };
}

/// A stored size as the picker writes it: `2688 × 1536`, or the value itself
/// when it is not a pixel size (`2K`).
String sizeValueText(String value) {
  final wxh = parseWxH(value);
  return wxh == null ? value : '${wxh.width} × ${wxh.height}';
}
