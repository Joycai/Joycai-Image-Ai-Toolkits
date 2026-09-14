# ② OpenAI Responses — protocol facts

> Wire facts for `protocols/openai_responses_protocol.dart`. How the app uses
> them (and which ones fail silently) is in
> [`../architecture/llm-three-layer.md`](../architecture/llm-three-layer.md),
> section 「② OpenAI Responses 的不变量」. Overview of the four families:
> [`landscape.md`](landscape.md) §3.

Sources, all read 2026-09-14:

- **[SDK]** the OpenAI Python SDK's generated types
  (`github.com/openai/openai-python`, `src/openai/types/responses/*.py`,
  `types/shared_params/reasoning.py`), generated from OpenAI's OpenAPI spec.
  `platform.openai.com/docs/api-reference` answered 403 to the fetcher, so
  quotes are from the SDK types.
- **[xAI]** `docs.x.ai/docs/api-reference` (Responses section).
- **[Std]** the agent-architecture standard (`02-protocol-differences.md` §7,
  `03-reasoning.md` §7, `06-errors-probing-observability.md` §4.1,
  `01-provider-layering.md` §9, `11-pitfalls.md` group G) — measured on two New
  API relays (GPT-5.4/5.5/5.6) and xAI's own host, 2026-09. Measured facts
  win over documentation where the two disagree.

## 1. Request

`POST {base}/responses` — the same base (`…/v1`) and `Authorization: Bearer`
as Chat Completions.

| Field | Fact | Source |
| --- | --- | --- |
| `instructions` | "A system (or developer) message inserted into the model's context." | [SDK] |
| `store` | "Whether to store the generated model response for later retrieval via API. Defaults to true when omitted." | [SDK] |
| `include` | Allowed values include `reasoning.encrypted_content`. | [SDK] |
| `reasoning.effort` | "Currently supported values are `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, and `max`." xAI: `none`, `low`, `medium`, `high`, `xhigh`; "The accepted values and the default used when unspecified vary per model." | [SDK] [xAI] |
| `reasoning.summary` | "One of `auto`, `concise`, or `detailed`." | [SDK] |
| `max_output_tokens` | "An upper bound for the number of tokens that can be generated for a response, including visible output tokens and reasoning tokens." | [SDK] |
| `stream` | "If set to true, the model response data will be streamed to the client as it is generated using server-sent events." | [SDK] |
| function tool | `name`, `parameters`, `strict` (all `Required`), `type: "function"`, optional `description`. `strict`: "Whether strict parameter validation is enforced for this function tool." | [SDK] `FunctionToolParam` |
| `tool_choice` (named) | `{type: "function", name}` — "Use this option to force the model to call a specific function." | [SDK] `ToolChoiceFunctionParam` |

Input items:

| Item | Shape | Source |
| --- | --- | --- |
| message | `{role: "user"\|"assistant"\|"system"\|"developer", content: str \| input parts}` — content "Can also contain previous assistant responses." | [SDK] `EasyInputMessageParam` |
| image part | `{type: "input_image", image_url, detail}` — `image_url`: "A fully qualified URL or base64 encoded image in a data URL."; `detail`: "One of `high`, `low`, `auto`, or `original`. Defaults to `auto`." | [SDK] `ResponseInputImageParam` |
| function call | `{type: "function_call", call_id, name, arguments}` — `arguments`: "A JSON string of the arguments to pass to the function." | [SDK] `ResponseFunctionToolCallParam` |
| function result | `{type: "function_call_output", call_id, output}` | [SDK] `FunctionCallOutput` |

Measured ([Std]):

- Leaving `instructions` out makes a New API relay inject its Codex system
  prompt (4.4K–9K input tokens). Send it every time, `""` included.
- Leaving `strict` out makes the official host promote the tool to strict.
  Send `strict: false` for the app's non-strict schemas.
- xAI returns no `encrypted_content` without
  `include: ["reasoning.encrypted_content"]`. A replay without it still
  answers correctly; only reasoning continuity is lost.
- Grok 4.5/4.6 reject `effort: "none"`, and every Grok rejects `max`, with a
  400. GPT-5.4 rejects `max`.
- Relays have echoed a different effort than was sent: `max` came back as
  `none` with 0 reasoning tokens, and `none` came back as `medium`.
- One relay ignored `max_output_tokens`.
- Unknown top-level keys are ignored by OpenAI and xAI.

## 2. Stream events

Event names, from the SDK's `ResponseStreamEvent` union ([SDK]). Fields are
quoted from each event class:

| Event | Fields read |
| --- | --- |
| `response.output_text.delta` | `delta` ("The text delta that was added."), `output_index`, `item_id`, `content_index` |
| `response.reasoning_summary_text.delta` | `delta` ("The text delta that was added to the summary."), `output_index`, `summary_index` |
| `response.reasoning_text.delta` | `delta` |
| `response.function_call_arguments.delta` | `delta`, `output_index` |
| `response.function_call_arguments.done` | `arguments` ("The function-call arguments."), `output_index`, `item_id` |
| `response.output_item.added` / `.done` | `item` ("The output item that was marked done."), `output_index` |
| `response.completed` / `response.incomplete` / `response.failed` | `response` (the full Response object) |
| `error` | `code`, `message`, `param` |

Terminal response ([SDK] `Response`):
`incomplete_details.reason` is one of `max_output_tokens`, `max_messages`,
`content_filter`, `steered`. `error` is "An error object returned when the
model fails to generate a Response."

Usage ([SDK] `ResponseUsage`): `input_tokens`,
`input_tokens_details.cached_tokens` ("retrieved from the cache" — a subset
of input), `input_tokens_details.cache_write_tokens`, `output_tokens`,
`output_tokens_details.reasoning_tokens` (a breakdown of output),
`total_tokens`.

Measured ([Std]):

- The `event:` line repeats the payload's `type`, so only `data:` lines need
  reading.
- xAI sends `[DONE]` after `response.completed`, even though the protocol has
  no such line.
- Text deltas carry an `obfuscation` padding field, and sending
  `include_obfuscation: false` had no effect. Read only `delta`.
- Some relays drop `item_id` from delta events, so group by `output_index`.
- Streams sometimes end without a terminal event.

## 3. Replay under `store: false`

The next tool round's `input` = history + the previous response's output
items (reasoning / function_call / message) + the `function_call_output`s.
Measured on GPT-5.4/5.5/5.6 and Grok ([Std] 02 §7.3), all four of these
answer 200 and correctly: replaying the items verbatim, dropping the reasoning
items, dropping `encrypted_content`, and sending bare `function_call`s. A
missing replay therefore produces no error; the cost is quality only. Replay
the items verbatim, and only to the model that produced them.

`message` items returned in output carry `id` and `status`
([SDK] `ResponseOutputMessageParam`); they are replayed as received. Prior
assistant *text* that has no captured item goes back as an easy input message
with string content.
