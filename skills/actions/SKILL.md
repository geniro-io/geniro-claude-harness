---
name: actions
description: "Use when scaffolding a reusable workflow-helper (Slack/PR/release automations) or invoking a previously-created action. Stored at .geniro/actions/. Run-mode executes the action directly — invoking it is the authorization, so no confirmation is asked. Skip for editing core Geniro skills — edit the plugin repo directly."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion]
argument-hint: "[list|create|edit|run|delete|validate] [name] [...args]"
---

# Actions: custom workflow-helper management

3-phase stateless loop: **Parse → Execute → Done**. CRUD frontend + runner over `.geniro/actions/` — user-authored workflow-helper actions stored as plain Markdown files. Six operations: `list`, `create`, `edit`, `run`, `delete`, `validate`.

**Runtime portability.** `${CLAUDE_PLUGIN_ROOT}` is set by Claude Code. When it is unset (another Agent-Skills runtime, e.g. Cursor), resolve it before following any reference: the plugin root is the ancestor directory of this file containing `.claude-plugin/plugin.json` — substitute it for every `${CLAUDE_PLUGIN_ROOT}` occurrence and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. Tool and hook substitutions for non-Claude-Code runtimes: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md`.

## Sub-commands

| Sub-command | Aliases | Purpose |
|-------------|---------|---------|
| `list` | show, view, ls, current | Print the table of installed actions |
| `create` | new, scaffold, make, add | Interview-driven scaffold for a new action |
| `edit` | change, modify, update, tweak, adjust | Open an existing action for external editing, then re-validate |
| `run` | invoke, exec, execute, do | Read an action file and follow its steps inline (no confirmation — invoking the action is the authorization) |
| `delete` | remove, rm, drop | Remove an action file (with confirmation) |
| `validate` | check, lint | Lint frontmatter and body against the rule set |

## What is a custom action?

A `.md` file at `.geniro/actions/<slug>.md` with YAML frontmatter declaring `name`, `description`, `risk_class`, and a body containing a numbered `## Steps` section. The orchestrator (Geniro) reads the body and follows the steps. Actions are NOT auto-registered as slash commands — they live as plain `.md` files (not as `<slug>/SKILL.md` subfolders) precisely so Claude Code does not pick them up as their own slash commands. They are only reachable through `/geniro:actions run <name>`.

## Loop invariants

1. Inline execution — `/geniro:actions` runs entirely in the orchestrator; no subagents are spawned in any mode.
2. Args validated — every Write is previewed as a draft and gated by a frontmatter-validation step (the `create` path validates at its validation gate, just after the draft is written). `run` has no confirmation gate (invariant 3 / Phase 5.3).
3. Invoking authorizes execution — `run` fires the action's steps directly regardless of `risk_class` (Phase 5.3); the tool-allowlist intersection (Phase 5.4), the one-time scope checkpoint when the run edits outside what the action declares (Phase 5.4), and author-placed `[AUQ]`/`## Confirm:` checkpoints still fire.
4. Bounded structured results — `list` renders a frontmatter-only table; the `description` field is the only free text shown and is already capped at create-validation time, so no separate body truncation applies.
5. Hard escalation gates — 3-retry on slug ambiguity → final abort AUQ.
6. Observations not assumed success — each step in `run` mode checks return status; failed step transitions to `failed` with step number captured.
7. Errors as structured observations — surfaced inline in final message.

## Budgets — quality-first

`/geniro:actions` has **zero hard kill caps**. Soft gates: 3-retry slug ambiguity → abort, 3-retry on create-validation failure. Architecture constraints: one action runs at a time (assumed sequential).

## ACI surface per phase

