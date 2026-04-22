---
name: geniro:review
description: "Parallel multi-agent code review with 5–6 specialized reviewers (bugs, security, architecture, tests, guidelines, +design when UI files present). Confidence-scored findings automatically filtered. Use for comprehensive code quality assessment."
context: main
model: inherit
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - Agent
  - AskUserQuestion
  - WebSearch
argument-hint: "[files, diff range, branch, or PR ref (#N, URL)]"
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
- Parse input. Detect the form: file paths, git diff range (e.g. `HEAD~5..HEAD`), branch name, or **PR ref** — a bare PR number (`#1234` or `1234`, resolved against the current repo) or a full GitHub PR URL (cross-repo OK). For a PR ref, strip any leading `#` and resolve it with `gh pr diff <number-or-url>` to materialize the diff and `gh pr view <number-or-url> --json baseRefName,headRefName` for base/head context, then feed the result into the rest of the pipeline exactly as if it were a local diff range. If `gh` is unavailable or the PR cannot be fetched, report the error to the user and stop — do not fall back silently to unstaged changes.
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

Spawn all five reviewer agents in **ONE response** — all Agent() calls in the same assistant turn, NOT one per turn. **Spawn the design reviewer (6th agent) ONLY when at least one changed file matches the UI-file detection rule defined below.**

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

**Step 3: Spawn batch × dimension agents in ONE response — all Agent() calls in the same assistant turn, NOT one per turn.**

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

### Phase 3: Relevance Evidence + Orchestrator Tagging

After reviewers complete, spawn a **relevance-filter-agent** to gather convention/over-engineering/pattern evidence per finding. **You (the orchestrator) then decide KEEP vs FILTER yourself** from the dossier — do NOT delegate the tagging decision.

**Why the split:** Reviewers apply general best practices, but not every best practice applies to every repo. A startup MVP doesn't need enterprise patterns. A repo that intentionally uses simple functions doesn't need dependency injection suggestions. Repo-reality evidence gathering is mechanical and belongs in a subagent; the KEEP/FILTER decision weighs convention evidence against severity and belongs at the orchestrator (Opus tier) where session context lives.

**Convention context gathering:** Before spawning the agent, read convention files that exist in the project — CONTRIBUTING.md, ADRs (docs/adr/), architecture docs. Pass their content alongside CLAUDE.md context.

Spawn the relevance-filter-agent for evidence gathering:

```
Agent(subagent_type="relevance-filter-agent", model="sonnet", prompt="""
FINDINGS: [all findings from all reviewers (5 or 6), in their original format]
CHANGED FILES: [list of changed file paths — the agent reads files itself via Read/Glob/Grep]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
CONVENTION FILES: [content of CONTRIBUTING.md, ADRs, architecture docs if they exist]

Gather evidence for each finding against this repo's actual patterns:
1. Convention alignment — does the suggestion match how this repo already works?
2. Over-engineering — is this YAGNI for this repo's complexity level?
3. Intentional pattern — does the flagged "problem" exist in 3+ other files intentionally?

Return an evidence dossier per finding (ALIGNS/CONTRADICTS/NEUTRAL, APPROPRIATE/OVER-ENGINEERED, ISOLATED/WIDESPREAD, safety_override for CRITICAL findings). Do NOT tag findings KEEP or FILTER — return evidence only; the orchestrator decides.
""")
```

**Orchestrator tagging:** After the dossier returns, synthesize it yourself per finding: weigh convention-alignment, over-engineering, and pattern-frequency evidence against severity and judge the finding KEEP or FILTER. CRITICAL findings (safety_override=true) are always KEEP regardless of convention evidence. Pass only KEEP findings to Phase 4 (Judge Pass). FILTERED findings appear in a collapsed section at the end of the review report for transparency. If the relevance-filter-agent fails to complete or returns malformed output, pass all findings through to Phase 4 as KEEP (fail-open); Phase 4 judge and Phase 4b validation still run normally on fail-open findings — only the convention-relevance layer is skipped.

### Phase 4: Judge Pass

**Input:** Only KEEP findings from Phase 3 (relevance-filtered). FILTERED findings are excluded from scoring but listed in the final report for transparency.

