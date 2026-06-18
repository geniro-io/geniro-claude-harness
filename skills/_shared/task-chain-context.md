# Task chain context — assemble read-only related-task chain for research priming

This file is the single source of truth. Skills cite this file; do NOT inline-paste the procedure.

Applied by `/geniro:plan` Phase 1 explore and `/geniro:implement` Phase 1 analyze to assemble read-only related-task chain context.

During research, assemble the full chain of related work — the current tracker issue, its parent epic, the sibling sub-tasks under that epic, and the neighboring milestone files on disk — into a single plain-English "TASK CHAIN CONTEXT" block. The block primes the research / analysis subagents and gives the user a "done-before / where-we-are / what's-next" narrative. The chain has two independent halves: a TRACKER half fetched read-only over MCP (persisted by `/geniro:plan` into the spec's tracker linkage), and a MILESTONE half derived fresh from disk every run (never persisted — the `milestone-N.md` files are the durable source of truth).

## Contents

- §1 Purpose + when called
- §2 Inputs
- §3 Half A — Tracker chain (MCP, read-only, depth-1)
- §4 Half B — Milestone chain (disk, no MCP)
- §4.5 Verify the gathered facts against declared data sources
- §5 Assembly — the TASK CHAIN CONTEXT block + facts-only rule
- §6 Output contract
- §7 Caller persistence note
- §8 Fail-open + cost bound + read-only + echo rule
- §9 Anti-rationalization

---

## 1. Purpose + when called

`/geniro:plan` invokes during Phase 1 explore, after the tracker ref is resolved and before the approach-generation phase, so the chain primes the research agents. `/geniro:implement` invokes during Phase 1 analyze, after workspace setup and before the research subagents spawn, so the chain primes the codebase-explorer and knowledge-retrieval agents. Both pass `MODE`; the rest of the contract is identical. `/geniro:review` is NOT a consumer — it keeps its existing lighter tracker context.

## 2. Inputs

| Slot | Meaning |
|---|---|
| `MODE` | `plan` or `implement`. Branches only persistence (see §7); the chain assembly is identical. |
| `WORKFLOW_REFS` | The resolved tracker ref(s) — each `{kind, issue_id, url, status, parent_ref?}`. The primary ref drives Half A. Empty / absent → Half A returns "none". |
| `TASK_DIR` | Planning task-dir. Globbed for `milestone-*.md` siblings + the parent `spec.md` in Half B. |
| `CURRENT_ARTIFACT` | Path to the artifact this run is producing or acting on (`spec.md` or `milestone-N.md`). Half B marks its position in the chain. |

## 3. Half A — Tracker chain (MCP, read-only, depth-1)

Resolve the related tracker chain for the primary ref. Read-only — never create, update, or comment on any tracker item. Depth-1 only: the parent epic and the epic's direct children, no recursion into grandchildren.

Driven by the matching `.geniro/workflow/<kind>.md` contract — read that file for the project's MCP tool names and query shape; never hardcode a tracker API. Resolve the workflow file cwd-first, primary-worktree fallback per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A.

Procedure:

1. **Find the parent epic.** If the primary ref already carries `parent_ref`, use it. Otherwise fetch the primary issue over MCP and read its parent link. No parent → Half A = "none".
2. **Fetch the parent.** Read the parent's `title`, `status`, and a short `scope` (the parent's description / objective, trimmed to ≤280 chars at a sentence boundary).
3. **List the parent's children.** Fetch the parent's direct children → `siblings[]` of `{issue_id, title, status}`. Exclude the primary ref itself from the sibling list. Cap at 8 entries (the sibling block stays ≤~1200 chars); when more exist, keep the highest-priority / earliest 8 and append a final `- ... +N more` marker. Omit the siblings entirely when the parent has no other children.
4. **Stamp `chain_fetched_at`** with the current ISO-8601 UTC time — this timestamps the chain enrichment independently of the per-ref `fetched_at`.

Char caps: parent `scope` ≤280 chars (sentence-boundary trim); siblings block ≤~1200 chars / ≤8 entries.

Fail-open: MCP unregistered, fetch timeout, or no parent → Half A = "none". A failed Half A never blocks Half B or the caller.

## 4. Half B — Milestone chain (disk, no MCP)

Derive the milestone chain fresh from disk every run. No MCP, no persistence — the `milestone-N.md` files on disk are the durable source of truth, so re-reading them is always current.

Procedure:

