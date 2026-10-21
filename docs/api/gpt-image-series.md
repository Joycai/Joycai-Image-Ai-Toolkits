# GPT Image 2 / 2.5 support audit

Verified against OpenAI documentation on 2026-10-21.

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
