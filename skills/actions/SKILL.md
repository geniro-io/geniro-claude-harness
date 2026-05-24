---
name: geniro:actions
description: "Use when scaffolding а reusable workflow-helper (Slack/PR/release automations) or invoking а previously-created action. Stored at .geniro/actions/. Run-mode gates execution by risk_class (low/medium/high). Skip for editing core Geniro skills — edit the plugin repo directly."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion]
argument-hint: "[list|create|edit|run|delete|validate] [name] [...args]"
---

# Actions: Custom Workflow-Helper Management

M10c 3-phase stateless loop: **Parse → Execute → Done**. CRUD frontend + runner over `.geniro/actions/` — user-authored workflow-helper actions stored as plain Markdown files. Six operations: `list`, `create`, `edit`, `run`, `delete`, `validate`. Stateless (per M10a Q5). Architecture spec: `architecture/M10c-actions-redesign.md`.

## Sub-commands

| Sub-command | Aliases | Purpose |
|-------------|---------|---------|
| `list` | show, view, ls, current | Print the table of installed actions |
| `create` | new, scaffold, make, add | Interview-driven scaffold for а new action |
| `edit` | change, modify, update, tweak, adjust | Open an existing action for external editing, then re-validate |
| `run` | invoke, exec, execute, do | Read an action file и follow its steps inline (AUQ-gated by `risk_class`) |
| `delete` | remove, rm, drop | Remove an action file (with confirmation) |
| `validate` | check, lint | Lint frontmatter и body against the M10c rule set |

If `$ARGUMENTS` is empty, default to `list`.

## What is а custom action?

А `.md` file at `.geniro/actions/<slug>.md` with YAML frontmatter declaring `name`, `description`, `risk_class`, и а body containing а numbered `## Steps` section. The orchestrator (Geniro) reads the body и follows the steps. Actions are NOT auto-registered as slash commands — they live as plain `.md` files (not as `<slug>/SKILL.md` subfolders) precisely so Claude Code does not pick them up as their own slash commands. They are only reachable through `/geniro:actions run <name>`.

## Loop invariants (M4 §2.2)

1. One result per subagent call — `/actions` does NOT spawn subagents in CRUD modes.
2. Args validated before exec — every Write preceded by frontmatter validation; every `run` preceded by AUQ-gate matching `risk_class`.
3. Permission before side-effect — `risk_class: medium|high` gates execution via AUQ; `risk_class: low` skips the gate but respects per-step tool-allowlist if declared.
4. Bounded structured results — `list` truncates per-action body display at 200 chars.
5. Hard escalation gates — 3-retry on slug ambiguity → final abort AUQ.
6. Observations not assumed success — each step in `run` mode checks return status; failed step transitions к `failed` with step number captured.
7. Errors as structured observations — surfaced inline in final message.

## Budgets — quality-first (M4 §2.3)

`/actions` has **zero Class-A hard kill caps**. Class-B gates: 3-retry slug ambiguity → abort, body preview truncation at 200 chars, 3-retry on create-validation failure. Architecture constraints: stateless (per M10a Q5); one action runs at а time (assumed sequential).

## ACI surface per phase (M4 §13.5)

| Phase | Allowed tools | Forbidden tools |
|---|---|---|
| `parse` | `Read`, `Bash` (read-only), `Glob`, `AskUserQuestion` | `Write`, `Edit`, mutating `Bash`, `Agent` |
| `execute` (list) | `Read`, `Glob`, `Bash(ls ...)`, `AskUserQuestion` | `Write`, `Edit`, `Agent`, `mcp__*` |
| `execute` (create) | `Read`, `Write`, `Bash(mkdir -p .geniro/actions/, grep, echo >> .gitignore)`, `AskUserQuestion` | `mcp__github__*`, network egress, `Agent` |
| `execute` (edit) | `Read`, `Edit`, `Bash(stat, mv)`, `AskUserQuestion` | `mcp__*`, network egress |
| `execute` (delete) | `Read`, `Bash(rm)`, `AskUserQuestion` | `Write`, `Edit`, all `mcp__*`, network egress |
| `execute` (run) | **Intersection of /actions allowed-tools AND action frontmatter `allowed-tools:`** | (whatever is NOT in the intersection) |
| `execute` (validate) | `Read`, `Glob`, `Bash(grep -n, wc)`, `AskUserQuestion` | `Write`, `Edit`, `Agent`, `mcp__*` |
| `done` | (terminal report) | (none) |

