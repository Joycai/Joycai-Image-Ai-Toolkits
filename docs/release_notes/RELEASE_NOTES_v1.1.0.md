# Release Notes - v1.1.0

We are excited to announce the release of version 1.1.0 of **Joycai Image AI Toolkits**. This update introduces the Model Context Protocol (MCP) for better interoperability, significant macOS optimizations, and enhanced billing management.

## 🌟 New Features

### 🔌 Model Context Protocol (MCP) Server
*   **Integrated MCP Server**: The toolkit now includes a built-in MCP server, allowing external clients (like Claude Desktop) to interact with the application's tools.
*   **Configurable Settings**: Enable/disable the MCP server and customize the communication port directly from the Settings screen.
*   **Tool Support**: Initial support for listing gallery images and managing tasks via the protocol.

### 🍎 macOS Platform Optimizations
*   **Sandbox Removal**: Explicitly disabled the App Sandbox to provide seamless, persistent access to local image directories without security-scoped bookmark overhead.
*   **Standardized Storage**: Migrated the application database and configuration to the standard `Application Support` directory, including an automatic migration routine for existing users.
*   **Native Build Script**: Added `build_script/build_macos.sh` for automated release packaging into a DMG installer.

### 💰 Billing & Model Management
*   **Model-Based Billing**: Introduced flexible billing modes (Token-based vs. Request-based) for more accurate cost tracking.
*   **Fee Groups**: Support for input/output fees and flat request fees per model.
*   **Enhanced Providers**: Improved robustness for Google GenAI and OpenAI API integrations.

## 🛠️ UI/UX Improvements
*   **Responsive Gallery**: Tabs and toolbars in the Workbench are now scrollable, preventing layout overflows on smaller windows.
*   **Prompt Management**: Redesigned prompt library picker and added support for exporting/importing prompts as JSON.
*   **Customization**: Added support for custom filename prefixes for generated images.
*   **Information**: The application version is now clearly displayed in the window title.

## 🔧 Fixes & Internal Changes
*   **Performance**: Switched to asynchronous I/O for directory scanning to eliminate UI freezes when loading large image libraries.
*   **Quality**: Resolved multiple static analysis linting issues and fixed a broken widget test.
*   **App Data Access**: Added a localized button in Settings to quickly open the app's internal data directory.

---
*For more details on setting up the new MCP feature, please refer to the `docs/MCP_GUIDE.md`.*
