# Windows Store AI safety acceptance (WIN-04)

Reviewed 2026-11-08. **Release blocked; preparation builds only.** This is a
source/automated acceptance record, not a provider certification or installed
MSIX test. No live generation, real credentials, or paid calls were used.

Microsoft's [Store policies, section 11.16](https://learn.microsoft.com/en-us/windows/apps/publish/store-policies#1116-live-generative-ai-content)
require safeguards for live generated content. Request parameters, consent to
transfer data, and provider brand names do not establish output safety. The
existing Mac safety assessment remains open independently.

## Route dispositions

Every `WireProtocol.id` is listed below; an architecture test detects omissions
when the dispatcher gains a route. **Blocked** means the Windows Store production
release is blocked, not that the running preparation app disables this route.
All rows need evidence for the actual endpoint/model and the advertised markets,
including refusal, successful output, streaming, and returned media. No row has
completed that acceptance. Rows describe client behavior, not claims about the
quality of a provider's moderation.

| Route ID | Client controls / provider signals | Can output reach UI without a local content check? | Disposition |
| --- | --- | --- | --- |
| `openai-chat` | Normalizes finish/refusal signals; Gemini compatibility thresholds constrained, but relays may ignore them | Yes, text/image chunks can precede terminal status | Blocked |
| `openai-responses` | Parses refusal/incomplete/error events; no shared output classifier | Yes, streamed deltas/tool results | Blocked |
| `anthropic-chat` | Parses Messages events and provider errors; no shared output classifier | Yes, streamed text/tool results | Blocked |
| `gemini-chat` | Four adjustable categories constrained to low/medium; prompt/finish block signals parsed | Yes, earlier chunks cannot be recalled by a later block | Blocked |
| `midjourney` | Proxy job statuses/errors; no verified moderation contract for arbitrary proxy | Yes, returned image/preview URLs | Blocked |
| `dashscope-chat` | Provider errors/finish metadata; no shared output classifier | Yes, streamed text/multimodal results | Blocked |
| `openai-images` | Provider errors parsed; partial previews are separate from saved final images | Yes, preview events are emitted before completion | Blocked |
| `chat-image` | Uses selected chat wire; inherits that wire's controls and relay limitations | Yes, embedded/remote images | Blocked |
| `xai-images` | Provider errors parsed; no shared output classifier | Yes, successful image results | Blocked |
| `gemini-imagen` | Empty/filtered prediction cannot become a decodable success; four Gemini sliders do not apply | Yes, successful prediction images | Blocked |
| `gemini-image` | Uses Gemini generateContent with constrained thresholds and block signals | Yes, earlier image/text chunks | Blocked |
| `dashscope-images-sync` | Provider errors parsed; no shared output classifier | Yes, successful image results | Blocked |
| `dashscope-images-async` | Submission/poll status and errors; no shared output classifier | Yes, completed job images | Blocked |
| `minimax-images` | Provider errors parsed; no shared output classifier | Yes, successful image results | Blocked |
| `ark-images` | Provider errors parsed; no shared output classifier | Yes, successful image results | Blocked |
| `openai-videos` | Job status/errors; no shared output classifier | Yes, downloaded completed video | Blocked |
| `xai-videos` | Job status/errors; no shared output classifier | Yes, downloaded completed video | Blocked |
| `gemini-veo` | Filtered empty completion reports raiMediaFilteredReasons; four Gemini sliders do not apply | Yes, successful video results | Blocked |
| `dashscope-video` | Job status/errors; no shared output classifier | Yes, completed video URLs | Blocked |
| `minimax-video` | Job status/errors; no shared output classifier | Yes, completed video results | Blocked |
| `minimax-h3-base-video` | Local/custom model job API; no verified moderation contract | Yes, completed video results | Blocked |

Assistant streaming, delegated agents, compaction, prompt refinement, and AI rename
use the selected chat route. OpenAI Image Batch uses the image request/job path,
not Gemini's four-category payload: those sliders are not a Batch moderation
control. Batch results and GPT image previews have no independent local safety
classifier. MCP and resumed/retried queue tasks use the same service/protocol
boundaries; MCP authentication cannot grant sharing permission or prove safety.

The relevant source is `lib/services/llm/protocols/`, routed only by
`llm_dispatcher.dart`. In particular, `gemini_payload.dart` normalizes thresholds
and block reasons, `openai_chat_payload.dart` emits the compatibility fields,
`openai_images_protocol.dart` emits `imagePreview`, and
`gemini_veo_protocol.dart` handles filtered empty video completions.