**If batched mode:** First deduplicate findings across batches — the same issue may be flagged by multiple batch reviewers if it spans modules. Merge duplicates, keeping the highest confidence score.

- Read each finding's source context (file + line range)
- Validate: does the issue actually exist? Check for mitigating context
- Preserve [NEW]/[PRE-EXISTING] tags from reviewers — findings in changed lines are [NEW], findings in unchanged code are [PRE-EXISTING]. Prioritize [NEW] findings in the report.
- **Build verification:** If build/test verification ran in parallel, incorporate its result — a failing build is automatically a CRITICAL finding (tag [NEW] or [PRE-EXISTING] based on base branch state).
- Confidence scoring: start from the reviewer's reported confidence, then adjust:
  - **Confirmed** (judge reproduces the issue from source): no change, or raise toward 100 if the reviewer under-scored
  - **Ambiguous** (needs more context to decide): −20
  - **Pattern elsewhere** (same code appears in 3+ other places unchanged): −40
  - **False positive** (judge cannot reproduce the issue from source): set to 0, rejected
- Filter: keep only findings with final confidence >= 80
- Classify:
  - **Critical**: MUST FIX (high-severity, high-confidence)
  - **High**: SHOULD FIX (medium-severity OR repeating pattern)
  - **Medium**: MINOR (low-severity, informational)
- Aggregate by file and severity
- Output final verdict with prioritized recommendations

### Phase 4b: Per-Finding Validation (Critical & High only)

For each CRITICAL or HIGH finding that passed the judge pass, spawn a **validation sub-agent** to independently confirm. Each validator gets the finding + full file context but NO knowledge of other findings (prevents anchoring).

**Why:** Anthropic's official code-review plugin uses this pattern — per-finding validation eliminates ~40% of false positives. The validator has fresh context and must independently reproduce the concern.

**Validation rules:**

