# Execution plan: modular image/video parameters and parameter UI

Date: 2026-10-03 (Asia/Shanghai)
Status: implemented and verified; historical commit/retirement pending
Baseline: repository version 4.28.4, commit 989e6b6; branch codex/modular-generation-parameters

## Resume after compaction

The user requested a review of differences in image/video inputs across models and
providers, accepted the proposed schema architecture, and explicitly added that the
parameter-setting UI must be easy to extend and change. This document captures both
parts. The user subsequently authorized execution on 2026-10-03 and required design continuity; the duplicate Grok Auto issue was added to scope.
When the user subsequently asks to execute, follow the phases below without routine
permission stops. Keep this file updated with completed phases, decisions and remaining
work so another compacted session can resume without reconstructing the discussion.

Desired result: adding a supported model or deployment normally changes declarations
and wire encoding, while adding or changing a UI editor changes one reusable editor.
Both image and video use the same form machinery, with specialized media/size editors.

No code was changed during the review and no tests or live upstream requests were run.
Findings are from repository code and maintained notes, not a fresh upstream API audit.
Original design frames were unavailable; visual baseline review is still required.

## Required guidance

Read AGENTS.md and these notes before implementation:

- docs/architecture/llm-three-layer.md
- docs/architecture/ui-design-workflow.md
- docs/architecture/design-tokens.md
- docs/architecture/keyboard-shortcuts.md when changing focus/keyboard behavior
- docs/ui-screenshot-harness.md
- docs/plans/README.md and plans/README.md (completed work and intentional behavior)

Apply joycai-ui-design for the UI and joycai-l10n for user-visible copy. Read applicable
Dart/Flutter test and analysis skills when used. Follow repository layering, database
injection, immutable state notification and fake-clock database rules. Do not spawn
agents unless the user or applicable instructions explicitly authorize delegation.

Use PowerShell on this Windows host. Run dependent commands separately and verify
exit codes. Preserve unrelated changes, local settings and .claude/worktrees.

## Scope and boundaries

Deliver shared generation schemas, typed drafts/requests, validation, profile modules,
parameter preference migration, task JSON compatibility, and modular parameter UI.
Migrate every existing image/video generation route, including generation through chat.
Keep the existing provider/protocol/model architecture and protocol choices.

Do not add providers, new generation endpoints, new TaskTypes, a remote plugin system,
a general-purpose form language, new pricing formulas, or a theme redesign. Do not
reinterpret deliberate animation/layout decisions. Unknown upstream behavior remains
explicitly unverified; verify official documentation before adding new API claims.
Existing documented debt such as Seedream's unused aspect ratio is addressed where it
falls directly within conditional parameter behavior. Unrelated billing/network debt
remains in the ledger.

## Review evidence and starting points

| Concern | Current code | Implication |
|---|---|---|
| String values and presentation mixed with constraints | lib/services/llm/param_spec.dart | Difficult to extend types, omission policies and dependencies |
| Model tables and version matching | model_capabilities.dart, model_capability_tables.dart, model_descriptor.dart, model_family.dart | Preserve existing capability detail while separating profile data |
| Coarse serving-protocol compatibility | ModelDescriptor._familyServedBy groups several video protocols under openaiVideo | Family equality does not prove parameter compatibility; add route-pair tests |
| Family-wide parameter memory | lib/state/app_state_workbench.dart | Different model versions/routes share and overwrite preferences |
| Image/video UI duplication | screens/workbench/model_selection_section.dart and widgets/video/video_param_controls.dart | Separate control switches, labels and span rules; image excludes sliders, video excludes customSize |
| Inputs accepted then discarded | video_config_panel.dart, xai_videos_protocol.dart, minimax_video_protocol.dart | Last frame unsupported on xAI; frames conflict with reference material |
| Mode-specific parameters | protocols/ark_payload.dart | Layers require one reference and ignore ratio; transparency forces PNG |
| Mixed task/runtime options | models/task_item.dart, services/tasks/task_executors.dart | Generation inputs, application metadata and cancellation share options maps |
| Existing strengths | image_size_rules.dart, image_size_vocabulary.dart, pure payload builders | Reuse these rather than rebuild them |

