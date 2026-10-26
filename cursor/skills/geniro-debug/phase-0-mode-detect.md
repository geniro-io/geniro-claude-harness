<!-- Generated from skills/debug/phase-0-mode-detect.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Debug Phase 0 — mode detection

## Contents

- Step 0.1 — Entry-time working-tree baseline
- Step 0.2 — Workspace
- Step 0.3 — Load custom instructions
- Step 0.4 — Branch freshness
- $ARGUMENTS routing
- Anchored verify-keyword signals
- Approvals-persistence protocol
- Step 0.5 — Create state.md
- Tool surface

Phase file for `/geniro:debug`. The spine — invariants, budgets, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md`.

state.md `phase: mode-detect`. Exits when the mode is picked and persisted to `approvals[]`: Scientific → `phase: investigate`, Adversarial → `phase: adversarial-mode-detect`.

**Step 0.1 — Entry-time working-tree baseline.** On a fresh run (skip on compaction-resume — the baseline already lives in state.md), before Step 0.2 evaluates the workspace decision, run `git status --porcelain` from the worktree root and capture its changed-path list — Step 0.2's recommendation reads it. Hold the captured list in working memory rather than writing it here: debug keys `.geniro/state/debug/<slug>/` to the branch (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Slug rules), and Step 0.2 is what may change the branch, so a write here would land under the slug this run is about to leave. Step 0.5 persists `baseline-dirty-paths`. Phase 3 §3.1's working-tree check subtracts this baseline — Adversarial Mode's ship path never reads it.

**Step 0.2 — Workspace.** Passive-detect first, ask only when ambiguous. Collect `IN_WORKTREE` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-signals.md`, then apply this decision tree (first match wins):

```
1. Compaction-resume, or a resumable state.md exists for this slug
   ⇒ SKIP the question — this run's workspace was already decided earlier. Re-apply
     the recorded workspace from state.md `branch:` / `worktree:` per
     `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md`
     § Mismatch handling (Case A/B/C) — never an auto-executed git operation.

2. IN_WORKTREE == true
   ⇒ SKIP the question — the run already sits in an isolated worktree, so no answer
     could change where it runs. AUTO-CONTINUE here. Echo:
       "Debugging in worktree '<dir>' on '<branch>'."

3. IN_WORKTREE == false
   ⇒ Fire the workspace question (Mode INSPECT-HERE).
```

Rule 3 fires `AskQuestion` (header `"Workspace"`) with options from the catalogue in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-chooser.md` §2, applied per that file's §4 Mode INSPECT-HERE. This call fires at Step 0.2, ahead of every later step, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-chooser.md` §6. When `$ARGUMENTS` is empty, the same call also carries Mode — one round-trip beats two, and the branch on this path falls back to the short-SHA slug (Workspace slug, below), since no description exists yet.

- **"Debug here on '<branch>'"** (`current-branch`) — investigate in place; the reproduction test and any tagged debug logging land on `<branch>`.
- **"Isolated worktree at this commit"** (`worktree`) — cut at `HEAD` into `.claude/worktrees/debug-<desc-slug>/` (bound in Workspace slug, below), then enter the worktree, leaving the current checkout on its branch. A worktree checks out that branch fresh, so any uncommitted work stays behind in the current checkout — and that work is often the very thing being debugged. After the `git worktree add`, before any subagent spawn, run the project's `### After worktree-setup` step per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md` §3.1 — the guaranteed per-worktree bootstrap execution site.
- **"New branch at this commit"** (`new-branch`) — cut at `HEAD` in the current checkout, carrying uncommitted work along and moving the checkout off the branch it started on.

Recommend exactly one label per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-chooser.md` §5: the worktree when `baseline-dirty-paths` is empty, the new branch when it is dirty.

`$ARGUMENTS` modifiers `current-branch` / `here` (the current-branch pick), `worktree` (the worktree pick), and `new-branch` (the new-branch pick) pre-answer this question and suppress it, matching the modifier set the other consumers accept. Strip a matched modifier before the mode-detect routing below, so it never leaks into the Scientific-vs-Adversarial decision.

**Workspace slug.** The worktree and new-branch picks name their branch `debug-<desc-slug>`, `<desc-slug>` derived — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-naming.md`'s slug source order and normalization — from the bug description just collected (the Mode answer, or `$ARGUMENTS` when it already carries one), falling back to `debug-<short-sha>` when no description is available yet. Honor a project branch-name format the way `/geniro:implement` does: extract `BRANCH_FORMAT_RULE` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-naming.md` §Extraction site now — the one targeted read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-chooser.md` §6 allows ahead of the pick — and compose it around the slug per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-naming.md` §Branch-format-rule conformance. This workspace slug is distinct from the branch-derived slug that names `.geniro/state/debug/<slug>/` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Slug rules) — that one is recomputed from whichever branch results, after this action lands.

