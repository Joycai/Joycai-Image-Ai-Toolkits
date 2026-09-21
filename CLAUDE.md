# CLAUDE.md

Cross-platform Flutter desktop/mobile app for AI image and video generation, built
around a multi-vendor LLM layer, for artists and designers working with AI media.

**Version:** 4.24.0 · **Dart SDK:** ^3.11.0 · **Tested on Flutter:** 3.47.2 (CI tracks `stable`)

## Key Commands

```bash
flutter pub get                                    # install dependencies
dart tool/merge_l10n.dart && flutter gen-l10n      # regenerate l10n (after editing .arb files)
flutter run                                        # run the app
flutter analyze                                    # gate 1 — must print "No issues found!"
flutter test -x screenshots                        # gate 2 — everything but the screenshot harness
flutter build macos                                # or windows / linux / apk / ipa
flutter test test/screenshots                      # render every screen to build/ui-screenshots/*.png
flutter test test/screenshots/component_gallery_test.dart  # every component, 8 theme seeds × light/dark
flutter test test/screenshots/render_probe.dart    # UI-thread rebuild/repaint cost (not in CI)
```

**Both gates must be green after every code change, before any commit.** CI
(`.github/workflows/flutter-ci.yml`) runs them in parallel jobs, tests sharded by file
across three runners. The `screenshots` tag (`dart_test.yaml`) marks harness files that
write PNGs and assert nothing; `rebuild_scope_test.dart` sits beside them but asserts,
so it stays in the gate.

## Project Map

`lib/` — each top-level folder is a layer (see *Layering* below).

```
main.dart          MultiProvider root → MyApp → AppWindowFrame → MainNavigationScreen
core/              Responsive breakpoints, AppConstants/enums, AppPaths, file utils, design_tokens,
                     app_shortcuts (the one keyboard-shortcut table)
                     (incl. AppDock, the phone dock's size), app_theme, app_semantic_colors, theme_accent
l10n/              generated — never edit; sources are l10n/src/<lang>/<module>.arb
models/            LLMModel, LLMChannel, PricingGroup, Prompt/SystemPrompt (+ PresetOutputKind), PromptTag, PromptHistoryEntry,
                     TaskItem (+ TaskType, TaskEvent), TokenUsage (one billed request; owns its
                     cost arithmetic) + UsageCheckpoint, AppImage, BrowserFile, LogEntry,
                     ImageLayer (a saved Seedream layer decomposition)
services/          all business logic, in domain folders only:
  llm/               the API stack — llm_service (facade) · llm_dispatcher (the ONLY routing table) ·
                       protocols/ (layer 1, wire formats) · vendors/ (layer 2, VendorProfile registry,
                       ProtocolFamily; platforms = PlatformProfile + RouteKind) · model_descriptor +
                       model_family (layer 3, the only place model-id sniffing is allowed) ·
                       context_budget (sole reader of a context window) · channel_routes (a channel's
                       routes, v45 document) · model_routes (RouteParams, RoutedChannel = the channel
                       as one model sees it)
  db/                database_service · database_migrations (onCreate + onUpgrade in lockstep) ·
                       repositories/ (model, prompt, task, usage, assistant session/note, cookie,
                       image_layer)
  tasks/             task_queue_service (concurrency, Stream<TaskEvent>, ETA) · task_executors
                       (`part of` it, one _executeXxxTask per TaskType) · task_list_ordering ·
                       ai_rename_agent · ai_rename_review (neither deletes a file the run placed)
  assistant/         Prompt Assistant — prompt_optimizer_agent + its eight `part`s (assistant_*,
                       prompt_optimizer_session), sub_agent_runner, knowledge_base_*, prompt_provenance
  catalogue/         what backs the models page (ordering, id uniqueness, context/output scales,
                       route_switching, channel_merge + its executor) — not llm/
  files/ media/ system/ billing/   filesystem ops · image/video/scraping · host adapters · spec billing
state/             ChangeNotifier singletons: AppState (app_state{,_data,_workbench}.dart), GalleryState,
                     FileBrowserState, FileStagingState, DownloaderState, ModelListState,
                     WorkbenchUIState, TaskListState, LogState
widgets/           shared UI, in domain folders only:
  ui/ glass/ drag/   the design system — app_* controls, generic inputs, drawing primitives,
                       listenable_selector (a Selector for a plain Listenable)
  shell/             nav chrome: window frame, top bar, phone dock, destinations, shell_cover, baked_backdrop
  models/ tasks/ settings/ files/ dialogs/ placeholders/
screens/           workbench · browser · batch · downloader · prompts · settings · metrics · models · wizard
bench/             render_bench.dart — GPU benchmark, inert unless RBENCH=1
```

