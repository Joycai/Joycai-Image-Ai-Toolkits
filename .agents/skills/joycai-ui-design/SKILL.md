---
name: joycai-ui-design
description: Design, improve, implement, or review Joycai UX/UI while preserving its existing warm-stone theme, paired accents, liquid-glass controls, and Flutter design system. Use for screen layouts, interaction flows, visual polish, and continuing work formerly designed in Claude Design.
---

# Joycai UI design

Continue the project's established visual system with Codex. Read paths below
relative to the repository root.

## Establish the brief

Read `AGENTS.md`, `docs/architecture/ui-design-workflow.md` and
`docs/architecture/design-tokens.md`. Check `docs/plans/README.md` and
`plans/README.md` before proposing a new round. Read the keyboard-shortcut note
when changing keyboard/focus behavior, and the relevant subsystem note for the flow.

Inspect the affected screen, its shared components and actual baseline renders
using `docs/ui-screenshot-harness.md`. Preserve baseline PNGs outside
`build/ui-screenshots/` before another run overwrites them. Old Claude Design
frame IDs are provenance; use supplied originals if available and state when
only the maintained repository specification and renders were inspected.

Describe the user's task and friction, the proposed hierarchy/actions, responsive
layout, relevant states and acceptance criteria. For substantial work, put the
brief in `docs/plans/`; small fixes can use the chat or PR. Follow the requested
design-only or implementation scope without introducing routine approval stops.

## Preserve the visual contract

- Use neutral `ColorScheme` roles by purpose (canvas, column, panel, card, track).
  Warm-stone neutrals stay independent of the accent in light and dark modes.
- Use `AppAccent` for accent forms and text; accent text uses `accentText` or
  `onAccentTint`. Status colors use `AppSemanticColors`/error roles; media overlays
  and identity palettes retain their separate meanings.
- Reuse `AppRadius`, `AppSpace`, `AppSize`, `AppType` and `AppMotion` rather than
  adding local style constants. Read the token note for exact values and exceptions.
- Glass belongs to the control layer. Content, forms and conversation bodies stay
  opaque. Preserve the budget of one full-width glass layer and at most three
  visible glass layers per screen; use the existing glass primitives and fallbacks.
- Reuse components in `widgets/{ui,glass,drag}` and the existing icon vocabulary.
  Respect reduced effects/motion and intentional animation exceptions in the ledger.
  A theme or token change requested by the user needs an explicit design rationale
  and updated contract tests/documentation.

## Implement and review

Follow the repository's layering/state rules and responsive breakpoints. Specify
empty, loading, error, selection and unsaved states as relevant; preserve primary
action clarity, keyboard reachability, semantic labels and mobile touch targets.
Use `joycai-l10n` for user-visible copy in all four languages; inspect long labels.

Run the relevant screen harness file. Inspect before/after PNGs at 390, 834, 1024
and 1440 widths, light/dark, with matching fixture state and locale. Add relevant
variants where missing: `shootMatrix()` covers light at every width and dark only
at desktop. A narrow desktop render does not validate native phone behavior.

For shared components or accent/status changes, run
`flutter test test/screenshots/component_gallery_test.dart` and inspect the
eight themes in both brightnesses. Also render affected screens with alternate
accents when their composition matters. For glass/motion changes inspect reduced
effects/motion; use render probes when painting, blur or rebuild cost changes.

Read harness exceptions and open the images: its green exit code does not assert
visual correctness. Add meaningful behavior tests for changed interactions and
run format, analyze and `flutter test -x screenshots` for code changes as required
by `AGENTS.md`. Report inspected evidence and unverified behavior accurately.

Keep lasting decisions in architecture notes and completed work/obligations in
the plan ledger; retire executed plans under the existing convention. Link
representative renders when handing off an implementation or visual review.
