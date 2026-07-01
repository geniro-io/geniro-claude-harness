# atomic-state-write — procedure spec

## Contents

- §When to use — tier → helper table
- §API — `atomic_state_write` / `atomic_state_append` signatures + exit codes
- §Timestamp sourcing — time-bearing fields come from a live clock read
- §Caller-side mtime check — optimistic-concurrency for T3 CRUD files
- §Known limitations — symlinks, append race
- §What this helper does NOT do — validation, locking, rollback, retry
- §Why per-write atomic — rationale
- §Portability notes — Linux vs macOS sync
- §NFS safety — tmp-filename uniqueness
- §Bypass — power-user allowlist opt-out

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
| T3 CRUD (`instructions/*.md`, `actions/*.md`, `workflow/*.md`, `planning/_*.md`) | `atomic_state_write` (with caller-side mtime check — see below) |
| T3 append-only JSONL (`.geniro/knowledge/learnings.jsonl`) | `atomic_state_append` |
| T1 ephemeral transient outputs (canonical list: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T1 — e.g. `.kr-out.md`, `.research-*.md`, `playwright-verify.png`) | Plain `Write` — no frontmatter, no atomicity requirement, deleted at the owning run's terminal exit |
| Reading state — no helper needed | use `Read` tool directly |

**Do not** use the built-in `Write` or `Edit` tools on `.geniro/` state paths. The `enforce-state-helper.sh` PreToolUse hook hard-blocks direct writes (exit 2), covering `Edit`/`Write`/`MultiEdit` and Bash-side writes alike.

---

## API

### `atomic_state_write <target>`

Reads content from stdin, writes atomically via `tmp + fsync + rename + fsync-dir`.

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"

atomic_state_write ".geniro/planning/dark-mode/state.md" <<EOF
---
tier: T1.5
producer: implement
schema-version: 1
branch: feature/dark-mode
timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
phase: implement
status: in-progress
non-resumable-actions: []
---

## Phase log
- analyze done
EOF
```

**Timestamp sourcing.** Every `timestamp:` / `completed-at:` / time-bearing field comes from a live clock read (`date -u +%Y-%m-%dT%H:%M:%SZ`) captured in the same Bash call that writes — never a copied example literal, a remembered value, or a rounded estimate. The literal timestamps elsewhere in this doc (and in `state-tier-spec.md`'s examples) are illustrative; an unquoted heredoc as shown above interpolates the live read at write time, which is why the example above uses `$(date -u ...)` rather than a frozen string. These fields order decisions across rounds and compactions, and the restore hook renders `completed-at` when warning about already-fired external actions — an invented time corrupts exactly the audit trail the field exists to provide.

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

**Empty stdin is a deliberate no-op.** When stdin is empty (zero bytes), the helper writes nothing, leaves `<target>` untouched, and returns 0. This guards against a failed upstream pipe (e.g. a generator that errored before producing output) silently truncating an existing state file to zero bytes. The rc=0 is indistinguishable from a successful write, so a caller that genuinely wants an empty file must `echo ""` (or `truncate -s 0 <target>`) directly rather than piping empty content through this helper.

### `atomic_state_append <target>`

Reads one line from stdin, appends with POSIX `O_APPEND` semantics.

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"

printf '%s' '{"ts":"2026-05-19T14:30:00Z","producer":"implement","scope":"feature/dark-mode","summary":"Use CSS variables not styled-components","tags":["css","ui"],"trust":"verified","dedup_key":"abc123def456"}' \
  | atomic_state_append ".geniro/knowledge/learnings.jsonl"
```

**Constraints:**
- Content length ≤ 4094 bytes (`GENIRO_APPEND_MAX_BYTES`, single-sourced in `lib/atomic-state-write.sh`); the 2 reserved bytes are the newline framing, so content + framing stays within the 4096-byte ceiling. POSIX `PIPE_BUF` atomicity is platform-dependent — 4096 bytes on Linux but only 512 on macOS — so do not rely on a raw pipe writing a single line near the boundary atomically.
- One line per invocation. Multi-line appends must call repeatedly.

**Empty stdin is a deliberate no-op.** When stdin is empty (zero bytes), the helper appends nothing, leaves `<target>` untouched, and returns 0 — the same guard `atomic_state_write` applies, so a failed upstream pipe can never inject a blank line into the JSONL log.

**Exit codes:**

| Code | Meaning |
|---|---|
| 0 | Success |
| 64 | Target path missing |
| 65 | `mkdir -p` failed |
| 68 | Content exceeds 4094 bytes (content + 2-byte framing would exceed the 4096-byte ceiling) |
| 69 | Append failed |

---

## Caller-side mtime check (T3 CRUD only)

For T3 CRUD files (`instructions/*.md`, `actions/*.md`, etc.), the caller is responsible for optimistic-concurrency mtime check **before** invoking `atomic_state_write`.

GNU `stat -c %Y` is Linux-only. BSD/macOS `stat` uses `-f %m`. Without a portable wrapper, the check silently no-ops on macOS (both `stat -c` calls error → both fallback to `echo 0` → values always equal → check disabled). Use this portable helper:

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
- **No empty-file write via empty stdin.** Empty stdin is a deliberate no-op (returns 0, leaves the target untouched) to keep a failed upstream pipe from truncating an existing state file. To write a genuinely empty file, `echo ""` or `truncate -s 0` the target directly.

---

## Why per-write atomic

- Without atomic writes, direct `Edit`/`Write` calls truncate-and-rewrite, leaving a window where reader sees half-written file.
- Fix: every state path goes through this helper. `tmp + fsync + rename + fsync-dir` guarantees either pre- or post-state, never partial.

The PreToolUse hook `enforce-state-helper.sh` (hard-block — exit 2) catches sites that bypass the helper.

---

## Portability notes

- `sync -d <file>` works on Linux (GNU coreutils). macOS `sync` has no `-d` flag.
- Helper probes `sync -d` per-call; on failure falls back to whole-disk `sync`. Slower on macOS but portable.

## NFS safety

- Tmp filename includes `$$` (PID) and `${HOSTNAME}`. Same-host PID collisions don't happen; cross-host shared `.geniro/` directories (rare) are safe because PID space + hostname is unique.

---

## Bypass — power users

Add `enforce-state-helper` to `.geniro/safety.json` `allow_patterns` to bypass the hook for the current project:

```json
{
  "allow_patterns": ["enforce-state-helper"]
}
```

This only silences the hook; it does not make direct `Edit`/`Write` safe. Use it only if you understand the atomicity trade-off.
