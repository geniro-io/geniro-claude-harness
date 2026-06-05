---
name: geniro:actions
description: "Use when scaffolding a reusable workflow-helper (Slack/PR/release automations) or invoking a previously-created action. Stored at .geniro/actions/. Run-mode gates execution by risk_class (low/medium/high). Skip for editing core Geniro skills — edit the plugin repo directly."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion]
argument-hint: "[list|create|edit|run|delete|validate] [name] [...args]"
---

# Actions: Custom Workflow-Helper Management

3-phase stateless loop: **Parse → Execute → Done**. CRUD frontend + runner over `.geniro/actions/` — user-authored workflow-helper actions stored as plain Markdown files. Six operations: `list`, `create`, `edit`, `run`, `delete`, `validate`. Stateless.

## Sub-commands

| Sub-command | Aliases | Purpose |
|-------------|---------|---------|
| `list` | show, view, ls, current | Print the table of installed actions |
| `create` | new, scaffold, make, add | Interview-driven scaffold for a new action |
| `edit` | change, modify, update, tweak, adjust | Open an existing action for external editing, then re-validate |
| `run` | invoke, exec, execute, do | Read an action file and follow its steps inline (AUQ-gated by `risk_class`) |
| `delete` | remove, rm, drop | Remove an action file (with confirmation) |
| `validate` | check, lint | Lint frontmatter and body against the rule set |

## What is a custom action?

A `.md` file at `.geniro/actions/<slug>.md` with YAML frontmatter declaring `name`, `description`, `risk_class`, and a body containing a numbered `## Steps` section. The orchestrator (Geniro) reads the body and follows the steps. Actions are NOT auto-registered as slash commands — they live as plain `.md` files (not as `<slug>/SKILL.md` subfolders) precisely so Claude Code does not pick them up as their own slash commands. They are only reachable through `/geniro:actions run <name>`.

## Loop invariants

1. Inline execution — `/geniro:actions` runs entirely in the orchestrator; no subagents are spawned in any mode.
2. Args validated — every Write is previewed as a draft and gated by a frontmatter-validation step (the `create` path validates at its validation gate, just after the draft is written); every `run` preceded by an AUQ-gate matching `risk_class`.
3. Permission before side-effect — `risk_class: medium|high` gates execution via AUQ; `risk_class: low` skips the gate but respects per-step tool-allowlist if declared.
4. Bounded structured results — `list` renders a frontmatter-only table; the `description` field is the only free text shown and is already capped at create-validation time, so no separate body truncation applies.
5. Hard escalation gates — 3-retry on slug ambiguity → final abort AUQ.
6. Observations not assumed success — each step in `run` mode checks return status; failed step transitions to `failed` with step number captured.
7. Errors as structured observations — surfaced inline in final message.

## Budgets — quality-first

`/geniro:actions` has **zero hard kill caps**. Soft gates: 3-retry slug ambiguity → abort, 3-retry on create-validation failure. Architecture constraints: stateless; one action runs at a time (assumed sequential).

## ACI surface per phase

| Phase | Allowed tools | Forbidden tools |
|---|---|---|
| `parse` | `Read`, `Bash` (read-only), `Glob`, `AskUserQuestion` | `Write`, `Edit`, mutating `Bash`, `Agent` |
| `execute` (list) | `Read`, `Glob`, `Bash(ls...)`, `AskUserQuestion` | `Write`, `Edit`, `Agent`, `mcp__*` |
| `execute` (create) | `Read`, `Bash(atomic_state_write, mkdir -p .geniro/actions/, grep, echo >> .gitignore)`, `AskUserQuestion` | `Write`, `Edit`, `mcp__github__*`, network egress, `Agent` |
| `execute` (edit) | `Read`, `Bash(atomic_state_write, stat, mv)`, `AskUserQuestion` | `Write`, `Edit`, `mcp__*`, network egress |
| `execute` (delete) | `Read`, `Bash(rm)`, `AskUserQuestion` | `Write`, `Edit`, all `mcp__*`, network egress |
| `execute` (run) | **Intersection of /geniro:actions allowed-tools AND action frontmatter `allowed-tools:`** | (whatever is NOT in the intersection) |
| `execute` (validate) | `Read`, `Glob`, `Bash(grep -n, wc)`, `AskUserQuestion` | `Write`, `Edit`, `Agent`, `mcp__*` |
| `done` | (terminal report) | (none) |

