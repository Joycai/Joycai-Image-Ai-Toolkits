import '../llm_types.dart';
import 'protocol.dart';

/// Pure request/response helpers for MiniMax's native surfaces.
///
/// IO-free on purpose: the repo has no HTTP mock setup, so the only way these
/// rules get pinned by tests is to keep them out of the protocol's request
/// path. `dashscope_payload.dart` and `gemini_payload.dart` are the same
/// arrangement.
///
/// The wire facts these encode are recorded in `docs/api/minimax.md`.

// ---------------------------------------------------------------------------
// Base-URL derivation — one channel, one key, every face
// ---------------------------------------------------------------------------

/// Every path suffix a MiniMax channel may have been configured with, longest
/// first so `/anthropic/v1` is never mistaken for a bare `/v1`.
const List<String> _minimaxFaceSuffixes = [
  '/anthropic/v1',
  '/anthropic',
  '/v1',
  '/v2',
];

/// The bare host base with any known MiniMax face suffix stripped.
String _minimaxHostBase(String endpoint) {
  var base = trimBaseUrl(endpoint);
  for (final suffix in _minimaxFaceSuffixes) {
    if (base.endsWith(suffix)) {
      base = trimBaseUrl(base.substring(0, base.length - suffix.length));
      break;
    }
  }
  return base;
}

/// The OpenAI-compatible base a channel's endpoint implies (`…/v1`, serving
/// `POST /chat/completions`).
///
/// A MiniMax channel is stored with whichever face its chat leads with — `/v1`
/// for the ① variant, `/anthropic/v1` for the ④ one. Deriving each face from
/// the other is what lets one channel — one stored key — reach chat, images
/// and video, instead of asking for the same account to be registered twice.
///
/// Idempotent by construction: an endpoint that is already `/v1`, or one on
/// another face, or a bare host, or any of those with trailing slashes, all
/// resolve to the same base.
String minimaxOpenAIBase(String endpoint) {
  final base = _minimaxHostBase(endpoint);
  return '$base/v1';
}

/// The Anthropic-compatible base a channel's endpoint implies
/// (`…/anthropic/v1`, serving `POST /messages`). Same contract as
/// [minimaxOpenAIBase].
String minimaxAnthropicBase(String endpoint) {
  final base = _minimaxHostBase(endpoint);
  return '$base/anthropic/v1';
}

/// The base the **v2 video surface** lives on (`…/v2`).
///
/// Video is the one surface MiniMax versioned separately: `/v2/video_generation`
/// and `/v2/query/video_generation/*` sit beside the `/v1` everything else uses.
/// Same contract as [minimaxOpenAIBase].
String minimaxV2Base(String endpoint) {
  final base = _minimaxHostBase(endpoint);
  return '$base/v2';
}

// ---------------------------------------------------------------------------
// Images — POST /v1/image_generation
// ---------------------------------------------------------------------------

/// Whether the caller asked for MiniMax's server-side prompt rewrite, or null
/// to leave the field off and inherit the upstream default (off).
///
/// Shares the `promptExtend` option key with DashScope: the two vendors spell
/// the field differently on the wire (`prompt_optimizer` vs `prompt_extend`)
/// but it is one control to the user, so it is one option and one label.
bool? minimaxPromptOptimizer(Map<String, dynamic>? options) {
  switch (readStringOption(options, 'promptExtend')) {
    case 'on':
      return true;
    case 'off':
      return false;
    default:
      return null;
  }
}

/// The request body for one image generation.
///
/// [subjectRefs] are reference images already resolved to something the
/// endpoint accepts — a public URL or a `data:<mime>;base64,…` string. Empty
/// means text-to-image; non-empty makes this a **subject reference** request,
/// which is the only image-conditioned mode this surface has (see
/// [minimaxSubjectReferenceNote]).
///
/// `n` is never sent. 1 is the upstream default, the app's image tasks each
/// produce one deliverable, and the field only costs a 400 when a model turns
/// out not to accept the count — the same reasoning that keeps it off the
/// DashScope and xAI bodies.
Map<String, dynamic> buildMiniMaxImagePayload({
  required String modelId,
  required String prompt,
  required List<String> subjectRefs,
  Map<String, dynamic>? options,
}) {
  final aspect = readStringOption(options, 'aspectRatio');
  final optimizer = minimaxPromptOptimizer(options);

  return {
    'model': modelId,
    'prompt': prompt,
    // The upstream default already, but sent explicitly so the parse below
    // never has to guess which of the two result fields it is reading.
    'response_format': 'url',
    if (aspect != null && aspect != 'not_set') 'aspect_ratio': aspect,
    'prompt_optimizer': ?optimizer,
    if (subjectRefs.isNotEmpty)
      'subject_reference': [
        // `character` is the only documented type: the reference is read as a
        // person to keep consistent, not as a canvas to edit.
        for (final ref in subjectRefs) {'type': 'character', 'image_file': ref},
      ],
  };
}

