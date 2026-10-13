# Local MCP image server

Stage one lets agents use configured image models for text-to-image and
reference-image/edit generation. The desktop app must be running. Video, standalone
text generation, layer decomposition, transparent editing, remote hosting and
browser-origin clients are not exposed.

## Connect

In Settings → Connectivity, choose a port (default 39287), optionally enter allowed
reference-image folders (one absolute path per line), and enable MCP. Copy the
connection configuration into a client that supports Streamable HTTP and custom
Authorization headers. The copied configuration includes a secret bearer token.
Rotating the token disconnects existing clients. Disabling the listener does not
cancel already accepted image tasks.

The endpoint is `http://127.0.0.1:39287/mcp` with `Authorization: Bearer <token>`.
The `mcp_dart` 2.4.2 adapter uses its stable protocol profile: 2026-07-28 discovery
and stateless calls, plus legacy initialization including 2025-11-25. The app uses
ordinary asynchronous tool handles; no MCP tasks extension is advertised. The SDK
owns protocol framing, schemas, lifecycle, headers and resource templates.

Local clients must send a Content-Length for POST requests; requests larger than
1 MiB, browser Origins, invalid hosts and missing/wrong credentials are rejected.
Only loopback is bound. There is no automatic remote exposure or stdio launcher.

## Agent workflow

1. `list_models` returns model-row IDs, names and readiness diagnostics. IDs select
   one configured model/channel pair, including when provider model names repeat.
2. `get_model_schema` returns supported parameter keys, typed choices/defaults,
   reference limits and numeric pixel constraints. Do not assume every model has
   separate resolution, aspect-ratio and quality controls.
3. `generate_image` accepts `requestId`, `modelId`, `prompt`, optional `parameters`,
   `references` and `defaults` (`model`, the default, or `saved`). Example arguments:

   ```json
   {
     "requestId": "my-workflow-image-001",
     "modelId": 7,
     "prompt": "A blue bird in watercolor",
     "parameters": {"quality": {"kind": "choice", "value": "high"}},
     "references": [{"path": "/Users/me/References/bird.png"}]
   }
   ```

   This example is valid only if that model schema advertises the quality choice.
   Omit references for text-to-image. A reference can instead be
   `{"taskId":"previous-task-id","outputId":0}` for a registered MCP output.
   Parameter values use existing GenerationValue JSON: choice/size strings,
   integer/decimal numbers, booleans, or `{"kind":"unset"}` / `{"kind":"auto"}`.
   Overrides do not edit workbench drafts. Ordinary references resolve to editImage
   or subjectImage according to the existing wire contract; routing stays in the
   dispatcher, including image-edit API selection.
4. Poll `get_generation` with the returned `taskId`. Responses contain durable
   status, effective parameters, output paths/resource URIs, dimensions, MIME types,
   warnings and structured errors. A failed generation is data in a successful
   status lookup. Invalid tool operations return `isError: true`.
5. `read_generation_image` returns a 1024px JPEG preview by default, or the original
   with `preview: false`. Returned dimensions describe the returned image, including
   a resized preview. Original bytes are also readable through
   `joycai://generations/{taskId}/images/{outputId}` resources. No arbitrary file-read
   tool is provided. Missing/moved output files are explicitly unavailable.
6. `cancel_generation` retains completed outputs. Cancellation does not guarantee
   upstream cancellation or a refund. A disconnected client can reconnect and poll.

## Persistence and boundaries

`GenerationSubmissionService` is an injected service under `services/tasks/`.
`ImageMcpServer` under `services/mcp/` exposes it. `McpServerState`, owned by AppState,
controls startup after settings restoration. Services do not import state or UI.
The queue and its LLM facade use the same injected database, including usage writes.
Existing production singleton logging is preserved.

Schema v50 adds `tasks.task_error`, `tasks.warnings`, and `mcp_requests`.
The request-key/digest row and pending task are inserted in one transaction before
queue publication. Keys are shared by all authorized clients, so use globally
unique workflow IDs. Same key and arguments return the existing task; changed
arguments fail. Keys are retained for the database lifetime even after history
removal, so removal cannot trigger another paid generation. Only a deliberately
new request ID or an explicit retry in the app requests another generation.
No promise of exactly-once execution at an upstream provider is made.

The processing state is persisted before any provider call, so a failed write
cannot leave billed work marked pending for replay. Each delivered output is
persisted before its result event. Failure/cancellation
retains those paths. Restart marks interrupted image work failed with an
`interrupted` error instead of resubmitting a potentially billed request; pending
work resumes through the normal queue. `get_generation` reads stored tasks rather
than the limited in-memory history. Existing provider billing/retry rules remain
in LLMService.

References are checked against canonical allowed directories, decoded and copied
into `mcp-inputs/<task-id>/` under the app data directory before acceptance. A saved
MCP output can be reused without adding its folder to the input allowlist. Inputs
are limited to 16 files, 20 MiB each and 64 megapixels across all animation
frames, further narrowed by the selected model. Frame rectangles must fit the
canvas before decoding; previews decode only the first frame. Replaced root
symlinks grant no new access, and missing roots do not block other approved roots
or registered outputs. The original read limit is also 20 MiB. Up to 16 acceptance calls
can wait; a queue containing 100 pending/running tasks refuses additional work.
Staged files remain local with task history; they are not included in backups.

MCP tokens, activation, allowed roots and port are local settings: export redacts
them and import preserves local values rather than accepting grants from a backup.
Task results expose sanitized error codes/messages, never channel credentials or
raw task logs. Provider errors expose stable summaries and HTTP status codes,
never upstream message bodies: providers can echo credentials in encodings that
a string redactor cannot reliably remove. Raw details remain in local task logs.

## Verification

`test/services/mcp/image_mcp_server_test.dart` connects the real Dart SDK client to
the listener and a local fake provider. It covers both protocol generations,
text/image-edit requests, resource reads, reconnect/replay, invalid inputs,
cancellation, provider errors, partial streamed results and saved defaults.
Regression coverage also includes root symlink replacement, missing roots, image
frame budgets, preview dimensions, token revocation, host rejection and failed
processing-state writes before provider submission.
Persistence and lifecycle tests cover migration, atomic acceptance, interrupted
work, history removal, token rotation, backup redaction and port conflicts.
The connectivity screenshot matrix covers 390/834/1024/1440 light/dark. These are
macOS-hosted renders. Format, static analysis, 3,183 non-screenshot tests (9 skipped),
11 connectivity renders, 32 component-gallery renders and a macOS debug build
passed. Windows/Linux packaging and paid live providers require separate native
smoke tests.

Protocol references: [Streamable HTTP](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)
and [tools](https://modelcontextprotocol.io/specification/2026-07-28/server/tools).
