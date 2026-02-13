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

### 🎨 高级编辑工具
*   **智能蒙版编辑器**：直接集成在侧边栏中，该工具允许使用手动画笔或 AI 驱动的对象分割进行精确的蒙版创建。
*   **图像比较器**：并排或使用滑动交换视图比较原始图像和处理后的图像，以详细分析变化。
*   **预览模式**：通过缩放和平移功能快速查看图像的完整细节。

### 🔌 生态系统与互操作性
*   **MCP 服务器**：内置 **模型上下文协议 (MCP)** 服务器，允许外部客户端（如 Claude Desktop）与您的图像库和任务进行交互。
*   **多平台支持**：为 **Windows (MSIX/ZIP)**、**macOS (DMG)** 和 **Linux (TAR.GZ)** 提供专业的安装程序和便携式软件包。

### 📋 任务队列管理器
*   **批量处理**：一键提交多张图像进行处理。
*   **并发控制**：通过限制同时进行的 AI 任务数量来管理系统资源。
*   **持久化**：所有任务都保存到本地数据库 (SQLite)，确保即使在应用重启后进度也能保留。

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
