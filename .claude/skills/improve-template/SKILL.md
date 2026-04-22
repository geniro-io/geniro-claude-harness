---
name: improve-template
description: "Investigate issues in geniro-claude-plugin, research fixes, and implement after approval"
context: main
model: inherit
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
  - WebSearch
  - WebFetch
argument-hint: "<issue description or area to improve>"
---

# /improve-template — Template Investigation & Fix Pipeline

You are the orchestrator for investigating and fixing issues in the geniro-claude-plugin.
You coordinate research agents, cross-reference findings, present evidence to the user, and
delegate implementation. You NEVER implement changes directly — except trivial fixes (1-2 lines,
obvious target, no ambiguity). Everything else goes through subagents.

**Template path:** (repo root — skills/, agents/, hooks/)
**Report path:** `report.md` (354KB best-practices guide based on 14 production frameworks)

---

## State Persistence

After completing each phase, write a checkpoint to `.claude/.artifacts/improve-template-state.md`:
```
Phase [N] completed: [phase name]
Issue: [one-line description]
Findings count: [N approved]
Files to change: [list]
```

On skill start: if `.claude/.artifacts/improve-template-state.md` exists, read it and resume
from the next incomplete phase. Ask the user if this is still the active improvement or a new one.

---

## Complexity Gate (before Phase 1)

Classify the request before entering the pipeline:

- **Obvious bug fix** — user shows a screenshot or error, the broken file and fix are clear
  (e.g., regex false positive, wrong path, typo). Skip to **Phase 1-fast**.
- **Targeted improvement** — specific skill/agent/hook to improve, clear scope.
  Run full pipeline (Phases 1-6).
- **Open-ended investigation** — "make X better", broad area, unclear scope.
  Run full pipeline (Phases 1-6).

### Phase 1-fast: Quick Fix Path

For obvious bug fixes only. The user already showed what's broken.

1. Read the affected file(s) to confirm the bug
2. Research the correct fix — spawn 1-2 agents if the fix isn't obvious:
   - Internet agent: search for the correct pattern/syntax
   - Codebase agent: check how similar cases are handled elsewhere in the template
3. Present the fix to the user with evidence, then use the `AskUserQuestion` tool (do NOT output options as plain text) to ask "Approve this fix or investigate deeper?" with options: "Approve — apply the fix" / "Investigate deeper — run full pipeline"
4. If approved: apply the fix (directly if 1-2 lines, subagent if more)
5. Spawn a fresh review agent (Phase 5 Step 1) to verify
6. Skip to Phase 6

---

## PHASE 1: INVESTIGATE (parallel research)

**Purpose:** Gather evidence from three independent sources about the issue or improvement area.

**Input:** User describes an issue, shows a screenshot, or names an area to improve.

### Step 1: Parse the request

Classify the request:
- **Bug fix** — something broken (screenshot, error, false positive). Extract: what happened, expected behavior, affected file(s).
- **Improvement** — enhance existing behavior. Extract: which skill/agent/hook, what aspect.
- **New capability** — add something missing. Extract: what, why, which files affected.

### Step 2: Spawn 3 research agents in ONE response

All three agents run in parallel — multiple Agent() calls in the same assistant turn, NOT one per turn. Each gets a focused research scope with zero overlap.
Replace every `{{placeholder}}` with the actual content from Step 1 before spawning.

```
Agent(model="opus", prompt="""
## Task: Internet Research
Search for patterns, best practices, and known solutions related to:
{{issue description from Step 1}}

Search for:
- Claude Code documentation and GitHub issues related to this
- Community patterns from claude-code plugins/frameworks
- General best practices for {{relevant domain from Step 1}}

For each finding, provide:
- Source (URL or reference)
- Key pattern or technique
- Direct applicability to our issue
- Evidence strength (strong/moderate/weak)

Return findings as a structured table. Do NOT suggest implementation — research only.
""", description="Research: internet patterns")

Agent(model="opus", prompt="""
## Task: Report.md Research
Read `report.md` and search for sections relevant to:
{{issue description from Step 1}}

This is a 354KB best-practices guide covering 14 production frameworks.
Search strategy:
1. Grep for keywords related to the issue
2. Read the Table of Contents (first 60 lines) to identify relevant sections
3. Read each relevant section fully
4. Extract specific recommendations, patterns, and anti-patterns

For each finding, provide:
- Section name and line range in report.md
- The specific recommendation or pattern
- How it applies to our issue
- Whether our template already follows it or not

Return findings as a structured table. Do NOT suggest implementation — research only.
""", description="Research: report.md patterns")

Agent(model="opus", prompt="""
## Task: Codebase Exploration
Explore the current state of the template files related to:
{{issue description from Step 1}}

Template root: repo root (skills/, agents/, hooks/)

Exploration strategy:
1. Identify which files are affected (skills, agents, hooks)
2. Read each affected file fully
3. Identify current patterns, gaps, and inconsistencies
4. Check cross-references (does file A reference file B correctly? Are paths valid?)
5. Check for related patterns in other skills that solve similar problems

For each finding, provide:
- File path and line range
- Current behavior
- Gap or inconsistency found
- How other template files handle similar situations

Return findings as a structured table. Do NOT suggest implementation — research only.
""", description="Research: codebase exploration")
```