**Run mode tool gating:**

```
effective_tool_surface = intersection(
  global allowed-tools for /actions skill,  # from SKILL.md frontmatter
  action frontmatter `allowed-tools:` field,
)
```

Action frontmatter MAY include risky tools (`Bash(curl ...)`, `mcp__github__*`) — these are then AUQ-gated by `risk_class` per §Phase 4 Step 2 below.

## Termination case → state mapping

| Cause | Message format |
|---|---|
| User cancelled at any AUQ | `aborted: user cancelled at <step>` |
| Slug resolution failed after 3 AUQ retries | `aborted: slug unresolved after 3 AUQ rounds` |
| Run-mode AUQ rejected (risk_class:high, user picked Cancel) | `aborted: user rejected high-risk action <slug>` |
| Validation rejected on create (frontmatter missing required field) | `aborted: create blocked by validation — <reason>` |
| Action body execution failed mid-step | `failed: action <slug> step <N> returned non-zero exit` |
| Write blocked by file-protection hook | `aborted: file-protection hook blocked write to <path>` |
| Validate found CRITICAL/HIGH issues | exit non-zero with `validate: <slug> failed — N CRITICAL, M HIGH` |

## Phase 1: Parse intent from `$ARGUMENTS`

**Step 0 — Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: actions`, `LOAD_TIER: rules-only`, `MODE: initial-load`. The helper's §Procedure prescribes an imperative `Read` of `global.md`; its §Echo contract requires one observable line. Both are mandatory.

Parse `$ARGUMENTS` to determine which sub-command runs и (optionally) which action is targeted. NEVER output questions as plain text — always use the `AskUserQuestion` tool at every WAIT gate.

### Action detection

| Intent | Aliases | Maps to |
|--------|---------|---------|
| List | show, view, list, ls, current | `list` |
| Create | create, new, scaffold, make, add | `create` |
| Edit | edit, change, modify, update, tweak, adjust | `edit` |
| Run | run, invoke, exec, execute, do | `run` |
| Delete | delete, remove, rm, drop | `delete` |
| Validate | validate, check, lint | `validate` |

If `$ARGUMENTS` is empty, default to `list`.

### Name / query detection

The non-verb portion of `$ARGUMENTS` is parsed differently for `create` vs `run`/`delete`/`validate`:

- **`create`** — the next non-verb token MUST be а kebab-case slug (lowercase letters, digits, hyphens; ≤64 chars; not а reserved word; no leading/trailing hyphen).
- **`run`, `delete`, `validate`** — the non-verb remainder is treated as а **resolution input** that may be either an exact kebab slug (fast path) or а free-text description (routed through Phase 4.0).

### Ambiguity resolution

**Bare-slug fast path.** If `$ARGUMENTS` is non-empty AND no recognized verb was detected AND the entire `$ARGUMENTS` exact-matches an existing action file (literal или kebab-normalized: `daily recap` → `daily-recap`), default to `run` with that resolved slug. Typing а known slug IS the answer to "what do you want to do?"; re-asking would violate "skip questions already answered". Cross-worktree confirmation (§Phase 4 below) still fires.

**Otherwise** AUQ the verb:

- **Question:** "What would you like to do with custom actions?"
- **Options:** `List` / `Create` / `Run` / `Delete` (Validate is documented but rarely the default — user invokes explicitly)

### Name validation (for `create` only)

- kebab-case (lowercase letters, digits, hyphens only)
- ≤64 characters
- NOT а reserved word: `anthropic`, `claude`, `geniro`, `list`, `create`, `edit`, `run`, `delete`, `validate`
- No leading/trailing hyphen

Re-ask up к 3 times via AskUserQuestion until valid.

## Phase 2: Mode dispatch

Branch on resolved action: `list` → Phase 3 · `create` → Phase 4 · `run` → Phase 5 · `edit` → Phase 6 · `delete` → Phase 7 · `validate` → Phase 8.

## Phase 3: Command `list`

### Step 1 — Scan directory

```bash
ls -la .geniro/actions/*.md 2>/dev/null
```

### Step 2 — Present results

If the directory is missing или empty:

```
No custom actions found.

Run `/geniro:actions create <name>` to scaffold your first action,
e.g. `/geniro:actions create slack-release-ping`.
```

Otherwise, for each `.md` file, Read the frontmatter и extract `name`, `description`, `risk_class`, `created`. Present а markdown table:

```
## Custom Actions

| Name | Description | Risk | Created |
|------|-------------|------|---------|
| daily-recap | Use when wrapping the day's commits + tests | low | 2026-04-12 |
| commit-and-pr-summary | Use when finalizing а PR before push | medium | 2026-04-18 |
| slack-release-ping | Use when posting а release note to #releases | high | 2026-04-15 |
```

Close with: "Run with `/geniro:actions run <name>`."

## Phase 4: Command `create`

### Step 1 — Pre-check

If `<name>` was not provided, use the name-validation flow from Phase 1.

If `.geniro/actions/<name>.md` already exists, AUQ:

- **Question:** "`.geniro/actions/<name>.md` already exists. What do you want to do?"
- **Options:**
  - `Edit in place` — Open the existing file and modify it directly
  - `Version it` — Rename existing к `<name>-v1.md`, then write а new `<name>.md`
  - `Cancel` — Leave the existing file untouched

On **Edit in place**: route к Phase 6 (which handles external-editor flow with `edit-in-place` entry mode).

On **Version it**: `mv .geniro/actions/<name>.md .geniro/actions/<name>-v1.md`, then continue к Step 2.

On **Cancel**: stop.

### Step 2 — Ensure directory + gitignore

```bash
mkdir -p .geniro/actions

# Remove bare `.geniro/` if present — it would block negation patterns below.
sed -i.bak '/^\.geniro\/$/d' .gitignore 2>/dev/null && rm -f .gitignore.bak

grep -q "^\.geniro/\*$" .gitignore 2>/dev/null || echo ".geniro/*" >> .gitignore
grep -q "^\!\.geniro/$" .gitignore 2>/dev/null || echo "!.geniro/" >> .gitignore
grep -q "^\!\.geniro/actions/$" .gitignore 2>/dev/null || echo "!.geniro/actions/" >> .gitignore
grep -q "^\!\.geniro/actions/\*\*$" .gitignore 2>/dev/null || echo "!.geniro/actions/**" >> .gitignore
```

This default keeps `.geniro/actions/` committed (team-shareable). Users who want their actions ignored can manually remove the `!.geniro/actions/` lines.

**Hook reminder:** the `.geniro/` deletion guard hook blocks `git add -f` on `.geniro/` paths — the correct path is `.gitignore` negation (above), never `git add -f`. Force-adding ignored files makes them visible in IDE Source Control panels, и а single "Discard All Changes" click becomes а one-click data-loss vector.

### Step 3 — Interview (Q1–Q5)

Use `AskUserQuestion` for each question. Q1–Q4 capture purpose, trigger, output, и test cases; **Q5 captures risk class (P-M10-1 closure)**.

**Q1 — Purpose:** "What should this action do?"
- `Slack/messaging workflow`, `Pull-request workflow`, `Release/deployment workflow`, `Custom workflow`

**Q2 — When to trigger:** "When should this action be used?"
- `On user demand only`, `When inspecting а PR`, `Before а release`, `Custom trigger context`

**Q3 — Output / side-effects:** "What does it produce or change?"
- `Reports back to chat only`, `Writes а file`, `Posts to an external system`, `Multiple side effects`

**Q4 — Test cases (optional):** "Should we include а brief 'how to test it' note?"
- `Yes — add 1–2 test cases`, `Skip`

**Q5 — Risk class (NEW):** "What is the risk class for this action?"
- `low` — Pure read operations: read files, list dirs, aggregate data, display info. No network, no file mutation outside cwd. Runs with no AUQ confirmation.
- `medium` — Local file mutation, git commit (no push), tests with side effects (DB seed, integration test). External reads (HTTP GET). Runs with 1-click confirm.
- `high` — External sends (Slack/PR/email), git push, npm publish, docker push, cloud mutations, file deletion outside `.geniro/`. Runs with explicit Cancel-default confirm.

**Recommended option (per scaffold heuristic, based on Q3):**

- Q3 = "Reports back to chat only" → suggest `low`
- Q3 = "Writes а file" → suggest `medium`
- Q3 = "Posts to an external system" → suggest `high`
- Q3 = "Multiple side effects" → suggest `high`

### Step 4 — Draft preview

Read the template at `${CLAUDE_PLUGIN_ROOT}/skills/actions/skill-template.md`, then synthesize а concrete action body by filling in answers from Step 3:

- Frontmatter `name` = the kebab-case slug.
- Frontmatter `description` MUST start with "Use when" и reflect Q2's trigger context (≤250 chars).
- Frontmatter `risk_class:` = Q5's answer (REQUIRED — new P-M10-1 minimal).
- Frontmatter `model: inherit` unless the interview clearly justifies opus.
- Frontmatter `allowed-tools:` matches Q3's output.
- Frontmatter `external-send: true` if Q3 = "Posts к an external system" or "Multiple side effects" with external (M10c consistency check; validate-mode enforces `external-send: true ⇒ risk_class: medium|high`).
- Body sections: `## Overview`, `## Steps` (numbered), и `## Test` (only if Q4 = Yes).

**Show the drafted markdown к the user. Do NOT call Write yet.** Then AUQ:

- **Question:** "Approve this draft?"
- **Options:**
  - `Approve and write` — Write the file as previewed
  - `Edit before writing` — Describe changes; I'll re-show the draft
  - `Cancel` — Discard и stop

On `Edit before writing`: capture specific changes via `AskUserQuestion` (free-text via "Other"), apply, re-show. Cap at **3 edit rounds**.

### Step 5 — Write the file

Use the Write tool to write `.geniro/actions/<name>.md`. Frontmatter MUST include `created: <YYYY-MM-DD>` (today) и `created-by: geniro:actions`. The body MUST NOT contain any `{{placeholder}}` strings.

### Step 6 — Validation gate (P-M10-1 minimal enforcement)

After Write, run these checks (orchestrator-side, no subagent):

| # | Check | Severity | Source |
|---|---|---|---|
| 1 | YAML frontmatter parses | CRITICAL | preserved |
| 2 | `name:` matches filename slug exactly | CRITICAL | preserved |
| 3 | `description:` starts with "Use when" (case-insensitive) | HIGH | preserved |
| 4 | `description:` ≤250 chars | HIGH | preserved |
| 5 | No `{{placeholder}}` in body | HIGH | preserved |
| 6 | File <500 lines | MEDIUM | preserved |
| 7 | `## Steps` section present with ≥1 numbered item | HIGH | preserved |
| 8 | **`risk_class:` field present** | **CRITICAL** | **NEW** |
| 9 | **`risk_class:` value in `{low, medium, high}`** | **CRITICAL** | **NEW** |
| 10 | **If `external-send: true`, `risk_class` MUST be `medium` or `high`** | **HIGH** | **NEW** |

On fail: surface the specific failure (check, line, expected). The on-failure rollback depends on **entry mode**:

- **Entry mode `create`** (Step 5 just wrote the file from а Step 4 draft): `rm -f .geniro/actions/<name>.md`. Re-run `/geniro:actions create <name>`.
- **Entry mode `edit-in-place`** (Phase 6 OR Step 1 "Edit in place"): leave the file as the user left it. Re-run `/geniro:actions edit <name>`.

Do NOT auto-fix the written file in either mode. Re-validate up к 3 retry rounds.

After all 10 checks pass, print: `Created \`.geniro/actions/<name>.md\`. Run with \`/geniro:actions run <name>\`.`

## Phase 5: Command `run`

### Phase 5.0: Resolve target by name-or-description (shared by `run` / `delete` / `validate`)

The resolver returns three named values: `<resolved-path>` (absolute или repo-relative), `<resolved-slug>` (basename minus `.md`), и `<source>` (`local` or `main-worktree`).

#### Step 1 — Build the registry index

Glob `./.geniro/actions/*.md` for the local registry. Detect worktree state:

```bash
git rev-parse --show-toplevel
git worktree list --porcelain
```

If cwd is а linked worktree, also Glob `<main-worktree-root>/.geniro/actions/*.md`. Tag each entry with `<source>` (`local` or `main-worktree`). When the same slug exists in both, **local wins** — drop the main-worktree entry.

#### Step 2 — Exact-slug fast path (literal or normalized)

Compute `<lookup>` from input: if already а valid kebab slug, `<lookup> = <input>`; otherwise normalize (trim, lowercase, whitespace-runs → hyphens). If `<lookup>` matches а registry entry's `name`:

- **Source = local:** return `(<resolved-path>, <resolved-slug>, local)`. No AUQ.
- **Source = main-worktree, sub-command = `run`:** confirm via AUQ before returning (cross-worktree gate per M10c §6.3 step 1, D9 closure):
  - **Question:** "Action `<lookup>` exists in the main worktree at `<main-worktree-root>/.geniro/actions/<lookup>.md`. Use it?"
  - **Options:** `Use the main-worktree copy` / `Cancel`
- **Source = main-worktree, sub-command = `delete` или `edit`:** skip the gate here; Step 4 handles the refuse-and-surface.

#### Step 3 — Free-text matching path

If Step 2 did not resolve, score every entry by semantic fit (orchestrator scores in-context). Take top 4 candidates by score.

Present an AUQ picker with up к 3 candidate options plus а final "Other" option. When "Other" is picked, surface free-text and loop. Cap loop at **3 rounds**; then surface "Could not narrow down — try `/geniro:actions list` for exact slugs" and stop.

#### Step 4 — Source-aware destructive-op guard (delete only)

If `<source> == main-worktree` AND sub-command is `delete`, refuse-and-surface (no "delete from main anyway" option — sibling worktrees represent intentionally separate workstreams).

### Phase 5.1: Resolve target

Call **Phase 5.0**. Phase 5.0 handles empty-input, exact-slug, free-text, и main-worktree-fallback cases.

### Phase 5.2: Read + parse

Read `<resolved-path>`. Parse frontmatter (`description`, `risk_class`, `model`, `allowed-tools`, `external-send`, `argument-hint`, `created`). Hold body steps in memory for Phase 5.4.

### Phase 5.3: Risk-class AUQ gate (P-M10-1 closure)

Read action's frontmatter `risk_class`:

- **`risk_class: low`** — Skip AUQ. Proceed к Phase 5.4.
- **`risk_class: medium`** — AUQ:
  - **Question:** "Run action `<slug>` (medium risk)?"
  - **Options:** `Run` (Recommended) / `Cancel`
  - If Cancel → failed (user aborted).
- **`risk_class: high`** — AUQ with **Cancel-as-recommended** default (forces explicit Run pick):
  - **Question:** "Run action `<slug>` (HIGH risk — confirm explicitly)?"
  - **Options:** `Cancel` (Recommended) / `Run anyway`
  - If Cancel → failed.

**Approvals[] persistence does NOT apply к run mode.** Risk-class AUQs are context-dependent (re-ask each run intentionally; "did I confirm `slack-release-ping` last week" must NOT auto-confirm this week). This is intentional per M10c §6.3.

**P-X8-2 L2 emit on rejection signal:** After the AUQ resolves (any outcome), source `${CLAUDE_PLUGIN_ROOT}/lib/emit-rejection.sh` и invoke once:

```bash
emit_rejection_if_signal \
  "/geniro:actions" "actions/<slug>" "risk_class_<low|medium|high>" \
  "Run action <slug>" "<picked label>" "<recommended label>"
```

`<recommended label>` is the option carrying `(Recommended)` — `Run` для medium, `Cancel` для high. Helper detects rejection signal (`Cancel`/`Cancel anyway`) и emits L2 `user_rejected_suggestion` ONLY когда signal fires. Acceptance (`Run` picked when recommended OR no rejection keyword) is а no-op. Cross-session signal: future /actions runs of the same slug surface «user rejected this action N times» (P-X8-2 read protocol). Note this is distinct от М1 approvals[] which is intentionally skipped here.

### Phase 5.4: Execute INLINE (tool-scope intersection)

Follow the action body's numbered steps directly. The orchestrator is the runtime — no subagent dispatch in v1. Pass extra positional `$ARGUMENTS` (after the action name) as input context under а "User-supplied input" heading.

**Tool-scope contract.** BEFORE running any step, intersect the action's frontmatter `allowed-tools` with the orchestrator's own `allowed-tools` ONCE и identify any step whose required tools fall outside the intersection. If gaps exist, surface them in а single AUQ before execution begins:

- **Question:** "The action declares N step(s) using tools outside this run's tool scope: [list step numbers + missing tools]. How should I proceed?"
- **Options:** `Skip the affected steps and run the rest` / `Cancel the run`

If no gaps, proceed without asking. Do NOT call any tool the action did not declare in `allowed-tools`. Do NOT re-prompt mid-execution — the up-front gate is the only tool-scope WAIT point.

If а step has а `[AUQ]` или `## Confirm:` annotation, fire AUQ at that step. On non-zero exit или tool failure → halt; transition к `failed` with step number captured.

### Phase 5.5: Wrap-up + L2 emit (D10 closure)

Print summary:

```
Action `<resolved-slug>` complete.

Steps run: <count>
Steps skipped: <list, or "none">
Files changed: <list, or "none">
External calls: <list, or "none">
```

**L2 emit on successful external-send run:** if the action's frontmatter declared `external-send: true` AND run succeeded, emit one L2 `discovery` row per M2 §5.3:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh"
emit_learning <<'EOF'
{
  "type": "discovery",
  "trust": "verified",
  "skill": "actions",
  "tags": ["actions", "run", "<risk_class>"],
  "summary": "ran <slug> (risk=<risk_class>, external=true)",
  "entry": {"slug": "<slug>", "side_effects": [...]}
}
EOF
```

Else: no emit (most action runs are not novel-discovery events).

## Phase 6: Command `edit`

### Step 1 — Resolve target

Call **Phase 5.0**. If `<source> == main-worktree`, refuse-and-surface (editing а sibling worktree's action would modify а separate workstream — same rationale as `delete`).

### Step 2 — Open for external editing

Print absolute path: `Edit: <absolute-path-to-resolved-file>`.

AUQ to wait for the user's "done" signal:

- **Question:** "Have you finished editing `<absolute-path>`?"
- **Options:**
  - `Done — re-run validation` — Re-read the file и run Phase 4 Step 6 checks (1-10) with `edit-in-place` entry mode
  - `Cancel` — Stop without re-validating; leave the file as the user left it

### Step 3 — Re-validate (on Done) + auto-validate

Re-run the **Phase 4 Step 6 validation gate** with **entry mode = `edit-in-place`**. The file is NOT deleted on validation failure — pre-existing user work is preserved.

**Auto-validation surfacing (M10c §8 addition):** if validation fails (CRITICAL/HIGH), surface findings + AUQ:

- **Question:** "Auto-validation found issues: <list>. What next?"
- **Options:** `Open editor again` / `Save anyway despite warnings` / `Revert to pre-edit version`

The auto-validation does NOT block save; it surfaces. User remains in control.

After all 10 checks pass: `Edited \`.geniro/actions/<resolved-slug>.md\`. Run with \`/geniro:actions run <resolved-slug>\`.`

## Phase 7: Command `delete`

### Step 1 — Resolve + source-guard

Call **Phase 5.0**. Phase 5.0 Step 4 enforces the source-aware guard: if `<source> == main-worktree`, refuse and stop. Phase 7 only continues when `<source> == local`.

### Step 2 — Confirm + high-risk warning

Read action's frontmatter `risk_class`. AUQ:

- **Question:** "Delete `.geniro/actions/<resolved-slug>.md`? This cannot be undone unless the file is committed к git." (For `risk_class: high`, prepend: "⚠ This high-risk action will be permanently removed; if it represents critical workflow, consider versioning it first via `/geniro:actions edit <resolved-slug>` and renaming к `<resolved-slug>-archived`.")
- **Options:** `Delete the file` / `Cancel` (Recommended)

### Step 3 — Execute

If confirmed:

```bash
rm -f .geniro/actions/<resolved-slug>.md
rmdir .geniro/actions/ 2>/dev/null  # silently if empty
```

Print: "Deleted `.geniro/actions/<resolved-slug>.md`."

The `.geniro/` deletion guard hook **allows** per-file `rm -f` of `.geniro/actions/<slug>.md` (per the hook's "Per-file `rm -f` remain allowed" rule); only bulk deletion is blocked.

## Phase 8: Command `validate` (NEW — OQ-M10b-1 closure)

### Step 1 — Resolve scope

If `<slug>` provided: validate only `.geniro/actions/<slug>.md`. Else validate all `.geniro/actions/*.md`. Read-only; never mutates.

### Step 2 — Lint rule set (shared with `/instructions validate review-extra`)

Combined rule table (Phase 4 Step 6 checks + P-M10-2 description hygiene):

| Check | Severity | Source |
|---|---|---|
| YAML frontmatter parses | CRITICAL | Phase 4 Step 6 |
| `name:` matches filename | CRITICAL | Phase 4 |
| `description:` starts with "Use when" | HIGH | Phase 4 + M10b P-M10-2 |
| `description:` ≤250 chars | HIGH | Phase 4 |
| `description:` mentions adjacent terms | LOW | M10b §10.2 |
| `description:` includes boundary clause ("Skip for ...") | LOW | M10b §10.2 |
| `risk_class:` present and valid (`low\|medium\|high`) | CRITICAL | M10c §7.2 (new) |
| `external-send: true` ⇒ `risk_class: medium\|high` | HIGH | M10c §7.2 (new) |
| `## Steps` section present with ≥1 numbered item | HIGH | Phase 4 |
| No `{{placeholder}}` in body | HIGH | Phase 4 |
| File <500 lines | MEDIUM | Phase 4 |
| `allowed-tools:` field present (if action mutates) | LOW | M10c P-M10-1 "scoped" guideline |
| No references to dropped skills in body | HIGH | M10b §10.2 alignment |

Dropped-skill ref check uses the list: `/brainstorm`, `/decompose`, `/follow-up`, `/deep-simplify`, `/features`, `/learnings`, `/cleanup`, `/vendor`.

### Step 3 — Output format

```
$ /geniro:actions validate

Validation results: 3 actions checked, 1 issue found.

✓ daily-recap.md                  no issues
⚠ slack-release-ping.md           1 HIGH
  └── Line 4: risk_class missing — REQUIRED field per P-M10-1
✓ pr-finalize.md                  no issues

To fix: /geniro:actions edit slack-release-ping
```

Exit non-zero if any CRITICAL or HIGH. MEDIUM / LOW are warnings.

## Memory I/O (M2 §13)

`.geniro/actions/*.md` is NOT а memory layer — it's executable workflow content. M2's 4 layers do not include actions.

| Layer | Read | Write | Notes |
|---|---|---|---|
| L1 CLAUDE.md | not read | not written | `/actions` does not touch CLAUDE.md |
| L2 learnings.jsonl | not read in CRUD modes | written в run mode if `external-send: true` and success (§Phase 5.5) | One `discovery` row per external-send run |
| L3 semantic files | not read | not written | N/A |
| L4 `.geniro/instructions/*.md` | not read by `/actions` itself | not written | `/instructions` owns this surface |
| Actions (`.geniro/actions/*.md`) | read in all modes | written in create/edit | T3 PERSISTENT/CRUD per M1; NOT part of M2 memory model |

Actions are stored at the M1 T3 PERSISTENT/CRUD tier. They survive compaction trivially (file-on-disk M3 §6 Block 1).

## Anti-pattern check (P-MP-1)

| # | Anti-pattern | Status |
|---|---|---|
| 1 | One giant prompt | ✅ SKILL.md modular; action bodies are user-authored; action template at `${CLAUDE_PLUGIN_ROOT}/skills/actions/skill-template.md` is ~80 LOC |
| 2 | One giant tool | ✅ N/A |
| 3 | Unbounded autonomous loop | ✅ 3-retry on slug + 3-retry on create-validation; run mode is one-pass through action body |
| 4 | Autonomous external sends in first release | ✅ `risk_class: high` AUQ-gate with Cancel-as-recommended default; bare-slug fast path still respects the gate |
| 5 | No approval state | ✅ Run-mode is per-invocation (context-dependent) — approvals[] persistence intentionally NOT applied; rationale documented в Phase 5.3 |
| 6 | No durable plans or goals | ✅ N/A — actions ARE the durable plans for user-authored workflows |
| 7 | No compaction strategy | ✅ Actions are file-on-disk; survive compaction natively |
| 8 | All connectors loaded up front | ✅ Actions are loaded only when invoked; one at а time |
| 9 | High-risk tools without policy | ✅ §ACI surface per phase + §Phase 5.3 risk-class AUQ ladder + Phase 4 schema constraints (allowed-tools intersection) |
| 10 | Subagents before single-agent MVP measured | ✅ Zero subagents в /actions itself (action body may spawn agents if user-authored, but that's not /actions concern) |
| 11 | Dynamic timestamps in plugin-distributed Markdown | ⚠ Implementation note — this SKILL.md has no runtime timestamps; the action `created:` field IS а timestamp but lives in user-authored content (not plugin-distributed) |
| 12 | Non-deterministic agent registration order | ✅ N/A |

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll just edit а core Geniro skill instead of creating а custom action" | No — core skills are shipped globally и overwritten on update. Custom workflow helpers belong at `.geniro/actions/`. |
| "I'll silently overwrite the existing action file" | No — for `create` on an existing slug, present edit/version/cancel via AUQ. For top-level `edit`, route through Phase 6. Silent overwrite destroys committed work. |
| "I'll skip the description hygiene preview" | No — descriptions starting with "Use when" trigger reliably. |
| "The five interview questions are overkill for а small action" | No — they're the official skill-creator questions; even small actions need а clear purpose, trigger, output, и risk class documented in the file. |
| "I'll register the new action as `<slug>/SKILL.md` so it shows in the slash menu" | No — that defeats the entire design. Custom actions are reachable ONLY through `/geniro:actions run`. |
| "I'll spawn а subagent to execute the action" | Not in v1 — Phase 5 is inline-only. |
| "I'll skip the risk_class AUQ if the user already confirmed last week" | No — risk-class decisions are context-dependent (P-M10-1 untrusted-by-default). Re-ask each run. The approvals[] persistence applies к one-time decisions (e.g., $ARGUMENTS disambiguation), NOT runtime confirmations. |
| "I'll auto-pick `risk_class: low` if I can't tell" | No — Q5 is mandatory. The scaffold heuristic suggests а value based on Q3, but the user must confirm or pick differently. |
| "I'll allow `--skip-confirm` flag к bypass the risk-class gate" | No — explicit anti-pattern (P-MP-1 #4). If user wants no-AUQ, they pick `risk_class: low` on create. Bypass would defeat the safety net. |
| "I'll auto-elevate risk_class к `high` if `allowed-tools:` contains `Bash(curl)`" | No — manual is fine (per M10c OQ-M10c-3). The validate-mode lint catches `external-send: true ⇒ risk_class: medium|high`. Auto-elevation would surprise users. |
| "I'll auto-pick the highest-scoring fuzzy match without showing the user" | No — every free-text resolution passes through AskUserQuestion. |
| "I'll re-use Phase 4 Step 6's `rm -f` failure behavior unconditionally" | No — failure path is parametric on **entry mode**. `create` → `rm -f` rollback is correct because the file didn't exist. `edit-in-place` → leave the file. |
| "I'll silently delete the action from the main worktree even though I'm in а linked worktree" | No — `delete` from а linked worktree refuses-and-surfaces. Sibling worktrees represent intentionally separate workstreams. |

## Cross-references

- M1 §T3 PERSISTENT (CRUD) — `.geniro/actions/` tier; optimistic mtime check
- M2 §5.3 L2 emit triggers — `discovery` emit on external-send actions (Phase 5.5)
- M3 §6 Block 1 — file-on-disk compaction-survival channel
- M4 §2.2 — 7 loop invariants
- M4 §2.3 — quality-first budgets
- M4 §13.5 — per-phase ACI
- M10b §8 — edit dialogue-mode pattern (shared)
- M10b §10 — validate rule set (shared P-M10-2 + structural lint)
- `architecture/M10c-actions-redesign.md` — full design rationale

## Definition of Done

- [ ] Intent parsed from `$ARGUMENTS` (или default to `list`)
- [ ] If `create`: 5-question interview completed, draft previewed и approved, file written, all 10 validation checks passed
- [ ] If `run`: action file located и read, risk_class AUQ fired (medium/high), action steps executed inline within tool-scope intersection
- [ ] If `delete`: confirmed via AUQ before removal (high-risk warning added if applicable)
- [ ] If `edit`: target resolved (или refused if main-worktree), absolute path printed, AUQ "Done" gate fired, Phase 4 Step 6 checks (1-10) re-run on Done, file NOT deleted on validation failure
- [ ] If `validate`: 13-rule lint executed; CRITICAL/HIGH cause non-zero exit
- [ ] All user interactions used `AskUserQuestion`
- [ ] `.gitignore` re-include rules added on first action created (idempotent)
- [ ] No `{{placeholder}}` left in any written file
- [ ] File written has frontmatter `created`, `created-by: geniro:actions`, и `risk_class:`
- [ ] L2 `discovery` emit fired on successful run with `external-send: true`
- [ ] Worktree fallback for `run` consulted main worktree only when local registry didn't resolve, и path confirmed via AUQ before executing
- [ ] `delete` / `edit` refused к operate on actions in а sibling worktree
