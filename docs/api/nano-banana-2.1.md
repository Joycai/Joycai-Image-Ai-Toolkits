# Nano Banana 2.1

Verified against Google documentation on 2026-10-18. Stable model ID:
`gemini-nano-banana-2.1` (October 2026). Add it to an existing Google Gemini
channel, or fetch the channel's model list and select it. No new vendor,
wire protocol, database migration, or pricing override is needed.

## Application support

- Automatically classified as an image model, including `models/` and provider namespaces.
- Text-to-image and image editing through the existing `generateContent` /
  `streamGenerateContent` transport; OpenAI-compatible relay chat retains Gemini extensions.
- Resolution: default (omit), `1K`, `2K`, `4K`. No `512` option; upstream default is `1K`.
- Aspect ratio: default (omit), `1:1`, `2:3`, `3:2`, `3:4`, `4:3`, `4:5`,
  `5:4`, `9:16`, `16:9`, `21:9`, `1:4`, `4:1`, `1:8`, `8:1`.
- At most 14 reference images, validated by the shared generation schema.
- Thinking: default (omit), `minimal`, `medium`, `high`; upstream default is
  `medium`. No off/low setting. Native requests use
  `generationConfig.thinkingConfig.thinkingLevel` (uppercase). Compatible chat
  uses `extra_body.google.thinking_config.thinking_level`, without a competing
  `reasoning_effort`. Relay acceptance depends on the relay implementation.
- Internal `thought: true` images are excluded from deliverables. Thought text
  remains reasoning; usage metadata is preserved.
- Parameters use the existing typed task snapshots, preferences, MCP schema and
  localized workbench form. No model-level chat reasoning change is needed.

The existing `generationConfig.imageConfig` remains in the API reference and
SDK examples. Newer examples also use `responseFormat.image`; this change keeps
`imageConfig` for compatibility with existing Gemini relays.

## Previous models checked in the same integration

| Model | Resolution options (plus unset) | Aspect ratios | Thinking control | Reference limit |
|---|---|---|---|---|
| `gemini-3.1-flash-image` | `512`, `1K`, `2K`, `4K` | 14, including extreme ratios | unset / minimal / high; default minimal | 14 |
| `gemini-3-pro-image` | `1K`, `2K`, `4K` | 10, including 21:9 | Automatic; no selectable level exposed | 14 |
| `gemini-nano-banana-2.1` | `1K`, `2K`, `4K` | 14 | unset / minimal / medium / high; default medium | 14 |

Flash's half-K wire value is exactly `512`, not `0.5K`. Pro now resolves its
specialized profile for both the official stable ID and `-preview`; the old
`gemini-3.1-pro-image` matching rule remains for backward compatibility, not as
an assertion that it is an official model. Namespaced and case-insensitive IDs
retain the same profiles. The original implementation omitted Flash's 512 and
thinking controls, missed the official Pro ID, and did not enforce either limit.

All three use the same tested sync/SSE transport and thought-image filtering.
Pro thinking runs automatically; the guide lists configurable levels only for
Flash and Nano Banana 2.1. These are image-task capabilities, not a claim of full
coverage of every upstream feature. The limitations below also apply to these
older models where Google supports the feature.

## Upstream capabilities outside this integration

Google also supports Web/Image Search grounding, video/PDF inputs and conversational
editing. This app's image task accepts image references; it does not add video/PDF
uploads, signed multi-turn image history, or an Interactions API client here.
Grounding is not exposed: its source attribution and Search entry-point display
need an end-to-end implementation before enabling the tool. Arbitrary function
calling, structured output, caching and URL context are not supported by this model.

The model page reports 131,072 input / 32,768 output tokens. An official forum
report documents inconsistent live limits. Keep discovered limits and user settings
as the source of truth rather than hard-coding the marketing context window.
Pricing remains user-configured; no paid live provider request was used to verify
this integration.

## Sources

- [Model capabilities and limits](https://ai.google.dev/gemini-api/docs/models/gemini-nano-banana-2.1)
- [Image generation guide](https://ai.google.dev/gemini-api/docs/image-generation)
- [Generate Content image guide](https://ai.google.dev/gemini-api/docs/generate-content/image-generation)
- [Generate Content API reference](https://ai.google.dev/api/generate-content)
- [OpenAI compatibility and thinking config](https://ai.google.dev/gemini-api/docs/openai)
- [Reported context-limit discrepancy](https://discuss.ai.google.dev/t/gemini-nano-banana-2-1-input-limit-the-model-card-says-1m-but-generatecontent-rejects-anything-above-65-536/187225)

- [Gemini 3.1 Flash Image model](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-image)
- [Gemini 3 Pro Image model](https://ai.google.dev/gemini-api/docs/models/gemini-3-pro-image)
