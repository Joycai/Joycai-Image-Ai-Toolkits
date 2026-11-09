# macOS App Sandbox

Default macOS Debug/Profile and Release builds use App Sandbox. Do not disable
that sandbox to work around an MAS file-access failure; fix authorization instead.

## Direct-download distribution

The two macOS distributions are separate apps and never automatically share data:

| Distribution | Installed app name | Bundle ID |
|---|---|---|
| Store / default signed build | Joycai Image AI Toolkits | `cn.joycai.joycaiImageAiToolkits` |
| Direct download | Joycai Image AI Toolkits Direct | `cn.joycai.joycaiImageAiToolkits.direct` |

The distinct identifiers separate sandbox containers, application support/cache
paths, native preferences and directory-bookmark stores. The distinct app names
allow side-by-side installation in Applications. Runner-only build variables
select the identity without renaming or reidentifying embedded plugin frameworks.
The packaging verifier rejects the Store identity or name in a direct package.
Existing Store and older shared-identity direct data is retained in the original
container. There is no automatic copy, link, shared App Group, or keychain access.
Migration remains an explicit user-selected import; encrypted credentials require
the original signed app and cannot be unlocked by the ad-hoc download. Bootstrap
rejects such credentials before creating AppState and displays recovery guidance.

GitHub Actions `flutter-build.yml` is explicitly a **direct-download** build/release
workflow, not an App Store pipeline. macOS calls:

```sh
bash build_script/build_macos.sh --distribution direct
```

The script cleans only `build/macos`, combines
`--dart-define=JOYCAI_DIRECT_DISTRIBUTION=true` with
`build_script/macos_direct.xcconfig` via `XCODE_XCCONFIG_FILE`, and emits
`Joycai-Image-Ai-Toolkits-Direct-Installer.dmg`. Both distributions enable App
Sandbox. The direct override uses `Runner/Direct.entitlements`, retains network,
user-selected files, Pictures/Downloads, Photos and app-scoped bookmarks, and
uses ad-hoc signing without App Store provisioning. It omits the Store-only
Keychain access group; the existing direct credential policy is unchanged.
Direct builds retain Hardened Runtime but set
`com.apple.security.cs.disable-library-validation`: ad-hoc signatures have no
Team ID, so the default library validation rejects FlutterMacOS at launch even
when `codesign --verify --deep --strict` passes. This exception is direct-only;
Store entitlements retain library validation. App Sandbox remains enabled.
The packaging verifier requires this exception for the current ad-hoc pipeline.
The direct xcconfig also pins `MACOSX_DEPLOYMENT_TARGET=14.0` across generated
Swift packages, matching the documented Runner floor and avoiding generated
package targets falling back to 12.0.
If switching to Developer ID signing, reassess it after signing all embedded
frameworks with the same team. See [Apple library validation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation).

The Dart distribution flag controls non-store product policy, not sandbox file
access. Both macOS distributions use container storage, the installation-import
bootstrap, native directory grants and security-scoped Finder-drop copies.
Existing non-sandbox installations need the explicit old-data import flow;
original data is not deleted. MCP allowlists remain additional restrictions.

Before packaging, `verify_macos_direct.py` requires deep/strict signature
validation, sandbox and bookmark entitlements, and no embedded provisioning
profile. This remains an ad-hoc signed package, not a notarized Developer ID
release. Developer ID signing/notarization remains separate work.

Application settings offers an optional Full Disk Access help dialog and a
System Settings link. Users grant that permission themselves. It only addresses
macOS privacy restrictions: it does not disable App Sandbox, replace directory
selection/bookmarks, or grant root privileges. No automatic permission probing
or launch-time prompt is performed. If opening the settings URL fails, the UI
shows the manual path. Native settings navigation and grant/restart behavior
must be verified on a real Mac; widget tests cannot grant OS permissions.

## Store distribution signing

PR #394 uses Apple Development automatic signing for local Debug/Profile/Release
builds and enables Hardened Runtime. The accepted Xcode recommendations raise the
Runner deployment target to macOS 14.0 with the current SDK. App Store export
re-signs an Archive with Apple Distribution and signs its pkg with Mac Installer
Distribution; these are distinct from the direct-download override above.

