import '../llm_types.dart';
import '../model_capabilities.dart';
import 'protocol.dart';

/// Pure request/response helpers for DashScope's native surfaces.
///
/// Everything here is IO-free on purpose: the repo has no HTTP mock setup, so
/// the only way these rules get pinned by tests is to keep them out of the
/// protocol's request path. `gemini_payload.dart` is the same arrangement.

/// The `/api/v1` base a channel's endpoint implies.
///
/// A DashScope channel is configured with the OpenAI-compatible endpoint
/// (`https://dashscope.aliyuncs.com/compatible-mode/v1`) because that is what
/// chat needs; image generation lives on the same host under `/api/v1`.
/// Deriving one from the other is what lets a single channel — a single
/// stored key — serve both, instead of asking the user to register the same
/// account twice.
///
/// Idempotent by construction: an endpoint that is already native, or a bare
/// host, or either with trailing slashes, all resolve to the same base. The
/// rule keys off the *path* only, so the international host works too.
String dashscopeNativeBase(String endpoint) {
  var base = _dashscopeHostBase(endpoint);
  return base.endsWith('/api/v1') ? base : '$base/api/v1';
}

/// The Anthropic-compatible base a channel's endpoint implies
/// (`…/apps/anthropic/v1`, serving `POST /messages`).
///
/// Same contract as [dashscopeNativeBase]: derived from the stored
/// compatible-mode endpoint so one channel serves the ④ face too, idempotent,
/// path-only (the international host works unchanged). Note the documented
/// SDK base is `…/apps/anthropic` *without* `/v1` — this returns the full
/// `/v1` base because the ④ protocol appends only `/messages`.
String dashscopeAnthropicBase(String endpoint) {
  var base = _dashscopeHostBase(endpoint);
  if (base.endsWith('/apps/anthropic/v1')) return base;
  if (base.endsWith('/apps/anthropic')) return '$base/v1';
  return '$base/apps/anthropic/v1';
}

/// The OpenAI-compatible base a channel's endpoint implies
/// (`…/compatible-mode/v1`).
///
/// The mirror image of [dashscopeNativeBase]: a channel configured natively
/// (`…/api/v1`) still needs the compatible face for the two things the native
/// one does not serve — the ① chat alternate, and model discovery, which
/// DashScope publishes only as `GET /compatible-mode/v1/models`. Same
/// contract: idempotent, path-only, so the international host works
/// unchanged.
String dashscopeCompatibleBase(String endpoint) {
  final base = _dashscopeHostBase(endpoint);
  return base.endsWith('/compatible-mode/v1')
      ? base
      : '$base/compatible-mode/v1';
}

/// The bare host base with any known DashScope face suffix stripped.
String _dashscopeHostBase(String endpoint) {
  var base = trimBaseUrl(endpoint);
  for (final suffix in const [
    '/compatible-mode/v1',
    '/compatible-mode',
    '/apps/anthropic/v1',
    '/apps/anthropic',
    '/api/v1',
  ]) {
    if (base.endsWith(suffix)) {
      base = trimBaseUrl(base.substring(0, base.length - suffix.length));
      break;
    }
  }
  return base;
}

/// The size string for this request, in DashScope's spelling, or null when
/// the upstream default should stand.
///
/// Two dialects meet here. The app stores sizes as `WxH` (every other family
/// spells them that way) while DashScope wants `W*H`; and `wan2.7-*` also
/// accepts the `1K` / `2K` presets, which carry no aspect information and so
/// are passed through untouched. Anything unrecognized returns null rather
/// than being forwarded — task options outlive the model they were chosen
/// for, and a stale `auto` from a previous OpenAI selection is a 400 here.
String? dashscopeSize(Map<String, dynamic>? options) {
  final raw = readStringOption(options, 'imageSize');
  if (raw == null || raw == 'not_set' || raw == 'auto') return null;

  final wxh = RegExp(r'^(\d+)[x*×](\d+)$').firstMatch(raw);
  if (wxh != null) return '${wxh.group(1)}*${wxh.group(2)}';

  final preset = raw.toUpperCase();
  if (preset == '1K' || preset == '2K' || preset == '4K') return preset;
  return null;
}

/// `prompt_extend` for this request, or null to leave the upstream default
/// (which is *on* — DashScope rewrites the prompt before generating).
bool? dashscopePromptExtend(Map<String, dynamic>? options) {
  switch (readStringOption(options, 'promptExtend')) {
    case 'on':
      return true;
    case 'off':
      return false;
    default:
      return null;
  }
}

