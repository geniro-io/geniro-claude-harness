# atomic-state-write — procedure spec

## Contents

- §When to use — tier → helper table
- §API — `atomic_state_write` / `atomic_state_append` signatures + exit codes
- §Timestamp sourcing — time-bearing fields come from a live clock read
- §Read-modify-write — changing a field in an existing state file
- §Caller-side mtime check — optimistic-concurrency for T3 CRUD files
- §Known limitations — symlinks, append race
- §What this helper does NOT do — validation, locking, rollback, retry
- §Portability notes — Linux vs macOS sync
- §NFS safety — tmp-filename uniqueness
- §Bypass — power-user allowlist opt-out

**Helper for atomic state-file writes.** Skills source this from Bash to write `.geniro/` state files without partial-write corruption.

- **Library:** `lib/atomic-state-write.sh`
- **Schema reference:** `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md`
- **Design rationale:** `ARCHITECTURE.md` §State Files
- **Validator:** `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md`

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
| T1 ephemeral transient outputs (canonical list: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T1 — e.g. `.kr-out.md`, `.research-*.md`, `ui-verify.png`) | Plain `Write` — no frontmatter, no atomicity requirement, deleted at the owning run's terminal exit |
| Reading state — no helper needed | use `Read` tool directly |

**Do not** use the built-in `Write` or `Edit` tools on `.geniro/` state paths. The `enforce-state-helper.sh` PreToolUse hook hard-blocks those (exit 2). A shell-side write is *not* blocked — the hook does not match `Bash` — but it carries the identical corruption risk, so route it through the helper anyway.

---

## API

### `atomic_state_write <target>`

Reads content from stdin, writes atomically via `tmp + fsync + rename + fsync-dir`, guaranteeing either the pre- or post-write state — never a partial file.

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
- Content length ≤ `GENIRO_APPEND_MAX_BYTES` (single-sourced in `lib/atomic-state-write.sh`); the 2 reserved bytes are the newline framing, so content + framing stays within the PIPE_BUF ceiling that constant is derived from. POSIX `PIPE_BUF` atomicity is platform-dependent — 4096 bytes on Linux but only 512 on macOS — so do not rely on a raw pipe writing a single line near the boundary atomically.
- One line per invocation. Multi-line appends must call repeatedly.

**Empty stdin is a deliberate no-op** — the same guard `atomic_state_write` documents above, so a failed upstream pipe can never inject a blank line into the JSONL log.

**Exit codes:**

| Code | Meaning |
|---|---|
| 0 | Success |
| 64 | Target path missing |
| 65 | `mkdir -p` failed |
| 68 | Content exceeds `GENIRO_APPEND_MAX_BYTES` (content + 2-byte newline framing would exceed it) |
| 69 | Append failed |

---

## Timestamp sourcing

Every `timestamp:` / `completed-at:` / time-bearing field comes from a live clock read (`date -u +%Y-%m-%dT%H:%M:%SZ`) captured in the same Bash call that writes — never a copied example literal, a remembered value, or a rounded estimate. The literal timestamps elsewhere in this doc (and in `state-tier-spec.md`'s examples) are illustrative; an unquoted heredoc as shown in §API interpolates the live read at write time, which is why that example uses `$(date -u ...)` rather than a frozen string. These fields order decisions across rounds and compactions, and the restore hook renders `completed-at` when warning about already-fired external actions — an invented time corrupts exactly the audit trail the field exists to provide.

---

## Read-modify-write

Changing one field in an existing state file is still a whole-file write through the helper: read the current content, transform it, pipe the result in. The transform prints to stdout and never touches the target.

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"
S=".geniro/planning/<task-dir>/state.md"

python3 - "$S" <<'PY' | atomic_state_write "$S"
import sys
b = open(sys.argv[1]).read()
b = b.replace("phase: validate", "phase: user-approve", 1)
sys.stdout.write(b)
PY
```

**A field the transform leaves alone is re-written at its old value.** The whole-file write means state cannot drift, and equally cannot advance on its own: a `phase:` or `status:` that a step is meant to move forward moves only inside a write that moves it, so a body-only edit carries the previous value forward silently. That result validates clean — `validate_state_file` checks the field is present and non-empty, never that it agrees with the body — and stays invisible until a resume routes on it. When a write is the one meant to advance such a field, read the frontmatter back afterwards and quote the value it now holds before telling the user where the run stands.

Editing the file in place instead — `sed -i`, an interpreter's `open(p,'w')`, an `Edit` call — is the truncate-and-rewrite this helper exists to replace, and it stays unsafe when a later `atomic_state_write` re-writes the result: by then the unprotected write already happened, so the helper copies damage rather than preventing it. No hook catches the in-place shape: `enforce-state-helper.sh` reads `file_path` and does not inspect shell commands, so this one rests on the caller.

When a step genuinely needs the new content staged on disk before the write, name the temp file with `mktemp`. A fixed path is shared by every session on the machine, so two concurrent runs stage into the same file and one writes the other's state into its own:

```bash
tmp=$(mktemp) && trap 'rm -f "$tmp"' EXIT
render_new_content > "$tmp"
atomic_state_write "$S" < "$tmp"
```

---

## Caller-side mtime check (T3 CRUD only)

For T3 CRUD files (`instructions/*.md`, `actions/*.md`, etc.), the caller is responsible for optimistic-concurrency mtime check **before** invoking `atomic_state_write`.

Compute mtime with a portable stat (GNU `stat -c %Y`, falling back to BSD/macOS `stat -f %m` — without the fallback the check silently no-ops on macOS), once at read time and again just before the write. Three outcomes: the target still doesn't exist at either time — no prior state to conflict with, proceed; `stat` failed at either time — treat as a conflict rather than silently disabling the check; the mtime changed since read — open an `AskUserQuestion` with three options: Overwrite (lose remote changes), Show diff, Abort.

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