Other important consumers: llm_service.dart, llm_dispatcher.dart,
llm_config_resolver.dart, output_spec.dart, services/billing/spec_billing.dart,
workbench_config_panel.dart, widgets/video/video_model_section.dart,
widgets/size_picker/, state/workbench_ui_state.dart, batch submission and retry paths.
Locate all readers/writers before changing option keys; this list is not exhaustive.

## Target architecture

### Resolution and ownership

Resolve the effective contract for:

    stored model + provider deployment + effective wire protocol
    + generation operation + attachment metadata + parameter draft
                         -> ResolvedGenerationSchema

LLMDispatcher remains the only routing authority. It resolves the effective protocol
and supplies the model/profile and vendor declarations to a pure schema resolver.
Schema modules must not import the dispatcher back; avoid import cycles. Surface/tag
and protocol-pin semantics remain centralized. UI/state must never duplicate routing,
inspect model/vendor IDs, or call model-ID-only capabilities for a stored model.

Suggested organization under lib/services/llm/generation/ (names may be refined):

- generation_param.dart: typed semantic keys/values and parameter constraints
- generation_operation.dart: supported operations and media-role vocabulary
- generation_schema.dart: effective schema, input contracts and field states
- generation_schema_resolver.dart: composition from already resolved inputs
- generation_validator.dart: parameter/media validation and structured diagnostics
- generation_request.dart: typed immutable request and versioned JSON codec
- generation_profiles.dart plus profiles/: model profile registry and declarations
- legacy_generation_options.dart: temporary old-key/value compatibility adapter

Provider restrictions/dialects belong in vendors/ declarations. Wire-specific contract
and encoding belong with protocols/. Model-ID matching stays in the existing layer-3
classification/descriptor implementation, not in profile files or UI renderers.
Keep services Flutter-free where practicable. Pure data may live in services; do not
make models/ import services/ or Flutter. Change source-layout tests only for an actual
intentional architecture change, not to bypass their boundary checks.

### Parameters and profiles

GenerationParamSpec describes semantic identity, type, units, choices/ranges, required
state, and omission/default policy. Support booleans, integers, decimals, enums and
sizes as needed by existing routes. Keep specialized ImageSizeRules/Vocabulary and
model-specific pixel mappings; do not reduce them to a generic width/height range.

Distinguish unset (inherit upstream), an explicit value, an explicit upstream auto
value, and a required application default. Replace not_set/on/off string semantics
internally with typed representations. Legacy serialization adapters preserve existing
wire behavior during migration. Never replace all sentinel strings with null blindly:
DashScope size defaults and required MiniMax parameters have distinct semantics.

GenerationModelProfile declares supported operations, parameter constraints, defaults,
reference roles/counts and execution hints. Split declarations by model group/version;
reuse small parameter fragments where semantics really match. Preserve current
long-running/streaming capability behavior rather than move it without tests.

GenerationProtocolContract describes what a wire can represent. Vendor/deployment
restrictions can narrow that contract or explicitly declare a dialect. Compose a
checked effective schema; do not use unrestricted last-write-wins map merging.
An empty compatible set must produce an explainable unsupported configuration.
Protocol mapping must explicitly translate units and values where necessary.

Unknown model aliases receive the existing protocol fallback with an identified
confidence/source; do not pretend that fallback constraints are verified model facts.
Support an optional explicit capability-profile selection for aliases in the final
phase. This selection describes capabilities only; it cannot change routing or enable
an unsupported protocol. Store the user's profile choice, not derived capability copies.

### Operations and attachments

Profiles declare their supported subset of operations, for example:

- Images: text generation, editing, subject reference, layers, transparent editing
- Video: text generation, first-frame animation, first/last-frame animation, reference guidance

Names must distinguish semantic differences; MiniMax subject references are not canvas
editing. Some modes can be inferred unambiguously from media, others need a selector.
Do not expose unsupported modes just because the shared enum contains them.

Input contracts describe roles (source, reference, first frame, last frame, mask and
future media only when supported), counts, mutual exclusion, required inputs, accepted
file types and relevant dimensions/alpha requirements. Validation uses actual readable
attachment metadata; the transport rechecks encoded inputs before sending. Do not
silently turn an unreadable first frame into a text-only paid generation.

