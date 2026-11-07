# Windows Store storage and credentials: validation record

Implementation uses the existing Windows x64 full-trust MSIX path. This note separates
host/unit evidence from installed-package acceptance. No Partner Center registration,
real credentials, paid service calls or publication are needed for the automated checks.

## Implemented and exercised

- Runtime identity and portable marker tests cover packaged, unpackaged and unknown
  identity, stale markers, mutation prevention and restart discovery.
- Package storage tests verify native-path selection/creation and no fallback on
  missing, relative or failed paths. The native helper returns no package path in
  the unpackaged test process; package-local resolution still needs installed checks.
- Installation import tests use synthetic SQLite/media on Windows: WAL snapshots,
  retained source/previous destinations, path rewriting, failure/retry, changed source,
  newer/invalid databases and traversal rejection. They do not simulate MSIX virtualization.
- Native MSVC x64 tests compile the production DPAPI implementation and exercise
  randomized encryption, round trip, tampering and invalid input. Flutter database
  integration sends synthetic bytes over stdin/stdout to that native helper, including
  a new process on each operation. It covers migration, fresh protector/restart,
  credential rotation, failed writes, backup redaction and foreign-envelope rejection.
  This verifies the native primitive and Dart persistence boundary, not Flutter's
  live Windows channel or cross-user behavior.
- Recovery tests verify a readable pre-reset SQLite snapshot, preservation of
  non-secret rows, MCP disabled and unchanged source credentials on snapshot failure.
  UI tests require explicit consent and serialize retry/reset.
- Schema 53 -> 54 upgrade retains rows; explicit downgrade refusal retains the version
  and rows. Older readers without a downgrade handler are not safe rollback targets. The existing
  Mac protection tests continue to exercise migration, rollback and redacted restore.
- Windows import and recovery are rendered at 390/834/1024/1440, light/dark, all four
  locales. Reviewed both screens at each size/theme, including long Japanese copy.
  Existing Mac recovery renders retained for comparison in `build/win03-baseline`.

## Reproduce native checks

Historical WIN-03 preparation artifact: `build/windows-store/preparation-rll14jpq/artifacts/`
(`4.31.8.0`, unsigned, NOT FOR SUBMISSION). SHA-256:
`255fde3b41b1ef1d1ffdd6a2927888a1e284e4100d19be74ce2cd6a8fea71e9e`.
The newer WIN-06 artifact and dependency findings are recorded in
[release validation](windows-store-release-validation.md).
The manifest/resource verifier passed after a fresh isolated Windows Release compile;
`provenance.json` records the staged working-source hashes (before the final commit).
Local Flutter is 3.47.9 with the explicit preparation override; CI remains pinned to
3.47.8 and has not been run remotely. Mac recovery's 32 baseline PNG hashes are unchanged.
Logs: `build/win03-package-final.log`, `build/win03-analyze-final.log`,
`build/win03-shots-final.log`; the 96 final screenshot cases passed. Python package
guards (4 tests) and both workflow YAML parses passed. No package was installed or submitted.

Final gates: format 939 files (zero changes on the final formatted tree), analyze
`No issues found!`, and `flutter test -x screenshots --concurrency=2`: **3546 passed,
5 skipped**, with the native DPAPI integration enabled (`build/win03-regression-final.log`).
Earlier runs found and fixed the new test's missing scroll and the unsafe assumption
that sqflite rejects downgrades by default. A subsequent default-concurrency run hit
the pre-existing setup-wizard directory-watcher access-denied failure; the final full
lower-concurrency run passed. A screenshot attempt concurrent with the test process
hit a locked `sqlite3.dll`; running the screenshot suite separately passed all 96 cases.
Direct-distribution targeted verification passed 25 tests, including portable storage,
runtime identity, both credential boundaries, native DPAPI and Store/direct safety
behavior (`build/win03-direct-tests.log`).

Run with Visual Studio C++ tools, Windows SDK, CMake and the pinned Flutter SDK:

```powershell
cmake -S windows/tests -B build/windows-store-native -A x64
# Check exit status before continuing each command.
cmake --build build/windows-store-native --config Release
& build/windows-store-native/Release/windows_store_native_tests.exe
$env:JOYCAI_WINDOWS_NATIVE_TEST_EXE = (Resolve-Path build/windows-store-native/Release/windows_store_native_tests.exe).Path
flutter test -x screenshots
flutter test test/screenshots/windows_store_shots_test.dart test/screenshots/credential_recovery_shots_test.dart --update-goldens
```

The dedicated Windows Store workflow builds this helper and enables the native
integration test. On other hosts that test is explicitly skipped; a skipped test
is not DPAPI acceptance. The GitHub release workflow is unchanged.

## Installed acceptance still required

This host has no `C:\Windows\System32\WindowsSandbox.exe`. No isolated standard-user
VM/session was supplied. No current-profile package, certificate trust, account or
system feature was installed/changed to substitute for that environment. Therefore
WIN-02 and WIN-03 remain open for the following native acceptance:

1. Use a disposable VM/standard account with synthetic direct-install data and a
   copy of the **exact** preparation package. Locally sign a separate copy with a
   disposable test certificate trusted only inside that VM; never modify or ship
   the unsigned Store candidate or add that certificate to production trust.
2. Launch installed MSIX; record package family, actual data path and artifact hash.
   Confirm `LocalState/Joycai`, no portable toggle/marker writes, and no automatic
   access/modification to the direct database. Explicitly import synthetic data,
   verify original hashes and retained previous installation, then restart.
3. Exercise system folder picker, drag/drop, loopback-only synthetic download,
   rename/trash, backup/restore and denied access. Keep output under a user-owned
   folder outside `Packages` and record its file hashes. No live AI request is needed.
4. Save synthetic channel/proxy/MCP values. Inspect raw DB for Windows envelopes;
   restart and verify usable values through the app. Rotate; verify new ciphertext.
   Corrupt a disposable copy and confirm recovery blocks tasks/MCP. Retry, then
   explicitly reset; verify the pre-reset snapshot, retained history/media and
   credential re-entry. Run under a different test user/profile to verify failure
   without exposing or logging the secret. A mocked denial is not a wrong-user test.
5. Upgrade an older locally signed package with the same family identity and a
   strictly higher valid version. Verify data, active-installation pointer and DPAPI
   decryption survive. Confirm direct/Store coexistence with independently selected
   data and outputs. Uninstall only the disposable package; verify external output
   hashes and direct-install data survive, and record package-local data removal.
6. Repeat on the advertised Windows floor and a current Windows release. Include
   final WACK results in WIN-06. Re-test after any candidate change.

Do not mark these checks passed from source inspection, unpackaged native tests,
UI screenshots or the presence of a valid MSIX manifest.
