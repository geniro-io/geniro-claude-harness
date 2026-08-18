# /improve-template — Phase 4-6 (implement, self-review, report)

Phase body for `.claude/skills/improve-template/SKILL.md`. Read on entry to Phase 4 — Phase 1-fast fixes, create-skill mode, and process-handoff triage runs that stop before Phase 4 never take this branch, and neither does a run that compacts before reaching it.

## Contents

- Phase 4 — Implement (delegated)
- Phase 5 — Self-review (fresh subagent)
- Phase 6 — Report, learn & complete
- Description-format validator (Phase 4 Step 3 extension)

---

## PHASE 4: IMPLEMENT (delegated)

**Purpose:** Apply approved changes through subagents. Orchestrator does NOT edit files
(except trivial 1-2 line fixes where the target and change are unambiguous).

### Step 0: Capture baseline
Record the paths about to be modified and the pre-change commit (`git rev-parse HEAD`). That is the whole baseline — Phase 5 resolves any file it needs from that revision, so re-reading file bodies into context here only duplicates what the Phase 1 research already carried.

### Step 1: Group changes by file/module

Group approved findings into implementation units:
- **Trivial** (1-2 lines, obvious target): Apply directly using Edit tool. No subagent needed.
  **Guard:** If you find yourself reading more than 2 files or the fix touches logic, delegate instead.
- **Single file changes:** One agent per file
- **Cross-file changes:** One agent per logical group (same module/feature)

### Step 2: Spawn implementation agents in ONE response (all Agent() calls in the same assistant turn, NOT one per turn)

Pre-inline the current file content each agent needs (from Phase 1 codebase research).

```
Agent(model="sonnet",  # execution spawn — model-tiering.md category 4; the change is approved and the files are named. Ceiling: a purely textual round sizes below it
      prompt="""
## Task: Implement Changes
Apply the following approved changes:

### Change 1: [description]
**File:** [path]
**Current behavior (line N-M):**
[paste relevant current code — pre-inlined from Phase 1 research]

**Required change:**
[specific description of what to change and why]

### Constraints
- **Size:** read `.claude/rules/skill-structure.md` § File-size limits before you edit (repo-relative
  path, you have Read access) and apply it to every file you touch. That section is the only source
  for the budgets and for what to do on overflow — do not restate its numbers into the file you edit.
- Preserve existing patterns (phase structure, agent spawning syntax, anti-rationalization tables)
- Match the change to exactly what was approved — extra scope here ships unreviewed
- Touch only the lines the approved change requires, leaving surrounding code as found
- Let the diff explain itself; skip comments narrating the change — those go stale the moment the code moves again
- **Edit-in-place principle:** When fixing or improving an instruction, rewrite the
  original instruction to be explicit about the correct behavior. NEVER add separate
  notes, exceptions, caveats, or conditions below/after the original. Adding
  "NOTE: also handle X" or "Exception: when Y, do Z" creates context distance and
  instruction rot. The original instruction should read correctly on its own.
- **Minimum tokens:** read `.claude/rules/skill-prose.md` §"Assume a capable model" before you edit
  (repo-relative path, you have Read access) and apply it to every section you touch. That section is
  the only source for what counts as removable detail and for what earns its place — do not restate
  its list into the file you edit. Prefer tightening an existing line over adding a new one, and
  subtract in the sections you touch; signal density, not size, is the target.
- **Adding text meant to change what a run finds or does:** read the same file's §"What adding
  instructions buys" first. It carries when wording is the wrong tool for the change you were handed,
  and what to reach for instead. Report back if the change you were given is one it rules out.
""", description="Implement: [group name]")
```

### Step 3: Validation gate

Orchestrator runs these checks directly (no subagent). All must pass before Phase 5:

