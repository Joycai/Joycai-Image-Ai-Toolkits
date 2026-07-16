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
4. **"Already read?" is derived from history, never tracked in a set.** It scans
   tool **results**, not the assistant's tool **calls** — the assistant message
   is appended to history *before* its calls execute, so matching on calls finds
   the read currently being executed and reports every read as a cache hit.
   Results also make failed reads (no `content` key) correctly not count.
5. **Compaction measures the trimmed history**, not the raw one, or layer 1 is
   pointless.
6. **The unlimited budget is a constant, not derived.** `0 × ratio == 0`, so a
   derived ratio trigger would fire on every single turn.
7. **An oversized system prompt warns, it does not throw.** The window is a
   preset off a slider; a hard failure line would break setups that work today.

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
  liveness means there is nothing to invalidate.

## Tests

Pure functions are pinned directly; prefer adding to these over end-to-end runs.

| File | Covers |
|---|---|
| `test/context_budget_test.dart` | tri-state, ratio math, reserve scaling, `budgetChars < window` for every preset |
| `test/optimizer_context_budget_test.dart` | `shouldCompact`, `occupiedChars`, per-call cap, exhaustion |
| `test/optimizer_kb_liveness_test.dart` | the three deadlock scenarios (elided / compacted / in-flight) |
| `test/knowledge_base_paging_test.dart` | boundary snapping, determinism, degenerate input |
| `test/knowledge_base_read_cap_test.dart` | whole-file vs paged, undersized windows |

**Not covered end-to-end:** the model dialog's tri-state control and the
Settings summary-ratio dropdown have never been driven through a real UI run.
