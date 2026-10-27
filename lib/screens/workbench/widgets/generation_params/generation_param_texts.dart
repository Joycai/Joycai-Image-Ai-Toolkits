import '../../../../l10n/app_localizations.dart';
import '../../../../services/llm/generation/generation_schema.dart';

/// Shared labels for both generation forms; no provider/model branches.
class GenerationParamTexts {
  static String diagnostic(AppLocalizations l10n, GenerationDiagnostic diagnostic) =>
      switch (diagnostic.code) {
        'unsupportedReferenceMedia' => l10n.generationUnsupportedReferenceMedia,
        'videoPromptLength' => l10n.generationVideoPromptLength,
        'wanEditSize' => l10n.generationWanEditSize,
        'agentTextOnly' => l10n.generationAgentTextOnly,
        'transparentJpeg' => l10n.generationTransparentJpeg,
        'unsupportedLastFrame' => l10n.generationUnsupportedLastFrame,
        'missingFirstFrame' => l10n.generationMissingFirstFrame,
        'conflictingMedia' => l10n.generationConflictingMedia,
        'singleSourceRequired' => l10n.generationSingleSource,
        'duplicateFrame' => l10n.generationDuplicateFrame,
        'tooManyReferences' || 'groupLimit' => l10n.generationMediaLimit,
        'unreadableMedia' => l10n.generationUnreadableMedia,
        'incompatibleProfile' => l10n.generationIncompatibleProfile,
        'alphaSourceRequired' => l10n.generationTransparentSource,
        _ => l10n.generationInvalidParameter,
      };
  static String label(AppLocalizations l10n, String labelKey, {bool video = false}) {
    switch (labelKey) {
      case 'promptExpansionMode':
        return l10n.paramPromptExpansionMode;
      case 'videoSeconds':
        return l10n.videoSeconds;
      case 'videoAudio':
        return l10n.generationAudio;
      case 'aspectRatio':
        return l10n.aspectRatio;
      case 'resolution':
        // The image families' `resolution` param is a width×height pair, which
        // is a size, not a resolution — and `16a` labels the row 「尺寸」. The
        // video panel's copy of this switch keeps `resolution`: there the
        // param really is one (720p / 1080p).
        return video ? l10n.resolution : l10n.imageSizeLabel;
      case 'imageThinkingLevel':
        return l10n.paramImageThinkingLevel;
      case 'quality':
        return l10n.quality;
      case 'promptExtendMode':
        return l10n.paramPromptExtendMode;
      case 'promptExtend':
        return l10n.promptExtend;
      case 'mjVersion':
        return l10n.mjVersion;
      case 'mjMode':
        return l10n.mjMode;
      case 'mjStylize':
        return l10n.mjStylize;
      case 'mjChaos':
        return l10n.mjChaos;
      case 'imageTask':
        return l10n.paramImageTask;
      case 'maxImages':
        return l10n.paramMaxImages;
      case 'imageBackground':
        return l10n.paramImageBackground;
      case 'outputCompression':
        return l10n.paramOutputCompression;
      case 'outputFormat':
        return l10n.paramOutputFormat;
      case 'optimizeMode':
        return l10n.paramOptimizeMode;
      case 'webSearch':
        return l10n.paramWebSearch;
      case 'watermark':
        return l10n.paramWatermark;
      default:
        return labelKey;
    }
  }

  static String option(
    AppLocalizations l10n,
    String paramKey,
    String value, {
    bool hasExplicitAuto = false,
  }) {
    if (paramKey == 'promptExpansionMode') {
      return switch (value) {
        'disabled' => l10n.promptExpansionDisabled,
        'balanced' => l10n.promptExpansionBalanced,
        'quality' => l10n.promptExpansionQuality,
        _ => value,
      };
    }
    if (paramKey == 'background' && value == 'transparent') return l10n.imageBackgroundTransparent;
    if (paramKey == 'background' && value == 'opaque') return l10n.imageBackgroundOpaque;
    if (paramKey == 'promptExtendMode') {
      if (value == 'direct') return l10n.promptExtendDirect;
      if (value == 'agent') return l10n.promptExtendAgent;
    }
    if (paramKey == 'thinkingLevel') {
      return switch (value) {
        'not_set' => l10n.generationOptionDefault,
        'minimal' => l10n.imageThinkingMinimal,
        'medium' => l10n.reasoningEffortMedium,
        'high' => l10n.reasoningEffortHigh,
        _ => value,
      };
    }
    if (value == 'not_set' && hasExplicitAuto) return l10n.generationOptionDefault;
    if (paramKey == 'seconds') return '${value}s';
    if (paramKey == 'videoQuality') {
      if (value == 'standard') return l10n.videoQualityStandard;
      if (value == 'high') return l10n.videoQualityHigh;
    }
    if (value == 'auto' || value == 'not_set') return l10n.optionAuto;
    // Two-state switches share one on/off vocabulary.
    if (paramKey == 'videoAudio' ||
        paramKey == 'promptExtend' ||
        paramKey == 'imageThinking' ||
        paramKey == 'webSearch' ||
        paramKey == 'watermark') {
      switch (value) {
        case 'on':
          return l10n.promptExtendOn;
        case 'off':
          return l10n.promptExtendOff;
      }
    }
    if (paramKey == 'imageTask') {
      switch (value) {
        case 'generate':
          return l10n.taskGenerate;
        case 'layers':
          return l10n.taskLayers;
        case 'transparent':
          return l10n.taskTransparent;
      }
    }
    if (paramKey == 'maxImages') {
      final n = int.tryParse(value);
      if (n == 1) return l10n.promptExtendOff;
      if (n != null) return l10n.maxImagesUpTo(n);
    }
    if (paramKey == 'optimizeMode') {
      switch (value) {
        case 'standard':
          return l10n.optimizeStandard;
        case 'fast':
          return l10n.optimizeFast;
      }
    }
    if (paramKey == 'outputFormat') return value.toUpperCase();
    if (paramKey == 'quality') {
      switch (value) {
        case 'low':
          return l10n.qualityLow;
        case 'medium':
          return l10n.qualityMedium;
        case 'high':
          return l10n.qualityHigh;
        case 'xhigh':
          return l10n.qualityXhigh;
        case 'max':
          return l10n.qualityMax;
      }
    }
    return value;
  }
}