Cross-field examples that must work:

- xAI: last frame unavailable; first frame and reference images cannot coexist
- MiniMax: frames and reference material cannot coexist
- Seedream layers: exactly one source image; aspect ratio inactive
- Seedream transparency: PNG output fixed; validate documented source requirements
- Seedream group output: references and output count share the existing request ceiling
- Size/tier/ratio combinations: preserve existing documented model-specific rules

Use structured diagnostics (code, affected fields/roles, severity, safe formatting
arguments). Localize them in UI; log them for non-UI callers. Explicit conflicting input
blocks submission with a useful reason. Do not silently drop inputs, clamp explicit
values or change formats. For stale stored preferences, offer/reset to valid values
with a visible reason. Intentional effective defaults/fixed format are displayed before
submission, not introduced unexpectedly during payload encoding.

### Drafts, requests and task persistence

Keep the editable draft separate from the effective request. Inactive values remain in
the draft so switching modes back restores them, but are excluded from the request.
Expose whether a field is active, hidden, disabled, fixed, or invalid, with a reason.
Evaluate dependencies deterministically; reject cyclic declarations in registry tests.

GenerationRequest contains operation, prompt, role-tagged media references and typed
parameters. Runtime ExecutionContext holds cancellation, timeout and logging. Existing
task metadata such as retry settings, output paths/prefixes and prompt provenance stays
outside the generation parameter namespace. Do not persist callbacks, keys or headers.

Use versioned nested generation JSON within the existing TaskItem.parameters column.
Keep TaskItem's generic map for other TaskTypes. Legacy readers map old flat task keys
to the new request; preserve metadata and pending/retry/resume behavior. New tasks write
one authoritative generation representation, not two indefinitely diverging maps.
A database migration is needed only for a real schema change, with onCreate/onUpgrade
in lockstep; JSON evolution alone does not require a new database column.

Persist profile ID/version, effective protocol evidence and channel/model references
for new tasks. Resolve credentials at runtime. Revalidate queued requests against the
current compatible route before initial submission; if a route/configuration changed
incompatibly, fail clearly rather than send a different request. Define and test what
constitutes a compatible change. Resuming an accepted job skips generation validation
and resubmission: preserve operationName/operationSurface and existing billed-job
resume/cancel behavior. Snapshot output intent separately from actual output metadata.
Keep billing based on effective sent values and actual reported outputs/input counts.

Preferences use stored model row ID + effective protocol ID + operation. Schema version
belongs to migration/validation metadata, not an automatic preference reset key.
Seed new stores from legacy family keys without deleting legacy data until migration
is proven. Preserve raw drafts when temporarily incompatible; never overwrite another
model's values. Respect immutable state notifications and database injection.

## Modular UI brief

User task: configure a generation knowing which settings and media will actually be
used. Adding a model should not require a new panel; changing an editor should affect
both image/video forms consistently. Preserve the existing warm-stone theme, accents,
control glass, token scales, shell and primary Generate action.

Suggested location: lib/screens/workbench/widgets/generation_params/.
Image and video are one workbench feature, so these widgets initially stay under that
screen. Promote only genuinely cross-feature widgets to widgets/<domain>/ later.
Existing widgets/ui, glass and drag primitives remain independent of services/models.

Modules:

- GenerationFormController: pure draft/validation orchestration in services if reusable;
  observable ownership/binding in existing state. No persistent state owned by a panel.
- GenerationFormPresentation: Flutter-side field/group order, label/help tokens, editor
  choice, span/basic-advanced hints and deliberate profile presentation overrides.
- GenerationParamPanel/sections/field shell: shared assembly and responsive layout.
- ParamEditorRegistry: explicit constructor-injected map from editor kind to builder;
  no mutable global registration or provider-specific panel switches.
- Editors: enum dropdown, segmented, toggle, integer slider/input, decimal input,
  existing size picker adapter, and specialized editor modules as needed.
- GenerationMediaInputs: role-driven slots/drop zones and supported mode selection.
- GenerationParamTexts: shared localization mapping and diagnostic formatting.