1. **Authoring lint:** `bash tests/authoring/lint-skills.sh` — a hard failure fails this check; its size and duplication warnings are advisory, judged against `.claude/rules/skill-structure.md` § File-size limits, which says what to do with an over-target file. The hard checks scan `skills/` and `agents/` only, so a `.claude/skills/`-only change gets the advisory half alone.
2. **Outbound references:** Glob for every path/agent/skill name mentioned in changed files — all must exist
3. **Inbound references:** Grep the entire template for filenames of changed files — verify referencing files aren't broken
4. **YAML frontmatter:** Verify changed SKILL.md files have valid frontmatter (name, description fields present)
5. **Pattern consistency:** Compare phase structure and agent-spawning syntax in changed skills against 1-2 other skills
6. **Description-format checks (6 sub-checks):** apply when any changed SKILL.md's YAML `description:` field was added or modified. The checks, their warning/blocker levels, and the procedure are in § Description-format validator below; check 6 there overlaps with #4 above and counts once.
7. **README/docs sync + generated-file sync (when changes touch user-facing surface or `agents/*.md`):** apply when the change adds/removes/renames a sub-command (verb), modifies YAML `description` or `argument-hint`, alters advertised behavior of an existing slash command, or adds/removes a top-level skill. Grep `README.md` and any `docs/*.md` for the changed skill's name (e.g., `geniro:actions`); also grep `CLAUDE.md` since it carries the skills-table row. For each matched section, read it and compare against the new behavior — flag as **warning** any drift: missing or extra sub-commands in lists, contradictory or stale behavioral descriptions, outdated usage examples, stale frontmatter mirrors. Propose the specific README/CLAUDE.md edits as part of the Phase 6 Step 1 summary so they ship with the same commit the user approves; do NOT silently apply them. If no README/CLAUDE.md/docs mention exists for the changed skill, note "no docs mention to sync". Warning-level — does NOT trigger the fix agent.
   **Generated Cursor agents — blocker, not a warning:** when the change edited any `agents/*.md`, run `scripts/build-cursor-agents.sh` and include the regenerated `cursor/agents/*.md` in the same change set. `tests/cursor/build-agents-fresh.sh` hard-fails CI on drift between the two, so omitting it ships a red build. Fix it by re-running the script rather than spawning a fix agent, and never hand-edit `cursor/agents/`.
8. **Compaction & redundancy (added text):** judge the lines this change ADDED against the Minimum-tokens principle in the Phase 4 Step 2 constraint set, plus hedges carrying no condition (the `description` field is out of scope here — § Description-format validator owns it). Warning-level — surfaces in the Phase 6 Step 1 Summary, does NOT trigger the fix agent.

