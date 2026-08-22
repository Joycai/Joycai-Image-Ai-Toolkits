# CLAUDE.md

Cross-platform Flutter desktop/mobile app for AI image processing with Google Gemini/Veo and OpenAI. Designed for artists and designers working with AI-generated media.

**Version:** 3.19.2 · **Dart SDK:** ^3.11.0 · **Tested on Flutter:** 3.44.2

## Key Commands

```bash
flutter pub get                                    # install dependencies
dart tool/merge_l10n.dart && flutter gen-l10n     # regenerate l10n (run after editing .arb files)
flutter run --release                              # run app (use --release on macOS — see Troubleshooting)
flutter analyze                                    # MUST show "No issues found!" before any commit
flutter build macos                                # or windows / linux / apk / ipa
flutter test test/screenshots                      # render every screen to build/ui-screenshots/*.png
flutter test test/screenshots/component_gallery_test.dart  # every component, 8 theme seeds × light/dark
```

## Project Map

```
lib/
  main.dart             # app entry, MultiProvider root, NavigationRail (desktop) / NavigationBar+Drawer (mobile)
  state/                # ChangeNotifier classes: AppState, GalleryState, FileBrowserState, DownloaderState, WorkbenchUIState
  services/             # all business logic
    llm/                # LLMService facade + LLMDispatcher; three-layer API stack (see architecture note)
      protocols/        # layer 1 — wire formats: openai_chat/images/videos, xai_images/videos, gemini_chat/imagen/veo, anthropic_chat, midjourney, dashscope_images
      vendors/          # layer 2 — VendorProfile registry (auth, surface overrides); ids stored in llm_channels.type
      model_descriptor.dart  # layer 3 — ModelDescriptor (family + capabilities); sole place model-id sniffing is allowed
    repositories/       # SQLite DAOs: model, prompt, task, usage, assistant session
    database_service.dart         # SQLite via sqflite/sqflite_common_ffi
    database_migrations.dart      # schema migrations
    task_queue_service.dart       # concurrency queue, Stream<TaskEvent>, ETA estimation
    prompt_optimizer_agent.dart   # Prompt Assistant agent: tool loop, modes (system prompt / knowledge base), session persistence + compaction
    knowledge_base_service.dart   # local knowledge-base folder access (README.md entry, paged reads)
    llm/context_budget.dart       # sole interpreter of a model's context window (see architecture note below)
    web_scraper_service.dart      # HTML image extraction with cookie support
  screens/              # workbench · browser · batch · downloader · prompts · settings · metrics · models · wizard
  models/               # LLMModel, LLMChannel, PricingGroup, Prompt, PromptTag, AppImage, BrowserFile, LogEntry
  core/                 # Responsive (breakpoints), AppConstants/enums, AppPaths, file utils
  widgets/              # shared UI components
  l10n/                 # generated — do NOT edit directly (see l10n workflow below)
    src/<lang>/         # source .arb files: en · zh · zh_Hant · ja
```

**Task types:** `imageProcess` · `imageDownload` · `promptRefine` · `aiRename` · `videoGenerate`  
**LLM protocol families:** `openai` · `gemini` · `anthropic` · `midjourney` — routing lives in `lib/services/llm/llm_dispatcher.dart`  
**Key dependencies:** see `pubspec.yaml` — `provider`, `sqflite`, `http`, `shelf`, `shelf_router`, `photo_view`, `extended_image`, `video_player`, `desktop_drop`, `file_picker`, `image`, `local_notifier`, `gal`

## Architecture Notes

Read the relevant note before changing that subsystem — each records invariants
that fail silently when broken, and alternatives already tried and rejected.

- **[LLM three-layer API stack](docs/architecture/llm-three-layer.md)** — protocol / vendor / model layering, the dispatcher routing table, and the layering rules (no model-id sniffing outside `ModelDescriptor`, no vendor branches inside protocols). Required reading before touching anything under `lib/services/llm/`.
- **[Prompt Assistant context management](docs/architecture/assistant-context.md)** — elide/compact layers, the `context_window` tri-state, knowledge-read budgeting and paging. Required reading before touching `prompt_optimizer_agent.dart`, `context_budget.dart`, or `knowledge_base_service.dart`.
- **[Design tokens & multi-theme rule](docs/architecture/design-tokens.md)** — how the design spec's single blue maps onto 8 seed colours: the `onAccentTint` brightness branch, the alpha ladder (and its dark-mode ceiling), which colours must *not* follow the seed, and the deliberate divergences from the spec. Required reading before touching `design_tokens.dart`, `app_semantic_colors.dart`, `app_theme.dart`, or any accent/status colour in `widgets/`.

