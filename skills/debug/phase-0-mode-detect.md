# Debug Phase 0 — mode detection

## Contents

- Step 0 — Load custom instructions
- Step 0.1 — Entry-time working-tree baseline
- Step 0.2 — Workspace
- Step 0.3 — Branch freshness
- Step 0.4 — Deep-mode activation
- $ARGUMENTS routing
- Anchored verify-keyword signals
- Approvals-persistence protocol

Phase file for `/geniro:debug`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md`.

state.md `phase: mode-detect`. **Step 0 — Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: debug`, `LOAD_TIER: pipeline`, `MODE: initial-load`. Echo per the helper's contract.

**Step 0.1 — Entry-time working-tree baseline.** On a fresh run (skip on compaction-resume — the baseline already lives in state.md), before Step 0.2 evaluates the workspace decision, run `git status --porcelain` from the worktree root and capture its changed-path list — Step 0.2's dirty-tree rule reads it to decide whether the worktree option is offered. Hold the captured list in working memory rather than writing it here: debug keys `.geniro/state/debug/<slug>/` to the branch (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Slug rules), and Step 0.2 is what may change the branch, so a write here would land under the slug this run is about to leave. Step 0.2 persists `baseline-dirty-paths` itself, in the phase's first `atomic_state_write`, after its own git action (if any) settles. The Step 0.3 branch-freshness pick writes its own `approvals[]` entry, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md` §7. Phase 3 §3.1's working-tree check subtracts this baseline — Adversarial Mode's ship path never reads it.

**Step 0.2 — Workspace.** Passive-detect first, ask only when ambiguous. Collect `IN_WORKTREE` and `PROTECTED_BRANCH` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-signals.md`, then apply this decision tree (first match wins):

```
1. Compaction-resume, or a resumable state.md exists for this slug
   ⇒ SKIP the question. Re-apply the recorded workspace from state.md
     `branch:` / `worktree:` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md`
     § Mismatch handling (Case A/B/C) — never an auto-executed git operation.

2. IN_WORKTREE == true
   ⇒ AUTO-CONTINUE here. No question. Echo:
       "Debugging in worktree '<dir>' on '<branch>'."

3. IN_WORKTREE == false AND PROTECTED_BRANCH == false
   ⇒ AUTO-CONTINUE in place. No question. Echo:
       "Debugging on '<branch>'. Reproduction test and any debug logging land here.
        Reverse with: re-run with 'worktree' in arguments."

4. IN_WORKTREE == false AND PROTECTED_BRANCH == true
   ⇒ Fire the workspace question (Mode INSPECT-HERE).
```

Rule 4 fires `AskUserQuestion` (header `"Workspace"`) with options from the catalogue in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-chooser.md` §2, applied per that file's §4 Mode INSPECT-HERE. This call fires here, at Step 0.2 — per the ordering contract in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-chooser.md` §6 and `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md` §1, before Step 0.3's freshness gate and Step 0.4's deep-mode routing, not after. When `$ARGUMENTS` is empty, the same call also carries Mode and, if still unresolved, Debug depth (Step 0.4's table decides which) — one round-trip beats three, and the branch on this path falls back to the short-SHA slug (Workspace slug, below), since no description exists yet.

- **"Debug here on '<branch>'"** (`current-branch`) — investigate in place; the reproduction test and any tagged debug logging land on `<branch>`.
- **"Isolated worktree at this commit"** (`worktree`) — cut at `HEAD` into `.claude/worktrees/debug-<desc-slug>/` (bound in Workspace slug, below), then `EnterWorktree`, leaving the protected checkout on its branch. Offered only when Step 0.1's `baseline-dirty-paths` is empty; a dirty tree withholds this option and the question says why in one sentence — a worktree would not bring the uncommitted work along, and that work is often the thing being debugged.
- **"New branch at this commit"** (`new-branch`) — cut at `HEAD` in the current checkout, carrying uncommitted work along and moving the checkout off the protected branch.

Recommend exactly one label per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-chooser.md` §5: the worktree when `baseline-dirty-paths` is empty, the new branch when it is dirty — the option descriptions above already say why; the recommendation rule doesn't repeat it.

`$ARGUMENTS` modifiers `current-branch` / `here` (the current-branch pick), `worktree` (the worktree pick), and `new-branch` (the new-branch pick) pre-answer this question and suppress it, matching the modifier set the other consumers accept. Strip a matched modifier before the mode-detect routing below, the same way Step 0.4 strips `--deep`.

**Workspace slug.** The worktree and new-branch picks name their branch `debug-<desc-slug>`, `<desc-slug>` derived — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-naming.md`'s slug source order and normalization — from the bug description just collected (the Mode answer, or `$ARGUMENTS` when it already carries one), falling back to `debug-<short-sha>` when no description is available yet. Honor a project branch-name format the way `/geniro:implement` does: read `.geniro/instructions/global.md` for a `BRANCH_FORMAT_RULE` now — the one targeted read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-chooser.md` §6 allows ahead of the pick — and compose it around the slug per `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §Phase 1: Step 0a signal detection, `BRANCH_FORMAT_RULE` row. This workspace slug is distinct from the branch-derived slug that names `.geniro/state/debug/<slug>/` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Slug rules) — that one is recomputed from whichever branch results, after this action lands.

