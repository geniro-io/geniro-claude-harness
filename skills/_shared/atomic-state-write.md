# atomic-state-write — procedure spec

## Contents

- §When to use — tier → helper table
- §API — the five functions, their signatures + exit codes
- §Timestamp sourcing — time-bearing fields come from a live clock read
- §Changing part of an existing file — edit in place, don't regenerate
- §Caller-side mtime check — optimistic-concurrency for T3 CRUD files
- §Properties every helper holds — signals, concurrency, permissions
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

**Which helper — by what the write does:**

| Operation | Helper |
|---|---|
| Advance one frontmatter field (`phase:`, `status:`, `timestamp:`) in a file that already exists | `atomic_state_set_field` |
| Change a known span of body text in a file that already exists | `atomic_state_edit` |
| Write a whole file whose content a *program* produces (a transform, a serializer, a renderer) | `atomic_state_write_cmd` |
| Write a whole file whose content is written literally in the call (heredoc) | `atomic_state_write` |
| Append one JSONL record | `atomic_state_append` |
| Read state | `Read` tool directly — no helper |

**Which paths this governs:**

| Tier / path | Routing |
|---|---|
| T1.5 task-bound durable artifacts (`.geniro/planning/<task-dir>/{state,spec}.md`, `plan-*.md`, `milestone-*.md`) | Helpers above |
| T1.5 session-bound state (`.geniro/state/<skill>/<slug>/state.md`) | Helpers above |
| T1.5 singleton state (`.geniro/state/setup/state.md`) | Helpers above |
| T2 handoff (`.geniro/state/handoff/from-*.md`) | Helpers above |
| T3 CRUD (`instructions/*.md`, `actions/*.md`, `workflow/*.md`, `planning/_*.md`) | Helpers above, plus the caller-side mtime check below |
| T3 append-only JSONL (`.geniro/knowledge/learnings.jsonl`) | `atomic_state_append` only |
| T1 ephemeral transient outputs (canonical list: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T1 — e.g. `.kr-out.md`, `.research-*.md`, `notes.md`) | Plain `Write` — no frontmatter, no atomicity requirement, deleted at the owning run's terminal exit |

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
| 70 | Stdin was empty — nothing written, `<target>` untouched |

**Side effects:**
- Creates parent directory if missing.
- Stages through a `mktemp` file beside the target, named `<target>.tmp.<hostname>.<random>`.
- Cleans up tmp on failure.

**Empty stdin leaves the target alone and reports rc 70.** A failed upstream pipe (a generator that errored before producing output) must not truncate an existing state file to zero bytes — but it must not read as success either. In `producer | atomic_state_write target` the helper is the pipeline's last element, so the pipeline's rc *is* the helper's: an rc 0 here reports "state written" for a run that wrote nothing, and the step's own gate passes on it. A caller that genuinely wants an empty file uses `truncate -s 0 <target>` directly.

**This helper cannot see a producer that dies mid-stream.** A generator that emits half its output and then exits non-zero leaves `cat` a short but perfectly valid payload, which is then renamed over good state at rc 0 — atomically committed corruption. The empty-stdin guard does not catch it, because the payload is not empty. Any whole-file content produced by a program goes through `atomic_state_write_cmd`, which runs the producer itself and can read its exit status. Reserve `atomic_state_write` for content written literally in the call (a heredoc), where there is no producer to fail.

### `atomic_state_write_cmd <target> <command> [args...]`

Runs the producer, captures its stdout, and commits **only if it exits 0**.

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"

atomic_state_write_cmd ".geniro/planning/dark-mode/spec.md" \
  python3 "$RENDERER" --task dark-mode