An editor receives typed value, effective constraints, field state, labels/help/error,
and onChanged. It never reads a provider/model ID or performs database/network IO.
Semantic type is distinct from editor choice: an integer can use a slider, input or
presets. Unsupported editor declarations fail tests and give a visible fallback/error;
do not silently filter fields out as current panels do.

Example presentation declaration (illustrative API, not existing Dart code):

    ParamFieldPresentation(
      key: GenerationParam.durationSeconds,
      editor: ParamEditorKind.integerSlider,
      group: ParamGroup.output,
      order: 30,
      span: ParamFieldSpan.full,
    )

Keep existing hierarchy: model/request selection, applicable generation settings and
media, prompt, primary action. Use groups such as output/input/advanced only when they
help the existing panel; do not force extra navigation for the current small forms.
At mobile <600, tablet <1000 and desktop >=1000, adapt within available panel width;
field span hints cannot assume desktop width. Preserve narrow desktop platform behavior.

Specify empty/no-model, incompatible route, invalid draft, unavailable input, fixed
value, switching modes/models, submission, and running states. Preserve keyboard focus
when field conditions change where possible, expose semantic labels/units/errors, honor
reduced motion and mobile touch targets. Changing mode must not silently erase media;
retain the draft and explain/remove conflicts through a deliberate interaction.

## Execution phases and checkpoints

### Phase 0 — inventory and baseline

- [x] Record branch/commit, status and toolchain. Use codex/ if creating a branch.
- [x] Inventory every media route, capability table, option reader/writer, task producer,
      preference key, output-spec/billing consumer and existing regression test.
- [x] Create a route/profile matrix using repository facts, including chat-image,
      sync/async, model versions, protocol pins and unknown aliases.
- [x] Capture baseline relevant workbench screenshots; preserve PNGs outside the harness
      output directory before re-rendering. Inspect long locales and required widths.
- [x] Record known failures and unverified API facts; do not infer live endpoint support.

Checkpoint: this plan contains the actual inventory and baseline evidence before edits.

### Phase 1 — schema core and compatibility adapters

- [x] Add typed values, operations, media contracts, structured diagnostics and codecs.
- [x] Compose schemas from dispatcher-resolved protocol/model/vendor inputs.
- [x] Initially wrap existing tables and preserve current requests via legacy adapters.
- [x] Add pure tests for defaults/unset/auto, types, dependencies, composition and codecs.
- [x] Test model/protocol pairs, especially different video wires sharing openaiVideo.

Checkpoint: existing payload/routing tests remain green; no accidental request changes.

### Phase 2 — shared UI scaffold and first complete slice

- [x] Add shared panel, presentation, registry, text mapping and state bindings.
- [x] Reuse existing primitives and size picker through editor adapters.
- [x] Implement video attachment conflicts and Seedream operation-dependent field states
      end to end, including service validation for non-UI callers.
- [x] Make intended corrections explicit: no accepted then ignored last frame/ratio;
      no hidden reference dropping or unexpected PNG substitution.
- [x] Add all four locales and meaningful widget tests; render and inspect first slice.

Checkpoint: architecture is exercised by real image and video cases, not unused types.

### Phase 3 — request, task and preference migration

- [x] Separate generation requests from execution controls and application metadata.
- [x] Add versioned task JSON with legacy readers; migrate all producers and retries.
- [x] Migrate family memory to per-model/protocol/operation drafts conservatively.
- [x] Add route-change validation before submit and preserve accepted-job resume paths.
- [x] Preserve fee-group output specs, actual sent input counts and reported cost behavior.

Checkpoint: legacy pending tasks/settings load; restart/resume never submits twice;
new requests survive round trips and model changes cannot alter them unnoticed.

### Phase 4 — complete route and UI migration

- [x] Split existing model/version declarations into profile modules without ID sniffing
      outside allowed layer-3 files; make registry/vocabulary enumeration authoritative.
- [x] Migrate every existing image/video route and both parameter panels to shared forms.
- [x] Extract pure encoding helpers where needed; ensure encoder and validator agree.
- [x] Replace duplicate labels/control switches/span rules and old option parsing once
      all consumers are migrated. Keep documented legacy JSON readers as needed.
- [x] Add explicit capability-profile selection for aliases, with compatibility validation,
      model-editor persistence and localization; use a DB migration if a column is added.

