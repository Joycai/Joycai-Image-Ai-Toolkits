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
    this.standaloneLastFrame = false,
    this.frameRatioAdaptive = false,
    this.requiredPromptMaxCharacters,
  });

  final int? referenceMaxSeconds;
  final String? referenceMaxResolution;
  final bool lastFrame;
  final bool exclusiveFrames;
  final int? groupLimit;
  final bool subjectReferences;
  final bool referenceAudioVideo;
  final bool standaloneLastFrame;
  final bool frameRatioAdaptive;
  final int? requiredPromptMaxCharacters;

  static const standard = GenerationProtocolContract();
  static const declarations = <WireProtocol, GenerationProtocolContract>{
    WireProtocol.xaiVideos: GenerationProtocolContract(lastFrame: false, exclusiveFrames: true),
    WireProtocol.openaiVideos: GenerationProtocolContract(lastFrame: false),
    WireProtocol.minimaxVideo: GenerationProtocolContract(
      exclusiveFrames: true,
      referenceAudioVideo: true,
      standaloneLastFrame: true,
      frameRatioAdaptive: true,
      requiredPromptMaxCharacters: 7000,
    ),
    WireProtocol.minimaxH3BaseVideo: GenerationProtocolContract(exclusiveFrames: true),
    WireProtocol.arkImages: GenerationProtocolContract(groupLimit: 15),
    WireProtocol.minimaxImages: GenerationProtocolContract(subjectReferences: true),
  };

  static GenerationProtocolContract forWire(WireProtocol? wire) => declarations[wire] ?? standard;
}
