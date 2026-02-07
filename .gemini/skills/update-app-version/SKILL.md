---
name: update-app-version
description: Scans the project and updates the application version across all relevant files including pubspec.yaml, build scripts, and native configuration files. Use when the user requests to update, increment, or set the application version (e.g., "update version to 1.3.0").
---

# Update App Version

This skill automates the process of updating the version number throughout the codebase. It targets common Flutter/Desktop project files to ensure consistency.

## Workflow

1.  **Identify Target Version**: Determine the version string the user wants to set (e.g., "1.3.0").
2.  **Run Update Script**: Execute the bundled script to perform the updates across multiple files.
3.  **Verify Changes**: Briefly check the modified files to ensure the replacement was successful and formatted correctly.
4.  **Inform User**: Report the success of the operation.

## Files Updated

- `pubspec.yaml`: Updates both `version` and `msix_version`.
- `windows/runner/Runner.rc`: Updates `VERSION_AS_STRING`.
- `build_script/inno_setup.iss`: Updates `MyAppVersion`.
- `test/widget_test.dart`: Updates the hardcoded version in widget tests.

## Usage

When a user asks to update the version:

1. Validate the version format.
2. Run the following command:
   ```bash
   node .gemini/skills/update-app-version/scripts/update_version.cjs <target-version>
   ```
3. Report the result to the user.