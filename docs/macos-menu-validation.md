# macOS native menu validation — DESK-03

Date: 2026-11-08. Base: `17c79b4`, implementation branch
`codex/macos-native-menus`. Status: implementation and isolated native probe
validation in progress; final full-application acceptance remains open.

## Behavior and ownership

Settings / ⌘, opens the existing Settings destination. View lists the eight
existing destinations using their existing ⌘1…8 bindings. Help exposes the
existing shortcut panel. Commands are supplied by the shell, not implemented in
Swift. They are disabled while the owning Flutter route is covered, and dispatch
rechecks the route to reject stale clicks. Native validation also requires the
main Flutter window to be key, so About and native panels cannot redirect it.
No selection, deletion, generation or file operation is added to the global menu.

About remains AppKit's standard panel and reads bundle name/version/build.
Services, Hide, Quit and window actions retain their existing targets/selectors.
Copy, Cut, Paste, Select All and other editing actions retain the native responder
chain. Native Undo/Redo dispatch to `UndoManager.client`, which Flutter changes
with the focused text history, including fields in modal routes. Edit requests
undo availability when opened; the native main menu handles ⌘Z/⇧⌘Z before the
Flutter keyboard pipeline, so an old menu snapshot cannot suppress a new history
checkpoint or execute the command twice. No field focus means no undo target.

The installed Flutter 3.47.9 SDK only publishes `UndoHistory` state to the system
undo manager on iOS. The original XIB Undo/Redo commands stayed disabled in the
macOS probe. This is why Undo/Redo require an explicit bridge.

`PlatformMenuBar` was evaluated against the installed SDK. Its provided items do
not include the native editing commands. A small AppKit bridge preserves the
existing XIB menu and responder chain instead of replacing editing with synthetic
keystrokes. References: [Flutter PlatformMenuBar](https://api.flutter.dev/flutter/widgets/PlatformMenuBar-class.html)
and [Apple menu validation](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/MenuList/Articles/EnablingMenuItems.html).

App-owned XIB labels use stable identifiers and four-language ARB sources. The
locale follows the application at runtime. Services supplied by other apps and
AppKit's dynamically inserted commands (tab controls, alternate Quit, dynamically
managed full-screen title) remain OS-owned and follow the system language.
The menu adds no Flutter layout, focus node, glass, colour or animation.

## Isolated native probe

`tool/macos_menu_probe.dart` uses the production runner and menu widget without
opening AppState, a database, a task queue or network. Build with:

```
flutter build macos --release -t tool/macos_menu_probe.dart
```

The inspected copy is `/tmp/Joycai Menu Probe.app`, with a distinct
`cn.joycai.desktopMenuProbe` bundle identifier and ad-hoc signature. This is a
local test artifact, not a Store candidate. Host: macOS 27.2 (26B123); Flutter
3.47.9 / Dart 3.13.7. CI's pinned Flutter 3.47.8 was not substituted locally.

Observed through native accessibility actions and keyboard input:

- Settings click, ⌘, and ⌘2 each incremented the probe command counter once.
- View → Tasks in Simplified Chinese dispatched destination 2 exactly once.
- Settings became disabled while a Flutter modal was open.
- The final native-window guard was checked with the standard About panel key:
  Settings was disabled behind it; About still showed the correct bundle version.
- English, Simplified Chinese, Traditional Chinese and Japanese app menu labels
  updated without restarting. Japanese Help opened the shortcut-help probe.
- Native About displayed `Joycai Image AI Toolkits Version 4.31.8 (1)`.
- Cut/Paste preserved the selected synthetic text. Native Undo changed
  `first second` to `first`; ⇧⌘Z restored `first second` after the keyboard fix.
- Both native Quit and ⌘Q terminated only the isolated probe.

The native window screenshot was inspected in the computer-use tool. Open-menu
screenshot requests returned “Screenshot unavailable”; menu labels and enabled
states were inspected through the native accessibility tree. This does **not**
satisfy the plan's requirement for retained native menu screenshots.

## Pinned SDK follow-up