Checkpoint: one editor implementation per UI type; model additions using existing types
require declarations and encoding only. No second routing table or capability truth.

### Phase 5 — verification and durable documentation

- [x] Complete the full acceptance matrix below and repository gates.
- [x] Inspect rendered screens, all affected themes and long localized labels.
- [x] Update llm-three-layer.md and UI workflow notes with final ownership/extension rules.
- [x] Add executed-round outcome, intentional differences and remaining debt to the ledger.
- [ ] Retire this one-time plan after implementation, preserving a committed historical
      reference under the repository convention. Do not delete the only uncommitted copy.

## Verification and acceptance

Use existing payload/routing tests as regression anchors, including:
wire_protocol_routing_test.dart, model_kind_protocol_pin_test.dart,
ark_images_payload_test.dart, seedream_capabilities_test.dart,
xai_image_capabilities_test.dart, minimax_payload_test.dart,
minimax_h3_base_payload_test.dart, dashscope_payload_test.dart,
openai_images_payload_test.dart, video_param_slider_test.dart,
veo_video_params_test.dart, video_input_images_test.dart,
video_poll_routing_test.dart and video_job_ended_test.dart.

Add meaningful coverage for:

- each registered profile/protocol pair and precise defaults/omission behavior;
- invalid types/ranges, mode dependencies, media conflicts and unreadable inputs;
- model/protocol/mode switching retaining drafts without sending inactive values;
- state list/object identity and localized diagnostics;
- one registry-rendered editor working in image and video, specialized size behavior;
- legacy task/preference codecs, new round trips, route changes and restart/resume;
- payload parity for unchanged cases; explicitly asserted corrected behavior;
- billing sees what was actually sent/reported, including ignored/defaulted input cases.

After every code change and before any commit, run required gates sequentially:

    dart format lib test tool
    flutter analyze
    flutter test -x screenshots

Analyze must print No issues found! Inspect formatting diffs for unrelated churn.
If ARB sources changed, run dart tool/merge_l10n.dart and only after success run
flutter gen-l10n before gates. Never edit generated localization files manually.

Run relevant screenshot harness files, extending fixtures for mode/conflict/invalid
states. Inspect 390/834/1024/1440 widths in light/dark, all four locales where labels
matter, and alternate accents. For shared control/color changes run component_gallery
across eight seeds and both brightnesses. Harness pass alone does not prove no overflow;
open images and inspect exception output. Native phone platform behavior needs separate
validation from narrow desktop screenshots. Measure UI performance with render_probe
if field/draft changes broaden rebuilds; avoid per-keystroke whole-shell notifications.

Live keys are not required for local refactor acceptance. If used for changed upstream
behavior, report exact verified scope and keep secrets out of fixtures, snapshots/logs.

## Progress and handoff log

- Implementation and verification completed; details and accepted limits follow below.
- Baseline renders: preserved in build/generation-baseline and visually inspected.
- Inventory/route matrix: recorded below; all existing routes use the shared dispatcher guard.
- Decisions or deviations during execution: append here with evidence and rationale.
- Remaining blockers: none established; sandbox helper failed during planning, so file
  commands used reviewed escalation. This is an environment issue, not a code finding.

### Execution started — 2026-10-03

User authorized execution and required visual continuity (themes, liquid glass,
light/dark, typography/font fallback). Current maintained design specification and
real Flutter renders are sufficient; no design change or AI mockup is needed.
Branch: codex/modular-generation-parameters. Baseline: 989e6b6.
Toolchain: Flutter 3.47.5 stable / Dart 3.13.4 on Windows PowerShell.
Baseline: 52 workbench screenshots passed, no reported layout exceptions; preserved
in build/generation-baseline. Inspected Seedream light and expanded video dark.
Baseline test gate: 3131 passed, 1 skipped. No live API calls.

Inventory: image producers are workbench_config_panel → AppState.submitTask and
TaskQueueService.addTask (including direct/batch callers); video producer is
video_config_panel → submitVideoTask. Execution is task_executors, with accepted
video jobs bypassing submission on resume. Prompt/details/menu and billing still
consume flat task fields; migrate these alongside the nested codec.
Preference stores: workbench_image_params / workbench_video_params, family.key,
plus historical last_aspect_ratio / last_resolution / last_video_* migration.