1. **Glob** `TASK_DIR` for `milestone-*.md` and the parent `spec.md`.
2. **Classify each milestone** into `done` / `current` / `next` by reading its frontmatter `lifecycle` + Section 11 (Done Condition), plus a sibling `state.md` `phase:` when one is present in the task-dir:
   - `done` — `lifecycle: approved`/`superseded`, OR a sibling state.md in a terminal `phase:` for that milestone.
   - `current` — the milestone matching `CURRENT_ARTIFACT`, OR the lowest-N milestone not yet done.
   - `next` — every milestone after the current one that is not done.
3. **Order by N** (the `milestone-N.md` index) and mark `CURRENT_ARTIFACT`'s position.

No milestone files → Half B = "none".

## 4.5 Verify the gathered facts against declared data sources

Once Half A and Half B have gathered the chain facts — parent epic status, sibling statuses, milestone states — cross-check each LOAD-BEARING chain fact against the project's declared data sources before assembling the block. Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md` for the full discover / screen / cross-check procedure; it consults the maximum applicable set (the project's declared `## Data Sources` plus the built-in code / git / tracker sources). Never assume a status from a single fetch when a declared source can confirm it.

Render each fact by the helper's outcome:

- **Confirmed** by a source → render normally (no annotation).
- **Conflicting** across sources → surface the conflict to the user in plain English and render the fact with the conflict noted (e.g. `In Progress (conflict: prod-db shows shipped)`).
- **Unconfirmed** — no source could corroborate it → mark it `unconfirmed` in the TASK CHAIN CONTEXT block. This extends the facts-only doctrine: today a status the fetch did not return is omitted; now a fetched status that no declared source could corroborate — when declared sources exist that should cover that fact's domain — is ALSO marked `unconfirmed` rather than presented as bare fact.

Fail-open: no declared `## Data Sources` block, or a source errors / fails its read-only screen → fall back to the single-fetch value with a one-line plain-English caveat (e.g. `Couldn't double-check the related-ticket statuses against a project data source — showing the tracker fetch as-is.`); never block assembly. Read-only throughout — this sub-step only reads sources, never mutates a tracker, DB, or deploy state.

## 5. Assembly — the TASK CHAIN CONTEXT block + facts-only rule

Render both halves into one plain-English block for prompt injection. Worked example:

```
TASK CHAIN CONTEXT
This task: CI-303 "Parallelize Case Radar backfill" (Todo)
Part of epic: CI-300 "Case Radar performance epic" (In Progress) — Cut backfill latency below 5 min.
Related tasks in this epic:
  - CI-301 "Per-user job partitioning" — Done (came before)
  - CI-302 "Backfill progress telemetry" — In Progress (conflict: deploy-state shows shipped)
  - CI-304 "Index tuning" — unconfirmed (tracker says Done; no data source could corroborate)
Milestones in this plan:
  [x] milestone-1 "Schema migration" — done
  [>] milestone-2 "Per-user jobs" — current
  [ ] milestone-3 "Telemetry" — next
Where this fits: milestone-1 shipped; this is milestone-2; milestone-3 follows.
```

Render only the halves that resolved — drop the epic/related-tasks lines when Half A is "none"; drop the milestones lines when Half B is "none".

**Facts-only narrative.** Every status, title, and position in the block is CITED from the MCP fetch (Half A) or read from disk (Half B), then cross-checked per §4.5 — never invented or inferred. Each chain fact lands in one of three states:

- **Confirmed** — a source corroborated it → rendered as a plain status word.
- **Conflicting** — sources disagree → rendered with the conflict noted inline and surfaced to the user.
- **Unconfirmed** — no source could corroborate it (or the fetch never returned it) → marked `unconfirmed`, not presented as a bare fact.

A sibling whose status the fetch did not return is still rendered without a status word — that case is unchanged. The §4.5 addition is the third state: a fetched-but-uncorroborated status (when declared sources should cover it) is marked `unconfirmed` rather than rendered as fact. This respects the always-on-verification doctrine: a status the chain cannot ground is never fabricated.

## 6. Output contract

The helper returns two things:

1. **The TASK CHAIN CONTEXT block** (§5) for prompt injection into the caller's research / analysis subagents. Both halves contribute to the block.
2. **`ENRICHED_REFS`** — the Half-A structured fields for `/geniro:plan` to persist: `parent_ref.{title, status, scope}` + `siblings[]` + `chain_fetched_at`, shaped per the canonical tracker-linkage schema in `${CLAUDE_PLUGIN_ROOT}/skills/plan/spec-template.md` §`workflow_refs[]` per-entry shape (the m5-v3 chain-enrichment fields). Only Half A feeds `ENRICHED_REFS`.