The 2026-11-05 local store export passed app/package signature checks and embedded
profile matching; it removed `get-task-allow` while preserving App Sandbox.
Archive requires `MACOSX_DEPLOYMENT_TARGET=14.0` to avoid a generated Swift package
minimum-version conflict. See the [MAS-07 verification record](../testing/mas07-distribution-verification.md)
for commands, export-only settings and remaining server-side validation.
Certificates, private keys, provisioning profiles and exported packages remain local.

## Entitlements

`macos/Runner/DebugProfile.entitlements` is used by Debug and Profile;
`macos/Runner/Release.entitlements` is used by Release.

| Entitlement | Purpose |
|---|---|
| `keychain-access-groups` | MAS-06: app-specific data-protection Keychain wrapping key; requires a matching provisioning profile even for local development. See [credential protection](credential-protection.md). |
| `app-sandbox` | Constrain both development and release builds to the macOS sandbox. |
| `network.client` | AI endpoints, media downloads, fonts and other outgoing connections. |
| `network.server` | Optional loopback MCP listener; also supports Flutter development tooling. Keep MCP loopback-only and authenticated. |
| `files.bookmarks.app-scope` | Persist and resolve app-scoped directory bookmarks on this Mac. |
| `files.user-selected.read-write` | User-selected files/folders through native open/save panels. This is not permission to access every stored path. |
| `assets.pictures.read-write` | Existing Pictures-folder access. This does not grant access to arbitrary external volumes or other folders. |
| `files.downloads.read-write` | Existing Downloads-folder access. |
| `personal-information.photos-library` | Existing Photos integration; the entitlement does not replace system privacy consent. |
| `cs.allow-jit` (Debug/Profile only) | Flutter development runtime. Not included in Release. |

The original sandbox change preserves existing permissions and enables the sandbox; it does not
add broad exceptions or a new distribution signing identity. The bookmark
entitlement accompanies the native directory authorization implementation. App Store signing remains MAS-07.

## File-access contract

An application allowlist is an additional restriction, not an OS authorization.
In particular, MCP reference-folder rules cannot grant sandbox access. Both the
application rule and macOS permission must allow the operation.

System directory APIs should resolve app data and caches in the sandbox container.
A saved absolute path, a directory that appears to exist, or a successful access
in the current session does not prove access will survive a restart. Persistent
external locations require a security-scoped bookmark lifecycle and recovery
when the grant is stale or inaccessible. Internal drag-and-drop cannot grant new
OS permissions; Finder drops must preserve any native authorization they carry.

## Shared directory authorization (MAS-02, phase 1)

`DirectoryAccessService` in `services/files/` is the cross-platform entry point.
macOS uses `joycai/directory_access`, implemented by `Runner/DirectoryAccess.swift`;
other platforms keep the existing file picker. All directory pickers (including
setup, output settings, browser/workbench roots, knowledge-base selection and
reauthorization) use this service. File import/export pickers and Finder drops
are separate follow-up work.

The native picker creates a bookmark from the actual `NSOpenPanel` URL before
returning a canonical path. Grants are stored atomically in
`Application Support/<bundle-id>/directory-grants.plist` **inside the sandbox**.
This is machine-local OS authorization, not business data: it is deliberately
separate from the application database and its JSON backups. A restored database
can contain a path without a grant and must ask the user to select it again.

Startup restores grants before constructing application state or resuming tasks;
state reloads also restore them before scans/watchers. Output writes, knowledge
validation, asynchronous reachability checks and MCP input staging retry restore.
Each native restoration resolves the bookmark without UI or auto-mounting volumes,
starts scoped access and verifies the directory can be listed. Stale bookmarks
are refreshed atomically, preserving read-only scope. There is one retained scope
per saved root for the app session (watchers and background work outlive screens).
Replacement acquires its new scope before releasing the previous one; unsuccessful
restoration and application termination release held scopes.

