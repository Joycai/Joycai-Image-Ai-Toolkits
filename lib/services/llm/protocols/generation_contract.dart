import '../vendors/vendor_profile.dart';

/// Input restrictions of a wire surface. This declaration never selects a
/// route; the dispatcher supplies the effective wire to schema composition.
class GenerationProtocolContract {
  const GenerationProtocolContract({
    this.lastFrame = true,
    this.referenceMaxSeconds,
    this.referenceMaxResolution,
    this.exclusiveFrames = false,
    this.groupLimit,
    this.subjectReferences = false,
    this.referenceAudioVideo = false,
    this.referenceUpload = false,
    this.maxReferenceVideos = 0,
    this.maxReferenceAudios = 0,
    this.maxReferenceMedia = 0,
    this.minReferenceSeconds = 0,
    this.maxReferenceTotalSeconds = 0,
    this.standaloneLastFrame = false,
    this.frameRatioAdaptive = false,
    this.promptMaxCharacters,
    this.promptRequired = false,
    this.promptOptionalWithMedia = false,
  });

  final int? referenceMaxSeconds;
  final String? referenceMaxResolution;
  final bool lastFrame;
  final bool exclusiveFrames;
  final int? groupLimit;
  final bool subjectReferences;
  final bool referenceAudioVideo;
  final bool referenceUpload;
  final int maxReferenceVideos;
  final int maxReferenceAudios;
  final int maxReferenceMedia;
  final int minReferenceSeconds;
  final int maxReferenceTotalSeconds;
  final bool standaloneLastFrame;
  final bool frameRatioAdaptive;
  final int? promptMaxCharacters;
  final bool promptRequired;
  final bool promptOptionalWithMedia;

  static const standard = GenerationProtocolContract();
  static const declarations = <WireProtocol, GenerationProtocolContract>{
    WireProtocol.dashscopeVideo: GenerationProtocolContract(
      exclusiveFrames: true,
      referenceAudioVideo: true,
      referenceUpload: true,
      maxReferenceVideos: 5,
      maxReferenceAudios: 5,
      maxReferenceMedia: 20,
      minReferenceSeconds: 1,
      maxReferenceTotalSeconds: 15,
      promptMaxCharacters: 20000,
      promptRequired: true,
      promptOptionalWithMedia: true,
    ),
    WireProtocol.xaiVideos: GenerationProtocolContract(lastFrame: false, exclusiveFrames: true),
    WireProtocol.openaiVideos: GenerationProtocolContract(lastFrame: false),
    WireProtocol.minimaxVideo: GenerationProtocolContract(
      exclusiveFrames: true,
      referenceAudioVideo: true,
      maxReferenceVideos: 3,
      maxReferenceAudios: 3,
      maxReferenceMedia: 12,
      minReferenceSeconds: 2,
      maxReferenceTotalSeconds: 15,
      standaloneLastFrame: true,
      frameRatioAdaptive: true,
      promptMaxCharacters: 7000,
      promptRequired: true,
    ),
    WireProtocol.minimaxH3BaseVideo: GenerationProtocolContract(exclusiveFrames: true),
    WireProtocol.arkImages: GenerationProtocolContract(groupLimit: 15),
    WireProtocol.minimaxImages: GenerationProtocolContract(subjectReferences: true),
  };

  static GenerationProtocolContract forWire(WireProtocol? wire) => declarations[wire] ?? standard;
}
