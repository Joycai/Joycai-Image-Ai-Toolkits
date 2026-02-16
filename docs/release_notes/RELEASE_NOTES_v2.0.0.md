# Release Notes - v2.0.0 (The Intelligence & Automation Update)

We are proud to announce version 2.0.0 of **Joycai Image AI Toolkits**. This milestone release introduces powerful new automation tools, a completely redesigned onboarding experience, and significant architectural improvements for data integrity and performance.

## 📥 Smart Image Downloader
A brand-new specialized tool for bulk image acquisition.
*   **Web Scraping Engine**: Automatically extract and download images from any URL.
*   **Batch Downloader**: Submit lists of URLs for high-speed concurrent downloads.
*   **Cookie Management**: Built-in support for host-based cookie persistence to handle protected content.
*   **Auto-Categorization**: Automatically organizes downloaded images into subdirectories based on source or metadata.

## 🧙 New User Setup Wizard
A polished first-launch experience to get you up and running in seconds.
*   **Guided Configuration**: Step-by-step setup for AI channels (OpenAI, Gemini).
*   **Model Auto-Discovery**: Automatically scan and add available models from your configured channels.
*   **Directory Initialization**: Easily pick and scan your initial image library.

## 🗄️ Database v22 & Data Integrity
Major overhaul of the persistence layer to support advanced features.
*   **Checkpointing System**: New `usage_checkpoints` table for ultra-fast analytics and historical data tracking.
*   **Multi-Tagging System**: Prompts and System Prompts now support multiple tags simultaneously with a dedicated junction table.
*   **System Prompt Presets**: Integrated standard templates for common tasks like media renaming (Jellyfin/Plex standards).
*   **Performance Monitoring**: Models now track average latency (`est_mean_ms`) and standard deviation to help you choose the fastest provider.

## 🎨 UI & UX Refinements
*   **Enhanced Prompt Management**: Support for Markdown in both user and system prompts.
*   **Sort Order Control**: Manually reorder prompts and tags with drag-and-drop support.
*   **Channel Visuals**: Improved channel tagging with customizable colors and visual indicators across the workbench and task queue.
*   **Markdown Editor**: A new dedicated editor component for professional prompt engineering.

## ⚙️ Core Enhancements
*   **Background Isolate Scanning**: Directory scanning and metadata extraction now run on dedicated Dart isolates, ensuring the UI remains buttery smooth even with tens of thousands of images.
*   **Extended Model Pricing**: Support for both Token-based and Request-based billing modes within Fee Groups.
*   **Security**: Improved API key handling and credential storage.

---
*v2.0.0 marks a transition from a simple toolkit to a comprehensive AI Media Workstation. We can't wait to see what you create with it!*
