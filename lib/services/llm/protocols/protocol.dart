import 'dart:io';
import 'dart:typed_data';

import '../llm_types.dart';
import '../model_descriptor.dart';
import '../vendors/vendor_profile.dart';

/// **Layer 1 — the protocol.**
///
/// A protocol is one *wire format*: an endpoint shape, a request payload, a
/// response/stream parsing rule. Protocols are stateless and vendor-agnostic —
/// the only vendor input they take is authentication ([VendorProfile.headers] /
/// [VendorProfile.decorateUrl]) and the only model input is the resolved
/// [ModelDescriptor]. A protocol must never branch on a vendor id and never
/// sniff a model id.
///
/// The dispatcher (`llm_dispatcher.dart`) composes the three layers: it picks
/// the protocol from `vendor.family` + `model.family` and hands the protocol a
/// fully-resolved [LLMTarget].

/// Everything a protocol needs to execute one request: the channel config
/// (endpoint, key, proxy), the vendor profile (auth) and the model descriptor
/// (capabilities, extension flags).
class LLMTarget {
  final LLMModelConfig config;
  final VendorProfile vendor;
  final ModelDescriptor model;

  const LLMTarget({
    required this.config,
    required this.vendor,
    required this.model,
  });

  Map<String, String> headers() =>
      vendor.headers(config.apiKey, config.endpoint);

  Uri decorateUrl(Uri url) => vendor.decorateUrl(url, config.apiKey);
}

typedef LLMLogger = Function(String, {String level});

/// Synchronous + streaming conversation surface.
abstract class ChatProtocol {
  Future<LLMResponse> generate(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    LLMLogger? logger,
  });

  Stream<LLMResponseChunk> generateStream(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  });
}

/// Single-shot image generation/editing surface (no streaming).
abstract class ImageGenProtocol {
  Future<LLMResponse> generateImage(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  });
}

/// Asynchronous job surface: submit returns an operation id, poll reports
/// status. Poll results use the Veo-shaped envelope
/// (`{done, response: {generateVideoResponse: ...}}`) the task executor
/// already speaks, regardless of the upstream's native format.
abstract class VideoJobProtocol {
  Future<String> submit(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  });

  Future<Map<String, dynamic>> poll(
    LLMTarget target,
    String operationName, {
    LLMLogger? logger,
  });
}

/// A model surfaced by a [DiscoveryProtocol] listing.
class DiscoveredModel {
  final String modelId;
  final String displayName;
  final String description;
  final Map<String, dynamic> rawData;

  DiscoveredModel({
    required this.modelId,
    required this.displayName,
    this.description = '',
    required this.rawData,
  });
}

/// Model listing surface.
abstract class DiscoveryProtocol {
  Future<List<DiscoveredModel>> fetchModels(LLMTarget target);
}

// ---------------------------------------------------------------------------
// Shared wire-level helpers
// ---------------------------------------------------------------------------

/// [endpoint] without any trailing slashes.
String trimBaseUrl(String endpoint) {
  var base = endpoint.trim();
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  return base;
}

Future<Uint8List?> readAttachmentBytes(LLMAttachment att) async {
  if (att.path != null) return File(att.path!).readAsBytes();
  if (att.bytes != null) return att.bytes;
  return null;
}

String extForMime(String mime) {
  if (mime.contains('png')) return 'png';
  if (mime.contains('webp')) return 'webp';
  return 'jpg';
}

String? readStringOption(Map<String, dynamic>? options, String key) {
  final v = options?[key];
  if (v is String && v.isNotEmpty) return v;
  return null;
}

/// Map the per-model aspectRatio + resolution options onto a `WxH` size
/// string shared by the Sora-style and xAI video surfaces. Falls back to the
/// upstream default if neither is set.
///
/// Three-tier resolution ladder (480p / 720p / 1080p, defaulting to 720p for
/// anything unrecognized — e.g. the legacy Veo "4k" option) crossed with the
/// aspect ratios exposed across families.
String? resolveVideoSize(Map<String, dynamic>? options) {
  if (options == null) return null;

  // Explicit WxH wins.
  final explicit = options['size'];
  if (explicit is String && RegExp(r'^\d+x\d+$').hasMatch(explicit)) {
    return explicit;
  }

  final aspect = options['aspectRatio']?.toString();
  final resolution = options['resolution']?.toString() ?? '720p';

  final tier = resolution.contains('1080')
      ? '1080'
      : resolution.contains('480')
          ? '480'
          : '720';

  const sizes = {
    '16:9': {'480': '854x480', '720': '1280x720', '1080': '1920x1080'},
    '9:16': {'480': '480x854', '720': '720x1280', '1080': '1080x1920'},
    '1:1': {'480': '480x480', '720': '720x720', '1080': '1080x1080'},
    '4:3': {'480': '640x480', '720': '960x720', '1080': '1440x1080'},
    '3:4': {'480': '480x640', '720': '720x960', '1080': '1080x1440'},
    '3:2': {'480': '720x480', '720': '1080x720', '1080': '1620x1080'},
    '2:3': {'480': '480x720', '720': '720x1080', '1080': '1080x1620'},
  };

  return sizes[aspect]?[tier];
}

String? resolveVideoSeconds(Map<String, dynamic>? options) {
  final s = options?['seconds'];
  if (s == null) return null;
  return s.toString();
}