Returned statuses distinguish `available`, `needsAuthorization`, `unavailable`
and `moved`. Offline, denied, deleted or corrupt bookmarks are retained for retry;
no background prompt or automatic directory recreation is performed by the grant
service. A moved bookmark does not silently rewrite application paths or MCP rules:
the user selects the intended location again. Existing unreachable-folder controls
handle browser/workbench recovery; output/knowledge settings can select again.
A corrupt **whole grant store** is not overwritten; it surfaces a store error and
requires recovery of that local file. Actual filesystem operations still handle
I/O failures after a successful check (a check is never a guarantee of future access).

MCP configuration requests a read-only grant for each ungranted rule's base folder.
The panel must select that same folder; cancellation/mismatch leaves MCP settings
and the listener unchanged. A grant shared with another feature is not downgraded.
Trailing `/*` and `/**` restrictions and canonical/symlink checks remain application
rules. On startup a failed grant shows the existing folder error without disabling
text-only generation; reference staging admits only roots whose OS restore and
application rule both succeed. Saving settings again offers reauthorization.

## Durable media (MAS-02, phase 2)

`PersistentMediaService` owns three directories under `AppPaths.getDataDirectory()`:

- `media/imports/<uuid>/`: imported images, video/audio references and camera inputs.
- `media/tasks/<uuid>/`: independent macOS queued-request snapshots, including prepared
  crop/mask images, video frames, image/video/audio references and prompt-refinement inputs.
- `media/results/`: persistent generation fallback, also used on iOS.

File names are kept inside unique directories. Copies stream through `.partial`
files, flush, then rename before a path can be published. Incomplete input sets
are discarded on failure without modifying originals. Importing a read-only source
creates a writable private copy instead of inheriting its filesystem permissions.
Finder drops pass `extraAppleBookmark` to the native `copyDrop` method; it resolves
and holds the exact scoped URL while a background thread copies the bytes, then
releases access. Promise drops without bookmarks copy from their container-local
source. Reference import errors use the existing localized import-error control.

On macOS, `TaskQueueService.addTask` snapshots inputs before saving/publishing the
task and before Batch preparation. Both `imagePaths` and the authoritative nested
`generation.media` (or legacy video options) are rewritten together; callers' drafts
are not mutated. Rename tasks keep original paths and downloader inputs remain URLs.
MCP already stages checked bytes in persistent `mcp-inputs`, so its durable-acceptance
path remains separate. On startup, old pending non-Batch requests without a remote
operation id are rescued before execution; a missing input fails locally and retains
its old path for explicit recovery. Already submitted remote/Batch jobs keep their
existing recovery identifiers and are not resubmitted by this change.

Result fallback is resolved directly by the executor when needed, independent of
whether the gallery has initialized settings. Image and Batch writes also fall back
if the selected directory fails **after** request submission; a complete result is
published only after a flushed partial file is renamed. A video filesystem failure
switches its existing download retry to durable storage, not a new generation request.
Results remain reachable through the existing result tree and export controls.

The result tree and aggregate scan contain only the configured output directory
and the current app-owned `media/results` directory, deduplicated when equal.
Legacy `result_cache` files are not deleted: the old root is kept as
`legacy_result_cache_directory` for recovery, but is not an extra gallery root. Old configured
output paths that pointed at this cache are redirected for future writes. Phase 3
below copies accessible old results and rewrites their history. Files whose migration
fails remain at risk of OS temporary-storage eviction until recovery. Workspace
selection and unsubmitted video drafts remain session UI state; this change persists their
imported bytes and queued requests, not the draft UI itself.

`TempStorageService` only clears its existing temporary `joycai/` tree, never these
persistent directories. Removing a workspace selection or task row does not delete
owned media. No age-based/orphan collector is introduced: reference-aware retention
can be added separately, but must not erase queued/retry inputs or paid outputs.

## Legacy results and existing installations (MAS-02, phase 3)

`LegacyResultMigration` runs on macOS/iOS before `AppState` construction, watchers,
queue loading and cleanup. It considers both the previous `result_cache_directory`
and `legacy_result_cache_directory`. It restores existing authorization without
prompting; the native bridge recognizes the process's own sandbox temporary directory
as well as its home container. Arbitrary other temporary folders are not authorized.