### Step 3: Collect and record

Wait for all 3 agents. Write key findings to state checkpoint.

---

## PHASE 2: CROSS-REFERENCE & FILTER

**Purpose:** Filter raw research to evidence-backed improvements only. This is orchestrator work — you aggregate and filter directly, no subagents needed.

### Step 1: Build a combined findings list

Merge findings from all 3 research agents. Group by topic. Same finding from multiple sources = stronger evidence — note the convergence.

### Step 2: Filter each finding

For each finding, assess yourself:

**Structural compatibility:**
- Compatible with template architecture? (skills = orchestrators, agents = leaf workers, <500 lines)
- Would it break existing patterns or cross-references?
- Which files would need changes?

**Evidence quality:**
- **Strong:** documented in official Claude Code docs, proven in production framework, or demonstrated by screenshot/error
- **Moderate:** pattern used by 2+ frameworks in report.md, or logical extension of documented behavior
- **Weak:** single blog post, theoretical benefit, "should work" reasoning
- **Rejected:** no evidence, contradicts known limitations, or speculative

### Step 3: Build the evidence table

Keep only findings that are:
- Structurally compatible (or adaptable)
- Evidence quality: strong or moderate
- Not contradicted by other findings

Write checkpoint with approved finding count.

---

## PHASE 2b: REDUNDANCY & RELEVANCE VALIDATION (subagent)

**Purpose:** Adversarial gate BEFORE the user sees findings — catches items that duplicate existing instructions or propose theoretical/over-engineered changes. The orchestrator cannot self-review its own Phase 2 filtering without bias.

Spawn `relevance-filter-agent` with every Phase 2-approved finding. The agent greps the target files for existing instructions (redundancy) and checks whether each change is needed for current scope or is YAGNI / defensive polish (relevance). It returns an evidence dossier per finding — NOT a KEEP/FILTER tag.

```
Agent(subagent_type="relevance-filter-agent", model="opus", prompt="""
FINDINGS: [all Phase 2-approved findings, numbered, with file paths and proposed changes]
CHANGED FILES: [list of file paths that would be modified — the agent reads them itself]
PROJECT CONTEXT: [relevant CLAUDE.md excerpts, CONTRIBUTING.md if present]

For each finding, return: ALIGNS|CONTRADICTS|NEUTRAL for redundancy (cite line if redundant); APPROPRIATE|OVER-ENGINEERED for necessity; one-line rationale. Do NOT tag KEEP or FILTER — evidence only; the orchestrator decides.
""", description="Validate: redundancy & relevance")
```

Read the dossier yourself: tag FILTER if CONTRADICTS (redundant) or OVER-ENGINEERED (not needed); otherwise KEEP. Do NOT delegate this tagging. Write checkpoint with KEEP count. Filtered findings appear in Phase 3's "Filtered" section for transparency but are not proposed for implementation.

---

## PHASE 3: PRESENT TO USER (WAIT)

**Purpose:** Show evidence-backed findings and get approval before any changes.

### Step 1: Present the evidence table

```
## Investigation Results: [issue/area]

### Findings (evidence-backed only)

| # | Finding | Evidence | Source(s) | Files Affected | Complexity |
|---|---------|----------|-----------|----------------|------------|
| 1 | [what to change] | [why — specific evidence] | [internet/report/codebase] | [file list] | [trivial/small/medium] |
| 2 | ... | ... | ... | ... | ... |

### Rejected (insufficient evidence)
- [finding] — rejected because [reason]

### Filtered by Phase 2b (redundant or over-engineering)
- [finding] — filtered because [redundant with <file:line> | over-engineering for current scope]

### Implementation plan
For each finding: which files change, what changes, estimated line impact.
```

### Step 2: Ask for approval

Use the `AskUserQuestion` tool (do NOT output options as plain text — the tool provides a structured UI). Call it with:
- **Question:** "How should I proceed with these findings?"
- **Options (use these exactly):**
  - "Implement all findings"
  - "Let me pick which ones to implement"
  - "I disagree with some findings — let me challenge them"
  - "Research deeper on specific items"

**If user picks C or D:** Go to Phase 3b.

### Phase 3b: Challenge Resolution

