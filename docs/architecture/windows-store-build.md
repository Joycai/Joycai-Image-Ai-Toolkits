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

Still pending: inspect the actual application-support path and existing direct-install
data visibility under installed MSIX on supported Windows versions. Determine whether
an explicit source-preserving import or separate storage namespace is needed before
enabling migration. No automatic Windows import was added. Native directory selection,
file operations, backup/restore, package upgrade and uninstall acceptance remain open;
WIN-02 is not complete. Keep user output outside package-owned storage during these
tests and verify uninstall does not remove it.
