# validate-state-file — procedure spec

**Helper for state-file frontmatter validation.** Skills source this from Bash before resume / after recovery to verify a state file is well-formed.

- **Library:** `lib/validate-state-file.sh`
- **Schema reference:** `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md`
- **Design rationale:** `ARCHITECTURE.md` §State Files
- **Write helper:** `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md`

---

## When to call

| Situation | Why |
|---|---|
| Skill resume after compaction (SessionStart hook re-enters task) | Verify state.md survived intact before continuing |
| Task-dir handoff (`/geniro:plan` writes `spec.md`, `/geniro:implement` reads it) | Catch malformed handoff early — fail fast at consumer entry |
| Optional sanity check after `atomic_state_write` | Belt-and-suspenders; not required (write helper guarantees atomicity) |
| Validator unit-test (`tests/state/validate-frontmatter.sh`) | Regression coverage |

Producers do NOT need to validate the file they just wrote — the write helper guarantees the bytes hit disk atomically and the producer controls the content.

---

## API

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/validate-state-file.sh"

# Capture rc directly — inside `if ! cmd` the special var $? holds the negated
# test status (always 0), so per-exit-code routing must read rc from the call.
validate_state_file ".geniro/planning/dark-mode/state.md"; rc=$?
if [ "$rc" -ne 0 ]; then
  # Handle recovery per the Recovery AUQ template (route on $rc) — open recovery AUQ.
  ...
fi
```

### Exit codes

| Code | Meaning | Recovery action |
|---|---|---|
| 0 | Valid | Proceed |
| 1 | File does not exist | Skill rebuild — call producer from scratch |
| 2 | Line 1 is not `---` (no frontmatter at all) | AUQ: delete-and-restart / open-in-editor |
| 3 | No closing `---` found | Same as above |
| 4 | Missing common-base required field (`tier`, `producer`, `schema-version`, `branch`, `timestamp`) | AUQ — same |
| 5 | Missing tier-specific required field | AUQ — same |
| 6 | `schema-version` mismatch (file from older plugin version) | AUQ: migrate / delete-and-restart |
| 7 | Body checksum mismatch | Manual-edit corruption — AUQ: revert / accept |
| 8 | `worktree:` path not in `git worktree list` | AUQ: update worktree path / delete-and-restart |
| 9 | `tier:` value not `T1` / `T1.5` / `T2` / `T3` | AUQ: open-in-editor |
| 64 | Caller error — no target path provided | Bug — fix caller |

---

## Validation procedure

The 7 steps validated, in order:

1. **File exists** at the given path.
2. **Line 1 is `---`** — frontmatter must start at line 1, no leading content or BOM.
3. **Frontmatter is closed** with a `---` on its own line.
4. **Common-base required fields present AND non-empty:** `tier`, `producer`, `schema-version`, `branch`, `timestamp`. Each must carry a non-empty scalar value — a bare `producer:` (key present, value empty) fails with code 4. `tier` and `schema-version` are additionally enum/value-checked in steps 5-6.
5. **`tier:` value is T1, T1.5, T2, or T3.** Tier-specific required fields are checked:
   - T1 → `phase`, `status`, `non-resumable-actions`
   - T1.5 → `phase`, `status`, `non-resumable-actions` (same shape as T1; differs in lifecycle — T1.5 survives Phase Ship)
   - T2 → `consumer`, `open_questions` (key-presence; MAY be empty `[]`)
   - T3 → `concurrency`
6. **`schema-version: 1`** — current supported version. Mismatch returns code 6 (caller decides whether to attempt migration).
7. **Optional checks:**
   - `checksum:` — sha256 of body matches.
   - `worktree:` — path is listed in `git worktree list --porcelain` (graceful skip when not inside a git repo).

---

## Recovery AUQ template

When `validate_state_file` returns non-zero, the calling skill must open an `AskUserQuestion`:

```
Q: state.md failed validation — <error from stderr>.
   The file may be corrupt, partially written, or from an older plugin version.

Options:
  - "Delete and restart"      — Drop the state file; skill re-runs from spec.
                                Loses in-flight state.
  - "Open in editor"          — Pause skill; you fix the file manually; re-run validation.
  - "Update worktree path"    — Only when the saved worktree path is stale (the worktree no longer exists at that location).
  - "Skip validation (emergency)" — Continue regardless. Risk: silent corruption.
```

The exact wording is per-skill; the four options are canonical.

---

## YAML parsing strategy

**Shell-line only.** No `yq` dependency.

Rationale: the frontmatter schema is flat (no nested structures except optional `approvals` list and `tags` inline-list). Common-base required scalar fields are checked for presence AND a non-empty value (extract via `awk` line-strip, then test for non-empty); block-list fields whose inline value may be empty (e.g. `non-resumable-actions:`) are checked for key-presence only (`grep -qE "^<key>:"`). Scalar values (`tier`, `schema-version`, `checksum`, `worktree`) are extracted via `awk` line-strip.

The `approvals:` array is checked only for key-presence (caller-side concern to parse the list structure when consuming it).

---

## What this helper does NOT do

- **No deep YAML validation.** Malformed YAML inside `approvals:` block won't be caught.
- **No semantic validation.** `producer: foo` is accepted regardless of whether `foo` is a real skill.
- **No body schema check.** Body is free-form per per-skill conventions; `## Section` headers not enforced.
- **No auto-repair.** Recovery is always user-driven via AUQ.
- **No JSONL line validation.** JSONL files (`learnings.jsonl`) use line-by-line validation elsewhere — the JSONL itself has no frontmatter. An optional `<file>.meta.yaml` sidecar convention exists for carrying tier metadata, but no helper currently emits or reads it (canonical shape: `state-tier-spec.md` §T3 append-only); `emit-learning.sh` / `query-learnings.sh` operate directly on the JSONL.

