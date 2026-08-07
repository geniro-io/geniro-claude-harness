# Actions — `create` sub-command (Phase 3)

Sub-command body for `${CLAUDE_PLUGIN_ROOT}/skills/actions/SKILL.md`. Read on Phase-1 dispatch to `create`. The spine keeps the invariants, the anti-rationalization table, the tool surface and the termination mapping — this file carries the Steps.

## Phase 3: `create` sub-command

### Step 1 — Pre-check

If `<name>` was not provided, use the name-validation flow from SKILL.md Phase 1.

Resolve `PRIMARY_ROOT` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A, re-running the snippet in every Bash call that uses the variable (Mode A owns the recompute-per-call rule). Actions are cross-session content, so every create-path write below is `"$PRIMARY_ROOT"`-prefixed — a cwd-relative write from a linked worktree is destroyed on `git worktree remove`.

If `"$PRIMARY_ROOT"/.geniro/actions/<name>.md` already exists, AUQ:

- **Question:** "`<resolved path>` already exists. What do you want to do?"
- **Options:**
- `Edit in place` — Open the existing file and modify it directly
- `Version it` — Rename existing to `<name>-v1.md`, then write a new `<name>.md`
- `Cancel` — Leave the existing file untouched

On **Edit in place**: route to Phase 5 (which handles external-editor flow with `edit-in-place` entry mode).

On **Version it**: `mv "$PRIMARY_ROOT"/.geniro/actions/<name>.md "$PRIMARY_ROOT"/.geniro/actions/<name>-v1.md`, then continue to Step 2.

On **Cancel**: stop.

### Step 2 — Ensure directory + gitignore

```bash
mkdir -p "$PRIMARY_ROOT"/.geniro/actions
```

Then apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gitignore-negation.md` with `actions` as its directory list — the directory that must stay committed. It drops a bare `.geniro/` line if present (that line would ignore the whole tree and defeat every negation), then idempotently appends `.geniro/*`, `!.geniro/`, `!.geniro/actions/`, and `!.geniro/actions/**`.

This default keeps `.geniro/actions/` committed (team-shareable). The negation must live in `"$PRIMARY_ROOT"/.gitignore`, beside where the action file is written. Users who want their actions ignored remove the two `!.geniro/actions/` lines by hand.

### Step 3 — Interview (Q1–Q4)

Use `AskUserQuestion` for each question. Q1–Q3 capture purpose, trigger, and output; **Q4 captures risk class**.

**Q1 — Purpose:** "What should this action do?"
- `Slack/messaging workflow`, `Pull-request workflow`, `Release/deployment workflow`, `Custom workflow`

**Q2 — When to trigger:** "When should this action be used?"
- `On user demand only`, `When inspecting a PR`, `Before a release`, `Custom trigger context`

**Q3 — Output / side-effects:** "What does it produce or change?"
- `Reports back to chat only`, `Writes a file`, `Posts to an external system`, `Multiple side effects`

**Q4 — Risk class:** "What is the risk class for this action?" (`risk_class` labels blast radius for the listing, the delete warning, and lint; it is not a run gate — Phase 4.2.)
- `low` — Pure read operations: read files, list dirs, aggregate data, display info. No network, no file mutation outside cwd.
- `medium` — Local file mutation, git commit (no push), tests with side effects (DB seed, integration test). External reads (HTTP GET).
- `high` — External sends (Slack/PR/email), git push, npm publish, docker push, cloud mutations, file deletion outside `.geniro/`.

**Recommended option (per scaffold heuristic, based on Q3):**

- Q3 = "Reports back to chat only" → suggest `low`
- Q3 = "Writes a file" → suggest `medium`
- Q3 = "Posts to an external system" → suggest `high`
- Q3 = "Multiple side effects" → suggest `high`

### Step 4 — Draft preview

Read the template at `${CLAUDE_PLUGIN_ROOT}/skills/actions/skill-template.md`; when the interview answers leave the shape thin, read `${CLAUDE_PLUGIN_ROOT}/skills/actions/example-actions/pr-notify-slack.md` alongside it as a worked example of a finished action file. Then synthesize a concrete action body by filling in answers from Step 3:

- Frontmatter `name` = the kebab-case slug.
- Frontmatter `description` reflects Q2's trigger context and follows the description rule in the template's §Authoring rules.
- Frontmatter `risk_class:` = Q4's answer (REQUIRED).
- Frontmatter `model: inherit` unless the interview clearly justifies opus.
- Frontmatter `allowed-tools:` matches Q3's output.
- Frontmatter `argument-hint:` names the positional args the Steps reference (e.g. `[pr_number]`); use `""` when the action takes none.
- Frontmatter `external-send: true` if Q3 = "Posts to an external system" or "Multiple side effects" with external.
- Body sections follow the template exactly: `# {{name}}` (H1 title), `## When to use`, `## When NOT to use` (omit if the action has no skip conditions), `## Steps` (numbered), `## Output`, `## Test cases` (1–2 checks that confirm the run worked).

**Show the drafted markdown to the user. Do NOT call Write yet.** Then AUQ:

- **Question:** "Approve this draft?"
- **Options:**
- `Approve and write` — Write the file as previewed
- `Edit before writing` — Describe changes; I'll re-show the draft
- `Cancel` — Discard and stop

On `Edit before writing`: capture specific changes via `AskUserQuestion` (free-text via "Other"), apply, re-show. Cap at **3 edit rounds**.

### Step 5 — Write the file

Route the file through `atomic_state_write` to `"$PRIMARY_ROOT"/.geniro/actions/<name>.md` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` — `.geniro/actions/*` is a T3 persistent-CRUD path, so direct `Edit`/`Write` trips the state-helper enforcement hook. Apply the §Caller-side mtime check before the write (`create` is the initial-write branch — target absent at read time and write time, so no conflict; `edit-in-place` catches concurrent modification). Frontmatter must include `created: <YYYY-MM-DD>` (today) and `created-by: geniro:actions`.

### Step 6 — Validation gate

Run the validation gate in `${CLAUDE_PLUGIN_ROOT}/skills/actions/actions-reference.md` §Validation gate with **entry mode = `create`**, and follow its verdict handling.

On a clean verdict, print: `Created \`.geniro/actions/<name>.md\`. Run with \`/geniro:actions run <name>\`.` When `$PRIMARY_ROOT` is not the current directory, show the resolved absolute path instead and append: "Written to the main repo checkout, so it survives if this worktree is removed."