/// What `subject_reference` actually does, for the log line that warns about it.
///
/// MiniMax's "image-to-image" is not editing. The reference is a single
/// front-facing portrait whose *subject* is carried into a newly generated
/// scene; the endpoint has no field that means "modify this picture". A
/// workbench request that attaches a landscape and asks for a colour change
/// will succeed and return something unrelated, so the mismatch is worth a
/// warning rather than a silent pass.
const String minimaxSubjectReferenceNote =
    'MiniMax reference images are subject references (a character portrait '
    'carried into a new image), not an edit of the source picture.';

/// Every image reference a `/v1/image_generation` response carries, in
/// declaration order.
///
/// Both result fields are read even though the request pins
/// `response_format: url`: a relay fronting this surface may answer in the
/// other spelling, and reading only the requested one turns that into "the
/// API returned no image" with the bytes sitting in the body.
List<String> minimaxImageRefs(Map<String, dynamic> data) {
  final refs = <String>[];
  final payload = data['data'];
  if (payload is! Map) return refs;

  // First populated field wins rather than both being concatenated: a relay
  // that mirrors the same images into *both* spellings would otherwise be
  // read as twice as many results, and the image task would write duplicate
  // files for one generation.
  for (final key in const ['image_urls', 'image_base64']) {
    final list = payload[key];
    if (list is! List) continue;
    for (final entry in list) {
      if (entry is String && entry.isNotEmpty) refs.add(entry);
    }
    if (refs.isNotEmpty) return refs;
  }
  return refs;
}

