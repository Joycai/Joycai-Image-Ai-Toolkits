# Windows Store build boundary

The manually dispatched `Windows Store Preparation` workflow builds an unsigned
x64 MSIX with an explicit preparation identity. It does not publish a GitHub release,
install a certificate, install the application or contact Partner Center. WIN-02
through WIN-06 remain prerequisites for release readiness.

## Local preparation

Use Python 3.12 and Flutter 3.47.8 on Windows with the Visual Studio C++ build tools:

```powershell
python -m unittest discover -s build_script -p test_windows_store.py
python build_script/build_windows_store.py --preparation
```

Local preparation may explicitly add `--allow-sdk-mismatch` when using a different
Flutter SDK. The actual SDK is recorded; this does not qualify as validation of the
pinned CI SDK. Production mode never accepts this override.

Each run creates a unique directory under `build/windows-store/`. Its `source`
directory contains a copy of versioned Windows application/test sources, including
current modifications. Stage newly added application source files in Git first.
Ignored files, old build artifacts and independent worktrees are never copied.
The temporary pubspec replaces only `msix_config`; the working repository's pubspec,
direct-distribution outputs and macOS configuration are not changed.

The script resolves locked dependencies, merges/generates localization, runs the
Store safety tests and compiles a fresh release with the explicit false distribution
define. It checks generated CMake defines before packaging. The installed `msix`
tool's Store mode uses the supplied identity without invoking local certificate
installation/signing; the script also explicitly disables signing.

Only verified packages receive `AppxManifest.xml` and `provenance.json` in `artifacts`.
Provenance records source hashes/revision/status, SDK, build flags, package settings
and SHA-256. Failed runs are retained for diagnosis and must not be published.
The preparation identity and artifact filename explicitly prohibit submission.

## Future Partner Center configuration

WIN-04 currently blocks this production path before any staging/build. Only
`--preparation` is available until the [AI safety acceptance record](../testing/windows-store-ai-safety.md)
is resolved in a reviewed change. Supplying a real identity does not bypass that
gate; the following configuration describes the future candidate path.

After registration and product reservation, supply a local JSON file with exact
`identity_name`, `publisher`, `publisher_display_name`, `display_name` and
`previous_version` values. Use `first` for the previous version only for the first
submission; otherwise use the highest previously submitted package version.

```powershell
python build_script/build_windows_store.py --config C:/path/to/store-identity.json
```