**Step 0.3 — Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: debug`, `LOAD_TIER: pipeline`, `MODE: initial-load`, after the workspace pick settles the tree it reads (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-chooser.md` §6). Echo per the helper's contract.

**Step 0.4 — Branch freshness.** On a fresh run (skip on compaction-resume), apply Mode FRESH-CONTINUE in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md`. The update is an offer, never auto-run — an unasked merge moves the user's HEAD. Fire that file's update-default or catch-up question verbatim when behind; before any action that moves HEAD, run `git status --porcelain`, and any output chains its unsaved-work question first. Hold the pick and resolved `behind` count for Step 0.5's `approvals[]` write (category `branch_freshness`).

$ARGUMENTS routing:

| $ARGUMENTS shape | Mode | Transition |
|---|---|---|
| empty | ONE `AskQuestion` call (fired at Step 0.2) carrying: Mode (header "Mode" — 4 options: "Describe the symptoms" / "Paste error message" / "Point to a failing test" / "Verify last changes (adversarial)"; first 3 → Scientific, fourth → Adversarial) + Workspace (when Step 0.2 rule 3 also fires) — up to 2 questions, one round-trip. | `mode-detect` → `investigate` OR `adversarial-mode-detect` |
| matches anchored verify-keyword signals (table below) | Adversarial Mode | `adversarial-mode-detect` |
| otherwise | Scientific Mode | `mode-detect` → `investigate` |

**Anchored verify-keyword signals** (bare keywords alone NOT enough — phrases like "verify that login returns 500" or "stress-test revealed a memory leak" are scientific-method bug reports, not verify requests):

- Anchored keyword signals: `verify <changes|diff|last|recent|my|this|PR>`, `break <my|the> diff`, `hunt for bugs in <diff|change|PR>`, `find edge cases in <diff|change|PR>`, `adversarial <mode|pass|scan|run>`, `stress-test <the diff|my change|last changes>`
- Phrase signals: `verify last changes`, `verify recent changes`, `verify my changes`, `check last changes`, `break my diff`
- Explicit diff range signals: `HEAD~N..HEAD`, `HEAD~N`, `main...HEAD`, bare PR ref (`#1234` or GitHub PR URL), bare branch name + verify keyword

**Approvals-persistence protocol:** before firing the empty-AUQ, check state.md frontmatter `approvals[]` (when state.md exists) for prior entry with `category: disambiguate_mode`. If found, use prior `picked` value. If not, fire AUQ → on user pick, hold it for Step 0.5: on a fresh run state.md does not exist yet, so `atomic_state_append_list_item` fails (rc 73). The session-start restore re-surfaces this saved choice from `approvals[]` on resume.

When in doubt (ambiguous input), default to Scientific Mode — user can re-invoke with explicit adversarial phrasing if needed.

**Step 0.5 — Create state.md.** After Steps 0.2-0.4 and the routing above settle workspace and mode, write state.md in one `atomic_state_write` from the template in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §2: `baseline-dirty-paths` held from Step 0.1, `branch:` / `worktree:` reflecting wherever the run now stands, and the held picks as `approvals[]` entries — `debug_workspace_setup` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-chooser.md` §6, `branch_freshness`, `disambiguate_mode`. This is the phase's first state write, after Step 0.2's git action (if any) settles — the path is keyed to the resulting branch. When Step 0.2 rule 1 found an existing state.md, append the held entries to it with `atomic_state_append_list_item` instead.

**Tool surface.** Read, plus Bash limited to `git branch --show-current` / `git rev-parse` / `git status --porcelain`, Step 0.4's `git fetch` / `git merge` / `git rebase` / `git stash` / `git pull --ff-only` (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md`), Step 0.2's `git worktree add` / `git checkout -b` (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-chooser.md`), Step 0.3's and the Workspace slug's `load_custom_instructions` call, and `atomic_state_write` / `atomic_state_append_list_item` to persist the picks. `AskQuestion` for those gates. EnterWorktree immediately after Step 0.2's `git worktree add`, so the run investigates inside the tree it cut, not the protected checkout; ExitWorktree to leave. Blocked: any project-file write or edit, and any ship or side-effect command (`git commit`, `git push`, `gh pr create`).
