---
name: joycai-add-llm-provider
description: >
  Guides adding a new AI provider (backend API) to the Joycai Image AI Toolkits app.
  Use whenever asked to "add a new model provider", "integrate a new AI API",
  "add an LLM provider", "support a new backend", "connect to a new AI service",
  or "add support for [ProviderName] models". This skill covers the full implementation
  checklist: implementing the ILLMProvider interface (all 4 methods), HTTP client
  lifecycle management, streaming vs non-streaming response parsing, token usage
  metadata (required for cost tracking), two registration calls in main.dart, and
  optional model discovery. Reference implementations: OpenAIAPIProvider and
  GoogleGenAIProvider in lib/services/llm/providers/.
---

# Add a New LLM Provider

The app's AI layer is built around `LLMService` + `ILLMProvider`. Each provider
is a self-contained class that handles one API's HTTP protocol, streaming format,
and response parsing. The service layer handles retry, session management, and
token accounting — providers only need to implement the raw communication.

## Files to Touch

| File | What to do |
|------|-----------|
| `lib/services/llm/providers/<name>_provider.dart` | Create new provider class |
| `lib/main.dart` (lines 33–37) | Register provider with `LLMService` and `ModelDiscoveryService` |
| `lib/services/llm/llm_config_resolver.dart` | Add channel type mapping if needed |

**Reference implementations** (read before writing):
- `lib/services/llm/providers/openai_api_provider.dart` — OpenAI-compatible REST + SSE streaming
- `lib/services/llm/providers/google_genai_provider.dart` — Google Gemini REST + SSE + long-running ops

## Checklist

- [ ] 1. Create `lib/services/llm/providers/<name>_provider.dart`
- [ ] 2. Implement `generate()` — synchronous request-response fallback
- [ ] 3. Implement `generateStream()` — streaming, must yield `LLMResponseChunk` with token metadata
- [ ] 4. Implement `startLongRunning()` if provider supports async jobs (video, image gen queues)
- [ ] 5. Implement `checkOperation()` paired with `startLongRunning()`
- [ ] 6. Close HTTP client in `finally` block in both `generate()` and `generateStream()`
- [ ] 7. Register in `main.dart`: `LLMService().registerProvider('type-id', MyProvider())`
- [ ] 8. Register discovery: `ModelDiscoveryService().registerProvider('type-id', MyProvider())` (if implementing `IModelDiscoveryProvider`)
- [ ] 9. Run `flutter analyze` — must report **"No issues found!"**

## Interface Contract

```dart
// lib/services/llm/llm_provider_interface.dart
abstract class ILLMProvider {
  Future<LLMResponse> generate(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    Function(String, {String level})? logger,
  });

  Stream<LLMResponseChunk> generateStream(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    Function(String, {String level})? logger,
  });

  Future<String> startLongRunning(   // return operation ID / name
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    Function(String, {String level})? logger,
  });

  Future<Map<String, dynamic>> checkOperation(   // return status map
    LLMModelConfig config,
    String operationName, {
    Function(String, {String level})? logger,
  });
}
```

## Key Types

```dart
// LLMModelConfig — what the provider receives
config.modelId      // String — e.g. "gpt-4o"
config.endpoint     // String — base URL (never hardcode this)
config.apiKey       // String — auth key
config.extraParams  // Map<String,dynamic> — model-specific options
config.createClient() // returns http.Client (proxy-aware)

// LLMMessage — a conversation turn
LLMMessage(role: LLMRole.system | .user | .assistant, content: '...', attachments: [...])
LLMAttachment.fromFile(File(path), mimeType)   // for images/files
LLMAttachment.fromBytes(bytes, mimeType)

// LLMResponse — synchronous response
LLMResponse(text: '...', generatedImages: [], metadata: {'usage': ...})

// LLMResponseChunk — one streaming chunk
LLMResponseChunk(textPart: '...', imagePart: bytes, metadata: {'usage': ...})
```

## Implementation Template

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../llm_provider_interface.dart';
import '../llm_types.dart';
import '../model_discovery_service.dart'; // only if implementing IModelDiscoveryProvider

class MyNewProvider implements ILLMProvider, IModelDiscoveryProvider {

  // ─── Model discovery (optional but recommended) ───────────────────────────

  @override
  Future<List<DiscoveredModel>> fetchModels(LLMModelConfig config) async {
    final url = Uri.parse('${config.endpoint}/models');
    final response = await http.get(url, headers: _headers(config.apiKey));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch models: ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    return (data['data'] as List).map((m) => DiscoveredModel(
      modelId: m['id'] as String,
      displayName: m['id'] as String,
      description: '',
      rawData: m as Map<String, dynamic>,
    )).toList();
  }

