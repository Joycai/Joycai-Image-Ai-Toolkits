---
name: bump-version
description: >
  Bump the application semantic version (MAJOR.MINOR.PATCH) across all files in the
  Joycai Image AI Toolkits project. Use when the user
  says "bump the version", "release X.Y.Z", "update to version X.Y.Z", or "bump
  major/minor/patch". For bumping only the build suffix (+B) without changing the
  semver, use the update-build-count skill instead.
---

# Bump Version

Bumps the semantic version (`MAJOR.MINOR.PATCH`) across every file that embeds
the version string. Commit and push only when included in the user's request.
The build suffix in `pubspec.yaml`
(`+B`) is always reset to `0` on a version bump.

## Step 0 — Determine the New Version

1. Read `pubspec.yaml` and extract the current version (e.g., `2.3.1+0` → semver `2.3.1`).
2. If the user supplied an explicit version (e.g., "bump to 2.4.0"), use it directly.
3. Otherwise ask whether to bump **major**, **minor**, or **patch**, then compute:
   - **patch**: `2.3.1` → `2.3.2`
   - **minor**: `2.3.1` → `2.4.0`
   - **major**: `2.3.1` → `3.0.0`
4. Proceed when the request determines the new version; ask only if the target is ambiguous.

## Step 1 — Pull & Rebase on `main`

Check the branch and working tree first. Preserve unrelated changes. When preparing
a release branch, bring it up to date before editing; do not rewrite a shared branch:

```bash
git fetch origin
git rebase origin/main
```

If the rebase fails, stop and report the conflict. Do NOT proceed with version edits.
On Windows PowerShell, run each command separately and check `$LASTEXITCODE`.

## Step 2 — Update All Version References

Replace **old semver** with **new semver** in every file below. Change only the
patterns shown — do not touch surrounding text.

### `pubspec.yaml`

| Field | Pattern | New value |
|-------|---------|-----------|
| `version:` | `version: X.Y.Z+B` | `version: NEW.VER.SION+0` |
| `msix_version:` | `msix_version: X.Y.Z.B` | `msix_version: NEW.VER.SION.0` |

### `windows/runner/Runner.rc`

Only update the **fallback `#else` branch**. Locate it by its macros, not line numbers. The
`#if defined(FLUTTER_VERSION_*)` guarded lines use build-time macros — do NOT touch them.

| Pattern | New value |
|---------|-----------|
| `#define VERSION_AS_NUMBER 2,3,1,0` | `#define VERSION_AS_NUMBER MA,MI,PA,0` |
| `#define VERSION_AS_STRING "2.3.1"` | `#define VERSION_AS_STRING "NEW.VER.SION"` |

### `build_script/inno_setup.iss`

| Pattern | New value |
|---------|-----------|
| `#define MyAppVersion "X.Y.Z"` | `#define MyAppVersion "NEW.VER.SION"` |

### `README.md`

| Pattern | New value |
|---------|-----------|
| `version-X.Y.Z-blue.svg` (badge URL) | `version-NEW.VER.SION-blue.svg` |
| `**App Version**: X.Y.Z` | `**App Version**: NEW.VER.SION` |

### `README_CN.md`

| Pattern | New value |
|---------|-----------|
| `version-X.Y.Z-blue.svg` (badge URL) | `version-NEW.VER.SION-blue.svg` |
| `**应用版本**：X.Y.Z` | `**应用版本**：NEW.VER.SION` |

### `AGENTS.md`

| Pattern | New value |
|---------|-----------|
| `**Version:** X.Y.Z ·` | `**Version:** NEW.VER.SION ·` |

## Step 3 — Verify with Flutter

```bash
flutter pub get
```

Confirm dependency resolution succeeds. Follow the verification gates in `AGENTS.md`;
`flutter pub get` alone does not validate Dart code changes.

## Step 4 — Commit the Version Bump

Only when committing is requested:

```bash
git add pubspec.yaml windows/runner/Runner.rc build_script/inno_setup.iss README.md README_CN.md AGENTS.md

git commit -m "chore: bump version to NEW.VER.SION"
```

## Step 5 — Push the Current Branch

Only when pushing is requested:

```bash
git push origin HEAD
```

Report the push result (branch name + commit SHA) to the user.

## Example

Starting from `version: 2.3.1+0`, user says "bump minor":

| File | Before | After |
|------|--------|-------|
| `pubspec.yaml` | `version: 2.3.1+0` / `msix_version: 2.3.1.0` | `version: 2.4.0+0` / `msix_version: 2.4.0.0` |
| `Runner.rc` | `2,3,1,0` / `"2.3.1"` | `2,4,0,0` / `"2.4.0"` |
| `inno_setup.iss` | `"2.3.1"` | `"2.4.0"` |
| `README.md` | `version-2.3.1-blue.svg` / `App Version: 2.3.1` | `version-2.4.0-blue.svg` / `App Version: 2.4.0` |
| `README_CN.md` | `version-2.3.1-blue.svg` / `应用版本：2.3.1` | `version-2.4.0-blue.svg` / `应用版本：2.4.0` |
| `AGENTS.md` | `**Version:** 2.3.1 ·` | `**Version:** 2.4.0 ·` |

Commit message: `chore: bump version to 2.4.0`
