# L2 episodic-memory write helper

## Contents

- §API — `emit_learning` signature
- §MODE contract
- §Required fields — what every entry must carry
- §Optional fields the helper recognizes
- §Sanitization — secret-redaction before write
- §Dedup pipeline — supersede-chain handling
- §4096-byte limit — the per-line atomicity cap
- §Example callers
- §Known limitations
- §Test coverage

**Status:** Authoritative for every append to `.geniro/knowledge/learnings.jsonl`.

`ARCHITECTURE.md` § "Memory Layers" documents the L2 entry schema and lifecycle.

## API

```bash
source lib/emit-learning.sh
echo '<json-object>' | emit_learning
```

- **Input:** a single JSON object on stdin (one entry per call).
- **Output:** none on success. JSONL line is appended to the log file. The helper does NOT echo the written entry or its computed `recurrence_count`. A caller that needs the post-write `recurrence_count` (e.g. to fire a `recurrence_count >= 3` rule-capture gate) reads it back via `query-learnings` after the emit — filter by the entry's `dedup_key` and pass `--include-superseded`, then read `recurrence_count` from the matched entry.
- **Side effects:**
 - Appends to `.geniro/knowledge/learnings.jsonl` (created if absent).
 - May append to `.geniro/knowledge/.redaction-log.jsonl` (via `redact_secrets`).

**Path resolution:** this helper uses `lib/repo-root.sh::_geniro_repo_root` to find the project root. When invoked from a linked git worktree (where `.geniro/` may exist with just `planning/`), the resolver returns the PRIMARY worktree's path so the L2 append lands in the canonical store. See `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` § "Why this exists" for the contract.

**Return codes:**
- `0` — entry appended, or no-op (identical duplicate).
- `64` — required field missing, or invalid JSON on stdin.
- `68` — serialized entry > 4096 bytes (POSIX atomic-append guarantee lost).

## MODE contract

Write-side helper — **no MODE parameter, compaction-immune.** Behavior is
identical at initial-load, refresh, and post-compaction. Skill flow decides
when to re-invoke after a SessionStart event; the helper itself does not
distinguish.

## Required fields

- `producer` (string)
- `scope` (string)
- `summary` (string)
- `tags` (array)

The helper rejects entries missing any of these with rc=64.

## Optional fields the helper recognizes

- `ts` — auto-injected as UTC ISO-8601 if absent.
- `dedup_key` — auto-computed as `sha256(producer|scope|normalize(summary))[:12]` if absent. `normalize` = lowercase + whitespace collapse + trim. Documented so callers can reproduce the key if they want to look up an entry later.
- `body` — sanitized via `redact_secrets`.
- `ext` — every string-valued path inside (including inside arrays) is sanitized via `redact_secrets`. Path labels in the audit log use dotted notation (e.g. `ext.symptom`, `ext.options.0`).
- `supersedes` — if the caller provides it, it's preserved verbatim. Otherwise the helper may auto-inject it (see Dedup).
- `recurrence_count` — how many times this learning has recurred. Defaults to `1` on a fresh emit. On a dedup match (different content under an existing `dedup_key`), the helper carries forward the prior entry's value and increments by 1, so a learning re-observed N times ends at `recurrence_count: N`. Callers normally leave this unset and let the helper manage it. The helper does not echo the resulting value — a caller that needs to read the post-write count (e.g. to gate a `recurrence_count >= 3` rule-capture offer) re-queries via `query-learnings --include-superseded` filtered by `dedup_key` after the emit. Entries written before this field existed have it absent — `query-learnings` treats absent as `1`, so legacy entries score and rank exactly as they did before the field was added.
- `type`, `trust`, `links`, `deprecated` — passed through unchanged.

Unknown fields are also passed through — the schema is open.

## Sanitization

The helper calls `redact_secrets` on:
- `summary`
- `body` (if present)
- Every string-valued path inside `ext` (recursive — handles nested objects and arrays)

Top-level non-string fields, `tags`, `producer`, `scope`, etc. are NOT sanitized — they are assumed to be control-plane metadata where secrets shouldn't appear and where sanitization would corrupt structure.

## Dedup pipeline

