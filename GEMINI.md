# GEMINI.md

This file provides a comprehensive overview of the **Joycai Image AI Toolkits** project, designed to be used as a context for AI-powered development assistance.

## Project Overview

Joycai Image AI Toolkits is a cross-platform desktop application built with Flutter. Its primary purpose is to provide a unified and powerful interface for interacting with various AI image generation and language models (LLMs), such as those from Google (Gemini) and OpenAI.

The application allows users to manage local image libraries, perform batch processing tasks, refine and manage a library of prompts, and track AI model usage and costs. It is designed for artists, designers, and researchers who work extensively with AI-generated media.

### Core Features

*   **AI Workbench:** The main interface for single-image processing, prompt refinement, and viewing results.
*   **Batch Processing:** A task queue system to process multiple images with specific AI models and parameters.
*   **Prompt Library:** A local database to save, categorize, and reuse effective prompts.
*   **Model Management:** Users can configure different AI models (from Google GenAI and OpenAI) and their associated API keys and pricing.
*   **Usage Tracking:** Monitors token consumption and estimates costs for API calls.
*   **Multi-language Support:** Localized for English and Chinese.

### Architecture

*   **Framework:** Flutter 3.10+ with Material 3 design.
*   **State Management:** `provider` package (`ChangeNotifierProvider` with an `AppState` class). The `AppState` class is the central hub for managing UI state, application settings, and data.
*   **Backend Services:**
    *   **LLM Service (`llm_service.dart`):** A singleton service that acts as a facade for different AI provider APIs (e.g., `GoogleGenAIProvider`, `OpenAIAPIProvider`). It handles request streaming, session management, and token usage recording.
    *   **Database Service (`database_service.dart`):** Manages a local SQLite database (using `sqflite_common_ffi` for desktop) to persist all user settings, prompts, models, tasks, and usage metrics.
    *   **Task Queue Service (`task_queue_service.dart`):** Manages a queue of background processing tasks with a configurable concurrency limit.
*   **UI:** The UI is structured into several main screens, managed by a `NavigationRail` in `main.dart`. Key screens include `WorkbenchScreen`, `TaskQueueScreen`, `PromptsScreen`, `TokenUsageScreen`, `ModelsScreen`, and `SettingsScreen`.
*   **Asynchronous Operations:** The app makes heavy use of `Future` and `Stream` for handling long-running operations like API calls and file I/O without blocking the UI.

## Building and Running

The project follows standard Flutter conventions.

### Prerequisites

*   Flutter SDK (^3.10.8)
*   API Keys for OpenAI or Google Gemini.

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
    # or -d macos / -d linux
    ```

4.  **Build the Application (Release):**
    ```bash
    flutter build windows
    # or macos / linux
    ```
    The `build_script/inno_setup.iss` file is used to create a Windows installer.

## Development Conventions

*   **Code Style:** The project uses `flutter_lints` for code analysis, with rules defined in `analysis_options.yaml`. Adherence to these linting rules is expected.
*   **State Management:** All application state should be managed through the central `AppState` class. For new features, extend `AppState` and notify listeners to update the UI. Avoid local state (`StatefulWidget`) for data that needs to be persisted or shared across screens.
*   **Immutability:** When modifying state in `AppState`, create new instances of lists or objects rather than modifying them in place, especially when using `notifyListeners()`.
*   **Services:** Business logic that is not directly tied to the UI should be implemented in the `lib/services` directory. For example, all interactions with external APIs are cleanly separated in the `LLMService`.
*   **Data Persistence:** All configuration and user data (prompts, models, etc.) must be saved to the SQLite database via the `DatabaseService`. Avoid storing important data in memory only.
*   **Localization:** All user-facing strings must be added to modular files in `lib/l10n/src/` (e.g., `workbench.arb`), then merged using `dart tool/merge_l10n.dart` before running `flutter gen-l10n`.

## Known Issues & Troubleshooting

### macOS Debug Build Crash (Flutter 3.38+)
When running the application in **Debug mode** on macOS, you may encounter a `Null check operator used on a null value` error in `xcode_backend.dart` (specifically in `_embedNativeAssets`).

*   **Cause:** This is an external Flutter SDK bug triggered by dependencies that use the "Native Assets" feature (e.g., `sqlite3`, `objective_c` via the `gal` plugin).
*   **Workaround:** 
    1.  Use **Release mode** for macOS development/testing: `flutter run --release`.
    2.  If Debug mode is absolutely necessary on macOS, temporarily remove/comment out the `gal` dependency in `pubspec.yaml`.
    3.  Always perform a deep clean when switching platforms or experiencing native build issues: `rm -rf build .dart_tool` followed by `flutter pub get`.
    4.  The database initialization has been optimized to use standard `sqflite` on macOS to reduce Native Asset triggers, but transitive dependencies may still cause the crash.

