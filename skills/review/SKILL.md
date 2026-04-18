---
name: geniro:review
description: "Parallel multi-agent code review with 5–6 specialized reviewers (bugs, security, architecture, tests, guidelines, +design when UI files present). Confidence-scored findings automatically filtered. Use for comprehensive code quality assessment."
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

Comprehensive code review using parallel multi-agent analysis. 5–6 specialized reviewers examine code changes simultaneously (design reviewer added when UI files are present), then a relevance filter validates findings against repo conventions and complexity level, and a judge pass confidence-scores and aggregates the results.

## Your Role — Orchestrate, Don't Review

You are a **coordinator**. You delegate review work to `reviewer-agent` instances via the Agent tool and validate their outputs in the judge pass. You do NOT review code yourself — you read files only to gather context and verify agent findings.

## Subagent Model Tiering

Follow the canonical rule in `skills/_shared/model-tiering.md`. Every `Agent(...)` spawn MUST pass `model=` explicitly.

**Skill-specific mapping** — reviewer dimension drives model choice:

| Spawn | Tier | Why |
|---|---|---|
| `reviewer-agent` (bugs, security, architecture, tests) | `sonnet` | Reasoning-heavy review |
| `reviewer-agent` (guidelines, design) | `haiku` | Rubric-based — pattern matching against checklist |
| `relevance-filter-agent` | `sonnet` | Adversarial validation against repo conventions |
| Per-finding validation sub-agents (CRITICAL/HIGH) | `sonnet` | Reasoning about whether finding is real |

## Review Process

### Phase 1: Collect Context & Triage
- Parse input (files, git diff range, branch)
- Load custom instructions from `.geniro/instructions/global.md` and `.geniro/instructions/review.md`. Read any found. Apply rules as constraints, additional steps at specified phases, and hard constraints.
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

**Small diff (≤8 substantive files, ≤400 LOC):** Standard mode — 5 reviewers (+1 design when UI files present, see detection rule below), each sees ALL files.

**Large diff (>8 substantive files or >400 LOC):** Batched mode — split files into batches, spawn reviewers per batch.

#### Step 0: Load criteria files (both modes)

Before spawning any reviewers, read these criteria files — their content is pre-inlined into each agent's prompt:
- `${CLAUDE_SKILL_DIR}/bugs-criteria.md`
- `${CLAUDE_SKILL_DIR}/security-criteria.md`
- `${CLAUDE_SKILL_DIR}/architecture-criteria.md`
- `${CLAUDE_SKILL_DIR}/tests-criteria.md`
- `${CLAUDE_SKILL_DIR}/guidelines-criteria.md`
- `${CLAUDE_SKILL_DIR}/design-criteria.md` (conditional — only loaded when the UI-file detection rule below matches at least one changed file)

Also read `CLAUDE.md` at the project root for tech stack context — use this to interpret criteria in the context of the project's language and framework.

#### Standard Mode (small diff)

Spawn all five reviewer agents **in a single message** for parallel execution. **Spawn the design reviewer (6th agent) ONLY when at least one changed file matches the UI-file detection rule defined below.**

```
Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
DIMENSION: bugs
CRITERIA: [content of bugs-criteria.md]
CHANGED FILES: [list of files with their full content]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
DIFF CONTEXT: [git diff summary showing what changed — used to tag findings as [NEW] vs [PRE-EXISTING]]
Review ONLY for bugs and correctness. Do not cross into other dimensions.
""")

Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
DIMENSION: security
CRITERIA: [content of security-criteria.md]
CHANGED FILES: [list of files with their full content]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
DIFF CONTEXT: [git diff summary]
Review ONLY for security vulnerabilities. Do not cross into other dimensions.
""")

Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
DIMENSION: architecture
CRITERIA: [content of architecture-criteria.md]
CHANGED FILES: [list of files with their full content]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
DIFF CONTEXT: [git diff summary]
Review ONLY for architecture and design patterns. Do not cross into other dimensions.
""")

Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
DIMENSION: tests
CRITERIA: [content of tests-criteria.md]
CHANGED FILES: [list of files with their full content]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
DIFF CONTEXT: [git diff summary]
Review ONLY for test quality and coverage. Do not cross into other dimensions.
""")

Agent(subagent_type="reviewer-agent", model="haiku", prompt="""
DIMENSION: guidelines
CRITERIA: [content of guidelines-criteria.md]
CHANGED FILES: [list of files with their full content]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
DIFF CONTEXT: [git diff summary]
Review ONLY for style, naming, and guideline compliance. Do not cross into other dimensions.
""")

# Conditional — spawn ONLY if at least one changed file matches the UI-file detection rule below.
Agent(subagent_type="reviewer-agent", model="haiku", prompt="""
DIMENSION: design
CRITERIA: [content of design-criteria.md]
CHANGED FILES: [list of files with their full content]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
DIFF CONTEXT: [git diff summary]
Review ONLY for visual/UX quality per the design rubric. Do not cross into other dimensions.
""")
```