Route/profile matrix (existing repository facts):
- chatImage: Gemini image generations and relay media through chat, existing
  model-specific parameters preserved when auto already selects chat.
- openaiImages: GPT image 1/2/2.5 and compatible aliases; xAI relay compatibility.
- xaiImages: legacy/current image tables, native JSON.
- geminiImagen: text-only images; geminiVeo: async videos.
- dashscopeImagesSync/Async: qwen fixed/free/edit and wan/pro tables; only declared
  async support offered; DashScope aliases use conservative fallback.
- dashscopeVideo: wan3 parameter and audio table.
- minimaxImages: subject reference; minimaxVideo: cloud H3 required duration/size;
  minimaxH3BaseVideo: self-hosted checkpoint, separate single-resolution contract.
- arkImages: Seedream 3/4/4.5/5 lite/pro/generic with mode/tier differences.
- openaiVideos: compatible multipart; xaiVideos: native JSON distinct vocabulary.
- midjourney: existing proxy mode/version/stylize/chaos declaration.
No new upstream claims; existing ledger's unverified endpoint facts stay unverified.

### Execution completed — 2026-10-03

- Phases 0–4 implemented. Model declarations split into eight profile modules;
  the complete profile registry feeds schema/semantic-key and billing vocabulary
  enumeration. Dispatcher owns effective-wire resolution and alias compatibility.
- Typed values, operation/role vocabulary, schema validation, nested request codec,
  runtime cancellation context and legacy adapters implemented. Existing payload
  encoders/size helpers stay as the wire boundary; no speculative API facts added.
- Both parameter panels use one editor registry, shared text mapping and field
  shells. Presentation can override editor/span independently of semantic type.
  New semantic numeric keys can declare integer/decimal types without editor changes.
- Video conflicts are visible and block submit; unsupported last-frame input remains
  removable. Layers hide unused ratio/count. Transparency fixes PNG visibly and
  validates actual source alpha; source bytes bypass JPEG compression.
- Grok Imagine Image 2.0 duplicate Auto labels corrected: unset = Default, explicit
  auto = Auto. Both API values retained; regression test and four locale translations.
- New tasks write a single authoritative generation snapshot. Legacy flat tasks
  remain readable. Model/channel/wire/profile/schema changes are checked before
  initial submission; compatible credential/endpoint updates remain allowed.
  Accepted-job resume/cancel/settlement behavior retains its existing regression gates.
- Draft preferences are model/channel/wire/operation scoped. Legacy family settings
  remain read-only migration seeds; incompatible drafts show a supported default
  with a reason without erasing the stored value. Alias profiles use existing settings;
  no database schema/version migration or application version bump was necessary.
- Gate 0: dart format lib test tool passed. Gate 1: flutter analyze printed No issues
  found. Gate 2: flutter test -x screenshots --concurrency=4 passed 3160, skipped 1.
  One default-concurrency run had an unrelated Windows watcher/socket denial in
  wizard setup; its isolated rerun and the complete four-worker run passed.
- Relevant renders: 100 passed (52 real workbench + 48 parameter specimens); no
  printed layout exceptions. Specimens cover all four widths and locales, light/dark
  and all eight accents. Component gallery: 32 passed (16 controls + 16 markdown).
  Inspected real Grok English light, Seedream dark, mobile light; parameter mobile
  Japanese, desktop English dark and Traditional Chinese light; and the sixteen
  theme control/status/selection samples in build/generation-theme-inspection.png.
- Existing theme, glass, font inheritance and size editor preserved. No shell/primitive
  paint or animation change. Existing rebuild-scope and render-performance assertions
  pass in the full gate; no GPU benchmark was necessary for this refactor.
- Durable ownership and extension rules live in architecture/generation-parameters.md,
  linked from the LLM and UI workflow notes. Original review tables in this plan are
  baseline evidence rather than the final file map.
- Remaining verification limits: no paid live upstream requests or native Android/iOS
  device run. Narrow desktop/component renders do not claim native platform coverage.
  Existing upstream/relay and pricing debt remains in the ledger.
- Retirement: preserve this completed execution record in the implementation commit,
  then remove the one-time plan and reference that commit in the ledger.