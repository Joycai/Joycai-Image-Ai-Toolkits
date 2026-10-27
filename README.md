# Joycai Image AI Toolkits

[![Flutter](https://img.shields.io/badge/Flutter-3.47.8-%2302569B.svg?style=flat&logo=Flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=flat&logo=dart&logoColor=white)](https://dart.dev)
[![Version](https://img.shields.io/badge/version-4.31.6-blue.svg)](https://github.com/Joycai/Joycai-Image-Ai-Toolkits/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Build Status](https://github.com/Joycai/Joycai-Image-Ai-Toolkits/actions/workflows/flutter-ci.yml/badge.svg)](https://github.com/Joycai/Joycai-Image-Ai-Toolkits/actions)

Joycai Image AI Toolkits is a powerful, cross-platform desktop & mobile application built with Flutter, designed to streamline AI-powered image and video processing workflows. It provides a unified interface to interact with various Large Language Models (LLMs) and Multimodal models for image generation, analysis, prompt optimization, video generation, and more.

[简体中文](README_CN.md) · [Documentation](docs/README.md) · [Testing](TESTING.md)

![App Icon](assets/icon/icon.png)

## 🚀 Key Features

### 🛠️ AI Workbench & Dynamic Channels

*   **Dynamic AI Channels**: Configure OpenAI, Google Gemini, Anthropic, xAI, DeepSeek, MiniMax, DashScope, Volcengine Ark, Midjourney proxies, New API relays, and local Ollama / LM Studio endpoints. Available capabilities depend on the model and route.
*   **Model-Specific Parameters**: Image and video forms expose supported sizes, quality, output formats, reference limits, and other options for the selected model. Compatible aliases can use a native capability profile.
*   **Unified Sidebar**: A resizable overlay sidebar providing quick access to **Directories**, **Preview**, **Comparator**, and **Mask Editor** tools without leaving your current context.
*   **Source Explorer**: Easily manage local image directories with built-in directory watching and **Background Isolate Scanning** to keep scanning off the UI isolate.
*   **Unified Gallery**: Seamlessly switch between source images and processed results.
*   **Control Panel**: Fine-tune your AI requests with model selection, aspect ratio, and resolution settings.
*   **Prompt Assistant**: Refine prompts through conversations with reference images, a persistent knowledge base, saved sessions, and sub-agents. Apply the resulting prompt to the workbench.
*   **Asynchronous GPT Image Batch**: Submit supported GPT Image models through the official OpenAI native Images route. Remote jobs resume polling after restart and offer refresh and cancellation actions. This mode produces one image per task without partial previews; see [Batch behavior and recovery](docs/api/gpt-image-series.md#asynchronous-batch-images-2026-10-26).
*   **GPT Image Streaming**: Show partial previews where supported and save final results as they arrive. A configurable soft timeout keeps waiting for late results without submitting another generation.

### 🎬 Video Generation

*   **AI Video Generation**: Generate videos with supported Google Veo, xAI, DashScope, and MiniMax models. First-frame, last-frame, reference-image, and audio options depend on the selected model and route.
*   **Configurable Resolution & Aspect Ratio**: Choose from the resolutions, aspect ratios, and durations supported by the selected model.
*   **Async Long-Running Operations**: Video generation tasks run via polling, with progress tracking in the Task Queue.

### 🎨 Advanced Editing & Acquisition

*   **Smart Image Downloader**: Extract and download images from URLs or bulk lists with cookie support for authenticated/protected sites.
*   **Image Editing**: Crop and resize images, draw masks, and use supported models for transparent editing or Seedream layer decomposition. Inspect layers and export a composited PNG.
*   **Image Comparator**: Compare raw and processed images side-by-side or with a sliding swap view.
*   **AI File Renamer**: Batch-rename files using an AI model with custom instructions via the File Browser.

### 🔌 Ecosystem & Onboarding

*   **Setup Wizard**: A guided onboarding experience to configure channels and discover models on first launch.
*   **Local MCP Image Server**: On desktop, external agents can discover configured image models, inspect parameter schemas, submit text/reference-image generation, poll tasks, and read results. Enable the authenticated loopback server in Settings → Connectivity; see [connection and tool details](docs/architecture/mcp-image-server.md).
*   **Model Auto-Discovery**: Fetch model lists where supported, use provider presets, or add model IDs manually.

### 📋 Task Queue & Prompt Management

*   **Persistent Task Queue**: Five task types — `imageProcess`, `promptRefine`, `imageDownload`, `aiRename`, `videoGenerate` — with configurable concurrency and retry support.
*   **Real-time Streaming**: Live log and result streaming from background tasks via `Stream<TaskEvent>`.
*   **Desktop Processing Count**: The macOS Dock and Windows taskbar show actively processing tasks. Remote Batch waiting does not contribute.
*   **Model-Based ETA**: Automatic task duration estimation per model, updated after every 10 completions.
*   **Multi-Tag Prompts**: Organise your prompt library with a flexible multi-tag system.
*   **Markdown Support**: Full Markdown editing for both user and system prompts.

### 📊 Token Usage & Cost Tracking

*   **Detailed Metrics**: Monitor input and output token consumption per model.
*   **Flexible Billing**: Token, request, and specification-based pricing with configurable fee groups and cached-token accounting.
*   **Cost Estimation**: Automatically calculate estimated costs based on configurable model pricing.
*   **Filtering**: Analyze usage by model or date range.

### ⚙️ Advanced Configuration

*   **Model Manager**: Tabbed interface for managing models and channels, including pricing group assignment.
*   **Global Proxy Support**: Full support for authenticated HTTP proxies with a quick-toggle switch.
*   **Localization**: Full support for English (`en`), Simplified Chinese (`zh`), Traditional Chinese (`zh_Hant`), and Japanese (`ja`).
*   **Theming**: Warm-stone surfaces, glass controls, eight accent seeds, and dark/light/system modes across phone, tablet, and desktop layouts.
*   **Data Portability**: Export/import configuration, prompt libraries, and optional usage records as JSON. API keys, cookies, proxy passwords, and local MCP grants are redacted. Task history and generated media are not included.

## 🛠️ Technical Stack

*   **Framework**: [Flutter](https://flutter.dev) (Material 3), version 3.47.8
*   **Dart SDK**: `^3.13.0`
*   **App Version**: 4.31.6
*   **State Management**: [Provider](https://pub.dev/packages/provider) — `AppState` coordinates dedicated gallery, file browser, staging, downloader, model, workbench, task, log, and MCP states
*   **Database**: [SQLite](https://pub.dev/packages/sqflite) (via `sqflite_common_ffi` for Desktop support)
*   **Localization**: `flutter_localizations` with modular ARB source files in `lib/l10n/src/`
*   **Networking**: `http` for REST API communication
*   **Media**: `extended_image`, `video_player` for display; `desktop_drop`, `file_picker` for input

## 📦 Getting Started

### Prerequisites

*   Flutter SDK 3.47.8 (includes Dart 3.13.7; CI and release builds use this version)
*   Native build tools for your target platform (see [build configuration](.github/workflows/flutter-build.yml)). Release automation builds Windows, macOS, Linux, and Android; iOS requires a local Apple toolchain and signing.
*   An API key for your chosen hosted provider, or a running local Ollama / LM Studio endpoint.

File Browser and Downloader are desktop-only destinations and are hidden on Android/iOS. The app does not target Flutter Web.

### Installation

1.  Clone the repository:
    ```bash
    git clone https://github.com/Joycai/Joycai-Image-Ai-Toolkits.git
    cd Joycai-Image-Ai-Toolkits
    ```
2.  Install dependencies:
    ```bash
    flutter pub get
    ```
3.  Generate localization files:
    ```bash
    dart tool/merge_l10n.dart
    flutter gen-l10n
    ```
4.  Run the application:
    ```bash
    flutter run -d windows # or macos / linux / android / ios
    ```

On first launch, use the setup wizard to add a channel and fetch or add models, then select a model in the workbench.

## Development

Run the three repository gates after code changes:

```bash
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test -x screenshots
```

For UI changes, also render and inspect `flutter test test/screenshots`. See the
[testing guide](TESTING.md), [architecture index](docs/README.md), and
[repository guidance](AGENTS.md) for test helpers, layering, and localization workflows.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
