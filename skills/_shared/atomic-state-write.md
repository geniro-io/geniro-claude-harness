# atomic-state-write — procedure spec

**Helper for atomic state-file writes.** Skills source this from Bash to write `.geniro/` state files without partial-write corruption.

- **Library:** `lib/atomic-state-write.sh`
- **Schema reference:** `skills/_shared/state-tier-spec.md`
- **Design rationale:** `ARCHITECTURE.md` §State Files
- **Validator:** `skills/_shared/validate-state-file.md`

---

## When to use

| Tier / situation | Helper |
|---|---|
| T1.5 task-bound durable artifacts (`.geniro/planning/<task-dir>/{state,spec}.md`, `plan-*.md`, `milestone-*.md`) | `atomic_state_write` |
| T1.5 session-bound state (`.geniro/state/<skill>/<slug>/state.md`) | `atomic_state_write` |
| T1.5 singleton state (`.geniro/state/setup/state.md`) | `atomic_state_write` |
| T2 handoff (`.geniro/state/handoff/from-*.md`) | `atomic_state_write` |
| T3 CRUD (`instructions/*.md`, `actions/*.md`, `workflow/*.yaml`, `planning/_*.md`) | `atomic_state_write` (with caller-side mtime check — see below) |
| T3 append-only JSONL (`.geniro/knowledge/learnings.jsonl`) | `atomic_state_append` |
| T1 ephemeral transient outputs (`.kr-out.md`, `.ce-out.md`, `.tr-out.md`, `.adversarial-out.md`, `notes.md`, `playwright-verify.png`) | Plain `Write` — no frontmatter, no atomicity requirement, deleted at Ship |
| Reading state — no helper needed | use `Read` tool directly |

**Do not** use the built-in `Write` or `Edit` tools on `.geniro/` state paths. The `enforce-state-helper.sh` PreToolUse hook warns on direct writes (and will hard-block once block-mode is enabled).

---

## API

### `atomic_state_write <target>`

Reads content from stdin, writes atomically via `tmp + fsync + rename + fsync-dir`.

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"

atomic_state_write ".geniro/planning/dark-mode/state.md" <<'EOF'
---
tier: T1.5
producer: implement
schema-version: 1
branch: feature/dark-mode
timestamp: 2026-05-19T14:30:00Z
phase: implement
status: in-progress
non-resumable-actions: []
---

## Phase log
- analyze done at 14:25:00Z
EOF
```

**Exit codes:**

| Code | Meaning |
|---|---|
| 0 | Success |
| 64 | Target path missing (caller error) |
| 65 | `mkdir -p` of parent directory failed |
| 66 | Writing tmp file failed (disk full, permissions) |
| 67 | Atomic rename failed |

**Side effects:**
- Creates parent directory if missing.
- Uses tmp filename `<target>.tmp.<pid>.<hostname>` to avoid NFS collisions.
- Cleans up tmp on failure.

### `atomic_state_append <target>`

Reads one line from stdin, appends with POSIX `O_APPEND` semantics.

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"

printf '%s' '{"ts":"2026-05-19T14:30:00Z","producer":"implement","scope":"feature/dark-mode","summary":"Use CSS variables not styled-components","tags":["css","ui"],"trust":"verified","dedup_key":"abc123def456"}' \
  | atomic_state_append ".geniro/knowledge/learnings.jsonl"
```

**Constraints:**
- Line length ≤ 4096 bytes (POSIX `PIPE_BUF` atomicity guarantee).
- One line per invocation. Multi-line appends must call repeatedly.

**Exit codes:**

| Code | Meaning |
|---|---|
| 0 | Success |
| 64 | Target path missing |
| 65 | `mkdir -p` failed |
| 68 | Line exceeds 4096 bytes |
| 69 | Append failed |

---

## Caller-side mtime check (T3 CRUD only)

For T3 CRUD files (`instructions/*.md`, `actions/*.md`, etc.), the caller is responsible for optimistic-concurrency mtime check **before** invoking `atomic_state_write`.

