# GEMINI.md

This file provides a comprehensive overview of the **Joycai Image AI Toolkits** project, designed to be used as a context for AI-powered development assistance.

## Project Overview

Joycai Image AI Toolkits is a cross-platform desktop (and mobile) application built with Flutter. Its primary purpose is to provide a unified and powerful interface for interacting with various AI image generation and language models (LLMs), such as those from Google (Gemini/Veo) and OpenAI.

The application allows users to manage local image libraries, perform batch processing tasks, refine and manage a library of prompts, download images from the web, rename files with AI, generate videos, and track AI model usage and costs. It is designed for artists, designers, and researchers who work extensively with AI-generated media.

- **Current Version:** 2.2.1
- **Dart SDK:** `^3.11.0`
- **Flutter SDK:** `^3.10.8` (tested against Flutter 3.41.1)

### Core Features

*   **AI Workbench:** The main interface for single-image processing, prompt refinement, video generation, and viewing results.
*   **File Browser:** A local file system explorer with AI-powered batch file renaming (`aiRename` task type).
*   **Batch Task Queue:** A persistent task queue system to process multiple images/videos with configurable concurrency. Task types: `imageProcess`, `promptRefine`, `imageDownload`, `aiRename`, `videoGenerate`.
*   **Image Downloader:** Extracts and downloads images from URLs or bulk lists, with cookie support for authenticated sites.
*   **Prompt Library:** A local SQLite database to save, categorize with multi-tag support, and reuse effective prompts (both user prompts and system prompts).
*   **Token Usage & Metrics:** Monitors token consumption and estimates costs per model, with token-based and request-based billing modes.
*   **Model & Channel Management:** Users can configure AI channels (providers) and models, including 3rd-party OpenAI-compatible REST proxies. Supports model auto-discovery.
*   **Setup Wizard:** A guided onboarding experience to configure channels and discover models on first launch.
*   **MCP Server:** Built-in Model Context Protocol (MCP) server for external client integration (e.g., Claude Desktop).
*   **Multi-language Support:** Localized for English (`en`), Simplified Chinese (`zh`), Traditional Chinese (`zh_Hant`), and Japanese (`ja`).

### Architecture

*   **Framework:** Flutter 3.10+ with Material 3 design.
*   **State Management:** `provider` package with multiple `ChangeNotifier` instances exposed via `MultiProvider`.
    *   **`AppState` (`lib/state/app_state.dart`):** The central singleton hub for settings, navigation, model/channel/pricing data cache, and coordination between sub-states.
    *   **`GalleryState` (`lib/state/gallery_state.dart`):** Manages the image gallery (source directories, selected images, processed images). Includes background isolate scanning.
    *   **`FileBrowserState` (`lib/state/file_browser_state.dart`):** Manages the local file system browser tree.
    *   **`DownloaderState` (`lib/state/downloader_state.dart`):** Manages image downloader state and cookie history.
    *   **`WorkbenchUIState` (`lib/state/workbench_ui_state.dart`):** Manages transient UI state for the workbench (e.g., sidebar panel selections).
*   **Backend Services (`lib/services/`):**
    *   **`LLMService` (`llm/llm_service.dart`):** A singleton facade for AI providers. Supports streaming (`requestStream`) and non-streaming (`request`) modes, session management, retry logic, and automatic token usage recording. Providers are registered by type: `google-genai`, `openai-api`.
    *   **`DatabaseService` (`database_service.dart`):** Manages the local SQLite database (using `sqflite`/`sqflite_common_ffi` for desktop). Persists all user data: settings, prompts, models, channels, pricing groups, tasks, and usage metrics.
    *   **`TaskQueueService` (`task_queue_service.dart`):** A `ChangeNotifier`-based task queue with configurable concurrency, persistent task history, retry support, real-time event streaming (`Stream<TaskEvent>`), and model-based ETA estimation.
    *   **`WebScraperService` (`web_scraper_service.dart`):** Scrapes and extracts image URLs from web pages using the `shelf`/`shelf_router` local server approach with cookie support and a local cache.
    *   **`ModelDiscoveryService` (`llm/model_discovery_service.dart`):** Fetches available model lists from provider APIs.
    *   **`NotificationService` (`notification_service.dart`):** Desktop notifications via `local_notifier`.
    *   **`ImageMetadataService` / `ImageProcessingService`:** Helpers for reading image metadata and performing local image operations.
    *   **`FilePermissionService`:** Handles platform-specific file permission requests.
