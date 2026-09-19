import 'dart:math' as math;

import '../image_size_rules.dart';
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
  final base = _dashscopeHostBase(endpoint);
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
  final base = _dashscopeHostBase(endpoint);
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

  // The shared parser (every size spelling the app meets: `x`, `X`, `*`,
  // `×`, stray spaces) — a private regex here used to miss `1024X1024`.
  final wxh = parseWxH(raw);
  if (wxh != null) return '${wxh.width}*${wxh.height}';

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

/// The pixel area every default qwen-image size is fitted into: the 1K
/// billing tier. DashScope bills `qwen-image*` by output *area* in two tiers
/// (`qima_output_1k` / `qima_output_2k`), and an omitted `size` renders at
/// 2048² — the 2K tier, at twice the price — so "no size" is never sent on
/// this dialect; a size is always derived, and it lands in the cheaper tier.
const int dashscopeQwenDefaultArea = 1024 * 1024;

/// This target's size control, or null when its model takes no `size` at
/// all — read off the model's declared parameters (layer 3), never off its
/// id. The basic `qwen-image-edit` declares no size control because the
/// endpoint has none for it; every other DashScope image model declares one.
ParamSpec? dashscopeSizeSpec(LLMTarget target) {
  for (final p in target.model.capabilities.imageParams) {
    if (p.key == 'imageSize') return p;
  }
  return null;
}

/// The `size` a qwen-image request gets when the author picked none.
///
/// Text-to-image: a 1K square. Edit: the input's own proportions, fitted
/// into the 1K area — because "follow the input" has no cheaper spelling on
/// this endpoint. Omitting `size` on an edit does follow the input's ratio,
/// but scales it up to the 2K area (a 768×1376 source came back 1520×2736)
/// and bills accordingly. So the ratio is honoured here, at the area the
/// author would have got for free elsewhere.
///
/// Both edges are floored to the model's grid; the area therefore lands just
/// under 1024², never over it. Proportions past the model's limit ([rules]:
/// 8:1 for qwen 2.0 / 3.0, 4:1 for edit-max / plus, whose edges must stay in
/// 512–2048) are clamped rather than refused — the endpoint would 400 on
/// them, and a clamped picture beats a failed request for a source that is a
/// strip or a banner.
String dashscopeQwenDefaultSize(
  ({int width, int height})? input, {
  ImageSizeRules rules = kDashscopeQwenSizeRules,
}) {
  if (input == null || input.width <= 0 || input.height <= 0) {
    return '1024*1024';
  }
  final step = rules.edgeStep;
  final maxRatio = rules.maxRatio;
  var ratio = input.width / input.height;
  if (ratio > maxRatio) ratio = maxRatio;
  if (ratio < 1 / maxRatio) ratio = 1 / maxRatio;

  // Solve w·h = area, w/h = ratio — short edge first, long edge derived from
  // the *snapped* short edge. Flooring both independently can push the
  // proportion past the 8:1 ceiling (2896×352 is 8.2:1), and deriving the
  // long edge from the snapped short one keeps it at or under the target.
  final landscape = ratio >= 1;
  final longOverShort = landscape ? ratio : 1 / ratio;
  final short = _floorToGrid(math.sqrt(dashscopeQwenDefaultArea / longOverShort), step);
  var long = _floorToGrid(short * longOverShort, step);
  // Snapping the short edge down lets the derived long edge overshoot the
  // area by a step (21:9 lands at 1568×672, 0.5 % over); the 1K tier is a
  // hard ceiling, so the long edge steps back until the area is under it.
  while (long * short > dashscopeQwenDefaultArea && long > step) {
    long -= step;
  }
  return landscape ? '$long*$short' : '$short*$long';
}

int _floorToGrid(double edge, int step) {
  final snapped = (edge / step).floor() * step;
  return snapped < step ? step : snapped;
}