**Important:** GNU `stat -c %Y` is Linux-only. BSD/macOS `stat` uses `-f %m`. Without a portable wrapper, the check silently no-ops on macOS (both `stat -c` calls error → both fallback to `echo 0` → values always equal → check disabled). Use this portable helper:

```bash
# Portable file-mtime — works on Linux (GNU coreutils) and macOS/BSD.
_get_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

# At read time:
initial_mtime=$(_get_mtime "$target")

# ... user edits content ...

# At write time:
current_mtime=$(_get_mtime "$target")
if [ ! -e "$target" ]; then
  # Initial write — target didn't exist at read time AND doesn't now.
  # No prior state to conflict with; proceed.
  :
elif [ -z "$initial_mtime" ] || [ -z "$current_mtime" ]; then
  # File exists but stat failed at read time and/or write time. Could be a
  # permission flip, transient FS error, or signal mid-call. Treat as
  # conflict — never silently disable the check. Open AUQ.
  exit 1
elif [ "$current_mtime" != "$initial_mtime" ]; then
  # File changed since read — open AUQ:
  #   - Overwrite (lose remote changes)
  #   - Show diff
  #   - Abort
  exit 1
fi

atomic_state_write "$target" <<EOF
...
EOF
```

T1 and T2 paths are path-scoped (slug / branch) and don't need the check; same-branch parallel writes are rare/abusive and last-writer-wins is acceptable.

## Known limitations

- **Symlinks are replaced, not followed.** The internal `mv tmp target` follows POSIX rename semantics — if `target` is a symlink, the symlink itself is replaced with a regular file (the linked-to file becomes orphaned with its old content). Don't symlink state files. If you need shared state between worktrees, share the `.geniro/` directory itself, not individual files inside it.

- **Append race on no-newline files can produce a blank line.** When two concurrent `atomic_state_append` calls both find a target file missing its trailing newline, both prepend `\n` independently. The POSIX `O_APPEND` write atomicity is preserved (no torn line), but the result is one harmless blank line in JSONL. `jq -cs` and `query-learnings` tolerate it; `wc -l` and strict line-number-based diagnostics over-count by 1. Acceptable for now — a single appender doesn't trigger it, and the first append after the race "heals" the file (subsequent appends see the trailing newline).

---

## What this helper does NOT do

- **No frontmatter validation.** Callers must produce valid frontmatter per `state-tier-spec.md`. Use `validate_state_file` after the write if validation is desired.
- **No locking.** T1 path-scoping and T3 mtime check are the concurrency model. No `flock`, no `.lock` files.
- **No rollback / backup.** Atomicity guarantees no partial writes; recovery is via skill re-run (T1/T2) or `git checkout` (T3 user content).
- **No retry on transient errors.** Caller decides.

---

## Why per-write atomic (Q2)

From the audit (M1 §Verification):
- Audit problem #1 — no atomic writes — root cause: direct `Edit`/`Write` calls truncate-and-rewrite, leaving a window where reader sees half-written file.
- Fix: every state path goes through this helper. `tmp + fsync + rename + fsync-dir` guarantees either pre- or post-state, never partial.

The PreToolUse hook `enforce-state-helper.sh` (warn-mode initially, block-mode after migration completes) catches sites that bypass the helper.

---

## Portability notes (§Open Q2 in M1 design)

- `sync -d <file>` works on Linux (GNU coreutils). macOS `sync` has no `-d` flag.
- Helper probes `sync -d` per-call; on failure falls back to whole-disk `sync`. Slower on macOS but portable.

## NFS safety (§Open Q3 in M1 design)

- Tmp filename includes `$$` (PID) and `${HOSTNAME}`. Same-host PID collisions don't happen; cross-host shared `.geniro/` directories (rare) are safe because PID space + hostname is unique.

---

## Bypass — power users

Add `enforce-state-helper` to `.geniro/safety.json` `allow_patterns` to silence the warning hook for the current project:

```json
{
  "allow_patterns": ["enforce-state-helper"]
}
```

Note: this only silences the hook; it does NOT make direct `Edit`/`Write` safe. Use only if you understand the atomicity trade-off.
