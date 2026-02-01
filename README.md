# Joycai Image AI Toolkits

Joycai Image AI Toolkits is a powerful, cross-platform desktop application built with Flutter, designed to streamline AI-powered image processing workflows. It provides a unified interface to interact with various Large Language Models (LLMs) and Multimodal models for image generation, analysis, and prompt optimization.

![App Icon](assets/icon/icon.png)

## 🚀 Key Features

### 🛠️ AI Workbench
*   **Source Explorer**: Easily manage local image directories with built-in directory watching.
*   **Unified Gallery**: Seamlessly switch between source images and processed results.
*   **Control Panel**: Fine-tune your AI requests with model selection, aspect ratio, and resolution settings.
*   **AI Prompt Refiner**: Leverage specialized models to optimize and "polish" your prompts before submission.

### 📋 Task Queue Manager
*   **Batch Processing**: Submit multiple images for processing in a single click.
*   **Concurrency Control**: Manage system resources by limiting the number of simultaneous AI tasks.
*   **Persistence**: All tasks are saved to a local database, ensuring progress is kept even after an app restart.
*   **Real-time Monitoring**: Track task status, view live execution logs, and manage pending/completed tasks.

### 📚 Prompt Library
*   **Save & Organize**: Build your own library of high-performing prompts.
*   **Categorization**: Tag prompts for different use cases (e.g., "Refiner", "Anime", "Realistic").
*   **Quick Access**: Directly pick prompts from your library within the Workbench.

### 📊 Token Usage & Cost Tracking
*   **Detailed Metrics**: Monitor input and output token consumption.
*   **Cost Estimation**: Automatically calculate estimated costs based on configurable model pricing.
*   **Filtering**: Analyze usage by model or date range (Today, Last Week, etc.).

### ⚙️ Advanced Configuration
*   **Model Manager**: Add and configure custom models for OpenAI and Google GenAI providers.
*   **Multi-Provider Support**: Configure separate endpoints and API keys for free and paid tiers.
*   **Localization**: Full support for English and Chinese (简体中文).
*   **Theme Support**: Material 3 design with Light, Dark, and Auto (System) modes.
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