/// One `metadata` counter, whichever way it was spelled.
///
/// MiniMax documents these as integers and **sends them as strings**
/// (`"success_count": "3"`), so a plain `is num` test never matches anything
/// the live endpoint returns. Both spellings are accepted rather than the
/// documented one alone, because relays fronting this surface re-serialize
/// the body and may hand back either.
int? _minimaxCount(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// Throws when a `metadata` block reports that every requested image failed.
///
/// `base_resp.status_code` covers the request-level failures and is checked by
/// [throwIfEnvelopeError] already. This is the *per-image* one: a 200 with
/// `status_code: 0` can still carry `success_count: 0`, and without this the
/// only symptom is an empty result list.
void throwIfMiniMaxImagesFailed(Map<String, dynamic> data) {
  final metadata = data['metadata'];
  if (metadata is! Map) return;
  final success = _minimaxCount(metadata['success_count']);
  final failed = _minimaxCount(metadata['failed_count']);
  if (success == 0 && failed != null && failed > 0) {
    throw LLMApiException(
        'MiniMax Images API generated no image ($failed failed). This is '
        'usually content moderation — the request itself succeeded.',
        isEnvelope: true);
  }
}

// ---------------------------------------------------------------------------
// Video — POST /v2/video_generation
// ---------------------------------------------------------------------------

/// The `role` a video reference carries in the `content[]` array.
///
/// MiniMax has no per-role fields: first frame, last frame and reference
/// material are all `content` items distinguished by this tag, which is why
/// the mutual-exclusion rule below is a client-side check rather than
/// something the body shape prevents.
enum MiniMaxVideoRole {
  firstFrame('first_frame', 'image_url'),
  lastFrame('last_frame', 'image_url'),
  referenceImage('reference_image', 'image_url');

  final String role;
  final String type;
  const MiniMaxVideoRole(this.role, this.type);

  /// Whether this role belongs to the *image-based* modality (first/last
  /// frame) rather than the *reference* one. Upstream rejects a request that
  /// mixes the two.
  ///
  /// Spelled as a positive list rather than "not a reference image": MiniMax
  /// documents five roles and this enum implements three, so an exclusion
  /// test would silently classify a future `reference_video` /
  /// `reference_audio` as a frame and invert the rule this predicate exists
  /// to enforce. A new role now defaults to the reference side, which is the
  /// safe one.
  bool get isFrame =>
      this == MiniMaxVideoRole.firstFrame ||
      this == MiniMaxVideoRole.lastFrame;
}

/// One resolved media item for [buildMiniMaxVideoPayload].
class MiniMaxVideoMedia {
  final MiniMaxVideoRole role;

  /// A public URL, an `mm_file://{file_id}`, or a `data:<mime>;base64,…`.
  final String url;

  const MiniMaxVideoMedia(this.role, this.url);
}

/// MiniMax's spelling of the shared `resolution` option: `768P` or `2K`.
///
/// Required upstream with no server-side default, so this never returns null —
/// a missing or unrecognized option resolves to `768P`, the cheaper tier.
String minimaxVideoResolution(Map<String, dynamic>? options) {
  final raw = readStringOption(options, 'resolution')?.toLowerCase() ?? '';
  return raw.contains('2k') ? '2K' : '768P';
}

/// MiniMax's `duration`, clamped into the documented 4–15 s window.
///
/// Also required with no server-side default, hence the 5 s fallback rather
/// than a null that would 400.
int minimaxVideoDuration(Map<String, dynamic>? options) {
  final seconds = int.tryParse(resolveVideoSeconds(options) ?? '');
  return (seconds ?? 5).clamp(4, 15);
}

/// The request body for one video generation task.
///
/// [media] must already be filtered for the image-based/reference mutual
/// exclusion — see [partitionMiniMaxVideoMedia], which is where that rule
/// lives so it can be tested without encoding an image.
Map<String, dynamic> buildMiniMaxVideoPayload({
  required String modelId,
  required String prompt,
  required List<MiniMaxVideoMedia> media,
  Map<String, dynamic>? options,
}) {
  final aspect = readStringOption(options, 'aspectRatio');
  // `adaptive` means "take the ratio from the input media", so a text-only
  // request has nothing to adapt to and upstream demands an explicit value.
  // Substituting the most common landscape ratio beats a 400 the user can
  // only fix by discovering the coupling themselves.
  final ratio = (aspect == null || aspect == 'not_set' || aspect == 'adaptive')
      ? (media.isEmpty ? '16:9' : 'adaptive')
      : aspect;

  return {
    'model': modelId,
    'content': [
      // Exactly one text item is mandatory and it must be present even for a
      // pure image-to-video request — an empty prompt is still a text item.
      {'type': 'text', 'text': prompt},
      for (final item in media)
        {
          'type': item.role.type,
          // The URL is nested inside a per-type object, not a flat `url`
          // sibling: `{"type": "image_url", "image_url": {"url": …}}`. A flat
          // spelling is accepted by the parser and then carries no image —
          // the request succeeds and generates as though nothing was
          // attached, which is billed and leaves nothing in the log.
          //
          // Verified live 2026-08-29 with a first-frame + last-frame request
          // that honored both frames. Worth restating because of that silent
          // failure mode: a green run of this line is not an HTTP 200, it is
          // output that obeyed the images.
          item.role.type: {'url': item.url},
          // `role`, by contrast, really is a sibling of `type`.
          'role': item.role.role,
        },
    ],
    'resolution': minimaxVideoResolution(options),
    'duration': minimaxVideoDuration(options),
    'ratio': ratio,
  };
}

/// Split [media] into the items that will be sent and the ones dropped by
/// MiniMax's image-based/reference mutual exclusion.
///
/// The frames win when both are present: a first/last frame is a precise
/// instruction the user placed deliberately, while reference images are
/// supplementary. Returns the kept items first.
(List<MiniMaxVideoMedia> kept, List<MiniMaxVideoMedia> dropped)
    partitionMiniMaxVideoMedia(List<MiniMaxVideoMedia> media) {
  final hasFrame = media.any((m) => m.role.isFrame);
  if (!hasFrame) return (media, const []);
  return (
    media.where((m) => m.role.isFrame).toList(),
    media.where((m) => !m.role.isFrame).toList(),
  );
}

/// The payload with base64 media replaced by a placeholder — a base64 image
/// is megabytes of noise in a debug log that exists to be read.
Map<String, dynamic> minimaxPayloadForLog(Map<String, dynamic> payload) {
  final content = payload['content'];
  if (content is! List) return payload;
  return {
    ...payload,
    'content': [for (final item in content) _mediaItemForLog(item)],
  };
}

/// One `content[]` item with its inline base64 replaced.
///
/// Follows `type` to find the media object, because the URL lives inside it
/// (`image_url: {url: …}`) rather than as a flat sibling. Matching on a flat
/// `url` looked like it worked while the payload builder emitted one and
/// would have gone silently inert the moment that was corrected — dumping a
/// 30 MB first frame into the log this function exists to keep readable.
Object? _mediaItemForLog(Object? item) {
  if (item is! Map) return item;
  final type = item['type'];
  if (type is! String) return item;
  final media = item[type];
  if (media is! Map) return item;
  final url = media['url'];
  if (url is! String || !url.startsWith('data:')) return item;
  return {
    ...item,
    type: {'url': '[base64 $type]'},
  };
}
