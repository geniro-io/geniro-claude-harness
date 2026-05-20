# validate-state-file — procedure spec

**Helper for state-file frontmatter validation.** Skills source this from Bash before resume / after recovery to verify a state file is well-formed.

- **Library:** `skills/_shared/validate-state-file.sh`
- **Schema reference:** `skills/_shared/state-tier-spec.md`
- **Design rationale:** `architecture/M1-state-files.md` §Validation helper
- **Write helper:** `skills/_shared/atomic-state-write.md`

---

## When to call

| Situation | Why |
|---|---|
| Skill resume after compaction (SessionStart hook re-enters task) | Verify state.md survived intact before continuing |
| Task-dir handoff (M5 → M4: `/plan` writes `spec.md`, `/implement` reads it) | Catch malformed handoff early — fail fast at consumer entry |
| Optional sanity check after `atomic_state_write` | Belt-and-suspenders; not required (write helper guarantees atomicity) |
| Validator unit-test (`tests/state/validate-frontmatter.sh`) | Regression coverage |

Producers do NOT need to validate the file they just wrote — the write helper guarantees the bytes hit disk atomically and the producer controls the content.

---

## API

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.sh"

if ! validate_state_file ".geniro/planning/dark-mode/state.md"; then
  rc=$?
  # Handle recovery per Q5 — open recovery AUQ.
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
| 8 | `worktree:` path not in `git worktree list` (P-M1-2) | AUQ: update worktree path / delete-and-restart |
| 9 | `tier:` value not `T1` / `T2` / `T3` | AUQ: open-in-editor |
| 64 | Caller error — no target path provided | Bug — fix caller |

---

## Validation procedure

The 7 steps validated, in order (per M1 §Validation helper):

1. **File exists** at the given path.
2. **Line 1 is `---`** — frontmatter must start at line 1, no leading content or BOM.
3. **Frontmatter is closed** with a `---` on its own line.
4. **Common-base required fields present:** `tier`, `producer`, `schema-version`, `branch`, `timestamp`. Just key-presence — values are not validated except `tier` and `schema-version`.
5. **`tier:` value is T1, T2, or T3.** Tier-specific required fields are checked:
   - T1 → `phase`, `status`, `non-resumable-actions`
   - T2 → `consumer`
   - T3 → `concurrency`
6. **`schema-version: 1`** — current supported version. Mismatch returns code 6 (caller decides whether to attempt migration).
7. **Optional checks:**
   - `checksum:` — sha256 of body matches.
   - `worktree:` — path is listed in `git worktree list --porcelain` (graceful skip when not inside a git repo).

---

## Recovery AUQ template (Q5)

When `validate_state_file` returns non-zero, the calling skill MUST open an `AskUserQuestion`:

```
Q: state.md failed validation — <error from stderr>.
   The file may be corrupt, partially written, or from an older plugin version.

Options:
  - "Delete and restart"      — Drop the state file; skill re-runs from spec.
                                Loses in-flight state.
  - "Open in editor"          — Pause skill; you fix the file manually; re-run validation.
  - "Update worktree path"    — Only if error is code 8 (worktree path stale).
  - "Skip validation (emergency)" — Continue regardless. Risk: silent corruption.
```

The exact wording is per-skill; the four options are canonical.

---

## YAML parsing strategy (§Open Q1 in M1 design)

**Shell-line only.** No `yq` dependency.

Rationale: the frontmatter schema is flat (no nested structures except optional `approvals` list and `tags` inline-list). Required-field check is just key-presence (`grep -qE "^<key>:"`). Scalar values (`tier`, `schema-version`, `checksum`, `worktree`) are extracted via `awk` line-strip.

The `approvals:` array is checked only for key-presence (caller-side concern to parse the list structure when consuming it).

---

## What this helper does NOT do

- **No deep YAML validation.** Malformed YAML inside `approvals:` block won't be caught.
- **No semantic validation.** `producer: foo` is accepted regardless of whether `foo` is a real skill.
- **No body schema check.** Body is free-form per per-skill conventions; `## Section` headers not enforced.
- **No auto-repair.** Recovery is always user-driven via AUQ.
- **No JSONL line validation.** JSONL files (`learnings.jsonl`) use line-by-line validation elsewhere — the JSONL itself has no frontmatter; the tier metadata lives in the sidecar `<file>.meta.yaml`.

---

## Sidecar files for JSONL

`learnings.jsonl` has no frontmatter (it's pure JSONL). The canonical tier metadata lives in `<file>.meta.yaml` which IS validatable:

```yaml
---
tier: T3
producer: implement
schema-version: 1
branch: main
timestamp: 2026-05-19T14:30:00Z
concurrency: append-only
schema-ref: "M2 §5.1 (canonical L2 entry schema)"
---
```

Call `validate_state_file` on the sidecar; the JSONL itself uses line-by-line parsing in the consumer (`query-learnings.sh`).
