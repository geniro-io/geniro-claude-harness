# L2 episodic-memory write helper

## Contents

- §API — `emit_learning` signature
- §Caller contract — make the write visible and non-trailing
- §MODE contract
- §Required fields — what every entry must carry
- §Evidence bar for `trust: verified` — the captured-artifact requirement
- §Optional fields the helper recognizes
- §Sanitization — secret-redaction before write
- §Injection rejection — write-time prompt-injection guard
- §Dedup pipeline — supersede-chain handling
- §Per-line byte ceiling — the append helper's sanity limit
- §Example callers
- §Known limitations

**Status:** Authoritative for every append to `.geniro/knowledge/learnings.jsonl`.

The canonical L2 entry schema is documented in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` § "T3 — append-only (learnings sidecar)"; `ARCHITECTURE.md` § "Memory Layers" covers the four-layer taxonomy and lifecycle.

## API

```bash
source lib/emit-learning.sh
echo '<json-object>' | emit_learning
```

- **Input:** a single JSON object on stdin (one entry per call).
- **Output:** none on success. JSONL line is appended to the log file. The helper does NOT echo the written entry or its computed `recurrence_count` — a caller that needs the post-write count reads it back via `query-learnings`; see the `recurrence_count` field note below for the exact filter.
- **Side effects:**
 - Appends to `.geniro/knowledge/learnings.jsonl` (created if absent).
 - May append to `.geniro/knowledge/.redaction-log.jsonl` (via `redact_secrets`).

**Path resolution:** `lib/repo-root.sh::_geniro_repo_root` resolves to the PRIMARY worktree, so the L2 append lands in the canonical store, never a linked worktree's. Contract: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` § "Why this exists".

**Return codes:**
- `0` — entry appended, or no-op (identical duplicate).
- `64` — required field missing, invalid JSON on stdin, or an instruction-injection payload was rejected (see §Injection rejection).
- `65` — could not create the `.geniro/knowledge/` parent directory (propagated from `atomic_state_append`).
- `68` — serialized entry exceeds the append helper's per-line byte ceiling (`GENIRO_APPEND_MAX_BYTES`; see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` §`atomic_state_append <target>`) — POSIX atomic-append guarantee lost.
- `69` — append write failed (disk full / permission denied; propagated from `atomic_state_append`).

## Caller contract — make the write visible and non-trailing

`emit_learning` is silent by design (no stdout on success). That silence is the failure surface: a step with no in-session signal that it ran is the first thing dropped when the orchestrator wraps up after the user-visible deliverable. The rules below bind every caller of this helper.

1. **Echo the write.** After a successful emit (`rc=0`), print one plain-English line to the user: `Recorded learning: <one-line summary>`. The echo is both a confirmation the user can see and a self-check that the step actually ran. `rc=0` covers a fresh append and a dedup no-op alike — echo either way, since the learning is in the store in both cases. Echo only the user-facing knowledge emits — `diagnosis`, `convention`, `decision`, `discovery`, `pitfall`. High-frequency internal bookkeeping emits (`discarded_hypothesis` per rejected hypothesis, `retry_failure_sequence`) are priming data, not findings; they stay silent so one debug Phase 1 doesn't echo five times.

2. **Fire it before the done declaration.** Sequence the emit ahead of the phase's terminal `phase: done` / handoff / final answer — and ahead of the outward-facing deliverable (push / PR / posted answer) when the learning doesn't depend on that deliverable's outcome. A local commit is not the drop-vector this rule guards against: the work still reads as in-progress on the branch, so sequencing the emit relative to a commit alone is not load-bearing. An emit placed after the outward deliverable is trailing housekeeping: once the PR is open or the answer is posted, the work reads as finished and the trailing step gets skipped. Making the emit part of completing the work — not a postscript to it — is what keeps it from being dropped.

3. **Surface a non-zero return — don't wave it off.** The helper prints nothing on success, so a swallowed non-zero return is indistinguishable from a clean write — the learning is gone and nothing in the session says so. On a non-zero return, diagnose the exit code against the §Return codes table and print one plain-English line so the loss is visible — e.g. `Couldn't record the learning — entry oversized` (rc=68), `Couldn't record the learning — a required field was missing` (rc=64), `Couldn't record the learning — write failed (disk full or permission denied)` (rc=69). Retry once only for the write-failed code (rc=69), since a transient disk/permission condition may clear; the other codes (missing field rc=64, oversized rc=68) describe the entry itself and won't succeed on a retry — fix the entry or surface and move on. Never run the emit as a backgrounded command: a backgrounded failure returns no exit code to inspect, so its loss is noticed only by accident.

4. **Route through a declared memory backend.** When `memory.md` carries a `## Memory Backend` block routing the `learnings` layer (surfaced by the L4 loader), apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/memory-backend.md` §4-§5 around this emit — mirror/replace handling, redact-before-store via `lib/redact-secrets.sh`, and fail-open to the file append all live there. No block → this is a no-op and the emit is the file append exactly as above.

## Sliding-window caps on bookkeeping types