Persist once, at the end of this step (rules 2-4; rule 1 skips — its state.md already carries this from a prior run): `baseline-dirty-paths` held from Step 0.1, state.md `branch:` / `worktree:` reflecting wherever the run now stands, and — rule 4 or its modifier-suppressed equivalent only — `approvals[]` category `debug_workspace_setup` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-chooser.md` §6. One `atomic_state_write`, the phase's first, run after rule 4's git action (if any) settles — so the write lands under the slug the action actually produced.

**Step 0.3 — Branch freshness.** On a fresh run (skip on compaction-resume), apply Mode FRESH-CONTINUE in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md` — debug creates at `HEAD` when it creates at all (Step 0.2's worktree and new-branch picks both cut from `HEAD`, never the default-branch tip), so Mode FRESH-BASE never applies here; offer to update the branch before the investigation starts when it is behind the default branch. Skipped silently when the branch is already current.

**Step 0.4 — Deep-mode activation.** Semantic-parse `$ARGUMENTS` for `--deep` / `deep` / `deep mode` and strip the token before the mode-detect routing below (so it never leaks into the Scientific-vs-Adversarial decision). `--deep` deepens Scientific Mode only; in Adversarial Mode it is accepted and recorded but currently deepens no stage. Then resolve whether the "Debug depth" question fires, and where:

| Condition | Debug-depth question |
|---|---|
| `--deep` present, or compaction-resume | Skipped — the flag pre-resolves Deep; resume re-applies the persisted `approvals[]` choice |
| Empty `$ARGUMENTS` | Joins the Mode call (plus Workspace, when Step 0.2 rule 4 also fires) — one `AskUserQuestion` call, per the `$ARGUMENTS` routing table below |
| Non-empty `$ARGUMENTS`, Step 0.2 rule 4 fired | Joins that same Workspace call |
| Otherwise (common path) | Standalone "Debug depth" question here, before Phase 1.1 memory load |

Every row stays inside the 4-question `AskUserQuestion` cap. The question shape (header "Debug depth", Standard / Deep options, no `(Recommended)`, empty answer re-asks rather than defaulting) and persistence (`deep-mode: <true|false>` + `approvals[]` category `deep_mode_choice` at the earliest `atomic_state_write`) are spelled out in `${CLAUDE_PLUGIN_ROOT}/skills/debug/deep-mode-reference.md` §1.

$ARGUMENTS routing:

| $ARGUMENTS shape | Mode | Transition |
|---|---|---|
| empty | ONE `AskUserQuestion` call (fired at Step 0.2) carrying: Mode (header "Mode" — 4 options: "Describe the symptoms" / "Paste error message" / "Point to a failing test" / "Verify last changes (adversarial)"; first 3 → Scientific, fourth → Adversarial) + Workspace (when Step 0.2 rule 4 also fires) + Debug depth (when Step 0.4's table above hasn't already resolved it) — up to 3 questions, one round-trip. | `mode-detect` → `investigate` OR `adversarial-mode-detect` |
| matches anchored verify-keyword signals (table below) | Adversarial Mode | `adversarial-mode-detect` |
| otherwise | Scientific Mode | `mode-detect` → `investigate` |

**Anchored verify-keyword signals** (bare keywords alone NOT enough — phrases like "verify that login returns 500" or "stress-test revealed a memory leak" are scientific-method bug reports, not verify requests):

- Anchored keyword signals: `verify <changes|diff|last|recent|my|this|PR>`, `break <my|the> diff`, `hunt for bugs in <diff|change|PR>`, `find edge cases in <diff|change|PR>`, `adversarial <mode|pass|scan|run>`, `stress-test <the diff|my change|last changes>`
- Phrase signals: `verify last changes`, `verify recent changes`, `verify my changes`, `check last changes`, `break my diff`
- Explicit diff range signals: `HEAD~N..HEAD`, `HEAD~N`, `main...HEAD`, bare PR ref (`#1234` or GitHub PR URL), bare branch name + verify keyword

**Approvals-persistence protocol:** before firing the empty-AUQ, check state.md frontmatter `approvals[]` for prior entry with `category: disambiguate_mode`. If found, use prior `picked` value. If not, fire AUQ → on user pick, append to `approvals[]` via `atomic_state_write` before proceeding. The session-start restore re-surfaces this saved choice from `approvals[]` on resume.

When in doubt (ambiguous input), default to Scientific Mode — user can re-invoke with explicit adversarial phrasing if needed.
