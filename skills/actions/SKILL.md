---
name: geniro:actions
description: "Use when scaffolding a reusable workflow-helper (Slack/PR/release automations) or invoking a previously-created action. Stored at .geniro/actions/. Skip for editing core Geniro skills — use /improve-template for that."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion]
argument-hint: "[create|list|run|delete] [name] [...args]"
---

# Actions: Custom Workflow-Helper Management

Create, list, run, and delete custom workflow-helper actions stored as plain Markdown files at
`.geniro/actions/<slug>.md`. Use this skill to scaffold reusable team automations (Slack pings,
PR finalizers, release checklists) and to invoke them on demand. Core Geniro skills are NOT
editable here — use `/improve-template` for those.

## Sub-commands

| Sub-command | Aliases | Purpose |
|-------------|---------|---------|
| `list` | show, view, ls, current | Print the table of installed actions |
| `create` | new, scaffold, make, add | Interview-driven scaffold for a new action |
| `run` | invoke, exec, execute, do | Read an action file and follow its steps inline |
| `delete` | remove, rm, drop | Remove an action file (with confirmation) |

If `$ARGUMENTS` is empty, default to `list`.

## What is a custom action?

A **custom action** is a plain `.md` file at `.geniro/actions/<slug>.md`. Its frontmatter declares:

```yaml
---
name: <slug>
description: "Use when … (≤250 chars, starts with 'Use when')"
model: inherit | sonnet | opus
allowed-tools: [Read, Bash, ...]
argument-hint: "[optional usage hint]"
created: YYYY-MM-DD
created-by: geniro:actions
---
```

The body contains numbered steps that the orchestrator follows when the action is invoked.

**Important:** custom actions are NOT auto-registered as top-level slash commands. They live as
plain `.md` files (not as `<slug>/SKILL.md` subfolders) precisely so Claude Code does not pick
them up as their own slash commands. They are only reachable through `/geniro:actions run <name>`.

## Phase 0: Parse intent from `$ARGUMENTS`

**First — load custom instructions.** Load `.geniro/instructions/global.md` if present. Apply its **Rules** and **Constraints** sections throughout the run (e.g., naming conventions for action slugs, required allowed-tools restrictions, mandatory dry-run gates). Phase-specific "Additional Steps" entries may not have matching phases here — apply where they fit, otherwise skip.

Parse `$ARGUMENTS` to determine which sub-command runs and (optionally) which action is targeted.
NEVER output questions as plain text — always use the `AskUserQuestion` tool at every WAIT gate.

### Action detection

| Intent | Aliases | Maps to |
|--------|---------|---------|
| List | show, view, list, ls, current | `list` |
| Create | create, new, scaffold, make, add | `create` |
| Run | run, invoke, exec, execute, do | `run` |
| Delete | delete, remove, rm, drop | `delete` |

If `$ARGUMENTS` is empty, default to `list`.

### Name / query detection

The non-verb portion of `$ARGUMENTS` is parsed differently for `create` vs `run`/`delete`:

- **`create`** — the next non-verb token MUST be a kebab-case slug (lowercase letters, digits, hyphens; ≤64 chars; not a reserved word; no leading/trailing hyphen). Anything else fails the Phase 0 name-validation re-ask loop.
- **`run` and `delete`** — the non-verb remainder is treated as a **resolution input** that may be either:
  1. an exact kebab slug (e.g., `slack-release-ping`) — fast path, resolved by file-existence check; OR
  2. a free-text description (e.g., `"post release notes to slack"`, `finalize my pr`) — routed through Phase 4.0 "Resolve target" which matches against installed actions' (slug, description) pairs and confirms the chosen action via AskUserQuestion before any execution.

  An input is treated as a free-text description when it is multi-word, quoted, contains uppercase or whitespace, or fails the kebab regex. A single-token kebab input that does not resolve to an existing file also falls through to free-text matching (the user may have typed an approximate slug). Trailing positional arguments AFTER the resolved action name are still passed as extra context to Phase 4.4.

### Ambiguity resolution

If the action verb is unclear or missing (and the input was not empty), use the `AskUserQuestion`
tool:

- **Question:** "What would you like to do with custom actions?"
- **Options:**
  - label: "List" — description: "Show all installed custom actions"
  - label: "Create" — description: "Scaffold a new custom action"
  - label: "Run" — description: "Invoke an existing custom action"
  - label: "Delete" — description: "Remove a custom action file"