For each challenged finding, spawn a research agent with: the finding description, the user's concern, and instructions to search for definitive evidence. Update the evidence table based on results. Re-present to user. Loop until approved.

---

## PHASE 4: IMPLEMENT (delegated)

**Purpose:** Apply approved changes through subagents. Orchestrator does NOT edit files
(except trivial 1-2 line fixes where the target and change are unambiguous).

### Step 0: Capture baseline
Before spawning implementation agents, read and record the current content of all files that will be modified. This baseline enables before/after comparison in Phase 5.

### Step 1: Group changes by file/module

Group approved findings into implementation units:
- **Trivial** (1-2 lines, obvious target): Apply directly using Edit tool. No subagent needed.
  **Guard:** If you find yourself reading more than 2 files or the fix touches logic, delegate instead.
- **Single file changes:** One agent per file
- **Cross-file changes:** One agent per logical group (same module/feature)

### Step 2: Spawn implementation agents in ONE response (all Agent() calls in the same assistant turn, NOT one per turn)

Pre-inline the current file content each agent needs (from Phase 1 codebase research).

```
Agent(model="opus", prompt="""
## Task: Implement Changes
Apply the following approved changes:

### Change 1: [description]
**File:** [path]
**Current behavior (line N-M):**
[paste relevant current code — pre-inlined from Phase 1 research]

**Required change:**
[specific description of what to change and why]

### Constraints
- Stay under 500 lines for SKILL.md files
- Preserve existing patterns (phase structure, agent spawning syntax, anti-rationalization tables)
- Do NOT add features beyond what was approved
- Do NOT refactor surrounding code
- Do NOT add comments explaining the change itself
- **Edit-in-place principle:** When fixing or improving an instruction, rewrite the
  original instruction to be explicit about the correct behavior. NEVER add separate
  notes, exceptions, caveats, or conditions below/after the original. Adding
  "NOTE: also handle X" or "Exception: when Y, do Z" creates context distance and
  instruction rot. The original instruction should read correctly on its own.

### Definition of Done
- [ ] All approved changes applied
- [ ] No unintended side effects on surrounding code
- [ ] File line count verified (under 500 for skills)
- [ ] Cross-references to other files still valid
""", description="Implement: [group name]")
```

### Step 3: Validation gate

Orchestrator runs these checks directly (no subagent). All must pass before Phase 5:

1. **Line counts:** `wc -l` on each changed SKILL.md — must be under 500
2. **Outbound references:** Glob for every path/agent/skill name mentioned in changed files — all must exist
3. **Inbound references:** Grep the entire template for filenames of changed files — verify referencing files aren't broken
4. **YAML frontmatter:** Verify changed SKILL.md files have valid frontmatter (name, description fields present)
5. **Pattern consistency:** Compare phase structure and agent-spawning syntax in changed skills against 1-2 other skills

If any check fails: spawn a fix agent. Re-run failed checks only. Max 1 fix round. Write checkpoint.

---

## PHASE 5: SELF-REVIEW (fresh subagent)

**Purpose:** Independent review by a fresh agent that wasn't involved in research or implementation.

### Step 1: Spawn review agent

MUST be a fresh agent — never reuse implementation agents (avoids anchoring bias).

```
Agent(model="opus", prompt="""
## Task: Independent Review of Template Changes
Review changes made to the geniro-claude-plugin template. You were NOT involved in
researching or implementing these changes — review with fresh eyes.

### Changes made:
{{git diff output of all changes}}

### Pre-change baseline:
{{file contents captured in Phase 4 Step 0}}

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
- **Warnings:** Present to user — let them decide.
- **Nits:** Apply if trivial, skip if subjective.
- **LGTM:** Proceed to Step 3.

### Step 3: Surface pre-existing bugs

If the reviewer found pre-existing bugs, present them to the user in a separate table:

```
### Pre-existing bugs found during review

These were NOT introduced by the current changes but were discovered while reviewing the affected files:

| # | File | Bug | Severity | Suggested fix |
|---|------|-----|----------|---------------|
| 1 | [path:line] | [description] | [blocker/warning/nit] | [fix] |
```

Use the `AskUserQuestion` tool (do NOT output options as plain text) to ask:
- **Question:** "Want to fix any of these pre-existing bugs?"
- **Options:**
  - "Fix all of them"
  - "Let me pick which ones to fix"
  - "Skip — focus on the current changes only"

- If **fix all**: spawn implementation agents for the pre-existing fixes (same Phase 4 flow), then re-run Phase 5 review on the new changes only.
- If **pick**: present each bug individually and let the user select, then implement selected fixes.
- If **skip**: proceed to Phase 6.

If no pre-existing bugs were found, skip this step.

---

## PHASE 6: REPORT, LEARN & COMPLETE

### Step 1: Summary

Present to the user:

```
## Changes Applied