The bookkeeping types (`retry_failure_sequence`, `discarded_hypothesis`) accumulate one entry per failed attempt, so an unbounded log fills `query-learnings` results with stale noise and drowns the findings a caller actually wants primed. Each capped type keeps only its N most recent entries per key:

| Type | Cap | Key |
|---|---|---|
| `retry_failure_sequence` | 3 | `(producer, scope, phase)` |
| `discarded_hypothesis` | 5 | `(producer, scope)` |

**On overflow, flip the oldest matching entry's `deprecated: true` BEFORE appending the new one.** That mutates an existing line in `.geniro/knowledge/learnings.jsonl`, which the append-only helper does not do — rewrite the file through `atomic_state_write`, never a direct `Edit`/`Write`. The state-helper hook blocks those two routes, so an attempt at them fails the step rather than corrupting the log; appending first and pruning after leaves the window over-full for any reader that queries in between.

Hold the shared knowledge-rewrite lock across the read-modify-write — the same one the archival path and the access-counter bump take. A whole-file rewrite that skips it silently discards every append another session made between the read and the rename.

That lock is a **directory**, created with `mkdir "<repo-root>/.geniro/knowledge/.archive-stale.lock"` and released with `rmdir` on exit; `mkdir` failing IS the "already held" signal, which is what makes the acquisition atomic. The mechanism is load-bearing, not an implementation detail: creating a *file* at that path leaves `mkdir` failing forever while the staleness check (`[ -d ]`) never sees a lock to reclaim, so every later rewrite in the repo wedges. When the lock is already held, skip the prune and append anyway — an over-full window self-corrects at the next emit, whereas a clobbered append is unrecoverable.

## MODE contract

**No MODE parameter, compaction-immune** — safe to re-invoke after a SessionStart event; the helper
does not distinguish initial-load from refresh.

## Required fields

- `producer` (string)
- `scope` (string)
- `summary` (string)
- `tags` (array)

The helper rejects entries missing any of these with rc=64.

## Evidence bar for `trust: verified`

