---
name: actions
description: "Use when scaffolding a reusable workflow-helper (Slack/PR/release automations) or invoking a previously-created action. Stored at .geniro/actions/. Run-mode executes the action directly — invoking it is the authorization, so no confirmation is asked. Skip for editing core Geniro skills — edit the plugin repo directly."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion]
argument-hint: "[list|create|edit|run|delete|validate] [name] [...args]"
---

# Actions: custom workflow-helper management

## Contents

- Sub-commands — the verb → phase map
- What is a custom action?
- Loop invariants
- Anti-rationalization
- Definition of done
- Budgets — quality-first
- ACI per-phase tool surface
- Memory I/O
- Termination case → state mapping
- Phase 1 — parse intent
- Phases 2-7 — one pointer per sub-command (`list` / `create` / `run` / `edit` / `delete` / `validate`); the bodies live in sibling files
- Cross-references

---

Stateless loop: **Parse → Execute → Done**. Execute branches into exactly one of six sub-commands, so a run passes through Phase 1, one sub-command body, and the terminal report. CRUD frontend + runner over `.geniro/actions/` — user-authored workflow-helper actions stored as plain Markdown files. Six operations: `list`, `create`, `edit`, `run`, `delete`, `validate`.

**Sub-command bodies.** Each sub-command's Steps live in `${CLAUDE_PLUGIN_ROOT}/skills/actions/subcommand-<verb>.md`. Read the one Phase 1 dispatches to — the five it did not dispatch to are never read. Two procedures more than one sub-command needs are shared in `${CLAUDE_PLUGIN_ROOT}/skills/actions/actions-reference.md`: §Target resolution (which action file to operate on) and §Validation gate (the create/validate checks).

**Runtime portability.** `${CLAUDE_PLUGIN_ROOT}` is set by Claude Code. When it is unset (another Agent-Skills runtime, e.g. Cursor), resolve it before following any reference: the plugin root is the ancestor directory of this file containing `.claude-plugin/plugin.json` — substitute it for every `${CLAUDE_PLUGIN_ROOT}` occurrence and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. Tool and hook substitutions for non-Claude-Code runtimes: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md`.

**After a compaction, re-Read the dispatched sub-command's body file before continuing it** — only a skill's front-loaded prefix is re-attached after a summary, so a mid-run summary can drop the Steps while leaving this spine intact. Re-Read the one file rather than re-invoking the skill; there is no state file here, so if which sub-command was running is also gone, re-resolve from Phase 1.

## Sub-commands

| Sub-command | Phase | Aliases | Purpose |
|-------------|-------|---------|---------|
| `list` | 2 | show, view, ls, current | Print the table of installed actions |
| `create` | 3 | new, scaffold, make, add | Interview-driven scaffold for a new action |
| `run` | 4 | invoke, exec, execute, do | Read an action file and follow its steps inline (no run-confirmation gate — Phase 4.2) |
| `edit` | 5 | change, modify, update, tweak, adjust | Open an existing action for external editing, then re-validate |
| `delete` | 6 | remove, rm, drop | Remove an action file (with confirmation) |
| `validate` | 7 | check, lint | Lint frontmatter and body against the rule set |

## What is a custom action?

A `.md` file at `.geniro/actions/<slug>.md` with YAML frontmatter declaring `name`, `description`, `risk_class`, and a body containing a numbered `## Steps` section. The orchestrator (Geniro) reads the body and follows the steps. Actions are NOT auto-registered as slash commands — they live as plain `.md` files (not as `<slug>/SKILL.md` subfolders) precisely so Claude Code does not pick them up as their own slash commands. They are only reachable through `/geniro:actions run <name>`.

## Loop invariants

The canonical agent-loop invariants in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` apply throughout /geniro:actions, with four skill-specific notes (an `#N` inside a note points at that file's numbered list):

