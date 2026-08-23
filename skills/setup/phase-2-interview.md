# Setup Phase 2 — Interview

Phase file for `/geniro:setup`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md`.

### 2.1 Approvals precheck

Before opening any AUQ, read state frontmatter `approvals[]`. For each AUQ slot, check `category == <slot-name>`:

- If present and `picked != null` → reuse the prior answer; emit `## Phase log` line: "Reused prior answer for `<slot>`: `<picked>` (asked_in_phase: `<phase>`)". **No re-ask.**
- If absent → ask via `AskUserQuestion`; on answer, append to `approvals[]`.

`/geniro:setup` has no persistent preference categories. These are this skill's AUQ slots today — detection confirmation, the §2.3 ambiguity disambiguation, tracker selection, the §3.6 statusline confirm, and the onboard prompt — one-shot each, not a ceiling on future ones.

### 2.2 Confirm detection

Render the detection summary to a chat message before asking anything. It carries, in this order:

- **Tech Stack**, **Package Manager**, **Test Runner**, **Linter** — one line each, from the §1.4 evidence. A signal Detect could not resolve reads `unknown`; never fill it by inference.
- **Validation Commands** — the resolved build / test / lint / typecheck command, verbatim, one per line. Omit a command the project does not define rather than inventing one.
- **From project documentation** — the domain facts §1.4 extracted (purpose, entities, architecture) with the source files named. Omit this block entirely when `$PROJECT_KNOWLEDGE` is empty.

Then `AskUserQuestion`: `Looks correct` / `Adjust some things`. If adjust, ask specifically what to change.

### 2.3 Codebase confirmations (only if Detect was ambiguous)

E.g., "Detect saw `pyproject.toml` AND `requirements.txt` — primary package manager?" Skip Batch 2 entirely if no ambiguity.

### 2.4 Optional integrations — issue tracker

Use `AskUserQuestion` header "Tracker". The recommended default is whichever tracker Phase 1 detected (else Skip) — e.g. `.github/ISSUE_TEMPLATE/` signals GitHub Issues, a `.gitlab/` directory signals GitLab Issues, a Linear ID or URL in recent commit messages signals Linear.

- Per-tracker mapping (Linear, GitHub Issues, GitLab Issues, Jira, Bitbucket, Skip) — see `${CLAUDE_PLUGIN_ROOT}/skills/setup/workflow-templates/` for templates. The six options overflow the 4-option cap, so chain a follow-up question per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §"Cap-extension for >4 options" rather than dropping a tracker from the offer — e.g. lead with the detected default plus three others, then `Something else` opens the remaining trackers.

Record the pick as `$ISSUE_TRACKER_CHOICE` for Phase 3 and write nothing here: Interview is read-only (§ACI per-phase tool surface), and §3.3 installs the workflow file under the batch approval gate invariant #3 requires.

### 2.4b Optional integrations — OpenSpec

Fires only when Phase 1 detected OpenSpec (`$OPENSPEC_ROOT` non-empty). When absent, skip silently.

Use `AskUserQuestion` header "OpenSpec", question "This repo uses OpenSpec (at `$OPENSPEC_ROOT`). Have `/geniro:plan` duplicate approved plans into OpenSpec change proposals, and `/geniro:implement` archive them after ship?", options "Yes — add the OpenSpec steps" (Recommended) / "No — skip".

The OpenSpec procedure lives ENTIRELY in the project's own instruction files — the plugin's `/geniro:plan` and `/geniro:implement` stay tool-agnostic and just execute the user-authored `### After user-approve` / `### After ship` steps via their custom-step anchors.

Record the pick as `$OPENSPEC_CHOICE` for Phase 3 and write nothing here — §3.3 merges the template blocks under the batch approval gate.

### 2.5 Custom instructions

AUQ: "Create a custom `.geniro/instructions/global.md` for project-wide workflow rules?" Default: no (avoid clutter). Users can run `/geniro:instructions create global` later. `global.md` also hosts the cross-skill `### After worktree-setup` step, if the project needs a per-worktree bootstrap (e.g. building a per-worktree code index for an MCP) to run whenever a skill creates a new worktree.

Transition to Phase 3.