| File | Change | Lines |
|------|--------|-------|
| [path] | [what changed] | [before → after line count] |

### Review result: [LGTM / N warnings]
[any warnings from Phase 5]
```

### Step 2: Extract learnings to memory

Scan the conversation for:
- User corrections ("actually, do X not Y")
- Convention discoveries (patterns that weren't documented)
- Blocked items or limitations encountered

Before writing to memory, check if existing memory already covers the topic — update
rather than duplicate. Skip this step entirely if nothing novel was discovered.

### Step 3: Cleanup

Remove `.claude/.artifacts/improve-template-state.md`.

### Step 4: Suggest commit & push

After cleanup, run `git status --short` and `git diff --stat` to show what's staged vs. unstaged. Then use the `AskUserQuestion` tool (do NOT output options as plain text) to offer shipping the changes:

- **Question:** "Ship these template changes?"
- **Options:**
  - "Commit and push (Recommended)" — orchestrator stages changed files by name, creates a commit with a message summarizing the findings, and pushes to the current branch's upstream
  - "Commit only — I'll push later"
  - "Skip — I'll commit manually"

If the user picks commit+push or commit-only:
- Stage only the files listed in the Phase 6 Step 1 summary table (never `git add -A` or `git add .`).
- Write the commit message via HEREDOC, following the repo's commit style (check `git log -5 --oneline` first).
- For commit+push: run `git push` after the commit succeeds. If the branch has no upstream, report the exact `git push -u origin <branch>` command and ask the user to confirm before running it.
- Never use `--no-verify`, `--amend`, or any destructive flag.
- If a pre-commit hook fails, surface the failure and stop — do not retry or bypass.

If the user picks skip, print the suggested commit message and the `git add` / `git commit` / `git push` commands for them to run manually.

---

## Mid-flow User Input

If the user interjects during any phase:
- **Correction/context** ("actually, also check X", "that file moved to Y") — incorporate into current phase, note in state checkpoint
- **Preference** ("use pattern X not Y") — apply at next decision point
- **Blocker** ("stop, that's wrong") — halt current phase, present what you have, ask how to proceed
- **New issue** ("also I noticed this other bug") — note it, finish current pipeline first, then ask if they want a second run

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll implement this multi-file change directly" | Changes touching 3+ files or any logic go through implementation subagents. Orchestrator coordinates, agents edit. |
| "The research is clear enough, skip cross-referencing" | Phase 2 exists because Phase 1 agents have no context about each other's findings. Cross-referencing catches contradictions and duplicates. |
| "The user will probably approve all, skip presenting" | Phase 3 is a WAIT gate. The user MUST see evidence and approve. No assumptions. |
| "I'll reuse the implementation agent for review" | Fresh agents avoid anchoring bias. The reviewer must NOT have seen the implementation prompt. |
| "One research agent is enough for this simple issue" | Three-source triangulation catches blind spots. Internet + report.md + codebase are independent knowledge sources. Exception: Phase 1-fast for obvious bugs. |
| "I already know the answer from previous sessions" | Memory is context, not evidence. Verify against current file state before acting. |
| "I'll spawn agents one at a time" | All parallel agents MUST be spawned in ONE response — multiple Agent() calls in the same assistant turn. Separate turns = no concurrency, full wall-clock latency per agent. |
| "I'll add a note about the edge case" | Rewrite the original instruction to handle it explicitly. Separate notes create context distance and rot — the original must read correctly on its own. |
| "The change is too small to affect other skills" | Small changes to shared patterns (agent spawning syntax, phase structure, naming conventions) propagate through cross-references. The validation gate catches this — never skip it. |
| "The findings are obviously good, skip the redundancy check" | Phase 2b exists because orchestrator self-filtering inherits the researcher's framing. A fresh subagent greps the target file for existing instructions and flags over-engineering — catches what the proposer cannot see. |

## Definition of Done

- [ ] Complexity gate applied (fast path or full pipeline)
- [ ] Phase 1: Research agents completed (3 for full pipeline, 1-2 for fast path)
- [ ] Phase 2: Findings cross-referenced and filtered to evidence-backed only
- [ ] Phase 2b: Redundancy & relevance validated via relevance-filter-agent subagent
- [ ] Phase 3: Evidence table presented, user approved specific changes
- [ ] Phase 4: Changes implemented (subagents for multi-file, direct for trivial)
- [ ] Phase 5: Independent review by fresh agent passed
- [ ] Phase 6: Summary presented, state file cleaned up
- [ ] Phase 6: Commit & push offered to the user (Step 4)
- [ ] All changed SKILL.md files under 500 lines
- [ ] No scope creep beyond approved changes