**Run mode tool gating:** the effective tool surface is the intersection of the `/geniro:actions` skill's own `allowed-tools` (SKILL.md frontmatter) with the action's frontmatter `allowed-tools:` field. Phase 5.4 applies this intersection before any step runs.

Action frontmatter MAY include risky tools (`Bash(curl...)`, `mcp__github__*`) — these are then AUQ-gated by `risk_class` per the run-mode risk-class gate (Phase 5.3).

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

Parse `$ARGUMENTS` to determine which sub-command runs and (optionally) which action is targeted. Surface every WAIT gate through the `AskUserQuestion` tool, not plain-text questions — plain-text prompts aren't gated and the run can proceed without an answer.

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

- **`create`** — the next non-verb token must be a kebab-case slug (lowercase letters, digits, hyphens; ≤64 chars; not a reserved word; no leading/trailing hyphen).
- **`run`, `delete`, `validate`** — the non-verb remainder is treated as a **resolution input** that may be either an exact kebab slug (fast path) or a free-text description (routed through Phase 5.0).

### Ambiguity resolution

**Bare-slug fast path.** If `$ARGUMENTS` is non-empty AND no recognized verb was detected AND the entire `$ARGUMENTS` exact-matches an existing action file (literal or kebab-normalized: `daily recap` → `daily-recap`), default to `run` with that resolved slug. Typing a known slug IS the answer to "what do you want to do?"; re-asking would violate "skip questions already answered". The cross-worktree confirmation in Phase 5.0 Step 2 still fires.

**Otherwise** AUQ the verb:

- **Question:** "What would you like to do with custom actions?"
- **Options:** `List` / `Create` / `Run` / `Delete` (Edit and Validate omitted at the 4-option cap — both are rarely the ambiguous default; the user invokes them explicitly)

### Name validation (for `create` only)

- kebab-case (lowercase letters, digits, hyphens only)
- ≤64 characters
- NOT a reserved word: `anthropic`, `claude`, `geniro`, `list`, `create`, `edit`, `run`, `delete`, `validate`
- No leading/trailing hyphen

Re-ask up to 3 times via AskUserQuestion until valid.

## Phase 2: Mode dispatch

Branch on resolved action: `list` → Phase 3 · `create` → Phase 4 · `run` → Phase 5 · `edit` → Phase 6 · `delete` → Phase 7 · `validate` → Phase 8.

## Phase 3: `list` sub-command

### Step 1 — Scan directory

Build the registry index per Phase 5.0 Step 1 (dual-glob local + main-worktree, deduped by absolute path, `local` wins, each row source-tagged). The list output tags each row with its source (`local` / `main-worktree`). Without this, list mode misses actions authored in the main worktree but absent from the current linked worktree.

```bash
ls -la ./.geniro/actions/*.md "$PRIMARY_ROOT"/.geniro/actions/*.md 2>/dev/null
```

### Step 2 — Present results

If the directory is missing or empty:

```
No custom actions found.

Run `/geniro:actions create <name>` to scaffold your first action,
e.g. `/geniro:actions create slack-release-ping`.
```

Otherwise, for each `.md` file, Read the frontmatter and extract `name`, `description`, `risk_class`, `created`. Tag each row with its `<source>` (`local` / `main-worktree`) from Step 1. Present a markdown table:

```
## Custom Actions

| Name | Description | Risk | Created | Source |
|------|-------------|------|---------|--------|
| daily-recap | Use when wrapping the day's commits + tests | low | 2026-04-12 | local |
| commit-and-pr-summary | Use when finalizing a PR before push | medium | 2026-04-18 | local |
| slack-release-ping | Use when posting a release note to #releases | high | 2026-04-15 | main-worktree |
```

Close with: "Run with `/geniro:actions run <name>`."

## Phase 4: `create` sub-command

### Step 1 — Pre-check

If `<name>` was not provided, use the name-validation flow from Phase 1.

If `.geniro/actions/<name>.md` already exists, AUQ:

- **Question:** "`.geniro/actions/<name>.md` already exists. What do you want to do?"
- **Options:**
- `Edit in place` — Open the existing file and modify it directly
- `Version it` — Rename existing to `<name>-v1.md`, then write a new `<name>.md`
- `Cancel` — Leave the existing file untouched

On **Edit in place**: route to Phase 6 (which handles external-editor flow with `edit-in-place` entry mode).