| Phase | Allowed tools | Forbidden tools |
|---|---|---|
| `parse` | `Read`, `Bash` (read-only), `Glob`, `AskUserQuestion` | `Write`, `Edit`, mutating `Bash`, `Agent` |
| `execute` (list) | `Read`, `Glob`, `Bash(ls...)`, `AskUserQuestion` | `Write`, `Edit`, `Agent`, `mcp__*` |
| `execute` (create) | `Read`, `Bash(atomic_state_write, mkdir -p "$PRIMARY_ROOT"/.geniro/actions/, grep, echo >> "$PRIMARY_ROOT"/.gitignore, sed -i, rm -f "$PRIMARY_ROOT"/.gitignore.bak, mv)`, `AskUserQuestion` | `Write`, `Edit`, `mcp__github__*`, network egress, `Agent` |
| `execute` (edit) | `Read`, `Bash(atomic_state_write, stat, cp, mv, rm -f *.pre-edit.bak)`, `AskUserQuestion` | `Write`, `Edit`, `mcp__*`, network egress |
| `execute` (delete) | `Read`, `Bash(rm)`, `AskUserQuestion` | `Write`, `Edit`, all `mcp__*`, network egress |
| `execute` (run) | **Intersection of /geniro:actions allowed-tools AND action frontmatter `allowed-tools:`** | (whatever is NOT in the intersection) |
| `execute` (validate) | `Read`, `Glob`, `Bash(grep -n, wc)`, `AskUserQuestion` | `Write`, `Edit`, `Agent`, `mcp__*` |
| `done` | (terminal report) | (none) |

**Run mode tool gating:** Phase 5.4 intersects the action's frontmatter `allowed-tools:` with this skill's own before any step runs.

Action frontmatter MAY include risky tools (`Bash(curl...)`, `mcp__github__*`); they run under the no-confirm contract (Phase 5.3), scoped by the action's `allowed-tools`. `risk_class` is a blast-radius label (listing / delete-warning / lint), not a run prompt.

## Termination case → state mapping