A learning emitted with `trust: verified` is grounded in a captured observation from the run — a test result, command output, log line, or `file:line` the producer actually read (an Evidence Block artifact per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`). A conclusion reasoned from context without such an observation is `trust: inferred`, not `verified`. Diagnosis-type learnings (root-cause claims, client/tool behavior claims) need the observation to actually demonstrate the claimed cause — a plausible explanation for a symptom is correlation, not verification. Memory outlives the session: a confidently-recorded wrong diagnosis misdirects every future session that recalls it, so the bar for `verified` is the captured artifact, not confidence.

## Optional fields the helper recognizes

- `ts` — auto-injected as UTC ISO-8601 if absent.
- `dedup_key` — auto-computed as `sha256(producer|scope|normalize(summary))[:12]` if absent. `normalize` = lowercase + whitespace collapse + trim. Documented so callers can reproduce the key if they want to look up an entry later.
- `body` — sanitized via `redact_secrets`.
- `ext` — every string value anywhere inside is sanitized via `redact_secrets`, whatever shape `ext` takes: a scalar string, an object, or arrays nested inside. Path labels in the audit log use dotted notation (e.g. `ext.symptom`, `ext.options.0`).
- `links` — walked and sanitized the same way as `ext` — a credential-bearing URL must not land unredacted, so `links` routes through `redact_secrets` like every other free-text field (e.g. `links.pr`, `links.refs.0`).
- `supersedes` — if the caller provides it, it's preserved verbatim. Otherwise the helper may auto-inject it (see Dedup).
- `recurrence_count` — how many times this learning has recurred. Defaults to `1` on a fresh emit. On a dedup match (different content under an existing `dedup_key`), the helper carries forward the prior entry's value and increments by 1, so a learning re-observed N times ends at `recurrence_count: N`. Callers normally leave this unset and let the helper manage it. The helper does not echo the resulting value — a caller that needs to read the post-write count re-queries after the emit via `source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh" && query_learnings --include-superseded`, filtered by `dedup_key`. Entries written before this field existed have it absent — `query-learnings` treats absent as `1`, so legacy entries score and rank exactly as they did before the field was added.
- `type`, `trust`, `deprecated` — passed through unchanged.

Unknown fields are also passed through — the schema is open.

## Sanitization

The helper calls `redact_secrets` on:
- `summary`
- `body` (if present)
- Every remaining string value anywhere else in the entry, at any depth and regardless of container — `ext`, `links`, `tags[]` elements (including a string nested inside a non-string element), and any caller-added key. One walk covers all of them, so a shape none of the schema fields anticipate (a scalar `ext`, an object buried in `tags[]`) is still reached.

The control-plane identifiers — `producer`, `scope`, `type`, `trust`, `ts`, `dedup_key`, `supersedes` — are excluded from that walk: they are assumed to hold no secrets, and sanitizing them would corrupt structure the helper itself relies on.

## Injection rejection

L2 entries are re-loaded into orchestrator and subagent context by `query-learnings`. A learning auto-emitted from untrusted text (a fetched page, a PR body, peer-PR content) could carry a prompt-injection payload that is then replayed verbatim into a later session. The read side is defended by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/untrusted-content-defense.md` (inlined into every subagent); this helper closes the **write** side as defense-in-depth.

Before redaction and dedup, `emit_learning` scans **every string value in the entry** (`summary`, `body`, every string inside `ext`, and any non-canonical free-text key such as `entry`/`note`) for two high-signal injection shapes and rejects the entry with `rc=64` if either matches:

- **Override phrasing** — `<verb> <previous-reference> <instruction-noun>`, e.g. "ignore previous instructions", "disregard the above context", "new directives:". Genuine technical learnings essentially never use this structure.
- **Chat-template control tokens** — `<|im_start|>`, `<|system|>`, `</system>`, etc.

The pattern set is deliberately narrow. A false reject drops just one best-effort learning — the caller surfaces the non-zero return per §Caller contract rule 3 but does not block the workflow on it — whereas a stored payload persists across sessions. If a legitimate learning needs one of these phrases, rephrase it. Control-plane tokens (`producer`/`scope`/`tags`/`type`/`trust`) are scanned too but never match the structured shapes, so scanning the whole entry is harmless and removes any "smuggle it into a non-standard key" bypass.

## Dedup pipeline

1. Compute or accept `dedup_key`.
2. `tail -n "$GENIRO_DEDUP_WINDOW"` of the log file (cheap — covers the recency window where dups appear; see §Known limitations for the default and how to override it).
3. Find the **last** prior entry with matching `dedup_key` (handles supersede chains correctly — the comparison targets the head of the chain).
4. Compare prior vs new excluding `ts`, `recurrence_count`, and `supersedes` via `jq -cS 'del(.ts, .recurrence_count, .supersedes)'` (canonicalized). All three are derived per-write fields: `ts` is auto-injected per write, `recurrence_count` is a re-emit counter, and `supersedes` is auto-injected only on a superseding entry — a fresh re-emit of that same content carries no `supersedes` at compare time. Excluding all three makes an identical re-emit of a superseding entry compare equal (correct no-op); comparing them would make every re-emit look "different", defeating the no-op return and falsely inflating `recurrence_count`.
5. Decisions:
 - **Equal** → no-op return 0.
 - **Different** + caller did NOT set `supersedes` → auto-inject `supersedes: <dedup_key>`, set `recurrence_count` to prior value + 1, append.
 - **Different** + caller set `supersedes` → preserve caller's value, set `recurrence_count` to prior value + 1, append.
6. **No prior match** → append fresh with `recurrence_count: 1`.

The prior entry's `recurrence_count` is read from the matched entry (absent counts as `1`), so a first re-emit lands at `2`, the next at `3`, and so on — the counter rides the supersede chain. `query-learnings` folds this count into its score as a dampened multiplier (a high count strengthens but does not dominate ranking).

## Per-line byte ceiling

A single JSONL line must stay under the append helper's per-line byte ceiling, or it aborts with rc=68 rather than risk a torn write — the exact value (`GENIRO_APPEND_MAX_BYTES`) and its newline-framing accounting are canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` §`atomic_state_append <target>`. That ceiling bounds line length; it is not by itself an atomicity guarantee — POSIX `PIPE_BUF` (the size up to which `>>` appends are kernel-serialized) is platform-dependent: 4096 bytes on Linux but only 512 on macOS. So a line near the ceiling is not guaranteed to append atomically on macOS; see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` §Known limitations for the canonical caveat. In practice: keep `body` short (≤ ~3.5KB), use `links` for full PRs/commits instead of inlining diffs, and put truly large content into a separate file referenced by `scope`.

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

- **Dedup window is bounded by `GENIRO_DEDUP_WINDOW`** (single-sourced in `lib/emit-learning.sh`). Older near-duplicates re-append as fresh entries. With typical L2 write volume (a few per `/geniro:debug` session, a few per `/geniro:implement` run) the default covers weeks; if it becomes too short, set `GENIRO_DEDUP_WINDOW` wider or have callers pre-query `learnings.jsonl` via `query-learnings` and pass `supersedes` explicitly.
- **No multi-entry batching.** One JSON object per call. Callers that need to emit many at once should loop.
- **Sanitization is per-call.** A pattern that fires across multiple ext fields emits multiple audit-log rows. Aggregating is left to readers of the audit log.
- **No producer→trust auto-default.** The helper does NOT auto-set `trust` based on producer; each caller supplies it explicitly at its emit site (e.g. `/geniro:debug` emits confirmed root causes as `verified`). A missing `trust` is treated as `inferred` by `query-learnings` (strictest filter excludes).
- **Concurrent emit-learning with the same caller-supplied `dedup_key` is not serialized.** Two parallel calls with the same key but different content append both without auto-injecting `supersedes`, because each call's dedup-scan happens before the other's append. Acceptable given the helper's no-lock design; if strict serialization is needed, callers can wrap calls with a file lock.