1. **Inline execution** — `/geniro:actions` runs entirely in the orchestrator; no subagents are spawned in any mode.
2. **Invariant #2 (args validated)** — every write is previewed as a draft and gated by a frontmatter-validation step (the `create` path validates at its validation gate, just after the draft is written).
3. **Invoking authorizes execution** — this replaces invariant #3 (permission before side-effect) on the `run` path only: `run` fires the action's steps directly regardless of `risk_class` (Phase 4.2). Five WAIT points survive, because none of them re-asks "are you sure you want to run this?": the cross-worktree confirmation (§Target resolution Step 2 — "use the copy from another worktree?"), the free-text picker (§Target resolution Step 3 — "which action?"), the tool-scope gap AUQ (Phase 4.3 — a step needs a tool outside the allowlist intersection), the one-time scope checkpoint when the run edits outside what the action declares (Phase 4.3), and any `[AUQ]`/`## Confirm:` checkpoint the action author placed inside the body. `create` / `edit` / `delete` stay AUQ-gated under #3.
4. **Invariant #7 (errors → structured observations)** — there is no state file here, so errors surface inline in the final message.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll just edit a core Geniro skill instead of creating a custom action" | No — core skills are shipped globally and overwritten on update. Custom workflow helpers belong at `.geniro/actions/`. |
| "I'll silently overwrite the existing action file" | No — for `create` on an existing slug, present edit/version/cancel via AUQ. For top-level `edit`, route through Phase 5. Silent overwrite destroys committed work. |
| "I'll skip the description hygiene preview" | No — descriptions starting with "Use when" trigger reliably. |
| "The four interview questions are overkill for a small action" | No — they capture the things every action needs documented regardless of size: purpose, trigger, output, and risk class. |
| "I'll register the new action as `<slug>/SKILL.md` so it shows in the slash menu" | No — that defeats the entire design. Custom actions are reachable ONLY through `/geniro:actions run`. |
| "I'll spawn a subagent to execute the action" | No — Phase 4 runs inline; the orchestrator is the runtime. |
| "I'll auto-pick `risk_class: low` if I can't tell" | No — Q4 is mandatory. The scaffold heuristic suggests a value based on Q3, but the user must confirm or pick differently. |
| "This action is high-risk (git push / Slack send), so I'll add a confirmation before running it to be safe" | No — invoking `/geniro:actions run <slug>` IS the authorization; an "are you sure?" AUQ re-asks a decision the user already made. Action-author `[AUQ]`/`## Confirm:` checkpoints inside the body are different — those are the author's deliberate in-step pauses; honor them. |
| "Invoking is the authorization, so this scope checkpoint is the confirmation gate that rule forbids." | Invocation removes the gate on the decision the user already made — running this action. The scope checkpoint reports something the user could not have known at invocation: the run outgrew what the action describes. New information, new decision. |
| "I'll auto-elevate risk_class to `high` if `allowed-tools:` contains `Bash(curl)`" | No — manual is fine. The validate-mode lint catches `external-send: true ⇒ risk_class: medium|high`. Auto-elevation would surprise users. |
| "I'll auto-pick the highest-scoring fuzzy match without showing the user" | No — every free-text resolution passes through AskUserQuestion. |
| "I'll re-use the validation gate's `rm -f` failure behavior unconditionally" | No — failure path is parametric on **entry mode**. `create` → `rm -f` rollback is correct because the file didn't exist. `edit-in-place` → leave the file. |
| "I'm in a linked worktree, so I'll refuse to edit/delete the main repo's copy of an action" | No — the main repo checkout is the canonical home of actions (`create` writes there); refusing would break the create→edit flow from a worktree. Local branch copies stay respected at read/run time (local wins); CRUD targets the canonical copy, asking only when both copies exist and differ. |

## Definition of done

Load-bearing exit gates — per-command mechanics live in their phase sections.

- [ ] Every user interaction used `AskUserQuestion`; destructive ops (`delete`, and overwrite on `create`) confirmed via AUQ before running.
- [ ] Writes to `.geniro/actions/` routed through `atomic_state_write` (T3 persistent-CRUD path); no `{{placeholder}}` left in any written file.
- [ ] `create` and `edit` ran `validate_action_file` and cleared it (or applied the entry-mode rollback); `validate` exited non-zero on any CRITICAL/HIGH.
- [ ] `run` executed inline with no run-confirmation gate (Phase 4.2), within the action's tool-scope intersection; the scope checkpoint fired (once) if the run edited outside what the action declares; L2 `discovery` emit fired on a successful `external-send: true` run.
- [ ] `.gitignore` re-include rules added on first action created (idempotent).

## Budgets — quality-first

No hard kill caps — the quality-first doctrine in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §"Budgets — quality-first (canonical)" applies. Soft gates: 3-retry slug ambiguity → abort, 3-retry on create-validation failure. Architecture constraints: one action runs at a time (assumed sequential).

## ACI per-phase tool surface

