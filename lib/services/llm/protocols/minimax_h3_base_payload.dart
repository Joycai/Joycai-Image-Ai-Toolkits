import '../llm_types.dart';
import 'minimax_payload.dart' show minimaxVideoDuration;
import 'protocol.dart';

/// Pure request/response helpers for the **self-hosted** MiniMax H3 surface —
/// the SGLang "H3-Base API" (`sglang serve --model-path MiniMaxAI/MiniMax-H3`).
///
/// IO-free on purpose, like `minimax_payload.dart`: the repo has no HTTP mock
/// setup, so these rules are kept out of the protocol's request path so
/// `test/minimax_h3_base_payload_test.dart` can pin them.
///
/// The wire facts are recorded in `docs/api/minimax.md` §8. In brief
/// (SGLang cookbook, MiniMax local-deploy-h3 guide):
///
///   `POST {base}/videos`               → `{id}` (async job)
///   `GET  {base}/videos/{id}`          → `{status: pending|…|completed|failed}`
///   `GET  {base}/videos/{id}/content`  → the finished MP4
///
/// Despite sharing the Sora-style path shape, the submit body is **JSON with
/// its own vocabulary**, not the ① multipart form: `task` (t2va/fl2va/ref2va),
/// a `conditions[]` array of role-tagged media *URIs*, and a `target` object
/// carrying `short_edge` / `aspect_ratio` / `duration_seconds`. And the poll's
/// terminal success is `completed`, not the `succeeded` the ① surface says —
/// either difference alone would make the ① protocol hang or 400 here.

/// The semantic slot one media condition fills. Mirrors the cloud surface's
/// three roles (`MiniMaxVideoRole`) so the two MiniMax video wires behave the
/// same from the workbench, but spells them in H3-Base's own vocabulary:
/// first/last frame are both `role: "keyframe"` distinguished by
/// `frame_index` (0 / -1), references are `role: "reference"`.
enum MiniMaxH3Role {
  firstFrame,
  lastFrame,
  reference;

  /// Whether this condition belongs to the keyframe modality (task `fl2va`)
  /// rather than the reference one (task `ref2va`).
  bool get isFrame => this != MiniMaxH3Role.reference;
}

/// One resolved media condition for [buildMiniMaxH3VideoPayload].
class MiniMaxH3Media {
  final MiniMaxH3Role role;

  /// A URI the *server* can dereference. The cookbook documents exactly one
  /// form — `file:///path` on the server's own filesystem — no URL and no
  /// base64 spelling exist on this wire, which is why the app converts local
  /// attachment paths with [minimaxH3FileUri] and the whole arrangement
  /// assumes the app and the SGLang service share a filesystem.
  final String uri;

  const MiniMaxH3Media(this.role, this.uri);
}

/// The `file://` URI for a local attachment path, in the form the H3-Base
/// server dereferences.
///
/// [windows] decides how the path is parsed (drive letters, backslashes);
/// callers pass `Platform.isWindows` so the payload layer itself stays free
/// of dart:io and the rule stays testable for both spellings.
String minimaxH3FileUri(String path, {required bool windows}) =>
    Uri.file(path, windows: windows).toString();

/// The filename prefix every materialized H3 reference temp file carries.
/// The writer ([MiniMaxH3BaseVideoProtocol._attachmentFilePath]) and the
/// startup sweeper both key off this, so they cannot drift apart.
const String minimaxH3TempRefPrefix = 'joycai_h3_ref_';

/// Whether a temp file named [basename], last modified at [modified], is a
/// stale H3 reference the startup sweep may delete at [now].
///
/// Guarded by both the prefix and an age floor: an H3 job's reference files
/// are read by the *server* asynchronously during generation, so a file young
/// enough to belong to an in-flight job must never be reaped. [maxAge]
/// (default 6h) is comfortably longer than any single video job.
bool minimaxH3TempRefIsStale(
  String basename,
  DateTime modified,
  DateTime now, {
  Duration maxAge = const Duration(hours: 6),
}) {
  if (!basename.startsWith(minimaxH3TempRefPrefix)) return false;
  return now.difference(modified) > maxAge;
}

/// Split [media] into the items that will be sent and the ones dropped by the
/// keyframe/reference exclusivity rule — the same client-side rule the cloud
/// surface applies (`partitionMiniMaxVideoMedia`), for the same reason: the
/// frames are a precise instruction the user placed deliberately, and the
/// released H3-Base checkpoints serve one task variant per process, so a
/// request mixing the two modalities has no shape the cookbook documents.
/// Returns the kept items first.
(List<MiniMaxH3Media> kept, List<MiniMaxH3Media> dropped)
    partitionMiniMaxH3Media(List<MiniMaxH3Media> media) {
  final hasFrame = media.any((m) => m.role.isFrame);
  if (!hasFrame) return (media, const []);
  return (
    media.where((m) => m.role.isFrame).toList(),
    media.where((m) => !m.role.isFrame).toList(),
  );
}