## Development Rules

- **`flutter analyze` must pass** (zero issues, info-level included) after every code change.
- **Responsive UI:** all changes must work on Mobile (<600px), Tablet (<1000px), Desktop (≥1000px). Use `Responsive`/`ResponsiveBuilder` (`lib/core/responsive.dart`). FileBrowser and ImageDownloader are desktop/tablet-only.
- **Visual debugging:** to actually *see* a layout rather than infer it, run `flutter test test/screenshots` and open the PNGs in `build/ui-screenshots/`. They render the real screens with seeded data at all three widths, in light and dark. Overflows are printed to the run output, not asserted — this is never a regression gate. See [docs/ui-screenshot-harness.md](docs/ui-screenshot-harness.md).
  For anything touching accent or status colour, use `component_gallery_test.dart` instead: it puts every component on one page and renders it under all 8 theme seeds in both brightnesses (16 PNGs), which is the only way to see whether a colour rule survives a seed change. `shoot()` also takes a `seedColor` if you need a whole screen at a specific seed.
- **State:** use the existing state classes. Never use `StatefulWidget` for shared or persistent data. Always create new list/object instances before `notifyListeners()` — do not mutate in place.
- **Data persistence:** all user data goes through `DatabaseService` and the repository layer. Never persist columns derivable from another table (the deleted `llm_models.type` is the cautionary tale — see the v32 migration).
- **LLM layering:** no model-id sniffing outside `model_family.dart`/`model_descriptor.dart`; no `vendor.id`/channel-type string comparisons outside `vendors/` and `llm_dispatcher.dart`; all routing branches live in `llm_dispatcher.dart` only. The greppable red-flag list is in [docs/architecture/llm-three-layer.md](docs/architecture/llm-three-layer.md).
- **Business logic:** belongs in `lib/services/`, not in widgets or screens.
- **Shell commands:** detect host OS before running shell commands. Never use Unix commands on Windows or PowerShell commands on macOS/Linux. No trial-and-error retries.

## Localization Workflow

Supports `en`, `zh`, `zh_Hant`, `ja`. **All four languages must be updated together.**

1. Edit keys in `lib/l10n/src/<lang>/<module>.arb` (e.g., `lib/l10n/src/en/settings.arb`).
2. **Never edit** `lib/l10n/app_*.arb` — auto-generated, will be overwritten.
3. `dart tool/merge_l10n.dart && flutter gen-l10n`

## Extension Patterns

**New task type:** add value to `TaskType` enum in `task_queue_service.dart` → implement `_executeXxxTask()` → wire into `addTask()`.

**New LLM vendor (OpenAI/Gemini-compatible supplier):** add a `VendorProfile` in `lib/services/llm/vendors/vendors.dart` → add a wizard preset in `widgets/models/channel_provider_presets.dart`. **New wire protocol:** implement the interfaces in `lib/services/llm/protocols/protocol.dart` → add a `ProtocolFamily` value → extend the switches in `lib/services/llm/llm_dispatcher.dart`. See [docs/architecture/llm-three-layer.md](docs/architecture/llm-three-layer.md).

## Troubleshooting

### macOS Debug Build Crash (Flutter 3.38+)

**Error:** `Null check operator used on a null value` in `xcode_backend.dart` (`_embedNativeAssets`)  
**Cause:** Flutter SDK bug triggered by Native Assets dependencies (`sqlite3`, `gal`)

1. Use release mode: `flutter run --release` _(preferred)_
2. Deep clean: `rm -rf build .dart_tool && flutter pub get`
3. Remove `gal` from `pubspec.yaml` if debug mode is required
4. Patch SDK (Flutter 3.38.5 only):
   ```bash
   sed -i '' "s/environment\['FLUTTER_BUILD_DIR'\]!/environment['FLUTTER_BUILD_DIR'] ?? 'build'/" \
     $FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.dart
   ```
