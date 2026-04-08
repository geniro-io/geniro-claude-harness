---
name: geniro:review
description: "Parallel multi-agent code review with 5 specialized reviewers (bugs, security, architecture, tests, guidelines). Confidence-scored findings automatically filtered. Use for comprehensive code quality assessment."
context: main
model: sonnet
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - Agent
  - WebSearch
argument-hint: "[files or git diff range to review]"
---

# Code Review Skill

Comprehensive code review using parallel multi-agent analysis. Five specialized reviewers examine code changes simultaneously from different perspectives, then a judge pass validates, confidence-scores, and aggregates findings.

## Your Role — Orchestrate, Don't Review

You are a **coordinator**. You delegate review work to `reviewer-agent` instances via the Agent tool and validate their outputs in the judge pass. You do NOT review code yourself — you read files only to gather context and verify agent findings.

## Three-Phase Process

### Phase 1: Collect Context & Triage
- Parse input (files, git diff range, branch)
- Read changed files and understand modifications
- Build context map of what changed and why
- Identify file types and affected modules
- **Count changed files and lines of code (LOC)**

**Triage (for large diffs):** If diff has >8 files or >400 LOC, classify files before full review:
- **Trivial**: Renames, formatting-only, import reordering, generated files, lock files → skip full review (mention in summary as "triaged out")
- **Substantive**: Logic changes, new code, API changes, security-sensitive → full review
- This can be done inline by the orchestrator (read each diff hunk, classify) — no subagent needed.

### Phase 2: Spawn Sub-Reviewers (Parallel, Adaptive Batching)

**Determine review mode based on diff size:**

**Small diff (≤8 substantive files, ≤400 LOC):** Standard mode — 5 reviewers, each sees ALL files.

**Large diff (>8 substantive files or >400 LOC):** Batched mode — split files into batches, spawn reviewers per batch.

#### Step 0: Load criteria files (both modes)

Before spawning any reviewers, read these criteria files — their content is pre-inlined into each agent's prompt:
- `.claude/skills/review/bugs-criteria.md`
- `.claude/skills/review/security-criteria.md`
- `.claude/skills/review/architecture-criteria.md`
- `.claude/skills/review/tests-criteria.md`
- `.claude/skills/review/guidelines-criteria.md`

#### Standard Mode (small diff)

Spawn all five reviewer agents **in a single message** for parallel execution:

```
Agent(subagent_type="reviewer-agent", prompt="""
DIMENSION: bugs
CRITERIA: [content of bugs-criteria.md]
CHANGED FILES: [list of files with their full content]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
DIFF CONTEXT: [git diff summary showing what changed — used to tag findings as [NEW] vs [PRE-EXISTING]]
Review ONLY for bugs and correctness. Do not cross into other dimensions.
""")

Agent(subagent_type="reviewer-agent", prompt="""
DIMENSION: security
CRITERIA: [content of security-criteria.md]
CHANGED FILES: [list of files with their full content]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
DIFF CONTEXT: [git diff summary]
Review ONLY for security vulnerabilities. Do not cross into other dimensions.
""")

Agent(subagent_type="reviewer-agent", prompt="""
DIMENSION: architecture
CRITERIA: [content of architecture-criteria.md]
CHANGED FILES: [list of files with their full content]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
DIFF CONTEXT: [git diff summary]
Review ONLY for architecture and design patterns. Do not cross into other dimensions.
""")

Agent(subagent_type="reviewer-agent", prompt="""
DIMENSION: tests
CRITERIA: [content of tests-criteria.md]
CHANGED FILES: [list of files with their full content]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
DIFF CONTEXT: [git diff summary]
Review ONLY for test quality and coverage. Do not cross into other dimensions.
""")

Agent(subagent_type="reviewer-agent", prompt="""
DIMENSION: guidelines
CRITERIA: [content of guidelines-criteria.md]
CHANGED FILES: [list of files with their full content]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
DIFF CONTEXT: [git diff summary]
Review ONLY for style, naming, and guideline compliance. Do not cross into other dimensions.
""")
```

