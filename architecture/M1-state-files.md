# M1 — State-Files Framework Design

**Status:** design approved (Q1–Q8 answered). Ready for execution.
**Parent index:** `/root/.claude/plans/reactive-dreaming-backus.md`
**Next milestone:** M2 — Memory & knowledge layers (after M1 execution OR before, your call).

---

## Approved decisions (Q1–Q8)

| # | Decision | Summary |
|---|---|---|
| **Q1** | 3 tiers + sub-attribute on T3 | T1 TASK / T2 HANDOFF / T3 PERSISTENT; T3 declares `concurrency: append-only \| crud` |
| **Q2** | Per-write atomic | Every write to any state path uses `atomic_state_write` helper (tmp + fsync + rename + fsync-dir). Enforced by PreToolUse hook. |
| **Q3** | No backup | Rely on atomic writes (Q2) + git history (T3) + skill-rerun regenerability (T1/T2). No `.bak`, no rolling buffer. |
| **Q4** | Tiered-rich frontmatter | Common base required everywhere; tier-specific required fields. Per-tier schema defined below. |
| **Q5** | Hard-fail with recovery AUQ | Validation failure prints error + opens AUQ (delete-and-restart / open-in-editor / skip-emergency). JSONL files use line-skip. |
| **Q6** | Tier-specific concurrency | T1: slug-scoped paths (+ truncation hash). T2: branch-scoped paths. T3 append-only: POSIX O_APPEND + fsync. T3 CRUD: optimistic mtime check. No locks anywhere. |
| **Q7** | Skeleton-then-skills migration | PR-0 infra (helper + hook warn-mode + validators) → one PR per skill → final PR flips hook to block-mode. |
| **Q8** | Optional open-standard fields | Q4 schema is required source-of-truth; `description:` and `tags:` are optional everywhere, encouraged on T3 user-CRUD files. |

---

## Architecture overview

Every state file in `.geniro/` lands in exactly one of three tiers, determined by its path:

```
.geniro/
├── planning/                         # T1 + T3 mixed (see note below)
│   ├── <task-dir>/                   # T1 — TASK (deleted at Phase Ship)
│   │   ├── spec.md
│   │   ├── plan.md
│   │   ├── state.md
│   │   ├── notes.md
│   │   ├── concerns.md
│   │   └── milestone-N.md
│   ├── _FEATURES.md                  # T3 — PERSISTENT (renamed with _ prefix for visual distinction)
│   ├── _CODEBASE_MAP.md              # T3 — PERSISTENT
│   └── _focus-<area>.md              # T3 — PERSISTENT (user-authored area deep-dives)
├── state/
│   └── handoff/                      # T2 — HANDOFF (overwritten on next produce)
│       ├── from-debug-<branch>.md
│       ├── from-review-<branch>.md
│       └── tdd-<branch>.md
├── knowledge/                        # T3 — PERSISTENT (append-only)
│   └── learnings.jsonl
├── instructions/                     # T3 — PERSISTENT (CRUD)
│   ├── global.md
│   ├── code-style.md
│   ├── <skill>.md
│   └── review-extra/
│       └── <slug>.md
├── actions/                          # T3 — PERSISTENT (CRUD)
│   └── <slug>.md
└── workflow/                         # T3 — PERSISTENT (CRUD)
    └── *.yaml
```

**Note on planning/:** the `_`-prefix on registry files (`_FEATURES.md`, `_CODEBASE_MAP.md`, `_focus-*.md`) gives users a visual cue that these are persistent-global, vs the task-dirs which are ephemeral. Validators enforce tier-by-frontmatter, not path-prefix; the `_` is purely cosmetic for human readers.

---

## The three tiers — full specifications

### T1 — TASK

**Purpose:** ephemeral state owned by ONE skill run; deleted at Ship.

**Path root:** `.geniro/planning/<task-dir>/` (cwd-relative; intentional — task is local to worktree).