The milestone half (Half B) is NEVER persisted — it is re-derived from disk on every run because the `milestone-N.md` files are the durable source of truth and persisting a stale snapshot would drift from them.

## 7. Caller persistence note

- **`/geniro:plan`** merges `ENRICHED_REFS` into state.md `## Workflow Refs`, then Phase 6 copies the tracker linkage (including the chain-enrichment fields) into spec.md frontmatter. The spec's `geniro_schema_version` is set to `m5-v3` only when at least one enrichment field was written; otherwise it stays `m5-v2` (tracker linkage without enrichment) or `m5-v1` (no tracker linkage).
- **`/geniro:implement`** does NOT persist. It reads the enriched tracker fields from the spec when present, re-derives the milestone half from disk, and refreshes the tracker half over MCP only when the spec's `chain_fetched_at` is stale (older than 1 hour) or absent — fail-open, exactly as Half A.

## 8. Fail-open + cost bound + read-only + echo rule

**Fail-open.** Both halves resolving to "none" → the helper returns an empty block; the caller skips injection entirely and proceeds. Any single failure (MCP unregistered, glob empty, malformed frontmatter) degrades that half to "none" and never blocks the caller's actual work.

| Failure | Result |
|---|---|
| `WORKFLOW_REFS` empty / no parent | Half A = "none" |
| MCP unregistered / fetch timeout | Half A = "none" |
| Workflow file absent in cwd + primary | Half A = "none" |
| `TASK_DIR` has no `milestone-*.md` | Half B = "none" |
| Both halves "none" | empty block — caller skips injection |

**Cost bound.** Depth-1 only: the parent epic + its direct siblings (Half A) and the task-dir's sibling milestones (Half B). No recursion into grandchild issues, no cross-epic walks, no fetch of sibling issue bodies (status + title only). This bounds the fetch to a single parent + one children-list call.

**Read-only guarantee.** The helper never mutates a tracker item, never edits the parent or sibling issues, and never writes a milestone or spec file. Half A is fetch-only; Half B is read-only disk glob.

**Plain-English echo.** User-facing lines describe "related tickets and milestones" — never `workflow_refs`, `m5-v3`, "Half A", or "ENRICHED_REFS". Example echo: `Pulled in the related tickets and milestones for context.`

## 9. Anti-rationalization

| Reasoning | Why it is wrong |
|---|---|
| "I'll recurse into the grandchild sub-tasks too for fuller context." | Depth-1 is the cost bound — parent + direct siblings only. Recursion turns a two-call fetch into an unbounded tree walk and floods the prompt with low-signal distant tickets. |
| "A sibling's status wasn't returned — I'll infer 'In Progress' from its title." | Every status is cited from the fetch. An inferred status is a fabricated fact that breaks the spec-challenge fact-verify doctrine. Render the sibling without a status word instead. |
| "The tracker fetch returned a status, so it's a confirmed fact — skip the §4.5 cross-check." | A single fetch is one source. When the project declares data sources whose domain covers that fact, the maximum-source doctrine (§4.5, per data-sources.md) says corroborate against them before presenting the status as fact — a tracker that lags the prod DB or deploy state is exactly the conflict §4.5 surfaces. A fetched status no declared source corroborates is marked `unconfirmed`, not rendered bare. |
| "Half A timed out, so I'll abort the run." | Both halves are fail-open. A failed tracker fetch degrades Half A to "none" and Half B still runs; both "none" returns an empty block and the caller proceeds. The chain is priming context, not a correctness gate. |
| "I'll persist the milestone half into the spec so `/geniro:implement` doesn't re-glob." | The `milestone-N.md` files are the durable source of truth; a persisted snapshot drifts the moment a milestone is edited. The milestone half is re-derived from disk every run by design. |
| "The spec is `m5-v2` and I added enrichment — I'll leave the version alone for safety." | `m5-v3` signals to readers that chain-enrichment fields may be present. Leaving it at `m5-v2` after writing `siblings[]` / `chain_fetched_at` mislabels the spec; bump to `m5-v3` whenever an enrichment field is written. |
| "I'll fetch each sibling's full body so the narrative is richer." | Siblings carry status + title only (depth-1 cost bound). Fetching each body multiplies the call count by the sibling count for marginal narrative gain — the where-we-are framing needs only status + title. |
