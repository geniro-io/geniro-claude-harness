# L3 semantic-memory write helper

**Status:** Authoritative for bounded auto-incremental writes to `_CODEBASE_MAP.md` and `_FEATURES.md`. Used by `/geniro:implement` (adds module entries), `/geniro:refactor` (move/rename), `/geniro:plan` (manages `_FEATURES.md`), and `/geniro:onboard` (writes its whole `_CODEBASE_MAP.md` through this helper).

## API

```bash
source lib/update-semantic.sh

# Append a fresh line
update_semantic --file <codebase-map|features> --append "<line>"

# Replace the first line whose content starts with a prefix
update_semantic --file <codebase-map|features> --replace "<prefix>" "<new-line>"
```

**Path resolution:** `lib/repo-root.sh::_geniro_repo_root` resolves to the PRIMARY worktree, so `_CODEBASE_MAP.md` / `_FEATURES.md` mutations land in the canonical store, never a linked worktree's. Contract: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` § "Why this exists".

Exit codes:
- `0` — wrote (or no-op, e.g. replace with no match — surfaced via stderr).
- `11` — lock held by another writer; caller should defer or retry.
- `64` — bad / missing flags.
- `68` — append content exceeds the append helper's per-call byte ceiling (`GENIRO_APPEND_MAX_BYTES`, single-sourced in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` §`atomic_state_append <target>`).
- `69` — append IO failure.
- `70` — the content for the write was never produced: `awk` failed during `--replace`, or an `--append` line came back empty (propagated from `atomic_state_append`). Distinct from a clean no-match, which is rc=0.
- `65` — could not create the parent directory (propagated from `atomic_state_append`).
- `71` — atomic write of replacement failed (also returned if `mktemp` fails while staging a `--replace`).

## MODE contract

**No MODE parameter, compaction-immune** — each invocation is a one-shot file mutation holding no
context-resident state, so re-invoking after a SessionStart event is always safe.

## Constraints

- **Applies only to `_CODEBASE_MAP.md` and `_FEATURES.md`.** Other L3 files (`_project.md`, `_architecture.md`, `_focus-*.md`) are manual-only.
- **Append or single-line replacement.** Never rewrites the whole file. One `--append` may carry several lines (up to the per-call byte ceiling, rc=68 past it), so a caller composing a whole section appends it as one block rather than line by line. Human edits anywhere in the file survive untouched.
- **Format is the caller's responsibility.** Helper accepts any string as the line. Spec recommends `- <path> — <short description>, used by <consumer>` but the helper does not enforce that — keeping format-policing out of the I/O layer lets callers compose.
- **Lock-guarded.** Each target has its own lock: `.geniro/planning/.codebase-map.lock` for codebase-map, `.geniro/planning/.features.lock` for features. Concurrent writers see rc=11 and decide whether to retry or defer until skill completion.

## Lock semantics

- **Acquire:** `(set -C; :>lock_path) 2>/dev/null` — POSIX-portable O_EXCL create. The shell with `noclobber` set refuses to write to an existing file.
- **Release:** a `trap 'rm -f "$lock_path"; trap - RETURN' RETURN` installed inside the helper fires on every return path and then uninstalls itself — bash RETURN traps are not function-scoped by default, so without the self-clear it would linger in the caller's shell and clobber a caller's own RETURN trap (the explicit `rm -f` on the success path is a belt-and-braces duplicate). An INT/TERM trap removes the lock (and any in-flight `mktemp`) on interrupt, so a Ctrl-C mid-write no longer wedges the next call at rc=11. The only residual leak is a hard SIGKILL or a crash, which skips every trap — and that leak self-heals: before acquiring, the helper reclaims a lock whose mtime is older than the reclaim window (`GENIRO_LOCK_RECLAIM_SECS` — the shared knob every lock site reclaims by, single-sourced with its rationale in `lib/lock-reclaim.sh`), then retries the O_EXCL create.
- **Different files have independent locks.** A `_CODEBASE_MAP.md` write does not block a `_FEATURES.md` write.

## Replace semantics

- **Match by line-prefix.** The first line in the target file whose content starts (`index($0, p) == 1`) with the given prefix string is replaced wholesale with the new line. Subsequent matches are not touched.
- **No-match is a no-op.** Helper returns 0 and emits a stderr notice. This is deliberate — replace is "tell me about this entry if it exists" semantics; failing on absence would force callers to pre-check.
- **Missing file is also a no-op.** Same reasoning.
- **`--replace` commits with its own `mktemp` + `mv -f`, not `atomic_state_write`.** The helper installs a process-global INT/TERM trap that would clobber this function's lock trap, so the rename is open-coded; the fsync-of-parent-directory step is traded away with it. On a partial write the original file still survives — the rename is atomic either way.

## Examples

```bash
# /geniro:implement records a new module
update_semantic --file codebase-map \
 --append "- src/components/Toggle.tsx — controlled toggle widget, used by SettingsPage"

# /geniro:refactor moves a file
update_semantic --file codebase-map \
 --replace "- src/old/legacy.ts" "- src/new/legacy.ts — moved during 2026-Q2 cleanup, used by App.tsx"

# /geniro:plan records a new feature
update_semantic --file features \
 --append "- [feat-12] Dark mode toggle, scope: ui, status: pending"
```

## Caller patterns: handling rc=11

The expected pattern is **defer-and-retry-at-skill-end**: rc=11 means the lock is held, not that the write failed, so queue the call and drain the queue at skill completion rather than dropping the write. Argument boundaries must survive the deferral — a multi-word `--append` / `--replace` value has to replay as ONE argument, never re-split into several.

For high-concurrency contention scenarios, callers can implement bounded retry with backoff — but typically L3 writes are once-per-skill-phase, and contention is rare.

## Known limitations

- **Stale-lock recovery is time-bounded, not manual.** A SIGKILL/crash leaves the lock file, but the next writer auto-reclaims it once its mtime exceeds the reclaim window (`GENIRO_LOCK_RECLAIM_SECS`, per `lib/lock-reclaim.sh`). The leak is therefore limited to a lock younger than that window.
- **One call, one atomic unit.** An append carries as much as fits under the byte ceiling; past it the caller splits into further calls.
- **Replace is first-match only.** If the target file has multiple lines matching the prefix, only the first is rewritten. This is the intended guarantee — single-line replacement, no mass rewrites — not a bug.