### Name validation (for `create` only)

When the resolved action is `create`, validate the name before continuing:

- Must be **kebab-case** (lowercase letters, digits, and hyphens only).
- Must be **≤64 characters**.
- Must NOT be a reserved word: `anthropic`, `claude`, `geniro`.
- Must NOT begin or end with a hyphen.

If the name is missing or invalid, use the `AskUserQuestion` tool:

- **Question:** "What should the action be named? (kebab-case, ≤64 chars, no reserved words)"
- **Options:**
  - label: "slack-release-ping" — description: "Example: post a release note to Slack"
  - label: "pr-finalize" — description: "Example: finalize and merge a PR"
  - label: "release-checklist" — description: "Example: walk a release checklist"
  - label: "Other" — description: "Provide your own kebab-case name"

Re-ask until a valid name is provided.

## Phase 1: Mode dispatch

Once `action` (and `name`, where applicable) are resolved, branch:

- `list` → Phase 2
- `create` → Phase 3
- `run` → Phase 4
- `delete` → Phase 5

## Phase 2: Command `list`

### Step 1: Scan directory

```bash
ls -la .geniro/actions/*.md 2>/dev/null
```

### Step 2: Present results

If the directory is missing or empty, print:

```
No custom actions found.

Run `/geniro:actions create <name>` to scaffold your first action,
e.g. `/geniro:actions create slack-release-ping`.
```

Otherwise, for each `.md` file under `.geniro/actions/`, Read the frontmatter and grep the
`description:` and `created:` lines. Present a markdown table:

```
## Custom Actions

| Name | Description | Created |
|------|-------------|---------|
| slack-release-ping | Use when posting a release note to #releases | 2026-04-12 |
| pr-finalize | Use when finalizing a PR before merge | 2026-04-18 |
```

Close with a hint: "Run with `/geniro:actions run <name>`."

## Phase 3: Command `create` (Mode 1)

### Phase 3.1: Pre-check

If `<name>` was not provided, use the `AskUserQuestion` tool from Phase 0's name-validation flow.

If `.geniro/actions/<name>.md` already exists, use the `AskUserQuestion` tool:

- **Question:** "`.geniro/actions/<name>.md` already exists. What do you want to do?"
- **Options:**
  - label: "Edit in place" — description: "Open the existing file and modify it directly"
  - label: "Version it" — description: "Rename existing to `<name>-v1.md`, then write a new `<name>.md`"
  - label: "Cancel" — description: "Leave the existing file untouched and stop"

On **Edit in place**: print the absolute path, instruct the user to edit it externally, then use the `AskUserQuestion` tool to wait for the user's "done" signal:

- **Question:** "Have you finished editing `<absolute-path>`?"
- **Options:**
  - label: "Done — re-run validation" — description: "Re-read the file and run the Phase 3.6 validation gate against the resulting content"
  - label: "Cancel" — description: "Stop without re-validating; leave the file as the user left it"

On **Done**, re-run the Phase 3.6 validation gate against the file. On **Cancel**, stop.

On **Version it**: `mv .geniro/actions/<name>.md .geniro/actions/<name>-v1.md`, then continue to
3.2.

On **Cancel**: stop.

### Phase 3.2: Ensure directory + gitignore

```bash
mkdir -p .geniro/actions
```

Then ensure `.gitignore` re-includes `.geniro/actions/` so the team can share actions via git:

```bash
# Remove bare `.geniro/` if present — it would block negation patterns below.
# (The setup skill does the same at its Phase 4.3 cleanup step.)
sed -i.bak '/^\.geniro\/$/d' .gitignore 2>/dev/null && rm -f .gitignore.bak

grep -q "^\.geniro/\*$" .gitignore 2>/dev/null || echo ".geniro/*" >> .gitignore
grep -q "^\!\.geniro/$" .gitignore 2>/dev/null || echo "!.geniro/" >> .gitignore
grep -q "^\!\.geniro/actions/$" .gitignore 2>/dev/null || echo "!.geniro/actions/" >> .gitignore
grep -q "^\!\.geniro/actions/\*\*$" .gitignore 2>/dev/null || echo "!.geniro/actions/**" >> .gitignore
```

This default keeps `.geniro/actions/` committed (so the team shares actions). Users who want
their actions ignored can manually remove the `!.geniro/actions/` lines.

### Phase 3.3: Interview (the four official skill-creator questions)

