---
name: bump-version
description: >
  Bump the application version (MAJOR.MINOR.PATCH) across all files in the project,
  push the current branch to origin, then merge main into the current branch.
  Use when the user says "bump the version", "release X.Y.Z", "update to version X.Y.Z",
  or "bump major/minor/patch".
---

# Bump Version Skill

This skill bumps the semantic version (`MAJOR.MINOR.PATCH`) across every file that
embeds the version string, then pushes the current branch and rebases on top of `main`.

The build suffix in `pubspec.yaml` (`+B`) is always reset to `0` on a version bump.

---

## Step 0 — Determine the New Version

1. Read `pubspec.yaml` and extract the **current** version (e.g., `2.2.1+0` → semver `2.2.1`).
2. If the user supplied an **explicit** new version (e.g., "bump to 2.3.0"), use it directly.
3. Otherwise ask whether to bump **major**, **minor**, or **patch**, then compute:
   - **patch**: `2.2.1` → `2.2.2`
   - **minor**: `2.2.1` → `2.3.0`
   - **major**: `2.2.1` → `3.0.0`
4. Confirm the new version with the user before making any changes.

---

## Step 1 — Pull & Rebase on `main`

Bring the current feature branch up to date before editing anything:

```powershell
git fetch origin
git rebase origin/main
```

If the rebase fails, stop and report the conflict to the user. Do NOT proceed with file edits.

---

## Step 2 — Update All Version References

Replace **old semver** with **new semver** in every file listed below.
Use the exact patterns shown — do not change surrounding text.

### `pubspec.yaml`
| Field | Old pattern | New value |
|---|---|---|
| `version:` | `version: X.Y.Z+B` | `version: NEW.VER.SION+0` |
| `msix_version:` | `msix_version: X.Y.Z.B` | `msix_version: NEW.VER.SION.0` |

### `windows/runner/Runner.rc`
| Pattern | New value |
|---|---|
| `#define VERSION_AS_NUMBER 2,1,1,0` (hardcoded fallback line) | `#define VERSION_AS_NUMBER MA,MI,PA,0` |
| `#define VERSION_AS_STRING "2.1.1"` (hardcoded fallback line) | `#define VERSION_AS_STRING "NEW.VER.SION"` |

> Note: The `#if defined(FLUTTER_VERSION_*)` guarded lines use build-time macros and must NOT be touched.
> Only update the **fallback** `#else` branch lines.

### `build_script/inno_setup.iss`
| Pattern | New value |
|---|---|
| `#define MyAppVersion "X.Y.Z"` | `#define MyAppVersion "NEW.VER.SION"` |

### `README.md`
| Pattern | New value |
|---|---|
| `version-X.Y.Z-blue.svg` (badge URL) | `version-NEW.VER.SION-blue.svg` |
| `**App Version**: X.Y.Z` | `**App Version**: NEW.VER.SION` |

### `README_CN.md`
| Pattern | New value |
|---|---|
| `version-X.Y.Z-blue.svg` (badge URL) | `version-NEW.VER.SION-blue.svg` |
| `**应用版本**：X.Y.Z` | `**应用版本**：NEW.VER.SION` |

### `GEMINI.md`
| Pattern | New value |
|---|---|
| `**Current Version:** X.Y.Z` | `**Current Version:** NEW.VER.SION` |

### `CLAUDE.md`
| Pattern | New value |
|---|---|
| `**Current Version:** X.Y.Z` | `**Current Version:** NEW.VER.SION` |

---

## Step 3 — Verify with Flutter

Run the following to ensure pubspec changes are valid:

```powershell
flutter pub get
```

Confirm output is `Got dependencies!` with no errors.

---

## Step 4 — Commit the Version Bump

Stage all changed files and commit with a standardised message:

```powershell
git add pubspec.yaml `
        windows/runner/Runner.rc `
        build_script/inno_setup.iss `
        README.md README_CN.md `
        GEMINI.md CLAUDE.md

git commit -m "chore: bump version to NEW.VER.SION"
```

---

## Step 5 — Push the Current Branch

```powershell
git push origin HEAD
```

Report the push result (branch name + commit SHA) to the user.

---

## Example

Starting from `version: 2.2.1+0`, user says "bump patch":

| File | Before | After |
|---|---|---|
| `pubspec.yaml` | `version: 2.2.1+0` / `msix_version: 2.2.1.0` | `version: 2.2.2+0` / `msix_version: 2.2.2.0` |
| `Runner.rc` | `2,1,1,0` / `"2.1.1"` | `2,2,2,0` / `"2.2.2"` |
| `inno_setup.iss` | `"2.2.1"` | `"2.2.2"` |
| `README.md` | `version-2.2.1-blue.svg` / `App Version: 2.2.1` | `version-2.2.2-blue.svg` / `App Version: 2.2.2` |
| `README_CN.md` | `version-2.2.1-blue.svg` / `应用版本：2.2.1` | `version-2.2.2-blue.svg` / `应用版本：2.2.2` |
| `GEMINI.md` | `Current Version: 2.2.1` | `Current Version: 2.2.2` |
| `CLAUDE.md` | `Current Version: 2.2.1` | `Current Version: 2.2.2` |

Commit message: `chore: bump version to 2.2.2`
