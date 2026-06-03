# L2 stale-entry archival helper

## Contents

- §API — invocation + flags
- §Criteria — the conditions an entry must meet to be archived
- §Output — what the helper reports
- §Safety invariants — never deletes, audit-trail preserving
- §Environment — env-var knobs
- §Caller conventions
- §Known limitations
- §Test coverage

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

**Path resolution:** this helper uses `lib/repo-root.sh::_geniro_repo_root` to find the project root. When invoked from a linked git worktree (where `.geniro/` may exist with just `planning/`), the resolver returns the PRIMARY worktree's path so archival mutations target the canonical L2 log. See `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` § "Why this exists" for the contract.

## Criteria (all must hold)

An entry becomes a stale candidate iff:

1. **score < 0.1** — using the same scoring formula as `query-learnings --score-min` (canonical definition in query-learnings.md §Score formula).
2. **age > 180 days** — measured from entry's `ts` field.
3. **access_count == 0** — entry has never been returned by a query that called `record_access`.
4. **not already deprecated** — `(.deprecated // false) == false`. Already-deprecated entries are skipped so re-runs report 0 candidates (idempotency).

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

**No candidates** (rc=1):
```
archive-stale: 0 stale candidates (no entries match score<0.1 + age>180d + access_count==0)
```

## Safety invariants

- **Never deletes.** Only flips `deprecated: true`. Entries remain on-disk for audit / future re-elevation.
- **Refuses to rewrite a corrupt log.** A real run aborts (rc=2) without writing if any line cannot be parsed as JSON, rather than silently dropping the unparseable line on the rewrite. This preserves the never-deletes guarantee even when the log is partially corrupt — fix or remove the malformed line, then re-run.
- **Auto-runs on SessionStart** when threshold met AND file changed since last archive. Manual invocation also supported (typical: `--dry-run` to preview).
- **Idempotent.** Already-deprecated entries are skipped (criterion 4 in §Criteria). Re-runs are safe and report 0 candidates.
- **Atomic write.** Uses tmp + POSIX `rename(2)` for the final write. Mid-run interruption leaves either the old or new file, never a partial one.
- **Multi-tab safe.** When invoked via hook, runs under a `mkdir`-acquired POSIX-atomic lock at `.geniro/knowledge/.archive-stale.lock`. Concurrent SessionStart events lose the race and skip silently; only one tab does work. Stale-lock TTL = 600s (orphans from crashed processes auto-cleaned).

## Environment

| Variable | Default | Effect |
|---|---|---|
| `GENIRO_DECAY_TAU_DAYS` | 90 | Controls `recency_decay = exp(-Δdays / τ)`. Same env as `query-learnings`. Lower τ = faster decay. |

## Caller conventions

- User runs `./lib/archive-stale.sh --dry-run` first to preview, then real run.
- SessionStart Block 5e auto-invokes `lib/archive-stale.sh` when `learnings.jsonl` exceeds the line-count threshold (`GENIRO_AUTO_ARCHIVE_THRESHOLD`, default 5000) AND the file hash changed since the last archive AND the mkdir-lock is acquired AND `memory.auto_archive_stale != false` in `.geniro/safety.json`. Hash-gating skips the run when nothing changed; the lock keeps concurrent tabs from doubling the work. Manual `--dry-run` is still the typical preview path.
- **Manual runs must not overlap a SessionStart auto-archive.** The mkdir-lock is held by the hook (Block 5e); the helper itself does not self-lock. A manual run launched while a SessionStart auto-archive is mid-write races it (last writer wins). The atomic rename prevents corruption, but to avoid a lost update, run manually only when no fresh session is starting.
- Compatible with `query-learnings`: queries default to excluding `deprecated: true` entries; if user wants to see archived ones, pass `--include-deprecated`.

## Known limitations

- **τ is global.** Same decay parameter applied to all entries. If a domain needs different decay (e.g., security pitfalls should age slower), use the `deprecated: false` manual override.
- **No partial-restore.** Once `deprecated: true`, restoration is a manual `learnings.jsonl` edit (set to `false` or delete the field).
- **No fuzzy-match restore.** No `unarchive --pattern` helper. By design — restoration is a deliberate user action.

## Test coverage

Coverage to maintain for this helper (no dedicated `tests/memory/archive-stale.sh` yet):
- Dry-run identifies candidates without writing
- Real run flips `deprecated: true`
- Idempotency (re-run reports 0)
- Bad flag rejected with rc=2
- No-log-file handled gracefully (rc=1)
- Score formula correctness at age=180d boundary
- access_count>0 protects entry from candidate set
