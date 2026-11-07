# Windows Store release validation (WIN-06)

Date: 2026-11-08. **Preparation validation only; release acceptance incomplete.**
The maintainer confirmed no isolated Windows test environment is available and
explicitly deferred those checks. This is a temporary deferral, not a pass or a
waiver of release criteria. WIN-04 still blocks production packaging; WIN-05 still
needs final publisher, rights, listing and reviewer-access acceptance.

## Environment and evidence boundaries

Development host reports Windows build 26300.9711, display version 26H2, x64.
This is not evidence for the manifest floor 10.0.17763.0 or a clean supported OS.
WACK is installed at `C:/Program Files (x86)/Windows Kits/10/App Certification Kit/`,
version 10.0.26100.7705. `WindowsSandbox.exe` is absent; Get-VM, vmrun and
VBoxManage are not on PATH. No separate VM/session was supplied.

Local Flutter is 3.47.9, using the explicit preparation-only SDK override;
CI remains pinned to 3.47.8. No certificates, trusted roots, Windows features,
user accounts, installed packages or external outputs were changed. No real
credentials, paid providers, Store upload or remote workflow dispatch was used.

The existing native C++ helper was rebuilt with MSVC and Windows SDK 10.0.26100.0.
DPAPI round trip, randomized encryption, tampering and empty-input rejection passed.
Its package path result is unpackaged/unavailable, as expected for this helper;
it does not test the installed Flutter channel. Python packaging checks: **6 passed**.
No application source changed in this batch. The previous full Flutter gates remain
historical WIN-04 evidence, not a newly executed WIN-06 suite.

## Fresh preparation package and static audit

Artifact: `build/windows-store/preparation-em0rhg6u/artifacts/joycai-store-preparation.msix`.
Version 4.31.8.0, unsigned test identity, **NOT FOR SUBMISSION**. SHA-256:
`04a9bb512e592df511bea5c897e6670d22305c64d726e2cc8690512e48b05710`.

Built from `0c91703ac5e1514fc113f07680cc76cb55ab47a6`; provenance records the
then-uncommitted skill removals, which are outside the source-staging set. All staged
application/source hashes still matched the working tree after the build. The user
subsequently requested committing those 22 skill removals separately (`8d00f387`).
No application code was changed by that commit.

Fresh isolated Windows Release compilation succeeded; the builder's **8 Store-mode
safety tests passed**. Manifest, four languages, full-trust entry point, capabilities,
minimum OS, runtime files, image references, unsigned status and explicit false direct
define passed the existing verifier. Log: `build/win06-package.log`. Artifact directory
also contains the exact manifest and build provenance. No pinned-SDK CI run is claimed.

Static inspection extracted every EXE/DLL from this exact MSIX, checked each PE header
with MSVC dumpbin and enumerated imports. **24 PE files are x64**. SQLite native-asset
mapping resolves to bundled `sqlite3.dll`; Flutter, plugin and VC runtime DLLs are
present. Files shared with the Release directory matched byte-for-byte. The retained
[dependency inventory](windows-store-native-dependencies.json) includes per-file
hashes/imports and the package hash. It is evidence for this artifact only.

**Open dependency finding:** `dartjni.dll` imports `jvm.dll`, which is not bundled
or present in this host's System32. The dependency graph introduces JNI through
`path_provider_android`; no inspected PE statically imports `dartjni.dll`. JNI's
CMake conditionally builds the library when it discovers a host JVM. This suggests
an unused Android-transitive library, but does not prove runtime safety or identical
payloads on clean CI. Before release, verify it is unused on Windows and exclude it
through an appropriately scoped packaging/build change, or establish and document
the actual supported dependency. Do not install Java or copy an arbitrary JVM just
to silence this audit. No dependency change was made in this validation batch.

Other imports are bundled, Windows API-set contracts, or DLLs found in the development
host's System32. Host presence does **not** prove clean-OS availability, minimum-OS
export support, dynamic LoadLibrary behavior or codec availability. Therefore native
dependency acceptance remains open even though the package verifier passed.

## Installed acceptance matrix

All rows below are **deferred, not run**, at the maintainer's request. Record actual
pass/fail and evidence after an isolated environment and accepted candidate exist.

| Check | Required evidence |
| --- | --- |
| Clean install and first launch | Standard user, OS version, package identity/hash, launch result, no dependency on installed Visual Studio or developer runtimes |
| Package storage and import | Actual LocalState/Joycai path, portable-mode denial, direct database unchanged, source/output hashes before/after explicit import |
| Credentials and restart | Live native channel, protected database values, usable synthetic credentials after restart/rotation, wrong-user failure and confirmed recovery snapshot |
| AI lifecycle | Accepted endpoint/model, agreed budget or synthetic loopback fixture; generation, poll, cancel, retry and resume; consent/revocation and no unexpected sends |
| Media and files | Video playback/thumbnails, downloads, picker, drag/drop, rename/trash, backup/restore, denied permissions and offline failures |
| Desktop integrations | Notifications, clipboard/share, mail handler and fallback, privacy link, optional authenticated loopback MCP; no external exposure |
| Shell identity | Start menu, taskbar/icon, display name, launch and Explorer restart behavior |
| Upgrade and coexistence | Previous same-family signed package, increasing version, preserved data/decryption; independent direct install remains functional |
| Uninstall | Only disposable package removed, external output/direct data hashes unchanged; actual package-local cleanup recorded |
| OS/dependency range | Repeat on declared minimum and current supported Windows releases, without development tools; verify codecs and dynamic native loading |
| WACK | Complete XML/HTML reports, tool version, exact tested package SHA-256, all failures/warnings investigated |

Detailed synthetic storage/credential procedures are in
[WIN-02/WIN-03 validation](windows-store-storage-security.md). Use the
[WIN-04 matrix](windows-store-ai-safety.md) and
[WIN-05 reviewer instructions](windows-store-submission.md) for safety and listing
acceptance. Local mocks and static imports do not substitute for these checks.

## Resume WACK in the isolated environment

Use a copy of the exact unsigned artifact. For preparation installation only, sign a
separate copy with a disposable test certificate trusted only within the test VM.
Retain both unsigned and signed SHA-256 values plus signing provenance; never silently
replace the original artifact or treat a test identity as a production submission.
Run WACK inside the VM's active interactive session, with its required privileges;
run ordinary application acceptance under a standard account.

```powershell
# In the disposable VM, after installing the exact test package:
$wack = 'C:/Program Files (x86)/Windows Kits/10/App Certification Kit/appcert.exe'
$packages = @(Get-AppxPackage -Name 'Joycai.StorePreparation')
if ($packages.Count -ne 1) { throw 'Expected exactly one preparation package' }
$report = Join-Path $env:TEMP 'joycai-wack.xml'
if (Test-Path -LiteralPath $report) { throw 'Choose a fresh report path' }
& $wack reset
if ($LASTEXITCODE -ne 0) { throw 'WACK reset failed' }
& $wack test -packagefullname $packages[0].PackageFullName -reportoutputpath $report
if ($LASTEXITCODE -ne 0) { throw 'WACK reported a failure; retain and review reports' }
```

Review generated XML/HTML even when exit status succeeds; record skipped tests and
warnings, not just a summary exit code. Repeat against the final production identity
and candidate after prior WIN items close. The above preparation command does not
validate a production package.

Microsoft documents the installed-package CLI and active-session requirement in
[Windows App Certification Kit](https://learn.microsoft.com/en-us/windows/uwp/debug-test-perf/windows-app-certification-kit)
(checked 2026-11-08). No WACK run/report is claimed here.
