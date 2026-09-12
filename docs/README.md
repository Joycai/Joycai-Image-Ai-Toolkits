# Documentation

Four kinds of document live here, and the difference between them is the whole
filing system:

| Directory | What it is | Rots when |
|---|---|---|
| [`architecture/`](architecture/) | How a subsystem works **today** — invariants, accepted limits, rejected alternatives. Maintained alongside the code. | The code changes and the note doesn't. Read it before changing that subsystem. |
| [`api/`](api/) | **Protocol facts** about other people's APIs. "What the industry looks like", never "what this project chose". No `lib/` paths, on purpose. | A vendor changes their wire format. |
| [`ai-agent-playbook/`](ai-agent-playbook/) | A reusable spec for building a multi-provider AI layer and an agent runtime, distilled from another project. Written to be dropped into a new repo as a standard. | Rarely — it is about mechanisms, not versions. |
| [`plans/`](plans/) | One-shot construction specs. Deleted once executed; what survives goes into the ledger. | Immediately after landing — that is why they get retired. |

Anything that is a dated snapshot of the code (an audit with `file:line`
references, a phase-completion note, a conformance table) does not get a home
here. It goes stale within one refactor and is more misleading than absent —
run `/code-review` or `/security-review` for a fresh one instead.

---

## Architecture notes

Required reading before touching the subsystem each one covers.

* **[LLM three-layer API stack](architecture/llm-three-layer.md)** — the
  protocol / vendor / model layering under `lib/services/llm/`, the single
  dispatcher routing table, the greppable hard-coding red-flag list, and the
  old→new path map for reading pre-refactor documents.
* **[Prompt Assistant context management](architecture/assistant-context.md)** —
  the elide/compact layers, the `context_window` tri-state, and how
  knowledge-base reads are budgeted and paged.
* **[Design tokens, multi-accent and liquid glass](architecture/design-tokens.md)** —
  where the tokens live, why the greys never follow the accent, the three
  forms the accent may take, the glass grades and their budget, and the
  deliberate divergences from the design spec.

## API reference

[`api/README.md`](api/README.md) is the index: four protocol families, the
three orthogonal axes (family / deployment / compatibility layer), and a file
per topic — [tools](api/tools.md), [streaming](api/streaming.md),
[reasoning](api/reasoning.md), [usage](api/usage.md),
[structured output](api/structured.md) — plus one per vendor whose wire is its
own ([Qianwen/DashScope](api/qianwen-bailian.md), [MiniMax](api/minimax.md),
[Veo](api/veo.md), [Gemini](api/gemini-api.md),
[Gemini images](api/google-api-standard.md)).

## AI agent playbook

[`ai-agent-playbook/README.md`](ai-agent-playbook/README.md) — twelve chapters
across the protocol layer, the agent runtime, sub-agents and long sessions,
closing with a [pitfall catalogue](ai-agent-playbook/11-pitfalls.md) and a
[staged migration roadmap](ai-agent-playbook/12-migration-roadmap.md).

## Plans and the ledger

[`plans/README.md`](plans/README.md) — which rounds landed, where their
conclusions now live, and **what is still owed**: the six checks that need a
real API key, three design gaps left out of the model-editor round, and two
security findings that are still open.

## Tooling

* **[UI screenshot harness](ui-screenshot-harness.md)** — renders the real
  screens headlessly at four widths in light and dark, so a layout can be
  looked at instead of inferred. Not a regression gate.

* **Render-performance probe** (`test/screenshots/render_probe.dart`) — the
  same trick for cost instead of looks: mounts the real tree and reports what
  one state change rebuilds, what a whole gesture costs, how many glass layers
  a screen carries, and what an animation drags into its repaint. Run it by
  name, `flutter test test/screenshots/render_probe.dart`; it is deliberately
  not a `*_test.dart` file, so it stays out of CI. Read its header before the
  numbers — the widget counts are the signal, the milliseconds are not. The
  regressions it has already found are pinned by
  `test/screenshots/rebuild_scope_test.dart` and
  `test/render_performance_test.dart`.

## Release notes

[`release_notes/`](release_notes/) archives v1.1.0 – v2.3.0. From v2.4.0
onwards the notes live on
[GitHub Releases](https://github.com/Joycai/Joycai-Image-Ai-Toolkits/releases).