| CRITICAL count | HIGH count | Validate |
|---|---|---|
| 0 | 0 | Skip entirely (proceed to Phase 5) |
| 0 | 1 | Skip (single HIGH isn't worth the spawn cost) |
| 0 | ≥2 | All HIGH |
| ≥1 | any | All CRITICAL + all HIGH |

Spawn all validators in **ONE response** — all Agent() calls in the same assistant turn, NOT one per turn:

```
Agent(subagent_type="general-purpose", model="sonnet", prompt="""
TASK: Validate a single review finding. You are an independent validator — confirm or reject this finding. You have Read, Glob, Grep, and Bash available for reproduction in step 4.

FINDING: [severity, dimension, file:line, description, evidence]
FILE CONTENT: [full content of the affected file]
DIFF CONTEXT: [relevant diff hunk]

You must:
1. Read the file and line range yourself
2. Check if the issue genuinely exists
3. Check for mitigating context the original reviewer may have missed
4. If the finding claims runtime behavior (crash, thrown error, regex/parser match, failing test, incorrect output), attempt a read-only reproduction: run `grep`/`rg` to confirm a pattern, or run the single existing test file that covers the code path (e.g. `pytest path/to/test_file.py::test_name`, `npx jest path/to/file.test.ts`). Allowed: read-only inspection and targeted single-test execution. Forbidden: full build, full test suite, migrations, installs, any write or file-creation command, network calls, `git` mutations (checkout, reset, stash, commit, push), container/VM spawns (`docker`, `podman`, `vagrant`), or any command that mutates persistent state. If a command is rejected by a project safety hook, treat the reproduction as impractical — do NOT retry or work around the hook; skip step 4 and rely on reasoning. If reproduction is otherwise impractical or unsafe, also skip and rely on reasoning.
5. Verdict: CONFIRMED (issue is real, with reproduction evidence if step 4 ran) or REJECTED (false positive, explain why)

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
- **PR ref**: `review #1234`, `review 1234`, or `review https://github.com/org/repo/pull/1234` — fetched via `gh pr diff <number-or-url>`; requires `gh` and a GitHub remote. For a PR in a different repo, use the full URL.
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

These rules expand the Phase 4 judge scoring. Baseline is always the reviewer's reported confidence, not a fixed 100.

1. **Adjustments to the reviewer's reported confidence:**
   - Issue reproduces from source: no change (or raise toward 100 if the reviewer under-scored)
   - Mitigating context/exception: −10 to −30
   - Same code appears in 3+ other places unchanged (pattern elsewhere): −40
   - Judge cannot reproduce the issue from source (false positive): set to 0, rejected

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
- All reviewers (or more in batched mode) are spawned in ONE response — all Agent() calls in the same assistant turn, NOT one per turn
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

See `${CLAUDE_SKILL_DIR}/learnings-reference.md` for a worked end-to-end example.

## Phase 5: Persist Findings to State

Write judge-validated findings to a state artifact so the next skill (or a resumed session) can consume them without re-running review. **Skip when `/geniro:review` is called as a sub-phase within `/geniro:implement`** (parent pipeline owns its own remediation loop).

**File:** `.claude/.artifacts/review-findings-state.md` — single file per branch, overwritten on each run.

**Schema (markdown with named sections):**

````
# Review Findings — <ISO 8601 timestamp>

## Summary
- branch: <current branch>
- input: <files | diff range | PR ref>
- files analyzed: N
- counts: CRITICAL=X, HIGH=Y, MEDIUM=Z
- build: pass | fail | not-run
- suggested next stage: /geniro:implement | /geniro:follow-up | none

## CRITICAL
- [NEW] path/to/file.ext:42-48 — <description> — recommendation: <action> — confidence: 95%
- ...

## HIGH
- ...

## MEDIUM
- ...

## Filtered
- path:line — <description> — reason: relevance | validation | confidence-below-threshold
````

Write the file even when zero actionable findings remain (empty severity sections, `suggested next stage: none`) — the artifact's existence signals "review ran, nothing to fix" to downstream skills and resumed sessions.

## Phase 5b: Learn & Improve

Extract knowledge and suggest project-scope improvements after delivering findings. **Skip when `/geniro:review` is called as a sub-phase within `/geniro:implement`** (parent pipeline handles learnings in Phase 7).

See `${CLAUDE_SKILL_DIR}/learnings-reference.md` for the full procedure (extract recurring anti-patterns, false positives, and user corrections; route project-scope improvements to CLAUDE.md / knowledge / project rules / custom instructions; offer via `AskUserQuestion`).

## Phase 6: Suggest Remediation

After Phase 5b, surface the next skill to fix what was found. **Skip when `/geniro:review` is called as a sub-phase within `/geniro:implement`** (parent owns its own fix loop), or when there are no actionable findings (CRITICAL + HIGH + MEDIUM all zero after Phase 4b).

**Severity-driven recommendation (must match the Phase 5 state file):**
- Any CRITICAL OR ≥2 HIGH findings → recommend `/geniro:implement` (full multi-agent pipeline, architecture-aware fixes)
- 0 CRITICAL AND ≤1 HIGH findings → recommend `/geniro:follow-up` (fast lane for trivial/small scope)

Use `AskUserQuestion` (do NOT print options as plain text) with header "Remediate". Mark the severity-recommended option with "(Recommended)" in its label. Options:
- **Run /geniro:implement** — full multi-agent pipeline; pre-load findings from `.claude/.artifacts/review-findings-state.md`
- **Run /geniro:follow-up** — fast lane; pre-load findings from the same file
- **Skip — I'll handle it manually** — no further action; state file remains for reference

Do NOT auto-invoke the next skill — surface the suggestion only. The user runs the slash command themselves; the state file path is the handoff channel.

## Definition of Done

Code review is complete when:
- [ ] Phase 1 context collected (files read, changes understood)
- [ ] Phase 2 reviewers spawned and executed in parallel
- [ ] All applicable reviewer dimensions completed (5 in standard mode, +1 design when UI files present; up to 18 parallel agents across batches in batched mode)
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
- [ ] Phase 5 state artifact written to `.claude/.artifacts/review-findings-state.md`
- [ ] Phase 6 remediation suggestion presented via `AskUserQuestion` (standalone invocations only)

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
| "I can skip writing the state file — the user can copy from chat" | The state file is the only handoff channel that survives compaction or session end. Findings in chat alone cannot reach the next skill. |
| "Findings are obvious — skip the AskUserQuestion and just tell them to run /implement" | Severity-driven recommendation is a structured choice (the user may want fast-lane follow-up for small scope, or to handle manually). Always offer the question; never assume. |

---