/// The request body for one H3-Base video generation job.
///
/// [media] must already be filtered through [partitionMiniMaxH3Media].
/// Field-by-field, against the SGLang cookbook's examples:
///
///  * `task` — derived from the media: none → `t2va`, keyframes → `fl2va`,
///    references → `ref2va`. There is no separate v2v task value upstream.
///  * `conditions[]` — keyframes carry `frame_index` 0 (first) / -1 (last),
///    the only two values the cookbook allows; references carry none. The
///    first frame is emitted before the last regardless of attachment order.
///  * `target.short_edge` — always 768: the released checkpoints' one
///    verified quality recipe (the 2K tier is cloud-only).
///  * `target.aspect_ratio` — `auto` means "follow the input media", so a
///    text-only request substitutes 16:9 exactly as the cloud builder does
///    for its `adaptive` spelling.
///  * `seconds` + `target.duration_seconds` — the cookbook sends the duration
///    in both places, so this does too; both come from the shared `seconds`
///    option clamped into the same 4–15 s window as the cloud surface.
///  * `num_inference_steps` / `flow_shift` / `audio_flow_shift` — the
///    released quality recipe's constants, sent verbatim from the cookbook
///    examples rather than left to undocumented server defaults.
Map<String, dynamic> buildMiniMaxH3VideoPayload({
  required String modelId,
  required String prompt,
  required List<MiniMaxH3Media> media,
  Map<String, dynamic>? options,
}) {
  final duration = minimaxVideoDuration(options);

  final hasFrames = media.any((m) => m.role.isFrame);
  final task = media.isEmpty ? 't2va' : (hasFrames ? 'fl2va' : 'ref2va');

  final aspect = readStringOption(options, 'aspectRatio');
  // `adaptive` is the cloud spelling of the same idea and shares the option
  // key; both normalize to H3-Base's `auto`.
  final ratio = (aspect == null ||
          aspect == 'not_set' ||
          aspect == 'adaptive' ||
          aspect == 'auto')
      ? (media.isEmpty ? '16:9' : 'auto')
      : aspect;

  final ordered = [
    ...media.where((m) => m.role == MiniMaxH3Role.firstFrame),
    ...media.where((m) => m.role == MiniMaxH3Role.lastFrame),
    ...media.where((m) => m.role == MiniMaxH3Role.reference),
  ];

  return {
    'model': modelId,
    'prompt': prompt,
    'seconds': duration,
    'task': task,
    'conditions': [
      for (final item in ordered)
        {
          'type': 'image',
          'uri': item.uri,
          'role': item.role.isFrame ? 'keyframe' : 'reference',
          if (item.role == MiniMaxH3Role.firstFrame) 'frame_index': 0,
          if (item.role == MiniMaxH3Role.lastFrame) 'frame_index': -1,
        },
    ],
    'target': {
      'short_edge': 768,
      'aspect_ratio': ratio,
      'duration_seconds': duration.toDouble(),
    },
    'num_outputs_per_prompt': 1,
    'num_inference_steps': 50,
    'flow_shift': 12.0,
    'audio_flow_shift': 3.0,
  };
}

/// Translate one H3-Base poll body into the Veo-shaped envelope the
/// videoGenerate executor speaks.
///
/// Status machine: `completed` → done, with [videoUri] (the job's `/content`
/// endpoint — the poll body itself carries no URL); `failed` → error naming
/// the operation; anything else (`pending`, or whatever the in-progress state
/// is spelled as — the cookbook never shows it) → not done. Note `completed`,
/// not the ① surface's `succeeded`: a poller expecting the wrong word never
/// errors, it reports "processing" forever.
Map<String, dynamic> minimaxH3PollEnvelope(
  Map<String, dynamic> data,
  String operationName,
  String videoUri,
) {
  final status = data['status']?.toString().toLowerCase() ?? '';

  if (status == 'completed') {
    return {
      'name': operationName,
      'done': true,
      'response': {
        'generateVideoResponse': {
          'generatedSamples': [
            {
              'video': {'uri': videoUri},
            }
          ],
        },
      },
    };
  }

  if (status == 'failed') {
    final err = data['error'];
    final msg = err is Map
        ? (err['message'] ?? err.toString())
        : (err?.toString() ?? 'unknown');
    throw LLMApiException(
        'MiniMax H3 local video job $operationName failed: $msg');
  }

  return {
    'name': operationName,
    'done': false,
    if (data['progress'] != null) 'progress': data['progress'],
    'status': status,
  };
}
