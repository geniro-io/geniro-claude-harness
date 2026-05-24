# L2 stale-entry archival helper (P-X8-4)

**Status:** Authoritative for marking `.geniro/knowledge/learnings.jsonl` entries `deprecated: true` based on score-decay criteria. Surfaces as а user-invoked operation OR via M3 SessionStart Block 5e notice.

**Spec source:** `architecture/P-X8-self-learning-extensions.md` §4.3.

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
- `0` — success (flipped к deprecated, or dry-run completed)
- `1` — no entries match criteria (informational)
- `2` — IO error / bad flag

## Criteria (ALL three must hold)

An entry becomes а stale candidate iff:

1. **score < 0.1** — using the same scoring formula as `query-learnings --score-min`:
   ```
   score = recency_decay × trust_weight × access_weight
   ```
2. **age > 180 days** — measured от entry's `ts` field.
3. **access_count == 0** — entry has never been returned by а query that called `record_access`.

AND the entry is not-already-deprecated.

The triple-AND ensures conservative bias — high-trust recent OR frequently-accessed entries are protected even if individually old.

## Output

**Dry-run mode** (`--dry-run`):
```
archive-stale: 87 stale candidate(s) (dry-run — no changes written):
  diagnosis: 12
  pitfall: 8
  discovery: 31
  retry_failure_sequence: 14
  untyped: 22

Run without --dry-run к flip deprecated:true on these entries.
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
- **Auto-runs on SessionStart** when threshold met AND file changed since last archive (M3 hook Block 5e — default ON; opt-out via `.geniro/safety.json memory.auto_archive_stale: false`). Manual invocation also supported (typical: `--dry-run` к preview).
- **Idempotent.** Already-deprecated entries are skipped (criterion 0). Re-runs are safe and report 0 candidates.
- **Atomic write.** Uses tmp + POSIX `rename(2)` for the final write. Mid-run interruption leaves either the old or new file, never а partial one.
- **Multi-tab safe.** When invoked via M3 hook, runs under а `mkdir`-acquired POSIX-atomic lock at `.geniro/knowledge/.archive-stale.lock`. Concurrent SessionStart events lose the race и skip silently; only one tab does work. Stale-lock TTL = 600s (orphans от crashed processes auto-cleaned).

## Environment

| Variable | Default | Effect |
|---|---|---|
| `GENIRO_DECAY_TAU_DAYS` | 90 | Controls `recency_decay = exp(-Δdays / τ)`. Same env as `query-learnings`. Lower τ = faster decay. |

## Caller conventions

- User runs `./lib/archive-stale.sh --dry-run` first к preview, then real run.
- M3 SessionStart Block 5e surfaces а notice when `wc -l learnings.jsonl > 5000`, prompting the user к check via dry-run. The hook itself never invokes archive-stale (would add latency к а hot path).
- Compatible с `query-learnings`: queries default к excluding `deprecated: true` entries; if user wants к see archived ones, pass `--include-deprecated`.

## Known limitations

- **τ is global.** Same decay parameter applied к all entries. If а domain needs different decay (e.g., security pitfalls should age slower), use the `deprecated: false` manual override.
- **No partial-restore.** Once `deprecated: true`, restoration is а manual `learnings.jsonl` edit (set к `false` or delete the field).
- **No fuzzy-match restore.** No `unarchive --pattern` helper. By design — restoration is а deliberate user action.

## Test coverage

`tests/memory/archive-stale.sh` exercises:
- Dry-run identifies candidates без writing
- Real run flips `deprecated: true`
- Idempotency (re-run reports 0)
- Bad flag rejected с rc=2
- No-log-file handled gracefully (rc=1)
- Score formula correctness at age=180d boundary
- access_count>0 protects entry от candidate set