/// The request body for one image generation or edit.
///
/// [imageRefs] are reference images already resolved to something the
/// endpoint accepts — a public URL or a `data:<mime>;base64,…` string. Empty
/// means text-to-image.
///
/// The two shapes differ in more than nesting, which is why this is a switch
/// and not a flag: `qwen-image*` carries the conversation under `input` and
/// leads with the images (the instruction reads as "…do this to them"), while
/// `wan2.7-*` puts `messages` at the top level and leads with the text.
/// [ImageRequestShape] is declared per model in layer 3 so neither this
/// function nor the protocol has to recognize a model id.
Map<String, dynamic> buildDashScopeImagePayload({
  required String modelId,
  required ImageRequestShape shape,
  required String prompt,
  required List<String> imageRefs,
  Map<String, dynamic>? options,
}) {
  final size = dashscopeSize(options);
  final promptExtend = dashscopePromptExtend(options);
  final parameters = <String, dynamic>{
    'size': ?size,
    'prompt_extend': ?promptExtend,
  };

  // `n` is never sent: 1 is the upstream default everywhere, and the ceiling
  // differs within a single family (`qwen-image-edit` accepts only 1 where
  // its siblings accept 6), so the field can only cost a 400 until there is
  // a reason to ask for more than one image.
  switch (shape) {
    case ImageRequestShape.dashscopeWan:
      return {
        'model': modelId,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'text': prompt},
              for (final ref in imageRefs) {'image': ref},
            ],
          }
        ],
        if (parameters.isNotEmpty) 'parameters': parameters,
      };
    case ImageRequestShape.dashscopeQwen:
    case ImageRequestShape.none:
      return {
        'model': modelId,
        'input': {
          'messages': [
            {
              'role': 'user',
              'content': [
                for (final ref in imageRefs) {'image': ref},
                {'text': prompt},
              ],
            }
          ],
        },
        if (parameters.isNotEmpty) 'parameters': parameters,
      };
  }
}

/// Throws when a DashScope body carries an error.
///
/// DashScope does not use OpenAI's `{"error": {...}}`, so the shared
/// [throwIfEnvelopeError] sees nothing: failures arrive as a top-level
/// `{status_code, code, message, request_id}`, and a failed async task
/// carries the same pair nested in `output`. A successful body also has
/// `status_code` (200) but no `code`, which is why presence of a non-empty
/// `code` — not of `status_code` — is the test.
///
/// Keeping the structured code intact matters beyond diagnostics:
/// `DataInspectionFailed` is a content-moderation refusal, and a refusal that
/// degrades into prose is exactly what gets misread as "this endpoint cannot
/// edit", triggering a second, billed generation.
void throwIfDashScopeError(Map<String, dynamic> data) {
  void check(Map source) {
    final code = source['code'];
    if (code is! String || code.isEmpty) return;
    final message = source['message'] ?? source['msg'] ?? '';
    final requestId = source['request_id'];
    throw LLMApiException(
      'DashScope error ($code): $message'
      '${requestId is String && requestId.isNotEmpty ? ' [request_id: $requestId]' : ''}',
      isEnvelope: true,
    );
  }

  check(data);
  final output = data['output'];
  if (output is Map) check(output);
}

/// Every image reference a response carries, in declaration order.
///
/// Two shapes, because the synchronous surface answers as a chat turn
/// (`output.choices[].message.content[].image`) and the task surface answers
/// as a result list (`output.results[].url`). Entries are returned raw — a
/// signed `https://` URL in practice, a `data:` string if one ever appears —
/// and the caller decides how to turn them into bytes.
List<String> dashscopeImageRefs(Map<String, dynamic> data) {
  final refs = <String>[];
  void add(Object? value) {
    if (value is String && value.isNotEmpty) refs.add(value);
  }

  final output = data['output'];
  if (output is! Map) return refs;

  final choices = output['choices'];
  if (choices is List) {
    for (final choice in choices) {
      if (choice is! Map) continue;
      final message = choice['message'];
      if (message is! Map) continue;
      final content = message['content'];
      if (content is! List) continue;
      for (final part in content) {
        if (part is Map) add(part['image']);
      }
    }
  }

  final results = output['results'];
  if (results is List) {
    for (final result in results) {
      if (result is Map) add(result['url'] ?? result['image']);
    }
  }

  return refs;
}

/// The payload with inline images replaced by a count, safe for logs.
///
/// A base64 image is megabytes of noise in a log that exists to be read, and
/// the conversation is the only place one can appear — under `input` on the
/// three-section shapes, at the top level on wan's. Shared by every native
/// surface (chat, image sync, image async) so one of them cannot start
/// spilling image bytes into the debug log while the others do not.
Map<String, dynamic> dashscopePayloadForLog(
    Map<String, dynamic> payload, int refs) {
  if (refs == 0) return payload;
  final note = '[messages with $refs inline reference image(s)]';
  return {
    for (final entry in payload.entries)
      entry.key: (entry.key == 'input' || entry.key == 'messages')
          ? note
          : entry.value,
  };
}
