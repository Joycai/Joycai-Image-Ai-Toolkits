import '../../../models/image_layer.dart';
import '../llm_types.dart';
import '../output_spec.dart' show billedImageCountKey;
import 'protocol.dart' show sentInputImages;

/// Pure request/response helpers for Volcengine Ark's image surface
/// (`POST {base}/images/generations`, Seedream).
///
/// IO-free on purpose, like `minimax_payload.dart` and `dashscope_payload.dart`:
/// every rule here is pinned case by case without a server
/// (`ark_images_payload_test.dart`); the transport around them is driven
/// against a loopback one (`ark_images_protocol_test.dart`). The wire facts
/// they encode are recorded in `docs/api/volcengine-ark.md`.
///
/// The inputs are the workbench's option keys (`imageSize`, `aspectRatio`,
/// `maxImages`, `imageTask`, …), which a model's table only declares where the
/// model accepts them (layer 3). This file never asks which model it is
/// building for: the one model-shaped fact it needs, the tier → ratio → pixels
/// map, arrives as data.

/// The most images one request may involve, references included.
const int arkMaxImagesPerRequest = 15;

/// Seedream 5.0 pro's task modes, spelled as the workbench's `imageTask`
/// option values.
const String arkTaskGenerate = 'generate';
const String arkTaskLayers = 'layers';
const String arkTaskTransparent = 'transparent';

/// Values meaning "leave it to the model".
bool _unset(String? v) => v == null || v.isEmpty || v == 'not_set' || v == 'auto';

