# L2 legacy-entry schema-migration helper

**Status:** Authoritative for one-time auto-migration of pre-M2 / non-canonical entries in `.geniro/knowledge/learnings.jsonl`. Invoked by `/geniro:setup` re-run migration sweep via the MIGRATION.md `Auto-fix:` mechanism.

**Spec source:** `architecture/M2-memory-layers.md` §5.1 (canonical schema) and `MIGRATION.md` v2.5.0 entry «`learnings.jsonl` legacy-entry schema migration».

## API

```bash
source lib/migrate-learnings.sh
migrate_legacy_learnings [--dry-run]
```

Or direct invocation:
```bash
./lib/migrate-learnings.sh [--dry-run]
```

**Exit codes:**
- `0` — success (rewrote N entries, or dry-run completed)
- `1` — no `learnings.jsonl` present OR all entries already canonical (informational)
- `2` — IO error (jq failed, tmp-write failed, rename failed, bad flag)

## What counts as legacy

An entry is "legacy / needs migration" iff it lacks ANY of the 4 required M2 §5.1 fields. Predicate (jq):

```
select(.producer == null or .scope == null or .summary == null or (.tags | type) != "array")
```

If `legacy_count == 0` после а cheap pre-scan, the helper returns rc=1 immediately (no rewrite, no rename).

## Synthesis rules

Applied per-entry when the legacy predicate matches:

| Field | Rule |
|---|---|
| `producer` | use existing if present; else `"/geniro:setup"` |
| `scope` | use existing if present; else `"global"` |
| `summary` | use existing `.summary`; else `.title` truncated к 240 chars; else `"<legacy entry without summary>"` |
| `tags` | if present and array, keep. Else `["legacy-migrated"]` plus non-empty `.category` and `.type` legacy fields (deduped). Always non-empty. |
| `ts` | use existing if present; else current UTC ISO-8601 |
| `type` | use existing if present; else map `.category`: `pattern → discovery`, `gotcha → diagnosis`, `anti-pattern → pitfall`, `investigation-methodology → discovery`, anything else → `discovery` |
| `trust` | use existing if present; else `"inferred"` |
| `dedup_key` | use existing if present; else `sha256(producer\|scope\|normalize(summary))[:12]` where `normalize` = lowercase + whitespace-collapse + trim |
| `migrated_from_legacy` | always set к `true` on migrated entries (marker for future tooling) |

**Legacy fields preserved:** `id`, `category`, original `title`, original `type` (if remapped), and any other open-schema additions are NOT stripped. M2 §5.1 schema is open.

## Atomicity & safety

- **Atomic write.** Per-line transform streams к `${log}.tmp.$$`, then `mv` performs а POSIX `rename(2)` (atomic on same filesystem). Mid-run interruption leaves either the old или the new file, never а partial one.
- **No `.bak` files.** Atomic rename IS the safety. Re-running с the same input is а no-op (idempotency gate).
- **Cheap idempotency.** Pre-scan counts legacy lines via а single jq pass; if zero, returns rc=1 без touching the file.
- **No file-lock.** `/geniro:setup` runs as а singleton — no parallel runs — so the state-file singleton serves as the lock. Direct invocation outside `/setup` is the user's responsibility.

## Opt-out

Set in `.geniro/safety.json`:

```json
{
  "memory": {
    "auto_migrate_learnings": false
  }
}
```

When opted out, the MIGRATION.md sweep's `Auto-fix:` short-circuits before invoking the helper. Manual direct invocation still runs unconditionally — the opt-out is enforced at the caller level (the MIGRATION.md `Auto-fix:` block), not inside the helper.

## Known limitations

- **4096-byte truncation skip.** If а migrated line exceeds 4096 bytes, the helper preserves the original legacy line unchanged and increments а `truncated_skipped` counter. The user sees «Skipped K entries (>4096 bytes after migration; legacy unchanged)» в the stderr summary.
- **JSON-syntax-error lines.** Malformed lines that jq cannot parse are preserved verbatim with no counter bump (silent skip). Run `jq -c . learnings.jsonl >/dev/null` separately to surface them.
- **Dedup-key collisions.** SHA-256[:12] collisions are extremely unlikely (~1 in 2^48), but если duplicate dedup_keys appear после migration, re-running `archive-stale` will not deduplicate them — that helper only flips `deprecated:true` on score-decay criteria. Manual review required for hash-clash repair.
- **No multi-tab lock.** Relies on `/setup`'s singleton state-file. If invoked manually concurrently с another writer (e.g. `emit-learning` от а parallel skill), the last `mv` wins. Avoid manual concurrent invocation.
- **Sanitization scope.** `redact_secrets` runs only on the synthesized `summary` field. Legacy on-disk fields (`.title`, `.id`, `.category`, `.type`, и any other open-schema additions) are preserved verbatim and NOT sanitized — they may still contain secrets from pre-M2 entries. Users с known secret-bearing legacy entries should audit `learnings.jsonl` separately.

## Example output

**Dry-run mode** (`--dry-run`):
```
migrate-learnings: 12 legacy entries would be migrated (dry-run — no changes written):
  pattern → discovery: 5
  gotcha → diagnosis: 2
  anti-pattern → pitfall: 1
  (untyped): 4

Run without --dry-run к rewrite legacy entries к canonical schema.
```

**Real run:**
```
migrate-learnings: rewrote 12 legacy entries to canonical schema:
  pattern → discovery: 5
  gotcha → diagnosis: 2
  anti-pattern → pitfall: 1
  (untyped): 4
All synthesized via /geniro:setup; legacy fields preserved on-disk.
```

**With truncation skips:**
```
migrate-learnings: rewrote 10 legacy entries to canonical schema:
  pattern → discovery: 5
  gotcha → diagnosis: 2
  ...
All synthesized via /geniro:setup; legacy fields preserved on-disk.
Skipped 2 entries (>4096 bytes after migration; legacy unchanged).
```

**No-op** (rc=1):
```
migrate-learnings: all entries already canonical (no-op)
```
