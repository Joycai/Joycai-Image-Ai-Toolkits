# CLAUDE.md

Cross-platform Flutter desktop/mobile app for AI image processing with Google Gemini/Veo and OpenAI. Designed for artists and designers working with AI-generated media.

**Version:** 2.3.3 · **Dart SDK:** ^3.11.0 · **Tested on Flutter:** 3.41.1

## Key Commands

```bash
flutter pub get                                    # install dependencies
dart tool/merge_l10n.dart && flutter gen-l10n     # regenerate l10n (run after editing .arb files)
flutter run --release                              # run app (use --release on macOS — see Troubleshooting)
flutter analyze                                    # MUST show "No issues found!" before any commit
flutter build macos                                # or windows / linux / apk / ipa
```

## Project Map

```
lib/
  main.dart             # app entry, MultiProvider root, NavigationRail (desktop) / NavigationBar+Drawer (mobile)
  state/                # ChangeNotifier classes: AppState, GalleryState, FileBrowserState, DownloaderState, WorkbenchUIState
  services/             # all business logic
    llm/                # LLMService facade + GoogleGenAIProvider + OpenAIAPIProvider; model discovery
    repositories/       # SQLite DAOs: model, prompt, task, usage
    database_service.dart         # SQLite via sqflite/sqflite_common_ffi
    database_migrations.dart      # schema migrations
    task_queue_service.dart       # concurrency queue, Stream<TaskEvent>, ETA estimation
    web_scraper_service.dart      # HTML image extraction with cookie support
  screens/              # workbench · browser · batch · downloader · prompts · settings · metrics · models · wizard
  models/               # LLMModel, LLMChannel, PricingGroup, Prompt, PromptTag, AppImage, BrowserFile, LogEntry
  core/                 # Responsive (breakpoints), AppConstants/enums, AppPaths, file utils
  widgets/              # shared UI components
  l10n/                 # generated — do NOT edit directly (see l10n workflow below)
    src/<lang>/         # source .arb files: en · zh · zh_Hant · ja
```

**Task types:** `imageProcess` · `imageDownload` · `promptRefine` · `aiRename` · `videoGenerate`  
**LLM providers (registered in `main.dart`):** `google-genai` · `openai-api`  
**Key dependencies:** see `pubspec.yaml` — `provider`, `sqflite`, `http`, `shelf`, `shelf_router`, `photo_view`, `extended_image`, `video_player`, `desktop_drop`, `file_picker`, `image`, `local_notifier`, `gal`

## Development Rules

- **`flutter analyze` must pass** (zero issues, info-level included) after every code change.
- **Responsive UI:** all changes must work on Mobile (<600px), Tablet (<1000px), Desktop (≥1000px). Use `Responsive`/`ResponsiveBuilder` (`lib/core/responsive.dart`). FileBrowser and ImageDownloader are desktop/tablet-only.
- **State:** use the existing state classes. Never use `StatefulWidget` for shared or persistent data. Always create new list/object instances before `notifyListeners()` — do not mutate in place.
- **Data persistence:** all user data goes through `DatabaseService` and the repository layer.
- **Business logic:** belongs in `lib/services/`, not in widgets or screens.
- **Shell commands:** detect host OS before running shell commands. Never use Unix commands on Windows or PowerShell commands on macOS/Linux. No trial-and-error retries.

## Localization Workflow

Supports `en`, `zh`, `zh_Hant`, `ja`. **All four languages must be updated together.**

1. Edit keys in `lib/l10n/src/<lang>/<module>.arb` (e.g., `lib/l10n/src/en/settings.arb`).
2. **Never edit** `lib/l10n/app_*.arb` — auto-generated, will be overwritten.
3. `dart tool/merge_l10n.dart && flutter gen-l10n`

## Extension Patterns

**New task type:** add value to `TaskType` enum in `task_queue_service.dart` → implement `_executeXxxTask()` → wire into `addTask()`.

**New LLM provider:** implement `ILLMProvider` (`lib/services/llm/llm_provider_interface.dart`) → register in `main.dart` via `LLMService().registerProvider('type-id', MyProvider())`.

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
