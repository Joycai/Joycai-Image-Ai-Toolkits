# Release notes — v4.30.0

## Image models

- Add Nano Banana 2.1 (`gemini-nano-banana-2.1`) with its aspect ratios, output sizes, thinking levels, and 14-reference limit.
- Complete Gemini 3.1 Flash Image support with 512 output and minimal/high thinking. Correct Gemini 3 Pro Image recognition and enforce both models' reference limits.
- Keep Gemini internal thought images out of saved results.
- Add Auto/Opaque/Transparent backgrounds, PNG/JPEG/WebP output, and JPEG/WebP compression controls for GPT Image 2 and GPT Image 2.5 Flare/Sunburst, including dated snapshots.
- Reject transparent JPEG before submission, preserve compression drafts across format changes, and retain defaults for previously queued GPT Image tasks.

Controls are localized in English, Simplified Chinese, Traditional Chinese, and Japanese.

## Validation and scope

Model profiles, native generation/edit requests, streaming Gemini responses, validation, and queued-task compatibility are covered by local tests. Responsive workbench and parameter screenshots were reviewed. No paid live provider requests were made.

This release does not add search grounding, signed Gemini image conversations, image masks, native OpenAI partial-image previews, or the Responses image-generation tool. GPT Image 2 transparency remains an upstream preview feature.

See the [Gemini integration notes](../api/nano-banana-2.1.md) and [GPT Image support matrix](../api/gpt-image-series.md) for details.