| Phase | Allowed tools | Forbidden tools |
|---|---|---|
| `parse` | `Read`, `Bash` (read-only), `Glob`, `AskUserQuestion` | `Write`, `Edit`, mutating `Bash`, `Agent` |
| `execute` (list) | `Read`, `Glob`, `Bash(ls...)`, `AskUserQuestion` | `Write`, `Edit`, `Agent`, `mcp__*` |
| `execute` (create) | `Read`, `Bash(atomic_state_write, mkdir -p "$PRIMARY_ROOT"/.geniro/actions/, the .gitignore re-include procedure, mv)`, `AskUserQuestion` | `Write`, `Edit`, `mcp__github__*`, network egress, `Agent` |
| `execute` (edit) | `Read`, `Bash(atomic_state_write, stat, cp, mv, rm -f *.pre-edit.bak)`, `AskUserQuestion` | `Write`, `Edit`, `mcp__*`, network egress |
| `execute` (delete) | `Read`, `Bash(rm)`, `AskUserQuestion` | `Write`, `Edit`, all `mcp__*`, network egress |
| `execute` (run) | **Intersection of /geniro:actions allowed-tools AND action frontmatter `allowed-tools:`** | (whatever is NOT in the intersection) |
| `execute` (validate) | `Read`, `Glob`, `Bash(grep -n, wc)`, `AskUserQuestion` | `Write`, `Edit`, `Agent`, `mcp__*` |
| `done` | (terminal report) | (none) |

**Run mode tool gating:** Phase 4.3 intersects the action's frontmatter `allowed-tools:` with this skill's own before any step runs.

Action frontmatter MAY include tools outside `/geniro:actions`' own `allowed-tools:` (e.g. `mcp__github__*`); those never fall inside the run-mode intersection above, so a step needing them surfaces at the tool-scope gap AUQ (Phase 4.3) — skipped or the run cancelled — never executed automatically under the no-confirm contract.

## Memory I/O

`.geniro/actions/*.md` is NOT a memory layer — it's executable workflow content. The 4 memory layers do not include actions.

| Layer | Read | Write | Notes |
|---|---|---|---|
| L2 learnings.jsonl | not read in CRUD modes | written in run mode if `external-send: true` and success (Phase 4.4) | One `discovery` row per external-send run |
| L4 `.geniro/instructions/*.md` | not read by `/geniro:actions` itself | not written | `/geniro:instructions` owns this surface |
| Actions (`.geniro/actions/*.md`) | read in all modes | written in create/edit | T3 PERSISTENT/CRUD — NOT part of the memory model |

## Termination case → state mapping

| Cause | Message format |
|---|---|
| Scope checkpoint (Phase 4.3) — user picked "Stop here, keep what's changed" | `aborted: stopped at scope checkpoint after step <N>`; edits stay in place and the Phase 4.4 summary, with its `/geniro:review` recommendation, prints before the transition |
| User cancelled at any question other than the scope checkpoint above | `aborted: user cancelled at <step>` |
| Slug resolution failed after 3 rounds of asking | `aborted: slug unresolved after 3 rounds of asking` |
| Validation rejected on create (frontmatter missing required field) | `aborted: create blocked by validation — <reason>` |
| Action body execution failed mid-step | `failed: action <slug> step <N> returned non-zero exit` |
| Write blocked by file-protection hook | `aborted: file-protection hook blocked write to <path>` |
| Validate found CRITICAL/HIGH issues | exit non-zero with `validate: <slug> failed — N CRITICAL, M HIGH` |

## Phase 1: Parse intent from `$ARGUMENTS`