Use the `AskUserQuestion` tool for each question. Capture free-text answers via the "Other" /
"Custom" option where supported.

**Q1 — Purpose:** "What should this action do?"
- label: "Slack/messaging workflow" — description: "Post or react in a chat channel"
- label: "Pull-request workflow" — description: "Inspect, finalize, or merge a PR"
- label: "Release/deployment workflow" — description: "Run a release checklist or deploy step"
- label: "Custom workflow" — description: "Describe your own purpose"

**Q2 — When to trigger:** "When should this action be used? (think: what user phrases or situations)"
- label: "On user demand only" — description: "Only when the user invokes it explicitly"
- label: "When inspecting a PR" — description: "Tied to PR-review context"
- label: "Before a release" — description: "Tied to release-prep context"
- label: "Custom trigger context" — description: "Describe your own trigger"

**Q3 — Output / side-effects:** "What does it produce or change?"
- label: "Reports back to chat only" — description: "No file or external changes"
- label: "Writes a file" — description: "Creates or modifies a file in the repo"
- label: "Posts to an external system (Slack/GitHub/etc.)" — description: "Calls an external API"
- label: "Multiple side effects" — description: "Combination of the above"

**Q4 — Test cases (optional):** "Should we include a brief 'how to test it' note in the action?"
- label: "Yes — add 1–2 test cases" — description: "Include a short Test section in the body"
- label: "Skip" — description: "No test section"

### Phase 3.4: Draft preview

Read the template at `${CLAUDE_SKILL_DIR}/skill-template.md`, then synthesize a concrete action
body by filling in the answers from Phase 3.3:

- Frontmatter `name` = the kebab-case slug.
- Frontmatter `description` MUST start with "Use when" and reflect Q2's trigger context.
- Frontmatter `model: inherit` unless the interview clearly justifies opus.
- Frontmatter `allowed-tools` matches Q3's output (e.g., add scoped `Bash(<cmd> *)` only if the action shells out — see `example-actions/pr-notify-slack.md` for the pattern).
- Body sections: `## Overview`, `## Steps` (numbered), and `## Test` (only if Q4 = Yes).

**Show the drafted markdown to the user. Do NOT call Write yet.** Then use the `AskUserQuestion`
tool:

- **Question:** "Approve this draft?"
- **Options:**
  - label: "Approve and write" — description: "Write the file as previewed"
  - label: "Edit before writing" — description: "Describe changes; I'll re-show the draft"
  - label: "Cancel" — description: "Discard the draft and stop"

On **Edit before writing**: prompt for the specific changes (still via `AskUserQuestion` with an
"Other"/free-text option), apply them to the in-memory draft, then re-show. Cap at **3 edit
rounds** — after the third round, surface the unresolved difficulty and stop.

### Phase 3.5: Write the file

Use the Write tool to write `.geniro/actions/<name>.md`. The frontmatter MUST include:

- `created: <YYYY-MM-DD>` — today's date in ISO format.
- `created-by: geniro:actions`.

The body MUST NOT contain any `{{placeholder}}` strings — every placeholder from the template
must be resolved against the interview answers before Write is called.

### Phase 3.6: Validation gate

After Write, run these checks (orchestrator-side, no subagent). Refuse to mark complete if any
check fails:

1. **YAML frontmatter parses** — file starts with `---`, has a closing `---`, and the block in
   between is valid YAML.
2. **`name:` matches the filename slug exactly** (e.g., `slack-release-ping.md` → `name: slack-release-ping`).
3. **`description:` starts with "Use when"** (case-insensitive) and is **≤250 characters**.
4. **No `{{placeholder}}` substrings anywhere** in the file (`grep -n "{{" .geniro/actions/<name>.md`).
5. **File is <500 lines** (`wc -l .geniro/actions/<name>.md`).
6. **Body has at least one numbered step** — typically a `## Steps` section with numbered items.

If any check fails, surface the specific failure (which check, which line, what was expected),
delete the just-written file with `rm -f .geniro/actions/<name>.md`, and stop. Tell the user to
re-run `/geniro:actions create <name>` and refine the inputs in the Phase 3.4 preview round.
Do NOT auto-fix the written file — the synthesis happens in Phase 3.4 (where the user can
preview and edit), not in post-write patching.

After all six checks pass, print:

```
Created `.geniro/actions/<name>.md`. Run with `/geniro:actions run <name>`.
```