The continuation run uses an isolated checkout of Flutter **3.47.8** at
`737ba8f885`, engine `cf636b1dfb`, with its matching downloaded artifacts.
The installed Flutter SDK was not switched or modified. Local pinned-SDK gates:
format **967 files, zero changes**, analyze **No issues found!**, and full
non-screenshot tests **3586 passed, 12 skipped**. This is local verification of
the CI-pinned SDK; no remote CI run or PR submission is claimed.

Logs and the local fixture live in gitignored
`build/desk03-acceptance-20261108/`. The full-app fixture asserts the independent
bundle ID `cn.joycai.desk03acceptance.r20261108` and matching sandbox support path
before accessing a database. It sets first-run completion, English, a synthetic
prompt, disabled MCP and no channels or tasks, then calls the production `main()`.
It uses the explicit direct-distribution Dart setting to avoid unrelated Store
Keychain provisioning, with App Sandbox retained on the isolated native copy.
This validates desktop behavior, not Store signing or credential acceptance.

## Full-app native follow-up

The pinned-SDK Release fixture built successfully (81.6 MB), and its isolated
ad-hoc signed copy passed strict signature verification. Observed in the real
application, with synthetic data only:

- Application → Settings and ⌘, opened Settings; ⌘5 opened Prompt Library.
- Help → Keyboard shortcuts opened the actual shortcut panel; Escape dismissed it.
- In New Prompt, ⌘Z changed the title `DESK03 first second` to `DESK03 first`;
  ⇧⌘Z restored it. Cut cleared the selected title and Paste restored it.
- ⌘, did not navigate behind the modal, and native Settings was disabled.
- Window exposed the standard commands; Bring All to Front returned to the app,
  but foreground ordering and the other window actions are not yet certified.

Resumed after manual unlock on 2026-11-08:

- The user physically tested ⌘/ and copying the prompt title into Prompt Content
  and reported **both work**. The subsequent native tree showed the actual shortcut
  panel open. This is manual acceptance evidence, not an automated keyboard pass.
- Full-app Application menu labels changed live in en/zh/zh_Hant/ja, including
  About, Settings, Services, Hide and Quit. Edit/View/Window/Help headings also
  followed each locale. English was restored afterward. OS-supplied Services
  children retained their system-managed titles.
- Native Hide removed the test window from the onscreen window inventory; Raise
  restored the application with Settings preserved. Zoom expanded the rendered
  window from 1600×1200 to 3024×1776 pixels, and a second Zoom restored 1600×1200.
  Minimize disabled the native Minimize/Zoom commands; selecting the application
  window in Window restored it to a standard window.
- Native About displayed `Joycai DESK03 Acceptance Version 4.31.8 (1)`, matching
  the isolated bundle. ⌘Q terminated the full-app fixture.

Further continuation on 2026-11-08:

- The user physically checked both remaining help cases and reported **both
  pass**: ⌘/ opens then closes on a second press, and ⇧⌘/ opens help. These are
  user-confirmed results in the full app with its production keyboard handler.
- Services → Services Settings opened System Settings with **Services shortcuts**
  selected. This verifies a concrete native Services action without invoking a
  third-party profiler or transmitting content.
- View → Enter Full Screen expanded the workbench and changed the native menu
  item to Exit Full Screen. Selecting that item restored the narrow workbench
  window and its original controls.
- A further native capture of the isolated app's candidate menu surface produced
  a blank image (`native-menu-surface-attempt.png`); it is failed-capture evidence,
  not an accepted menu screenshot. Window metadata is in
  `resumed-menu-windows.json` alongside it.
- With explicit user approval, AppleScript was tried solely to activate the
  isolated app and open its menus. Activation ran, but System Events rejected
  menu control with error **-1719**, reporting that `osascript` lacks Accessibility
  access. No system permission was granted or changed. This is an OS permission
  block, not an app-menu failure or an automatic approval-review rejection.
- The user chose to **skip the manual VoiceOver check** in this continuation.
  It remains unverified, not passed. The isolated app and System Settings were
  closed using their native Quit menu items; final app inventory confirmed both
  stopped and VoiceOver not running. No implementation code changed in this pass;
  `git diff --check` passed, and the earlier pinned-SDK gates remain the latest
  code verification.

Automation limitations and remaining evidence:

