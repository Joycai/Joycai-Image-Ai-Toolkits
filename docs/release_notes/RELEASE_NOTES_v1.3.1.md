# Release Notes - v1.3.1

## Summary
This patch release addresses critical authentication issues in the initial setup wizard and improves application branding on Windows.

## 🛠 Improvements & Bug Fixes
- **Setup Wizard Fixes**: Resolved 401 errors during model discovery by ensuring the Google GenAI endpoint correctly includes the `/v1beta` version prefix.
- **Input Sanitization**: API keys, endpoints, and display names are now automatically trimmed of whitespace to prevent authentication failures caused by accidental spaces.
- **Windows Taskbar Icon**: Optimized the launcher icon configuration to ensure the application icon displays correctly in the Windows taskbar across all scaling modes.
- **Version Alignment**: Updated internal versioning and build scripts to v1.3.1.

## 📝 Documentation
- Minor updates to localization files for English and Chinese.
