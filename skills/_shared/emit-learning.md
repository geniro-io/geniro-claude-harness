# L2 episodic-memory write helper

**Status:** Authoritative for every append to `.geniro/knowledge/learnings.jsonl`.

 and (lifecycle).

## API

```bash
source lib/emit-learning.sh
echo '<json-object>' | emit_learning
```

- **Input:** a single JSON object on stdin (one entry per call).
- **Output:** none on success. JSONL line is appended to the log file.
- **Side effects:**
 - Appends to `.geniro/knowledge/learnings.jsonl` (created if absent).
 - May append to `.geniro/knowledge/.redaction-log.jsonl` (via `redact_secrets`).

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
- `type`, `trust`, `links`, `deprecated` — passed through unchanged.

Unknown fields are also passed through — the schema is open.1.

## Sanitization

The helper calls `redact_secrets` on:
- `summary`
- `body` (if present)
- Every string-valued path inside `ext` (recursive — handles nested objects and arrays)

Top-level non-string fields, `tags`, `producer`, `scope`, etc. are NOT sanitized — they are assumed to be control-plane metadata where secrets shouldn't appear and where sanitization would corrupt structure.

## Dedup pipeline

1. Compute or accept `dedup_key`.
2. `tail -n 200` of the log file (cheap — covers the recency window where dups appear).
3. Find the **last** prior entry with matching `dedup_key` (handles supersede chains correctly — we compare against the head of the chain).
4. Compare prior vs new excluding `ts` via `jq -cS 'del(.ts)'` (canonicalized).
5. Decisions:
 - **Equal** → no-op return 0.
 - **Different** + caller did NOT set `supersedes` → auto-inject `supersedes: <dedup_key>`, append.
 - **Different** + caller set `supersedes` → preserve caller's value, append.
6. **No prior match** → append fresh.

## 4096-byte limit

A single JSONL line must fit in `PIPE_BUF` for POSIX `>>` to be atomic. If the line exceeds 4096 bytes, the helper aborts with rc=68 rather than risk torn writes. In practice this means: keep `body` short (≤ ~3.5KB), use `links` for full PRs/commits instead of inlining diffs, and put truly large content into a separate file referenced by `scope`.

## Example callers

```bash
# /debug auto-emit after CONFIRMED + fix applied
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
# /plan recording an architectural decision
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

- **Dedup window is 200 lines.** Older near-duplicates re-append as fresh entries. With typical L2 write volume (a few per `/debug` session, a few per `/implement` run) the 200-line window covers weeks; if it becomes too short, callers can pre-query `learnings.jsonl` via `query-learnings` (next helper) and pass `supersedes` explicitly.
- **No multi-entry batching.** One JSON object per call. Callers that need to emit many at once should loop.
- **Sanitization is per-call.** A pattern that fires across multiple ext fields emits multiple audit-log rows. Aggregating is left to readers of the audit log.
- **No producer→trust auto-default.** .3 documents per-emitter trust defaults (e.g. `/geniro:debug` → `verified`). The helper does NOT auto-set `trust` based on producer; callers must supply it explicitly. Skills will set the right value when they integrate; meanwhile a missing `trust` is treated as `inferred` by `query-learnings` (strictest filter excludes).
- **Concurrent emit-learning with the same caller-supplied `dedup_key` is not serialized.** Two parallel calls with the same key but different content append both without auto-injecting `supersedes`, because each call's dedup-scan happens before the other's append. Acceptable given the helper's no-lock design; if strict serialization is needed, callers can wrap calls with a file lock.

## Test coverage

`tests/memory/emit-learning.sh` exercises the required-fields contract, auto-injected ts and dedup_key, caller-supplied dedup_key, sanitization of summary / body / ext / nested-ext, the dedup pipeline (no-op vs supersede), oversized rejection, and invalid-JSON rejection.
