# Joycai Image AI Toolkits

[![Flutter](https://img.shields.io/badge/Flutter-3.41.1-%2302569B.svg?style=flat&logo=Flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=flat&logo=dart&logoColor=white)](https://dart.dev)
[![Version](https://img.shields.io/badge/version-3.5.0-blue.svg)](https://github.com/Joycai/Joycai-Image-Ai-Toolkits/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Build Status](https://github.com/Joycai/Joycai-Image-Ai-Toolkits/actions/workflows/flutter-ci.yml/badge.svg)](https://github.com/Joycai/Joycai-Image-Ai-Toolkits/actions)

Joycai Image AI Toolkits is a powerful, cross-platform desktop & mobile application built with Flutter, designed to streamline AI-powered image and video processing workflows. It provides a unified interface to interact with various Large Language Models (LLMs) and Multimodal models for image generation, analysis, prompt optimization, video generation, and more.

![App Icon](assets/icon/icon.png)

## 🚀 Key Features

### 🛠️ AI Workbench & Dynamic Channels
*   **Dynamic AI Channels**: Add any number of AI provider channels (OpenAI, Google GenAI, or 3rd-party OpenAI-compatible REST proxies) with custom endpoints and visual tags.
*   **Unified Sidebar**: A resizable overlay sidebar providing quick access to **Directories**, **Preview**, **Comparator**, and **Mask Editor** tools without leaving your current context.
*   **Source Explorer**: Easily manage local image directories with built-in directory watching and **Background Isolate Scanning** for zero-stutter performance.
*   **Unified Gallery**: Seamlessly switch between source images and processed results.
*   **Control Panel**: Fine-tune your AI requests with model selection, aspect ratio, and resolution settings.
*   **AI Prompt Refiner**: Leverage specialized models to optimize and "polish" your prompts before submission.

### 🎬 Video Generation
*   **AI Video Generation**: Generate videos via Google Veo models directly from the workbench, with support for first-frame, last-frame, and reference image inputs.
*   **Configurable Resolution & Aspect Ratio**: Choose from 720p / 1080p / 4K and 16:9 / 9:16 output formats.
*   **Async Long-Running Operations**: Video generation tasks run via polling, with progress tracking in the Task Queue.

### 🎨 Advanced Editing & Acquisition
*   **Smart Image Downloader**: Extract and download images from URLs or bulk lists with cookie support for authenticated/protected sites.
*   **Smart Mask Editor**: Integrated into the sidebar for precise mask creation using manual brushes or AI-powered object segmentation.
*   **Image Comparator**: Compare raw and processed images side-by-side or with a sliding swap view.
*   **AI File Renamer**: Batch-rename files using an AI model with custom instructions via the File Browser.

### 🔌 Ecosystem & Onboarding
*   **Setup Wizard**: A guided onboarding experience to configure channels and discover models on first launch.
*   **MCP Server**: Built-in **Model Context Protocol (MCP)** server for external client integration (e.g., Claude Desktop).
*   **Model Auto-Discovery**: Automatically fetch available models from any configured channel/provider.

### 📋 Task Queue & Prompt Management
*   **Persistent Task Queue**: Five task types — `imageProcess`, `promptRefine`, `imageDownload`, `aiRename`, `videoGenerate` — with configurable concurrency and retry support.
*   **Real-time Streaming**: Live log and result streaming from background tasks via `Stream<TaskEvent>`.
*   **Model-Based ETA**: Automatic task duration estimation per model, updated after every 10 completions.
*   **Multi-Tag Prompts**: Organise your prompt library with a flexible multi-tag system.
*   **Markdown Support**: Full Markdown editing for both user and system prompts.

### 📊 Token Usage & Cost Tracking
*   **Detailed Metrics**: Monitor input and output token consumption per model.
*   **Dual Billing Modes**: Token-based or Request-based billing with configurable pricing groups.
*   **Cost Estimation**: Automatically calculate estimated costs based on configurable model pricing.
*   **Filtering**: Analyze usage by model or date range.

### ⚙️ Advanced Configuration
*   **Model Manager**: Tabbed interface for managing models and channels, including pricing group assignment.
*   **Global Proxy Support**: Full support for authenticated HTTP proxies with a quick-toggle switch.
*   **Localization**: Full support for English (`en`), Simplified Chinese (`zh`), Traditional Chinese (`zh_Hant`), and Japanese (`ja`).
*   **Theming**: Material 3 dynamic theming with configurable seed color and dark/light/system mode.
*   **Data Portability**: Export and import your entire configuration and history as JSON.

## 🛠️ Technical Stack

*   **Framework**: [Flutter](https://flutter.dev) (Material 3), version 3.41.1
*   **App Version**: 3.5.0
*   **State Management**: [Provider](https://pub.dev/packages/provider) — multi-state (`AppState`, `GalleryState`, `FileBrowserState`, `DownloaderState`, `WorkbenchUIState`)
*   **Database**: [SQLite](https://pub.dev/packages/sqflite) (via `sqflite_common_ffi` for Desktop support)
*   **Localization**: `flutter_localizations` with modular ARB source files in `lib/l10n/src/`
*   **Networking**: `http` for REST API communication; `shelf` / `shelf_router` for local MCP/scraper server
*   **Media**: `photo_view`, `extended_image`, `video_player` for display; `desktop_drop`, `file_picker` for input

## 📦 Getting Started

### Prerequisites
*   Flutter SDK (^3.10.8, tested on 3.41.1)
*   API Keys for [OpenAI](https://platform.openai.com/) or [Google Gemini / Veo](https://aistudio.google.com/)

### Installation
1.  Clone the repository:
    ```bash
    git clone https://github.com/Joycai/Joycai-Image-Ai-Toolkits.git
    ```
2.  Install dependencies:
    ```bash
    flutter pub get
    ```
3.  Generate localization files:
    ```bash
    flutter gen-l10n
    ```
4.  Run the application:
    ```bash
    flutter run -d windows # or macos / linux / android / ios
    ```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
