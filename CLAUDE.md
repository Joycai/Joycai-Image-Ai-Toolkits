# CLAUDE.md

Cross-platform Flutter desktop/mobile app for AI image and video generation, built
around a multi-vendor LLM layer. Designed for artists and designers working with
AI-generated media.

**Version:** 4.0.2 · **Dart SDK:** ^3.11.0 · **Tested on Flutter:** 3.47.2 (CI tracks `stable`)

## Key Commands

```bash
flutter pub get                                    # install dependencies
dart tool/merge_l10n.dart && flutter gen-l10n      # regenerate l10n (run after editing .arb files)
flutter run                                        # run the app
flutter analyze                                    # MUST show "No issues found!" before any commit
flutter test                                       # full suite — CI gates on this
flutter build macos                                # or windows / linux / apk / ipa
flutter test test/screenshots                      # render every screen to build/ui-screenshots/*.png
flutter test test/screenshots/component_gallery_test.dart  # every component, 8 theme seeds × light/dark
```

CI (`.github/workflows/flutter-ci.yml`) runs `flutter gen-l10n` → `flutter analyze`
→ `flutter test`. Both gates must be green locally before you push.

## Project Map

```
lib/
  main.dart                       # entry: MultiProvider root → MyApp → AppWindowFrame → MainNavigationScreen
                                  #   (title-bar nav · tablet top bar · phone dock — see widgets/shell/)
  state/                          # ChangeNotifier singletons: AppState (split across app_state{,_data,_workbench}.dart),
                                  #   GalleryState, FileBrowserState, FileStagingState, DownloaderState,
                                  #   WorkbenchUIState, TaskListState, LogState
  services/                       # all business logic
    llm/
      llm_service.dart            # facade the app calls
      llm_dispatcher.dart         # the ONLY routing table (surface × protocol × vendor)
      protocols/                  # layer 1 — wire formats: openai chat/images/videos · xai images/videos ·
                                  #   gemini chat/imagen/veo · anthropic chat ·
                                  #   dashscope chat/images/images-async/video · minimax images/video · midjourney
      vendors/                    # layer 2 — VendorProfile registry (auth, per-surface protocol menus);
                                  #   ProtocolFamily lives in vendor_profile.dart; ids stored in llm_channels.type
      model_descriptor.dart       # layer 3 — family + capabilities; with model_family.dart, the only
                                  #   place model-id sniffing is allowed
      context_budget.dart         # sole interpreter of a model's context window (see architecture note)
    repositories/                 # SQLite DAOs: model, prompt, task, usage, assistant session, assistant note
    database_service.dart         # SQLite via sqflite / sqflite_common_ffi
    database_migrations.dart      # schema migrations, onCreate + onUpgrade in lockstep
    task_queue_service.dart       # concurrency queue, Stream<TaskEvent>, ETA estimation
    task_executors.dart           # `part of` the queue — one _executeXxxTask per TaskType
    task_list_ordering.dart       # task-list filter/sort: created_at is the only key; pinning is a switch over it
    prompt_optimizer_agent.dart   # Prompt Assistant agent: tool loop, modes (system prompt / knowledge base),
                                  #   session persistence + compaction
    sub_agent_runner.dart         # nested single-shot agent runs used by the assistant
    knowledge_base_service.dart   # local knowledge-base folder access (README.md entry, paged reads)
    web_scraper_service.dart      # HTML image extraction with cookie support
  screens/                        # workbench · browser · batch · downloader · prompts · settings · metrics · models · wizard
  models/                         # LLMModel, LLMChannel, PricingGroup, Prompt/SystemPrompt, PromptTag,
                                  #   PromptHistoryEntry, TaskItem (+ TaskType, TaskEvent), AppImage, BrowserFile, LogEntry
  core/                           # Responsive (breakpoints), AppConstants/enums, AppPaths, file utils,
                                  #   design_tokens.dart · app_theme.dart · app_semantic_colors.dart · theme_accent.dart
  widgets/                        # shared UI components; subfolders: shell/ (nav chrome) · glass/ · dialogs/ · drag/ · models/
  l10n/                           # generated — do NOT edit directly (see l10n workflow below)
    src/<lang>/                   # source .arb files, one per module: en · zh · zh_Hant · ja
```

**Task types** (`lib/models/task_item.dart`): `imageProcess` · `imageDownload` · `promptRefine` · `aiRename` · `videoGenerate`  
**LLM protocol families** (`ProtocolFamily`): `openai` · `gemini` · `anthropic` · `midjourney` · `dashscope` — routing lives in `lib/services/llm/llm_dispatcher.dart`  
**Key dependencies:** see `pubspec.yaml` — `provider`, `sqflite`, `http`, `extended_image`, `video_player`, `desktop_drop`, `file_picker`, `image`, `flutter_local_notifications`, `gal`

## Architecture Notes

Read the relevant note before changing that subsystem — each records invariants
that fail silently when broken, and alternatives already tried and rejected.