String? _opt(Map<String, dynamic>? options, String key) {
  final v = options?[key];
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// The request body for one Ark image generation.
///
/// [imageRefs] are the reference images already encoded (`data:` URLs), in
/// the order the prompt refers to them (「图1」「图2」…). [tierPixelSizes] is
/// the model's documented mapping (`ModelCapabilities.tierPixelSizes`).
/// [warn] receives one sentence per request the builder had to change — a
/// group ceiling tightened, a JPEG request turned PNG — so the change is
/// logged rather than silent.
///
/// [stream] asks for the SSE form (docs/api/volcengine-ark.md §5): one event
/// per image as it is drawn. Only for a model and route that serve it — the
/// caller decides; 5.0 pro answers the field with a 400.
///
/// Throws [LLMApiException] (no status: never retried, nothing was sent) when
/// a task mode's precondition fails, because upstream would reject the
/// request anyway — and bill nothing, but only after a round trip that for
/// this surface can queue for a minute.
Map<String, dynamic> buildArkImagePayload({
  required String modelId,
  required String prompt,
  required List<String> imageRefs,
  Map<String, Map<String, String>> tierPixelSizes = const {},
  Map<String, dynamic>? options,
  void Function(String message)? warn,
  bool stream = false,
}) {
  final task = _opt(options, 'imageTask') ?? arkTaskGenerate;
  final body = <String, dynamic>{'model': modelId};

  final trimmed = prompt.trim();
  // Layer decomposition takes an optional prompt — none means "split every
  // main element" — so an empty one is left off rather than sent blank.
  if (trimmed.isNotEmpty) body['prompt'] = trimmed;

  if (imageRefs.length == 1) {
    body['image'] = imageRefs.first;
  } else if (imageRefs.length > 1) {
    body['image'] = List<String>.of(imageRefs);
  }

  final tier = _opt(options, 'imageSize');
  final ratio = _opt(options, 'aspectRatio');

  switch (task) {
    case arkTaskLayers:
      _requireSingleReference(imageRefs, 'Layer decomposition');
      body['layer_decomposition'] = true;
      // Tiers only here (1K / 1.5K / 2K / auto): the base keeps the source's
      // aspect ratio, so a chosen ratio has nothing to act on.
      if (!_unset(tier)) body['size'] = tier;
    case arkTaskTransparent:
      _requireSingleReference(imageRefs, 'Transparent-layer editing');
      body['background'] = 'transparent';
      final size = _arkSize(tier, ratio, tierPixelSizes, warn);
      if (size != null) body['size'] = size;
    default:
      final size = _arkSize(tier, ratio, tierPixelSizes, warn);
      if (size != null) body['size'] = size;
      _applyGroup(body, options, imageRefs.length, warn);
  }

  final format = _opt(options, 'outputFormat')?.toLowerCase();
  if (task == arkTaskTransparent) {
    // A transparent result is PNG by definition; asking for JPEG beside
    // `background: transparent` is a documented 400.
    if (format != null && format != 'png') {
      warn?.call('Transparent-layer editing always outputs PNG; '
          'sending output_format png instead of $format.');
    }
    body['output_format'] = 'png';
  } else if (format == 'png' || format == 'jpeg') {
    body['output_format'] = format;
  }

  final mode = _opt(options, 'optimizeMode');
  if (mode == 'fast' || mode == 'standard') {
    body['optimize_prompt_options'] = {'mode': mode};
  }

  if (_opt(options, 'webSearch') == 'on') {
    body['tools'] = [
      {'type': 'web_search'},
    ];
  }

  // Upstream's default is *on*, and a watermarked image is billed the same.
  // Always explicit, off unless the author asked (docs/api/volcengine-ark.md
  // §2).
  body['watermark'] = _opt(options, 'watermark') == 'on';

  // A link, not inline base64: a group of 4K PNGs inlined would be a response
  // body in the hundreds of megabytes. The links live 24 h; results are
  // downloaded before the request returns.
  body['response_format'] = 'url';
  if (stream) body['stream'] = true;
  return body;
}

void _requireSingleReference(List<String> refs, String mode) {
  if (refs.length == 1) return;
  throw LLMApiException(
      '$mode needs exactly one reference image; this request has '
      '${refs.length}. Nothing was sent.');
}

/// The `size` field: the tier alone when no ratio is chosen (the model reads
/// the ratio off the prompt), the documented pixels for (tier, ratio)
/// otherwise. A ratio with no tier looks the pixels up under the model's
/// first tier, which the tables list as upstream's default
/// (`ModelCapabilities.tierPixelSizes`) — and which is the only one for a
/// version that has no tier control.
String? _arkSize(String? tier, String? ratio,
    Map<String, Map<String, String>> tierPixelSizes,
    void Function(String message)? warn) {
  final hasTier = !_unset(tier);
  if (_unset(ratio)) return hasTier ? tier : null;
  final key = hasTier ? tier! : tierPixelSizes.keys.firstOrNull;
  final pixels = key == null ? null : tierPixelSizes[key]?[ratio];
  if (pixels != null) return pixels;
  warn?.call('No documented size for aspect ratio $ratio at '
      '${key ?? 'the default tier'}; letting the model choose the ratio.');
  return hasTier ? tier : null;
}

/// Group generation: `maxImages` of 1 (or none) sends nothing; more turns it
/// on with that ceiling, tightened so references plus results stay within
/// [arkMaxImagesPerRequest].
void _applyGroup(Map<String, dynamic> body, Map<String, dynamic>? options,
    int referenceCount, void Function(String message)? warn) {
  final asked = int.tryParse(_opt(options, 'maxImages') ?? '') ?? 1;
  if (asked <= 1) return;
  final room = arkMaxImagesPerRequest - referenceCount;
  final ceiling = asked > room ? room : asked;
  if (ceiling < asked) {
    warn?.call('Group generation is capped at $arkMaxImagesPerRequest images '
        'including references; $referenceCount reference(s) leave room for '
        '$ceiling, not $asked.');
  }
  if (ceiling <= 1) return;
  body['sequential_image_generation'] = 'auto';
  body['sequential_image_generation_options'] = {'max_images': ceiling};
}

/// One generated image as the response describes it.
class ArkImageItem {
  /// A download link (`response_format: url`) or inline base64.
  final String ref;

  /// Stacking order in a layer decomposition — 0 for the base, 1+ for the
  /// layers — or null outside that mode.
  final int? zIndex;

  /// A decomposed layer's name, as the model labelled it.
  final String? name;

  /// The model's one-line description of a decomposed layer.
  final String? description;

  /// `bounding_box.absolute` — where a layer sits on the base, in the base
  /// image's pixels. Null for the base and outside that mode.
  final LayerBox? box;

  const ArkImageItem(this.ref,
      {this.zIndex, this.name, this.description, this.box});

  /// This image's place in a decomposition, or null outside that mode.
  GeneratedImageLayer? get layer => zIndex == null
      ? null
      : GeneratedImageLayer(
          zIndex: zIndex!, name: name, description: description, box: box);
}

/// One `data[]` item (or a stream's `partial_succeeded` event) that carries
/// an image → the item, or null when it has neither a link nor base64.
ArkImageItem? _imageItemFrom(Map item) {
  final url = item['url'];
  final b64 = item['b64_json'];
  final ref = url is String && url.isNotEmpty
      ? url
      : (b64 is String && b64.isNotEmpty ? b64 : null);
  if (ref == null) return null;
  final z = item['z_index'];
  final bbox = item['bounding_box'];
  return ArkImageItem(ref,
      zIndex: z is num ? z.toInt() : null,
      name: _nonEmpty(item['name']),
      description: _nonEmpty(item['description']),
      box: bbox is Map ? LayerBox.fromList(bbox['absolute']) : null);
}

String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;

/// One image of a group that failed while the rest of the request succeeded.
class ArkImageFailure {
  final String code;
  final String message;
  const ArkImageFailure(this.code, this.message);

  @override
  String toString() => code.isEmpty ? message : '$code: $message';
}

/// A decoded Ark image response.
class ArkImageResult {
  /// Successful images in delivery order — for a layer decomposition, base
  /// first and then by stacking order.
  final List<ArkImageItem> images;

  /// The items of `data[]` that carried an `error` instead of an image.
  final List<ArkImageFailure> failures;

  /// `usage` verbatim, or empty.
  final Map<String, dynamic> usage;

  const ArkImageResult(this.images, this.failures, this.usage);
}

/// Reads `data[]` and `usage` off a successful (2xx, no top-level `error`)
/// response. Tolerant of shape: an item with neither a link, base64 nor an
/// error is skipped rather than failing the images that did arrive.
ArkImageResult parseArkImageResponse(Map<String, dynamic> body) {
  final raw = body['data'];
  final items = raw is List ? raw : const [];
  final images = <ArkImageItem>[];
  final failures = <ArkImageFailure>[];
  for (final item in items) {
    if (item is! Map) continue;
    final err = item['error'];
    if (err is Map) {
      failures.add(ArkImageFailure(
          '${err['code'] ?? ''}', '${err['message'] ?? 'unknown error'}'));
      continue;
    }
    final image = _imageItemFrom(item);
    if (image != null) images.add(image);
  }
  // A decomposition answers base + layers; the stacking order is the one
  // that means something on disk (base first, then bottom to top). Stable
  // sort, so ordinary results keep their delivery order.
  if (images.any((i) => i.zIndex != null)) {
    final indexed = images.indexed.toList()
      ..sort((a, b) {
        final byZ = (a.$2.zIndex ?? 1 << 20).compareTo(b.$2.zIndex ?? 1 << 20);
        return byZ != 0 ? byZ : a.$1.compareTo(b.$1);
      });
    images
      ..clear()
      ..addAll(indexed.map((e) => e.$2));
  }
  final usage = body['usage'];
  return ArkImageResult(images, failures,
      usage is Map ? usage.cast<String, dynamic>() : const {});
}

/// The response metadata for one Ark request that delivered [delivered]
/// pictures, [failed] items of a group having come back as errors.
///
/// Ark bills Seedream per image. Its `output_tokens` (pixels / 256) is
/// informational, and publishing it under a token key would let a
/// token-priced fee group invent a cost, so the raw block is kept under its
/// own name. `image_count` keeps the metadata non-empty, which is what makes
/// LLMService record the usage row at all.
///
/// Two of Ark's own counts outrank what this client saw:
///  * `usage.generated_images` — the pictures Ark *charged* for
///    (docs/api/volcengine-ark.md §4), published as [billedImageCountKey].
///    A link that fails to download was drawn and billed all the same; the
///    delivered count alone recorded it as free.
///  * `usage.input_images` — 5.0 pro's count of references, the free first
///    one included (measured 2026-09-21), over [refCount], what this client
///    put in the body; 5.0 lite and 4.x report no such field and fall back
///    to it.
Map<String, dynamic> arkResultMetadata({
  required int delivered,
  required int failed,
  required Map<String, dynamic> usage,
  required int refCount,
}) {
  final billed = usage['generated_images'];
  return {
    'image_count': delivered,
    if (failed > 0) 'failed_images': failed,
    if (usage.isNotEmpty) 'ark_usage': usage,
    if (billed is num && billed.isFinite && billed > 0)
      billedImageCountKey: billed.toInt(),
    ...sentInputImages(refCount, reported: usage['input_images']),
  };
}

/// One decoded event of a streamed Ark image response
/// (docs/api/volcengine-ark.md §5).
sealed class ArkStreamEvent {
  const ArkStreamEvent();
}

/// `image_generation.partial_succeeded`: one image, finished.
class ArkStreamImage extends ArkStreamEvent {
  final ArkImageItem item;

  /// `image_index`, 0-based across the request, or null when absent.
  final int? index;
  const ArkStreamImage(this.item, this.index);
}

/// `image_generation.partial_failed`: one image of the group did not make it
/// (typically moderation); the rest keep coming.
class ArkStreamFailure extends ArkStreamEvent {
  final ArkImageFailure failure;
  const ArkStreamFailure(this.failure);
}

/// `image_generation.completed`: the request is over; carries `usage`.
class ArkStreamCompleted extends ArkStreamEvent {
  final Map<String, dynamic> usage;
  const ArkStreamCompleted(this.usage);
}

/// Reads one SSE `data:` object. Null for an event this client does not
/// know (and for one it knows but that carries nothing usable) — skipped,
/// never fatal, so a new event type upstream cannot break the images that
/// do arrive. The `type` field is read rather than the `event:` line: the two
/// are identical on the wire, and the data object is self-contained.
///
/// `partial_failed` is written from the documentation, not a capture (it
/// could not be provoked on the plan): its error is read from an `error`
/// object when there is one, else from top-level `code` / `message`.
ArkStreamEvent? parseArkStreamEvent(Map<String, dynamic> data) {
  switch (data['type']) {
    case 'image_generation.partial_succeeded':
      final item = _imageItemFrom(data);
      if (item == null) return null;
      final index = data['image_index'];
      return ArkStreamImage(item, index is num ? index.toInt() : null);
    case 'image_generation.partial_failed':
      final err = data['error'];
      final source = err is Map ? err : data;
      return ArkStreamFailure(ArkImageFailure('${source['code'] ?? ''}',
          '${source['message'] ?? 'unknown error'}'));
    case 'image_generation.completed':
      final usage = data['usage'];
      return ArkStreamCompleted(
          usage is Map ? usage.cast<String, dynamic>() : const {});
    default:
      return null;
  }
}
