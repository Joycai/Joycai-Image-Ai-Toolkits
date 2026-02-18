# Joycai Image AI Toolkits

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=flat&logo=Flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=flat&logo=dart&logoColor=white)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Build Status](https://github.com/Joycai/Joycai-Image-Ai-Toolkits/actions/workflows/flutter-ci.yml/badge.svg)](https://github.com/Joycai/Joycai-Image-Ai-Toolkits/actions)

Joycai Image AI Toolkits 是一个功能强大的跨平台桌面应用程序，使用 Flutter 构建，旨在简化 AI 驱动的图像处理工作流程。它提供了一个统一的界面，用于与各种大型语言模型 (LLM) 和多模态模型进行交互，以实现图像生成、分析和提示词优化。

![应用图标](assets/icon/icon.png)

## 🚀 主要功能

### 🛠️ AI 工作台与动态通道
*   **动态 AI 通道**：添加任意数量的 AI 提供商通道（OpenAI、Google GenAI 或第三方 REST 代理），并支持自定义端点和可视化标签。
*   **统一侧边栏**：全新的可调整大小的悬浮侧边栏，让您无需离开当前上下文即可快速访问 **目录**、**预览**、**比较器** 和 **蒙版编辑器** 工具。
*   **源资源管理器**：通过内置的目录监视和 **后台隔离扫描** 轻松管理本地图像目录，实现零卡顿的性能体验。
*   **统一图库**：在源图像和处理结果之间无缝切换。
*   **控制面板**：通过模型选择、纵横比和分辨率设置微调您的 AI 请求。
*   **AI 提示词优化器**：利用专用模型在提交前优化和“润色”您的提示词。

### 🎨 高级编辑与获取
*   **智能图像下载器**：全新的专业工具，支持从 URL 或批量列表提取并下载图像，内置 Cookie 支持以处理受保护内容。
*   **智能蒙版编辑器**：直接集成在侧边栏中，该工具允许使用手动画笔或 AI 驱动的对象分割进行精确的蒙版创建。
*   **图像比较器**：并排或使用滑动视图比较原始图像和处理后的图像。

### 🔌 生态系统与入驻体验
*   **设置向导**：全新的引导式入驻体验，帮助您快速配置通道并即时发现模型。
*   **MCP 服务器**：内置 **模型上下文协议 (MCP)** 服务器，允许外部客户端（如 Claude Desktop）进行交互。

### 📋 任务队列与提示词管理
*   **多标签提示词**：通过灵活的多标签系统组织您的提示词库。
*   **Markdown 支持**：为用户提示词和系统提示词提供完整的 Markdown 编辑支持。
*   **批量处理**：具有后台隔离扫描功能的高性能批量处理。

### 📊 Token 用量与成本追踪
*   **详细指标**：监控输入和输出 Token 的消耗，支持 **基于模型的计费**。
*   **成本估算**：根据可配置的模型定价（基于 Token 或基于请求）自动计算估算成本。
*   **过滤**：按模型或日期范围分析用量。

### ⚙️ 高级配置
*   **模型管理器**：重新设计的选项卡式界面，用于管理模型和通道。
*   **全局代理支持**：完全支持带身份验证的 HTTP 代理，并提供快速切换开关。
*   **本地化**：完全支持英语和中文（简体中文）。
*   **数据可移植性**：将您的整个配置和历史记录导出和导入为 JSON 格式。

## 🛠️ 技术栈

*   **框架**：[Flutter](https://flutter.dev) (Material 3)
*   **版本**：2.1.0
*   **状态管理**：[Provider](https://pub.dev/packages/provider)
*   **数据库**：[SQLite](https://pub.dev/packages/sqflite) (通过 `sqflite_common_ffi` 支持桌面端)
*   **本地化**：`flutter_localizations` (ARB 文件)
*   **网络**：用于 REST API 通信的 `http`

## 📦 快速开始

### 前置条件
*   Flutter SDK (^3.10.8)
*   [OpenAI](https://platform.openai.com/) 或 [Google Gemini](https://aistudio.google.com/) 的 API 密钥

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
    flutter run -d windows # 或 macos/linux
    ```

## 📄 许可证

本项目采用 MIT 许可证 - 有关详细信息，请参阅 [LICENSE](LICENSE) 文件。