- **[LLM three-layer API stack](docs/architecture/llm-three-layer.md)** — protocol / vendor / model layering, the dispatcher routing table, and the layering rules (no model-id sniffing outside `ModelDescriptor`, no vendor branches inside protocols). Required reading before touching anything under `lib/services/llm/`.
- **[Prompt Assistant context management](docs/architecture/assistant-context.md)** — elide/compact layers, the `context_window` tri-state, knowledge-read budgeting and paging. Required reading before touching `prompt_optimizer_agent.dart`, `context_budget.dart`, or `knowledge_base_service.dart`.
- **[Design tokens & multi-theme rule](docs/architecture/design-tokens.md)** — how the design spec's single blue maps onto 8 seed colours: the `onAccentTint` brightness branch, the alpha ladder (and its dark-mode ceiling), which colours must *not* follow the seed, and the deliberate divergences from the spec. Required reading before touching `design_tokens.dart`, `app_semantic_colors.dart`, `app_theme.dart`, or any accent/status colour in `widgets/`.

[docs/README.md](docs/README.md) indexes the rest: protocol facts under `docs/api/`,
the portable AI-agent playbook, and the two ledgers of retired work —
[docs/plans/README.md](docs/plans/README.md) (seven feature/refactor rounds, where each
conclusion now lives, and **what is still owed**) and [plans/README.md](plans/README.md)
(fourteen animation plans, plus the effects ruled deliberate — do not "fix" those).
Read the relevant ledger before proposing a round of work; plan files are deleted once
executed, so an empty directory does not mean the work is open.

## Development Rules

- **`flutter analyze` must pass** (zero issues, info-level included) and **`flutter test` must be green** after every code change.
- **Responsive UI:** all changes must work on Mobile (<600px), Tablet (<1000px), Desktop (≥1000px). Use `Responsive`/`ResponsiveBuilder` (`lib/core/responsive.dart`). File Browser and Downloader are hidden on *mobile platforms* (`desktopOnly` in `widgets/shell/app_destinations.dart`, a `Platform.isAndroid || Platform.isIOS` check) — that is a platform gate, not a width gate, so both still render in a narrow desktop window.
- **Visual debugging:** to *see* a layout instead of inferring it, run `flutter test test/screenshots` and open the PNGs in `build/ui-screenshots/` — the real screens with seeded data at four widths (390 / 834 / 1024 / 1440), light and dark. Overflows are printed, never asserted: this is not a regression gate. See [docs/ui-screenshot-harness.md](docs/ui-screenshot-harness.md).
  For anything touching accent or status colour use `component_gallery_test.dart` instead — every component on one page under all 8 theme seeds in both brightnesses (16 PNGs) is the only way to see whether a colour rule survives a seed change. `shoot()` also takes an `accent` (a `ThemeAccent` from `AppConstants.presetThemes`) for a whole screen at one theme colour.
- **State:** use the existing state classes. Never use `StatefulWidget` for shared or persistent data. Always create new list/object instances before `notifyListeners()` — do not mutate in place.
- **Data persistence:** all user data goes through `DatabaseService` and the repository layer. Never persist columns derivable from another table (the deleted `llm_models.type` is the cautionary tale — see the v32 migration). Every schema change needs both an `onUpgrade` step and the matching `onCreate` call.
- **LLM layering:** no model-id sniffing outside `model_family.dart`/`model_descriptor.dart`; no `vendor.id`/channel-type string comparisons outside `vendors/` and `llm_dispatcher.dart`; all routing branches live in `llm_dispatcher.dart` only. The greppable red-flag list is in [docs/architecture/llm-three-layer.md](docs/architecture/llm-three-layer.md).
- **Business logic:** belongs in `lib/services/`, not in widgets or screens.
- **Shell commands:** detect host OS before running shell commands. Never use Unix commands on Windows or PowerShell commands on macOS/Linux. No trial-and-error retries.

## Localization Workflow

Supports `en`, `zh`, `zh_Hant`, `ja`. **All four languages must be updated together.**

1. Edit keys in `lib/l10n/src/<lang>/<module>.arb` (e.g., `lib/l10n/src/en/settings.arb`).
2. **Never edit** `lib/l10n/app_*.arb` — auto-generated by `merge_l10n.dart`, will be overwritten.
3. `dart tool/merge_l10n.dart && flutter gen-l10n`

## Extension Patterns

**New task type:** add a value to `TaskType` in `lib/models/task_item.dart` → implement
`_executeXxxTask()` in `services/task_executors.dart` → add its branch to `_executeTask()`
in `task_queue_service.dart`. `addTask()` takes the type as a parameter and needs no change.

**New LLM vendor (OpenAI/Gemini-compatible supplier):** add a `VendorProfile` in
`lib/services/llm/vendors/vendors.dart` → add a preset in
`widgets/models/channel_provider_presets.dart` (one catalogue — the add-channel rail,
the editor's preset overlay and first-run all read it).

**New wire protocol:** implement the interfaces in `lib/services/llm/protocols/protocol.dart`
→ add a `WireProtocol` value (and a `ProtocolFamily` only if the auth/discovery shape is
genuinely new) → extend the switches in `lib/services/llm/llm_dispatcher.dart`.
See [docs/architecture/llm-three-layer.md](docs/architecture/llm-three-layer.md).