On **Version it**: `mv .geniro/actions/<name>.md .geniro/actions/<name>-v1.md`, then continue to Step 2.

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

**Hook reminder:** the `.geniro/` deletion guard hook blocks `git add -f` on `.geniro/` paths — the correct path is `.gitignore` negation (above), never `git add -f`. Force-adding ignored files makes them visible in IDE Source Control panels, and a single "Discard All Changes" click becomes a one-click data-loss vector.

### Step 3 — Interview (Q1–Q5)

Use `AskUserQuestion` for each question. Q1–Q4 capture purpose, trigger, output, and test cases; **Q5 captures risk class**.

**Q1 — Purpose:** "What should this action do?"
- `Slack/messaging workflow`, `Pull-request workflow`, `Release/deployment workflow`, `Custom workflow`

**Q2 — When to trigger:** "When should this action be used?"
- `On user demand only`, `When inspecting a PR`, `Before a release`, `Custom trigger context`

**Q3 — Output / side-effects:** "What does it produce or change?"
- `Reports back to chat only`, `Writes a file`, `Posts to an external system`, `Multiple side effects`

**Q4 — Test cases (optional):** "Include a brief 'how to test it' note?"
- `Yes — add 1–2 test cases`, `Skip`

**Q5 — Risk class:** "What is the risk class for this action?"
- `low` — Pure read operations: read files, list dirs, aggregate data, display info. No network, no file mutation outside cwd. Runs with no AUQ confirmation.
- `medium` — Local file mutation, git commit (no push), tests with side effects (DB seed, integration test). External reads (HTTP GET). Runs with 1-click confirm.
- `high` — External sends (Slack/PR/email), git push, npm publish, docker push, cloud mutations, file deletion outside `.geniro/`. Runs with explicit Cancel-default confirm.

**Recommended option (per scaffold heuristic, based on Q3):**

- Q3 = "Reports back to chat only" → suggest `low`
- Q3 = "Writes a file" → suggest `medium`
- Q3 = "Posts to an external system" → suggest `high`
- Q3 = "Multiple side effects" → suggest `high`

### Step 4 — Draft preview

Read the template at `${CLAUDE_PLUGIN_ROOT}/skills/actions/skill-template.md`, then synthesize a concrete action body by filling in answers from Step 3:

- Frontmatter `name` = the kebab-case slug.
- Frontmatter `description` must start with "Use when" and reflect Q2's trigger context (≤250 chars).
- Frontmatter `risk_class:` = Q5's answer (REQUIRED).
- Frontmatter `model: inherit` unless the interview clearly justifies opus.
- Frontmatter `allowed-tools:` matches Q3's output.
- Frontmatter `external-send: true` if Q3 = "Posts to an external system" or "Multiple side effects" with external.
- Body sections follow the template exactly: `# {{name}}` (H1 title), `## When to use`, `## When NOT to use` (omit if no adjacent-action collision), `## Steps` (numbered), `## Output`, `## Test cases` (only if Q4 = Yes).

**Show the drafted markdown to the user. Do NOT call Write yet.** Then AUQ:

- **Question:** "Approve this draft?"
- **Options:**
- `Approve and write` — Write the file as previewed
- `Edit before writing` — Describe changes; I'll re-show the draft
- `Cancel` — Discard and stop

On `Edit before writing`: capture specific changes via `AskUserQuestion` (free-text via "Other"), apply, re-show. Cap at **3 edit rounds**.

### Step 5 — Write the file

