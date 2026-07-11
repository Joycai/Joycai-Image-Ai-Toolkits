# Joycai Image AI Toolkits

[![Flutter](https://img.shields.io/badge/Flutter-3.41.1-%2302569B.svg?style=flat&logo=Flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=flat&logo=dart&logoColor=white)](https://dart.dev)
[![Version](https://img.shields.io/badge/version-2.13.0-blue.svg)](https://github.com/Joycai/Joycai-Image-Ai-Toolkits/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Build Status](https://github.com/Joycai/Joycai-Image-Ai-Toolkits/actions/workflows/flutter-ci.yml/badge.svg)](https://github.com/Joycai/Joycai-Image-Ai-Toolkits/actions)

Joycai Image AI Toolkits 是一个功能强大的跨平台桌面与移动应用程序，使用 Flutter 构建，旨在简化 AI 驱动的图像与视频处理工作流程。它提供了一个统一的界面，用于与各种大型语言模型 (LLM) 和多模态模型进行交互，实现图像生成、分析、提示词优化、视频生成等功能。

![应用图标](assets/icon/icon.png)

## 🚀 主要功能

### 🛠️ AI 工作台与动态通道
*   **动态 AI 通道**：添加任意数量的 AI 提供商通道（OpenAI、Google GenAI 或第三方 OpenAI 兼容 REST 代理），支持自定义端点和可视化标签。
*   **统一侧边栏**：可调整大小的悬浮侧边栏，让您无需离开当前上下文即可快速访问 **目录**、**预览**、**比较器** 和 **蒙版编辑器** 工具。
*   **源资源管理器**：通过内置的目录监视和 **后台隔离扫描** 轻松管理本地图像目录，实现零卡顿的性能体验。
*   **统一图库**：在源图像和处理结果之间无缝切换。
*   **控制面板**：通过模型选择、纵横比和分辨率设置微调您的 AI 请求。
*   **AI 提示词优化器**：利用专用模型在提交前优化和"润色"您的提示词。

### 🎬 视频生成
*   **AI 视频生成**：直接从工作台通过 Google Veo 模型生成视频，支持首帧、尾帧和参考图像输入。
*   **可配置分辨率与纵横比**：可选择 720p / 1080p / 4K 和 16:9 / 9:16 输出格式。
*   **异步长时运行任务**：视频生成任务通过轮询方式异步运行，并在任务队列中实时追踪进度。

### 🎨 高级编辑与获取
*   **智能图像下载器**：支持从 URL 或批量列表提取并下载图像，内置 Cookie 支持以处理需验证的受保护站点。
*   **智能蒙版编辑器**：直接集成在侧边栏中，支持使用手动画笔或 AI 驱动的对象分割进行精确的蒙版创建。
*   **图像比较器**：并排或使用滑动视图比较原始图像和处理后的图像。
*   **AI 文件重命名器**：通过文件浏览器，使用 AI 模型和自定义指令批量重命名文件。

### 🔌 生态系统与入驻体验
*   **设置向导**：全新的引导式入驻体验，帮助您在首次启动时快速配置通道并发现模型。
*   **MCP 服务器**：内置 **模型上下文协议 (MCP)** 服务器，允许外部客户端（如 Claude Desktop）进行交互。
*   **模型自动发现**：自动从任何已配置的通道/提供商获取可用模型列表。

### 📋 任务队列与提示词管理
*   **持久化任务队列**：支持五种任务类型——`imageProcess`（图像处理）、`promptRefine`（提示词优化）、`imageDownload`（图像下载）、`aiRename`（AI 重命名）、`videoGenerate`（视频生成），可配置并发数和重试次数。
*   **实时流式输出**：通过 `Stream<TaskEvent>` 实时推送后台任务的日志和结果。
*   **基于模型的 ETA 估算**：每 10 次任务完成后自动更新各模型的时长预测。
*   **多标签提示词**：通过灵活的多标签系统组织您的提示词库。
*   **Markdown 支持**：为用户提示词和系统提示词提供完整的 Markdown 编辑支持。

### 📊 Token 用量与成本追踪
*   **详细指标**：按模型监控输入和输出 Token 的消耗。
*   **双计费模式**：支持基于 Token 或基于请求次数的计费，并可配置定价组。
*   **成本估算**：根据可配置的模型定价自动计算估算成本。
*   **过滤**：按模型或日期范围分析用量。

### ⚙️ 高级配置
*   **模型管理器**：选项卡式界面，用于管理模型和通道，支持定价组分配。
*   **全局代理支持**：完全支持带身份验证的 HTTP 代理，并提供快速切换开关。
*   **本地化**：完全支持英语 (`en`)、简体中文 (`zh`)、繁体中文 (`zh_Hant`) 和日语 (`ja`)。
*   **主题定制**：Material 3 动态主题，支持自定义种子色和深色/浅色/跟随系统模式。
*   **数据可移植性**：将整个配置和历史记录导出和导入为 JSON 格式。

## 🛠️ 技术栈

*   **框架**：[Flutter](https://flutter.dev) (Material 3)，版本 3.41.1
*   **应用版本**：2.13.0
*   **状态管理**：[Provider](https://pub.dev/packages/provider) — 多状态类（`AppState`、`GalleryState`、`FileBrowserState`、`DownloaderState`、`WorkbenchUIState`）
*   **数据库**：[SQLite](https://pub.dev/packages/sqflite)（通过 `sqflite_common_ffi` 支持桌面端）
*   **本地化**：`flutter_localizations`，使用 `lib/l10n/src/` 中的模块化 ARB 源文件
*   **网络**：`http` 用于 REST API 通信；`shelf` / `shelf_router` 用于本地 MCP/抓取器服务器
*   **媒体**：`photo_view`、`extended_image`、`video_player` 用于显示；`desktop_drop`、`file_picker` 用于文件输入

## 📦 快速开始

### 前置条件
*   Flutter SDK (^3.10.8，已在 3.41.1 上测试)
*   [OpenAI](https://platform.openai.com/) 或 [Google Gemini / Veo](https://aistudio.google.com/) 的 API 密钥

### 安装
1.  克隆仓库：
    ```bash
    git clone https://github.com/Joycai/Joycai-Image-Ai-Toolkits.git
    ```
2.  安装依赖：
    ```bash
    flutter pub get
    ```
3.  生成本地化文件：
    ```bash
    flutter gen-l10n
    ```
4.  运行应用程序：
    ```bash
    flutter run -d windows # 或 macos / linux / android / ios
    ```

## 📄 许可证

本项目采用 MIT 许可证 - 有关详细信息，请参阅 [LICENSE](LICENSE) 文件。
