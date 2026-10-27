# Codex UI design workflow

Codex continues both UX/UI design and Flutter implementation for this project.
The visual language remains the September 2026 redesign: warm-stone surfaces,
paired accent themes, restrained glass on controls, and the existing geometry,
typography and motion scales. Changing the design tool does not change that standard.

## Sources and continuity

- [Design tokens](design-tokens.md) defines the visual contract and accepted
  departures from the original designs. Its linked core files and contract tests
  provide the implemented values; use existing shared components under
  `lib/widgets/ui/`, `lib/widgets/glass/` and `lib/widgets/drag/`.
- [Executed work and outstanding decisions](../plans/README.md) and the
  [animation ledger](../../plans/README.md) explain intentional behavior and
  limitations. Check them before proposing work already completed or ruled deliberate.
- [Keyboard shortcuts](keyboard-shortcuts.md) governs keyboard interactions.
  [The screenshot harness](../ui-screenshot-harness.md) explains rendered evidence.
- The original Claude Design project ID and frame names in the design-token note
  and historical ledgers retain their meaning. They identify past sources, not a
  requirement to use Claude Design or DesignSync for new work.

The original design project is unavailable and its files are not checked into this
repository. The maintained specifications, components, contract tests and real app
renders are the reconstructed design reference. Say
which evidence was available; do not claim original-frame parity without seeing
those frames. If an export is supplied, compare it with the current contract and
document conflicts rather than silently restoring already rejected behavior.

## From request to implementation

Use the repository's `joycai-ui-design` skill for design proposals, UI improvements
and visual reviews. For a small fix, the brief can be a concise explanation in the
chat or PR. For a substantial flow, write a construction brief under `docs/plans/`
using the existing ledger conventions. Match the requested scope: a design-only
request produces a reviewable design; an implementation request continues through
code and validation without a separate approval step unless a material decision
requires user input.

A useful brief records:

1. The user task, observed friction and intended improvement, with baseline renders.
2. Information hierarchy, primary/secondary actions, layout and responsive behavior.
3. Relevant states: empty/populated, loading/running, error/retry, selection,
   disabled actions, cancellation and unsaved edits as the flow requires.
4. Component/token choices, keyboard/focus behavior, touch targets, semantic labels,
   and localization implications for en, zh, zh_Hant and ja.
5. Acceptance criteria, affected files, visual checks and justified departures.

Prefer real Flutter renders or a focused harness variant for visual proposals.
An optional wireframe can explain a flow, but actual app renders establish final
visual fidelity. Reuse the existing icon and component vocabulary. Keep business
logic in services/state, and follow the repository's layer boundaries.

## Visual acceptance

Capture the relevant screen before edits and preserve those PNGs outside the
harness output directory, because each run overwrites the same filenames. Compare
before/after at the same size, brightness, accent, locale and fixture state.

Inspect affected layouts at 390, 834, 1024 and 1440 logical pixels. Review light
and dark modes; extend the harness with missing dark/narrow or interaction variants
when needed. `shootMatrix()` renders four light sizes and desktop dark by default,
so it does not itself prove every width in both brightnesses. The 390px desktop
capture proves narrow layout, not Android/iOS platform navigation or native behavior.

For shared components or accent/status changes, render and inspect all eight paired
themes with `component_gallery_test.dart`. For screen-specific accent use, also
review that screen with relevant alternate accents (especially Orange light).
Review reduced visual effects and reduced motion when changing glass or animation.
Check long localized text, focus visibility, reachable actions, scroll/overflow,
and whether status meaning remains clear without relying on color alone.

Screenshot tests overwrite PNGs and pass even when layout exceptions are printed.
Open the generated images and read the exception output; a green harness run is
not visual approval. Assert behavior in meaningful widget tests when behavior
changes, and run the three gates in `AGENTS.md` for code changes. Measure render
cost using the documented probes when a change affects blur, painting or rebuilds.

## Handoff and durable decisions

