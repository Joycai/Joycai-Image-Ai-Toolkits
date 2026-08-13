---
name: joycai-add-llm-provider
description: >
  Guides adding a new AI supplier (vendor) or a new wire protocol to the
  Joycai Image AI Toolkits app's three-layer LLM stack. Use whenever asked to
  "add a new model provider", "integrate a new AI API", "add an LLM provider",
  "support a new backend", "connect to a new AI service", or "add support for
  [ProviderName] models". Covers: deciding whether the addition is a vendor
  (layer 2) or a protocol (layer 1), VendorProfile fields, dispatcher routing,
  channel-wizard presets, and model capabilities (layer 3).
---

# Add a New LLM Vendor or Protocol

The LLM stack is three layers (required reading:
`docs/architecture/llm-three-layer.md`):

1. **Protocol** (`lib/services/llm/protocols/`) — a wire format: endpoint
   shape, payload, response/stream parsing. Families: `openai`, `gemini`,
   `midjourney`.
2. **Vendor** (`lib/services/llm/vendors/`) — a supplier of a protocol
   family: auth scheme, surface overrides. `VendorProfile.id` is stored in
   `llm_channels.type`.
3. **Model** (`lib/services/llm/model_descriptor.dart` +
   `model_family.dart` + `model_capabilities.dart`) — family classification
   and capabilities. The ONLY place model-id string sniffing is allowed.

All routing lives in `lib/services/llm/llm_dispatcher.dart`. `LLMService`
(retry, sessions, token accounting) and `LLMConfigResolver` never change for
a new vendor.

## First: which layer is this?

- **The service speaks OpenAI chat/completions or the Gemini REST dialect**
  (DeepSeek, MiniMax, Qwen, a new relay, …) → it's a **vendor**. No new
  protocol code.
- **The service has its own wire format** (like midjourney-proxy did) → it's
  a **protocol** (plus a vendor profile that serves it).

## Checklist A — new vendor (the common case)

- [ ] 1. `lib/services/llm/vendors/vendors.dart`: add a `static const String`
      id and a `VendorProfile` entry. Pick `family` (openai/gemini) and
      `auth` (`bearer`, `googleApiKey`, `googleApiKeyWithBearerFallback`).
- [ ] 2. Vendor-specific surface? Set a declarative flag on `VendorProfile`
      (see `usesXaiNativeSurfaces`) and add the protocol selection to the
      dispatcher. Never branch on `vendor.id` inside a protocol.
- [ ] 3. UI preset: `widgets/models/channel_wizard_dialog.dart` `_presets`
      list (+ provider title l10n via the `joycai-l10n` skill) and, if it
      should appear in first-run setup, `screens/wizard/setup_wizard.dart`'s
      dropdown.
- [ ] 4. Models with new parameters? Extend layer 3:
      `model_capabilities.dart` (ParamSpec tables) and, if a new family is
      needed, `model_family.dart` + the dispatcher routing.
- [ ] 5. `flutter analyze` — must report **"No issues found!"**
- [ ] 6. `flutter test` — the vendor auth tests live in
      `test/google_auth_headers_test.dart`; add cases for a new auth scheme.

## Checklist B — new protocol

- [ ] 1. Create `lib/services/llm/protocols/<name>_protocol.dart`
      implementing the relevant interfaces from `protocols/protocol.dart`:
      `ChatProtocol` (sync + stream), `ImageGenProtocol` (single-shot),
      `VideoJobProtocol` (submit + poll, translate poll results into the
      Veo-shaped `{done, response: {generateVideoResponse: ...}}` envelope),
      `DiscoveryProtocol`.
- [ ] 2. Protocols receive an `LLMTarget` — use `target.headers()` /
      `target.decorateUrl()` for auth, `target.model.capabilities` for
      limits, `target.config.createClient()` for proxy-aware HTTP (close it
      in `finally`). No vendor-id branches, no modelId sniffing.
- [ ] 3. Add a `ProtocolFamily` value and extend every switch in
      `llm_dispatcher.dart` (generate / generateStream / startLongRunning /
      checkOperation / discoverModels).
- [ ] 4. Add the vendor profile(s) serving the protocol (Checklist A).
- [ ] 5. Token usage: yield/return `metadata` carrying the upstream usage
      payload — `LLMService._recordUsage` understands OpenAI
      (`prompt_tokens`/`completion_tokens`) and Google
      (`promptTokenCount`/`candidatesTokenCount`) keys.
- [ ] 6. `flutter analyze` + `flutter test`.

## Key types

```dart
// protocols/protocol.dart
class LLMTarget {
  final LLMModelConfig config;   // endpoint, apiKey, fees, proxy, channelType
  final VendorProfile vendor;    // layer 2 — auth + family
  final ModelDescriptor model;   // layer 3 — family + capabilities
  Map<String, String> headers();
  Uri decorateUrl(Uri url);
}

// llm_types.dart (unchanged by vendor work)
LLMMessage(role: LLMRole.system | .user | .assistant | .tool, content: '...', attachments: [...])
LLMResponse(text: '...', generatedImages: [], metadata: {...}, toolCalls: [...])
LLMResponseChunk(textPart: ..., imagePart: ..., metadata: ..., isDone: ...)
```

## Reference implementations

- `protocols/openai_chat_protocol.dart` — JSON + SSE streaming, tools,
  relay image extraction.
- `protocols/gemini_veo_protocol.dart` — async job (submit + poll).
- `protocols/midjourney_protocol.dart` — fully custom wire format hidden
  behind the ChatProtocol shape (submit-poll loop inside generate()).
- `vendors/vendors.dart` — the seven existing profiles, including xAI's
  surface-override pattern.
