# Prompt Assistant: context management

How the Prompt Assistant decides what to send the model, when to summarize, and
how much of a knowledge file it may read at once.

This is the map and the rules. The reasoning for each individual constant and
branch lives in the dartdoc next to it — that is deliberate, so it cannot drift
away from the code it explains. What is written here is what the code *cannot*
say locally: how the pieces fit, which invariants span more than one file, and
which alternatives were tried and rejected (so they don't get "fixed" back in).

## The shape

Two layers and one gate. All three measure the same way, with
`PromptOptimizerAgent.occupiedChars`.

| | When it runs | Lossy? | Code |
|---|---|---|---|
| **Layer 1 — elide** | Before every request | No — the outgoing copy only; the DB keeps the original | `_trimForSend` / `_elide` |
| **Layer 2 — compact** | Once per turn, *outside* the tool loop | Yes — history is really replaced by an LLM summary | `_maybeCompact` |
| **Gate — read cap** | Before every `read_knowledge_file` call | n/a — it bounds what enters | `_readCapNow` → `ContextBudget.readCapChars` |

Layer 1 protects the last `_keepRecentTurns` **user** turns and stubs out bulky
knowledge reads before them. Layer 2 folds everything before that boundary into
a summary. The gate is what keeps a single turn from overflowing on its own,
because neither layer can help mid-loop (see *Accepted limits*).

Per turn, in order: build the system prompt once → warn if it is oversized →
persist → maybe compact → loop { trim, request, calibrate, execute tools }.

## The window tri-state

`llm_models.context_window` is one nullable int encoding three states.
[`ContextBudget`](../../lib/services/llm/context_budget.dart) is the **only**
place that decodes it — two unrelated consumers (this agent, and image batching
in `web_scraper_service.dart`) must not drift on what `null` or `0` mean.

| Stored | Means | Set by |
|---|---|---|
| `null` | unset — assume a conservative default | never picking the control |
| `<= 0` | user asserts no practical limit | "unlimited" |
| `> 0` | an explicit token count | the 9-notch preset slider |

Use `ContextBudget.modeOf` / `.store` rather than comparing to `0` by hand.

## Why characters, not tokens

Budgets are computed in the character domain and converted with
`ContextBudget.charsPerToken`. **The conversion is not a safety factor — a
larger value is more permissive** (`budget = tokens × ratio × charsPerToken`).
The pre-3.5 threshold implicitly assumed ~4 chars/token (an English figure);
against a Chinese knowledge base that let the budget run several times past the
real window, and requests failed before compaction ever fired.

When the provider reports `usage`, `ContextBudget.calibrate` divides the chars
actually sent by the tokens actually billed and the session switches to that
measured ratio. When it doesn't, the conservative default stands.

## The usage readout

The 上下文占用 card in the assistant's right panel shows the same accounting the
budget runs on, so the user can see a turn approaching compaction instead of
discovering it afterwards. `PromptOptimizerAgent.measureContext` builds it;
`ContextUsageSnapshot` (`services/assistant_context_usage.dart`) carries it; the
card is presentational and does no arithmetic beyond formatting.

Three things about it are load-bearing:

1. **It measures `_trimForSend(history)`, not `history`.** Layer 1 is what the
   provider actually receives. A readout over the raw history keeps charging for
   every elided knowledge read the session ever did and never comes back down —
   the number would only ever grow, which is precisely the question the card is
   there to answer.
2. **Tool schemas are counted for display and *not* for the budget.**
   `occupiedChars` excludes them, and it is both the compaction basis and
   `calibrate`'s divisor — widening it would move the trigger for every existing
   session and re-scale every calibrated ratio. So `toolSchemaChars` is measured
   separately. The consequence is deliberate: the card's total is slightly
   larger than the number `shouldCompact` compares, and that direction is the
   safe one (the user sees the fuller figure). The bias partly cancels itself —
   `calibrate` divides a tools-free char count by a tokens count that includes
   them, so the observed ratio comes out low and the budget conservative.
3. **The system prompt and the tool schemas are *recorded*, not derived.**
   Neither is reconstructible from the session: the prompt is assembled per turn
   from a mode, a preset and (in knowledge mode) a file read off disk, and the
   tool list shrinks mid-turn when `read_knowledge_file` is withdrawn.
   `recordRequestBasis` writes both immediately before each request, which is
   why the readout tracks a turn as it runs rather than only at the end of it.
   Until the first request they are **absent from `slices`, not zero** — a
   session restored from the database knows its history exactly and knows
   nothing about the next system prompt, and the card draws that as '—'.

The window itself is the same tri-state, decoded by `ContextBudget.modeOf` and
converted with the session's calibrated ratio when it has one:

| Stored | Bar drawn against | Card says |
|---|---|---|
| `> 0` | `tokens × charsPerToken` | the fraction, plainly |
| `null` | `defaultWindowTokens × charsPerToken` | "no window set — this is the default assumption" |
| `<= 0` | nothing | the spend, and `Unlimited` in place of a denominator |

The unset row is not a cop-out: that assumption is what actually budgets the
turn, so drawing it shows what the app does. What the caption prevents is
presenting it as a measurement of *this* model.

## Invariants

Each of these is load-bearing, and breaking any of them fails *silently* —
nothing throws, the numbers just quietly stop meaning what they claim.

1. **`occupiedChars` includes the system prompt.** It is both the budget basis
   and the divisor in `calibrate`, so it must measure the same request the
   provider billed. It also counts attachments and tool-call argument JSON: a
   content-only tally misses a staged `write_knowledge_file` body entirely and
   over-grants the read budget by exactly that much.
2. **The read cap is recomputed per tool call, never per turn.** One assistant
   message routinely carries several `read_knowledge_file` calls. Computed once,
   every call in the batch claims the same remaining window — an *n*-fold
   overflow. Reading occupancy from `session.history` makes this fall out for
   free: each result is appended before the next call runs.
3. **Page size is determined by the file, not by the call.** Page numbers are
   cache keys (see invariant 4), so the same page must always mean the same
   bytes. A file that fits comes back whole as `1/1`; one that doesn't uses the
   constant `KnowledgeBaseService.pageSize`. Making the page size track the
   remaining window would make page 1 mean different things at different times.
   **One deliberate exception**: when the remaining window cannot hold even one
   full page (`maxChars < pageSize`, i.e. a cap in [2000, 8000)), the page
   shrinks to the cap rather than refusing small-window models any paged read
   at all. In that regime page numbers are *not* stable across reads — the
   worst consequence is a redundant re-read or a stale "already in context"
   note near exhaustion, both self-correcting on the next turn. Accepted, not
   an oversight.
4. **"Already read?" is derived from history, never tracked in a set.** It scans
   tool **results**, not the assistant's tool **calls** — the assistant message
   is appended to history *before* its calls execute, so matching on calls finds
   the read currently being executed and reports every read as a cache hit.
   Results also make failed reads (no `content` key) correctly not count.
   **The same rule now governs image re-views** (`_liveViewedPaths`): a
   `view_image` request is only refused while the earlier attachment still sits
   inside the recent window — once layer 1 elides it (or compaction folds it),
   the model may view the image again. `viewedImagePaths` survives only as the
   UI's "has been looked at" badge and gates nothing the model asks for.
5. **Compaction measures the trimmed history**, not the raw one, or layer 1 is
   pointless.
6. **The unlimited budget is a constant, not derived.** `0 × ratio == 0`, so a
   derived ratio trigger would fire on every single turn.
7. **An oversized system prompt warns, it does not throw.** The window is a
   preset off a slider; a hard failure line would break setups that work today.
8. **Every tool call gets a paired result before the turn ends — except a valid
   `ask_user` call, which is the *one* deliberate exception.** Its result IS the
   user's answer, so the turn returns with the call dangling and the pending
   state is derived from that dangling call (invariant 4's philosophy:
   `pendingAskUser` is a history scan, never a flag). This is safe only because
   nothing sends the history while it dangles, and every path back into a turn
   pairs it first: `answerAskUser`, `resolvePendingAskUserAsFreeText` (free text
   typed while pending), or the self-healing cancel guard at the top of
   `runTurn`. Add a new way to start a turn and skip that guard, and the first
   request 400s on both providers.
9. **A suspended `ask_user` call is the *last* message in the history**, which
   is what makes pairing it later legal — the result appended when the user
   answers lands immediately after the assistant message that made it.
   `canStageAskUser` enforces it by refusing to stage a question batched with
   any other tool call: `view_image` appends its attachment as a **user**
   message once the batch finishes, so a batched question's answer would arrive
   behind it and the history would read `assistant(tool_calls) → tool → user →
   tool`. Providers reject that (docs/api/tools.md §3) and history is
   cumulative, so the session never recovers — this is a session-killer, not a
   turn-killer. `_pairDanglingAskUser` additionally checks adjacency at pairing
   time and, for a history written before this rail existed, strips the call
   rather than appending a misplaced tool message.

## Accepted limits

- **No mid-loop compaction, structurally.** `_maybeCompact` runs outside the
  tool loop, `_recentBoundary` counts only user messages (so the current turn's
  tool results are always inside the protected window), and `_maybeCompact`
  early-returns at `boundary <= 1` anyway. **A single turn can pin the context at
  `window − reserve` until it ends.** The read cap and dropping
  `read_knowledge_file` from the tool list once exhausted are the only brakes.
- **Compaction can never rescue the system prompt** — it only folds history. The
  file map lives in the system prompt and is re-sent in full every request, so
  past ~half the window the turn is doomed and the warning is the only signal.
- `charsPerToken` is a heuristic, and the first request of a session has no
  calibration yet. A very large single-shot read of pure CJK can still overflow.

## Rejected, and why

- **Reading token counts from provider metadata as the occupancy basis.**
  `usage` is optional in the OpenAI-compatible response; llama.cpp, LM Studio
  and various proxies omit it, which reads as *zero* occupancy — on exactly the
  small local models that overflow first. It is used opportunistically for
  calibration, never as the basis.
- **Offset-based cache keys / range-containment checks.** Only needed if page
  size were dynamic; invariant 3 removes the dynamism instead, at the cost of a
  20K file paging as 3 pages rather than 2. No new correctness surface.
- **A `Set` of read pages.** This was the pre-3.5 implementation and it
  deadlocked: nothing invalidated the key when `_elide` or `_maybeCompact`
  removed the content it pointed at, so the model was told "already in the
  conversation — refer to the earlier result" about content that no longer
  existed, with no way to recover. Restarting the app fixed it (restore rebuilt
  the set from surviving rows), which is why it was hard to reproduce. Deriving
  liveness means there is nothing to invalidate. **The image-view path kept the
  old `Set` pattern until 2026-08** — `viewedImagePaths` gated re-views without
  anything invalidating it — and exhibited exactly this deadlock before moving
  to the same derivation (`_liveViewedPaths`).

## Tests

Pure functions are pinned directly; prefer adding to these over end-to-end runs.

| File | Covers |
|---|---|
| `test/context_budget_test.dart` | tri-state, ratio math, reserve scaling, `budgetChars < window` for every preset |
| `test/optimizer_context_budget_test.dart` | `shouldCompact`, `occupiedChars`, per-call cap, exhaustion |
| `test/optimizer_context_usage_test.dart` | the readout: role split, trimmed-not-raw history, window tri-state, unmeasured slices |
| `test/optimizer_context_card_test.dart` | the card's four states (unmeasured / configured / assumed / unlimited) at both panel widths |
| `test/optimizer_kb_liveness_test.dart` | the three deadlock scenarios (elided / compacted / in-flight) |
| `test/knowledge_base_paging_test.dart` | boundary snapping, determinism, degenerate input |
| `test/knowledge_base_read_cap_test.dart` | whole-file vs paged, undersized windows |
| `test/optimizer_image_liveness_test.dart` | image re-view liveness: fresh / elided / compacted |
| `test/openai_chat_payload_test.dart` | reasoning echo-back, inline `<think>` split (sync + cross-chunk), in-body error envelopes |

**Not covered end-to-end:** the model dialog's tri-state control and the
Settings summary-ratio dropdown have never been driven through a real UI run.
