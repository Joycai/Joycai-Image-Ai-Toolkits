# Microsoft Store release preparation

Created: 2026-11-07. Status: WIN-01 preparation implemented and locally verified;
production identity and pinned-SDK CI verification pending. WIN-02 portable storage
boundary and explicit import implemented; installed acceptance pending. WIN-03 DPAPI,
migration and recovery implemented; packaged/cross-user acceptance pending. WIN-04
route audit and release guard implemented; safety/installed acceptance remains open.
WIN-05 and WIN-06 planned.

Prepare Joycai's Flutter Windows desktop application for Microsoft Store distribution
as an x64 MSIX. Keep the GitHub distribution and ongoing Mac App Store work working.
Completion means a reproducible Store candidate with recorded package acceptance
results and submission materials ready for review; publication is a separate action.

## Scope and release decisions

Use the existing full-trust desktop application. An AppContainer conversion is not
part of this plan. MSIX packaging and Store signing are the intended distribution
path; the Inno Setup and ZIP downloads remain direct-distribution artifacts.

Before production packaging, the publisher must supply or confirm the Partner Center
product identity, publisher identity, account type, and reserved product name. Before
submission, confirm target markets, pricing, external AI-service charges, supported
Windows versions, and a reviewer-access budget. Do not invent these values. Local
implementation and testing can proceed with an explicitly separate test identity.

The existing MSIX inspected during planning was version 4.31.7.0 and used a testing
publisher. It is not evidence about a future release candidate. Windows plaintext
credential storage is a security gap to remediate; DPAPI is a proposed implementation,
not a Microsoft requirement to use a specific encryption API.

## Ordered work

### WIN-01 Dedicated Store build and package identity

Dependencies: production identity confirmation for the final artifact.

Implementation: the isolated builder, preparation workflow and package guards are
implemented. The publisher has not enrolled in Partner Center, so production identity
and submission validation remain deferred. See the [build boundary](../architecture/windows-store-build.md)
and [ledger](README.md) for commands, validation evidence and remaining limits.

- Add a dedicated Windows Store packaging script/workflow using the repository's
  pinned Flutter version. Compile fresh with `JOYCAI_DIRECT_DISTRIBUTION=false`;
  never repackage the existing direct-distribution executable.
- Keep Store packaging settings separate from the default sideload settings in
  `pubspec.yaml`. Check the installed `msix` tool's supported configuration options
  before selecting overrides or a temporary generated configuration.
- Set Store mode, Partner Center identity/publisher/display name, x64 architecture,
  and a valid increasing Store version. Validate the Store rules for the fourth
  version component rather than copying a direct build number blindly.
- Declare the actual four supported languages using Windows resource language tags.
  Verify icons, display names, minimum OS version, bundled native dependencies and
  `runFullTrust`. Keep only needed capabilities and prepare their explanations.
- Inspect the generated `AppxManifest.xml`; fail the workflow for a testing publisher,
  unexpected identity/version, missing resources, or a direct-distribution build.
  Record the source revision, SDK version, build options and artifact hash.
- Store signing and local test signing are separate paths. Do not ship the testing
  certificate or ask Store users to trust it. Keep secrets out of repository files.

Acceptance: a fresh candidate and extracted manifest match the expected configuration;
Store-mode safety tests pass; GitHub direct artifacts still use their own settings.

### WIN-02 Packaged storage and portable mode

Dependencies: WIN-01 test packaging path.