## Phase 4: Command `run` (Mode 2 — INLINE-ONLY for v1)

> v1 of this skill executes actions **inline only**. If an action declares `model: opus` or
> `context: fork` in its frontmatter, future versions may dispatch to a subagent — for now, the
> orchestrator follows the action steps directly in the current session.

### Phase 4.0: Resolve target by name-or-description (shared by `run` and `delete`)

Both `run` and `delete` call into this resolver before they touch any action file. The resolver returns three named values: `<resolved-path>` (absolute or repo-relative), `<resolved-slug>` (basename of `<resolved-path>` minus `.md`), and `<source>` (`local` or `main-worktree`). All downstream phases (4.2, 4.3, 4.5, 5.2, 5.3) consume `<resolved-slug>` for display/rm and `<resolved-path>` for Read. The resolver NEVER auto-executes — every selection passes through AskUserQuestion.

#### Step 1: Build the registry index

Glob `./.geniro/actions/*.md` to get the **local** registry. For each file, Read the frontmatter and extract `name` and `description`.

Detect worktree state:

```bash
git rev-parse --show-toplevel    # current worktree root
git worktree list --porcelain    # first `worktree <path>` entry is the main worktree
```

If the current `--show-toplevel` differs from the first `worktree` entry in the porcelain listing, the user is in a **linked worktree**. In that case, also Glob `<main-worktree-root>/.geniro/actions/*.md` and extract `name` + `description` for each. Tag each entry with `<source>` (`local` or `main-worktree`). When the same slug exists in both, **local wins** — drop the main-worktree entry from the candidate list.

If `git rev-parse` fails (not a git repo) or the porcelain listing has only one entry (single worktree), there is no main-worktree fallback — the registry is just `local`.

#### Step 2: Exact-slug fast path

If the user's input is a valid kebab slug AND an entry with `name == <input>` exists in the merged registry:

- **Source = local:** return `(<resolved-path>, <resolved-slug>, local)` immediately. No AskUserQuestion required.
- **Source = main-worktree, sub-command = `run`:** show a confirmation via AskUserQuestion before returning.
  - **Question:** "`<input>` was not found in this worktree's `.geniro/actions/`. The action `<input>` exists in the main worktree at `<main-worktree-root>/.geniro/actions/<input>.md`. Use it?"
  - **Options:**
    - label: "Use the main-worktree copy" — description: "Read the action from the main worktree (read-only). Execution still happens in this worktree."
    - label: "Cancel" — description: "Stop. The action is not available in this worktree."
  - On confirm, return `(<main-worktree-path>, <input>, main-worktree)`. On cancel, stop the whole sub-command.
