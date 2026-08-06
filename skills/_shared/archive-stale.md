# L2 stale-entry archival helper

**Status:** Authoritative for marking `.geniro/knowledge/learnings.jsonl` entries `deprecated: true` based on score-decay criteria. Surfaces as a user-invoked operation OR via SessionStart Block 5e notice.

## API

```bash
source lib/archive-stale.sh
archive_stale_learnings [--dry-run]
```

Or direct invocation:
```bash
./lib/archive-stale.sh [--dry-run]
```

**Exit codes:**
- `0` — success (flipped to deprecated, or dry-run completed)
- `1` — no entries match criteria (informational)
- `2` — IO error, bad flag, invalid `GENIRO_DECAY_TAU_DAYS`, or refused-to-rewrite because the log holds malformed line(s) (see §Safety invariants)
- `3` — direct invocation only: the rewrite lock is held by another process; run skipped (re-run in a moment). A caller that already owns the lock (the SessionStart hook) sets `GENIRO_ARCHIVE_LOCK_HELD=1` to skip acquisition.

**Path resolution:** `lib/repo-root.sh::_geniro_repo_root` resolves to the PRIMARY worktree, so archival mutations target the canonical L2 log, never a linked worktree's. Contract: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` § "Why this exists".

## Criteria (all must hold)

An entry becomes a stale candidate iff:

1. **Score below the staleness floor** — using the same scoring formula as `query-learnings --score-min` (canonical definition in query-learnings.md §Score formula).
2. **Age past the staleness horizon** — measured from the entry's `ts` field.
3. **access_count == 0** — entry has never been returned by a query that called `record_access`.
4. **not already deprecated** — `(.deprecated // false) == false`. Already-deprecated entries are skipped so re-runs report 0 candidates (idempotency).

The floor and the horizon are literals in `lib/archive-stale.sh`'s jq filter, stated there with the reasoning behind each; the helper echoes both in its own output (below), so read the numbers from the run rather than from this page.

The four-way AND ensures conservative bias — high-trust recent or frequently-accessed entries are protected even if individually old.

## Output

**Dry-run mode** (`--dry-run`):
```
archive-stale: 87 stale candidate(s) (dry-run — no changes written):
 diagnosis: 12
 pitfall: 8
 discovery: 31
 retry_failure_sequence: 14
 untyped: 22

Run without --dry-run to flip deprecated:true on these entries.
```

**Real run:**
```
archive-stale: flipped deprecated:true on 87 entries:
 diagnosis: 12
 pitfall: 8
 ...

All entries preserved on-disk (audit trail). Re-run safe (idempotent — already-deprecated entries skipped).
```

**No candidates** (rc=1). The real message substitutes the live §Criteria thresholds for the placeholder below, which is where to read their current values:
```
archive-stale: 0 stale candidates (no entries match <score / age / access_count thresholds>)
```

## Safety invariants

- **Never deletes.** Only flips `deprecated: true`. Entries remain on-disk for audit / future re-elevation.
- **Refuses to rewrite a corrupt log.** A real run aborts (rc=2) without writing if any line cannot be parsed as JSON, rather than silently dropping the unparseable line on the rewrite. This preserves the never-deletes guarantee even when the log is partially corrupt — fix or remove the malformed line, then re-run.
- **Auto-runs on SessionStart** when threshold met AND file changed since last archive. Manual invocation also supported (typical: `--dry-run` to preview).
- **Idempotent.** Already-deprecated entries are skipped (criterion 4 in §Criteria). Re-runs are safe and report 0 candidates.
- **Atomic write.** Uses tmp + POSIX `rename(2)` for the final write. Mid-run interruption leaves either the old or new file, never a partial one.
- **Multi-tab safe.** When invoked via hook, runs under a `mkdir`-acquired POSIX-atomic lock at `.geniro/knowledge/.archive-stale.lock`. Direct invocations acquire the same lock themselves (rc=3 when held), and `record_access` counter rewrites share it too — the hook, direct runs, and counter bumps are mutually excluded. A caller that *sources* this helper and calls `archive_stale_learnings()` directly owns locking itself (the function never auto-locks — see the header contract). Concurrent SessionStart events lose the race and skip silently; only one tab does work. A lock orphaned by a crashed process is reclaimed once its mtime exceeds the shared reclaim window (`GENIRO_LOCK_RECLAIM_SECS`, single-sourced with its rationale in `lib/lock-reclaim.sh`).

## Environment

| Variable | Default | Effect |
|---|---|---|
| `GENIRO_DECAY_TAU_DAYS` | see `lib/score-formula.sh` | Controls `recency_decay = exp(-Δdays / τ)`. Same env as `query-learnings`. Lower τ = faster decay. Default single-sourced in `lib/score-formula.sh` (`GENIRO_DECAY_TAU_DAYS_DEFAULT`) so the ranker and archiver cannot drift on it. |
| `GENIRO_AUTO_ARCHIVE_THRESHOLD` | see `hooks/session-start-restore.sh` | `learnings.jsonl` line count above which the SessionStart hook auto-invokes this helper (see §Caller conventions). |

## Caller conventions

- User runs `./lib/archive-stale.sh --dry-run` first to preview, then real run.
- SessionStart Block 5e auto-invokes `lib/archive-stale.sh` when `learnings.jsonl` exceeds the line-count threshold (`GENIRO_AUTO_ARCHIVE_THRESHOLD`, default single-sourced in `hooks/session-start-restore.sh`) AND the file hash changed since the last archive AND the mkdir-lock is acquired AND `memory.auto_archive_stale != false` in `.geniro/safety.json`. Hash-gating skips the run when nothing changed; the lock keeps concurrent tabs from doubling the work. Manual `--dry-run` is still the typical preview path.
- **Manual runs are lock-safe against a SessionStart auto-archive.** A direct `./lib/archive-stale.sh` invocation acquires the same mkdir-lock itself, so if the hook holds it the manual run no-ops with rc=3 (re-run in a moment) rather than racing a mid-write. No lost update. The only unlocked path is a caller that *sources* the helper and calls `archive_stale_learnings()` directly — that caller owns locking itself (the function never auto-locks), which is why the hook sets `GENIRO_ARCHIVE_LOCK_HELD=1` after taking the lock.
- Compatible with `query-learnings`: queries default to excluding `deprecated: true` entries; if user wants to see archived ones, pass `--include-deprecated`.

## Known limitations

- **τ is global.** Same decay parameter applied to all entries. If a domain needs different decay (e.g., security pitfalls should age slower), use the `deprecated: false` manual override.
- **No partial-restore.** Once `deprecated: true`, restoration is a manual `learnings.jsonl` edit (set to `false` or delete the field).
- **No fuzzy-match restore.** No `unarchive --pattern` helper. By design — restoration is a deliberate user action.