1. Compute or accept `dedup_key`.
2. `tail -n 200` of the log file (cheap — covers the recency window where dups appear).
3. Find the **last** prior entry with matching `dedup_key` (handles supersede chains correctly — the comparison targets the head of the chain).
4. Compare prior vs new excluding `ts`, `recurrence_count`, and `supersedes` via `jq -cS 'del(.ts, .recurrence_count, .supersedes)'` (canonicalized). All three are derived per-write fields: `ts` is auto-injected per write, `recurrence_count` is a re-emit counter, and `supersedes` is auto-injected only on a superseding entry — a fresh re-emit of that same content carries no `supersedes` at compare time. Excluding all three makes an identical re-emit of a superseding entry compare equal (correct no-op); comparing them would make every re-emit look "different", defeating the no-op return and falsely inflating `recurrence_count`.
5. Decisions:
 - **Equal** → no-op return 0.
 - **Different** + caller did NOT set `supersedes` → auto-inject `supersedes: <dedup_key>`, set `recurrence_count` to prior value + 1, append.
 - **Different** + caller set `supersedes` → preserve caller's value, set `recurrence_count` to prior value + 1, append.
6. **No prior match** → append fresh with `recurrence_count: 1`.

The prior entry's `recurrence_count` is read from the matched entry (absent counts as `1`), so a first re-emit lands at `2`, the next at `3`, and so on — the counter rides the supersede chain. `query-learnings` folds this count into its score as a dampened multiplier (a high count strengthens but does not dominate ranking).

## 4096-byte limit

A single JSONL line must fit in `PIPE_BUF` for POSIX `>>` to be atomic. If the line exceeds 4096 bytes, the helper aborts with rc=68 rather than risk torn writes. In practice this means: keep `body` short (≤ ~3.5KB), use `links` for full PRs/commits instead of inlining diffs, and put truly large content into a separate file referenced by `scope`.

## Example callers

```bash
# /geniro:debug auto-emit after CONFIRMED + fix applied
jq -nc \
 --arg p "/geniro:debug" \
 --arg s "src/components/Toggle.tsx" \
 --arg sum "Stale closure in useEffect — value missing from deps" \
 '{
 producer:$p, scope:$s, summary:$sum,
 tags:["bug","react","useEffect"],
 type:"diagnosis",
 ext:{symptom:"toggle stale", root_cause:"missing dep", fix:"add value to deps array"},
 trust:"verified"
 }' | emit_learning
```

```bash
# /geniro:plan recording an architectural decision
jq -nc \
 --arg p "/geniro:plan" \
 '{
 producer:$p, scope:"global",
 summary:"chose fetch over axios",
 tags:["arch","http"],
 type:"decision",
 ext:{options:["axios","fetch"], chosen:"fetch", reasoning:"fewer deps, native AbortController"}
 }' | emit_learning
```

## Known limitations

- **Dedup window is 200 lines.** Older near-duplicates re-append as fresh entries. With typical L2 write volume (a few per `/geniro:debug` session, a few per `/geniro:implement` run) the 200-line window covers weeks; if it becomes too short, callers can pre-query `learnings.jsonl` via `query-learnings` (next helper) and pass `supersedes` explicitly.
- **No multi-entry batching.** One JSON object per call. Callers that need to emit many at once should loop.
- **Sanitization is per-call.** A pattern that fires across multiple ext fields emits multiple audit-log rows. Aggregating is left to readers of the audit log.
- **No producer→trust auto-default.** `ARCHITECTURE.md` § "Memory Layers" documents per-emitter trust defaults (e.g. `/geniro:debug` → `verified`). The helper does NOT auto-set `trust` based on producer; callers must supply it explicitly. Skills will set the right value when they integrate; meanwhile a missing `trust` is treated as `inferred` by `query-learnings` (strictest filter excludes).
- **Concurrent emit-learning with the same caller-supplied `dedup_key` is not serialized.** Two parallel calls with the same key but different content append both without auto-injecting `supersedes`, because each call's dedup-scan happens before the other's append. Acceptable given the helper's no-lock design; if strict serialization is needed, callers can wrap calls with a file lock.

## Test coverage

`tests/memory/emit-learning.sh` exercises the required-fields contract, auto-injected ts and dedup_key, caller-supplied dedup_key, sanitization of summary / body / ext / nested-ext, the dedup pipeline (no-op vs supersede), oversized rejection, and invalid-JSON rejection.
