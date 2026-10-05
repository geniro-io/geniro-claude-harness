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

The canonical L2 entry schema is documented in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` § "T3 — append-only (learnings sidecar)".

## API

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh"
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
- `70` — nothing was recorded because the entry came back empty: either stdin was empty, or the serialized line was. The caller contract echoes "Recorded learning:" on rc 0, so this path must not report success.

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

**On overflow, flip the oldest matching entry's `deprecated: true` BEFORE appending the new one.** That mutates an existing line in `.geniro/knowledge/learnings.jsonl`, which the append-only helper does not do — rewrite the file per the JSONL locked-rewrite exception in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` §When to use, never a direct `Edit`/`Write` (those truncate and rewrite in place, so a crash mid-write leaves a partial log). Prune before appending: appending first leaves the window over-full for any reader that queries in between.

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
- `dedup_key` — auto-computed as `sha256(producer|scope|normalize(summary))[:12]` if absent (`normalize` = lowercase + whitespace collapse + trim), so callers can reproduce it to look an entry up later.
- `body`, `ext`, `links` — free text; every string inside is redacted per §Sanitization.
- `supersedes` — preserved verbatim if the caller provides it; otherwise the helper may auto-inject it (see §Dedup pipeline).
- `recurrence_count` — defaults to `1` on a fresh emit; on a dedup match with different content the helper carries the prior entry's value forward and adds 1. Callers leave it unset. The helper does not echo the result — re-query with `source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh" && query_learnings --include-superseded`, filtered by `dedup_key`. Absent on legacy entries; `query-learnings` treats absent as `1`.
- `type`, `trust`, `deprecated` — passed through unchanged.

Unknown fields are also passed through — the schema is open.

## Sanitization

The helper calls `redact_secrets` on `summary`, `body`, and every other string value in the entry at any depth and in any container — `ext`, `links` (a credential-bearing URL must not land unredacted), `tags[]` elements, and any caller-added key. Audit-log path labels use dotted notation (e.g. `ext.options.0`). The control-plane identifiers — `producer`, `scope`, `type`, `trust`, `ts`, `dedup_key`, `supersedes` — are excluded: they hold no secrets, and sanitizing them would corrupt structure the helper relies on.

## Injection rejection

L2 entries are re-loaded into orchestrator and subagent context by `query-learnings`, so a learning auto-emitted from untrusted text (a fetched page, a PR body, peer-PR content) could replay a prompt-injection payload into a later session. The read side is defended by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/untrusted-content-defense.md`; this helper closes the **write** side.

Before redaction and dedup, `emit_learning` scans every string value in the entry and rejects it with `rc=64` on either of two high-signal shapes:

- **Override phrasing** — `<verb> <previous-reference> <instruction-noun>`, e.g. "ignore previous instructions", "disregard the above context", "new directives:".
- **Chat-template control tokens** — `<|im_start|>`, `<|system|>`, `</system>`, etc.

The pattern set is deliberately narrow: a false reject drops one best-effort learning (the caller surfaces the non-zero return per §Caller contract rule 3 and does not block), whereas a stored payload persists across sessions. If a legitimate learning needs one of these phrases, rephrase it.

## Dedup pipeline

1. Compute or accept `dedup_key`.
2. Scan the last `GENIRO_DEDUP_WINDOW` lines of the log (§Known limitations) for the **last** prior entry with that key — the head of the supersede chain.
3. Compare prior vs new with `ts`, `recurrence_count`, and `supersedes` excluded (canonicalized `jq -cS 'del(.ts, .recurrence_count, .supersedes)'`). All three are derived per-write fields; comparing them would make every re-emit look different, defeating the no-op return and inflating `recurrence_count`.
4. Decide:
 - **Equal** → no-op, rc 0.
 - **Different**, caller did NOT set `supersedes` → inject `supersedes: <dedup_key>`, set `recurrence_count` to prior + 1, append.
 - **Different**, caller set `supersedes` → keep the caller's value, set `recurrence_count` to prior + 1, append.
 - **No prior match** → append fresh with `recurrence_count: 1`.

The counter rides the supersede chain (absent counts as `1`), so a first re-emit lands at `2`, then `3`. `query-learnings` folds it into its score as a dampened multiplier.

## Per-line byte ceiling

A JSONL line over the append helper's ceiling aborts with rc=68 rather than risk a torn write; the value (`GENIRO_APPEND_MAX_BYTES`) is canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` §`atomic_state_append <target>`. The ceiling bounds line length but is not an atomicity guarantee — `PIPE_BUF` is 4096 on Linux and only 512 on macOS (see that file's §Known limitations). Keep `body` short (≤ ~3.5KB), use `links` for full PRs/commits instead of inlining diffs, and put large content in a separate file referenced by `scope`.

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

- **Dedup window is bounded by `GENIRO_DEDUP_WINDOW`** (default single-sourced in `lib/emit-learning.sh`). Older near-duplicates re-append as fresh entries. If the window proves too short, set it wider or have callers pre-query via `query-learnings` and pass `supersedes` explicitly.
- **No multi-entry batching.** One JSON object per call; loop for many.
- **Sanitization is per-call.** A pattern firing across several fields emits several audit-log rows.
- **No producer→trust auto-default.** Each caller supplies `trust` at its emit site (e.g. `/geniro:debug` emits confirmed root causes as `verified`); a missing `trust` is treated as `inferred` by `query-learnings`.
- **Concurrent emits with the same caller-supplied `dedup_key` are not serialized.** Two parallel calls with different content both append without auto-injecting `supersedes`, because each dedup-scan runs before the other's append. Wrap calls in a file lock if strict serialization is needed.