*   **Repositories (`lib/services/repositories/`):** Thin data access objects used by `DatabaseService` for specific entities: `model_repository.dart`, `prompt_repository.dart`, `task_repository.dart`, `usage_repository.dart`.
*   **UI (Screens):** The UI is structured into several main screens managed by a `NavigationRail` (desktop/tablet) or `NavigationBar` + `Drawer` (mobile) in `main.dart`:
    *   `WorkbenchScreen` — image/video processing & gallery
    *   `FileBrowserScreen` — local file system browser with AI rename
    *   `TaskQueueScreen` — batch task queue management
    *   `ImageDownloaderScreen` — web image extraction and download
    *   `PromptsScreen` — prompt library management
    *   `TokenUsageScreen` — API usage metrics and cost tracking
    *   `ModelsScreen` — channel and model configuration
    *   `SettingsScreen` — app preferences (theme, locale, proxy, MCP, etc.)
*   **Core Utilities (`lib/core/`):**
    *   `responsive.dart` — `Responsive` class (breakpoints: mobile < 600px, tablet < 1000px, desktop ≥ 1000px) and `ResponsiveBuilder` widget.
    *   `constants.dart` — `AppConstants`, enums (`AppAspectRatio`, `AppResolution`, `ModelTag`, `VeoResolution`, `VeoAspectRatio`, `BillingMode`).
    *   `app_paths.dart` — Platform-specific application directory paths.
    *   `file_utils.dart` — File utility helpers.
*   **Models (`lib/models/`):** Data model classes: `LLMModel`, `LLMChannel`, `PricingGroup`, `Prompt` (user & system), `PromptTag`, `AppImage`, `BrowserFile`, `LogEntry`.
*   **Key Dependencies:**
    *   `provider`, `sqflite`, `sqflite_common_ffi`, `path_provider`, `http`
    *   `photo_view`, `extended_image`, `video_player` — media display
    *   `desktop_drop`, `file_picker`, `image_picker` — file input
    *   `shelf`, `shelf_router` — local MCP/scraper HTTP server
    *   `flutter_markdown_plus`, `google_fonts`
    *   `gal` — save to gallery (mobile)
    *   `local_notifier` — desktop notifications
    *   `package_info_plus`, `share_plus`, `url_launcher`
    *   `image`, `image_size_getter` — image utilities
    *   `crypto`, `html`, `intl`, `uuid`

## Building and Running

The project follows standard Flutter conventions.

### Prerequisites

*   Flutter SDK (^3.10.8, tested on 3.41.1)
*   Dart SDK (^3.11.0)
*   API Keys for OpenAI or Google Gemini/Veo.

### Key Commands

1.  **Install Dependencies:**
    ```bash
    flutter pub get
    ```

2.  **Generate Localization Files:**
    This command needs to be run to generate the necessary localization strings from the `.arb` files in `lib/l10n`.
    ```bash
    flutter gen-l10n
    ```

3.  **Run the Application (Debug):**
    Run the app on a connected desktop platform.
    ```bash
    flutter run -d windows
    # or -d macos / -d linux / -d android / -d ios
    ```

4.  **Build the Application (Release):**
    ```bash
    flutter build windows
    # or macos / linux / apk / ipa
    ```
    *   The `build_script/inno_setup.iss` file is used to create a Windows installer.
    *   The `build_script/build_macos.sh` script is used for macOS builds.
    *   The `msix_config` in `pubspec.yaml` supports building a Windows MSIX package.

5.  **Code Analysis:**
    ```bash
    flutter analyze
    ```

## Development Conventions