## Custom endpoints and transport decision

Unverified custom, relay, and local endpoints are **not accepted for production
Windows Store release**. Do not approve one by vendor label, model name, HTTPS,
or user consent alone. Either verify its actual controls and all enabled output
paths, or enforce an explicit restriction before releasing. Since official
endpoints also lack completed per-route acceptance, this change blocks the whole
production packaging path rather than inventing a supposedly safe allowlist.
`build_windows_store.py --config ...` fails before staging or building. There is
no command-line override. Removing the gate requires a reviewed code change with
completed evidence or implemented route restrictions. `--preparation` continues
to produce an unsigned test-identity artifact labelled NOT FOR SUBMISSION.

Current AI transport permits HTTP after explicit consent. Remote HTTP can expose
prompts, media, credentials and proxy credentials; consent does not encrypt them.
Production acceptance requires HTTPS for remote AI/result transfers and a reviewed
proxy transport policy. Deliberate HTTP loopback integrations must remain possible
with explicit recipient consent; localhost exceptions must not authorize arbitrary
LAN/remote hosts or automatic redirects. This is a **release requirement still
owed**, not a claim that a runtime HTTPS restriction has been implemented. Direct
GitHub and Mac behavior are unchanged. No external moderation service is added:
that would itself introduce a recipient and require disclosure/consent.

## Sharing and reporting evidence

`LLMModelConfig.createClient` gates every send, disables automatic redirects, and
rechecks revocation immediately before transmission. Tests cover first use,
changed origin/scheme/port/proxy, restarts, denied persistence, concurrent prompts,
revocation on an existing lease, aborted sends, real loopback redirects, result
downloads, and terminal MCP failure mapping. Import/backup tests exclude consent
records. Already transmitted data/accepted jobs cannot be recalled by revocation.

WIN-04 adds HTTP multipart upload, polling, resumed-client, and result-fetch
revocation checks at that common client boundary. These are synthetic transport
checks, not proof of installed queue/MCP lifecycle behavior. The Gemini payload
matrix exercises native text/image and compatibility stream/nonstream paths with
legacy, malformed and strict values in Store and direct modes. Existing settings
tests cover saved values/reload and the acknowledgement-only editing control.

Reporting uses `mailto:joycai@joycai.cn` with no subject/body/attachments. Widget
tests exercise launch success, false return, exception, and clipboard fallback.
No report is sent by the tests. Actual Windows mail-handler/clipboard behavior
still needs installed testing. On 2026-11-08 the maintainer confirmed use of this
address and the existing maintainer review/response procedure. Mail delivery and
ongoing monitoring were not independently tested; the procedure is recorded in
[content safety](../architecture/content-safety.md#content-concerns).

## Release evidence still required

1. Approve the final enabled route/endpoint/model set, demonstrate controls with
   agreed safe fixtures and a separately authorized test account/budget, and
   restrict routes whose controls cannot be established. Include previews and
   streaming before completion, not just final responses.
2. Implement and test the remote transport requirement and deliberate loopback
   exception without changing direct/Mac behavior unintentionally.
3. Maintain monitoring of the confirmed reporting destination using the existing
   maintainer procedure; verify mail-handler behavior during installed acceptance.
4. In an isolated installed MSIX, exercise first use, changed recipients, revoked
   queued/retried/resumed jobs, Batch and MCP, and reporting with/without a mail
   handler. Record artifact hash, Windows version and results.
5. Rebuild the exact candidate with the pinned SDK after these changes; retain
   direct-mode and Mac regression evidence. WIN-04 remains open until then.

## Automated validation (2026-11-08)

- Format: 941 files, zero changes; analyzer: `No issues found!`.
- Full non-screenshot suite with native DPAPI enabled, `--concurrency=2`:
  **3552 passed, 5 skipped** (`build/win04-regression.log`).
- Direct-distribution safety/consent/reporting/matrix tests: **32 passed**
  (`build/win04-direct.log`). Store/default equivalents passed in the full suite.
- Python packaging guards: **6 passed**, including a real CLI invocation that
  rejects production mode before reading identity or invoking an SDK.
- Both workflow YAML files parsed; `git diff --check` passed.
- No `lib/`, macOS native, dependency, default MSIX, or GitHub release workflow
  changes in this batch. No UI changed, so screenshots were not regenerated.
  No new MSIX was built or installed; the preceding WIN-03 preparation artifact
  remains prior-build evidence, not a new candidate. Local Flutter is 3.47.9;
  remote pinned-3.47.8 CI and native Mac compilation were not run in this batch.