**Lifecycle:** created at skill Phase 0 (or first state-write); deleted at Phase Ship by the skill that created it. If skill aborts, files remain — next invocation prompts user to resume or delete.

**Worktree routing:** **cwd-relative**. T1 lives where the work is happening. Worktrees get teardown'd together with their T1 files.

**Concurrency:** path-scoped via `<task-dir>` (slug-derived from branch). Different branches → different task-dirs → no collision. Same branch + same worktree + two `/implement` runs in parallel is rare/abusive; if it happens, the second run detects existing task-dir and AUQs.

**Required frontmatter:**

```yaml
---
tier: T1
producer: <skill-name>      # e.g. "implement", "debug"
schema-version: 1
branch: <git-branch>         # source-of-truth at write time
timestamp: <ISO-8601 UTC>
phase: <current-phase-name>  # e.g. "Phase 3 - Implement"
status: <in-progress|done|failed>
non-resumable-actions: []    # list of completed side-effects (commits pushed, PRs posted)
---
```

**Optional frontmatter:** `description`, `tags`, `worktree`, `notes`.

**Body schema:** unstructured; per-skill conventions.

**Slug rule (audit problem #8 fix):**
```bash
slug=$(git branch --show-current | tr '[:upper:]' '[:lower:]' | sed 's#[^a-z0-9]\+#-#g')
if [ "${#slug}" -gt 60 ]; then
  slug="$(echo "$slug" | head -c 52)-$(echo "$slug" | sha256sum | head -c 8)"
fi
```
Truncation+hash prevents two long-branch-name slugs from collapsing to the same 60-char prefix.

---

### T2 — HANDOFF

**Purpose:** inter-skill data hand-off. Producer skill writes; consumer skill reads; producer overwrites on next run.

**Path root:** `.geniro/state/handoff/`.

**Naming convention:** `from-<producer>-<branch>.md` — branch-scoped to eliminate cross-branch collision (audit problem #6 partial-mitigation).

**Lifecycle:**
- Created by producer at end of its main phases (debug Step 6.5a, review Phase 5).
- Read by consumer at its Phase 1 (e.g., `/implement`).
- **Overwritten** by producer on next run (same branch).
- Not auto-deleted — last produce remains as audit trail until next overwrite.

**Worktree routing:** **primary-worktree** via existing `primary-worktree.md` Mode A resolver. Handoff is between skills within one project; living in primary keeps it visible to all worktrees.

**Concurrency:** branch-scoping makes parallel producers on different branches non-conflicting. Two producers on the same branch is rare; if it occurs, last-writer-wins (acceptable — same-branch parallel debug is abusive).

**Required frontmatter:**

```yaml
---
tier: T2
producer: <skill-name>
schema-version: 1
branch: <git-branch>
timestamp: <ISO-8601 UTC>
consumer: <skill-or-pipe-separated-list>   # post-redesign typically just "implement"
---
```

**Optional frontmatter:** `description`, `tags`, `severity-summary`, `[POSTED-TO-PR]` audit tags.

**Body schema:** producer-defined; consumer parses by `## Section` headers.

---

### T3 — PERSISTENT

**Purpose:** cross-session knowledge & user content. Never auto-deleted.

**Path roots:**
- `.geniro/knowledge/` — append-only knowledge corpus.
- `.geniro/instructions/` — user-authored rule sets.
- `.geniro/actions/` — user-authored workflow actions.
- `.geniro/workflow/` — integration config.
- `.geniro/planning/_FEATURES.md`, `_CODEBASE_MAP.md`, `_focus-*.md` — global registries.

**Lifecycle:** never auto-deleted. Edited via CRUD operations (user, or learnings auto-append). Recovered via `git checkout` if corrupted.

**Worktree routing:** **primary-worktree** always (these files belong to the project, not the working branch).

**Concurrency sub-attribute:** `concurrency: append-only | crud` declared in frontmatter.

#### T3 append-only

**Files:** `.geniro/knowledge/learnings.jsonl`.

**Format:** JSONL (one JSON object per line; ≤ 4KB per line to fit POSIX atomic append).

**Write mechanism:** `printf '%s\n' "$json_line" >> file` with `O_APPEND` flag (shell's `>>` provides this). Single-line ≤ 4KB writes are atomic by kernel guarantee. No lock.

**Dedup (audit problem #4):** each entry includes a `content-hash:` field (SHA-256 of normalized summary text). Consumers (knowledge-retrieval-agent) skip duplicates by hash. Writers may pre-check by `grep` to avoid double-append within a single skill run.

**JSONL line schema:**

```json
{
  "content-hash": "sha256-hex...",
  "tags": ["debug", "react", "useEffect"],
  "source-skill": "debug",
  "source-branch": "bugfix-toggle-flicker",
  "created-at": "2026-05-16T15:00:00Z",
  "summary": "Stale closure in useEffect cleanup caused...",
  "evidence": "src/Toggle.tsx:34"
}
```

#### T3 CRUD

**Files:** `.geniro/instructions/**`, `.geniro/actions/**`, `.geniro/workflow/**`, `.geniro/planning/_*.md`, `.geniro/-state.json` (plugin metadata).

**Write mechanism:** `atomic_state_write` helper (tmp + fsync + rename + fsync-dir).

**Concurrency:** optimistic. Helper records mtime at read; checks before write. On mtime mismatch → AUQ:
- **Overwrite** (lose remote changes — user accepts)
- **Show diff** (display remote-vs-local diff; user resolves manually)
- **Abort** (cancel write; user retries after re-reading)

**Required frontmatter (in addition to common base):**

```yaml
---
tier: T3
producer: <skill-or-user>
schema-version: 1
concurrency: append-only|crud
---
```

JSONL has no frontmatter — schema lives in a sidecar `<file>.meta.yaml` declaring `tier`, `producer`, `schema-version`, `concurrency: append-only`, and the JSON-line schema reference.

---

## Frontmatter contract (consolidated)

**Common base — required on every state file:**
| Field | Type | Example |
|---|---|---|
| `tier` | enum: T1\|T2\|T3 | `T1` |
| `producer` | string | `implement` |
| `schema-version` | integer | `1` |
| `branch` | string | `feature/dark-mode` |
| `timestamp` | ISO-8601 UTC | `2026-05-16T14:30:00Z` |

**Tier-specific required:**
| Tier | Additional required fields |
|---|---|
| T1 | `phase`, `status`, `non-resumable-actions` |
| T2 | `consumer` |
| T3 | `concurrency` |

**Optional everywhere:**
| Field | When useful |
|---|---|
| `description` | T3 user-CRUD (editor display) |
| `tags` | T3 user-CRUD (editor search) |
| `worktree` | Cross-worktree debugging |
| `checksum` | Manual-edit corruption detection (optional sha256 of body) |
| `notes` | Free-form |

**Format rules:**
- Frontmatter MUST start on line 1 with `---`.
- Closing `---` on its own line.
- Empty line after closing fence before body.
- Body MAY use `## Section` headers; per-skill conventions for content.

---

## Atomic write helper

**Location:** `skills/_shared/atomic-state-write.md` (procedure spec) + a tiny shell wrapper invoked from skill SKILL.md files.

**API (called from a skill via Bash):**

```bash
atomic_state_write <target-path> <<'CONTENT'
---
tier: T1
producer: implement
schema-version: 1
branch: feature/dark-mode
timestamp: 2026-05-16T14:38:00Z
phase: implement
status: in-progress
non-resumable-actions: []
---

## Phase log
- analyze done at 14:30:00Z
- implement started at 14:32:00Z
CONTENT
```

**Phase enum (M4 v3 canonical for `/implement`):** `analyze`, `implement`, `phase-2-escalated`, `self-review`, `phase-3-escalated`, `debug-handoff`, `ship`, `ship-committed-only`, `done`, `aborted`. The `phase:` field accepts any string per M1 spec — other skills define their own enums.

**Procedure:**

```bash
atomic_state_write() {
  local target="$1"
  local tmp="${target}.tmp.$$"  # PID-suffixed to avoid parallel collisions
  local content
  content="$(cat)"               # read content from stdin

  # 1. Write to tmp
  printf '%s' "$content" > "$tmp" || { rm -f "$tmp"; return 1; }

  # 2. fsync tmp file
  sync -d "$tmp" 2>/dev/null || sync

  # 3. Atomic rename (POSIX guarantee)
  mv "$tmp" "$target" || { rm -f "$tmp"; return 1; }

  # 4. fsync the directory so the rename is durable
  sync -d "$(dirname "$target")" 2>/dev/null || sync

  return 0
}
```

**Sibling helper `atomic_state_append` (T3 append-only):**

```bash
atomic_state_append() {
  local target="$1"
  local line
  line="$(cat)"
  # Single-line ≤ 4KB append is POSIX-atomic via O_APPEND
  printf '%s\n' "$line" >> "$target" || return 1
  sync -d "$target" 2>/dev/null || sync
  return 0
}
```

---

## Validation helper

**Location:** `skills/_shared/validate-state-file.md`.

**API:**

```bash
validate_state_file <target-path>
# Returns 0 on success; non-zero on failure.
# On failure, prints structured error to stderr.
```

**Procedure:**

1. Verify file exists and begins with `---\n` on line 1.
2. Parse YAML frontmatter via `yq` or shell-line parsing.
3. Check common-base required fields (`tier`, `producer`, `schema-version`, `branch`, `timestamp`).
4. Read `tier` and check tier-specific required fields (T1 → phase/status/non-resumable-actions; T2 → consumer; T3 → concurrency).
5. If `schema-version` doesn't match supported version, fall through to "schema-version mismatch" error path.
6. If `checksum` field present, compute SHA-256 of body (post-frontmatter) and compare; mismatch → corruption.

**On failure (Q5 — hard-fail with recovery AUQ):**

The skill that invoked validation MUST handle non-zero return by opening an `AskUserQuestion` like:

```
Q: state.md failed validation — missing required field 'non-resumable-actions' (T1 schema).
   The file may be corrupt, partially written, or from an older plugin version (schema-version: 0).

Options:
  - Delete state file and restart skill from spec   (lose in-flight state)
  - Open file in $EDITOR and fix manually          (skill pauses; retry validation after)
  - Skip validation and continue (emergency)        (risk: silent corruption)
```

**JSONL files** use line-by-line validation. Each malformed line is logged and skipped; the rest of the file is loaded.

---

## PreToolUse hook — enforce-state-helper-usage

**Location:** `hooks/enforce-state-helper.sh`.

**Trigger:** `PreToolUse` matcher `Edit|Write`.

**Behavior:**
- If the target path is under `.geniro/state/`, `.geniro/planning/<task-dir>/`, or `.geniro/knowledge/` AND the calling tool is direct `Edit`/`Write` (not via `atomic_state_write`) → **block** (in block-mode) or **warn** (in warn-mode).
- Hook checks if the calling skill's prompt explicitly mentions the helper name; this is a heuristic but catches the common case.
- Allowlist in `.geniro/safety.json`: `enforce-state-helper` bypass for power users.

**Warn-mode vs block-mode (Q7 migration):**
- During Stage 1 (skeleton + per-skill migration), hook is in **warn-mode** — prints a warning but allows the call. This catches forgotten migration sites without blocking work.
- Final PR flips to **block-mode** — direct Edit on state paths is rejected.

---

## Concurrency mechanisms — implementation sketch

### T1: slug-scoped path + truncation hash

```bash
compute_task_slug() {
  local branch="$1"  # default: current branch
  : "${branch:=$(git branch --show-current)}"
  local slug
  slug="$(echo "$branch" | tr '[:upper:]' '[:lower:]' | sed 's#[^a-z0-9]\+#-#g')"
  if [ "${#slug}" -gt 60 ]; then
    slug="$(printf '%s' "$slug" | head -c 52)-$(printf '%s' "$slug" | sha256sum | head -c 8)"
  fi
  printf '%s' "$slug"
}
```

### T2: branch-scoped handoff path

```bash
handoff_path() {
  local producer="$1"
  local slug
  slug="$(compute_task_slug)"
  printf '.geniro/state/handoff/from-%s-%s.md' "$producer" "$slug"
}
```

### T3 append-only: POSIX-atomic append (already shown in helper section)

### T3 CRUD: optimistic mtime check

```bash
# At read time:
initial_mtime=$(stat -c %Y "$target")

# At write time (just before atomic_state_write):
current_mtime=$(stat -c %Y "$target" 2>/dev/null || echo 0)
if [ "$current_mtime" != "$initial_mtime" ]; then
  # File changed since we read it. Open AUQ.
  # AUQ options: overwrite / show-diff / abort
fi
```

---

## Migration plan

### PR-0 — Infrastructure (1–2 days)

**Files to add:**
- `skills/_shared/atomic-state-write.md` — helper procedure spec (called via Bash from skills).
- `skills/_shared/validate-state-file.md` — validation procedure spec.
- `skills/_shared/state-tier-spec.md` — canonical frontmatter schema reference (this design doc, distilled).
- `hooks/enforce-state-helper.sh` — PreToolUse hook in **warn-mode** initially.
- `hooks/enforce-state-helper.sh` config in plugin's `hooks.json`.
- `tests/state/atomic-write.sh` — exercises tmp+rename happy path + crash recovery simulation.
- `tests/state/validate-frontmatter.sh` — exercises Q4 schema with positive + negative cases per tier.
- Update `CLAUDE.md` to document the new tier model and helper invocation.

**Acceptance:**
- Helpers callable from a sample skill (a smoke-test skill in `tests/`).
- Validator hard-fails on missing required field and prints structured error.
- Hook warns (doesn't block) on direct Edit to state paths.

### PR-1 — `/implement` reference migration

**Why first:** most complex skill; if the design holds here, it holds everywhere.

**Changes:**
- Update `skills/implement/SKILL.md`:
  - Replace direct `Edit` on `.geniro/planning/<task>/state.md` with `atomic_state_write` calls.
  - Add canonical frontmatter to all state files written.
  - At resume (post-compaction), call `validate_state_file` on the resumed state.md.
- Migrate Path 1: `state-<slug>.md` resume pattern (where used in /implement).
- Add `non-resumable-actions` tracking: when /implement does a `git push` or `gh pr comment`, append to the list.

**Acceptance:** `/implement` runs end-to-end with helper-mediated writes; resume after a forced compaction recovers cleanly; validator catches a hand-corrupted state file.

### PR-2 through PR-N — remaining skills

Order (lowest risk first):

1. `/debug` — already uses HYPOTHESES-<slug>.md state; conversion is mechanical. Adds T2 handoff path move (`findings-state.md` → `from-debug-<branch>.md`).
2. `/review` — moves `review-findings-state.md` → `from-review-<branch>.md`.
3. `/follow-up` — **state-file migration only.** Per master plan §66, the skill source is deleted (absorbed by `/implement`). This PR migrates existing in-flight user state to `task-dir/state.md` so live pipelines survive the upgrade; the skill directory itself is removed in а separate milestone after M4 ships.
4. `/refactor` — straightforward state-file conversion.
5. `/learnings` (or the auto-pass replacing it) — `learnings.jsonl` gets a sidecar `.meta.yaml`, append helper adopted.
6. `/instructions` — adds optimistic mtime check on edits.
7. `/actions` — same.
8. `/onboard` — converts CODEBASE_MAP.md to `_CODEBASE_MAP.md` with T3 frontmatter.
9. `/setup` — adds the `_FEATURES.md` rename + frontmatter.
10. Other hooks (`session-start-restore.sh` — renamed from `post-compact-notification.sh` per M3 §6 with broader `SessionStart` matcher; `enforce-tdd-order.sh`) — update to use validator.

**Per-skill PR template:** ~30 min each. Each PR adds 1–3 helper-call sites and the canonical frontmatter. The hook's warn-mode tolerates the in-progress mixed state — partially-migrated repos still work.

### PR-final — flip hook to block-mode

One-line config change in `hooks/enforce-state-helper.sh`: `MODE=warn` → `MODE=block`. After this lands, any direct Edit/Write on a state path is rejected with a clear error pointing at the helper.

---

## Path inventory — current → new

| Current path | New path | Tier | Migration step |
|---|---|---|---|
| `.geniro/planning/<task-dir>/state.md` | `.geniro/planning/<task-dir>/state.md` | T1 | Add canonical frontmatter; switch to helper. |
| `.geniro/planning/<task-dir>/spec.md`, `plan-<slug>.md`, `concerns.md`, `notes.md`, `milestone-N.md` | Same paths | T1 | Same. |
| `.geniro/planning/FEATURES.md` | `.geniro/planning/_FEATURES.md` | T3 CRUD | Rename + frontmatter. |
| `.geniro/planning/CODEBASE_MAP.md` | `.geniro/planning/_CODEBASE_MAP.md` | T3 CRUD | Rename + frontmatter. |
| `.geniro/planning/focus-<area>.md` | `.geniro/planning/_focus-<area>.md` | T3 CRUD | Rename + frontmatter. |
| `.geniro/state/follow-up/state-<slug>.md` | `.geniro/planning/<task-dir>/state.md` | T1 | **Consolidated**: one state.md per task, not per skill. |
| `.geniro/state/refactor/state-<slug>.md` | `.geniro/planning/<task-dir>/state.md` | T1 | Same. |
| `.geniro/state/improve-template/state-<slug>.md` | `.geniro/planning/<task-dir>/state.md` | T1 | Same. |
| `.geniro/state/debug/HYPOTHESES-<slug>.md` | `.geniro/planning/<task-dir>/hypotheses.md` | T1 | Move into task-dir. |
| `.geniro/state/debug/findings-state.md` | `.geniro/state/handoff/from-debug-<branch>.md` | T2 | Branch-scoped path. |
| `.geniro/state/debug/adversarial-tests.md` | `.geniro/state/handoff/from-debug-adversarial-<branch>.md` | T2 | Branch-scoped path. |
| `.geniro/state/review-findings-state.md` | `.geniro/state/handoff/from-review-<branch>.md` | T2 | Branch-scoped path. |
| `.geniro/state/follow-up/skeptic-hypothesis-<slug>.md` | `.geniro/planning/<task-dir>/skeptic-hypothesis.md` | T1 | Move into task-dir. |
| `.geniro/state/follow-up/adversarial-<slug>.md` | `.geniro/planning/<task-dir>/adversarial.md` | T1 | Move into task-dir. |
| `.geniro/state/follow-up/.deletion-<basename>.patch` | `.geniro/planning/<task-dir>/.deletion-<basename>.patch` | T1 | Move into task-dir. |
| `.geniro/state/tdd/state-<slug>.md` | `.geniro/state/handoff/tdd-<branch>.md` | T2 | Branch-scoped path (cross-skill handoff). |
| `.geniro/knowledge/learnings.jsonl` | Same path | T3 append-only | Add sidecar `.meta.yaml`; switch to append helper. |
| `.geniro/instructions/**/*.md` | Same paths | T3 CRUD | Add `concurrency: crud` to frontmatter. |
| `.geniro/actions/**/*.md` | Same paths | T3 CRUD | Same. |
| `.geniro/workflow/**` | Same paths | T3 CRUD | Same. |
| `.geniro/.geniro-state.json` | Same path | T3 CRUD | Add sidecar `.meta.yaml`. |

**Consolidation gains:**
- T1 state files now live in ONE place per task (`.geniro/planning/<task-dir>/`) instead of scattered across `.geniro/state/<skill>/`.
- All cross-session handoff goes through a single dir (`.geniro/state/handoff/`) with predictable `from-<producer>-<branch>.md` naming.
- T3 persistent registries get `_` prefix for visual distinction.

---

## Open implementation questions (for execution phase)

The following decisions were left intentionally for execution time — they don't affect the design but need answers when writing code:

1. **YAML parser:** `yq` (external dep, fully YAML-compliant) vs shell-line parsing (no dep, brittle on edge cases). Recommendation: shell-line for required-field check (cheap), `yq` for any nested-structure parsing.
2. **`fsync` portability:** `sync -d` (GNU) vs `gsync` (macOS) vs Python `os.fsync` fallback. Recommendation: probe at install time; fall back to `sync` (whole-disk) if no per-file sync available.
3. **PID-suffix safety:** `tmp.$$` can collide across hosts if `.geniro/` is on a shared filesystem (NFS). Recommendation: add `$HOSTNAME` suffix as extra safety: `tmp.$$.${HOSTNAME}`.
4. **AUQ phrasing for validator failures:** exact wording of the recovery options. Recommendation: design phrasing during PR-0 review.
5. **Test infrastructure for crash simulation:** how do we test crash-mid-write? Recommendation: shell-level `kill -9` against a sleep'd writer process during PR-0 test development.
6. **Backward-compat for already-deployed `.geniro/` dirs:** during PR-0 rollout, existing T1 state files lack frontmatter. Recommendation: validator detects missing frontmatter and treats as `schema-version: 0`; offers AUQ to migrate.

---

## Verification

This design is verified against the audit findings:

| Audit problem # | Addressed by |
|---|---|
| 1 — No atomic writes | Q2 (per-write atomic helper) + Q7 (PreToolUse hook enforces) |
| 2 — No rolling buffer / no checksum / no `latest_ok` | Q3 (no backup — atomic + git + regenerability suffices) |
| 3 — No schema validation on load | Q4 (tiered-rich schema) + Q5 (hard-fail with recovery AUQ) |
| 4 — `learnings.jsonl` no dedup | T3 append-only `content-hash` field |
| 5 — TDD state lifecycle ambiguous | Moved to T2 (`from-tdd-<branch>.md`); single handoff channel |
| 6 — Cross-session handoff overwrite-only | T2 branch-scoping eliminates same-branch collision; cross-branch handoffs don't overwrite each other |
| 7 — Worktree resolver Mode B not exhaustive | Helper API is uniform; primary-worktree routing happens once at helper entry |
| 8 — Slug 60-char truncation collision | T1 slug rule adds truncation hash suffix |
| 9 — Post-compaction mid-checkpoint recovery undefined | Atomic writes mean state.md is always either pre- or post-checkpoint; phase resume is deterministic |
| 10 — Skill-cleanup ownership decentralized | T1 cleanup is single rule: `rm -rf .geniro/planning/<task-dir>` at Phase Ship |
| 11 — Planning dir conflates global vs task-local | `_` prefix on T3 registries; T1 in task-dirs |
| 12 — Frontmatter keys inconsistent | Q4 tiered-rich schema is the canonical contract |

All 12 audit problems closed.

---

## Next steps

1. **User reviews this design doc.** Edit / push back / approve.
2. On approval, **execute PR-0** (infrastructure) — this is the first concrete code work.
3. After PR-0 lands and is verified, **either**:
   - Continue with PR-1 (`/implement` reference migration), or
   - Move to **M2 — Memory & knowledge layers** investigation and design (M2 doesn't depend on M1 execution being complete; can be designed in parallel and executed after).

Recommended: design M2 next (no code yet), then execute M1+M2 together in coordinated PRs. Keeps the design coherent across both milestones.
