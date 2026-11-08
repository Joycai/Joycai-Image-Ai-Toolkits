# Content safety (MAS-05)

Windows Store WIN-04 has a separate [route acceptance matrix](../testing/windows-store-ai-safety.md).
Its production packaging is blocked pending route/transport/reporting acceptance;
this does not alter the Mac App Store or direct build behavior described here.

## Implemented boundary

The Gemini safety controls now live in Settings > Application, not in the
workbench generation dialog. Every distribution defaults new/missing/invalid
settings to `BLOCK_MEDIUM_AND_ABOVE`. The four sliders initially display saved
values but cannot be edited until the user acknowledges the warning. Cancel or
closing the warning leaves them locked; acknowledgement only unlocks this mounted
section, never changes thresholds, sends a request or retries a task. Leaving the
section and returning requires acknowledgement again.

Store-configured builds (`JOYCAI_DIRECT_DISTRIBUTION=false`, the default) expose
only `BLOCK_LOW_AND_ABOVE` and `BLOCK_MEDIUM_AND_ABOVE`. `SafetySettings.normalize`
also enforces that set during settings load/save and REST payload construction.
Thus old/imported settings, queued task snapshots and MCP generation cannot send
`BLOCK_ONLY_HIGH`, `BLOCK_NONE` or `OFF` via the supported Gemini payload builders.
Old database values need not be rewritten: every use is normalized; a subsequent
edit persists normalized values. Unknown categories are dropped.

Direct builds expose all five values after acknowledgement. Valid existing
choices are retained and shown, including old permissive choices; the new medium
default does not silently overwrite an explicit saved choice. This is an editing
warning, not an authentication/authorization boundary or a retroactive task edit.
A direct task snapshot can retain its earlier choices. Changing the setting does
not rewrite existing tasks or restart failed work.

### Building direct packages

`store: false` in `msix_config` controls packaging, not Dart's distribution mode.
The default `dart run msix:create` rebuilds Windows, so `windows_build_args` in
`pubspec.yaml` also passes `--dart-define=JOYCAI_DIRECT_DISTRIBUTION=true`.
Without that argument a sideload MSIX still uses the Store safety policy.
When using `--build-windows false`, first compile with that same Dart define;
packaging cannot change the policy already compiled into an executable.

For macOS direct packages, run
`bash build_script/build_macos.sh --distribution direct`. This pairs the Dart
define with the native non-sandbox configuration. A plain `flutter build macos`
uses the default sandbox/Store configuration and keeps the two-value policy.
Rebuild and reinstall old packages to apply the correct distribution mode.
Previously saved permissive values that were already overwritten by a Store-mode
edit must be selected again; the build flag cannot restore overwritten values.

## What these settings do not prove

These four thresholds are Gemini request parameters, not an application-level
text/image/video classifier. Veo and Imagen do not use this parameter list. Other
providers have their own controls and defaults; this change does not infer or
claim equivalent protection for them. Gemini-via-OpenAI compatibility payloads
also normalize the outgoing list, but a relay can ignore it (the existing New API
integration documentation explicitly notes this). No endpoint allowlist or new
third-party moderation upload was introduced.

Apple's [Review Guidelines 1.1 and 1.2](https://developer.apple.com/app-store/review/guidelines/)
require addressing objectionable content and, where applicable, user-generated
content abuse. A warning alone does not establish compliance. Gemini's
[safety settings documentation](https://ai.google.dev/gemini-api/docs/safety-settings)
defines medium as blocking medium/high likelihood and low as blocking low or
higher likelihood. Neither is a guarantee that every harmful result is blocked.
Sources checked 2026-11-05.

## Content concerns

Settings > About provides a dedicated content concern section naming Joycai and
`joycai@joycai.cn`. Compose email opens the user's mail application with only the
address; Copy email remains available when no mail handler exists. It does not
submit a report automatically or attach prompts, credentials, files or metadata.
Four-language instructions ask for the issue, app version and service/model,
and ask users not to send keys, private files or illegal imagery.

Handling procedure for the maintainer:

1. Review incoming concerns privately; request only the minimum lawful information
   needed to identify the affected service/feature. Do not request secrets or illegal media.
2. Distinguish upstream content filtering from client behavior (bypasses, retries,
   unexpected display or misleading controls). Reproduce with synthetic safe data.
3. For client defects, track a sanitized issue and fix/test the affected path.
   For provider issues, direct the reporter to the provider's appropriate reporting
   channel and assess whether the integration should be restricted.
4. Reply with the action taken or remaining limitation. There is no automated
   mailbox processing, response-time guarantee or upstream deletion capability.

The app does not run a public user feed or an account-based social service; adding
a fictitious “block user” control would not address its actual generation risks.
The applicability of the full UGC requirements still needs review against the
final product and supported services.

## Remaining MAS-05 work

- Verify filtering/refusal behavior per supported provider, including text, image,
  video, streaming/preview, Batch, assistant and MCP paths. Do not treat the Gemini
  parameter constraint as universal enforcement.
- Assess the treatment of returned content and custom/relay services before final
  submission; add controls appropriate to demonstrated gaps.
- Exercise the final signed store build's settings and mail-handler fallback using
  isolated data. Fill age-rating answers from actual capabilities and evidence.
- MAS-05 remains open until these cross-provider and release checks are resolved.

## Verification (2026-11-05)

- Format: 922 files, zero changes; analyze: No issues found.
- Full non-screenshot suite: 3503 passed, 10 skipped. Store/default and direct
  targeted runs each passed 7 tests, covering malformed/legacy maps, native and
  compatibility Gemini payloads, saved values/reload, warning cancellation,
  acknowledgement without changing values and locking again after remount.
- 27 store-mode screenshots plus 3 direct-mode narrow screenshots passed;
  inspected settings at 390/834/1024/1440 in both themes, narrow English/Japanese/
  Traditional Chinese warnings, and representative report views. No new overflow
  appeared in the render logs. Baseline generation-dialog screenshot retained in
  `build/mas05-baseline/`; store renders in `build/mas05-store-screenshots/`.
- GitHub non-store Windows/Linux/Android builds now explicitly set the direct
  define, matching the existing macOS direct script. CI adds direct-mode safety
  tests alongside the existing file-access checks. Both workflows pass actionlint.
- macOS store-configured Release build succeeded (81.2 MB); not launched, uploaded
  or submitted for review. This compile check is not native acceptance.
- Verification uses isolated fixtures; no real AI calls or user-data mutations.
  Native mail-handler behavior, Windows/mobile installation and per-provider
  moderation/refusal quality were not exercised.
