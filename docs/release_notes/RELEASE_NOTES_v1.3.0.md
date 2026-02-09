# Release Notes - v1.3.0

## Summary
Version 1.3.0 is a massive update that introduces powerful new tools for asset acquisition, local file management, and UI productivity. This release transforms the toolkit into a more comprehensive workstation for AI image professionals.

## 🚀 New Features
- **AI Image Downloader**: A dedicated screen for searching and downloading images directly from the web, integrated with a scraper service.
- **File Browser & AI Batch Rename**: A full-featured file browser within the app, allowing for organized file management and intelligent, AI-powered batch renaming of local assets.
- **Floating Preview & Comparator**: New floating window system that allows users to keep an image preview or comparison tool visible while navigating other parts of the app.
- **Mask Editor**: A new dialog for creating and editing image masks, essential for inpainting and specialized AI workflows.
- **Send to Selection**: New context menu action to quickly move gallery items to the active selection or other tools.

## 🛠 Improvements & Refactorings
- **Performance Optimization**: Completely redesigned image library scanning using background isolates, ensuring zero UI stutter even with thousands of files.
- **UI Modernization**: Significant updates to the Workbench, Models screen, and Prompts screen for better usability and Material 3 adherence.
- **Repository Pattern**: Refactored data access logic into specialized repositories (Model, Prompt, Task, Usage) for better maintainability and testability.
- **Enhanced Notifications**: Improved system notification service for background task completion.
- **Window State Management**: Introduced a dedicated `WindowState` to handle floating windows and complex UI persistence.

## 🐞 Bug Fixes
- Resolved layout overflows and hit-test exceptions in complex desktop views.
- Fixed localization inconsistencies in English and Chinese.
- Corrected coordinate handling in the gallery and preview dialogs.

## 📝 Documentation
- Updated README with new features and project badges.
- Improved internal API documentation for the new repository architecture.

---
*Thank you for being part of the Joycai community! This update provides the foundation for more advanced AI interaction models coming in the future.*
