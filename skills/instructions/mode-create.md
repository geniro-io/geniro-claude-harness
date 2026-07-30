# Instructions — `create` mode

Mode body for `${CLAUDE_PLUGIN_ROOT}/skills/instructions/SKILL.md`. Read on Phase-1 dispatch to `create`. The spine keeps the scope set, the file shapes, the frontmatter reference, the invariants and the tool surface — this file carries the Steps.

---

### Step 1 — Check for existing file

```bash
cat "$PRIMARY_ROOT"/.geniro/instructions/<scope>.md 2>/dev/null
```

If file exists: AUQ "File exists — overwrite, edit instead, or cancel?". Branch accordingly.

### Step 2 — Ensure directory exists

```bash
mkdir -p "$PRIMARY_ROOT"/.geniro/instructions
mkdir -p "$PRIMARY_ROOT"/.geniro/instructions/review-extra # if scope == review-extra
```

### Step 3 — Gather project context

When the request does not already name a concrete rule, read enough of the project — CLAUDE.md, the build and test scripts, the linter and formatter configs — that Step 4's suggestions name this project's real tooling instead of placeholders.

### Step 4 — Scope-specific scaffold + interview

Each scope gets a **scope-specific scaffold** with example Rules to make the empty-file moment less confusing. The four scaffolds (`code-style` / `implement` / `global` / `memory`) plus their stub-inclusion notes live in `${CLAUDE_PLUGIN_ROOT}/skills/instructions/instructions-authoring-reference.md` §1 — render the matching scaffold first, always.

The interview is for requests that arrive vague. When the invocation already names an actionable rule ("add a rule that we run `pnpm test` before shipping"), place it in the scaffold under the block type §Block-type detection resolved and go straight to Step 5 — re-interviewing a user who already answered spends three questions to reach the line they handed over. Otherwise use `AskUserQuestion`:

- **Question:** "Add what kind of rules?"
- **Options (scope-tailored):** Documentation / Quality gates / Workflow steps / Free-form (Other path)

Capture 1-2 follow-up answers via additional AUQs. Convert vague user input into a specific criterion the model can weigh, per the rule-writing principles in `${CLAUDE_PLUGIN_ROOT}/skills/instructions/instructions-authoring-reference.md` §2 — name the command or path, and give the reason where the rule is one the model would otherwise talk itself out of (e.g. "make sure we test" → "Cover each new public function with a test; run `npm test` before shipping — CI reviews the last green run, not the working tree").

### Step 5 — Generate the file

Apply the writing principles in `${CLAUDE_PLUGIN_ROOT}/skills/instructions/instructions-authoring-reference.md` §2. Show preview via final AUQ `Write scaffold? | Edit body before writing | Cancel`. On `write`, route the file through `atomic_state_write` targeting `"$PRIMARY_ROOT"/.geniro/instructions/<scope>.md` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` — `.geniro/instructions/*` is a T3 persistent-CRUD path, so direct `Edit`/`Write` trips the state-helper enforcement hook.

### Step 6 — Confirm

Print:

```
Created `.geniro/instructions/<scope>.md`

This file will be loaded by <affected skills list> at the start of each run.
Edit via `/geniro:instructions edit <scope>`; lint via `/geniro:instructions validate`.
```

For `review-extra`, follow the slug-bearing flow in `${CLAUDE_PLUGIN_ROOT}/skills/instructions/instructions-review-extra.md`.
