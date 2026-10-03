import '../model_capabilities.dart';
import '../vendors/vendor_profile.dart';

/// Explicit compatibility vocabulary for native alias profiles. Names are
/// stable persistence IDs, not model-ID heuristics. Chat dialects keep their
/// conservative existing descriptor until they have a declared alias contract.
class GenerationProfiles {
  static const byWire = <WireProtocol, List<String>>{
    WireProtocol.openaiImages: ['openaiImage', 'openaiImage2', 'openaiImage25'],
    WireProtocol.xaiImages: ['xaiImage', 'xaiImageLegacy'],
    WireProtocol.geminiImagen: ['imagen'],
    WireProtocol.geminiVeo: ['veoVideo'],
    WireProtocol.openaiVideos: ['openaiVideo'],
    WireProtocol.xaiVideos: ['grokImagineVideo'],
    WireProtocol.dashscopeImagesSync: [
      'dashscopeImageFallback',
      'dashscopeQwenImage',
      'dashscopeQwenImageFixed',
      'dashscopeQwenImageEdit',
      'dashscopeQwenImageEditMaxPlus',
      'dashscopeWanImage',
      'dashscopeWanImagePro',
    ],
    WireProtocol.dashscopeImagesAsync: ['dashscopeWanImage', 'dashscopeWanImagePro'],
    WireProtocol.dashscopeVideo: ['dashscopeWanVideo'],
    WireProtocol.minimaxImages: ['minimaxImage'],
    WireProtocol.minimaxVideo: ['minimaxVideo'],
    WireProtocol.minimaxH3BaseVideo: ['minimaxH3Base'],
    WireProtocol.arkImages: [
      'seedreamGeneric',
      'seedream30',
      'seedream40',
      'seedream45',
      'seedream50Lite',
      'seedream50Pro',
    ],
    WireProtocol.midjourney: ['midjourney'],
  };

  static List<String> compatible(WireProtocol? wire) => byWire[wire] ?? const [];

  static ModelCapabilities? resolve(String? profile, WireProtocol? wire) {
    if (profile == null) return null;
    if (!compatible(wire).contains(profile)) {
      throw ArgumentError.value(profile, 'generationProfile', 'Incompatible with ${wire?.id}');
    }
    return ModelCapabilities.profiles[profile]!;
  }
}
