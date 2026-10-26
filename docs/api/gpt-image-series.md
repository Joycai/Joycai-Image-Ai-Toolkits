# GPT Image 2 / 2.5 support audit

Verified against OpenAI documentation on 2026-10-26.

## Model IDs

| Model | Stable ID | Snapshot | App quality options |
|---|---|---|---|
| GPT Image 2 | `gpt-image-2` | `gpt-image-2-2026-04-21` | auto, low, medium, high |
| GPT Image 2.5 Flare | `gpt-image-2.5-flare` | `gpt-image-2.5-flare-2026-09-08` | auto, low, medium, high, xhigh, max |
| GPT Image 2.5 Sunburst | `gpt-image-2.5-sunburst` | `gpt-image-2.5-sunburst-2026-09-08` | auto, low, medium, high, xhigh, max |

Use the variant's full ID: OpenAI's catalog does not list a bare `gpt-image-2.5` model.
The app's permissive relay classification does not establish upstream availability.

## Existing supported workflow

All six IDs already resolve to dedicated Images profiles and the same native
transport. The follow-up implementation adds background, output format and compression controls.

- Text-to-image: JSON `POST /images/generations`.
- Reference-image editing: multipart `POST /images/edits`, with one `image` or
  multiple `image[]` parts; up to 16 reference images.
- `imageSize` becomes API `size`; `quality` is passed through, with `auto` omitted
  to use the API default. Sizes can be automatic, presets, or custom dimensions.
- Custom sizes: both edges divisible by 16, longest edge at most 3840,
  aspect ratio between 1:3 and 3:1, and 655,360–8,294,400 total pixels.
  OpenAI describes resolutions above 2560x1440 as experimental.
- `background`: auto (default), opaque, transparent. Transparent JPEG is rejected
  before submission; PNG and WebP preserve transparency. GPT Image 2 transparency
  remains an upstream preview capability.
- `outputFormat`: png (default), jpeg, webp; encoded as `output_format` on both
  generation and edit requests. Returned bytes determine the saved file extension.
- `outputCompression`: integer 0–100 (default 100), encoded as `output_compression`
  only for JPEG/WebP. The slider hides for PNG without erasing its parked draft.
- Existing queued snapshots missing the new controls keep the prior defaults;
  mismatched non-default output intent still fails validation.
- One output per request (`n=1`); base64 results, actual size/quality, and token
  usage are retained. The app's queue can submit separate generation tasks.
- `input_fidelity` is omitted. GPT Image 2 uses high fidelity automatically.
- With task streaming enabled and the model's streaming setting enabled, GPT Image
  2 / 2.5 Images routes send `stream: true`, `partial_images: 3` for both JSON
  generation and multipart reference edits. Earlier GPT Image models retain the
  single-response adapter.
- `image_generation.partial_image` / `image_edit.partial_image` replace one
  transient preview on the running task card, in all responsive layouts. Only
  `*.completed` yields a deliverable; preview bytes never enter result paths,
  the gallery, persistence, MCP output lists, or the billed output-image count.
  Final provider token usage (including upstream preview charges) is retained.
- Preview state clears on completion, failure and cancellation. A stream ending
  without a completed image fails; no automatic resubmission after previews.
  Both first-byte and subsequent waits use the image-generation allowance.
- A compatible gateway returning JSON is consumed as the same request's final
  response. A gateway rejecting streaming must have streaming disabled by the
  user; the app does not resubmit a potentially billed generation.

## API features not exposed by this workflow

These are capability gaps, not evidence that the supported size/quality workflow
is broken. The UI and transport currently do not send these optional fields:

| API feature | Current application behavior |
|---|---|
| `moderation` auto/low | API default auto |
| `n` 1–10 | Fixed at 1 |
| Preview count (`partial_images` 0–3) | Fixed at 3 when streaming; no separate count control |
| Edit `mask` | No mask attachment workflow |
| Responses `image_generation` tool | Not implemented as a conversational image workflow |

No paid upstream requests or third-party relay validation were performed.
Regression coverage in `test/services/llm/gpt_image_series_test.dart` checks all six
IDs, namespaced/case variants, model-specific validation, generation and one/two
reference edits through a local HTTP server, returned image/usage metadata, output field encoding, incompatible transparency rejection,
and old queued snapshot compatibility. Widget tests check conditional compression
visibility, retained values, and the localized JPEG diagnostic.
Existing size-picker tests cover legal-size calculation and boundary constraints.

## Official sources