Implemented: runtime package identity, conservative portable-mode enforcement shared
by paths and marker operations, and suppression of the destructive legacy Documents
database move for packaged Windows. Existing settings/wizard gates consume the policy.
See the [storage boundary](../architecture/windows-store-build.md#packaged-storage-boundary-win-02)
for the source audit and installed-package checks still owed.
Follow-up now uses explicit package-local storage and a source-preserving Windows
import. Native acceptance remains open; see the [validation record](../testing/windows-store-storage-security.md).

- Detect Windows package identity at runtime through a small host adapter so all
  packaged installs, including sideloaded MSIX, disable portable mode. A Dart Store
  build flag alone does not identify every packaged installation.
- Enforce the restriction in `AppPaths` and the write operation, as well as hiding
  the settings control. Preserve portable behavior for unpackaged Windows builds.
- Audit database, logs, caches, temporary files and default output paths for writes
  into the package directory. Use writable per-user storage and user-chosen outputs.
- Check whether MSIX virtualization changes discovery of an existing unpackaged
  installation. If migration is needed, offer an explicit import that preserves the
  source and never silently overwrites either installation's database.
- Test directory selection, drag/drop, download, rename/trash, backup/restore,
  restart, package upgrade and uninstall with synthetic data in an isolated profile.

Acceptance: no package-directory writes; packaged portable mode cannot be enabled;
unpackaged portable mode still works; upgrades preserve application data and uninstall
does not remove user-owned output folders.

### WIN-03 Windows credential protection

Dependencies: WIN-02 storage behavior; can be developed beside WIN-01.

Implemented: user-scoped native DPAPI, distinct versioned envelope, schema 54 and explicit
downgrade refusal, transactional migration/read-back, early startup gate, redacted backup/foreign
envelope rejection and explicit Windows credential re-entry recovery with a retained
snapshot. Mac Keychain behavior and unpackaged Windows storage remain intact. Native
DPAPI tests use synthetic data; installed/cross-user checks are not yet complete.

- Extend the existing `CredentialProtection` boundary with Windows user-scoped DPAPI
  support. Decide and document a platform-specific versioned envelope before writing
  encrypted values; do not confuse Windows ciphertext with the existing Mac envelope.
- Enable protection before database access and before task/MCP startup in packaged
  Windows installs. Keep the current direct-distribution behavior explicit for this
  release; broader direct-install encryption is separate work.
- Protect channel keys, proxy passwords and MCP tokens. Audit cookie storage and
  sensitive logs separately and resolve their handling before the privacy review;
  this is not a claim of whole-database encryption.
- Migrate existing plaintext transactionally with read-back verification. On failure,
  retain original data, stop dependent startup and provide a recoverable error.
  Never silently fall back to plaintext or send ciphertext as an API credential.
- Preserve backup redaction. Reject foreign encrypted values; document that copying
  a database to another user/device is not a credential-transfer mechanism. Design
  an explicit credential re-entry recovery path that preserves non-secret data.
- Make shared recovery messages platform-neutral or platform-specific as appropriate;
  update all four languages. Extend the credential architecture note.

Acceptance: synthetic migration, restart, rotation, corrupt-envelope, wrong-user,
import/export and failure-retry tests pass. Native packaged tests verify protection
under the standard Windows user account, without exposing secrets in logs or backups.

### WIN-04 AI safety and sharing acceptance

Dependencies: WIN-01 Store build; reuse MAS-04/MAS-05 mechanisms and findings.

Source audit and synthetic checks are recorded in the
[route acceptance matrix](../testing/windows-store-ai-safety.md). Every current
wire has a disposition, checked against the enum by a test. No route has completed
content-safety acceptance; production Windows Store packaging is now blocked in
code while preparation remains available. Remote HTTP policy, provider/custom-route
controls and installed behavior remain release prerequisites. The maintainer
confirmed the existing reporting address/procedure on 2026-11-08.
This does not change the GitHub or Mac App Store runtime/build paths.

- Verify Store Gemini constraints across saved settings, imports, old queued tasks,
  retries, Batch and MCP. Keep direct-mode tests to detect accidental regressions.
- Build a route matrix for supported text/image/video services, assistant streaming,
  previews and custom endpoints. Record provider filtering/refusal behavior and
  whether returned content can reach the UI before an applicable check.
- Define the supported Store behavior for unverified custom/relay endpoints. If a
  route cannot meet the content requirements, remediate its controls or restrict
  that route for the Store release; do not equate a provider label with safety.
- Validate AI consent and revocation on Windows for first use, changed recipients,
  resumed tasks and MCP. Review unencrypted remote endpoints and define treatment
  of sensitive transfers while preserving deliberate localhost integrations.
- Exercise content reporting with and without a mail handler. Confirm a monitored
  destination and response process; avoid automatically attaching private content.

Acceptance: every enabled Store route has a recorded disposition; unresolved safety
gaps block that route or the release. Reporting, consent and revocation work in the
packaged app. Any live paid test requires an agreed test account and budget.

### WIN-05 Privacy and submission materials

Dependencies: final WIN-02 through WIN-04 behavior; draft materials can begin earlier.

- Update `PRIVACY_POLICY.md` to accurately cover Windows protection, remaining
  plaintext data, storage, backups, imports, endpoints and reporting. Verify its
  public URL and the existing application entry point.
- Prepare descriptions and actual Windows screenshots, support contact, category,
  supported languages, system requirements and market selection. Disclose required
  third-party accounts/API keys, external charges and live generative AI clearly.
- Complete the age-rating and generative-AI declarations from enabled capabilities.
  Verify account-type eligibility and any regional requirements with Partner Center.
- Prepare restricted-capability notes explaining full-trust native desktop operation
  and network use. Review third-party content, asset and dependency licenses.
- Prepare reviewer instructions covering first launch, provider setup, consent,
  image/video generation and reporting. Use revocable, limited-budget test credentials
  in the private certification notes, never the public listing or repository.

Acceptance: materials match the candidate; reviewer access works and has sufficient
quota; required account and product fields are confirmed. No upload is implied by
preparing these materials.

### WIN-06 Installed release validation

Dependencies: WIN-01 through WIN-05.

- Run Windows App Certification Kit on the exact candidate; investigate failures
  and warnings and retain the report with the candidate's hash and manifest.
- Install under an isolated standard user on clean Windows environments covering the
  declared OS range. Confirm native dependencies are bundled or properly declared,
  without relying on the development machine's Visual Studio installation.
- Exercise first launch, generation/polling/cancel/retry, video playback/thumbnails,
  download, file operations, notifications, clipboard/share, MCP, offline failures,
  denied file access, restart and credential recovery. Use synthetic data.
- Test a previous packaged version upgrading to the candidate, direct/Store coexistence,
  migration and uninstall. Inspect Start-menu identity, icons and taskbar behavior.
- Record pass/fail evidence in a Windows acceptance note; distinguish automated
  coverage, native checks and untested configurations. Re-test any changed candidate.

Acceptance: no unresolved release-blocking failures; WACK results reviewed; native
checks complete for advertised configurations; reviewer package and materials agree.
Then present the concrete candidate and submission details for the separate decision
to upload/submit. Store certification, not local testing, determines approval.

## Verification and implementation discipline

Each code-changing batch must pass `dart format lib test tool`, `flutter analyze`
with `No issues found!`, and `flutter test -x screenshots` before a commit. Add tests
for storage, credential failure behavior and build-mode boundaries in the matching
layer/domain folders. Follow the existing injected-database and real-async test rules.

UI changes use `joycai-ui-design`; strings use `joycai-l10n` in all four languages,
then merge and generate localization. Render and inspect affected screens at
390/834/1024/1440 in light/dark themes. Shared LLM changes must follow the three-layer
architecture. Validate packaging scripts/workflows and inspect their actual artifacts.

Update the plan ledger after each accepted item, including outstanding limits.
Move durable decisions to architecture notes. Retire this plan after execution as
required by the repository documentation convention.

## Policy references

Recheck these at submission because requirements can change:

- [Microsoft Store policies](https://learn.microsoft.com/en-us/windows/apps/publish/store-policies):
  security, testability, privacy, capability use, commerce, age ratings and live AI.
- [Desktop distribution paths](https://learn.microsoft.com/en-us/windows/apps/distribute-through-store/how-to-distribute-your-win32-app-through-microsoft-store):
  MSIX signing, updates and certification tooling.
- [Capability declarations](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/app-capability-declarations):
  justification for restricted capabilities.
- [Packaged desktop filesystem behavior](https://learn.microsoft.com/windows/msix/desktop/desktop-to-uwp-behind-the-scenes):
  installation-directory protection and redirected storage.
