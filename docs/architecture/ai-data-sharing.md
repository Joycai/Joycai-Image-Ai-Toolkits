# AI data sharing consent

MAS-04 implements the explicit permission boundary described in Apple's
[App Review Guideline 5.1.2(i)](https://developer.apple.com/app-store/review/guidelines/#data-use-and-sharing)
(checked 2026-11-05). It is an application permission, separate from directory
bookmarks, API credentials, MCP authentication and App Tracking Transparency.
It applies to every distribution/platform, not just the Mac App Store build.

## Boundary and scope

`LLMModelConfig.createClient()` wraps each pooled-client lease in a consent gate.
Every `send`, including retries, polls, streams, multipart uploads and result
fetches, checks `AiConsentService` before the underlying client can transmit.
Connection reuse never reuses an authorization check. All 20 current protocol
files that construct a client use this entry point. Do not call `buildClient` or
`LLMClientPool.take` directly from a protocol or feature.

The SHA-256 scope key uses recipient-key format 2: actual request origin,
configured service origin and proxy origin (scheme/host/port). Routes, vendor
labels and credentials do not change the disclosed parties and reuse consent.
Legacy route-keyed records are matched by these same stored origins, with a
remembered denial taking precedence over a grant. A changed origin requires fresh
permission. The disclosure and settings namespace remain version 1 because the
data categories and purposes are unchanged. Records contain no credentials,
request bodies, signed URLs or query parameters.
Model names and preset labels never establish the recipient's identity. The UI
names known official hosts using the existing platform registry; other hosts are
shown as custom, with their actual origin always visible.

HTTP automatic redirects are disabled. A 3xx response fails through the existing
protocol error handling instead of silently forwarding data to an unchecked
recipient. Configure the final API endpoint; provider/CDN flows that require
redirects need an explicit consent-aware redirect implementation before they can
be supported. No arbitrary external redirect is currently followed.

## Covered entry paths

| Entry | Shared enforcement |
| --- | --- |
| Workbench image/video, prompt refinement, queued work and manual retry | LLMService → dispatcher → protocol client |
| Image Batch upload/create/reconcile/poll/results | ImageBatchSession → OpenAIImageBatchProtocol client |
| Assistant, delegated turns, compaction and AI rename | LLMService → protocol client |
| Channel/model discovery and probes | Dispatcher protocol clients |
| Restored image/video operations | Existing persisted job identity → protocol polling client |
| MCP generation | Existing generation/queue services; only the local app UI can grant consent |
| Finished video downloads | LLMService.downloadClientFor → same guarded client |

The ordinary website downloader, font downloads and opening the policy in a
browser are separate user-requested non-AI operations, not governed by this gate.
MCP receives a terminal `consentRequired` task error when denied; there is no
MCP tool to grant permission. Denial is explicitly non-retryable in LLMService.

## Lifecycle and concurrency

The host loads the local decisions before starting services and resumes pending
jobs only after the first app frame, when a local consent dialog can be shown.
Missing UI, unreadable storage or malformed decisions never implicitly allow a
send. A failed load can be retried. No production test/network bypass exists;
test runners install an explicit in-memory consent presenter for existing mock
protocol fixtures, while consent tests replace it with isolated real decisions.

Unknown recipients queue dialogs; simultaneous requests for a scope share the
first persisted decision. Already authorized recipients continue independently
of an unrelated unanswered dialog. Grants cannot be used until storage succeeds.
Only explicit allow/decline choices are persisted. Dismissing a dialog or a
missing presentation context blocks the current send without remembering a
refusal, so a later request can prompt again. Existing remembered refusals still
require the settings action before another prompt.
Image result resolution preserves `AiConsentRequired` instead of retrying it or
turning it into an invalid-image error. The localized denial identifies the
recipient origin; API diagnostics distinguish remembered denial, dismissal,
missing presenter and changed decisions without recording credentials.
A generation counter invalidates waiting requests when the user revokes/resets
permission; the client checks the current decision again immediately before send.
Closed/aborted client requests cannot transmit after a delayed acceptance.

Revocation blocks future sends, including existing pooled clients. It cannot
recall transmitted bytes, stop an already accepted upstream job or delete data
from the recipient. Canceling an upstream job is itself a request and cannot
bypass revoked consent. In-flight transfers may complete. Existing request/job
timeouts still apply while a prompt is open; a task that timed out must be retried.

Settings > About groups route-specific decisions by their disclosed recipient,
service and proxy. Revoke blocks every existing scope in that group. “Ask next
time” clears those decisions so the next request prompts; it never grants access
or automatically retries stopped tasks. A persistence error leaves grants blocked
in memory and shows a save error; retry saving before quitting.

## Storage and import

Decisions live in DatabaseService settings key `ai_data_sharing_consent_v1`.
Settings exports redact it and restore ignores incoming values, even crafted
nonempty ones, preserving this installation's existing decisions. Whole-library
installation migration removes it from the imported database. Keys remain scoped
to disclosed origins, so an imported channel cannot repurpose a local decision for
another address. No database schema version change is needed.

When changing disclosure categories/purposes, increment the version in both the
scope key and setting namespace and define the import exclusion for the new key.
Do not treat acceptance of a policy page or entry of an API key as consent.