  // ─── Synchronous request (used when model.supportsStream == false) ────────

  @override
  Future<LLMResponse> generate(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    Function(String, {String level})? logger,
  }) async {
    final url = Uri.parse('${config.endpoint}/chat/completions');
    final client = config.createClient(); // proxy-aware
    try {
      final response = await client.post(url,
        headers: _headers(config.apiKey),
        body: jsonEncode(_buildPayload(config.modelId, history, options, stream: false)),
      );
      if (response.statusCode != 200) {
        throw Exception('API error: ${response.statusCode} — ${response.body}');
      }
      final data = jsonDecode(response.body);
      return LLMResponse(
        text: data['choices']?[0]?['message']?['content'] ?? '',
        metadata: data['usage'] ?? {},  // token counts for cost tracking
      );
    } finally {
      client.close(); // ALWAYS close — prevents resource leaks
    }
  }

  // ─── Streaming request (preferred path) ──────────────────────────────────

  @override
  Stream<LLMResponseChunk> generateStream(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    Function(String, {String level})? logger,
  }) async* {
    final url = Uri.parse('${config.endpoint}/chat/completions');
    final request = http.Request('POST', url)
      ..headers.addAll(_headers(config.apiKey))
      ..body = jsonEncode(_buildPayload(config.modelId, history, options, stream: true));

    final client = config.createClient();
    try {
      final response = await client.send(request);
      if (response.statusCode != 200) {
        client.close();
        throw Exception('Stream error: ${response.statusCode}');
      }

      await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.isEmpty || line == 'data: [DONE]') continue;
        final dataLine = line.startsWith('data: ') ? line.substring(6) : line;

        try {
          final chunk = jsonDecode(dataLine);
          // Emit token usage metadata (required for cost tracking)
          if (chunk['usage'] != null) {
            yield LLMResponseChunk(metadata: chunk['usage']);
          }
          final delta = chunk['choices']?[0]?['delta']?['content'] as String?;
          if (delta != null && delta.isNotEmpty) {
            yield LLMResponseChunk(textPart: delta);
          }
        } catch (_) {
          // skip malformed lines
        }
      }
    } finally {
      client.close(); // ALWAYS close, even after stream ends
    }
  }

  // ─── Long-running operations (skip if not needed) ────────────────────────

  @override
  Future<String> startLongRunning(LLMModelConfig config, List<LLMMessage> history, {
    Map<String, dynamic>? options, Function(String, {String level})? logger,
  }) async {
    throw UnimplementedError('MyNewProvider does not support long-running operations.');
  }

  @override
  Future<Map<String, dynamic>> checkOperation(LLMModelConfig config, String operationName, {
    Function(String, {String level})? logger,
  }) async {
    throw UnimplementedError('MyNewProvider does not support long-running operations.');
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Map<String, String> _headers(String apiKey) => {
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
  };

  Map<String, dynamic> _buildPayload(
    String modelId,
    List<LLMMessage> history,
    Map<String, dynamic>? options, {
    required bool stream,
  }) {
    return {
      'model': modelId,
      'stream': stream,
      'messages': history.map((m) => {
        'role': m.role.name,
        'content': m.content,
      }).toList(),
      ...?options,
    };
  }
}
```

## Registration in `main.dart`

```dart
// lib/main.dart, after existing registerProvider calls:
LLMService().registerProvider('my-provider-type', MyNewProvider());
ModelDiscoveryService().registerProvider('my-provider-type', MyNewProvider());
```

The type string (e.g., `'my-provider-type'`) must match the `type` field stored
on `LLMChannel` records in the database for models to route correctly.

## Common Pitfalls

**Hardcoded endpoint URLs** — Always use `config.endpoint`. Users configure custom
endpoints (proxies, mirrors). Hardcoding breaks any non-default deployment.

**Not closing the HTTP client** — `config.createClient()` allocates a connection.
Without `client.close()` in a `finally` block, each request leaks a socket.
This applies to both `generate()` and `generateStream()`.

**Implementing only `generateStream()`** — `LLMService` calls `generate()` when
`model.supportsStream == false`. If unimplemented, those models will error.

**Missing token metadata in streaming** — The `metadata` field of `LLMResponseChunk`
carries token counts. The service layer uses this to record usage and estimate cost.
Without it, usage tracking silently reports zero tokens.

**Forgetting the second `registerProvider` call** — `LLMService` needs the provider
to route AI calls; `ModelDiscoveryService` needs it to populate the model list in
the Models screen. Both registrations are required if model discovery is supported.
