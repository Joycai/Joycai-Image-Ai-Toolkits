✦ Release Notes - v1.2.0 (The Workbench & Ecosystem Update)


We are excited to announce v1.2.0, a major milestone that transforms Joycai Image AI Toolkits from a specialized tool into a flexible, multi-provider platform. This update focuses on power-user features, performance, and
professional distribution.

  ---

🚀 New Features


🌐 Dynamic AI Channels
You are no longer limited to fixed providers!
* Custom Endpoints: Add any number of AI provider channels (OpenAI, Google GenAI, or 3rd-party REST proxies).
* Official Google Support: Dedicated support for the official Google GenAI API with specialized authentication.
* Visual Organization: Assign custom tags and colors to each channel to easily identify which provider is powering your models.


📝 Staging Prompt Workbench
The Prompt Library has been reimagined as a professional drafting area.
* Drafting Pane: A new three-pane layout allows you to build complex prompts by iteratively adding or replacing snippets from your library.
* Manual Staging: Edit your combined prompt in a dedicated area before committing it to your work.
* Append/Overwrite: Choose exactly how to apply your drafted prompt to the workbench.


🎨 Decoupled Category Management
Organize your prompts your way.
* Standalone Categories: Manage prompt tags independently with custom names and colors.
* System Protection: The "Refiner" category is now a protected system tag, ensuring your AI tools always have the right instructions.


⚡ Background Isolate Scanning
We've completely re-engineered how the app handles your files.
* Zero UI Stutter: Large image libraries are now scanned in background isolates. Even with thousands of images, the UI remains fluid and responsive at 60FPS.

  ---

💎 UX & UI Enhancements


* Redesigned Models Screen: A clean, tabbed interface separating Model management from Channel configuration.
* Advanced Discovery: Added keyword filtering to the "Fetch Models" dialog to help you navigate hundreds of available models.
* Modernized Prompt Cards: Multi-line previews, character counts, and one-click copy actions.
* Improved Setup Wizard: A refined first-run experience that guides you through the new dynamic provider setup.
* Global Proxy Support: Full support for authenticated HTTP proxies with a quick-toggle switch.

  ---

🛠 Stability & Technical Improvements


* Relational Database: Migrated to a robust relational model (v13) with automated ID mapping for settings imports.
* Architecture Cleanup: Extracted Gallery management into a modular state controller for better maintainability.
* Layout Fixes: Resolved rare hit-test and semantics exceptions in complex desktop layouts.
* Quality Standard: Achieved a "Zero Issue" status in static analysis (flutter analyze).

  ---


📦 Distribution & Multi-Platform Support


We have fully automated our build pipeline. You can now download official installers for:
* Windows: Professional MSIX installer and portable ZIP.
* macOS: Standard DMG installer (Apple Silicon native).
* Linux: Portable TAR.GZ bundle.

  ---


Thank you for using Joycai Image AI Toolkits! This update provides the foundation for a truly open and scalable AI workflow. We can't wait to see what you create.