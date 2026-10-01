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

Report the resulting UX behavior, visual evidence inspected, automated checks and
any unverified states or platform behavior. Link representative local renders for
review. Record durable design decisions and accepted departures in the relevant
architecture note, and completed work or remaining obligations in the plan ledger.
Retire executed construction plans according to the existing repository convention.
Keep token values in their existing sources rather than a second copied style guide.