If any check fails: spawn a fix agent. Re-run failed checks only. Max 1 fix round. Write checkpoint. Warnings (#1 lint advisories, #6 sub-items 1-4, #7 README/docs drift, and #8 compaction/redundancy) do NOT trigger the fix agent — they appear in the Phase 6 Step 1 Summary as advisory items.

---

## PHASE 5: SELF-REVIEW (fresh subagent)

**Purpose:** Independent review by a fresh agent that wasn't involved in research or implementation.

### Step 1: Spawn review agent

Must be a fresh agent — never reuse implementation agents (avoids anchoring bias).

```
Agent(prompt="""
## Task: Independent Review of Template Changes
Review changes made to the Geniro plugin template. You were NOT involved in
researching or implementing these changes — review with fresh eyes.

### Changes made:
{{git diff output of all changes}}

### Pre-change baseline:
Commit {{pre-change sha from Phase 4 Step 0}}; files {{paths from Phase 4 Step 0}}. Run `git show <sha>:<path>` for any of them you need in full.

### Review checklist:
1. **Correctness:** Do the changes do what they claim? Any logic errors?
2. **Consistency:** Do changes match patterns used elsewhere in the template?
   - Phase structure consistent with other skills?
   - Agent spawning syntax matches template conventions?
   - Anti-rationalization tables present where needed?
3. **Scope creep:** Were any changes made beyond what was approved?
4. **Edit-in-place:** Were original instructions rewritten to be explicit, or were
   notes/exceptions/caveats added separately? Separate notes = blocker.
5. **Regressions:** Compare the diff against the baseline. Check:
   - Did any existing instruction's meaning change unintentionally?
   - Are cross-references that worked before still valid?
   - Could downstream skills/agents behave differently due to these changes?
6. **Pre-existing bugs:** While reviewing the changed files, also note any bugs, inconsistencies, or broken patterns that existed BEFORE this change. Report these separately — they are opportunities, not blockers.
7. **Subtraction:** an improvement pass removes as well as adds (the Minimum-tokens
   constraint the implementers were given). Report what this diff REMOVED — deleted rows, restatements
   collapsed into a citation, hand-holding the model derives itself, rules the change superseded. If
   the diff is purely additive, say so in those words and judge whether that was right: a genuinely
   new gate or phase adds without removing, but a pass that reworded an instruction while leaving the
   detail it replaced in place has left the file heavier and more contradictory than it found it.

### For each issue found, report:
- File and line
- Issue description
- Severity (blocker/warning/nit)
- **Category: "introduced" or "pre-existing"**
- Suggested fix

If no issues in either category: report "LGTM — all checks passed"
""", description="Review: independent template review")
```

### Step 2: Process review results

**Introduced issues** (from the current changes):
- **Blockers:** Spawn a fresh fix agent (not the implementer). Then re-review with another fresh agent. Max 1 fix round.
- **Warnings:** Multi-select `AskUserQuestion` (header: `"Warnings"`, ≤4 options per call, chaining past the cap), mirroring `.claude/skills/audit-plugin/phase-5-action-gate.md`'s pick path — apply the ones picked, ship the rest as-is.
- **Nits:** Apply if trivial, skip if subjective.
- **LGTM:** Proceed to Step 3.

**Subtraction report** (checklist item 7): carry the reviewer's answer into the Phase 6 Step 1 summary. A purely-additive pass ships only with the reviewer's justification for why nothing was removable — that line is what stops each pass from silently growing the file it was meant to improve.

### Step 3: Surface pre-existing bugs

If the reviewer found pre-existing bugs, present them to the user in a separate table:

```
### Pre-existing bugs found during review

These were NOT introduced by the current changes but were discovered while reviewing the affected files:

| # | File | Bug | Severity | Suggested fix |
|---|------|-----|----------|---------------|
| 1 | [path:line] | [description] | [blocker/warning/nit] | [fix] |
```

Use the `AskUserQuestion` tool to ask:
- **Question:** "Want to fix any of these pre-existing bugs?"
- **Options:**
  - "Fix all of them"
  - "Let me pick which ones to fix"
  - "Skip — focus on the current changes only"

- If **fix all**: spawn implementation agents for the pre-existing fixes (same Phase 4 flow), then re-run Phase 5 review on the new changes only.
- If **pick**: walk the bugs one at a time — render each row, then fire its own lean `AskUserQuestion` (header: `"This bug"`) — "Fix it" / "Skip it" / "Skip the rest" — matching `skills/reflect/SKILL.md`'s per-candidate walk — then implement the ones fixed.
- If **skip**: proceed to Phase 6.

If no pre-existing bugs were found, skip this step.

---

## PHASE 6: REPORT, LEARN & COMPLETE

### Step 1: Summary

Present to the user:

```
## Changes Applied

| File | Change | Words |
|------|--------|-------|
| [path] | [what changed] | [before → after word count] |

### Review result: [LGTM / N warnings]
[any warnings from Phase 5]

### Removed by this pass
[what the pass subtracted, per Phase 5 checklist item 7 — or "nothing removed" plus the reviewer's justification]

### Verification status
[per change: tested / measured / unmeasured-by-choice — from Step 2]
```

### Step 2: Propose how to verify what landed

The pass has evidence that its files changed and none that its changes work. Close that gap explicitly: classify every landed change into one of three kinds, render the table below, and offer the verifications that exist. Never claim a change is verified because the pipeline's own gates were green — lint and the reference checks prove the edit is well-formed, not that it does anything.

| Kind | What landed | How it gets decided |
|---|---|---|
| **Deterministic** | A hook, a `lib/` helper, a script, a validator, a parser, a path or schema contract | A test case. Name the suite file it belongs in and the case: the input that reproduces the old behavior, and the assertion that fails without this change. |
| **Behavioral** | Skill or agent prose that changes what a run finds, checks, or decides | A measured run — `/eval-loop` against the module the prose belongs to. Name the module, the task class the change targets, and that the screen is paid. |
| **Neither** | Docs, naming, a structural move, a cross-reference repair | Say so in one line. Inventing a test for a rename is worse than admitting the change rides on review alone. |

Then one `AskUserQuestion` offering only the kinds this pass actually produced: write the tests now / start the measurement now / ship unverified and record it. A behavioral change shipping unverified is legitimate — most do — but it ships named as unmeasured, so the next pass over that file knows the prose was never shown to work.

**A behavioral instruction edit is a hypothesis, not a fix.** `.claude/rules/skill-prose.md` §"What adding instructions buys" carries what such edits reliably do and do not buy; a pass that added one and skipped the measurement has produced a candidate, and the summary says candidate.

### Step 3: Extract learnings to memory

Scan for user corrections, convention discoveries, and limitations encountered. Before writing, check if existing memory already covers the topic — update rather than duplicate. Skip if nothing novel was discovered.

### Step 4: Cleanup

`rm -rf .geniro/state/improve-template/<slug>/` — the whole slug directory, per `skills/_shared/within-skill-state-handoff.md` § Cleanup contract — plus this run's two Phase 1 research reports (`.research-architecture-<slug>.md`, `.research-codebase-<slug>.md`). Delete only the current branch's slug; never glob across slugs.

### Step 5: Suggest commit & push

After cleanup, run `bash tests/run-all.sh` — CI gates on it, so a red suite here is a red pull request. If a suite fails, report which one and stop; the ship options are not offered on a red suite. Otherwise show the user what is currently staged versus unstaged, then use the `AskUserQuestion` tool to offer shipping the changes:

- **Question:** "Ship these template changes?"
- **Options:**
  - "Commit and push (Recommended)" — orchestrator stages changed files by name, creates a commit with a message summarizing the findings, and pushes to the current branch's upstream
  - "Commit only — I'll push later"
  - "Skip — I'll commit manually"

If the user picks commit+push or commit-only:
- Stage only the files listed in the Phase 6 Step 1 summary table (never `git add -A` or `git add .`).
- Write the commit message via HEREDOC, following the repo's commit style (check `git log -5 --oneline` first).
- For commit+push: run `git push` after the commit succeeds. A branch with no upstream is a second decision the ship gate above never showed — creating a remote branch is its own outward, non-resumable action class (`skills/_shared/approval-scope.md`). Fire `AskUserQuestion` (header: `"No upstream"`) — **Question:** "No upstream for `<branch>` — push and create it?" **Options:** "Push and set upstream" / "Commit only, skip the push". Run `git push -u origin <branch>` only on the first.
- Never use `--no-verify`, `--amend`, or any destructive flag.
- If a pre-commit hook fails, surface the failure and stop — do not retry or bypass.

If the user picks skip, print the suggested commit message and the `git add` / `git commit` / `git push` commands for them to run manually.

---

## Description-format validator (Phase 4 Step 3 extension)

Adds 6 format checks to the existing Phase 4 validation gate. Applies to BOTH improve-existing-skill (when changes touch a SKILL.md description field) AND create-skill mode.

For each changed/created SKILL.md, check the YAML `description:` field:

1. **Length within budget**: per `.claude/rules/skill-structure.md` §Frontmatter hygiene. Warning if violated (not blocker — content matters more than character count). Flag a description only for exceeding this limit, never for verbosity: its trigger keywords + what/when drive skill selection, so trimming them to save tokens degrades discovery.
2. **Third person**: description should read as "use when X" / "the skill does Y" — NOT "I will X" / "you should X". Check: grep for `\b(I |my |me |you |your )\b` in the description; if matches, flag as warning.
3. **"Use when" trigger clause**: description should include a phrase like "Use when …" / "Use for …" / "Trigger when …" — names the conditions that activate the skill. Required (warning if missing).
4. **"Skip for" anti-trigger clause** (recommended, not required): "Skip for X — use Y instead" — disambiguates against neighbor skills. Adds a recommendation note when missing; not a warning.
5. **No `{{placeholder}}` patterns**: residual template variables. Blocker if found.
6. **Single line OR clean multi-line YAML**: description must parse as valid YAML; check for unescaped quotes or unbalanced `|` `>` indicators that break frontmatter parsing. Blocker if YAML invalid.

Report results in the existing Phase 4 validation summary. Warnings do not block; blockers route to a fresh fix agent (max 1 round) per existing Phase 4 routing.