- Automated ⌘/ and ⇧⌘/ did not toggle the shortcut panel. The `super+question`
  input selected native Help search. Physical ⌘/ passed as reported above;
  the shifted variant and repeat-to-close subsequently passed the user's physical
  check above. Automated shortcut delivery itself remains unverified.
- Automated cross-field Paste (including native menu invocation) changed the
  accessibility-reported value without updating the visible body. The user's
  physical Copy/Paste check passed. Do not treat accessibility value changes alone
  as proof of a rendered edit, or this automation discrepancy as a confirmed app
  defect; no speculative editing bridge was added in response.
- The user approved native `screencapture` for this isolated app. Its window
  inventory exposed no visible menu popup even while accessibility exposed the
  open Help menu. The retained `en-native-window.png` shows the application window,
  not an open menu, and does not satisfy the four-language menu screenshot gate.
- VoiceOver was explicitly enabled in System Settings (off → on confirmed).
  Automated VO+M did not expose menu navigation feedback, and binding the VoiceOver
  app timed out. VoiceOver was restored to **off**, confirmed in Settings and the
  final running-app inventory. No spoken-output or VoiceOver-navigation pass is
  claimed. The utility's caption preference was already on and was not changed.
- Keyboard settings listed only ABC and Simplified Pinyin. No non-US hardware
  layout was exercised or added. App-directed synthetic keys cannot establish
  physical layout correctness.
- Services Settings was subsequently verified as described above; no third-party
  service was executed.

The earlier desktop lock was resolved by the user. At the end of the resumed run,
the isolated fixture, VoiceOver Utility and System Settings were all closed through
their UI and verified absent from running apps. No production application was launched.
After the pause, the installed SDK configuration and normal `lib/main.dart`
Release target were restored successfully (81.7 MB); strict signature verification
passed. Restoration logs are `restored-pub.log` and `restored-build.log` beside
the pinned-SDK acceptance logs.

## Automated verification and remaining acceptance

PR preparation: version bumped to **4.31.9+0**. On Flutter **3.47.8**, dependency
resolution succeeded, format checked **967 files with zero changes**, analyze
reported **No issues found!**, and the full non-screenshot suite again passed
**3586 tests, 12 skipped**. The production `lib/main.dart` macOS Release build
succeeded (81.7 MB), passed strict signature verification, and its bundle metadata
was checked as **4.31.9 (0)**. Logs use the `pr-` prefix in the evidence directory.
The native interaction observations above remain evidence from **4.31.8 (1)**;
no new full-app native interaction run is claimed for the version-only bump.

Focused tests cover route enablement, stale callbacks, restoration after pop,
four-language live updates, non-macOS isolation, teardown, and focused Undo/Redo
inside a modal with no mutation after blur. Format: 967 files. Analyze:
`No issues found!`. Full non-screenshot suite: **3586 passed, 12 skipped**.
Settings screenshot harness: 35 passed, no printed exceptions/overflows;
inspected About at 390/834/1024/1440 in both light and dark. Those renders use
fixture version metadata and do not validate native menu or bundle metadata.
Both the final probe and the normal `lib/main.dart` macOS Release target built
successfully; normal build output was restored (81.7 MB). The probe's distinct
ad-hoc signed copy passed `codesign --verify --deep --strict` and was quit after
validation. The normal application was not launched against production data.

Run macOS builds serially with other Flutter commands: a concurrent pub/test run
regenerated the ephemeral Swift package platform to 12.0 during one build,
conflicting with a native dependency's minimum 13.0. A serialized `--no-pub`
build restored Flutter's project-derived deployment target and succeeded; no
tracked platform/dependency setting was changed for this.

Still owed before checking DESK-03 complete:

- Verify invocation counts for full-app native navigation alongside the production
  HardwareKeyboard handler. The isolated probe has exact counts; the full-app
  help toggle and cross-field Copy/Paste have user-confirmed physical results.
- Retained real menu screenshots in all four app languages, and VoiceOver review.
- Non-US keyboard layout checks. Services Settings, Hide, Zoom/restore,
  Minimize/restore, full-screen entry/exit and Quit have results above.
- No Windows/phone native verification is claimed by these macOS checks.