### UI-file detection rule

Used by the conditional design reviewer. A file is considered a UI file if its path matches any of these globs — `**/components/**`, `**/pages/**`, `**/app/**`, `**/views/**`, `**/ui/**` — or its extension is one of `.tsx`, `.jsx`, `.vue`, `.svelte`, `.css`, `.scss`, `.sass`, `.less`, `.styled.ts`, `.styled.tsx`. The design dimension is skipped entirely when no changed file matches.

**Dimensions:**
1. **Bugs Reviewer** — Logic errors, null checks, off-by-one, state issues
2. **Security Reviewer** — Injection, auth/authz, secrets, crypto, validation
3. **Architecture Reviewer** — Design patterns, modularity, coupling, tech debt
4. **Tests Reviewer** — Coverage gaps, missing edge cases, test quality
5. **Guidelines Reviewer** — Style, naming, documentation, compliance
6. **Design Reviewer (conditional)** — Visual/UX quality: token conformance, spacing/type scale, state completeness, WCAG AA contrast, responsive coverage, exemplar drift. Fires only when the diff contains UI files (see detection rule above).

**Model routing:** Guidelines and design use `haiku` (sufficient for rubric checks, saves tokens). Bugs, security, architecture, and tests use `sonnet` (accuracy-critical). In batched mode, apply the same model per dimension.

#### Batched Mode (large diff)