**Dimensions:**
1. **Bugs Reviewer** — Logic errors, null checks, off-by-one, state issues
2. **Security Reviewer** — Injection, auth/authz, secrets, crypto, validation
3. **Architecture Reviewer** — Design patterns, modularity, coupling, tech debt
4. **Tests Reviewer** — Coverage gaps, missing edge cases, test quality
5. **Guidelines Reviewer** — Style, naming, documentation, compliance

#### Batched Mode (large diff)

**Why batch?** LLMs exhibit a U-shaped attention curve — 30%+ accuracy drop when relevant context is in the middle of large prompts ([Liu et al., "Lost in the Middle"](https://arxiv.org/abs/2307.03172)). A reviewer given 20 files misses issues in files 8-15. Batching keeps each reviewer's context focused.

**Step 1: Group files into batches of ~5 files each.**
- Group by module/directory when possible (files in the same module are more coherent to review together)
- Keep test files with their source files in the same batch
- Example: 15 substantive files → Batch A (5 files), Batch B (5 files), Batch C (5 files)

**Step 2: Determine which dimensions apply per batch.**
Not every batch needs all 5 dimensions. Skip irrelevant ones to save tokens:
- Test-only batch → skip security, architecture. Run: bugs, tests, guidelines
- Config/infra batch → skip tests. Run: security, architecture, guidelines
- UI component batch → skip security (unless auth-related). Run: bugs, architecture, tests, guidelines
- API/auth batch → all 5 dimensions

**Step 3: Spawn batch × dimension agents in a single message.**

Use the same `Agent(subagent_type="reviewer-agent", prompt="""...""")` pattern as standard mode, but each agent gets only its batch's files. Include `DIFF CONTEXT` for [NEW]/[PRE-EXISTING] tagging.

```
Example for 15 files, 3 batches:
  Batch A (auth module, 5 files):   bugs-A, security-A, architecture-A, tests-A, guidelines-A  → 5 agents
  Batch B (UI components, 5 files): bugs-B, architecture-B, tests-B, guidelines-B              → 4 agents (no security)
  Batch C (test utilities, 5 files): bugs-C, tests-C, guidelines-C                             → 3 agents (no security/arch)
  Total: 12 agents (vs 5 in standard mode, but each has 1/3 the files = much higher accuracy)
```

**Constraints:**
- Max **15 parallel agents** (5 batches × 3 dimensions is a practical ceiling)
- Each agent gets: criteria file + its batch's file contents only + brief summary of other batches for cross-reference context
- All agents spawned in ONE message for parallel execution

#### Build Verification (parallel with reviewers, both modes)

Run the project's validation suite **in parallel** with the reviewer agents. This catches build failures and test regressions that no reviewer can detect:

```bash
source .claude/hooks/backpressure.sh && run_silent "Build Check" "<validation_cmd from CLAUDE.md>"
```

If backpressure is unavailable, run directly: `<validation_cmd> 2>&1 | tail -80`

Feed the pass/fail result into the Phase 3 judge pass. A failing build is automatically a CRITICAL finding — tag as [NEW] if the base branch build passes, or [PRE-EXISTING] if it was already broken.

### Phase 3: Judge Pass

**If batched mode:** First deduplicate findings across batches — the same issue may be flagged by multiple batch reviewers if it spans modules. Merge duplicates, keeping the highest confidence score.

- Read each finding's source context (file + line range)
- Validate: does the issue actually exist? Check for mitigating context
- Preserve [NEW]/[PRE-EXISTING] tags from reviewers — findings in changed lines are [NEW], findings in unchanged code are [PRE-EXISTING]. Prioritize [NEW] findings in the report.
- **Build verification:** If build/test verification ran in parallel, incorporate its result — a failing build is automatically a CRITICAL finding (tag [NEW] or [PRE-EXISTING] based on base branch state).
- Confidence scoring:
  - **Confirmed**: stays 100 or increases
  - **Ambiguous**: -20 (needs context)
  - **Pattern elsewhere**: -40 (systemic, lower individual severity)
  - **False positive**: rejected (0)
- Filter: keep only findings >= 80 confidence
- Classify:
  - **Critical**: MUST FIX (high-severity, high-confidence)
  - **High**: SHOULD FIX (medium-severity OR repeating pattern)
  - **Medium**: MINOR (low-severity, informational)
- Aggregate by file and severity
- Output final verdict with prioritized recommendations

## Input Formats

- **Files**: `review src/auth.js src/db.js`
- **Git diff**: `review HEAD~5..HEAD`
- **Branch**: `review feature/auth`
- **Current changes**: `review` (no args = unstaged + staged changes)

## Output Structure

```
## Review Summary
- Files analyzed: N
- Issues found: N (CRITICAL: X, HIGH: Y, MEDIUM: Z)
- Overall confidence: XX%

## Critical Issues (MUST FIX)
### [CRITICAL] [NEW] Issue Title
- File: path/to/file.js:42-48
- Severity: [security|logic|performance]
- Finding: [specific description]
- Evidence: [code snippet or pattern]
- Recommendation: [action to take]
- Confidence: 95%

## High Priority Issues
[Same format]

## Medium Priority Issues
[Same format]

## Review Confidence
- Bugs analysis: 92%
- Security analysis: 88%
- Architecture analysis: 85%
- Tests analysis: 90%
- Guidelines analysis: 94%
- Judge validation: 89%
```

## Confidence Scoring Rules

1. **Validation Check** (adjust from 100):
   - Does the exact issue exist in code? -0 if yes, -20 if unclear
   - Is there mitigating context/exception? -10 to -30
   - How widespread is the pattern? -40 if elsewhere, -10 if isolated

2. **Filter Threshold**: 80 confidence minimum
   - Above 80: include in report
   - 70-79: mention in "minor" section only
   - Below 70: discard (too noisy)

3. **Classification**:
   - CRITICAL: security vulnerability OR logic bug with high impact
   - HIGH: architecture issue OR pattern in multiple places OR test gap
   - MEDIUM: style/documentation OR low-impact suggestion

## Parallel Execution Strategy

All five reviewers are spawned as independent `reviewer-agent` instances via the Agent tool:
- Each agent receives ONE criteria file, the changed files, and the diff context
- All five (or more in batched mode) are spawned in a SINGLE message for parallel execution
- Each reviewer is a leaf agent — it cannot spawn sub-agents (by design)
- Judge pass reads all outputs and validates findings

## Common False Positives to Avoid

- **Defensive coding confusion**: Extra null checks aren't always wrong (context matters)
- **Async complexity**: Async/await or promises aren't inherently bad
- **Temporary/debug code**: Check if code is intentionally disabled
- **Third-party integration**: Don't flag patterns required by external APIs
- **Legacy compatibility**: Old patterns may exist for backwards compatibility
- **Configuration-driven behavior**: Don't flag behavior that's configurable elsewhere

## Tips for Best Results

1. Review focused changes (single feature/fix) yields better results than large refactors
2. Provide context: mention what changed and why in your input
3. Review diff ranges rather than whole files when possible
4. Read critical findings' source code to understand context
5. CRITICAL+HIGH findings are actionable; MEDIUM are suggestions
6. Confidence scores guide priority, not absolute judgment
7. For large PRs (20+ files): batched mode activates automatically, splitting files across reviewer agents for better accuracy
8. If you see quality drop on large reviews, try splitting into smaller review runs (e.g., review backend files separately from frontend)

## Integration with CI/CD

Can be used in pull request checks:
- Run on feature branch: `review feature/my-feature`
- Compare to main: `review main..feature/my-feature`
- Output can be formatted for GitHub comments, Slack, or email
- Threshold-based gating: block merge if CRITICAL findings exist

## Example Workflow

```
$ review src/auth/login.js src/auth/logout.js
Analyzing 2 files with 47 lines changed...

Spawning parallel reviewers:
  - Bugs reviewer (async pattern detection)
  - Security reviewer (injection points, auth flows)
  - Architecture reviewer (module dependencies)
  - Tests reviewer (coverage analysis)
  - Guidelines reviewer (code style)

[Reviewers execute in parallel: ~5-8 seconds]

Validating 12 findings...
- 8 pass confidence threshold
- 4 filtered (< 80% confidence)

## Review Summary
Files: 2 | Issues: 8 (1 CRITICAL, 3 HIGH, 4 MEDIUM)

## CRITICAL ISSUES (1)
[SQL Injection in login.js:34-38] ...

## HIGH PRIORITY (3)
[Missing logout validation] ...
[Weak password check] ...
[Race condition in session] ...

## MEDIUM PRIORITY (4)
[Inconsistent error messages] ...
[Missing JSDoc comments] ...
...

Overall Assessment: APPROVE WITH CHANGES
```

## Phase 4: Learn & Improve

After delivering the review summary, extract knowledge and suggest improvements. **Skip this phase when `/geniro:review` is called as a sub-phase within `/geniro:implement`** (the parent pipeline handles learnings in Phase 7). Only run when `/geniro:review` is invoked standalone.

### Extract Learnings

Scan the review findings for patterns worth remembering:
- **Recurring anti-patterns** found across multiple files → save as `project` memory (helps future implementations avoid the same mistakes)
- **False positives** where a finding looked real but wasn't (framework-specific pattern, intentional deviation) → save as `feedback` memory (improves future review accuracy)
- **User corrections** on review findings — "that's not a bug, it's intentional because..." → save as `feedback` memory (calibrates future reviews)

Before writing, check if an existing memory covers this topic — UPDATE rather than duplicate. Skip if nothing novel was discovered.

### Suggest Improvements

Check if the review revealed harness improvement opportunities:

| Category | What to look for | Target files |
|---|---|---|
| **Rules gaps** | Same anti-pattern found in multiple places? A rule would prevent it. | `.claude/rules/*.md` |
| **Criteria gaps** | Reviewer missed a bug class that should be checked? | `.claude/skills/review/*-criteria.md` |
| **Agent prompt gaps** | Implementation agent produced a pattern the reviewer flagged? | `.claude/agents/*.md` |
| **Stale rules** | A rule flagged something that turns out to be correct? | `.claude/rules/*.md` |

For each improvement found, present to the user:
```
The review revealed potential harness improvements:

1. [Rule gap] No rule prevents [anti-pattern] — suggest adding to backend-conventions.md
2. [Criteria gap] Security criteria don't check for [vulnerability class] — suggest adding

A) Apply all improvements
B) Review one-by-one
C) Skip
```

If user approves, draft and apply. If no improvements found, skip silently.

## Definition of Done

Code review is complete when:
- [ ] Phase 1 context collected (files read, changes understood)
- [ ] Phase 2 reviewers spawned and executed in parallel
- [ ] All 5 reviewers (bugs, security, architecture, tests, guidelines) completed
- [ ] Phase 3 judge validation complete (findings verified)
- [ ] Confidence scoring applied (>=80 threshold)
- [ ] Issues classified by severity (Critical, High, Medium)
- [ ] Findings tagged as [NEW] or [PRE-EXISTING] based on diff context
- [ ] Review summary generated with all findings
- [ ] Output delivered with actionable recommendations
- [ ] Learnings extracted (standalone invocations only)
- [ ] Improvement suggestions presented (standalone invocations only)

---

## Compliance — Do Not Skip Phases

| Your reasoning | Why it's wrong |
|---|---|
| "I can skip context gathering" | Without understanding what changed and why, you'll produce false positives and miss real issues. |
| "I'll review all aspects myself instead of spawning 5 agents" | Serial review misses perspective. All 5 specialized reviewers MUST execute in parallel. |
| "The reviewers found good stuff, skip judge validation" | Unfiltered findings create report fatigue. Only >=80 confidence findings provide signal. |
| "I can tell this is a real issue without reading the source" | Always validate findings in context — check the actual file and lines before reporting. |
| "While I'm here, let me suggest improvements beyond the diff" | Review against the scope of changes, not "what else could be improved." Stay focused. |
| "The agent said it thoroughly reviewed everything" | Agents self-report optimistically. Verify by reading their actual outputs yourself. |

**Merge confidently without addressing CRITICAL findings:** CRITICAL issues MUST be fixed before shipping.

---