- **Source = main-worktree, sub-command = `delete`:** skip the "Use the main-worktree copy?" gate (it's the wrong question for `delete`). Return `(<main-worktree-path>, <input>, main-worktree)` directly so Step 4 can fire the single source-aware refuse-and-surface gate.

#### Step 3: Free-text matching path

If Step 2 did not resolve (input is not a valid kebab slug, OR the input is a slug but no matching `name` exists in the merged registry), score every entry against the user's input by semantic fit between the input and the entry's `description` (and secondarily its `name`). The orchestrator does this scoring directly in-context — there is no external scorer.

Take the top **N=4** candidates by score. If the merged registry has fewer than 2 entries, skip the picker (≤1 candidate) and return immediately if there's exactly one match; if zero, print one of the following and stop:
- If the main-worktree fallback was checked (linked worktree, multiple worktrees in `git worktree list`): `No custom actions in this worktree's registry, and none in the main worktree's registry either. Run \`/geniro:actions create <name>\` first.`
- Otherwise (single worktree or `git rev-parse` failed): `No custom actions in registry. Run \`/geniro:actions create <name>\` first.`

Present an AskUserQuestion picker with up to 4 options (one per candidate):

- **Question:** "Which action did you mean by \"<input>\"?"
- **Options (one per candidate, in score order):**
  - label: `<slug>` — description: `<first 80 chars of the action's description, prefixed with "[main]" if source=main-worktree>`
- The 4th option (or sooner, if fewer than 3 strong candidates) MUST be:
  - label: "Other" — description: "Describe more specifically — re-prompt with a refined query"

When an "Other" option is selected, AskUserQuestion will surface free-text input from the user; treat that as a refined query and loop back into Step 3 with the new input. Cap the loop at **3 rounds**; after the third round, surface "Could not narrow down — try `/geniro:actions list` for the exact slugs" and stop.

**Cap-extension when >4 candidates:** if more than 4 candidates have non-trivial scores, chain a second AskUserQuestion call. Use the canonical chained-AskUserQuestion pattern from `skills/review/SKILL.md` Phase 4c — batch candidates into ≤4 per call, never drop or merge candidates to fit one question. The first question asks the user to narrow to a coarse group ("Which area?" with ≤4 grouped options); the second presents the ≤4 candidates inside the chosen group.

When the user picks a specific slug, return `(<resolved-path>, <resolved-slug>, <source>)`. If the chosen path's source is `main-worktree` AND the sub-command is `run`, fire the same Step 2 confirmation gate ("Use the main-worktree copy?") before returning. For `delete`, skip the confirmation here and let Step 4 handle the refuse-and-surface.

#### Step 4: Source-aware destructive-op guard (delete only)

For the `delete` sub-command, AFTER resolution, if `<source> == main-worktree`, do NOT proceed with the `rm`. Use AskUserQuestion:

- **Question:** "Action `<slug>` lives in the main worktree at `<main-worktree-root>/.geniro/actions/<slug>.md`. Deleting it from a linked worktree would modify a sibling tree. How do you want to proceed?"
- **Options:**
  - label: "Cancel — I'll switch to main and re-run" — description: "Stop. Switch to the main worktree (`cd <main-worktree-root>`) and re-run `/geniro:actions delete <slug>`."
  - label: "Cancel — keep the action" — description: "Stop without deleting."

Both options stop. There is no "delete from main anyway" option — that's the canonical scope-anchor behavior (sibling worktrees represent intentionally separate workstreams).

### Phase 4.1: Resolve target

Call **Phase 4.0** (resolve by name-or-description). Phase 4.0 handles the empty-input, exact-slug, free-text, and main-worktree-fallback cases — Phase 4.1 itself only consumes the returned `(<resolved-path>, <resolved-slug>, <source>)` tuple.

If `<source> == main-worktree`, the orchestrator has already confirmed the user wants to read the main-worktree copy in Phase 4.0 Step 2 (or Step 3's tail confirm). Phase 4.4 will execute INLINE in the current worktree using the action body loaded from `<resolved-path>`; no files in the main worktree are written.

### Phase 4.2: Read + parse

Read `<resolved-path>` (returned from Phase 4.0 — may be inside the current worktree's `.geniro/actions/` or, when `<source> == main-worktree`, the main worktree's path). Parse the frontmatter (`description`, `model`, `allowed-tools`, `argument-hint`, `created`). Hold the body steps in memory for Phase 4.4.

### Phase 4.3: Confirmation gate

Trigger this gate **only if any of the following are true**:

- The frontmatter `description` contains "Do NOT" or "destructive".
- The action's `allowed-tools` includes `Bash`.

When triggered, use the `AskUserQuestion` tool:

- **Question:** "About to run `<resolved-slug>` with these tools: [list]. Side-effecting operations may be triggered. Proceed?"
- **Options:**
  - label: "Run it" — description: "Execute the action steps now"
  - label: "Cancel" — description: "Don't run; stop here"

If the gate is not triggered (read-only action), skip directly to 4.4.

### Phase 4.4: Execute INLINE

Follow the action body's numbered steps directly as the orchestrator. The orchestrator is the
runtime — there is no subagent dispatch in v1. Pass any extra positional `$ARGUMENTS` (after the
action name) as input context, inlined into the action's prompt under a "User-supplied input"
heading the action steps can reference.

**Tool-scope contract.** BEFORE running any step, intersect the action's frontmatter `allowed-tools` with the orchestrator's own `allowed-tools` ONCE and identify every step whose required tools fall outside the intersection. If any gaps exist, surface them all in a single `AskUserQuestion` call before execution begins:

- **Question:** "The action declares <N> step(s) using tools outside this run's tool scope: [list step numbers + missing tools]. How should I proceed?"
- **Options:**
  - label: "Skip the affected steps and run the rest" — description: "Execute steps within scope; mark out-of-scope steps as skipped in the Phase 4.5 wrap-up"
  - label: "Cancel the run" — description: "Stop before any step executes"

If no gaps exist, proceed without asking. Do NOT call any tool the action did not declare in `allowed-tools`, and do NOT re-prompt mid-execution — the up-front gate is the only tool-scope WAIT point.

### Phase 4.5: Wrap-up

When the action completes, print a brief summary:

```
Action `<resolved-slug>` complete.

Steps run: <count>
Steps skipped: <list, or "none">  # populated when Phase 4.4's tool-scope gate dropped out-of-scope steps
Files changed: <list, or "none">
External calls: <list, or "none">
```

## Phase 5: Command `delete`

### Step 1: Resolve + source-guard

Call **Phase 4.0** (resolve by name-or-description). Phase 4.0's Step 4 enforces the source-aware destructive-op guard: if the resolved action lives in the main worktree (`<source> == main-worktree`), Phase 4.0 surfaces an AskUserQuestion that stops the run regardless of which option the user picks. Phase 5 only continues here when `<source> == local`.

### Step 2: Confirm

Use the `AskUserQuestion` tool:

- **Question:** "Delete `.geniro/actions/<resolved-slug>.md`? This cannot be undone unless the file is committed to git."
- **Options:**
  - label: "Delete the file" — description: "Permanently remove this action"
  - label: "Cancel" — description: "Keep the file unchanged"

### Step 3: Execute

If confirmed:

```bash
rm -f .geniro/actions/<resolved-slug>.md
```

If the directory is now empty, silently clean up:

```bash
rmdir .geniro/actions/ 2>/dev/null
```

Print: "Deleted `.geniro/actions/<resolved-slug>.md`."

## Anti-rationalization table

| Your reasoning | Why it's wrong |
|---|---|
| "I'll just edit a core Geniro skill instead of creating a custom action" | No — core skills are shipped globally and overwritten on update. Custom workflow helpers belong at `.geniro/actions/`. |
| "I'll silently overwrite the existing action file" | No — present edit/version/cancel via `AskUserQuestion`. Silent overwrite destroys committed work. |
| "I'll skip the description hygiene preview" | No — descriptions starting with "Use when" trigger reliably; vague descriptions break Mode 2 routing. |
| "The four interview questions are overkill for a small action" | No — they're the official skill-creator questions; even small actions need a clear purpose, trigger, and output documented in the file. |
| "I'll register the new action as `<slug>/SKILL.md` so it shows in the slash menu" | No — that defeats the entire design. Custom actions are reachable ONLY through `/geniro:actions run`. Plain `.md` files at `.geniro/actions/` do not register. |
| "I'll spawn a subagent to execute the action" | Not in v1 — Mode 2 is inline-only. Adding subagent dispatch is deferred until a real action proves it's needed. |
| "I'll output the questions as plain text instead of using `AskUserQuestion`" | No — every WAIT gate uses the `AskUserQuestion` tool. Plain text doesn't block. |
| "The `.gitignore` re-include lines are unnecessary if the user wants actions ignored" | No — default is committed (team-shareable). Users who want ignored can remove the re-include manually. Don't pre-decide for them. |
| "I'll auto-pick the highest-scoring fuzzy match without showing the user" | No — every free-text resolution passes through AskUserQuestion. The orchestrator owns judgment, not auto-pick. Silent fuzzy execution is the picker analog of performative agreement. |
| "I'll silently delete the action from the main worktree even though I'm in a linked worktree" | No — `delete` from a linked worktree refuses-and-surfaces. Sibling worktrees represent intentionally separate workstreams (see `skills/_shared/scope-anchor.md` § Anti-rationalization); the user must switch to main and re-run. |

## Definition of Done

- [ ] Intent parsed from `$ARGUMENTS` (or default to `list`)
- [ ] If `create`: 4-question interview completed, draft previewed and approved, file written, all 6 validation checks passed
- [ ] If `run`: action file located and read, confirmation gate (when needed), action steps executed inline
- [ ] If `delete`: confirmed via `AskUserQuestion` before removal
- [ ] All user interactions used `AskUserQuestion` — no plain-text questions
- [ ] `.gitignore` re-include rules added on first action created (idempotent)
- [ ] No `{{placeholder}}` left in any written file
- [ ] File written has frontmatter `created` and `created-by: geniro:actions`
- [ ] If `run`/`delete` received free-text input, Phase 4.0 resolved it via AskUserQuestion before any execution
- [ ] Worktree fallback for `run` consulted the main worktree only when local registry didn't resolve, and the loaded path was confirmed via AskUserQuestion before executing
- [ ] `delete` refused to remove actions from a sibling worktree (main-worktree source → refuse-and-surface)
