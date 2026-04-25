---
name: geniro:actions
description: "Create and invoke custom workflow-helper actions stored at .geniro/actions/. Use when you want to scaffold a reusable workflow (Slack/PR/release automations) or run a previously-created action. Do NOT use for editing core Geniro skills — use /improve-template for that."
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

### Name detection

Any non-action token after the action verb is treated as the action name (kebab-case). Example:
`/geniro:actions create slack-release-ping` → `action=create, name=slack-release-ping`. Trailing
positional arguments after the name (e.g., `run my-action arg1 arg2`) are passed to Phase 4 as
extra context.

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

On **Edit in place**: print the absolute path, instruct the user to edit it, then re-run the
Phase 3.6 validation gate against the resulting file. Do not proceed past validation until the
user signals they're done.

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

### Phase 4.1: Resolve target

If `<name>` was not provided, scan `.geniro/actions/*.md` (same Glob as Phase 2) and use the
`AskUserQuestion` tool with one option per file (label = action name, description = the action's
`description` field):

- **Question:** "Which action do you want to run?"
- **Options:** one label per existing action (with its description as the option description).

If `.geniro/actions/<name>.md` does not exist, print:

```
Action `<name>` not found. Available: <comma-separated list>.
```

…and stop.

### Phase 4.2: Read + parse

Read `.geniro/actions/<name>.md`. Parse the frontmatter (`description`, `model`, `allowed-tools`,
`argument-hint`, `created`). Hold the body steps in memory for Phase 4.4.

### Phase 4.3: Confirmation gate

Trigger this gate **only if any of the following are true**:

- The frontmatter `description` contains "Do NOT" or "destructive".
- The action's `allowed-tools` includes `Bash`.

When triggered, use the `AskUserQuestion` tool:

- **Question:** "About to run `<name>` with these tools: [list]. Side-effecting operations may be triggered. Proceed?"
- **Options:**
  - label: "Run it" — description: "Execute the action steps now"
  - label: "Cancel" — description: "Don't run; stop here"

If the gate is not triggered (read-only action), skip directly to 4.4.

### Phase 4.4: Execute INLINE

Follow the action body's numbered steps directly as the orchestrator. The orchestrator is the
runtime — there is no subagent dispatch in v1. Pass any extra positional `$ARGUMENTS` (after the
action name) as input context, inlined into the action's prompt under a "User-supplied input"
heading the action steps can reference.

**Tool-scope contract.** Before executing each step, intersect the action's frontmatter
`allowed-tools` with the orchestrator's own `allowed-tools`. Refuse any step that would call a
tool outside that intersection — surface the gap via the `AskUserQuestion` tool with options
"Skip this step" / "Cancel the run". Do NOT silently call tools the action did not declare.

### Phase 4.5: Wrap-up

When the action completes, print a brief summary:

```
Action `<name>` complete.

Steps run: <count>
Files changed: <list, or "none">
External calls: <list, or "none">
```

## Phase 5: Command `delete`

### Step 1: Confirm

Use the `AskUserQuestion` tool:

- **Question:** "Delete `.geniro/actions/<name>.md`? This cannot be undone unless the file is committed to git."
- **Options:**
  - label: "Delete the file" — description: "Permanently remove this action"
  - label: "Cancel" — description: "Keep the file unchanged"

### Step 2: Execute

If confirmed:

```bash
rm -f .geniro/actions/<name>.md
```

If the directory is now empty, silently clean up:

```bash
rmdir .geniro/actions/ 2>/dev/null
```

Print: "Deleted `.geniro/actions/<name>.md`."

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

## Definition of Done

- [ ] Intent parsed from `$ARGUMENTS` (or default to `list`)
- [ ] If `create`: 4-question interview completed, draft previewed and approved, file written, all 6 validation checks passed
- [ ] If `run`: action file located and read, confirmation gate (when needed), action steps executed inline
- [ ] If `delete`: confirmed via `AskUserQuestion` before removal
- [ ] All user interactions used `AskUserQuestion` — no plain-text questions
- [ ] `.gitignore` re-include rules added on first action created (idempotent)
- [ ] No `{{placeholder}}` left in any written file
- [ ] File written has frontmatter `created` and `created-by: geniro:actions`
