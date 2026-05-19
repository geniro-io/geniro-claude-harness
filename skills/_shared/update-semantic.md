# L3 semantic-memory write helper

**Status:** Authoritative for bounded auto-incremental writes to `_CODEBASE_MAP.md` and `_FEATURES.md`. Used by `/implement` (adds module entries), `/refactor` (move/rename), and `/plan` (manages `_FEATURES.md`).

**Spec source:** `architecture/M2-memory-layers.md` §6.3 (bounded auto-incremental writes).

## API

```bash
source skills/_shared/update-semantic.sh

# Append a fresh line
update_semantic --file <codebase-map|features> --append "<line>"

# Replace the first line whose content starts with a prefix
update_semantic --file <codebase-map|features> --replace "<prefix>" "<new-line>"
```

Exit codes:
- `0` — wrote (or no-op, e.g. replace with no match — surfaced via stderr).
- `11` — lock held by another writer; caller should defer or retry.
- `64` — bad / missing flags.
- `70` — append failed (filesystem / IO).
- `71` — atomic write of replacement failed.

## MODE contract (M3 §7.4)

Write-side helper — **no MODE parameter, compaction-immune.** Each
invocation is а one-shot file mutation; the helper holds no context-resident
state across calls. Skill flow decides when to re-invoke after а SessionStart
event.

## Constraints (from M2 §6.3)

- **Applies only to `_CODEBASE_MAP.md` and `_FEATURES.md`.** Other L3 files (`_project.md`, `_architecture.md`, `_focus-*.md`) are manual-only.
- **Append-only or single-line replacement.** Never rewrites the whole file. Human edits anywhere in the file survive untouched.
- **Format is the caller's responsibility.** Helper accepts any string as the line. Spec recommends `- <path> — <short description>, used by <consumer>` but the helper does not enforce that — keeping format-policing out of the I/O layer lets callers compose.
- **Lock-guarded.** Each target has its own lock: `.geniro/planning/.codebase-map.lock` for codebase-map, `.geniro/planning/.features.lock` for features. Concurrent writers see rc=11 and decide whether to retry or defer until skill completion.

## Lock semantics

- **Acquire:** `(set -C; :>lock_path) 2>/dev/null` — POSIX-portable O_EXCL create. The shell with `noclobber` set refuses to write to an existing file.
- **Release:** explicit `rm -f` on success/error paths inside the helper. The function does NOT install a signal trap — if the process is killed mid-write the lock leaks and a stale lock will surface as rc=11 on the next call. **Manual recovery:** delete the lock file. Documented as a known limitation; future PRs may add a stale-lock heuristic (lock-file age + PID check).
- **Different files have independent locks.** A `_CODEBASE_MAP.md` write does not block a `_FEATURES.md` write.

## Replace semantics

- **Match by line-prefix.** The first line in the target file whose content starts (`index($0, p) == 1`) with the given prefix string is replaced wholesale with the new line. Subsequent matches are not touched.
- **No-match is a no-op.** Helper returns 0 and emits a stderr notice. This is deliberate — replace is "tell me about this entry if it exists" semantics; failing on absence would force callers to pre-check.
- **Missing file is also a no-op.** Same reasoning.
- **The atomic rename uses `atomic_state_write`** (M1). On a partial-write / power-loss the original file survives.

## Examples

```bash
# /implement records a new module
update_semantic --file codebase-map \
  --append "- src/components/Toggle.tsx — controlled toggle widget, used by SettingsPage"

# /refactor moves a file
update_semantic --file codebase-map \
  --replace "- src/old/legacy.ts" "- src/new/legacy.ts — moved during 2026-Q2 cleanup, used by App.tsx"

# /plan records a new feature
update_semantic --file features \
  --append "- [feat-12] Dark mode toggle, scope: ui, status: pending"
```

## Caller patterns: handling rc=11

The expected pattern is **defer-and-retry-at-skill-end**:

```bash
deferred_writes=()
attempt_update() {
  update_semantic "$@"
  if [ $? -eq 11 ]; then
    deferred_writes+=("$*")
  fi
}

# At skill completion, drain the queue
for w in "${deferred_writes[@]}"; do
  # eval ok here because args are skill-controlled
  eval "update_semantic $w"
done
```

For high-concurrency contention scenarios, callers can implement bounded retry with backoff — but typically L3 writes are once-per-skill-phase, and contention is rare.

## Known limitations

- **Stale-lock recovery is manual.** A killed writer leaves the lock file. Future enhancement: stale-lock detection via age + PID.
- **No batch ops.** One line per call. Callers needing multiple writes loop.
- **Replace is first-match only.** If the target file has multiple lines matching the prefix, only the first is rewritten. Acceptable per the spec's "single-line replacement; no mass rewrites" guarantee.

## Test coverage

`tests/memory/update-semantic.sh` exercises append (to missing file + existing file), replace (matching + non-matching + missing file), all flag-validation failures (rc=64), lock contention (rc=11), and per-file independent locks.