| Cause | Message format |
|---|---|
| User cancelled at any AUQ (other than the scope checkpoint's stop pick — next row) | `aborted: user cancelled at <step>` |
| Scope checkpoint (Phase 5.4) — user picked "Stop here, keep what's changed" | `aborted: stopped at scope checkpoint after step <N>`; edits stay in place and the Phase 5.5 summary, with its `/geniro:review` recommendation, prints before the transition |
| Slug resolution failed after 3 AUQ retries | `aborted: slug unresolved after 3 AUQ rounds` |
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

Resolve `PRIMARY_ROOT` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A, re-running the snippet in every Bash call that uses the variable (Mode A owns the recompute-per-call rule). Actions are cross-session content, so every create-path write below is `"$PRIMARY_ROOT"`-prefixed — a cwd-relative write from a linked worktree is destroyed on `git worktree remove`.

If `"$PRIMARY_ROOT"/.geniro/actions/<name>.md` already exists, AUQ:

- **Question:** "`<resolved path>` already exists. What do you want to do?"
- **Options:**
- `Edit in place` — Open the existing file and modify it directly
- `Version it` — Rename existing to `<name>-v1.md`, then write a new `<name>.md`
- `Cancel` — Leave the existing file untouched

On **Edit in place**: route to Phase 6 (which handles external-editor flow with `edit-in-place` entry mode).

On **Version it**: `mv "$PRIMARY_ROOT"/.geniro/actions/<name>.md "$PRIMARY_ROOT"/.geniro/actions/<name>-v1.md`, then continue to Step 2.

On **Cancel**: stop.

### Step 2 — Ensure directory + gitignore

```bash
mkdir -p "$PRIMARY_ROOT"/.geniro/actions

# Remove bare `.geniro/` if present — it would block negation patterns below.
sed -i.bak '/^\.geniro\/$/d' "$PRIMARY_ROOT"/.gitignore 2>/dev/null && rm -f "$PRIMARY_ROOT"/.gitignore.bak

grep -q "^\.geniro/\*$" "$PRIMARY_ROOT"/.gitignore 2>/dev/null || echo ".geniro/*" >> "$PRIMARY_ROOT"/.gitignore
grep -q "^\!\.geniro/$" "$PRIMARY_ROOT"/.gitignore 2>/dev/null || echo "!.geniro/" >> "$PRIMARY_ROOT"/.gitignore
grep -q "^\!\.geniro/actions/$" "$PRIMARY_ROOT"/.gitignore 2>/dev/null || echo "!.geniro/actions/" >> "$PRIMARY_ROOT"/.gitignore
grep -q "^\!\.geniro/actions/\*\*$" "$PRIMARY_ROOT"/.gitignore 2>/dev/null || echo "!.geniro/actions/**" >> "$PRIMARY_ROOT"/.gitignore
```

This default keeps `.geniro/actions/` committed (team-shareable). The negation edits target `"$PRIMARY_ROOT"/.gitignore` — the negation must live where the action file is written. Users who want their actions ignored can manually remove the `!.geniro/actions/` lines.

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

**Q5 — Risk class:** "What is the risk class for this action?" (`risk_class` labels the action's blast radius for the listing, the delete-confirmation warning, and lint — it does not add a run-time confirmation; an action the user invoked is never re-confirmed.)
- `low` — Pure read operations: read files, list dirs, aggregate data, display info. No network, no file mutation outside cwd.
- `medium` — Local file mutation, git commit (no push), tests with side effects (DB seed, integration test). External reads (HTTP GET).
- `high` — External sends (Slack/PR/email), git push, npm publish, docker push, cloud mutations, file deletion outside `.geniro/`.

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
- Body sections follow the template exactly: `# {{name}}` (H1 title), `## When to use`, `## When NOT to use` (omit if the action has no skip conditions), `## Steps` (numbered), `## Output`, `## Test cases` (only if Q4 = Yes).

**Show the drafted markdown to the user. Do NOT call Write yet.** Then AUQ:

- **Question:** "Approve this draft?"
- **Options:**
- `Approve and write` — Write the file as previewed
- `Edit before writing` — Describe changes; I'll re-show the draft
- `Cancel` — Discard and stop

On `Edit before writing`: capture specific changes via `AskUserQuestion` (free-text via "Other"), apply, re-show. Cap at **3 edit rounds**.

### Step 5 — Write the file

Route the file through `atomic_state_write` to `"$PRIMARY_ROOT"/.geniro/actions/<name>.md` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` — `.geniro/actions/*` is a T3 persistent-CRUD path, so direct `Edit`/`Write` trips the state-helper enforcement hook. Apply the §Caller-side mtime check before the write (`create` is the initial-write branch — target absent at read time and write time, so no conflict; `edit-in-place` catches concurrent modification). Frontmatter must include `created: <YYYY-MM-DD>` (today) and `created-by: geniro:actions`. The body must not contain any `{{placeholder}}` strings.

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

- **Entry mode `create`** (Step 5 just wrote the file from a Step 4 draft): `rm -f "$PRIMARY_ROOT"/.geniro/actions/<name>.md`. Re-run `/geniro:actions create <name>`.
- **Entry mode `edit-in-place`** (Phase 6 OR Step 1 "Edit in place"): leave the file as the user left it. Re-run `/geniro:actions edit <name>`.

On failure, report the issue and let the user fix it — auto-fixing would silently rewrite user-authored content. Re-validate up to 3 retry rounds.

After all 10 checks pass, print: `Created \`.geniro/actions/<name>.md\`. Run with \`/geniro:actions run <name>\`.` When `$PRIMARY_ROOT` is not the current directory, show the resolved absolute path instead and append: "Written to the main repo checkout, so it survives if this worktree is removed."

## Phase 5: `run` sub-command

### Phase 5.0: Resolve target by name-or-description (shared by `run` / `edit` / `delete` / `validate`)

The resolver returns three named values: `<resolved-path>` (absolute or repo-relative), `<resolved-slug>` (basename minus `.md`), and `<source>` (`local` or `main-worktree`).

#### Step 1 — Build the registry index

Resolve `PRIMARY_ROOT` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A — the snippet sets a shell variable used by the dual-glob below.

Dual-glob both `./.geniro/actions/*.md` (local) and `<PRIMARY_ROOT>/.geniro/actions/*.md` (main); tag each entry with `<source>` (`local` or `main-worktree`). When cwd IS the main worktree the two globs resolve to the same path — dedupe by absolute path before tagging. When the same slug exists in both, **local wins** — drop the main-worktree entry. This is the canonical registry build that Phase 3 (`list`) and Phase 8 (`validate`) reference.

#### Step 2 — Exact-slug fast path (literal or normalized)

Compute `<lookup>` from input: if already a valid kebab slug, `<lookup> = <input>`; otherwise normalize (trim, lowercase, whitespace-runs → hyphens). If `<lookup>` matches a registry entry's `name`:

- **Source = local, sub-command = `run` or `validate`:** return `(<resolved-path>, <resolved-slug>, local)`. No AUQ.
- **Source = local, sub-command = `edit` or `delete`:** do not return yet — continue to Step 4. The Step 1 registry dropped any same-slug main-worktree entry (local wins), so only Step 4's direct both-locations check can see the second copy.
- **Source = main-worktree, sub-command = `run`:** confirm via AUQ before returning (cross-worktree confirmation; `<source>` was tagged in Step 1):
- **Question:** "Action `<lookup>` exists in the main worktree at `<PRIMARY_ROOT>/.geniro/actions/<lookup>.md`. Use it?"
- **Options:** `Use the main-worktree copy` / `Cancel`
- **Source = main-worktree, sub-command = `edit` or `delete`:** no gate here; Step 4 resolves which copy is operated on.
- **Source = main-worktree, sub-command = `validate`:** return `(<resolved-path>, <resolved-slug>, main-worktree)` without AUQ — `validate` is read-only.

#### Step 3 — Free-text matching path

If Step 2 did not resolve, score every entry by semantic fit (orchestrator scores in-context). Take the top 3 candidates by score.

Present an AUQ picker with up to 3 candidate options plus a final "Other" option. When "Other" is picked, surface free-text and loop. Cap loop at **3 rounds**; then surface "Could not narrow down — try `/geniro:actions list` for exact slugs" and stop.

#### Step 4 — Canonical-copy resolution (`edit` / `delete` only)

The main repo checkout is the canonical home of actions — `create` writes there, so refusing to edit/delete the copy `create` just wrote would break the create→edit flow from a worktree. Worktree-local copies (tracked branch variants) stay respected at read/run time — the `run`/`list` local-wins rule is unchanged. For `edit` and `delete`, after Step 2 or Step 3 resolves `<resolved-slug>`, check BOTH `./.geniro/actions/<resolved-slug>.md` AND `<PRIMARY_ROOT>/.geniro/actions/<resolved-slug>.md` directly on disk — not the Step 1 registry, whose local-wins dedupe hides the main copy — before returning:

- Slug exists ONLY at `<PRIMARY_ROOT>` → operate there directly.
- Slug exists ONLY locally (cwd copy, e.g. a committed branch-local file) → operate on the local copy.
- Slug exists in BOTH with identical contents → operate on the main-repo copy without asking. Contents differ → one AUQ:
- **Question:** "`<resolved-slug>` exists in both the main repo checkout and this worktree, and the two copies differ (`run` currently uses this worktree's copy). Which copy should I <edit|delete>?"
- **Options:** `Main repo copy (Recommended)` / `This worktree's branch copy` / `Cancel`

`delete` still passes through the Phase 7 Step 2 destructive-op confirmation regardless of which copy is targeted.

### Phase 5.1: Resolve target

Call **Phase 5.0**. Phase 5.0 handles empty-input, exact-slug, free-text, and main-worktree-fallback cases.

### Phase 5.2: Read + parse

Read `<resolved-path>`. Parse frontmatter (`description`, `risk_class`, `model`, `allowed-tools`, `external-send`, `argument-hint`, `created`). Hold body steps in memory for Phase 5.4.

### Phase 5.3: No run-confirmation gate

`run` executes the action's steps directly regardless of `risk_class` — invoking `/geniro:actions run <slug>` IS the authorization, so re-asking "are you sure?" would only repeat a decision the user already made. Proceed straight to Phase 5.4. Scope of that authorization: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/approval-scope.md`. `risk_class` stays as action metadata: it drives the `list` Risk column, the `delete` high-risk warning (Phase 7), the validate lint rules (Phase 8), and the L2 learning tag (Phase 5.5) — it never gates execution.

The remaining WAIT points in run mode are not "are you sure you want to run this?" prompts, and stay in place: the cross-worktree confirmation (Phase 5.0 Step 2 — "use the copy from another worktree?"), the free-text picker (Phase 5.0 Step 3 — "which action?"), the tool-scope gap AUQ (Phase 5.4 — a step needs a tool outside the allowlist intersection), the scope checkpoint (Phase 5.4 — the run edited outside what the action declares), and any `[AUQ]`/`## Confirm:` checkpoint the action author placed inside the body.

### Phase 5.4: Execute inline (tool-scope intersection)

Follow the action body's numbered steps directly, inline in the orchestrator (invariant 1). Pass extra positional `$ARGUMENTS` (after the action name) as input context under a "User-supplied input" heading.

**Tool-scope contract.** BEFORE running any step, intersect the action's frontmatter `allowed-tools` with the orchestrator's own `allowed-tools` ONCE and identify any step whose required tools fall outside the intersection. If gaps exist, surface them in a single AUQ before execution begins:

- **Question:** "The action declares N step(s) using tools outside this run's tool scope: [list step numbers + missing tools]. How should I proceed?"
- **Options:** `Skip the affected steps and run the rest` / `Cancel the run`

If no gaps, proceed without asking. Do not call any tool the action did not declare in `allowed-tools` — the intersection is the action author's stated tool budget. Do not re-prompt mid-execution — the up-front gate is the only tool-scope WAIT point.

**Scope checkpoint.** The action's own `## Steps` declare where its work belongs. Track what the run edits (the same changed-file list Phase 5.5 reports) and pause once — the first time the run edits production files outside the areas those steps name:

- **Question:** "This run has changed <N> files, including <the areas the action's steps don't mention>. How should I continue?"
- **Options:** `Keep going` / `Show me the diff first` / `Stop here, keep what's changed`

`Show me the diff first` renders the diff and re-fires this same question, so the user decides with the diff in view — the one-pause cap counts triggers, not re-renders. `Stop here, keep what's changed` halts execution with the edits left in place and goes to Phase 5.5: print the wrap-up summary, including its `/geniro:review` recommendation, before the terminal transition — the run that most needs an independent look is the one that must not exit silently.

One such trigger per run at most, and it is declaration-relative — what the action names versus what the run touched. The count is reported, never the trigger; no number of edits fires this on its own.

This is not a re-authorization: invoking the action authorized the run and Phase 5.3 stands, so the checkpoint never re-asks whether to run it. It reports an outcome the user could not have known at invocation — the work outgrew what the action describes. New information, new decision. That is what earns the interruption, and why there is exactly one: a second prompt gets less attention than the first, not more.

**Persistent-path write routing.** When an action step writes to `.geniro/instructions/`, `.geniro/actions/`, or `.geniro/workflow/` via a relative path, resolve the target against `$PRIMARY_ROOT`, recomputed via the Mode A snippet inside the Bash call performing the write — these three families are persistent user-authored content that must survive worktree removal, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md`. Task-local writes (`.geniro/planning/`, `.geniro/state/`) stay cwd-relative. Writes still route through the atomic helpers where the state-helper hook requires them.

If a step has a `[AUQ]` or `## Confirm:` annotation, fire AUQ at that step. On non-zero exit or tool failure → halt; transition to `failed` with step number captured.

### Phase 5.5: Wrap-up + record a learning

Print summary:

```
Action `<resolved-slug>` complete.

Steps run: <count>
Steps skipped: <list, or "none">
Files changed: <list, or "none">
External calls: <list, or "none">
```

When the scope checkpoint fired (Phase 5.4), close the summary by recommending an independent look at the diff: "This run went past what the action describes — `/geniro:review` reviews the diff before you push." Recommend it, never run it — `/geniro:actions` spawns no subagent and calls no other skill (invariant 1); the user decides whether to run it.

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

Call **Phase 5.0**. Phase 5.0 Step 4 resolves which copy to edit — the canonical main-repo copy by default, the local branch copy when only it exists or the user picks it.

### Step 2 — Open for external editing

Snapshot the file before handing it off — `cp "<absolute-path>" "<absolute-path>.pre-edit.bak"` — so the auto-validation's "Revert to pre-edit version" option (Step 3) has a restore target; without it that option has nothing to restore.

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
- **Options:** `Open editor again` / `Save anyway despite warnings` / `Revert to pre-edit version` (restore via `mv "<path>.pre-edit.bak" "<path>"`)

The auto-validation does NOT block save; it surfaces. User remains in control. On any terminal pick (Save / Revert / Cancel), remove the snapshot: `rm -f "<path>.pre-edit.bak"`.

After all 10 checks pass: `Edited \`<resolved-path>\`. Run with \`/geniro:actions run <resolved-slug>\`.` When the edited copy is the main-repo one and the current directory is a different worktree, append: "Written to the main repo checkout, so it survives if this worktree is removed."

## Phase 7: `delete` sub-command

### Step 1 — Resolve target copy

Call **Phase 5.0**. Phase 5.0 Step 4 resolves which copy to delete — the canonical main-repo copy by default, the local branch copy when only it exists or the user picks it. Phase 7 continues with `<resolved-path>`.

### Step 2 — Confirm + high-risk warning

Read action's frontmatter `risk_class`. AUQ:

- **Question:** "Delete `<resolved-path>`? This cannot be undone unless the file is committed to git." (For `risk_class: high`, prepend: "⚠ This high-risk action will be permanently removed; if it represents critical workflow, consider versioning it first via `/geniro:actions edit <resolved-slug>` and renaming to `<resolved-slug>-archived`.")
- **Options:** `Delete the file` / `Cancel` (Recommended)

### Step 3 — Execute

If confirmed:

```bash
rm -f "<resolved-path>"
rmdir "$(dirname "<resolved-path>")" 2>/dev/null # silently if empty
```

Print: "Deleted `<resolved-path>`."

The `.geniro/` deletion guard hook **allows** per-file `rm -f` of `.geniro/actions/<slug>.md` (per the hook's "Per-file `rm -f` remain allowed" rule); only bulk deletion is blocked.

## Phase 8: `validate` sub-command

### Step 1 — Resolve scope

When validating all actions (no `<slug>` provided), build the registry per Phase 5.0 Step 1 (dual-glob local + main-worktree, deduped, `local` wins, source-tagged). Without this, validate run from a linked worktree misses primary-worktree actions and produces a false-pass.

If `<slug>` provided: resolve via Phase 5.0 (Steps 1-3) to get `<resolved-path>` and `<source>`, then validate only that single file. Else validate the deduped union from the dual-glob above. Read-only; never mutates.

### Step 2 — Lint rule set (shared with `/geniro:instructions validate review-extra`)

Run the 10 create-gate checks (Phase 4 Step 6 table, same severities), plus these validate-only rows:

| Check | Severity |
|---|---|
| `description:` mentions adjacent terms | LOW |
| `description:` includes boundary clause ("Skip for...") | LOW |
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
✓ commit-and-pr-summary.md (local) no issues

To fix: /geniro:actions edit slack-release-ping
```

Exit non-zero if any CRITICAL or HIGH. MEDIUM / LOW are warnings.

## Memory I/O

`.geniro/actions/*.md` is NOT a memory layer — it's executable workflow content. The 4 memory layers do not include actions.

| Layer | Read | Write | Notes |
|---|---|---|---|
| CLAUDE.md (not a memory layer) | not read | not written | `/geniro:actions` does not touch CLAUDE.md |
| L2 learnings.jsonl | not read in CRUD modes | written in run mode if `external-send: true` and success (§Phase 5.5) | One `discovery` row per external-send run |
| L3 semantic files | not read | not written | N/A |
| L4 `.geniro/instructions/*.md` | not read by `/geniro:actions` itself | not written | `/geniro:instructions` owns this surface |
| Actions (`.geniro/actions/*.md`) | read in all modes | written in create/edit | T3 PERSISTENT/CRUD — NOT part of the memory model |

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
| "I'll auto-pick `risk_class: low` if I can't tell" | No — Q5 is mandatory. The scaffold heuristic suggests a value based on Q3, but the user must confirm or pick differently. |
| "This action is high-risk (git push / Slack send), so I'll add a confirmation before running it to be safe" | No — invoking `/geniro:actions run <slug>` IS the authorization; adding an "are you sure?" AUQ would re-ask a decision the user already made by invoking it. `risk_class` is metadata (list / delete-warning / lint), not a run gate. Action-author `[AUQ]`/`## Confirm:` checkpoints inside the body are different — those are the author's deliberate in-step pauses; honor them. |
| "Invoking is the authorization, so this scope checkpoint is the confirmation gate that rule forbids." | Invocation removes the gate on the decision the user already made — running this action. The scope checkpoint reports something the user could not have known at invocation: the run outgrew what the action describes. New information, new decision. |
| "I'll auto-elevate risk_class to `high` if `allowed-tools:` contains `Bash(curl)`" | No — manual is fine. The validate-mode lint catches `external-send: true ⇒ risk_class: medium|high`. Auto-elevation would surprise users. |
| "I'll auto-pick the highest-scoring fuzzy match without showing the user" | No — every free-text resolution passes through AskUserQuestion. |
| "I'll re-use Phase 4 Step 6's `rm -f` failure behavior unconditionally" | No — failure path is parametric on **entry mode**. `create` → `rm -f` rollback is correct because the file didn't exist. `edit-in-place` → leave the file. |
| "I'm in a linked worktree, so I'll refuse to edit/delete the main repo's copy of an action" | No — the main repo checkout is the canonical home of actions (`create` writes there); refusing would break the create→edit flow from a worktree. Local branch copies stay respected at read/run time (local wins); CRUD targets the canonical copy, asking only when both copies exist and differ. |

## Cross-references

- PERSISTENT (CRUD) — `.geniro/actions/` tier; write via `atomic_state_write` with the caller-side optimistic mtime check per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md`
- L2 emit triggers — `discovery` emit on external-send actions (Phase 5.5)

## Definition of done

Load-bearing exit gates — per-command mechanics live in their phase sections.

- [ ] Every user interaction used `AskUserQuestion`; destructive ops (`delete`, and overwrite on `create`) confirmed via AUQ before running.
- [ ] Writes to `.geniro/actions/` routed through `atomic_state_write` (T3 persistent-CRUD path); no `{{placeholder}}` left in any written file.
- [ ] `create` passed all 10 validation checks (including required `risk_class:`); `validate` exited non-zero on any CRITICAL/HIGH.
- [ ] `run` executed inline with no run-confirmation gate (Phase 5.3), within the action's tool-scope intersection; the scope checkpoint fired (once) if the run edited outside what the action declares; L2 `discovery` emit fired on a successful `external-send: true` run.
- [ ] `.gitignore` re-include rules added on first action created (idempotent).
