# Joycai Image AI Toolkits

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=flat&logo=Flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=flat&logo=dart&logoColor=white)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Build Status](https://github.com/Joycai/Joycai-Image-Ai-Toolkits/actions/workflows/flutter-ci.yml/badge.svg)](https://github.com/Joycai/Joycai-Image-Ai-Toolkits/actions)

Joycai Image AI Toolkits is a powerful, cross-platform desktop application built with Flutter, designed to streamline AI-powered image processing workflows. It provides a unified interface to interact with various Large Language Models (LLMs) and Multimodal models for image generation, analysis, and prompt optimization.

![App Icon](assets/icon/icon.png)

## 🚀 Key Features

### 🛠️ AI Workbench & Dynamic Channels
*   **Dynamic AI Channels**: Add any number of AI provider channels (OpenAI, Google GenAI, or 3rd-party REST proxies) with custom endpoints and visual tags.
*   **Source Explorer**: Easily manage local image directories with built-in directory watching and **Background Isolate Scanning** for zero-stutter performance.
*   **Unified Gallery**: Seamlessly switch between source images and processed results.
*   **Control Panel**: Fine-tune your AI requests with model selection, aspect ratio, and resolution settings.
*   **AI Prompt Refiner**: Leverage specialized models to optimize and "polish" your prompts before submission.

### 📝 Staging Prompt Workbench
*   **Drafting Pane**: Build complex prompts by iteratively adding or replacing snippets from your library in a professional three-pane layout.
*   **Manual Staging**: Edit your combined prompt in a dedicated area before committing it to your work.
*   **Append/Overwrite**: Choose exactly how to apply your drafted prompt to the workbench.

### 🔌 Ecosystem & Interoperability
*   **MCP Server**: Built-in **Model Context Protocol (MCP)** server allows external clients (like Claude Desktop) to interact with your image gallery and tasks.
*   **Multi-Platform**: Professional installers and portable bundles for **Windows (MSIX/ZIP)**, **macOS (DMG)**, and **Linux (TAR.GZ)**.

### 📋 Task Queue Manager
*   **Batch Processing**: Submit multiple images for processing in a single click.
*   **Concurrency Control**: Manage system resources by limiting the number of simultaneous AI tasks.
*   **Persistence**: All tasks are saved to a local database (SQLite), ensuring progress is kept even after an app restart.

### 📊 Token Usage & Cost Tracking
*   **Detailed Metrics**: Monitor input and output token consumption with **Model-Based Billing** support.
*   **Cost Estimation**: Automatically calculate estimated costs based on configurable model pricing (Token-based vs. Request-based).
*   **Filtering**: Analyze usage by model or date range.

### ⚙️ Advanced Configuration
*   **Model Manager**: Redesigned tabbed interface for managing models and channels.
*   **Global Proxy Support**: Full support for authenticated HTTP proxies with a quick-toggle switch.
*   **Localization**: Full support for English and Chinese (简体中文).
*   **Data Portability**: Export and import your entire configuration and history as JSON.

## 🛠️ Technical Stack

*   **Framework**: [Flutter](https://flutter.dev) (Material 3)
*   **State Management**: [Provider](https://pub.dev/packages/provider)
*   **Database**: [SQLite](https://pub.dev/packages/sqflite) (via `sqflite_common_ffi` for Desktop support)
*   **Localization**: `flutter_localizations` (ARB files)
*   **Networking**: `http` for REST API communication

## 📦 Getting Started

### Prerequisites
*   Flutter SDK (^3.10.8)
*   API Keys for [OpenAI](https://platform.openai.com/) or [Google Gemini](https://aistudio.google.com/)

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
    flutter run -d windows # or macos/linux
    ```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
