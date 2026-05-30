# Verification Cache

Authoritative cache-invalidation rules for build/lint/test PASS results carried across phases. Consumers: `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-4-3-test-gate-reference.md` (independent re-run gate), `${CLAUDE_PLUGIN_ROOT}/skills/review/incoming-mode-reference.md` (PR-comment re-run), `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` (cross-phase PASS carry).

This file is the single source of truth for cache invalidation. Skills cite this file; do NOT inline-paste the rules.

## What is cached

When a sub-agent reports PASS for the project's `<build_cmd> && <lint_cmd> && <test_cmd>` triad (via a `## Checks Report` section or equivalent structured artifact), the orchestrator MAY cache the result and skip re-running for the next phase — IF AND ONLY IF every invalidation rule below holds. The cache is a pre-mutation snapshot of green CI, not a time-bounded "recently passed" marker.

Cache record fields (minimum):

- `command_triad`: verbatim build/lint/test commands as run.
- `commit_sha`: `git rev-parse HEAD` at cache-write.
- `worktree_dirty_at_write`: `git status --porcelain | wc -l` at cache-write (must be the post-agent state).
- `mtime_ceiling`: timestamp of the latest `Edit`/`Write` observed before cache-write.
- `reporting_agent_exit`: clean / non-clean.

## Invalidation rules

The cache MUST be discarded and the triad re-run when any of the following hold:

- Any `Edit`, `Write`, or external file modification happened between cache-write and cache-read. The orchestrator detects this by tracking its own tool calls and by re-reading `git status --porcelain` / file mtimes against `mtime_ceiling` before honoring the cache.
- The cache is older than the current phase boundary's intent. Cross-phase carry is allowed only when no mutation has happened since cache-write; a phase-boundary crossing alone does NOT invalidate, but any mutation inside the new phase does.
- A different commit SHA is checked out (`git rev-parse HEAD` differs from `commit_sha`). Worktree changes invalidate unconditionally — including reverts, rebases, and branch switches.
- The reporting agent's exit was non-clean (timeout, partial output, hook abort). Orchestrators NEVER cache inferred-PASS from partial outputs — absence of FAIL is not PASS.
- The `command_triad` differs from what the next phase needs (e.g., Phase 5 cached `pnpm test --run` but Phase 6 requires `pnpm test --run --coverage`). Different commands = different cache key.

When invalidated, the orchestrator re-runs the full triad and writes a fresh cache record; the stale record is discarded, never partially honored.

## Atomic write & single-writer

Only the orchestrator writes the cache; sub-agents NEVER write to the cache file directly. Sub-agents emit `## Checks Report` sections in their output; the orchestrator parses, validates, and writes.

Writes go through tmpfile + rename for atomicity (per GSD Pattern 5):

```bash
tmpfile="$(mktemp -p "$(dirname "$cache_path")" .cache.XXXXXX)"
printf '%s\n' "$cache_record" > "$tmpfile"
mv -f "$tmpfile" "$cache_path"
```

This guarantees a concurrent reader never sees a half-written record. Single-writer means the cache file has one writer per orchestrator run; if an orchestrator spawns parallel sub-agents that each report PASS, the orchestrator serializes the writes (or merges into a single record after all complete).

## Anti-rationalization

| Rationalization | Counter |
|---|---|
| "Phase 5 simplify reported PASS, Phase 6 can skip the re-run." | Only if no `Edit`/`Write` happened between Phase 5 reporting and Phase 6 entry. Check `mtime_ceiling` against current file mtimes before honoring. |
| "I'll trust the sub-agent's PASS report without re-checking the file mtime." | The orchestrator MUST verify the cache wasn't invalidated by a post-cache mutation. The sub-agent reports the state at its exit; the orchestrator owns the state from then on. |
| "The fixer agent only touched test files, the build cache is still valid." | Any mutation invalidates — the build/lint/test triad is atomic. Test-only edits can still break lint or compilation. Re-run the full triad. |
| "I'll cache PASS even though the agent timed out — the partial output looked clean." | Non-clean exit = no cache. Absence of FAIL in partial output is not evidence of PASS. |
| "The user committed locally between phases, but the diff is small — keep the cache." | Different `commit_sha` = invalidate unconditionally. Commit size is irrelevant; the tree changed. |

## Definition of Done

A consumer skill correctly applies the verification cache when:

- [ ] Cache-honor decisions check ALL invalidation rules (mutation-since-write, commit SHA, command triad, reporting-agent exit) before skipping the re-run.
- [ ] Cache writes are tmpfile + rename, single-writer, orchestrator-only.
- [ ] Sub-agents emit `## Checks Report` sections; they do NOT touch the cache file.
- [ ] On any invalidation, the full triad is re-run and a fresh record is written; the stale record is discarded.
- [ ] Completion claims that rely on cached PASS attach the Evidence Block from the original capture per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`, plus a one-line "cache honored — no mutation since `<commit_sha>`" note.