Protocol files are named `<family>_<surface>_protocol.dart` (openai chat/responses/images/videos,
xai, gemini chat/imagen/veo, anthropic, dashscope, minimax, midjourney, ark images); shared `*_payload`,
`openai_chat_parsing`, `streaming_tool_calls`, `inline_think` and `chat_image_extraction` are
reused across families. The anthropic protocol is split over seven `anthropic_*` files —
mapped in the LLM architecture note.

**Task types** (`TaskType`): `imageProcess` · `imageDownload` · `promptRefine` · `aiRename` · `videoGenerate`
**Protocol families** (`ProtocolFamily`): `openai` · `gemini` · `anthropic` · `midjourney` · `dashscope`

## Read Before You Touch

Each note records invariants that fail silently when broken, and alternatives already
tried and rejected.

| Touching… | Read first |
|---|---|
| anything under `lib/services/llm/` | [docs/architecture/llm-three-layer.md](docs/architecture/llm-three-layer.md) — layering, routing table, greppable red-flag list |
| `services/assistant/` (esp. `assistant_context_window.dart`), `context_budget.dart`, `knowledge_base_service.dart` | [docs/architecture/assistant-context.md](docs/architecture/assistant-context.md) — elide/compact layers, `context_window` tri-state, knowledge paging |
| `design_tokens.dart`, `app_semantic_colors.dart`, `app_theme.dart`, any accent/status colour in `widgets/` | [docs/architecture/design-tokens.md](docs/architecture/design-tokens.md) — one spec blue → 8 seeds, `onAccentTint`, alpha ladder, colours that must *not* follow the seed |
| `core/app_shortcuts.dart`, `widgets/ui/focus_pane.dart`, any `onKeyEvent` in a screen | [docs/architecture/keyboard-shortcuts.md](docs/architecture/keyboard-shortcuts.md) — the three tiers, why selection keys belong to a focus region, and the handful of things that fail silently |
| proposing a new round of work | [docs/plans/README.md](docs/plans/README.md) (executed rounds, **what is still owed**) and [plans/README.md](plans/README.md) (animation plans, and effects ruled deliberate — do not "fix" those). Plan files are deleted once executed: an empty directory does not mean the work is open |

[docs/README.md](docs/README.md) indexes the rest: protocol facts (`docs/api/`), the
AI-agent playbook, and the tooling (screenshot harness, render probe, GPU bench).

## Development Rules

### Layering

`lib/` directories are ranked; a file may import its own directory plus anything of
strictly **lower** rank — never sideways, never up:

`core`, `l10n` (0) → `models` (1) → `services` (2) → `state` (3) → `widgets` (4) → `screens` (5) → `bench` (6) → `main.dart` (7)

