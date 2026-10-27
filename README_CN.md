# Joycai Image AI Toolkits

[![Flutter](https://img.shields.io/badge/Flutter-3.47.8-%2302569B.svg?style=flat&logo=Flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=flat&logo=dart&logoColor=white)](https://dart.dev)
[![Version](https://img.shields.io/badge/version-4.31.6-blue.svg)](https://github.com/Joycai/Joycai-Image-Ai-Toolkits/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Build Status](https://github.com/Joycai/Joycai-Image-Ai-Toolkits/actions/workflows/flutter-ci.yml/badge.svg)](https://github.com/Joycai/Joycai-Image-Ai-Toolkits/actions)

Joycai Image AI Toolkits 是一个功能强大的跨平台桌面与移动应用程序，使用 Flutter 构建，旨在简化 AI 驱动的图像与视频处理工作流程。它提供了一个统一的界面，用于与各种大型语言模型 (LLM) 和多模态模型进行交互，实现图像生成、分析、提示词优化、视频生成等功能。

[English](README.md) · [开发文档](docs/README.md) · [测试指南](TESTING.md)

![应用图标](assets/icon/icon.png)

## 🚀 主要功能

### 🛠️ AI 工作台与动态通道

*   **动态 AI 通道**：支持 OpenAI、Google Gemini、Anthropic、xAI、DeepSeek、MiniMax、DashScope、火山引擎 Ark、Midjourney 代理、New API 中转及本地 Ollama / LM Studio。可用能力取决于模型与请求路由。
*   **模型专属参数**：图像与视频表单根据所选模型显示尺寸、质量、输出格式、参考图数量等选项；兼容别名可指定原生能力配置。
*   **统一侧边栏**：可调整大小的悬浮侧边栏，让您无需离开当前上下文即可快速访问 **目录**、**预览**、**比较器** 和 **蒙版编辑器** 工具。
*   **源资源管理器**：通过内置的目录监视和 **后台隔离扫描** 轻松管理本地图像目录，将扫描工作移出 UI isolate。
*   **统一图库**：在源图像和处理结果之间无缝切换。
*   **控制面板**：通过模型选择、纵横比和分辨率设置微调您的 AI 请求。
*   **提示词助手**：通过多轮对话、参考图、持久化知识库、已保存会话和子代理优化提示词，并将结果应用到工作台。
*   **GPT Image 异步 Batch**：支持通过 OpenAI 官方原生 Images 路由提交适用的 GPT Image 模型；重启后继续轮询远程任务，支持刷新与取消。每个任务生成一张图，不提供部分预览，详见 [Batch 行为与恢复](docs/api/gpt-image-series.md#asynchronous-batch-images-2026-10-26)。
*   **GPT Image 流式出图**：在支持的路由显示部分预览并保存最终结果；可配置的软超时会继续等待迟到结果，不会重复提交生成。

### 🎬 视频生成

*   **AI 视频生成**：支持 Google Veo、xAI、DashScope 和 MiniMax 的适用模型；首帧、尾帧、参考图与音频选项取决于模型和请求路由。
*   **可配置分辨率与纵横比**：根据所选模型选择支持的分辨率、纵横比与时长。
*   **异步长时运行任务**：视频生成任务通过轮询方式异步运行，并在任务队列中实时追踪进度。

### 🎨 高级编辑与获取

*   **智能图像下载器**：支持从 URL 或批量列表提取并下载图像，内置 Cookie 支持以处理需验证的受保护站点。
*   **图像编辑**：支持裁剪、缩放、手绘蒙版，以及适用模型的透明编辑和 Seedream 拆图层；可查看图层并导出合成 PNG。
*   **图像比较器**：并排或使用滑动视图比较原始图像和处理后的图像。
*   **AI 文件重命名器**：通过文件浏览器，使用 AI 模型和自定义指令批量重命名文件。

### 🔌 生态系统与入驻体验

*   **设置向导**：全新的引导式入驻体验，帮助您在首次启动时快速配置通道并发现模型。
*   **本地 MCP 图像服务器**：桌面端外部代理可发现已配置的图像模型、查看参数 schema、提交文生图或参考图生成、轮询任务并读取结果。在设置 → 连接中启用带鉴权的回环服务器，详见 [连接与工具说明](docs/architecture/mcp-image-server.md)。
*   **模型自动发现**：在支持的通道获取模型列表，也可使用提供商预设或手动添加模型 ID。

### 📋 任务队列与提示词管理

*   **持久化任务队列**：支持五种任务类型——`imageProcess`（图像处理）、`promptRefine`（提示词优化）、`imageDownload`（图像下载）、`aiRename`（AI 重命名）、`videoGenerate`（视频生成），可配置并发数和重试次数。
*   **实时流式输出**：通过 `Stream<TaskEvent>` 实时推送后台任务的日志和结果。
*   **桌面处理计数**：macOS Dock 和 Windows 任务栏显示正在处理的任务数，不包含等待远程 Batch 的任务。
*   **基于模型的 ETA 估算**：每 10 次任务完成后自动更新各模型的时长预测。
*   **多标签提示词**：通过灵活的多标签系统组织您的提示词库。
*   **Markdown 支持**：为用户提示词和系统提示词提供完整的 Markdown 编辑支持。

### 📊 Token 用量与成本追踪

*   **详细指标**：按模型监控输入和输出 Token 的消耗。
*   **灵活计费**：支持按 Token、按请求和按规格计费，可配置费率组并记录缓存 Token。
*   **成本估算**：根据可配置的模型定价自动计算估算成本。
*   **过滤**：按模型或日期范围分析用量。

### ⚙️ 高级配置

*   **模型管理器**：选项卡式界面，用于管理模型和通道，支持定价组分配。
*   **全局代理支持**：完全支持带身份验证的 HTTP 代理，并提供快速切换开关。
*   **本地化**：完全支持英语 (`en`)、简体中文 (`zh`)、繁体中文 (`zh_Hant`) 和日语 (`ja`)。
*   **主题定制**：暖石色表面、玻璃控件、八种强调色，以及深色/浅色/跟随系统模式；适配手机、平板与桌面布局。
*   **数据可移植性**：以 JSON 导入导出配置、提示词库及可选的用量记录。API 密钥、Cookie、代理密码和本地 MCP 授权会被脱敏；不包含任务历史和生成媒体。

## 🛠️ 技术栈

*   **框架**：[Flutter](https://flutter.dev) (Material 3)，版本 3.47.8
*   **Dart SDK**：`^3.13.0`
*   **应用版本**：4.31.6
*   **状态管理**：[Provider](https://pub.dev/packages/provider) — `AppState` 协调图库、文件浏览、暂存、下载、模型、工作台、任务、日志及 MCP 等独立状态
*   **数据库**：[SQLite](https://pub.dev/packages/sqflite)（通过 `sqflite_common_ffi` 支持桌面端）
*   **本地化**：`flutter_localizations`，使用 `lib/l10n/src/` 中的模块化 ARB 源文件
*   **网络**：`http` 用于 REST API 通信
*   **媒体**：`extended_image`、`video_player` 用于显示；`desktop_drop`、`file_picker` 用于文件输入

## 📦 快速开始

### 前置条件

*   Flutter SDK 3.47.8（包含 Dart 3.13.7；CI 和发布构建使用此版本）
*   目标平台的原生构建工具（参见 [构建配置](.github/workflows/flutter-build.yml)）。发布自动化构建 Windows、macOS、Linux 和 Android；iOS 需本地 Apple 工具链及签名。
*   所选托管服务的 API 密钥，或已运行的本地 Ollama / LM Studio 服务。

文件浏览器和下载器仅在桌面平台提供，在 Android/iOS 隐藏；应用不面向 Flutter Web。

### 安装

1.  克隆仓库：
    ```bash
    git clone https://github.com/Joycai/Joycai-Image-Ai-Toolkits.git
    cd Joycai-Image-Ai-Toolkits
    ```
2.  安装依赖：
    ```bash
    flutter pub get
    ```
3.  生成本地化文件：
    ```bash
    dart tool/merge_l10n.dart
    flutter gen-l10n
    ```
4.  运行应用程序：
    ```bash
    flutter run -d windows # 或 macos / linux / android / ios
    ```

首次启动时，通过设置向导添加通道并获取或添加模型，然后在工作台选择模型。

## 开发

代码变更后运行仓库的三项检查：

```bash
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test -x screenshots
```

UI 变更还需运行 `flutter test test/screenshots` 并查看渲染图片。测试辅助工具、分层约束及本地化流程见
[测试指南](TESTING.md)、[架构文档索引](docs/README.md) 和 [仓库指南](AGENTS.md)。

## 📄 许可证

本项目采用 MIT 许可证 - 有关详细信息，请参阅 [LICENSE](LICENSE) 文件。