The migration recursively copies regular files into flat `media/results`, skipping
incomplete `.partial` files and refusing symlinks or overlapping source/destination
roots. Deterministic names distinguish original paths while keeping sibling image/TXT
stems together. Streaming SHA-256 verification detects incomplete/changing copies
and refuses to overwrite a differing destination. Originals are never deleted.

After every copy succeeds, one SQLite transaction rewrites exact paths in all task
history (inputs, results, structured parameters, Batch state), assistant attachments
and image-layer rows, then redirects a cache-backed primary output and retires the
legacy setting. It does not change task states, remote operation identifiers, billing
or prompt prose. Only existing copied files are mapped; missing historical files are
not reconstructed, and their old paths remain. Malformed historical JSON is preserved.
The layer index is refreshed after commit. No schema version change is needed.

On copy/authorization/database failure, startup reports an error in the run console
and continues using retained legacy history/settings. Copies already completed remain
safe in persistent storage and are reused on retry; only the current result and output
roots are scanned by the gallery. No partial migration is marked complete. A
later launch retries; missing/offline/external roots need recovery or explicit directory
authorization through the existing directory picker before restarting. Old Batch jobs
also redirect a retained legacy output root before saving newly received results.
There is no runtime migration button or automatic deletion of legacy originals.

### Unsandboxed Application Support assessment

`AppPaths` plus the installed `path_provider_foundation` implementation use
`~/Library/Application Support/cn.joycai.joycaiImageAiToolkits` outside the sandbox;
the sandbox resolves that support directory inside its container instead. The existing
Documents-to-support database check does not cover this change. JSON backup restores
configuration, prompts and optional usage, but deliberately excludes task history,
assistant sessions and media; it is **not** a full installation migration.

### Explicit installation import (MAS-02, phase 4)

Apple's first-container manifest cannot handle existing containers or explicit conflict
choices. We instead ship one user-selected import flow for both cases; **no container
migration manifest** is installed. On macOS the bootstrap screen runs before any live
`DatabaseService`, AppState, watcher, queue recovery or cleanup. It appears once, and
Settings → Application can schedule it for the next launch. Scheduling never replaces
an open database. Users must confirm that the old app is closed and that continuing
will resume the imported queued tasks. Source selection/cancellation is independent
of the confirmation. Copying disables continuation; failure offers retry or keeping
the current installation. Success requires an explicit Continue before app startup.

`InstallationMigrationService` opens the selected database read-only and uses SQLite
`VACUUM INTO` for a consistent snapshot including committed WAL contents. It validates
integrity and recognizable app tables, rejects future/unknown schema versions, and
runs normal schema upgrades only on the isolated copy. Protect the staging directory
before the snapshot; do not pre-create its output file (Darwin SQLite rejects it).
Use `rawQuery` for `wal_checkpoint(TRUNCATE)` and require a zero busy result: unlike
FFI, Darwin's execute API rejects statements that return rows. It copies the application's
owned `media`, `mcp-inputs`, `fonts` and `usage-journal` trees, verifies SHA-256, excludes
unfinished `.part`/`.partial` files, and rejects links and source/destination overlap.
A final inventory/digest check and SQLite `data_version` check reject source changes.
These checks do not replace the user's obligation to keep the old app closed.

Only exact paths to copied files/directories are rebased in tasks (including Batch
state), assistant attachments, layers, source-directory rows and directory settings.
Prompt text and provider operation IDs are preserved. Missing files and external
folders remain at their old paths; they are not fabricated or recursively imported.
Existing legacy temporary results still use phase 3 and require access to that root.
Copied usage journals preserve their event IDs for normal idempotent replay. The full
SQLite database retains history, conversations, billing, channels and keys, unlike a
JSON configuration backup. Logs, caches, executables and OS bookmark stores are not
installation data and are not copied. Imported MCP token/roots/port are cleared and
MCP is disabled; external directory access must satisfy the current Mac's grants.