- A service may not read `AppState` — pass the value in, or park it beside the thing that
  needs it (`LLMDebugLogger.enabled`). A shared widget may not import a screen — inject
  the dependency (`AppRunConsole`'s `onExpand`).
- **`widgets/` and `services/` keep nothing in their root.** Every file sits in a domain
  folder. And `lib/widgets/` means *more than one feature uses it*: a widget with one
  screen's worth of callers belongs under that screen.
- **The design system (`widgets/{ui,glass,drag}`) imports only `core`, `l10n` and
  itself.** When a primitive seems to need something higher, either it is not a
  primitive or the dependency belongs lower (the dock's size became `AppDock` in
  `core/design_tokens.dart` so `AppSnackbar` could clear it).
- **Business logic belongs in `lib/services/`**, not in widgets or screens.
- **LLM layering:** no model-id sniffing outside `model_family.dart`/`model_descriptor.dart`;
  no `vendor.id`/channel-type string comparisons outside `vendors/` and `llm_dispatcher.dart`;
  every routing branch lives in `llm_dispatcher.dart`.

`test/source_layout_test.dart` enforces the import rules (ranks, no cycles, empty roots,
the design-system boundary, no relative import climbing out of `lib/`) and prints the
offending file and line. A genuinely new layer or folder means changing that test on purpose.

### State and data

- Use the existing state classes; never a `StatefulWidget` for shared or persistent data.
- **Hand out a new list/object before `notifyListeners()` — never mutate in place.**
  List identity is the only signal a `select` has; `rebuild_scope_test.dart` pins this.
- **Take the database, don't fetch it.** Every state class, repository and
  DB-reading service has an optional `DatabaseService` on its constructor
  (`database:` on a state or service, `db:` on a repository) defaulting to the
  singleton; `AppState` hands its own down to every sub-state and to the task
  queue. Keep new ones that way, and in tests inject `openTestDatabase()`
  (`test/support/in_memory_database.dart`) instead of reaching for the real
  file through `usePrivateDataDir`.
- All user data goes through `DatabaseService` and the repositories. Never persist a column
  derivable from another table (the deleted `llm_models.type` — see the v32 migration).
  Every schema change needs an `onUpgrade` step **and** the matching `onCreate` call.

### UI

- **Responsive:** every change must work on Mobile (<600px), Tablet (<1000px) and Desktop
  (≥1000px) via `Responsive`/`ResponsiveBuilder` (`lib/core/responsive.dart`). File Browser
  and Downloader are hidden on mobile *platforms* (`desktopOnly` in
  `widgets/shell/app_destinations.dart`) — a platform gate, not a width gate, so both still
  render in a narrow desktop window.
- **See, don't infer:** run the screenshot harness and open `build/ui-screenshots/` — real
  screens with seeded data at 390 / 834 / 1024 / 1440, light and dark. Overflows are printed,
  not asserted ([docs/ui-screenshot-harness.md](docs/ui-screenshot-harness.md)). For accent
  or status colour use `component_gallery_test.dart` — the only way to see whether a colour
  rule survives a seed change; `shoot()` also takes an `accent` for a whole screen.
- **Render performance — measure, don't reason, and know which thread you measure.**
  UI thread: `render_probe.dart`; its findings are pinned by `rebuild_scope_test.dart` and
  `test/render_performance_test.dart`. GPU: `lib/bench/render_bench.dart` — read its traps in
  [docs/README.md](docs/README.md#tooling) first (on Windows `rasterDuration` misses GPU time;
  numbers drift 2x between sessions, so take before and after in one pass).
  Already stopped: the window ground is one baked image (`widgets/shell/baked_backdrop.dart`),
  and a settled full-screen cover stops the shell under it (`widgets/shell/shell_cover.dart`).
  Both are pinned by tests that assert the mechanism, never a frame time.

### Shell

Detect the host OS before running shell commands — no Unix commands on Windows, no
PowerShell on macOS/Linux, no trial-and-error retries.

## Localization

Languages: `en`, `zh`, `zh_Hant`, `ja` — **update all four together** (the `joycai-l10n`
skill has the checklist).

1. Edit `lib/l10n/src/<lang>/<module>.arb`. **Never** edit `lib/l10n/app_*.arb` — generated.
2. `dart tool/merge_l10n.dart && flutter gen-l10n`

## Extension Patterns

- **New task type** (skill: `joycai-add-task-type`): add a `TaskType` value in
  `lib/models/task_item.dart` → implement `_executeXxxTask()` in
  `services/tasks/task_executors.dart` → add its branch to `_executeTask()` in
  `task_queue_service.dart`. `addTask()` needs no change.
- **New LLM vendor** (OpenAI/Gemini-compatible; skill: `joycai-add-llm-provider`): add a
  `VendorProfile` in `lib/services/llm/vendors/vendors.dart` → add a preset in
  `widgets/models/channel_provider_presets.dart` (the one catalogue the add-channel rail,
  preset overlay and first-run all read).
- **New wire protocol:** implement `lib/services/llm/protocols/protocol.dart` → add a
  `WireProtocol` value (and a `ProtocolFamily` only if the auth/discovery shape is genuinely
  new) → extend the switches in `llm_dispatcher.dart`.