```

The command is exec'd directly, not through a shell — for a pipeline or a redirect, pass `bash -c '<pipeline>'`.

**Exit codes:** as `atomic_state_write` (0 / 64 / 65 / 66 / 67 / 70), plus:

| Code | Meaning |
|---|---|
| 75 | Producer exited non-zero — nothing written, `<target>` untouched (its rc is on stderr) |

### `atomic_state_edit <target> <old_text> <new_text>`

Replaces one **literal** occurrence of `<old_text>` and commits the result through the same tmp + fsync + rename path. No regex, no glob, no shell escaping to get wrong: `*`, `?` and `[` in the anchor are compared as bytes.

`<old_text>` must match exactly once. Zero matches and more than one are both errors that change nothing — the helper never guesses which occurrence was meant.

```bash
atomic_state_edit ".geniro/state/handoff/from-review-main.md" \
  "- [ ] Null deref in parseConfig" \
  "- [x] Null deref in parseConfig"
```

| Code | Meaning |
|---|---|
| 0 | Success |
| 64 | Target path or `<old_text>` missing (an empty anchor matches everywhere) |
| 66 / 67 | As `atomic_state_write` |
| 71 | `<old_text>` not found — nothing changed |
| 72 | `<old_text>` matched more than once — pass a longer, unique anchor |
| 73 | Target does not exist, is unreadable, or contains a `0x04` byte (the helper's record separator) |
| 76 | The file declares `checksum:` and the edit falls below the frontmatter, which would leave that seal stale |

Occurrences are counted **non-overlapping**, the same way a replace is defined: in `aaa`, the anchor `aa` is one occurrence, not two.

### `atomic_state_set_field <target> <field> <value>`

Sets `<field>: <value>` inside the **leading `---` frontmatter block only** — a same-named line in the body is never touched. The field must already exist: a state file's schema comes from `state-tier-spec.md`, and inventing a key here would let a typo pass for a set.

```bash
atomic_state_set_field ".geniro/planning/dark-mode/state.md" phase user-approve
atomic_state_set_field ".geniro/planning/dark-mode/state.md" timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

| Code | Meaning |
|---|---|
| 0 | Success |
| 64 | Target path or field name missing; the value argument omitted (pass `""` to set an empty value); or the value spans more than one line, which would put a bare continuation line inside the `---` block |
| 66 / 67 | As `atomic_state_write` |
| 73 | Target does not exist or is unreadable |
| 74 | No closed leading `---` block, or the field is not in it — nothing changed |

### `atomic_state_append <target>`

Reads stdin and appends it as one record with POSIX `O_APPEND` semantics.

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"

printf '%s' '{"ts":"2026-05-19T14:30:00Z","producer":"implement","scope":"feature/dark-mode","summary":"Use CSS variables not styled-components","tags":["css","ui"],"trust":"verified","dedup_key":"abc123def456"}' \
  | atomic_state_append ".geniro/knowledge/learnings.jsonl"
```

**Constraints:**
- Content length ≤ `GENIRO_APPEND_MAX_BYTES` (single-sourced in `lib/atomic-state-write.sh`); the 2 reserved bytes are the newline framing, so content + framing stays within the PIPE_BUF ceiling that constant is derived from. POSIX `PIPE_BUF` atomicity is platform-dependent — 4096 bytes on Linux but only 512 on macOS — so do not rely on a raw pipe writing a single line near the boundary atomically.
- One record per invocation. The record may span several lines as long as it stays under the byte ceiling; the append is what must be atomic, not each line.

**Empty stdin appends nothing and reports rc 70** — the same contract `atomic_state_write` documents above. A failed upstream pipe can never inject a blank line into the JSONL log, and, just as important, can never report a learning as recorded when the serializer emitted nothing.

**Exit codes:**

| Code | Meaning |
|---|---|
| 0 | Success |
| 64 | Target path missing |
| 65 | `mkdir -p` failed |
| 68 | Content exceeds `GENIRO_APPEND_MAX_BYTES` (content + 2-byte newline framing would exceed it) |
| 69 | Append failed |
| 70 | Stdin was empty — nothing appended |

---

## Timestamp sourcing

Every `timestamp:` / `completed-at:` / time-bearing field comes from a live clock read (`date -u +%Y-%m-%dT%H:%M:%SZ`) captured in the same Bash call that writes — never a copied example literal, a remembered value, or a rounded estimate. The literal timestamps elsewhere in this doc (and in `state-tier-spec.md`'s examples) are illustrative; an unquoted heredoc as shown in §API interpolates the live read at write time, which is why that example uses `$(date -u ...)` rather than a frozen string. These fields order decisions across rounds and compactions, and the restore hook renders `completed-at` when warning about already-fired external actions — an invented time corrupts exactly the audit trail the field exists to provide.

---

## Changing part of an existing file

Change the bytes you mean and leave the rest alone — `atomic_state_set_field` for a frontmatter field, `atomic_state_edit` for a span of body text. Both go through the same tmp + fsync + rename commit, so an in-place edit is exactly as atomic as a whole-file write.

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"
S=".geniro/planning/<task-dir>/state.md"

atomic_state_set_field "$S" phase user-approve
atomic_state_set_field "$S" timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

**Regenerating the whole file to change one field re-writes every other field at its old value.** That is the failure this section exists to prevent: a `phase:` or `status:` a step was meant to advance moves only inside a write that moves it, so a regeneration driven by a body edit carries the previous value forward silently. The result validates clean — `validate_state_file` checks a field is present and non-empty, never that it agrees with the body — and stays invisible until a resume routes on the stale value. A scoped set cannot produce it: the untouched fields are never rewritten at all.

The escape hatch is a genuine whole-file regeneration — a renderer producing the file from scratch, a migration rewriting its whole shape. Route those through `atomic_state_write_cmd` so a producer that dies mid-render cannot commit a half-file over good state.

Editing in place by other means — `sed -i`, an interpreter's `open(p,'w')`, an `Edit` call — is the truncate-and-rewrite this helper exists to replace, and it stays unsafe when a later `atomic_state_write` re-writes the result: by then the unprotected write already happened, so the helper copies damage rather than preventing it. No hook catches the shell-side shape: `enforce-state-helper.sh` reads `file_path` and does not inspect shell commands, so this one rests on the caller.

---

## Caller-side mtime check (T3 CRUD only)

For T3 CRUD files (`instructions/*.md`, `actions/*.md`, etc.), the caller is responsible for an optimistic-concurrency mtime check **before** invoking any of the write helpers — the editors read-then-write like the whole-file writers and lose a concurrent update the same way.

Compute mtime with a portable stat (GNU `stat -c %Y`, falling back to BSD/macOS `stat -f %m` — without the fallback the check silently no-ops on macOS), once at read time and again just before the write. Three outcomes: the target still doesn't exist at either time — no prior state to conflict with, proceed; `stat` failed at either time — treat as a conflict rather than silently disabling the check; the mtime changed since read — open an `AskUserQuestion` with three options: Overwrite (lose remote changes), Show diff, Abort.

T1 and T2 paths are path-scoped (slug / branch) and don't need the check; same-branch parallel writes are rare/abusive and last-writer-wins is acceptable.

## Properties every helper holds

- **Signals belong to the caller.** Each public function does its work in a subshell, so the trap that removes a half-written tmp file cannot replace a trap the caller installed, and a signal arriving mid-write does not override the caller's own handler or exit code.
- **Concurrent calls get distinct tmp files.** Names come from `mktemp`, not from `$$` — inside a subshell `$$` is the parent shell's pid, so two backgrounded writers to one target once shared a tmp path and could splice their payloads into one committed file. Distinct tmp files reduce that to last-writer-wins, which is the documented concurrency model.
- **Permissions are carried across a rewrite.** A state file deliberately restricted to `0600` stays `0600`; a new file gets the mode a plain `>` redirection would have produced.
- **A directory in the target's place is refused** (rc 67) rather than silently receiving the tmp file, which `mv` would otherwise do while reporting success.

## Known limitations

- **Symlinks are replaced, not followed.** The internal `mv tmp target` follows POSIX rename semantics — if `target` is a symlink, the symlink itself is replaced with a regular file (the linked-to file becomes orphaned with its old content). Don't symlink state files. If you need shared state between worktrees, share the `.geniro/` directory itself, not individual files inside it.

- **Append race on no-newline files can produce a blank line.** When two concurrent `atomic_state_append` calls both find a target file missing its trailing newline, both prepend `\n` independently. The POSIX `O_APPEND` write atomicity is preserved (no torn line), but the result is one harmless blank line in JSONL. `jq -cs` and `query-learnings` tolerate it; `wc -l` and strict line-number-based diagnostics over-count by 1. Acceptable for now — a single appender doesn't trigger it, and the first append after the race "heals" the file (subsequent appends see the trailing newline).

---

## What this helper does NOT do

- **No frontmatter validation on the whole-file writers.** `atomic_state_write` / `atomic_state_write_cmd` take whatever content they are given; produce valid frontmatter per `state-tier-spec.md` and run `validate_state_file` after the write if validation is desired. `atomic_state_set_field` is the exception: it requires a closed leading `---` block and a pre-existing field, and fails rc 74 rather than inventing either.
- **No locking.** T1 path-scoping and T3 mtime check are the concurrency model. No `flock`, no `.lock` files.
- **No rollback / backup.** Atomicity guarantees no partial writes; recovery is via skill re-run (T1/T2) or `git checkout` (T3 user content).
- **No retry on transient errors.** Caller decides.

---

## Portability notes

- `sync -d <file>` fsyncs one file on Linux (GNU coreutils). BSD/macOS `sync` takes no options and ignores every operand, returning 0 either way — so an rc-based probe reads macOS as "per-file sync succeeded". The helper discriminates on `sync --help` naming `--data` instead, and falls back to whole-disk `sync`.
- **Where there is no per-file sync, the helper syncs nothing.** The former whole-disk fallback cost 164 ms per write and flushed every mounted filesystem on the machine while buying nothing: macOS `sync(2)` schedules the flush rather than waiting for it. Atomicity — the rename — never depended on it and holds on every platform; durability across power loss is Linux-only in practice. Nothing in the state model depends on surviving a power cut.

## NFS safety

- The tmp filename carries the hostname plus `mktemp` randomness. A PID would not have been enough: inside a subshell `$$` is the parent shell's, so same-host concurrent writers collided. The hostname covers the cross-host case on a shared `.geniro/`; zsh does not set `HOSTNAME`, so the helper falls back to `HOST` and then to `hostname`.

---

## Bypass — power users

Add `enforce-state-helper` to `.geniro/safety.json` `allow_patterns` to bypass the hook for the current project:

```json
{
  "allow_patterns": ["enforce-state-helper"]
}
```

This only silences the hook; it does not make direct `Edit`/`Write` safe. Use it only if you understand the atomicity trade-off.