*   **Code Style:** The project uses `flutter_lints` for code analysis, with rules defined in `analysis_options.yaml`. Adherence to these linting rules is expected.
*   **State Management:** All application state should be managed through the appropriate state class (`AppState`, `GalleryState`, `FileBrowserState`, `DownloaderState`, or `WorkbenchUIState`). For new features, extend the relevant state class and notify listeners. Avoid ad-hoc local state (`StatefulWidget`) for data that needs to be persisted or shared across screens.
*   **UI & Layout:** All UI changes and improvements **MUST** consider and adapt to **Mobile, Tablet, and Desktop** screen sizes. Use the `Responsive` helper class and `ResponsiveBuilder` widget with Material 3 design principles. Some features (File Browser, Image Downloader) are hidden on mobile platforms.
*   **Code Analysis & Quality:** After every code change, **MUST** run `flutter analyze` and ensure **No issues found!** (including info-level lints). Any reported issues must be fixed before proceeding.
*   **Immutability:** When modifying state in any state class, create new instances of lists or objects rather than modifying them in place, especially when using `notifyListeners()`.
*   **Services:** Business logic not directly tied to the UI must be implemented in the `lib/services` directory. All interactions with external APIs are cleanly separated in the `LLMService` and its providers.
*   **Data Persistence:** All configuration and user data (prompts, models, settings, etc.) must be saved to the SQLite database via the `DatabaseService`. The repository layer in `lib/services/repositories/` should be used for structured data access. Avoid storing important data in memory only.
*   **Localization (l10n) Workflow:**
    *   **Source of Truth:** All translation keys MUST be added to the modular `.arb` files located in `lib/l10n/src/` (e.g., `lib/l10n/src/en/settings.arb`). Each language has its own subdirectory: `en/`, `zh/`, `zh_Hant/`, `ja/`.
    *   **Do NOT Modify Top-Level Files:** Never directly edit `lib/l10n/app_*.arb`. These files are automatically generated by merging the modular source files and will be overwritten.
    *   **Updating Translations:**
        1.  Edit/Add keys in the corresponding language and module file in `lib/l10n/src/`.
        2.  Run the merge tool: `dart tool/merge_l10n.dart`.
        3.  Generate the Dart localization classes: `flutter gen-l10n`.
    *   **Multi-language Support:** The project currently supports English (`en`), Simplified Chinese (`zh`), Traditional Chinese (`zh_Hant`), and Japanese (`ja`). Ensure **all four languages** are updated when adding new keys.
*   **Task System:** When adding new background operations, use the `TaskQueueService.addTask()` API and add a new `TaskType` enum value if needed. Implement the corresponding `_executeXxxTask()` method in `task_queue_service.dart`.
*   **LLM Providers:** To add a new AI provider, implement `ILLMProvider` from `llm_provider_interface.dart`, and register it in `main.dart` via `LLMService().registerProvider(...)`.

## Known Issues & Troubleshooting

### macOS Debug Build Crash (Flutter 3.38+)
When running the application in **Debug mode** on macOS, you may encounter a `Null check operator used on a null value` error in `xcode_backend.dart` (specifically in `_embedNativeAssets`).

*   **Cause:** This is an external Flutter SDK bug triggered by dependencies that use the "Native Assets" feature (e.g., `sqlite3`, `objective_c` via the `gal` plugin).
*   **Workaround:**
    1.  Use **Release mode** for macOS development/testing: `flutter run --release`.
    2.  If Debug mode is absolutely necessary on macOS, temporarily remove/comment out the `gal` dependency in `pubspec.yaml`.
    3.  Always perform a deep clean when switching platforms or experiencing native build issues: `rm -rf build .dart_tool` followed by `flutter pub get`.
    4.  The database initialization has been optimized to use standard `sqflite` on macOS to reduce Native Asset triggers, but transitive dependencies may still cause the crash.
    5.  **Hotfix for Flutter 3.38.5:** If the error persists at `xcode_backend.dart:345`, you can patch your local SDK with the following command:
        ```bash
        # Replace the forced null check with a fallback value
        sed -i '' "s/environment\['FLUTTER_BUILD_DIR'\]!/environment['FLUTTER_BUILD_DIR'] ?? 'build'/" $FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.dart
        ```
        *Note: Replace `$FLUTTER_ROOT` with your Flutter installation path.*
