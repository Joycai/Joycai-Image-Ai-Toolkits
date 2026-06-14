---
name: update-build-count
description: Automatically increment the build number in pubspec.yaml and synchronize it across relevant project files (Android, iOS, Windows, MSIX). Use when the user wants to "bump the build count", "update the version suffix", or "increment the build number" for a new internal or test release.
---

# Update Build Count

This skill provides a streamlined workflow to increment the build number (the `+B` part of `X.Y.Z+B`) across the Joycai Image AI Toolkits project.

## Workflow

1.  **Read Current Version**:
    - Analyze `pubspec.yaml` to extract the current `version` (e.g., `2.1.0+1`).
2.  **Increment Build Number**:
    - Identify the current build number (the part after `+`).
    - Increment it by 1 (e.g., `1` -> `2`).
    - Construct the new version string (e.g., `2.1.0+2`).
3.  **Update Configuration Files**:
    - **`pubspec.yaml`**:
        - Update `version: X.Y.Z+B`.
        - Update `msix_config` -> `msix_version: X.Y.Z.B` (replace the last `0` or previous build number with the new one).
    - **`windows/runner/Runner.rc`**:
        - Locate `#define VERSION_AS_NUMBER`. If it's hardcoded (not using `FLUTTER_VERSION_*`), update it to `X,Y,Z,B`.
    - **Documentation**:
        - Check `README.md` and `README_CN.md` for any specific version+build mentions and update them if they exist.
4.  **Verification**:
    - Run `flutter pub get` to ensure the `pubspec.lock` is synchronized.
    - Confirm the changes with the user.

## Example

If `pubspec.yaml` has `version: 2.1.0+1`:
- New version: `2.1.0+2`
- `msix_version`: `2.1.0.2`
- `Runner.rc` (if hardcoded): `2,1,0,2`