Route the file through `atomic_state_write` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` — `.geniro/actions/*` is a T3 persistent-CRUD path, so direct `Edit`/`Write` trips the state-helper enforcement hook. Apply the §Caller-side mtime check before the write (`create` is the initial-write branch — target absent at read time and write time, so no conflict; `edit-in-place` catches concurrent modification). Frontmatter must include `created: <YYYY-MM-DD>` (today) and `created-by: geniro:actions`. The body must not contain any `{{placeholder}}` strings.

### Step 6 — Validation gate

After Write, run these checks (orchestrator-side, no subagent):

| # | Check | Severity |
|---|---|---|
| 1 | YAML frontmatter parses | CRITICAL |
| 2 | `name:` matches filename slug exactly | CRITICAL |
| 3 | `description:` starts with "Use when" (case-insensitive) | HIGH |
| 4 | `description:` ≤250 chars | HIGH |
| 5 | No `{{placeholder}}` in body | HIGH |
| 6 | File <500 lines | MEDIUM |
| 7 | `## Steps` section present with ≥1 numbered item | HIGH |
| 8 | **`risk_class:` field present** | **CRITICAL** |
| 9 | **`risk_class:` value in `{low, medium, high}`** | **CRITICAL** |
| 10 | **`external-send: true` requires `risk_class: medium` or `high`** | **HIGH** |

On fail: surface the specific failure (check, line, expected). The on-failure rollback depends on **entry mode**:

- **Entry mode `create`** (Step 5 just wrote the file from a Step 4 draft): `rm -f .geniro/actions/<name>.md`. Re-run `/geniro:actions create <name>`.
- **Entry mode `edit-in-place`** (Phase 6 OR Step 1 "Edit in place"): leave the file as the user left it. Re-run `/geniro:actions edit <name>`.

Do NOT auto-fix the written file in either mode. Re-validate up to 3 retry rounds.

After all 10 checks pass, print: `Created \`.geniro/actions/<name>.md\`. Run with \`/geniro:actions run <name>\`.`

## Phase 5: `run` sub-command

### Phase 5.0: Resolve target by name-or-description (shared by `run` / `delete` / `validate`)

The resolver returns three named values: `<resolved-path>` (absolute or repo-relative), `<resolved-slug>` (basename minus `.md`), and `<source>` (`local` or `main-worktree`).

#### Step 1 — Build the registry index

Resolve `PRIMARY_ROOT` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A — the snippet sets a shell variable used by the dual-glob below.

Dual-glob both `./.geniro/actions/*.md` (local) and `<PRIMARY_ROOT>/.geniro/actions/*.md` (main); tag each entry with `<source>` (`local` or `main-worktree`). When cwd IS the main worktree the two globs resolve to the same path — dedupe by absolute path before tagging. When the same slug exists in both, **local wins** — drop the main-worktree entry. This is the canonical registry build that Phase 3 (`list`) and Phase 8 (`validate`) reference.

#### Step 2 — Exact-slug fast path (literal or normalized)

Compute `<lookup>` from input: if already a valid kebab slug, `<lookup> = <input>`; otherwise normalize (trim, lowercase, whitespace-runs → hyphens). If `<lookup>` matches a registry entry's `name`:

- **Source = local:** return `(<resolved-path>, <resolved-slug>, local)`. No AUQ.
- **Source = main-worktree, sub-command = `run`:** confirm via AUQ before returning (cross-worktree gate per step 1):
- **Question:** "Action `<lookup>` exists in the main worktree at `<PRIMARY_ROOT>/.geniro/actions/<lookup>.md`. Use it?"
- **Options:** `Use the main-worktree copy` / `Cancel`
- **Source = main-worktree, sub-command = `delete` or `edit`:** skip the gate here; Step 4 handles the refuse-and-surface.
- **Source = main-worktree, sub-command = `validate`:** return `(<resolved-path>, <resolved-slug>, main-worktree)` without AUQ — `validate` is read-only.

#### Step 3 — Free-text matching path

If Step 2 did not resolve, score every entry by semantic fit (orchestrator scores in-context). Take the top 3 candidates by score.

Present an AUQ picker with up to 3 candidate options plus a final "Other" option. When "Other" is picked, surface free-text and loop. Cap loop at **3 rounds**; then surface "Could not narrow down — try `/geniro:actions list` for exact slugs" and stop.

#### Step 4 — Source-aware destructive-op guard (delete only)

If `<source> == main-worktree` AND sub-command is `delete`, refuse-and-surface (no "delete from main anyway" option — sibling worktrees represent intentionally separate workstreams).

### Phase 5.1: Resolve target

Call **Phase 5.0**. Phase 5.0 handles empty-input, exact-slug, free-text, and main-worktree-fallback cases.

### Phase 5.2: Read + parse

Read `<resolved-path>`. Parse frontmatter (`description`, `risk_class`, `model`, `allowed-tools`, `external-send`, `argument-hint`, `created`). Hold body steps in memory for Phase 5.4.

### Phase 5.3: Risk-class AUQ gate

Read action's frontmatter `risk_class`:

- **`risk_class: low`** — Skip AUQ. Proceed to Phase 5.4.
- **`risk_class: medium`** — AUQ:
- **Question:** "Run action `<slug>` (medium risk)?"
- **Options:** `Run` (Recommended) / `Cancel`
- If Cancel → failed (user aborted).
- **`risk_class: high`** — AUQ with **Cancel-as-recommended** default (forces explicit Run pick):
- **Question:** "Run action `<slug>` (HIGH risk — confirm explicitly)?"
- **Options:** `Cancel` (Recommended) / `Run anyway`
- If Cancel → failed.

**Approvals[] persistence does NOT apply to run mode.** Risk-class AUQs are context-dependent (re-ask each run intentionally; "did I confirm `slack-release-ping` last week" must NOT auto-confirm this week).

**L2 emit on rejection signal:** After the AUQ resolves (any outcome), source `${CLAUDE_PLUGIN_ROOT}/lib/emit-rejection.sh` and invoke once:

```bash
emit_rejection_if_signal \
"/geniro:actions" "actions/<slug>" "risk_class_<low|medium|high>" \
"Run action <slug>" "<picked label>" "<recommended label>"
```

`<recommended label>` is the option carrying `(Recommended)` — `Run` for medium, `Cancel` for high. Helper detects rejection signal (picks containing `Cancel`) and emits L2 `user_rejected_suggestion` ONLY when signal fires. Acceptance (`Run` picked when recommended OR no rejection keyword) is a no-op. Cross-session signal: future /geniro:actions runs of the same slug surface "user rejected this action N times". This is distinct from approvals[], which is intentionally skipped in run mode.

### Phase 5.4: Execute inline (tool-scope intersection)

Follow the action body's numbered steps directly. The orchestrator is the runtime — no subagent dispatch; Phase 5 runs inline. Pass extra positional `$ARGUMENTS` (after the action name) as input context under a "User-supplied input" heading.

**Tool-scope contract.** BEFORE running any step, intersect the action's frontmatter `allowed-tools` with the orchestrator's own `allowed-tools` ONCE and identify any step whose required tools fall outside the intersection. If gaps exist, surface them in a single AUQ before execution begins:

- **Question:** "The action declares N step(s) using tools outside this run's tool scope: [list step numbers + missing tools]. How should I proceed?"
- **Options:** `Skip the affected steps and run the rest` / `Cancel the run`

If no gaps, proceed without asking. Do not call any tool the action did not declare in `allowed-tools` — the intersection is the action author's stated tool budget. Do not re-prompt mid-execution — the up-front gate is the only tool-scope WAIT point.

If a step has a `[AUQ]` or `## Confirm:` annotation, fire AUQ at that step. On non-zero exit or tool failure → halt; transition to `failed` with step number captured.

### Phase 5.5: Wrap-up + L2 emit

Print summary:

```
Action `<resolved-slug>` complete.

Steps run: <count>
Steps skipped: <list, or "none">
Files changed: <list, or "none">
External calls: <list, or "none">
```

**L2 emit on successful external-send run:** if the action's frontmatter declared `external-send: true` AND run succeeded, emit one L2 `discovery` row

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

After a successful emit, echo `Recorded learning: <summary>` to the user, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §"Caller contract" — the helper writes silently, so the echo is the only signal the run was recorded.

Else: no emit (most action runs are not novel-discovery events).

## Phase 6: `edit` sub-command

### Step 1 — Resolve target

Call **Phase 5.0**. If `<source> == main-worktree`, refuse-and-surface (editing a sibling worktree's action would modify a separate workstream — same rationale as `delete`).

### Step 2 — Open for external editing

Print absolute path: `Edit: <absolute-path-to-resolved-file>`.

AUQ to wait for the user's "done" signal:

- **Question:** "Have you finished editing `<absolute-path>`?"
- **Options:**
- `Done — re-run validation` — Re-read the file and run Phase 4 Step 6 checks (1-10) with `edit-in-place` entry mode
- `Cancel` — Stop without re-validating; leave the file as the user left it

### Step 3 — Re-validate (on Done) + auto-validate

Re-run the **Phase 4 Step 6 validation gate** with **entry mode = `edit-in-place`**. The file is NOT deleted on validation failure — pre-existing user work is preserved.

**Auto-validation surfacing:** if validation fails (CRITICAL/HIGH), surface findings + AUQ:

- **Question:** "Auto-validation found issues: <list>. What next?"
- **Options:** `Open editor again` / `Save anyway despite warnings` / `Revert to pre-edit version`

The auto-validation does NOT block save; it surfaces. User remains in control.

After all 10 checks pass: `Edited \`.geniro/actions/<resolved-slug>.md\`. Run with \`/geniro:actions run <resolved-slug>\`.`

## Phase 7: `delete` sub-command

### Step 1 — Resolve + source-guard

Call **Phase 5.0**. Phase 5.0 Step 4 enforces the source-aware guard: if `<source> == main-worktree`, refuse and stop. Phase 7 only continues when `<source> == local`.

### Step 2 — Confirm + high-risk warning

Read action's frontmatter `risk_class`. AUQ:

- **Question:** "Delete `.geniro/actions/<resolved-slug>.md`? This cannot be undone unless the file is committed to git." (For `risk_class: high`, prepend: "⚠ This high-risk action will be permanently removed; if it represents critical workflow, consider versioning it first via `/geniro:actions edit <resolved-slug>` and renaming to `<resolved-slug>-archived`.")
- **Options:** `Delete the file` / `Cancel` (Recommended)

### Step 3 — Execute

If confirmed:

```bash
rm -f .geniro/actions/<resolved-slug>.md
rmdir .geniro/actions/ 2>/dev/null # silently if empty
```

Print: "Deleted `.geniro/actions/<resolved-slug>.md`."

The `.geniro/` deletion guard hook **allows** per-file `rm -f` of `.geniro/actions/<slug>.md` (per the hook's "Per-file `rm -f` remain allowed" rule); only bulk deletion is blocked.

## Phase 8: `validate` sub-command

### Step 1 — Resolve scope

When validating all actions (no `<slug>` provided), build the registry per Phase 5.0 Step 1 (dual-glob local + main-worktree, deduped, `local` wins, source-tagged). Without this, validate run from a linked worktree misses primary-worktree actions and produces a false-pass.

If `<slug>` provided: resolve via Phase 5.0 (Steps 1-3) to get `<resolved-path>` and `<source>`, then validate only that single file. Else validate the deduped union from the dual-glob above. Read-only; never mutates.

### Step 2 — Lint rule set (shared with `/geniro:instructions validate review-extra`)

Combined rule table (Phase 4 Step 6 checks + description hygiene):

| Check | Severity |
|---|---|
| YAML frontmatter parses | CRITICAL |
| `name:` matches filename | CRITICAL |
| `description:` starts with "Use when" | HIGH |
| `description:` ≤250 chars | HIGH |
| `description:` mentions adjacent terms | LOW |
| `description:` includes boundary clause ("Skip for...") | LOW |
| `risk_class:` present and valid (`low\|medium\|high`) | CRITICAL |
| `external-send: true` ⇒ `risk_class: medium\|high` | HIGH |
| `## Steps` section present with ≥1 numbered item | HIGH |
| No `{{placeholder}}` in body | HIGH |
| File <500 lines | MEDIUM |
| `allowed-tools:` field present (if action mutates) | LOW |
| No references to dropped skills in body | HIGH |

Dropped-skill ref check uses the list: `/brainstorm`, `/decompose`, `/follow-up`, `/deep-simplify`, `/features`, `/learnings`, `/cleanup`, `/vendor`.

### Step 3 — Output format

```
$ /geniro:actions validate

Validation results: 3 actions checked, 1 issue found.

✓ daily-recap.md (local) no issues
⚠ slack-release-ping.md (main-worktree) 1 HIGH
└── Line 4: risk_class missing — REQUIRED field
✓ pr-finalize.md (local) no issues

To fix: /geniro:actions edit slack-release-ping
```

Exit non-zero if any CRITICAL or HIGH. MEDIUM / LOW are warnings.

## Memory I/O

`.geniro/actions/*.md` is NOT a memory layer — it's executable workflow content. The 4 memory layers do not include actions.

| Layer | Read | Write | Notes |
|---|---|---|---|
| L1 CLAUDE.md | not read | not written | `/geniro:actions` does not touch CLAUDE.md |
| L2 learnings.jsonl | not read in CRUD modes | written in run mode if `external-send: true` and success (§Phase 5.5) | One `discovery` row per external-send run |
| L3 semantic files | not read | not written | N/A |
| L4 `.geniro/instructions/*.md` | not read by `/geniro:actions` itself | not written | `/geniro:instructions` owns this surface |
| Actions (`.geniro/actions/*.md`) | read in all modes | written in create/edit | T3 PERSISTENT/CRUD ; NOT part memory model |

Actions are stored at the T3 PERSISTENT/CRUD tier. They survive compaction trivially because they are files on disk.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll just edit a core Geniro skill instead of creating a custom action" | No — core skills are shipped globally and overwritten on update. Custom workflow helpers belong at `.geniro/actions/`. |
| "I'll silently overwrite the existing action file" | No — for `create` on an existing slug, present edit/version/cancel via AUQ. For top-level `edit`, route through Phase 6. Silent overwrite destroys committed work. |
| "I'll skip the description hygiene preview" | No — descriptions starting with "Use when" trigger reliably. |
| "The five interview questions are overkill for a small action" | No — they capture the things every action needs documented regardless of size: purpose, trigger, output, and risk class. |
| "I'll register the new action as `<slug>/SKILL.md` so it shows in the slash menu" | No — that defeats the entire design. Custom actions are reachable ONLY through `/geniro:actions run`. |
| "I'll spawn a subagent to execute the action" | No — Phase 5 runs inline; the orchestrator is the runtime. |
| "I'll skip the risk_class AUQ if the user already confirmed last week" | No — risk-class decisions are context-dependent. Re-ask each run. The approvals[] persistence applies to one-time decisions (e.g., $ARGUMENTS disambiguation), NOT runtime confirmations. |
| "I'll auto-pick `risk_class: low` if I can't tell" | No — Q5 is mandatory. The scaffold heuristic suggests a value based on Q3, but the user must confirm or pick differently. |
| "I'll allow `--skip-confirm` flag to bypass the risk-class gate" | No — explicit anti-pattern. If user wants no-AUQ, they pick `risk_class: low` on create. Bypass would defeat the safety net. |
| "I'll auto-elevate risk_class to `high` if `allowed-tools:` contains `Bash(curl)`" | No — manual is fine. The validate-mode lint catches `external-send: true ⇒ risk_class: medium|high`. Auto-elevation would surprise users. |
| "I'll auto-pick the highest-scoring fuzzy match without showing the user" | No — every free-text resolution passes through AskUserQuestion. |
| "I'll re-use Phase 4 Step 6's `rm -f` failure behavior unconditionally" | No — failure path is parametric on **entry mode**. `create` → `rm -f` rollback is correct because the file didn't exist. `edit-in-place` → leave the file. |
| "I'll silently delete the action from the main worktree even though I'm in a linked worktree" | No — `delete` from a linked worktree refuses-and-surfaces. Sibling worktrees represent intentionally separate workstreams. |

## Cross-references

- PERSISTENT (CRUD) — `.geniro/actions/` tier; write via `atomic_state_write` with the caller-side optimistic mtime check per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md`
- L2 emit triggers — `discovery` emit on external-send actions (Phase 5.5)
- Compaction survival — actions are files on disk, so they persist across compaction
- §Loop invariants — 7 loop invariants
- §Budgets — quality-first budgets
- §ACI surface per phase — per-phase ACI
- §Phase 6: `edit` sub-command — edit dialogue-mode pattern
- §Phase 8: `validate` sub-command — validate rule set (shared + structural lint)

## Definition of Done

- [ ] Intent parsed from `$ARGUMENTS` (or default to `list`)
- [ ] If `create`: 5-question interview completed, draft previewed and approved, file written, all 10 validation checks passed
- [ ] If `run`: action file located and read, risk_class AUQ fired (medium/high), action steps executed inline within tool-scope intersection
- [ ] If `delete`: confirmed via AUQ before removal (high-risk warning added if applicable)
- [ ] If `edit`: target resolved (or refused if main-worktree), absolute path printed, AUQ "Done" gate fired, Phase 4 Step 6 checks (1-10) re-run on Done, file NOT deleted on validation failure
- [ ] If `validate`: 13-rule lint executed; CRITICAL/HIGH cause non-zero exit
- [ ] All user interactions used `AskUserQuestion`
- [ ] `.gitignore` re-include rules added on first action created (idempotent)
- [ ] No `{{placeholder}}` left in any written file
- [ ] On create, file written has frontmatter `created`, `created-by: geniro:actions`, and `risk_class:` (validate enforces `risk_class:`; `created`/`created-by` are create-time stamps, not re-validated, so a hand-authored action without them still passes validate)
- [ ] L2 `discovery` emit fired on successful run with `external-send: true`
- [ ] Worktree fallback for `run` consulted main worktree only when local registry didn't resolve, and path confirmed via AUQ before executing
- [ ] `delete` / `edit` refused to operate on actions in a sibling worktree