/// The request body for one image generation or edit.
///
/// [imageRefs] are reference images already resolved to something the
/// endpoint accepts — a public URL or a `data:<mime>;base64,…` string. Empty
/// means text-to-image. [inputSize] is the first reference's pixel size when
/// the caller could read one; it only matters to the qwen default (see
/// [dashscopeQwenDefaultSize]).
///
/// [sizeSpec] is the model's size control (`dashscopeSizeSpec`), null when
/// the model takes no `size` at all — derived from the model's declared
/// parameters (layer 3), because the answer differs *within* the family:
/// `qwen-image-edit` (the basic one, not `-max` / `-plus`) has no `size` and
/// 400s on receiving one, while every sibling both accepts it and, left
/// without it, renders at the 2K tier. So where a size control exists one is
/// always sent — and where none exists, none is.
///
/// The requested size goes through the spec first: task options outlive the
/// model they were chosen for (a retried task, a size left over from another
/// family), and a value the model's own table rejects is replaced by the
/// table's default rather than forwarded to a 400. A closed list without a
/// sentinel (first-generation `qwen-image`) therefore always sends one of
/// its own sizes; a sentinel falls through to the dialect's default, which
/// is fitted to the spec's size rules.
///
/// `n` is always sent, and always 1. The upstream default is **not** 1
/// everywhere: `wan2.7-*` defaults to four images and bills every one of
/// them, so a request that leaves `n` off buys four pictures for one task.
/// Every model in scope accepts `n: 1` (the ceilings differ — 6, 4, and the
/// basic `qwen-image-edit`'s hard 1 — but the floor is shared).
///
/// Both shapes carry the conversation under `input` — the envelope is always
/// `model` / `input` / `parameters`. A second-hand mirror of the docs showed
/// `wan2.7-*` with `messages` at the top level; the real endpoint answers
/// that with `400 InvalidParameter: Field required: input.messages`
/// (2026-09-19, wan2.7-image-pro). What does differ is the part order:
/// `qwen-image*` leads with the images (the instruction reads as "…do this
/// to them"), `wan2.7-*` leads with the text.
/// [ImageRequestShape] is declared per model in layer 3 so neither this
/// function nor the protocol has to recognize a model id.
Map<String, dynamic> buildDashScopeImagePayload({
  required String modelId,
  required ImageRequestShape shape,
  required String prompt,
  required List<String> imageRefs,
  Map<String, dynamic>? options,
  ({int width, int height})? inputSize,
  ParamSpec? sizeSpec,
}) {
  final String? size;
  if (sizeSpec == null) {
    size = null;
  } else {
    final requested = sizeSpec.normalize(readStringOption(options, 'imageSize'));
    size = dashscopeSize({'imageSize': requested}) ??
        switch (shape) {
          // wan takes the tier presets directly, and its own omitted default
          // is the 2K tier — the same double-price trap as qwen's.
          ImageRequestShape.dashscopeWan => '1K',
          ImageRequestShape.dashscopeQwen ||
          ImageRequestShape.none =>
            dashscopeQwenDefaultSize(
              inputSize,
              rules: sizeSpec.sizeRules ?? kDashscopeQwenSizeRules,
            ),
        };
  }
  final promptExtend = dashscopePromptExtend(options);
  final parameters = <String, dynamic>{
    'n': 1,
    'size': ?size,
    'prompt_extend': ?promptExtend,
  };

  final images = [for (final ref in imageRefs) {'image': ref}];
  final text = {'text': prompt};
  final content = switch (shape) {
    ImageRequestShape.dashscopeWan => [text, ...images],
    ImageRequestShape.dashscopeQwen ||
    ImageRequestShape.none =>
      [...images, text],
  };
  return {
    'model': modelId,
    'input': {
      'messages': [
        {'role': 'user', 'content': content},
      ],
    },
    'parameters': parameters,
  };
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
/// three-section shapes (a bare `messages` is redacted too, should a surface
/// ever carry one). Shared by every native
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