**Why batch?** LLMs exhibit a U-shaped attention curve — 30%+ accuracy drop when relevant context is in the middle of large prompts ([Liu et al., "Lost in the Middle"](https://arxiv.org/abs/2307.03172)). A reviewer given 20 files misses issues in files 8-15. Batching keeps each reviewer's context focused.

**Step 1: Group files into semantic batches of ~5 files each.**
- Analyze files by **domain responsibility**, not just directory: auth concern, data layer, API surface, UI components, infrastructure/config, tests
- Group files that share a domain concern into the same batch (e.g., auth controller + auth middleware + auth test = one batch)
- Use signals to determine responsibility: file path patterns, import relationships (grep for cross-file imports), naming conventions
- Fall back to directory grouping when fewer than 2 of the 3 signals (path pattern, import relationship, naming convention) agree on a domain for a file
- Keep test files with their corresponding source files in the same batch
- Example: 15 files → Batch A (auth: controller + middleware + test), Batch B (API: routes + validators + serializers), Batch C (infra: config + migrations + seeds)

**Step 2: Determine which dimensions apply per batch.**
Not every batch needs all 5–6 dimensions. Skip irrelevant ones to save tokens. Use the UI-file detection rule above to decide whether a batch gets the design dimension:
- Test-only batch → skip security, architecture, design. Run: bugs, tests, guidelines
- Config/infra batch → skip tests, design. Run: security, architecture, guidelines
- UI component batch → skip security (unless auth-related). Run: bugs, architecture, tests, guidelines, design
- API/auth batch → all 5 dimensions (design only if it also contains UI files — rare)

**Step 3: Spawn batch × dimension agents in a single message.**

Use the same `Agent(subagent_type="reviewer-agent", model=<sonnet|haiku>, prompt="""...""")` pattern as standard mode, but each agent gets only its batch's files. Per the Subagent Model Tiering block, pass `model="sonnet"` for bugs/security/architecture/tests and `model="haiku"` for guidelines/design. Include `DIFF CONTEXT` for [NEW]/[PRE-EXISTING] tagging.

```
Example for 15 files, 3 batches:
  Batch A (auth module, 5 files):   bugs-A, security-A, architecture-A, tests-A, guidelines-A       → 5 agents
  Batch B (UI components, 5 files): bugs-B, architecture-B, tests-B, guidelines-B, design-B         → 5 agents (no security; +design)
  Batch C (test utilities, 5 files): bugs-C, tests-C, guidelines-C                                  → 3 agents (no security/arch/design)
  Total: 13 agents (vs 5 in standard mode, but each has 1/3 the files = much higher accuracy)
```

**Constraints:**
- Max **18 parallel agents** (5 batches × up to 6 dimensions when UI files present)
- Each agent gets: criteria file + its batch's file contents only + brief summary of other batches for cross-reference context
- All agents spawned in ONE message for parallel execution

#### Build Verification (parallel with reviewers, both modes)

Run the project's validation suite **in parallel** with the reviewer agents. This catches build failures and test regressions that no reviewer can detect:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" && run_silent "Build Check" "<validation_cmd from CLAUDE.md>"
```

If backpressure is unavailable, run directly: `<validation_cmd> 2>&1 | tail -80`

Feed the pass/fail result into the Phase 4 judge pass. A failing build is automatically a CRITICAL finding — tag as [NEW] if the base branch build passes, or [PRE-EXISTING] if it was already broken.

### Phase 3: Relevance Filter

After reviewers complete, spawn a **relevance-filter-agent** to check which findings actually apply to this repo. The agent receives all findings plus repo context, then verifies each finding against actual codebase patterns and complexity level.

**Why this step exists:** Reviewers apply general best practices, but not every best practice applies to every repo. A startup MVP doesn't need enterprise patterns. A repo that intentionally uses simple functions doesn't need dependency injection suggestions. This step filters findings that contradict repo conventions or suggest over-engineering.

**Convention context gathering:** Before spawning the agent, read convention files that exist in the project — CONTRIBUTING.md, ADRs (docs/adr/), architecture docs. Pass their content alongside CLAUDE.md context.

Spawn the relevance filter agent:

```
Agent(subagent_type="relevance-filter-agent", model="sonnet", prompt="""
FINDINGS: [all findings from all reviewers (5 or 6), in their original format]
CHANGED FILES: [list of changed file paths — the agent reads files itself via Read/Glob/Grep]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
CONVENTION FILES: [content of CONTRIBUTING.md, ADRs, architecture docs if they exist]

Evaluate each finding against this repo's actual patterns. For each finding, check:
1. Convention alignment — does the suggestion match how this repo already works?
2. Over-engineering — is this YAGNI for this repo's complexity level?
3. Intentional pattern — does the flagged "problem" exist in 3+ other files intentionally?

Tag each finding as KEEP or FILTER with evidence.
CRITICAL severity findings (security vulnerabilities, data loss, crashes) are always KEEP.
""")
```

**Pass only KEEP findings to Phase 4 (Judge Pass).** FILTERED findings appear in a collapsed section at the end of the review report for transparency. If the relevance-filter-agent fails to complete or returns malformed output, pass all findings through to Phase 4 unfiltered (fail-open).

### Phase 4: Judge Pass

**Input:** Only KEEP findings from Phase 3 (relevance-filtered). FILTERED findings are excluded from scoring but listed in the final report for transparency.

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

### Phase 4b: Per-Finding Validation (Critical & High only)

For each CRITICAL or HIGH finding that passed the judge pass, spawn a **validation sub-agent** to independently confirm. Each validator gets the finding + full file context but NO knowledge of other findings (prevents anchoring).

**Why:** Anthropic's official code-review plugin uses this pattern — per-finding validation eliminates ~40% of false positives. The validator has fresh context and must independently reproduce the concern.

**Skip conditions:** If 0 Critical/High findings remain after Phase 4, skip to Phase 5. Always validate CRITICAL findings regardless of count; skip validation for HIGH findings only when there is exactly 1 HIGH and 0 CRITICAL.

Spawn all validators **in a single message** for parallel execution:

```
Agent(model="sonnet", prompt="""
TASK: Validate a single review finding. You are an independent validator — confirm or reject this finding.

FINDING: [severity, dimension, file:line, description, evidence]
FILE CONTENT: [full content of the affected file]
DIFF CONTEXT: [relevant diff hunk]

You must:
1. Read the file and line range yourself
2. Check if the issue genuinely exists
3. Check for mitigating context the original reviewer may have missed
4. Verdict: CONFIRMED (issue is real) or REJECTED (false positive, explain why)

Do NOT review for other issues — validate this ONE finding only.
""")
```

**Process results:**
- CONFIRMED findings: keep in final report at original severity
- REJECTED findings: demote to "Filtered by validation" section (visible but not actionable)
- If a validator fails to complete: keep the finding (fail-open)

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

## Filtered by Relevance (not applicable to this repo)
[List of findings that were filtered with 1-line reasons — e.g., "over-engineering for this repo's complexity level", "contradicts established repo pattern"]

## Review Confidence
- Bugs analysis: 92%
- Security analysis: 88%
- Architecture analysis: 85%
- Tests analysis: 90%
- Guidelines analysis: 94%
- Design analysis: XX% (when UI files present)
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

All 5–6 reviewers (+1 design when UI files present) are spawned as independent `reviewer-agent` instances via the Agent tool:
- Each agent receives ONE criteria file, the changed files, and the diff context
- All reviewers (or more in batched mode) are spawned in a SINGLE message for parallel execution
- Each reviewer is a leaf agent — it cannot spawn sub-agents (by design)
- Relevance filter checks findings against repo conventions, then judge pass confidence-scores the remaining findings

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

Spawning parallel reviewers (5–6, +design when UI files present):
  - Bugs reviewer (async pattern detection)
  - Security reviewer (injection points, auth flows)
  - Architecture reviewer (module dependencies)
  - Tests reviewer (coverage analysis)
  - Guidelines reviewer (code style)

[Reviewers execute in parallel: ~5-8 seconds]

Running relevance filter against repo conventions...
- 10 of 12 findings kept
- 2 filtered (over-engineering for this repo's complexity level)

Judge pass on 10 findings...
- 8 pass confidence threshold (>=80)
- 2 filtered (< 80% confidence)

Validating 4 Critical/High findings (per-finding validators)...
- 3 confirmed, 1 rejected (false positive — mitigating context found)

## Review Summary
Files: 2 | Issues: 7 (1 CRITICAL, 2 HIGH, 4 MEDIUM)

## CRITICAL ISSUES (1)
[SQL Injection in login.js:34-38] ...

## HIGH PRIORITY (2)
[Missing logout validation] ...
[Race condition in session] ...

## MEDIUM PRIORITY (4)
[Inconsistent error messages] ...
[Missing JSDoc comments] ...
...

Overall Assessment: APPROVE WITH CHANGES
```

## Phase 5: Learn & Improve

After delivering the review summary, extract knowledge and suggest improvements. **Skip this phase when `/geniro:review` is called as a sub-phase within `/geniro:implement`** (the parent pipeline handles learnings in Phase 7). Only run when `/geniro:review` is invoked standalone.

### Extract Learnings

Scan the review findings for patterns worth remembering:
- **Recurring anti-patterns** found across multiple files → save as `project` memory (helps future implementations avoid the same mistakes)
- **False positives** where a finding looked real but wasn't (framework-specific pattern, intentional deviation) → save as `feedback` memory (improves future review accuracy)
- **User corrections** on review findings — "that's not a bug, it's intentional because..." → save as `feedback` memory (calibrates future reviews)

Before writing, check if an existing memory covers this topic — UPDATE rather than duplicate. Skip if nothing novel was discovered.

### Suggest Improvements

Check if the review revealed improvement opportunities. Classify each by **routing target**:

| What was discovered | Route to | Why |
|---|---|---|
| Reviewer missed a bug class that should be checked | **Review criteria** | `${CLAUDE_SKILL_DIR}/*-criteria.md` |
| Implementation agent produced a flagged anti-pattern | **Agent prompt** | `${CLAUDE_PLUGIN_ROOT}/agents/*.md` |
| Security pattern that should be blocked automatically | **Rules/hooks** | Automated enforcement beats manual detection |
| Recurring false positive revealing undocumented convention | **CLAUDE.md** | Document the convention so reviewers don't flag it |
| Non-obvious insight about codebase quality | **Knowledge** (learnings.jsonl) | Context for future reviews |
| Review rule the user enforced manually (e.g., "always check X") | **Custom instructions** | `.geniro/instructions/review.md` — persists as review-specific rule |

Present via `AskUserQuestion` with header "Improvements": "Apply all" / "Review one-by-one" / "Skip". Group by target. If no improvements found, skip silently.

## Definition of Done

Code review is complete when:
- [ ] Phase 1 context collected (files read, changes understood)
- [ ] Phase 2 reviewers spawned and executed in parallel
- [ ] All 5–6 reviewers completed (5 always, +1 design when UI files present)
- [ ] Phase 3 relevance filter applied (findings checked against repo conventions and complexity)
- [ ] Phase 4 judge validation complete (findings verified)
- [ ] Phase 4b per-finding validation run for Critical/High findings (if applicable)
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
| "I'll review all aspects myself instead of spawning the reviewer agents" | Serial review misses perspective. All 5–6 specialized reviewers MUST execute in parallel. |
| "The reviewers found good stuff, skip relevance filtering" | Reviewers apply general best practices — without checking against THIS repo's patterns, you'll report over-engineering suggestions and convention-contradicting findings that waste engineer time. |
| "The reviewers found good stuff, skip judge validation" | Unfiltered findings create report fatigue. Only >=80 confidence findings provide signal. |
| "I can tell this is a real issue without reading the source" | Always validate findings in context — check the actual file and lines before reporting. |
| "While I'm here, let me suggest improvements beyond the diff" | Review against the scope of changes, not "what else could be improved." Stay focused. |
| "The agent said it thoroughly reviewed everything" | Agents self-report optimistically. Verify by reading their actual outputs yourself. |
| "I can merge confidently without addressing CRITICAL findings" | CRITICAL issues MUST be fixed before shipping. They are non-negotiable. |

---