**Step 0 — Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: actions`, `LOAD_TIER: rules-only`, `MODE: initial-load`. The helper's §Procedure prescribes an imperative `Read` of `global.md`; its §Echo contract requires one observable line. Both are mandatory.

Parse `$ARGUMENTS` to determine which sub-command runs and (optionally) which action is targeted. Surface every WAIT gate through the `AskUserQuestion` tool, not plain-text questions — plain-text prompts aren't gated and the run can proceed without an answer.

### Action detection

Map the verb token in `$ARGUMENTS` to a sub-command via the alias table in §Sub-commands above — that table is the single copy; the sub-command's own name matches as well as its aliases.

If `$ARGUMENTS` is empty, default to `list`.

### Name / query detection

The non-verb portion of `$ARGUMENTS` is parsed differently for `create` vs `run`/`delete`/`validate`:

- **`create`** — the next non-verb token must be a slug satisfying §Name validation below (the single home for the slug rules).
- **`run`, `delete`, `validate`** — the non-verb remainder is treated as a **resolution input** that may be either an exact kebab slug (fast path) or a free-text description (routed through `${CLAUDE_PLUGIN_ROOT}/skills/actions/actions-reference.md` §Target resolution).

### Ambiguity resolution

**Bare-slug fast path.** If `$ARGUMENTS` is non-empty AND no recognized verb was detected AND the entire `$ARGUMENTS` exact-matches an existing action file (literal or kebab-normalized: `daily recap` → `daily-recap`), default to `run` with that resolved slug. Typing a known slug IS the answer to "what do you want to do?"; re-asking would violate "skip questions already answered". The cross-worktree confirmation in §Target resolution Step 2 still fires.

**Otherwise** AUQ the verb:

- **Question:** "What would you like to do with custom actions?"
- **Options:** `List` / `Create` / `Run` / `Something else` — the six sub-commands overflow the 4-option cap, so chain a follow-up question per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §"Cap-extension for >4 options" rather than dropping a sub-command from the offer. On `Something else`, fire the second question with `Delete` / `Edit` / `Validate`.

### Name validation (for `create` only)

- kebab-case (lowercase letters, digits, hyphens only)
- ≤64 characters
- NOT a reserved word: `anthropic`, `claude`, `geniro`, `list`, `create`, `edit`, `run`, `delete`, `validate`
- No leading/trailing hyphen

Re-ask up to 3 times via AskUserQuestion until valid.

### Dispatch

Once the sub-command is resolved, **Read that sub-command's body file** — `${CLAUDE_PLUGIN_ROOT}/skills/actions/subcommand-<verb>.md`, named in its phase section below — and follow it. Read it again on any resumption of the run, including after a compaction: the Steps are not in this file, so a run that skips the Read has nothing to execute. Read only the one dispatched to.

That Read comes before any step of the sub-command and carries a one-line echo, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — the dispatched body is this run's phase body, and it holds every pause this skill has. `run` is where that matters most: the sub-command deliberately skips the invocation confirmation, so the tool-scope-gap question and the scope checkpoint inside `subcommand-run.md` are the whole distance between invoking an action and arbitrary side effects. `delete` holds the destructive-op confirmation, and the deletion hook permits a per-file `rm -f` on `.geniro/actions/<slug>.md`, so nothing else stops it. A further file a sub-command body defers to — `actions-reference.md` §Target resolution, §Validation gate — is bound by the same contract.

## Phase 2: `list` sub-command

**On dispatch, Read `${CLAUDE_PLUGIN_ROOT}/skills/actions/subcommand-list.md`** — it carries the Steps: build the shared registry index, then print the installed-actions table.

## Phase 3: `create` sub-command

**On dispatch, Read `${CLAUDE_PLUGIN_ROOT}/skills/actions/subcommand-create.md`** — it carries the Steps: pre-check and existing-file branch, directory + `.gitignore` negation, the four interview questions, the draft preview, the `atomic_state_write`, and the validation gate.

## Phase 4: `run` sub-command

**On dispatch, Read `${CLAUDE_PLUGIN_ROOT}/skills/actions/subcommand-run.md`** — it carries the Steps: §4.1 resolve/read/parse, §4.2 the no-run-confirmation contract, §4.3 inline execution under the tool-scope intersection and the scope checkpoint, §4.4 wrap-up and the L2 emit. Every `Phase 4.M` citation in this skill resolves there.

## Phase 5: `edit` sub-command

**On dispatch, Read `${CLAUDE_PLUGIN_ROOT}/skills/actions/subcommand-edit.md`** — it carries the Steps: resolve the canonical copy, snapshot and hand off to an external editor, then re-validate with `edit-in-place` entry mode.

## Phase 6: `delete` sub-command

**On dispatch, Read `${CLAUDE_PLUGIN_ROOT}/skills/actions/subcommand-delete.md`** — it carries the Steps: resolve which copy, the destructive-op confirmation with its high-risk warning, and the per-file `rm -f`.

## Phase 7: `validate` sub-command

**On dispatch, Read `${CLAUDE_PLUGIN_ROOT}/skills/actions/subcommand-validate.md`** — it carries the Steps: resolve scope (single file or the whole deduped registry), run the shared validation gate per file plus the validate-only rows, and print the report. Read-only; never mutates.

## Cross-references

- PERSISTENT (CRUD) — `.geniro/actions/` tier; write via `atomic_state_write` with the caller-side optimistic mtime check per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md`
- L2 emit triggers — `discovery` emit on external-send actions (Phase 4.4)
- `.gitignore` re-include — `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gitignore-negation.md`, applied at Phase 3 Step 2 so `.geniro/actions/` stays committed

