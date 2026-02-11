# Release Notes - v1.4.0 (The Responsive & Performance Update)

We are thrilled to announce version 1.4.0 of **Joycai Image AI Toolkits**. This major update focuses on providing a professional, high-performance experience across all device sizes—from mobile phones to ultrawide desktop monitors—while significantly optimizing the underlying data processing logic.

## 📱 Adaptive UI & UX Redesign
The entire application has been re-engineered with a mobile-first, desktop-optimized philosophy.

### Master-Detail Layouts (Desktop)
*   **Prompts & Models**: Replaced full-width lists with professional Split-View interfaces. A persistent sidebar now allows for instantaneous category switching and model management.
*   **Task Queue**: Added a new summary sidebar providing real-time stats (Pending, Running, Completed) and centralized global controls.
*   **Settings**: Grouped configurations into logical categories accessible via a clean side navigation pane.

### Mobile Optimization
*   **Hybrid Navigation**: Refined the main navigation bar to prioritize essential tools, moving secondary actions into a clean "More" drawer to eliminate icon crowding.
*   **Responsive Toolbars**: Standardized `AppBar` usage across all screens, integrating navigation toggles and core actions.
*   **Adaptive Controls**: Summary cards and data action grids now stack logically on small screens to prevent horizontal overflow and ensure large touch targets.

### Intelligent Window Management
*   **Boundary Awareness**: Floating windows (Preview and Comparator) now automatically detect screen boundaries and reposition themselves during window resizing.
*   **Mobile Mode**: On narrow screens, floating windows now default to a maximized state for a native-app feel.

## ⚡ High-Performance Analytics
We've overhauled how the app handles large datasets to ensure a 60FPS fluid experience.

*   **Checkpoint + Offset Calculation**: Optimized Token Usage statistics using a new database checkpointing system. This reduces computational complexity from $O(N)$ to $O(1)$ lookup for historical data.
*   **Usage List Pagination**: The usage history now supports "Load More" scrolling, preventing UI freezes when viewing thousands of past AI interactions.
*   **Smart Log Console**: A redesigned terminal-style console featuring:
    *   **Level Filtering**: Toggle view for ERRORS, SUCCESS, or RUNNING tasks.
    *   **Smart Auto-Scroll**: Read history without being interrupted by new incoming logs.
    *   **Integrated Search**: Instantly find specific task IDs or log messages.

## 🔧 Internal Improvements
*   **Temporary Directory Migration**: Downloader caches and Mask Editor outputs are now stored in OS-managed temporary directories, keeping your permanent application folders clean.
*   **Automated Quality Suite**: Introduced a comprehensive responsive layout test suite that programmatically catches UI overflows and build errors before they reach production.
*   **Input Sanitization**: Improved robustness of API configuration fields with automatic whitespace trimming and validation.

## 🐞 Fixed in this Release
*   Resolved a critical `StateError` when viewing usage statistics with deleted Fee Groups.
*   Fixed multiple `RenderBox` constraint exceptions on narrow mobile screens.
*   Standardized theme and language selection controls to prevent layout "jittering" during transitions.

---
*Thank you for supporting Joycai Image AI Toolkits! This update represents our commitment to building a scalable, professional workstation for AI artists and researchers.*