These are metadata, not credentials. The script requires them explicitly and rejects
known preparation/testing placeholders; it cannot verify their ownership or accuracy
against Partner Center. The package version is the pubspec's stable three-component
version plus `.0`, must increase beyond the supplied previous version, and obeys
[Microsoft's version rules](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/app-package-requirements?pivots=store-installer-msix).
Version bumps follow the repository's versioning workflow.

Verification checks identity, version, architecture, all four language declarations,
capabilities, desktop OS floor, entry point, executable, runtime resources and referenced
images. It rejects bundled certificates and locally signed packages. This validates
package structure, not runtime compatibility: WACK, full native dependency resolution,
installation, upgrades, language behavior and declared minimum OS acceptance remain
WIN-06 work. The inherited OS floor is 10.0.17763.0 pending that validation.

## Capability rationale

- `runFullTrust`: Flutter Win32 host and native desktop file/media integrations.
- `internetClient`: user-selected AI services and media downloads.
- `privateNetworkClientServer`: configured LAN AI services; the app's MCP listener
  remains loopback-only. A capability declaration does not open a firewall rule or
  make MCP accessible to the LAN.

The final submission must explain required capabilities in Partner Center and verify
their necessity against the final binary. Full-trust packaging is not AppContainer
isolation. See [Microsoft's capability guidance](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/app-capability-declarations).

The GitHub `flutter-build.yml` workflow and default sideload `msix_config` continue
to create direct-distribution packages; this path never reuses their compiled output.

## Windows native dependencies: JNI exclusion

`path_provider_android` pulls the JNI package into the shared dependency graph;
Windows uses `path_provider_windows` and does not use a JVM. The JNI plugin's optional
Java discovery previously made Windows output depend on whether the build host had
a JDK: it could bundle `dartjni.dll` with an unsatisfied `jvm.dll` import.

The Windows CMake project disables optional JNI discovery before generated plugin
rules run, shadows a previously cached `JNI_FOUND`, and fails if a JNI target is
nevertheless created. Its install step removes only a stale `dartjni.dll` from the
build bundle, covering incremental builds as well as fresh builds. This applies to
both GitHub/direct Windows builds and Store preparation. It changes no Android,
macOS, Mac App Store, dependency version or generated plugin file.

The Store verifier rejects `dartjni.dll` and `jvm.dll` anywhere in an MSIX,
case-insensitively, rather than silently removing files after packaging. A future
intentional Windows Java integration must revisit this policy, its runtime delivery
and licensing together. CMake's
[optional package-discovery switch](https://cmake.org/cmake/help/latest/variable/CMAKE_DISABLE_FIND_PACKAGE_PackageName.html)
is used only in the Windows project; the explicit `JNI_FOUND` override prevents an
earlier configure's cached result from enabling the optional JNI target.

## Packaged storage boundary (WIN-02)

`WindowsPackage` queries the process through
[`GetCurrentPackageFullName`](https://learn.microsoft.com/en-us/windows/win32/api/appmodel/nf-appmodel-getcurrentpackagefullname).
Only `APPMODEL_ERROR_NO_PACKAGE` authorizes portable storage. A package identity,
unexpected result or unavailable API disables it. This covers sideloaded MSIX as
well as Store builds, independent of `JOYCAI_DIRECT_DISTRIBUTION`.

`PortableStorage` owns marker reads and writes. Packaged processes ignore an existing
`.portable` and never create or delete it. `AppPaths` uses application support storage
instead; the existing wizard/settings visibility checks use the same policy. Mac
active-installation resolution and unpackaged Windows portable behavior are unchanged.
Packaged/unknown Windows processes also skip the legacy Documents database rename:
startup must not move another installation's source database.

Source audit: database, debug logs, fonts, durable media and MCP staging derive from
`AppPaths`/`DatabaseService`; scratch media and thumbnails use OS temporary storage.
The ordinary console log is in memory. Windows output folders are user-selected saved
settings. The only executable-relative write found in `lib` was the portable marker.
These findings do not validate OS redirection or user-selected paths at runtime.

Packaged Windows now explicitly selects
`<unredirected LocalAppData>/Packages/<runtime package family>/LocalState/Joycai`.
The host queries `GetCurrentPackageFamilyName` and `SHGetKnownFolderPath` with
`KF_FLAG_NO_PACKAGE_REDIRECTION`; it never guesses the family from build metadata.
No package identity or path-query failure means no fallback to the direct database.
This avoids the legacy Roaming AppData merged view before credential encryption.
Package family identity, not the version, owns data across upgrades. See Microsoft's
[known-folder flags](https://learn.microsoft.com/en-us/windows/win32/api/shlobj_core/ne-shlobj_core-known_folder_flag).

First launch and Settings offer the existing explicit installation importer, with
Windows instructions. The old app must be closed. SQLite `VACUUM INTO` captures
committed WAL data into an isolated installation; owned media is copied and checked,
external output folders remain external, and one active-installation pointer selects
the copy. Existing source/current installations remain intact; MCP is disabled and
AI consent cleared. Windows selects the FFI SQLite factory before any app DB opens.
Native package discovery never automatically imports or encrypts direct-install data.

Installed path checks, directory selection, drag/drop, file operations, backup/restore,
package upgrade and uninstall acceptance remain open. WIN-02 is not complete. The
host used for implementation has no Windows Sandbox executable; it was not modified
to add Sandbox, accounts or certificate trust. The exact remaining procedure and
recorded checks are in [Windows storage/security validation](../testing/windows-store-storage-security.md).