Each copy lives under the physical Application Support directory's
`installations/<uuid>`. After validation and closing SQLite, an atomic rename of
`active-installation` activates it. `AppPaths` resolves this macOS-only pointer before
all subsequent data accesses. Normal fresh installs still use the original support
root. The previous database/WAL/media remain untouched, even when populated; no
merge or silent overwrite occurs. A receipt in the new installation records the
source and previous root without credentials. These bootstrap pointer/choice/request
files are deliberately outside the business database: they must be read before it
can be opened. Native OS bookmarks stay in the physical support root.

Ordinary failures remove only the new unactivated copy. A hard kill before activation
may leave an unreferenced directory, but the previous pointer remains authoritative;
a hard kill after activation selects the complete copy next launch. No automatic
backup/orphan deletion or in-app rollback selector is provided. Recovery to the
previous installation can use the recorded previous root while the app is closed;
do not replace a database under a running app or remove the real user's container.
Native selection, populated-container import, restart and forced process interruption
are covered by the [isolated native acceptance record](../testing/mas02-native-acceptance.md).
This uses an ad-hoc signed test identity, not App Store distribution signing. Live WAL
under read-only native grants remains a separate acceptance item.

SQLite snapshot semantics: [VACUUM INTO](https://www.sqlite.org/lang_vacuum.html).

Reference: [Apple container migration](https://developer.apple.com/documentation/security/migrating-your-app-s-files-to-its-app-sandbox-container).

## Adaptation queue

These are source-inspection findings, not claims that each operation has failed
in a running signed app. Track implementation and native validation in MAS-02
and the [release ledger](../plans/README.md).

| Feature / code | Current boundary and required follow-up |
|---|---|
| Source/output folders — `GalleryState`, `FileBrowserState`, `FilePermissionService` | Shared picker and bookmark restoration implemented before scans/watchers and output writes. Isolated native picker/read/write/cancel/restart, moved/deleted-root reauthorization and disk-image unmount/remount accepted. Physical removable-device hot unplug remains pending. |
| Knowledge-base root — `KnowledgeBaseService` | Shared directory picker, restore on root lookup and permission-aware validation implemented. Existing knowledge write confirmation remains independent of OS access. |
| Finder image/video drops — workbench gallery and video reference/frame slots | External drops and reference pickers now import bytes into private persistent storage. Native copy holds/releases the resolved bookmark URL; queued macOS tasks receive independent snapshots. Ordinary local Finder image drop accepted in the isolated sandbox: private copy survives source rename and process restart, with matching SHA-256. The transient workspace list is not persisted. File promises, cloud placeholders and video slots remain pending. |
| File rename/move/copy/trash | Existing services operate on paths. Source and destination permissions must both hold; renaming a parent can invalidate saved locations. `NSWorkspace.recycle` is already used for trash; validate it under real grants. Never turn a permission failure into permanent deletion. |
| MCP reference folders — `McpServerState`, `ReferenceFolderRule` | Text-entered rules now require system folder selection for ungranted roots. Read-only bookmarks and restore checks are wired in, preserving canonical/symlink/wildcard restrictions. The listener itself retains both network entitlements and binds only `127.0.0.1`. |
| Portable mode — `AppPaths`, settings Application section and setup wizard | Windows only. macOS, Linux and mobile hide the switch, ignore existing `.portable` markers and never create/delete them. They always use the system Application Support directory. Existing portable data is left untouched; authorized migration remains a separate task. |
| Existing user database — `DatabaseService._initDatabase` | The legacy migration checks the Documents path returned by the current process, not an explicit migration from the previous unsandboxed Application Support location. The startup import above now handles an explicitly selected old Application Support/portable data folder before this initialization runs. Both new and already-created containers use that flow; live production migration remains untested. |
| Result fallback — `GalleryState.reloadSettings`, `TaskQueueService._getEffectiveOutputDir` | New fallback uses persistent `media/results`, visible through existing result/export controls. Image/Batch late write failure and video download retry also use it. Accessible old temporary results and associated history now migrate at startup; failures retain the originals for retry. |
| Backup/import/export | Native open/save panels provide a basis for one-shot access; restored paths do not carry grants. Verify backup selection/save and request fresh grants for restored external locations. |
| Open folder/logs and database permissions | `FileUtils` / `LLMDebugLogger` call `Process.run('open', ...)`; database hardening calls `chmod`. Test child-process behavior and error reporting under the signed sandbox; prefer native APIs if these fail. No shell execution exemption was added. |
| Fonts, logs, DB and caches | Normally use `AppPaths` / system directory APIs and should remain inside the container when portable mode is off. Verify actual resolved paths and first-launch directory creation. |
| Photos, notifications, sharing, video thumbnails/playback, Dock badge | Existing native APIs/plugins remain in place. Validate consent denial, authorized media access and plugin behavior in a sandboxed app; compilation alone does not prove runtime compatibility. |

## Validation boundaries

Format, static analysis and Flutter tests do not run inside the packaged macOS
application sandbox. A successful build plus inspection of embedded entitlements
proves packaging configuration, not successful runtime file access.

Phase 1 verification (2026-11-04): format 896 files unchanged, analyzer clean,
3446 non-screenshot tests passed / 9 skipped, Debug and Release builds succeeded.
The final Release embeds `app-sandbox` and `files.bookmarks.app-scope`; deep/strict
signature verification passed. Dart channel tests exercise failure/retry/cancel
and MCP settings preservation, not Apple's native bookmark implementation.
No production app or user database was opened for runtime acceptance.

Phase 2 checks: format 901 files unchanged, analyzer clean, 3456 non-screenshot
tests passed / 9 skipped. Persistence tests delete original files, recreate a queue
against a real test database, reject missing inputs, preserve remote operation ids,
and simulate late output-directory loss. The H3 Chinese screenshot harness passed
16 cases; all four widths in light/dark were visually inspected. A fresh Release
products directory produced an 80.8 MB app passing deep/strict signature verification
(an earlier incremental App.framework seal mismatch was resolved by rebuilding,
not manual re-signing). These tests do
not substitute for real Finder/bookmark and signed-process restart acceptance.

Phase 3 checks (2026-11-04): format 903 files unchanged, analyzer clean,
3463 non-screenshot tests passed / 9 skipped. Seven new migration tests cover full
history/attachment/layer rewriting, literal prompt preservation, sidecar names,
completed-copy reuse, destination conflicts, transaction rollback/retry, missing
roots, symlinks, nested duplicate names, partial exclusion and overlapping roots.
A fresh Release products directory built the 80.8 MB app and passed deep/strict
signature validation. The incremental App.framework seal mismatch recurred; preserving
that generated directory and rebuilding resolved it without manual re-signing.
No UI layout changed, so no new screenshot run was needed. Native Finder, first
container creation and actual cross-process restart remain untested.

Phase 4 checks (2026-11-04): format 909 files unchanged, analyzer clean,
3475 non-screenshot tests passed / 9 skipped. Nine new service tests cover a real
WAL snapshot, populated destination retention, source immutability, copy-only schema
upgrades, activation/read-back, future/unrelated schema rejection, overlap/link
rejection, failed-copy retry, changed database/media rejection and missing references.
Three state tests cover confirmation, picker cancellation and retry. The 56-shot
harness covers four locales and four widths/light-dark, migration states, the storage
wizard and the settings entry. Representative images at every width/brightness were
opened; no overflow was reported. A transparent bootstrap Scaffold found in rendered
review was fixed with the theme's explicit canvas colour. Fresh Release products
built an 80.9 MB app with deep/strict signature validation; the known incremental
App.framework seal issue again required preserving old products and rebuilding.
No production database, application launch, credentials or paid requests were used.

Native acceptance must use a signed app and a controlled test profile with no
production keys or pending paid tasks. Verify first launch, file panel grants,
Finder drops, process restart, denied/stale grants, task recovery, backup restore,
MCP connection and reference input, result export and system integrations. Keep
the production database intact. Store distribution signing and upload validation
are a separate gate; ad-hoc signing is not evidence of App Store readiness.

References: [Apple App Sandbox](https://developer.apple.com/documentation/security/app-sandbox),
[sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox?language=objc),
[Mac App Store review requirements](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility).
