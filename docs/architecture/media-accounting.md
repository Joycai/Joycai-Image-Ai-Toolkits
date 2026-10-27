# Media usage and USD cost accounting

Schema v52 adds nullable `token_usage.accounting`, nullable
`fee_groups.media_pricing`, and transaction identities in `usage_events`.
Historical rows remain on the legacy arithmetic path; prices and quantities are
not inferred or backfilled. New rows use `UsageAccounting` components exclusively,
never the sum of legacy columns and components. Currency remains USD; this does
not introduce exchange-rate conversion or subscription/invoice billing.

`MediaAccounting.price` is the common arithmetic and validation entry for ordinary
requests and Image Batch. Text input/cache/output use existing prices. Image
input/cache/output have separate optional per-million prices; missing differs from
explicit zero. Cache belongs to its own modality. Inclusive totals validate the
buckets, but are not additional charges. Missing cache information produces a
labelled non-cache estimate; a nonzero total cache without a usable modality split
makes the result incomplete. Missing usage or missing prices cannot appear as an
actual zero bill. Batch keeps a result deliverable while incomplete usage waits
for a later refresh; completion replaces the incomplete row under the same scope.

Spec/request billing retains independently charged input images even with zero
output. Video input seconds are a distinct component; their rate table matches
**output** size/quality/duration. Submission captures the entire applicable rule
table and known inputs, with `pending` status. MiniMax supplies sent video duration
as an estimate and terminal `usage.input_seconds`, `usage.output_seconds`,
`usage.input_image_count` and `task.resolution` as evidence. Folded video token
counts are not charged again. Other adapters leave unavailable measurements
unknown; new adapters must normalize actual evidence rather than guess zero.
Fractional seconds and explicit zero survive settlement; media-container duration
is not substituted for billing usage. Unsupported generation APIs (regeneration,
Context-IR, etc.) are not introduced by this accounting change.

Video usage IDs include the local task scope and are persisted beside the remote
operation identity in task parameters. Resuming pre-v52 tasks retains the legacy
identity; without a full historic price table their estimate is not repriced with
current settings. Terminal components, legacy display projections and a reported
USD total are updated atomically. A complete trusted reported total (including 0)
replaces the estimate, while `snapshotCost` remains available. No report is not a
free result. Failure, cancellation and absence of output do not independently
establish refund evidence: the estimate remains pending. A provider report is not
an independently reconciled invoice.

Before SQLite writes, `UsageRepository` flushes an event to `usage-journal/` next
to the selected database and atomically renames it. This spool contains normalized
quantities and prices, never credentials or prompts. Applied event identity and
row mutation commit together. Startup and usage reads replay submissions before
settlements; retries never submit another generation. Duplicate events are no-ops;
older settlement versions cannot replace newer evidence. Failed events remain on
disk and are logged. If journal persistence fails, SQLite is still attempted; if
both stores fail, recording loss is explicitly reported without hiding a paid
result. In-memory test databases disable disk journaling; recovery tests use a
private temporary file database. Accounting updates invalidate usage checkpoints.
Malformed recovery envelopes are isolated so other events can still replay. Clearing
usage records atomically discards matching pending events before removing their
spool files, including model-scoped clears. Settlement identity includes its version;
a later correction may restore an earlier quantity, while identical evidence does
not advance the accounting revision.

Gemini nonempty modality breakdowns explicitly enumerate present modalities; a
text-only breakdown therefore has no image usage, while a missing breakdown stays
unknown. Counters are validated individually before aggregation, and reasoning
output belongs to the text bucket. Ordinary token requests and Batch both derive
legacy chart counters and blended rates from the same disjoint components.

The editor reuses existing fee-group fields and the spec table, with an optional
input-video section and four languages. Usage rows show `≈` for estimates and `—`
for entirely unknown costs; expanded details expose status and individual known
components. Totals are known-item estimates, not a claim that incomplete or
pending requests were actually charged. Original visual design exports were not
available; repository specifications and before/after Flutter renders are the
visual reference.
