import '../vendors/vendor_profile.dart';

/// Input restrictions of a wire surface. This declaration never selects a
/// route; the dispatcher supplies the effective wire to schema composition.
class GenerationProtocolContract {
  const GenerationProtocolContract({
    this.lastFrame = true,
    this.exclusiveFrames = false,
    this.groupLimit,
    this.subjectReferences = false,
  });

  final bool lastFrame;
  final bool exclusiveFrames;
  final int? groupLimit;
  final bool subjectReferences;

  static const standard = GenerationProtocolContract();
  static const declarations = <WireProtocol, GenerationProtocolContract>{
    WireProtocol.xaiVideos: GenerationProtocolContract(lastFrame: false, exclusiveFrames: true),
    WireProtocol.openaiVideos: GenerationProtocolContract(lastFrame: false),
    WireProtocol.minimaxVideo: GenerationProtocolContract(exclusiveFrames: true),
    WireProtocol.minimaxH3BaseVideo: GenerationProtocolContract(exclusiveFrames: true),
    WireProtocol.arkImages: GenerationProtocolContract(groupLimit: 15),
    WireProtocol.minimaxImages: GenerationProtocolContract(subjectReferences: true),
  };

  static GenerationProtocolContract forWire(WireProtocol? wire) => declarations[wire] ?? standard;
}
