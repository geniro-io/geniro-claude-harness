# Debug Phase 0 — mode detection

Phase file for `/geniro:debug`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md`.

state.md `phase: mode-detect`. **Step 0 — Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: debug`, `LOAD_TIER: pipeline`, `MODE: initial-load`. Echo per the helper's contract.

**Step 0.1 — Branch freshness.** On a fresh run (skip on compaction-resume), apply Mode FRESH-CONTINUE in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md` — /geniro:debug investigates in place on the current branch, so if that branch is behind the default branch, offer to update it before the investigation starts. Skipped silently when the branch is already current.

**Step 0.2 — Deep-mode activation.** Semantic-parse `$ARGUMENTS` for `--deep` / `deep` / `deep mode` and strip the token before the mode-detect routing below (so it never leaks into the Scientific-vs-Adversarial decision). Deep mode composes with the mode switch — Scientific+Deep and Adversarial+Deep are both valid. Then resolve depth: `--deep` present or a compaction-resume → skip the depth question (flag pre-resolves to Deep; resume re-applies the persisted choice); empty `$ARGUMENTS` → add the "Debug depth" question to the same mode AskUserQuestion call; otherwise (common path) → fire a standalone "Debug depth" question here, before Phase 1.1 memory load. The question shape (header "Debug depth", Standard / Deep options, no `(Recommended)`, empty → Standard) and persistence (`deep-mode: <true|false>` + `approvals[]` category `deep_mode_choice` at the earliest `atomic_state_write`) are spelled out in `${CLAUDE_PLUGIN_ROOT}/skills/debug/deep-mode-reference.md` §1.

$ARGUMENTS routing:

| $ARGUMENTS shape | Mode | Transition |
|---|---|---|
| empty | AUQ with header "Mode" — 4 options: "Describe the symptoms" / "Paste error message" / "Point to a failing test" / "Verify last changes (adversarial)". First 3 → Scientific. Fourth → Adversarial. When `--deep` is absent and this is not a resume, add the Step 0.2 "Debug depth" question to this SAME AskUserQuestion call (two questions answered together). | `mode-detect` → `investigate` OR `adversarial-mode-detect` |
| matches anchored verify-keyword signals (table below) | Adversarial Mode | `adversarial-mode-detect` |
| otherwise | Scientific Mode | `mode-detect` → `investigate` |

**Anchored verify-keyword signals** (bare keywords alone NOT enough — phrases like "verify that login returns 500" or "stress-test revealed a memory leak" are scientific-method bug reports, not verify requests):

- Anchored keyword signals: `verify <changes|diff|last|recent|my|this|PR>`, `break <my|the> diff`, `hunt for bugs in <diff|change|PR>`, `find edge cases in <diff|change|PR>`, `adversarial <mode|pass|scan|run>`, `stress-test <the diff|my change|last changes>`
- Phrase signals: `verify last changes`, `verify recent changes`, `verify my changes`, `check last changes`, `break my diff`
- Explicit diff range signals: `HEAD~N..HEAD`, `HEAD~N`, `main...HEAD`, bare PR ref (`#1234` or GitHub PR URL), bare branch name + verify keyword

**Approvals-persistence protocol:** before firing the empty-AUQ, check state.md frontmatter `approvals[]` for prior entry with `category: disambiguate_mode`. If found, use prior `picked` value. If not, fire AUQ → on user pick, append to `approvals[]` via `atomic_state_write` before proceeding. The session-start restore re-surfaces this saved choice from `approvals[]` on resume.

When in doubt (ambiguous input), default to Scientific Mode — user can re-invoke with explicit adversarial phrasing if needed.