- [Image generation guide](https://developers.openai.com/api/docs/guides/image-generation)
- [Generate image API reference](https://developers.openai.com/api/reference/resources/images/methods/generate)
- [Edit image API reference (multipart)](https://developers.openai.com/api/reference/python/resources/images/methods/edit)
- [Edit image API reference (JSON)](https://developers.openai.com/api/reference/resources/images/methods/edit)

### Gateway framing compatibility and diagnostics

The Images stream reader detects SSE versus regular JSON from the response body,
including a UTF-8 BOM and SSE comments, rather than trusting a relay's content-type
header. Complete JSON events are consumed immediately, so missing blank event
separators and connections kept open after completion do not discard a final image.
Multi-line SSE data uses the standard newline join first; if JSON decoding fails,
the reader tries joining the data fragments without inserted newlines to support
relays that wrap a base64 string. Invalid or truncated events still fail without
resubmitting the generation.

With API debug logging enabled, the request log now includes response status and
content headers, detected framing, sanitized SSE lines, parsed event types and image
byte counts, plus elapsed time. JSON failures report the decoder message, offset,
character code, payload length and data-line count instead of suggesting an HTML
page. Long base64 runs and credentials remain masked. The original reported log
was truncated, so these compatibility cases are regression scenarios rather than
a claim that its exact wire-level cause has been established.

### Slow responses and saved late results

GPT Image's default timeout is 25 minutes. Settings → Application → Image generation
lets users choose a different duration; the preference is stored under
`gpt_image_timeout_minutes` and resolved when each request starts (including MCP
and older queued tasks). Streaming first/subsequent image gaps and standard
requests use the same value. GPT Image 1/2/2.5 share this policy; unrelated routes
retain their own timeout behavior.

This is a soft response threshold: after it elapses, the app logs a warning and
keeps the original pending request/read. A late final image follows normal saving,
result persistence and usage accounting; the timeout never submits a second
generation. Explicit cancellation still aborts the transport. Waiting continues
until a result, an upstream error/disconnection, explicit cancellation or app exit;
there is no recovery endpoint for a request lost when the app closes.

This follows an observed `image_edit.completed` response with a valid 7,246,878-byte
PNG after 790,894 ms: the previous five-minute guard discarded the pending read
while cancellation waited for that successful response. Parser success did not
mean delivery to the executor. Regression tests accelerate only the configured
deadline timer, hold the HTTP response until it fires, and verify a saved image
and one usage record for both streaming and standard requests.


## Asynchronous Batch images (2026-10-26)

Workbench exposes **Asynchronous submission** for the six exact IDs above on
an official OpenAI channel, `https://api.openai.com`, and the native Images route.
Relay model aliases, custom hosts, chat/Responses image tools and Nano Banana
Batch are not enabled. Batch is a task execution mode, not a new image task type.

One task uploads one JSONL request (`custom_id = task.id`, `n=1`) using Files
`purpose=batch`, then creates a `/batches` job with a `24h` window. Generation
uses `/v1/images/generations`; reference edits use JSON `/v1/images/edits` with
inline data URLs (maximum 16 references, with the documented per-URL limit).
The existing generation schema validates size, quality, background and format.
Batch has no stream or partial previews.

The task row owns execution mode and a JSON checkpoint (schema v51): original
channel/model/endpoint, immutable price snapshot, input-file/job/result-file IDs,
submission intent, polling schedule, cancellation and settlement checkpoints.
Status and checkpoint are saved together. Credentials remain in the channel;
changing them permits re-authentication, while changing the endpoint/channel
identity pauses recovery. Active Batch jobs protect their model/channel from
removal and channel merge. Input JSON is frozen in the chosen output directory's
`.joycai-batch/<task-id>/input.json`; keep this folder until submission completes.
Ordinary database backups include checkpoints, **not** these external input files
or generated media. Cross-machine pre-submission recovery therefore also needs
that output directory. Frozen input caches are retained for diagnosis.

After acceptance, local execution concurrency is released. A queue-owned timer
polls after 30 seconds, then approximately 60/120/300 seconds with jitter;
refreshes are serialized and deduplicated, including manual refresh. Transient
failures back off up to 30 minutes and respect Retry-After. Authentication,
changed configuration and ambiguous submission require manual attention.
The app need not stay on the task screen. Closing it stops polling; reopening
restores active jobs even outside the normal history limit. Remote work continues
while the app is closed; the app must reopen to download results.

A lost create response never triggers another generation: reconcile the exact
submission intent and input-file ID against the remote batch listing. An
unresolved/ambiguous match stays protected. Cancellation stays active until
confirmed remotely. Terminal batches are still protected while their matching
result, saved image or usage settlement is outstanding. Results are matched by
custom ID, written atomically to deterministic filenames, and checked against
existing bytes before reuse. A retry of a settled failed job is explicitly a new
request; refresh always follows the original job.

Official Batch USD/million-token prices are snapshotted explicitly: text input
2.5, image input 4, text cache 0.625, image cache 1, image output 15. TokenUsage
performs cost arithmetic with a weighted input/cache rate; this does not halve
an arbitrary custom pricing group. A unique `batch:<task-id>` usage identity
prevents duplicate billing records after a crash. Missing or inconsistent usage
keeps settlement pending, even when the image has been delivered.

Task filters combine submission mode (all/immediate/asynchronous) with existing
status filters. Row/detail actions offer refresh; the toolbar refreshes all active
Batch tasks. Clear-completed, clear-all and direct repository deletion preserve
unfinished or unsettled Batch jobs. Remote waiting/cancelling/retrieving/attention
labels are visible on compact status pills and details show the last refresh.

Local HTTP tests cover wire requests and matching; queue tests cover restart,
automatic/manual polling, cancellation, cleanup protection, usage idempotency,
network/Retry-After and partial recovery. Four locales, four viewport widths and
light/dark screenshots cover the controls. No paid live OpenAI request or native
mobile run was performed.

Sources: [Batch guide](https://developers.openai.com/api/docs/guides/batch),
[pricing](https://developers.openai.com/api/docs/pricing),
[JSON image edits](https://developers.openai.com/api/reference/resources/images/methods/edit).
