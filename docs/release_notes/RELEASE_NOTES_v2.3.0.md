# Release Notes - v2.3.0 (The UX, Layout & Mobile Optimization Update)

Welcome to version 2.3.0 of **Joycai Image AI Toolkits**. This release brings massive user experience refinements across three major phases: Workflow Efficiency, Layout Polish, and Mobile/Tablet Optimization. It also expands video compatibility and includes critical stability updates.

## ⚡ Workflow Efficiency (Phase 1)
Enhance your productivity with fast media routing and bulk operations:
*   **Gallery Context Shortcuts**: Right-click (or long-press) any image in the gallery to immediately route it as the first frame, last frame, or reference asset in the Video Workbench.
*   **Unified Prompt Search**: Enjoy a consistent search input layout across all platforms (Mobile `SliverAppBar` vs Desktop `AppBar`).
*   **Prompt Bulk Actions**: Long-press prompt list cards to enter selection mode, then bulk delete or bulk apply categories/tags using the new floating action bar.

## ✨ Layout Polish (Phase 2)
Micro-animations and layout details for a premium look and feel:
*   **Resizable Workbench Dividers**: Interactive divider hit area increased from 4px to 10px for easier targeting. Added a hover highlight animation that widens the line and tints it in the primary theme color.
*   **Collapsible Cards**: Refactored cards to expand and collapse using a smooth native `SizeTransition` coupled with an arrow `RotationTransition` for seamless transitions.

## 📱 Mobile/Tablet Optimization (Phase 3)
A fully optimized interface for smaller screens:
*   **Adaptive Frame Stacking**: Video reference frame slots stack vertically on mobile screens.
*   **Tap-to-Pick Targets**: Tapping empty frame slots on mobile now automatically slides open the gallery drawer to let you select images quickly.
*   **Task Summary Bar**: Added a compact active/pending task counter at the bottom of the mobile screen. Tapping it opens the task queue inside a smooth modal bottom sheet.
*   **Quick Concurrency Control**: Access task concurrency limits directly from a mobile-exclusive pop-up "More" menu without navigating away from the workspace.

## ⚙️ Backend & Quality Upgrades
*   **OpenAI Video Support**: Implemented simulated Long Running Operation (LRO) support for OpenAI video models (e.g. Sora-based or generic video models) to enable mock testing.
*   **Layout & Linter Fixes**: Resolved ListTile assertion crashes, fixed mobile layout overflows, cleaned up null-aware spreads, and removed deprecated onReorder warnings.

---
*v2.3.0 makes Joycai Image AI Toolkits feel more responsive, polished, and mobile-friendly than ever. Thank you for your feedback!*