The macOS app icon uses AppKit's native Dock badge to show the number of tasks
whose status is `processing`. Pending, completed, failed and cancelled tasks do
not count; zero clears the badge. `DockBadgeService` listens to the application
queue for the lifetime of `MyApp`, synchronizes on attachment and only sends
count changes through `joycai/dock_badge`. The badge uses the system appearance,
independent of window size, app accent and locale. Flutter screenshot renders do
not include the operating system's Dock; native appearance needs a running macOS
app check.

Windows uses the same service/channel and processing-only count, rendered as a
white number on a fixed red taskbar overlay through `ITaskbarList3`. The exact
count shrinks to fit for multiple digits; zero removes the overlay. The runner
retains the latest count until `TaskbarButtonCreated` and reapplies it after
Explorer restarts, with DPI-aware rendering. Native icon/COM/drawing resources
are released after each update. This OS badge is independent of the app theme
and screen layout. Windows build and taskbar visual checks require a Windows host;
Flutter screenshots cannot validate the overlay.

Image and video parameter forms share the workbench's `generation_params` panel,
presentation hints, editor registry and localized text mapping. Replace an editor
through that registry; do not copy a control switch into either form. Model/wire
constraints arrive from the dispatcher-resolved schema. Preserve existing App
controls, themes, glass and font inheritance; see [generation parameters](generation-parameters.md)
for ownership, compatibility and extension rules.

Report the resulting UX behavior, visual evidence inspected, automated checks and
any unverified states or platform behavior. Link representative local renders for
review. Record durable design decisions and accepted departures in the relevant
architecture note, and completed work or remaining obligations in the plan ledger.
Retire executed construction plans according to the existing repository convention.
Keep token values in their existing sources rather than a second copied style guide.

GPT Image 2 / 2.5 progressive previews appear directly below the running task's
header on the task queue, without expanding the row. The localized caption marks
the image as an unsaved generation preview. Each preview replaces the prior one;
only the final image becomes a saved result. The preview uses the existing opaque
card, token spacing/radius, a bounded 220px image area and a 640px decode width.
It clears on every terminal outcome. No new glass, animations or theme roles.

The GPT Image timeout control sits first in Application settings under Image
generation, using the existing setting row and dropdown. It defaults to 25 minutes
and applies to new requests. All four locales explain that the threshold warns
about a slow response while waiting continues and late results are saved until
the user cancels. Opaque surfaces, theme roles and existing responsive behavior
are preserved. The maintained specifications and real Flutter before/after
renders are the reference; original Claude Design frames were unavailable.


### GPT Image Batch controls (2026-10-26)

The workbench adds an optional asynchronous switch only for supported official
Images routes; its hint explains the 24-hour window, no previews and reopening
the app to collect results. Mode is visibly reflected in the submit label.
Tasks keep the existing status filters and add an independent submission-mode
segment. Remote phases use compact neutral status pills so cancellation or a
required action remains visible at narrow widths; details retain IDs, last check
and diagnostic text. Refresh is available per task and for all active batches.
Unfinished/unsettled jobs are protected by queue and repository rules, not merely
a disabled menu item. Clear-all explains the protection. Design authority is the
maintained specification and current controls, with four-locale renders at
390/834/1024/1440 in both themes; no new visual system or animation was introduced.

### H3 reference inputs (2026-10-27)

Reference file actions use `AppButton.secondary`, sharing the design system's
label/icon geometry and themed outline. File-row removal intentionally uses
`IconButton` under the global `iconButtonTheme`: `AppIconButton` is reserved
for standalone boxed actions, not icons inside rows or cards. Parameter editors
use `AppDropdown` / `AppSegmentedControl`; duration sliders inherit the global
`SliderTheme` (with a local overlay radius only).

The video workbench retains the existing model/frame/image-reference cards and
adds a compact video/audio reference card only on supported routes (or while
parked files need removal). Buttons wrap, filenames truncate with independent
remove actions, and the existing scrolling column/drawer/sheet keeps the primary
action reachable. Frame-mode aspect ratio is fixed with an explanatory caption;
Lite reference mode offers only fixed ratios. Four locales cover controls,
limits and unsupported-model diagnostics. Maintained design specs and baseline
Flutter renders were used, without historical design-service originals.
