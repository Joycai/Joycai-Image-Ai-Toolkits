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
request a fresh code review or security review instead.

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
* **[Keyboard shortcuts](architecture/keyboard-shortcuts.md)** — the three
  tiers a key can be claimed at, why anything acting on a selection belongs to
  a focus region rather than to a screen, the text-field gate that has no
  exceptions, and the handful of ways all of this fails silently.

## API reference

[`api/README.md`](api/README.md) is the index: four protocol families, the
three orthogonal axes (family / deployment / compatibility layer), and a file
per topic — [tools](api/tools.md), [streaming](api/streaming.md),
[reasoning](api/reasoning.md), [usage](api/usage.md),
[structured output](api/structured.md), [Responses](api/responses.md) — plus
one per vendor whose wire is its own ([Qianwen/DashScope](api/qianwen-bailian.md),
[MiniMax](api/minimax.md), [Volcengine Ark / Seedream](api/volcengine-ark.md),
[Veo](api/veo.md), [Gemini](api/gemini-api.md),
[Gemini images](api/google-api-standard.md)).

## AI agent playbook

[`ai-agent-playbook/README.md`](ai-agent-playbook/README.md) — five layers:
process (an [audit playbook](ai-agent-playbook/00-audit-playbook.md), two staged
roadmaps — [protocol](ai-agent-playbook/12-migration-roadmap.md) /
[agent](ai-agent-playbook/12b-agent-roadmap.md) — and the
[knowledge-ingestion protocol](ai-agent-playbook/30-knowledge-ingestion.md));
conclusion matrices ([platforms](ai-agent-playbook/20-platform-matrix.md),
[model × platform × face](ai-agent-playbook/22-model-capability-matrix.md),
[image / video / ASR](ai-agent-playbook/23-media-matrix.md),
[open questions](ai-agent-playbook/31-open-questions.md)); the prose itself
(protocol layer, all four families with Responses included; agent runtime,
sub-agents and long sessions; media generation and speech recognition); two
[pitfall catalogues](ai-agent-playbook/11-pitfalls.md) (protocol /
[agent](ai-agent-playbook/11b-agent-pitfalls.md)); and a
[changelog](ai-agent-playbook/CHANGELOG.md). It is a snapshot of two skills'
references — `ai-agent-architecture` (v2.1.0) and `agent-runtime-architecture`
(synced 2026-09-30); re-sync it from there rather than editing it here. Facts
this repo measures go into the skill first (per its ingestion protocol), then
come back with the next sync.

## Plans and the ledger

[`plans/README.md`](plans/README.md) — which rounds landed, where their
conclusions now live, and **what is still owed**, grouped by round: the
checks that need a real API key (each with its pass/fail criterion), the
deliberate departures from each design brief, and what the security round
chose not to encrypt and why.

## Codex project setup

[`../AGENTS.md`](../AGENTS.md) is the canonical project instruction file.
Repository skills live in [`../.agents/skills/`](../.agents/skills/), including the
five project workflows for localization, task types, providers, versions, and builds.
Codex discovers these files; if migrated skills do not appear in an existing session,
start a fresh chat in this repository.

No project-specific Codex configuration is required by the current setup. Personal
model, sandbox, approval, and MCP preferences stay in the user's Codex configuration.
Claude's local command approvals are not portable Codex configuration; the ignored
`.claude/settings.local.json` and existing `.claude/worktrees/` remain local.
The external playbook source skills listed above are needed only for a requested
re-sync; the checked-in playbook remains readable without installing them.

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
  `test/core/render_performance_test.dart`.

* **GPU render bench** (`lib/bench/render_bench.dart`) — the raster/GPU side,
  inert unless `RBENCH=1`. Build profile, then drive the exe with
  `RBENCH_SCENE` (`blank`, `aurora-live`/`aurora`, `glass0`…`glass4`,
  `app-lightbox-legacy`/`app-lightbox`, …) at a fixed `RBENCH_SIZE`; it prints
  `FrameTiming` percentiles and a layer census. Three traps:
  * **`rasterDuration` does not see GPU time on Windows.** The app pins Skia on
    ANGLE (`windows/runner/main.cpp`, for video_player_win's DXGI textures),
    which executes asynchronously — a scene reading 0.9ms of raster was really
    11ms of GPU. Read `\GPU Engine(pid_<pid>*engtype_3d)\Running Time` instead.
  * **Check which adapter the process landed on.** The dev machine's display
    hangs off the integrated Radeon, and Windows puts the app there.
  * **Absolute numbers drift up to 2x between sessions** — always take before
    and after in one pass, which is what the `*-live` / `*-legacy` scene pairs
    exist for.

## Release notes

[`release_notes/`](release_notes/) archives v1.1.0 – v2.3.0. From v2.4.0
onwards the notes live on
[GitHub Releases](https://github.com/Joycai/Joycai-Image-Ai-Toolkits/releases).
