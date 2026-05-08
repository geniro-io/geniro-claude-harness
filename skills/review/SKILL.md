---
name: geniro:review
description: "Use when you want a comprehensive code review of pending changes. Spawns 7–8 parallel reviewers (bugs, security, architecture, tests, optimizations, guidelines, conventions, +design when UI files present) with confidence-scored findings automatically filtered."
context: main
model: inherit
allowed-tools: [Read, Write, Glob, Grep, Bash, Agent, AskUserQuestion, WebSearch]
argument-hint: "[files, diff range, branch, or PR ref (#N, URL)] [--plan <path>] [--tdd]"
---

# Code Review Skill

Comprehensive code review using parallel multi-agent analysis. 7–8 specialized reviewers examine code changes simultaneously (design reviewer added when UI files are present), then a relevance filter validates findings against repo conventions and complexity level, and a judge pass confidence-scores and aggregates the results.

## Your Role — Orchestrate, Don't Review

You are a **coordinator**. You delegate review work to `reviewer-agent` instances via the Agent tool and validate their outputs in the judge pass. You do NOT review code yourself — you read files only to gather context and verify agent findings.

## Subagent Model Tiering

Follow the canonical rule in `skills/_shared/model-tiering.md`. Every `Agent(...)` spawn MUST pass `model=` explicitly. For plugin-defined subagents (reviewer, relevance-filter, adversarial-tester), also follow `skills/_shared/spawn-agent.md` — bare-name first; on `Agent type '<name>' not found`, degrade to `general-purpose` with the agent body inlined.

**Skill-specific mapping** — reviewer dimension drives model choice:

| Spawn | Tier | Why |
|---|---|---|
| `reviewer-agent` (bugs, security, architecture, tests, optimizations, conventions, design) | `sonnet` | Reasoning-heavy review (design covers visual/UX reasoning, token conformance, WCAG checks) |
| `reviewer-agent` (guidelines) | `haiku` | Rubric-based — pattern matching against checklist |
| `relevance-filter-agent` | `inherit` | Orchestrator-grade reasoning to weigh repo-convention evidence against reviewer findings (carve-out) |
| `adversarial-tester-agent` (Phase 4c only) | `inherit` | Reasoning-grade test authoring — synthesis tier mirrors orchestrator (carve-out) |
| Per-finding validation sub-agents (CRITICAL/HIGH) | `inherit` | Reasoning-grade verification — synthesis tier mirrors orchestrator (carve-out) |

## Review Process

### Phase 1: Collect Context & Triage
- **Scope:** follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` for target resolution (working tree → branch-vs-base diff → no-op). The base branch is whatever scope-anchor resolves it to (PR base, remote `origin/HEAD`, or local `main`/`master` fallback) — do NOT hardcode `main`. Report the resolved target on its own (e.g., "Reviewing working tree — 3 files" or "Reviewing branch diff against `origin/master` — 2 commits, 5 files") — do NOT preface it with harness "Auto Mode" framing. NEVER invoke `gh pr list` or any other PR-discovery command to invent a target — PR mode triggers ONLY on the explicit PR-ref forms enumerated below.
- **Harness Auto Mode handling:** `/geniro:review` has NO auto mode of its own. Follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/auto-mode-signals.md` §"Not a per-skill trigger" — do NOT promote the harness "Auto Mode Active" reminder into transcript framing (e.g., never announce "Auto mode → proceeding without prompting"). Scope resolution and Phase 4c's user-approval gate are governed by their own rules regardless of harness Auto Mode state.
- Parse input. Detect the form: file paths, git diff range (e.g. `HEAD~5..HEAD`), branch name, or **PR ref** — a bare PR number (`#1234` or `1234`, resolved against the current repo) or a full GitHub PR URL (cross-repo OK). For a PR ref, strip any leading `#` and resolve it with `gh pr diff <number-or-url>` to materialize the diff and `gh pr view <number-or-url> --json baseRefName,headRefName,body,title,headRefOid,url` for base/head context, head SHA pin, PR URL, plus PR body+title (the PR body feeds PLAN CONTEXT below). Capture the original PR ref (the `#N` / digits / URL form the user passed), the `headRefOid` value, and the canonical `url` — all three are persisted to the Phase 5 state file so Phase 6's PR-comment gate can fire without re-detection (the `headRefOid` is what Phase 6 pins as `commit_id` on the GitHub reviews API call to prevent line-anchor drift if the PR is updated mid-review). Then feed the diff into the rest of the pipeline exactly as if it were a local diff range. If `gh` is unavailable or the PR cannot be fetched, report the error to the user and stop — do not fall back silently to unstaged changes and do not run `gh pr list` to "find a related PR".
- Load custom instructions from `.geniro/instructions/global.md` and `.geniro/instructions/review.md`. Read any found. Apply rules as constraints, additional steps at specified phases, and hard constraints.
- **Collect PLAN CONTEXT** (optional) from these sources in priority order: (a) PR body+title from `gh pr view`; (b) `--plan <path>` flag in `$ARGUMENTS`; (c) auto-discovered `docs/spec.md`/`docs/plan.md`/`PLAN.md`/`SPEC.md`. Concat non-empty sources, cap ~3000 chars. See `${CLAUDE_SKILL_DIR}/plan-context-reference.md` for schema, decision-marker convention, and example. If nothing resolves, PLAN CONTEXT renders as `none` in every prompt below.
- **Detect mode**: scan `$ARGUMENTS` for `--tdd` (TDD mode — auto-author failing tests gates which findings get posted to PR) and `--standard` (explicit Standard mode). When neither flag is present, surface a startup `AskUserQuestion` after triage (see Phase 1 Step "Mode AUQ" below). Persist the resolved value to the Phase 5 state file's `mode:` line so Phase 4c and Phase 6 can read it without re-detection.
- Read changed files and understand modifications
- Build context map of what changed and why
- Identify file types and affected modules
- **Count changed files and lines of code (LOC)**

**Triage (for large diffs):** If diff has >8 files or >400 LOC, classify files before full review:
- **Trivial**: Renames, formatting-only, import reordering, generated files, lock files → skip full review (mention in summary as "triaged out")
- **Substantive**: Logic changes, new code, API changes, security-sensitive → full review
- This can be done inline by the orchestrator (read each diff hunk, classify) — no subagent needed.

**Mode AUQ (fires only when `$ARGUMENTS` contains neither `--tdd` nor `--standard`).** After triage, surface a single `AskUserQuestion` (do NOT print options as plain text) so the user can opt into TDD mode if they want comments gated on F→P-verified failing tests. When either flag is in `$ARGUMENTS`, the flag wins — the AUQ is skipped entirely. When the AUQ fires, capture the answer and persist it to the Phase 5 state file's `mode:` field.

- **Header:** "Review mode"
- **Question:** "Run a Standard review (post all kept findings) or a TDD review (only post findings backed by an F→P-verified failing test)?"
- **Options:**
  - "Standard review (Recommended)" — current behavior; Phase 4c gate is opt-in per-run as today; Phase 6 posts all kept findings.
  - "TDD review (auto-author failing tests for findings)" — Phase 4c gate's Recommended option flips to "Author tests for all eligible findings" (you still confirm with one keystroke — the gate is non-negotiable per Phase 4c Step 2). Phase 6 PR-comment posting filters to `[CONFIRMED-BY-TEST]` findings plus non-testable decision-types only.

If the user declines to answer (empty answer), default to Standard. The user's `--tdd`/`--standard` flag, if present, always overrides this AUQ. See `${CLAUDE_SKILL_DIR}/tdd-mode-reference.md` for what TDD mode flips, edge cases (no eligible findings, all tests pass green, `--tdd` with `--plan` or with sub-phase invocation), the F→P contract scope, and rollback notes.

### Phase 2: Spawn Sub-Reviewers (Parallel, Adaptive Batching)

**Determine review mode based on diff size:**

**Small diff (≤8 substantive files, ≤400 LOC):** Standard mode — 7 reviewers (+1 design when UI files present, see detection rule below), each sees ALL files.

**Large diff (>8 substantive files or >400 LOC):** Batched mode — split files into batches, spawn reviewers per batch.

#### Step 0: Load criteria files (both modes)

Before spawning any reviewers, read these criteria files — their content is pre-inlined into each agent's prompt:
- `${CLAUDE_SKILL_DIR}/bugs-criteria.md`
- `${CLAUDE_SKILL_DIR}/security-criteria.md`
- `${CLAUDE_SKILL_DIR}/architecture-criteria.md`
- `${CLAUDE_SKILL_DIR}/tests-criteria.md`
- `${CLAUDE_SKILL_DIR}/optimizations-criteria.md`
- `${CLAUDE_SKILL_DIR}/guidelines-criteria.md`
- `${CLAUDE_SKILL_DIR}/conventions-criteria.md`
- `${CLAUDE_SKILL_DIR}/design-criteria.md` (conditional — only loaded when the UI-file detection rule below matches at least one changed file)

Also read `CLAUDE.md` at the project root for tech stack context — use this to interpret criteria in the context of the project's language and framework.

#### Standard Mode (small diff)

Spawn all seven reviewer agents in **ONE response** — all Agent() calls in the same assistant turn, NOT one per turn. **Spawn the design reviewer (8th agent) ONLY when at least one changed file matches the UI-file detection rule defined below.** Every reviewer prompt carries a `PLAN CONTEXT:` field (Phase 1 collected; renders as `none` when empty) and this exact alignment-tag instruction appended at the end of the prompt body: `Findings that align with explicit plan decisions (e.g., "D-09: existing X are NOT backfilled") must be tagged [ALIGNS-WITH-PLAN]; findings that diverge must be tagged [DIVERGES-FROM-PLAN] — these route to INTENT-CHECK decision-type, not bug severity.`

```
Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
DIMENSION: bugs
CRITERIA: [content of bugs-criteria.md]
CHANGED FILES: [list of files with their full content]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
DIFF CONTEXT: [git diff summary showing what changed — used to tag findings as [NEW] vs [PRE-EXISTING]]
PLAN CONTEXT: [content from Phase 1, or "none"]
Review ONLY for bugs and correctness. Do not cross into other dimensions.
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""")

Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
DIMENSION: security
CRITERIA: [content of security-criteria.md]
CHANGED FILES: [list of files with their full content]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
DIFF CONTEXT: [git diff summary]
PLAN CONTEXT: [content from Phase 1, or "none"]
Review ONLY for security vulnerabilities. Do not cross into other dimensions.
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""")

Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
DIMENSION: architecture
CRITERIA: [content of architecture-criteria.md]
CHANGED FILES: [list of files with their full content]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
DIFF CONTEXT: [git diff summary]
PLAN CONTEXT: [content from Phase 1, or "none"]
Review ONLY for architecture and design patterns. Do not cross into other dimensions.
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""")

Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
DIMENSION: tests
CRITERIA: [content of tests-criteria.md]
CHANGED FILES: [list of files with their full content]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
DIFF CONTEXT: [git diff summary]
PLAN CONTEXT: [content from Phase 1, or "none"]
Review ONLY for test quality and coverage. Do not cross into other dimensions.
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""")

Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
DIMENSION: optimizations
CRITERIA: [content of optimizations-criteria.md]
CHANGED FILES: [list of files with their full content]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
DIFF CONTEXT: [git diff summary]
PLAN CONTEXT: [content from Phase 1, or "none"]
Review ONLY for SQL/ORM hydration, projection, React re-render hygiene, frontend bundle/asset perf, async parallelization, and bulk-ops wins. Do not cross into other dimensions (N+1, eager-loading, caching, pagination, sync-I/O are owned by the architecture dimension).
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""")

Agent(subagent_type="reviewer-agent", model="haiku", prompt="""
DIMENSION: guidelines
CRITERIA: [content of guidelines-criteria.md]
CHANGED FILES: [list of files with their full content]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
DIFF CONTEXT: [git diff summary]
PLAN CONTEXT: [content from Phase 1, or "none"]
Review ONLY for style, naming, and guideline compliance. Do not cross into other dimensions.
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""")

Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
DIMENSION: conventions
CRITERIA: [content of conventions-criteria.md]
CHANGED FILES: [list of files with their full content]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
DIFF CONTEXT: [git diff summary]
PLAN CONTEXT: [content from Phase 1, or "none"]
Review ONLY for codebase-pattern conformance via modal-pattern inference (sample siblings, flag deviations from ≥80% modal). Do not cross into other dimensions.
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""")

# Conditional — spawn ONLY if at least one changed file matches the UI-file detection rule below.
Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
DIMENSION: design
CRITERIA: [content of design-criteria.md]
CHANGED FILES: [list of files with their full content]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
DIFF CONTEXT: [git diff summary]
PLAN CONTEXT: [content from Phase 1, or "none"]
Review ONLY for visual/UX quality per the design rubric. Do not cross into other dimensions.
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""")
```

### UI-file detection rule

Used by the conditional design reviewer. A file is considered a UI file if its path matches any of these globs — `**/components/**`, `**/pages/**`, `**/app/**`, `**/views/**`, `**/ui/**` — or its extension is one of `.tsx`, `.jsx`, `.vue`, `.svelte`, `.css`, `.scss`, `.sass`, `.less`, `.styled.ts`, `.styled.tsx`. The design dimension is skipped entirely when no changed file matches.

**Dimensions:**
1. **Bugs Reviewer** — Logic errors, null checks, off-by-one, state issues
2. **Security Reviewer** — Injection, auth/authz, secrets, crypto, validation
3. **Architecture Reviewer** — Design patterns, modularity, coupling, tech debt
4. **Tests Reviewer** — Coverage gaps, missing edge cases, test quality
5. **Optimizations Reviewer** — SQL/ORM hydration skip (`.lean()` / `disableIdentityMap` / `raw:true` / projections), React re-render hygiene, frontend bundle/asset perf, async parallelization, bulk ops. Defers N+1 / eager-loading / caching / pagination / sync-I/O / O(n²) to architecture §6.
6. **Guidelines Reviewer** — Style, naming, documentation, compliance
7. **Conventions Reviewer** (always fires) — Codebase-pattern conformance: statistical inference of repo-modal patterns (file placement, declaration order, mixing-of-kinds, error-handling style, sibling consistency). Flags deviations only when ≥80% of N≥3 siblings agree on a pattern; skips ambiguous splits to avoid bikeshedding. Self-suppresses (emits zero findings) when fewer than 3 sibling files exist for inference.
8. **Design Reviewer (conditional)** — Visual/UX quality: token conformance, spacing/type scale, state completeness, WCAG AA contrast, responsive coverage, exemplar drift. Fires only when the diff contains UI files (see detection rule above).

**Model routing:** Guidelines uses `haiku` (sufficient for rubric checks, saves tokens). Bugs, security, architecture, tests, optimizations, conventions, and design use `sonnet` (accuracy-critical — conventions performs statistical pattern inference; design weighs visual/UX reasoning beyond pure rubric matching). In batched mode, apply the same model per dimension.

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
Not every batch needs all 7–8 dimensions. Skip irrelevant ones to save tokens. Use the UI-file detection rule above to decide whether a batch gets the design dimension:
- Test-only batch → skip security, architecture, optimizations, design. Run: bugs, tests, guidelines, conventions
- Config/infra batch → skip tests, design. Run: security, architecture, optimizations, guidelines, conventions
- UI component batch → skip security (unless auth-related). Run: bugs, architecture, tests, optimizations, guidelines, conventions, design
- API/auth batch → all 7 dimensions (design only if it also contains UI files — rare)

**Step 3: Spawn batch × dimension agents in ONE response — all Agent() calls in the same assistant turn, NOT one per turn.**

Use the same `Agent(subagent_type="reviewer-agent", model=<sonnet|haiku>, prompt="""...""")` pattern as standard mode, but each agent gets only its batch's files. Per the Subagent Model Tiering block, pass `model="sonnet"` for bugs/security/architecture/tests/optimizations/conventions/design and `model="haiku"` for guidelines. Include `DIFF CONTEXT` for [NEW]/[PRE-EXISTING] tagging, the same `PLAN CONTEXT:` field collected in Phase 1, and the same alignment-tag instruction as standard mode.

```
Example for 15 files, 3 batches:
  Batch A (auth module, 5 files):   bugs-A, security-A, architecture-A, tests-A, optimizations-A, guidelines-A, conventions-A       → 7 agents
  Batch B (UI components, 5 files): bugs-B, architecture-B, tests-B, optimizations-B, guidelines-B, conventions-B, design-B         → 7 agents (no security; +design)
  Batch C (test utilities, 5 files): bugs-C, tests-C, guidelines-C, conventions-C                                   → 4 agents (no security/arch/design)
  Total: 18 agents (vs 7 in standard mode, but each has 1/3 the files = much higher accuracy)
```

**Constraints:**
- Max **40 parallel agents** (5 batches × up to 8 dimensions when UI files present)
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
Agent(subagent_type="relevance-filter-agent", prompt="""
FINDINGS: [all findings from all reviewers (7 or 8), in their original format]
CHANGED FILES: [list of changed file paths — the agent reads files itself via Read/Glob/Grep]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
CONVENTION FILES: [content of CONTRIBUTING.md, ADRs, architecture docs if they exist]
PLAN CONTEXT: [content from Phase 1, or "none"]

Gather evidence for each finding against this repo's actual patterns:
1. Convention alignment — does the suggestion match how this repo already works?
2. Over-engineering — is this YAGNI for this repo's complexity level?
3. Intentional pattern — does the flagged "problem" exist in 3+ other files intentionally?

Return an evidence dossier per finding (ALIGNS/CONTRADICTS/NEUTRAL, APPROPRIATE/OVER-ENGINEERED, ISOLATED/WIDESPREAD, safety_override for CRITICAL findings). Do NOT tag findings KEEP or FILTER — return evidence only; the orchestrator decides.
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""")
```

**Orchestrator tagging:** After the dossier returns, synthesize it yourself per finding: weigh convention-alignment, over-engineering, and pattern-frequency evidence against severity and judge the finding KEEP or FILTER. CRITICAL findings (safety_override=true) are always KEEP regardless of convention evidence. Pass only KEEP findings to Phase 4 (Judge Pass). FILTERED findings appear in a collapsed section at the end of the review report for transparency. If the relevance-filter-agent fails to complete or returns malformed output, pass all findings through to Phase 4 as KEEP (fail-open); Phase 4 judge and Phase 4b validation still run normally on fail-open findings — only the convention-relevance layer is skipped. When fail-open triggers, surface "relevance-filter fail-open — convention check skipped for this run" under `## Caveats` in the final report. **User-facing language:** announce the fail-open in the live transcript using that same plain-English Caveats wording (e.g., "Convention-check filter timed out; passing all reviewer findings to the judge un-filtered. Final report will note the skipped step in Caveats."). Do NOT reference internal phase numbers (e.g., "Phase 4 Step −1"), skill-internal taxonomy ("TRUNCATED per skill rules", "fail-open per skill rules"), or other terms that require reading SKILL.md to parse.

### Phase 4: Judge Pass

**Input:** Only KEEP findings from Phase 3 (relevance-filtered). FILTERED findings are excluded from scoring but listed in the final report for transparency.

**If batched mode:** First deduplicate findings across batches — the same issue may be flagged by multiple batch reviewers if it spans modules. Merge duplicates, keeping the highest confidence score.

- **Step −1: Truncation check.** For each reviewer output, scan for the required `## Dimension Summary` footer (defined in `reviewer-agent.md` output template). If absent, the reviewer ran out of turns mid-analysis: mark that dimension as TRUNCATED, surface in the final report under `## Caveats` (e.g., "bugs reviewer truncated mid-analysis — partial output, recommend re-run with higher maxTurns"), and recommend re-running the dimension with higher maxTurns. Do not silently accept partial output. **User-facing language:** when announcing truncation in the live transcript, use plain-English wording matching the Caveats line — do NOT reference internal phase numbers ("Phase 4 Step −1") or skill-internal taxonomy ("TRUNCATED per skill rules") in user-facing output.
- **Step 0: Intent reconciliation.** For each finding tagged `[DIVERGES-FROM-PLAN]`, verify the divergence against PLAN CONTEXT. If the plan explicitly authorizes the divergence (e.g., D-09), demote to decision-type `[INTENT-CHECK]` and exclude from CRITICAL/HIGH severity. If the plan contradicts the finding (genuine divergence), keep as bug. Findings already tagged `[ALIGNS-WITH-PLAN]` exit the bug pipeline directly to `[INTENT-CHECK]`.
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
Agent(subagent_type="general-purpose", prompt="""
TASK: Validate a single review finding. You are an independent validator — confirm or reject this finding. You have Read, Glob, Grep, and Bash available for reproduction in step 4.

FINDING: [severity, dimension, file:line, description, evidence]
FILE CONTENT: [full content of the affected file]
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
DIFF CONTEXT: [relevant diff hunk]

You must:
1. Read the file and line range yourself
2. Check if the issue genuinely exists
3. Check for mitigating context the original reviewer may have missed
4. If the finding claims runtime behavior (crash, thrown error, regex/parser match, failing test, incorrect output), attempt a read-only reproduction: run `grep`/`rg` to confirm a pattern, or run the single existing test file that covers the code path (e.g. `pytest path/to/test_file.py::test_name`, `npx jest path/to/file.test.ts`). Allowed: read-only inspection and targeted single-test execution. Forbidden: full build, full test suite, migrations, installs, any write or file-creation command, network calls, `git` mutations (checkout, reset, stash, commit, push), container/VM spawns (`docker`, `podman`, `vagrant`), or any command that mutates persistent state. If a command is rejected by a project safety hook, treat the reproduction as impractical — do NOT retry or work around the hook; skip step 4 and rely on reasoning. If reproduction is otherwise impractical or unsafe, also skip and rely on reasoning.
5. Verdict: CONFIRMED (issue is real, with reproduction evidence if step 4 ran) or REJECTED (false positive, explain why)

Do NOT review for other issues — validate this ONE finding only.
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""")
```

**Process results:**
- CONFIRMED findings: keep in final report at original severity
- REJECTED findings: demote to "Filtered by validation" section (visible but not actionable)
- If a validator fails to complete: keep the finding (fail-open). Note "[dimension] validator failed for finding '<short title>' — kept fail-open" under `## Caveats` in the final report.

### Phase 4c: Test-Confirmation Gate (optional, user-gated)

**Purpose:** Reduce false positives by asking the user whether to spawn `adversarial-tester-agent` to author failing tests that confirm review findings. Tests that fail today on independent orchestrator re-run (F→P-confirmed) tag the corresponding finding `[CONFIRMED-BY-TEST]` and stay in the report. Tests that pass today (agent's `discarded-cannot-repro` signal) demote the finding to the `## Filtered` section with `[CHALLENGED-BY-TEST]` — finding stays visible to the user, deprioritized but not deleted. The skill MUST NEVER spawn the agent without explicit user approval — the gate is the load-bearing safety property, and inline gates degrade to "this counts as approval".

**Skip when `/geniro:review` is called as a sub-phase within `/geniro:implement`** (parent pipeline runs Phase 6 Stage D's adversarial test-author against the same diff; running it twice double-spawns the same agent against the same surface).

**Step 1: Filter findings by decision-type.**

Eligible findings: any finding whose `decision:` is `TESTABLE`, plus CRITICAL or HIGH findings whose `decision:` is `FIX-NOW` AND whose description names runtime behavior (regex match, parser output, control-flow branch, computed result, thrown error type). Excluded: findings whose `decision:` is `PRODUCT-DECISION` (multiple valid resolutions — no single behavior to assert), `INTENT-CHECK` (plan conformance, not runtime), and `FIX-NOW` findings whose description names typos / cross-references / wrong import paths (no runtime behavior to test against — see "Runtime-behavior classification" rule below). Use the decision-type taxonomy as defined in `${CLAUDE_SKILL_DIR}/plan-context-reference.md`.

If the eligible-findings set is empty after filtering, skip the rest of Phase 4c entirely — do NOT show an `AskUserQuestion`. Proceed to Phase 5.

**Runtime-behavior classification (canonical rule, used by both Phase 4c Step 1 and Phase 6 Step 3.5).** A `FIX-NOW` finding's description "names runtime behavior" if and only if it cites at least one of: regex match, parser output, control-flow branch (taken/not-taken), computed result, thrown error type, returned value, mutated state, observable side effect (DOM mutation, file write, API call, db query). A `FIX-NOW` finding's description is NON-runtime ("typo-class") if it cites: typo / spelling, cross-reference (link, anchor, ref number), wrong import path, dead code that compiles, comment-only edits, formatting, lint-style issues. Phase 4c Step 1 uses this rule to exclude non-runtime FIX-NOW from eligibility (no behavior to test against). Phase 6 Step 3.5 uses the same rule to retain non-runtime FIX-NOW findings in the TDD-mode post set (no test to gate on — they post directly). The rule is intentionally prose-based and decided at orchestrator-evaluation time; the per-finding line schema does NOT carry a persisted `runtime-class:` tag — both phases evaluate the rule fresh against the same finding description, so they cannot diverge.

**Step 2: User-approval gate (mandatory before any agent spawn).**

Use `AskUserQuestion` (do NOT print options as plain text — the tool provides a structured UI) with header "Test-gate". When the state-file `mode:` is `tdd`, render the first option's label as `"Author tests for all eligible findings (Recommended)"` (literal `(Recommended)` suffix on the label string itself, matching the canonical pattern at the Phase 1 Mode AUQ); in Standard mode, render the same option without the suffix. The gate itself is non-negotiable in every mode — the Phase 4c invariant ("this skill MUST NEVER spawn the agent without explicit user approval — the gate is the load-bearing safety property, and inline gates degrade to 'this counts as approval'") is the load-bearing safety property; mode flips only the highlighted default.

- **Question:** "Author failing tests to confirm review findings? Tests that pass today demote the corresponding finding to ## Filtered (kept visible, not deleted). The skill never writes tests without your approval."
- **Options:**
  - "Author tests for all eligible findings" — first option's literal label gains a ` (Recommended)` suffix when `mode: tdd` per the preamble above
  - "Let me pick which findings"
  - "Skip — don't author tests"

If user picks **"Skip"**, proceed to Phase 5 (no spawn, no state changes, no caveats).

If user picks **"Pick"**, chain `AskUserQuestion` calls (each with `multiSelect: true`) listing eligible findings. Each option's `label` is `path:line — short title — decision: <type>`; each option's `preview` carries the finding's full body (Evidence / Suggested-fix / Confidence / Origin) per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Multi-select pick loop — pull the body fields from in-memory reviewer-agent output (Phase 4c runs in the same invocation that produced findings; the artifact has not been written yet). AskUserQuestion has a 4-option cap; when more than 4 eligible findings exist, batch them across multiple chained questions (≤4 per call) — never drop or merge options to fit a single question. Aggregate selections across all calls into the eligible set. Filter to the user's union selection. If user deselects all, treat as "Skip" and proceed to Phase 5.

**Step 3: Spawn the adversarial-tester-agent.**

Spawn ONE `adversarial-tester-agent` (per the canonical model-tiering carve-out — frontmatter-declared `model: inherit`, omit `model=` at the spawn site to mirror orchestrator tier; reasoning-grade test authoring) with the eligible findings as hypothesis seeds. The agent already enforces F→P verification, 3× flake check, "test files only", and scope-locked-to-the-diff — no agent changes required. **Resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A (subagent without Bash) before sending the prompt: substitute the absolute path into `OUTPUT PATH:` below, and use the same resolved path on every subsequent read in Steps 4 and 5. The agent treats the path as a literal — passing the unresolved placeholder creates a literal `<PRIMARY_ROOT>` directory.**

```
Agent(subagent_type="adversarial-tester-agent", prompt="""
CHANGED FILES: [list of changed file paths with full content — pre-inlined from Phase 1]
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
DIFF: [git diff summary]
SHARED EDGE-CASE CHECKLIST: ${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md (READ at runtime; do not expect it inlined)
PROJECT TEST FRAMEWORK HINTS: [test command from CLAUDE.md, naming convention, 1-2 exemplar test files inlined]
PRIOR REVIEW FINDINGS (hypothesis seeds): [each eligible finding as: path:line — description — decision-type — severity]
OUTPUT PATH: <PRIMARY_ROOT>/.geniro/review-findings-adversarial.md

For each seeded finding, attempt to author a failing test that reproduces it. If the test cannot be made to fail on current code, mark the hypothesis `discarded-cannot-repro` per your existing protocol — that signal is load-bearing for this caller (it triggers a finding demotion in the orchestrator's downstream processing). You may also generate fresh hypotheses from the diff per your normal Step 2 workflow; treat seeded findings as priority-1 and fresh hypotheses as priority-2 within your hard cap of 10 authored tests.
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""")
```

**Step 4: Independent re-verification by the orchestrator.**

For EACH authored test in the agent's report's `### Authored Failing Tests (F→P verified)` section, the orchestrator runs the project's test command itself (a single re-run; the agent already did 3× flake check). Use `backpressure.sh` to keep failing-test output from flooding context:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" && run_silent "Test-gate re-run" "<project test command from CLAUDE.md> <test path>"
```

If `backpressure.sh` is unavailable, run directly: `<project test command> <test path> 2>&1 | tail -80`.

Capture exit code:
- Non-zero (red) → test STILL fails on independent re-run → keep authored test on disk; tag the corresponding finding `[CONFIRMED-BY-TEST]`.
- Zero (green) → test passes on independent re-run despite agent reporting it red → likely flake or framework issue. Note "[test path] flipped green on independent re-run" under `## Caveats`. Do NOT delete the test (the user reviews authored tests in Phase 6); do NOT tag the finding `[CONFIRMED-BY-TEST]`.

Never trust the agent's red/green claim alone — the orchestrator's independent re-run IS the gate.

**Step 5: Demote-don't-delete logic for findings whose tests cannot reproduce.**

For each eligible finding, correlate to the agent's report by matching its `Targeted source` field against the finding's `path:lines` (proximity match — same file, overlapping line range). Then act per this table:

| Agent's report block | Action on the matching review finding |
|---|---|
| `### Authored Failing Tests` (F→P-confirmed by orchestrator re-run in Step 4) | Tag finding `[CONFIRMED-BY-TEST]` in its severity section. Annotate per-finding line with `confirmed-by: <test path>`. Keep severity unchanged. |
| `### Discarded Hypotheses` with reason "passed on current code" | DEMOTE: remove from current severity section; add to `## Filtered` with reason `test-gate-cannot-reproduce`. Tag `[CHALLENGED-BY-TEST]`. Preserve original severity in the line so the user can re-elevate if they disagree with the test. |
| `### Inconclusive` (flaky / framework limitation) | Keep finding unchanged in its severity section. No tag. (The signal is "agent could not decide", not "finding is wrong".) |
| No matching hypothesis at all | Keep finding unchanged. Agent did not attempt this finding (likely deprioritized below the hard cap of 10 authored tests). Orchestrator does NOT infer either way. |

The demote-don't-delete rule is non-negotiable: a green test can mean (a) the bug is not real, (b) the test is wrong, or (c) the test fails for the wrong reason ([PoC-Gym, arXiv 2602.04165](https://arxiv.org/html/2602.04165v1)). Preserving the finding in `## Filtered` lets the user re-elevate it if they disagree with the test.

**Step 6: Fail-open.**

If the adversarial-tester-agent fails to complete, returns malformed output, its report cannot be parsed, or the orchestrator's Step 4 re-run command itself errors (test framework not installed, exec error), do NOT revoke any findings and do NOT add `[CONFIRMED-BY-TEST]` tags. Surface "test-gate fail-open — bug confirmation skipped for this run" under `## Caveats` in the final report. Mirrors Phase 4b validator and relevance-filter fail-open semantics.

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
- Decision Type: one of [FIX-NOW] mechanical/low-risk, [TESTABLE] edge case worth a test, [PRODUCT-DECISION] multiple valid paths needing human triage, [INTENT-CHECK] verify against plan before treating as bug (auto-applied by Phase 4 Step 0). Defs+examples: see plan-context-reference.md.
- Finding: [specific description]
- Evidence: [code snippet or pattern]
- Recommendation: [action to take]
- Confidence: 95%

## High Priority Issues
[Same format]

## Medium Priority Issues
[Same format]

## Intent Checks (verify against plan before treating as bugs)
[Findings auto-demoted from `[DIVERGES-FROM-PLAN-*]` or `[ALIGNS-WITH-PLAN-*]` by Phase 4 Step 0. Each entry cites the plan decision (e.g., D-09) and the apparent divergence. Human triage decides whether the divergence is intentional (close), a doc gap (update plan), or a real bug (re-elevate to MEDIUM/HIGH). Omit section when empty.]

## Filtered by Relevance (not applicable to this repo)
[List of findings that were filtered with 1-line reasons — e.g., "over-engineering for this repo's complexity level", "contradicts established repo pattern"]

## Caveats (TRUNCATED dimensions from Phase 4 Step −1; subagent failures, e.g., relevance-filter fail-open or per-finding validator fail-open — omit section when empty)

## Review Confidence
- Bugs analysis: 92%
- Security analysis: 88%
- Architecture analysis: 85%
- Tests analysis: 90%
- Optimizations analysis: 88%
- Guidelines analysis: 94%
- Conventions analysis: 87%
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

All 7–8 reviewers (+1 design when UI files present) are spawned as independent `reviewer-agent` instances via the Agent tool:
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

**File:** `<PRIMARY_ROOT>/.geniro/review-findings-state.md` — single file per branch, overwritten on each run. Resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A so the file (and its `[POSTED-TO-PR]` idempotency markers) survives worktree teardown.

**Schema (markdown with named sections):**

````
# Review Findings — <ISO 8601 timestamp>

## Summary
- branch: <current branch>
- mode: <standard | tdd>                       # set by Phase 1 mode-flag detection or Mode AUQ; consumed by Phase 4c default-highlighting and Phase 6 PR-comment filter. Default `standard` when neither flag nor AUQ resolved.
- input: <files | diff range | PR ref>
- pr-ref: <#N | full PR URL | none>           # populated only when input was a PR ref; consumed by Phase 6 PR-comment gate as the gating predicate (none = gate skipped). When reading state files written by older versions of this skill that predate the field, treat the missing key as `pr-ref: none` and skip the PR-comment gate.
- pr-url: <https://github.com/.../pull/N | none>  # canonical URL from `gh pr view --json url`; used in user-facing messages and as the audit-trail link for `posted-to-pr:` markers
- pr-head-sha: <40-char SHA | none>           # `headRefOid` snapshotted at Phase 1; pinned as `commit_id` on the GitHub reviews API call to prevent line-anchor drift if the PR updates mid-review
- files analyzed: N
- counts: CRITICAL=X, HIGH=Y, MEDIUM=Z
- build: pass | fail | not-run
- suggested next stage: /geniro:implement | /geniro:follow-up | none

# Per-finding line schema (used by CRITICAL, HIGH, MEDIUM, and Intent sections — `decision:` applies to ALL severities, not just CRITICAL):
#   - [NEW|PRE-EXISTING] [optional: CONFIRMED-BY-TEST|CHALLENGED-BY-TEST|POSTED-TO-PR] path:lines — <description> — decision: <FIX-NOW|TESTABLE|PRODUCT-DECISION|INTENT-CHECK> — recommendation: <action> — confidence: NN%
#   - When `decision: PRODUCT-DECISION`, the line is followed by indented sub-fields: `options:` sub-list (one bullet per option, copied verbatim from the reviewer-agent's `Options:` field — see `agents/reviewer-agent.md` §Output Format) AND the body fields `evidence:`, `why-matters:`, `suggested-fix:` (copied verbatim from the reviewer-agent's `Evidence:` / `Why this matters:` / `Suggested fix:` fields). Phase 6 Step 0 and downstream `/follow-up` Phase 5 Step 2 / `/implement` Phase 6 Fix-Loop pre-step consumers read these sub-fields to populate `AskUserQuestion` per the canonical shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Single-finding gate. The user's chosen option text replaces the line's `recommendation:` field; the `options:` sub-list and the body sub-fields are preserved as audit trail and as the cross-skill handoff for `preview` rendering.
#   - [CONFIRMED-BY-TEST] is appended by Phase 4c when the orchestrator's independent re-run confirms the agent-authored test fails today; line also gains `confirmed-by: <test path>`.
#   - [CHALLENGED-BY-TEST] appears only in the `## Filtered` section (finding moved there by Phase 4c when the test passed on current code); the original severity is preserved in-line so the user can re-elevate.
#   - [POSTED-TO-PR] is appended by Phase 6's PR-comment gate after a finding has been successfully posted to the PR; line also gains `posted-to-pr: <inline-comment-URL>`. The orchestrator MUST skip findings already carrying this tag on subsequent runs of `/geniro:review` against the same PR — this is the idempotency contract that prevents duplicate comments on re-runs (no API hash-diff needed; the marker IS the dedupe key).

## CRITICAL
- [NEW] path/to/file.ext:42-48 — <description> — decision: FIX-NOW — recommendation: <action> — confidence: 95%
- ...

## HIGH
- [NEW] path/to/file.ext:80-92 — <description> — decision: PRODUCT-DECISION — recommendation: <action> — confidence: 88%
  options:
    - <Label A> — <one-line trade-off>
    - <Label B> — <one-line trade-off>
  evidence: |
    <2-5 line code snippet copied from the reviewer-agent's Evidence: field>
  why-matters: <one-sentence impact, copied from the reviewer-agent's "Why this matters:" field>
  suggested-fix: |
    <synthesis text copied from the reviewer-agent's "Suggested fix:" field>
- ...

## MEDIUM
- [NEW] path/to/file.ext:120-125 — <description> — decision: TESTABLE — recommendation: <action> — confidence: 82%
- ...

## Intent
- [NEW] path/to/file.ext:200-210 — <description> — decision: INTENT-CHECK — plan-citation: D-09 "<one-line decision quote>" — recommendation: <verify or close> — confidence: 90%
- ...

## Filtered
- path:line — <description> — reason: relevance | validation | confidence-below-threshold | test-gate-cannot-reproduce
- [CHALLENGED-BY-TEST] path:line — <description> — reason: test-gate-cannot-reproduce — original-severity: <CRITICAL|HIGH|MEDIUM> — challenged-by: <test path>

## Authored Tests (Phase 4c — AI-authored, F→P-verified, ready for triage by user)
- path/to/foo.edge.test.ts — confirms: <finding path:line> — confidence: NN%
- path/to/bar.async.test.ts — confirms: <finding path:line> — confidence: NN%
````

Write the file even when zero actionable findings remain (empty severity sections, `suggested next stage: none`) — the artifact's existence signals "review ran, nothing to fix" to downstream skills and resumed sessions.

## Phase 5b: Learn & Improve

Extract knowledge and suggest project-scope improvements after delivering findings. **Skip when `/geniro:review` is called as a sub-phase within `/geniro:implement`** (parent pipeline handles learnings in Phase 7).

See `${CLAUDE_SKILL_DIR}/learnings-reference.md` for the full procedure (extract recurring anti-patterns, false positives, and user corrections; route project-scope improvements to CLAUDE.md / knowledge / project rules / custom instructions; offer via `AskUserQuestion`).

## Phase 6: Suggest Remediation

After Phase 5b, surface the next skill to fix what was found. **Skip when `/geniro:review` is called as a sub-phase within `/geniro:implement`** (parent owns its own fix loop), or when there are no actionable findings (CRITICAL + HIGH + MEDIUM all zero after Phase 4b).

**Step 0: Open-decision gate (per-finding, Always-WAIT).** Before recommending which skill to run, surface every `decision: PRODUCT-DECISION` finding kept by Phase 4 judge to the user — they pick the resolution path; you NEVER pick on their behalf. The orchestrator must not auto-resolve multi-path findings even when the reviewer's `recommendation:` field appears obvious.

For each kept finding with `decision: PRODUCT-DECISION` (read from `<PRIMARY_ROOT>/.geniro/review-findings-state.md`):

1. Read the finding's `Options:` sub-list AND the body sub-fields (`evidence:`, `why-matters:`, `suggested-fix:`) from the per-finding line in the state file (see Phase 5 per-finding line schema above for the persisted shape).
2. Fire `AskUserQuestion` per the canonical shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Single-finding gate. Set `header: "Open decision"`. Render the `question` text with the finding's severity / `path:lines` / short-title / decision-type / `why-matters` line per the spec's Source-field map; render each option's `label`+`description` from the finding's `options:` sub-list bullets; render each option's `preview` with the finding body (Evidence / Suggested-fix / Confidence / Origin). Do NOT collapse this rendering to label + 1-line description — the body in `preview` is what gives the user enough context to actually pick a resolution path.
3. Update the finding line in `<PRIMARY_ROOT>/.geniro/review-findings-state.md`: replace the `recommendation:` field with the user's chosen option text. Preserve all other fields (including `options:`, `evidence:`, `why-matters:`, `suggested-fix:`). The state file is the handoff to the next skill, so the chosen path AND the body travel with the finding.

When more than 4 PRODUCT-DECISION findings exist, OR a single finding's `Options:` carries `(more-options-exist: chain-follow-up)`, chain `AskUserQuestion` calls per the cap-extension pattern documented in the "Failing tests" `AskUserQuestion` block later in Phase 6 — chain questions; never split or drop options. The canonical body schema applies identically to every chained call.

This gate is **Always-WAIT** in every mode (see `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §Auto Mode Behavior, `[PRODUCT-DECISION] finding encountered` row). If `AskUserQuestion` returns an empty answer, fall back to plain text and re-ask — never default to the reviewer's synthesis.

Skip this Step 0 entirely when zero PRODUCT-DECISION findings remain after Phase 4 judge.

**Severity-driven recommendation (must match the Phase 5 state file):**
- Any CRITICAL OR ≥2 HIGH findings → recommend `/geniro:implement` (full multi-agent pipeline, architecture-aware fixes)
- 0 CRITICAL AND ≤1 HIGH findings → recommend `/geniro:follow-up` (fast lane for trivial/small scope)

Use `AskUserQuestion` (do NOT print options as plain text) with header "Remediate". Mark the severity-recommended option with "(Recommended)" in its label. Options:
- **Run /geniro:implement** — full multi-agent pipeline; pre-load findings from `<PRIMARY_ROOT>/.geniro/review-findings-state.md`
- **Run /geniro:follow-up** — fast lane; pre-load findings from the same file
- **Skip — I'll handle it manually** — no further action; state file remains for reference

Do NOT auto-invoke the next skill — surface the suggestion only. The user runs the slash command themselves; the state file path is the handoff channel.

**When `## Authored Tests` is non-empty, fire a separate `AskUserQuestion` with header "Failing tests"** — chained after the Remediate question when Remediate fires; standalone immediately after the Phase 6 entry condition otherwise (cap-extension pattern: chain questions, do not split or drop existing options). **Skip when `/geniro:review` is called as a sub-phase within `/geniro:implement`** (parent pipeline owns its own commit decision) OR when the `## Authored Tests` section is empty.

- **Question:** "How should the N failing tests authored by Phase 4c be handled? They are AI-authored — review before merging."
- **Header:** "Failing tests"
- **Options:**
  - "Commit failing tests on current branch" — orchestrator stages only the test files listed in `## Authored Tests` (never `git add -A` / `git add .`), composes a commit message following the repo's commit style (check `git log -5 --oneline` first), and commits via HEREDOC. Keeps the failing tests on the same branch where review ran so the chosen remediation skill picks them up immediately. **Recommended in Standard mode and in TDD mode without a PR ref.**
  - "Commit + push to current branch's upstream" — same as commit-only, then `git push`. If the branch has no upstream, surface the exact `git push -u origin <branch>` command and ask the user to confirm before running it. **Recommended in TDD mode when a PR ref is present** (so the failing tests appear on the PR alongside the inline comments — the gate stays mandatory; mode only flips which option is highlighted).
  - "Leave uncommitted" — tests stay on disk for the user to review and stage manually.

Never use `--no-verify`, `--amend`, or destructive flags. If a pre-commit hook fails, surface the failure and stop — do not retry or bypass.

**Phase 6 final gate — PR-comment posting (Always-WAIT, two-step, PR-ref-only).** When the Phase 5 state file's `## Summary` carries a non-`none` `pr-ref:` value (i.e., the original `$ARGUMENTS` was a PR ref — `#N`, bare digits, or full PR URL — captured at Phase 1) AND at least one finding remains unposted (i.e., kept by Phase 4 judge / Phase 4b validator / Phase 4c test gate AND not already tagged `[POSTED-TO-PR]` from a prior run), surface a final gate offering to post findings as PR comments. **Skip when `/geniro:review` is called as a sub-phase within `/geniro:implement`** (parent pipeline owns its own PR-handling decisions), when `pr-ref: none`, OR when zero unposted findings remain.

Chained position: fires AFTER the "Failing tests" question when authored tests exist; otherwise standalone after "Remediate". The chain stays within the cap-extension convention (each individual prompt has 2 options — well under the 4-option cap).

**Step 1 — Consent gate (Q1):** Use `AskUserQuestion` (do NOT print options as plain text) with header "PR comments":

- **Question:** "Post the N kept findings as inline comments on PR `<pr-ref>`? Posting is an external write to a public surface — the skill never posts without explicit approval."
- **Options:**
  - "Yes — post findings as PR comments"
  - "Skip — I'll handle it manually (Recommended)"

The "Skip" default is recommended because PR comments are public and irreversible. If user picks **Skip**, write nothing, mark no findings posted, proceed to Phase 6 cleanup.

**Step 2 — Granularity gate (Q2, fires only on Yes):** Chain a second `AskUserQuestion` with header "Post mode":

- **Question:** "Send all kept findings in a single batched review, or pick which ones to post?"
- **Options:**
  - "Send all (Recommended)" — single batched review event reduces notification noise (one PR-author notification instead of N) and dodges secondary rate limits
  - "Pick one-by-one" — chained `multiSelect` prompts; you choose which findings to include

**Step 3 — Pick loop (fires only on "Pick one-by-one"):** Chain `AskUserQuestion` calls, each with `multiSelect: true`, presenting eligible findings as options. Each option's `label`: `<severity-badge> path:line — <short title>`. Each option's `description`: the finding's `recommendation:` field plus `confidence: NN%`. Each option's `preview`: the finding's full body (Evidence / Suggested-fix / Confidence / Origin) per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Multi-select pick loop — pull the body fields from in-memory reviewer-agent output (Phase 6 PR-comment runs in the same invocation that produced findings). AskUserQuestion has a 4-option cap; when more than 4 eligible findings exist, batch them across multiple chained questions (≤4 per call) — never drop or merge options to fit a single question (cap-extension pattern, identical to Phase 4c Step 2). Aggregate selections across all calls into the post set. If the user deselects all (or returns empty answers across the whole chain), treat as Skip and proceed without posting.

**Step 3.5 — TDD-mode post-set filter.** When the state-file `mode:` is `tdd`, filter the post set so that findings whose `decision:` is `TESTABLE` and which lack a `[CONFIRMED-BY-TEST]` tag are excluded (they remain visible in the local report's severity sections; they are not posted to the PR). Findings retained for posting in TDD mode: (a) any finding tagged `[CONFIRMED-BY-TEST]`, regardless of decision-type; (b) any finding whose `decision:` is `PRODUCT-DECISION` or `INTENT-CHECK` (no executable behavior to gate on); (c) findings whose `decision:` is `FIX-NOW` AND which match the "Runtime-behavior classification" rule's NON-runtime branch (no runtime behavior to test against — see Phase 4c Step 1's classification rule, the single source of truth). When the filter empties the post set, fall back to Skip semantics — do not post anything; surface "TDD mode: no F→P-confirmed findings — nothing posted to PR" once in chat. In Standard mode (`mode: standard`), this step is a no-op — every kept finding stays in the post set as today.

**Step 4 — Post via the GitHub reviews API.** Parse `<owner>/<repo>/<number>` from the state-file Summary's `pr-url` (canonical form `https://github.com/<owner>/<repo>/pull/<N>` — extract with e.g. `awk -F/ '{print $4"/"$5}'` for `owner/repo` and `awk -F/ '{print $7}'` for `<number>`; the `pr-ref` field is preserved verbatim from user input and is NOT parsed in this step). Pass the snapshotted `pr-head-sha` as `commit_id`. ONE `gh api` call posts the entire review (Send-all mode = N comments in one review event; Pick mode = the user-selected subset in one review event). Use `event: COMMENT` only — never `APPROVE` or `REQUEST_CHANGES` (the skill is a reviewer, not an authorizer).

The full review body is composed as JSON via `jq` and piped to `gh api --input -` (the `gh` flags `-f` / `--raw-field` send STATIC SCALAR string parameters and CANNOT carry a nested array — a JSON body with `comments[]` MUST be passed via `--input`):

```bash
jq -nc \
  --arg sha "<pr-head-sha>" \
  --arg body "Geniro review — <N> findings (CRITICAL: X, HIGH: Y, MEDIUM: Z)" \
  --argjson comments '<comments-json>' \
  '{commit_id: $sha, event: "COMMENT", body: $body, comments: $comments}' \
  | gh api --method POST "/repos/<owner>/<repo>/pulls/<number>/reviews" --input -
```

The `<comments-json>` array is built from the post set. Each element:

```json
{
  "path": "<file path relative to repo root>",
  "line": <last line in finding's path:lines range — comment anchor>,
  "side": "RIGHT",
  "start_line": <first line in finding's path:lines range, ONLY when range spans multiple lines; OMIT for single-line findings>,
  "start_side": "RIGHT",
  "body": "**<SEVERITY>** [decision-type] — <description>\n\n**Recommendation:** <recommendation>\n\n*Confidence: NN%*"
}
```

Range anchoring: GitHub's reviews API requires `line` (end of range) and accepts optional `start_line` + `start_side` to highlight a multi-line span. For a single-line finding (`path:42`), include only `line: 42`. For a range (`path:42-48`), include `line: 48`, `start_line: 42`, `start_side: "RIGHT"` so the inline comment highlights the full range in the GitHub UI. Build the comment object accordingly per finding — do NOT emit `start_line` for single-line findings (GitHub rejects `start_line == line`).

Pull the `body` fields (description, recommendation, confidence, decision-type, severity) from the in-memory finding records — Phase 6 PR-comment posting runs in the same invocation that produced findings, so the full reviewer-agent output (including Evidence and Why-this-matters) is available without needing the state file. **For findings tagged `[CONFIRMED-BY-TEST]`, append `\n\n**Failing test:** \`<test-path>\`` to the rendered `body` string, pulling `<test-path>` from the finding's `confirmed-by:` field in the state file. This applies in both Standard and TDD modes — wherever a confirming test exists, surfacing the test path is signal for the PR reviewer.** PRODUCT-DECISION rows additionally persist `evidence:`, `why-matters:`, `suggested-fix:` to the state file for cross-skill consumers (`/follow-up`, `/implement`) per the Phase 5 per-finding line schema; non-PRODUCT-DECISION rows do not persist body fields because no cross-skill AUQ surface needs them. Severity-badge rendering: `**CRITICAL**` (red emphasis) / `**HIGH**` (bold) / `**MEDIUM**` (italic-bold). Decision-type tag in brackets after severity: `[FIX-NOW]` / `[TESTABLE]` / `[PRODUCT-DECISION]` / `[INTENT-CHECK]`.

**Step 5 — Persist `[POSTED-TO-PR]` markers.** Parse the API response (a `comments` array on the returned review object, each element carrying an `html_url`); for each posted comment, append `[POSTED-TO-PR]` to the corresponding finding's tag list and add `posted-to-pr: <html_url>` to the line in `<PRIMARY_ROOT>/.geniro/review-findings-state.md`. This is the idempotency contract — the next `/geniro:review` run against the same PR reads these markers and excludes already-posted findings from Step 1's "N unposted findings" count, preventing duplicates without a server-side hash check.

**Step 6 — Posting-failure semantics.** If the `gh api` call fails (non-zero exit, HTTP error, missing scopes, secondary rate limit with 403/429), surface the error verbatim to the user and stop — do not retry, do not fall back to a different endpoint, do not bypass with `--no-verify`-style flags, do not silently downgrade to top-level `gh pr comment` (which loses inline anchoring). No partial state is written: leave the per-finding `[POSTED-TO-PR]` tags off entirely so the user can re-run cleanly after fixing the underlying issue. Mirrors existing `gh` failure handling at SKILL.md Phase 1 (gh-unavailable surface-and-stop).

**Empty-answer handling (universal).** If `AskUserQuestion` returns an empty answer at any of the three prompts, fall back to plain text and re-ask once — never promote empty to a default Yes. After one re-ask, if still empty, treat as Skip and proceed without posting.

## Definition of Done

Code review is complete when:
- [ ] Phase 1 context collected (files read, changes understood, PLAN CONTEXT resolved from PR body / `--plan` / project files / none)
- [ ] Phase 2 reviewers spawned and executed in parallel, each prompt carrying PLAN CONTEXT + alignment-tag instruction
- [ ] All applicable reviewer dimensions completed (6 in standard mode, +1 design when UI files present; up to 35 parallel agents across batches in batched mode)
- [ ] Phase 3 relevance filter applied (findings checked against repo conventions, complexity, and PLAN CONTEXT)
- [ ] Phase 4 judge validation complete (findings verified) — Step −1 truncation check ran (truncated dimensions in `## Caveats`); Step 0 intent reconciliation ran (plan-authorized divergences demoted to `[INTENT-CHECK]`)
- [ ] Phase 4b per-finding validation run for Critical/High findings (if applicable)
- [ ] Phase 4c test-confirmation gate evaluated (skipped when no eligible findings, called as sub-phase of /geniro:implement, or user declines)
- [ ] Phase 4c fail-open caveat surfaced under `## Caveats` if the adversarial-tester-agent failed or its report could not be parsed
- [ ] TDD mode only: Phase 1 mode-flag detection ran (`--tdd` / `--standard` / Mode AUQ) and `mode:` persisted to the Phase 5 state file
- [ ] TDD mode only: Phase 4c Step 2 AUQ rendered "Author tests for all eligible findings" with the `(Recommended)` suffix — gate itself fired exactly as in Standard mode (the Phase 4c invariant "this skill MUST NEVER spawn the agent without explicit user approval" was honored), N/A when no eligible findings exist or Phase 4c was skipped per Step 1
- [ ] TDD mode only: Phase 6 Step 3.5 post-set filter applied — only `[CONFIRMED-BY-TEST]` findings + `[INTENT-CHECK]` + `[PRODUCT-DECISION]` + `[FIX-NOW]`-typo-class were eligible for posting
- [ ] Confidence scoring applied (>=80 threshold)
- [ ] Issues classified by severity (Critical, High, Medium) and Decision Type ([FIX-NOW] | [TESTABLE] | [PRODUCT-DECISION] | [INTENT-CHECK])
- [ ] Findings tagged as [NEW] or [PRE-EXISTING] based on diff context
- [ ] Review summary generated with all findings
- [ ] Output delivered with actionable recommendations
- [ ] Learnings extracted (standalone invocations only)
- [ ] Improvement suggestions presented (standalone invocations only)
- [ ] Phase 5 state artifact written to `<PRIMARY_ROOT>/.geniro/review-findings-state.md`
- [ ] Phase 6 open-decision gate fired for every `[PRODUCT-DECISION]` finding (always-WAIT) — user chose resolution path before remediation routing; standalone invocations only
- [ ] Phase 6 remediation suggestion presented via `AskUserQuestion` (standalone invocations only)
- [ ] Phase 6 authored-tests handoff offered when `## Authored Tests` is non-empty (standalone invocations only)
- [ ] Phase 6 PR-comment gate fired (always-WAIT, two-step) when `pr-ref:` non-`none` AND at least one finding remains unposted; standalone invocations only — skipped silently when `pr-ref: none`, when zero unposted findings remain, or when `/geniro:review` runs as sub-phase of `/geniro:implement`
- [ ] Posted findings tagged `[POSTED-TO-PR]` with `posted-to-pr: <comment-url>` in `<PRIMARY_ROOT>/.geniro/review-findings-state.md` so re-runs are idempotent

---

## Compliance — Do Not Skip Phases

| Your reasoning | Why it's wrong |
|---|---|
| "I can skip context gathering" | Without understanding what changed and why, you'll produce false positives and miss real issues. |
| "I'll review all aspects myself instead of spawning the reviewer agents" | Serial review misses perspective. All 7–8 specialized reviewers MUST execute in parallel. |
| "The reviewers found good stuff, skip relevance filtering" | Reviewers apply general best practices — without checking against THIS repo's patterns, you'll report over-engineering suggestions and convention-contradicting findings that waste engineer time. |
| "The reviewers found good stuff, skip judge validation" | Unfiltered findings create report fatigue. Only >=80 confidence findings provide signal. |
| "I can tell this is a real issue without reading the source" | Always validate findings in context — check the actual file and lines before reporting. |
| "While I'm here, let me suggest improvements beyond the diff" | Review against the scope of changes, not "what else could be improved." Stay focused. |
| "The agent said it thoroughly reviewed everything" | Agents self-report optimistically. Verify by reading their actual outputs yourself. |
| "I can merge confidently without addressing CRITICAL findings" | CRITICAL issues MUST be fixed before shipping. They are non-negotiable. |
| "I can skip writing the state file — the user can copy from chat" | The state file is the only handoff channel that survives compaction or session end. Findings in chat alone cannot reach the next skill. |
| "Findings are obvious — skip the AskUserQuestion and just tell them to run /implement" | Severity-driven recommendation is a structured choice (the user may want fast-lane follow-up for small scope, or to handle manually). Always offer the question; never assume. |
| "No PR body / no plan file, so PLAN CONTEXT collection is pointless — skip it" | The Phase 1 step is cheap and renders `none` when nothing resolves. Skipping it means future PRs that do have a plan get silently ignored, and reviewers can't tag `[ALIGNS-WITH-PLAN]` even when a `--plan` flag was passed. Always run the resolution. |
| "A reviewer's output is missing the `## Dimension Summary` footer but the findings look complete — accept it" | Truncation often clips the last (and most synthesized) finding. Phase 4 Step −1 exists precisely to flag this; mark the dimension TRUNCATED in `## Caveats` and recommend re-running with higher maxTurns. Do not silently accept partial output. |
| "Findings are obvious — skip the Phase 4c test gate" | Phase 4c is the false-positive reduction stage. Independent test-execution catches findings that read as bugs but cannot be reproduced — a different signal than Phase 4b's read-only validation. Always offer the gate when eligible findings exist; the user can decline, but the offer is not yours to skip. |
| "I'll spawn the adversarial-tester-agent and ask the user to confirm later" | Inline gates rationalize away into "this counts as approval". Skill MUST `AskUserQuestion` BEFORE spawning. The two-step gate (skill asks → on YES, spawn) is the only rationalization-resistant variant. Spawning first and asking second is exactly the failure mode the user-approval rule exists to prevent. |
| "The test passes today, so the finding is fake — delete it" | Demote, do not delete. A green test can mean (a) the bug is not real, (b) the test is wrong, or (c) the test fails for the wrong reason ([PoC-Gym, arXiv 2602.04165](https://arxiv.org/html/2602.04165v1) documents this failure mode). Move the finding to `## Filtered` with `[CHALLENGED-BY-TEST]` and original severity preserved so the user can re-elevate it if they disagree with the test. |
| "The reviewer's `recommendation:` field is obvious — I'll just route to the next skill without asking the user about each `[PRODUCT-DECISION]` finding" | `[PRODUCT-DECISION]` findings have multiple valid resolution paths by definition (see `agents/reviewer-agent.md` §Decision Type Guidance). The `recommendation:` field on a multi-path finding is a synthesis, not the chosen path. The orchestrator NEVER picks on the user's behalf — Phase 6 Step 0 (always-WAIT) presents enumerated `Options:` to the user via `AskUserQuestion` BEFORE any remediation routing. Skipping the per-finding gate ships a product decision the user did not authorize. |
| "The findings look obviously postable — I'll just batch-post them to the PR and tell the user after" | Posting to a PR is an external write to a public surface — the same audience-expanding action class as `gh pr create` and `git push`. Inline gates rationalize away into "this counts as approval". The skill MUST `AskUserQuestion` BEFORE the `gh api` call. The two-step gate (skill asks Yes/Skip → on YES, posts) is the only rationalization-resistant variant; posting first and asking second is exactly the failure mode the user-approval rule exists to prevent. |
| "User picked Pick-one-by-one and findings are obviously postable — I'll just include them all and skip the per-finding multiSelect" | The whole point of Pick mode is that the user wants per-finding control; overriding it ships a posting decision they did not authorize. Always render the chained `multiSelect: true` AskUserQuestion calls (≤4 options each, cap-extension chained when more), aggregate the selections, post only the union. If the user deselects all, treat as Skip and post nothing. |
| "The user already ran `/geniro:review` against this PR yesterday and approved posting — I'll skip the gate this time" | Permissions don't carry across runs. The state file's `[POSTED-TO-PR]` markers are an idempotency contract (skip already-posted findings on re-run), NOT a blanket re-authorization for new findings. Every run that has at least one unposted finding fires the consent gate from scratch. |
| "TDD mode is on, the user clearly wants tests authored — I'll skip the Phase 4c AUQ this time" | TDD mode flips the *Recommended* highlight, not the *gate*. The Phase 4c invariant is non-negotiable: this skill MUST `AskUserQuestion` BEFORE spawning `adversarial-tester-agent` in EVERY mode (see Phase 4c Step 2 — "this skill MUST NEVER spawn the agent without explicit user approval — the gate is the load-bearing safety property, and inline gates degrade to 'this counts as approval'"). Mode is a default-selection signal, not consent. The two-step gate (skill asks → on YES, spawn) is the only rationalization-resistant variant — pre-answering "because mode=tdd" rationalizes the gate away exactly as the "I'll spawn the adversarial-tester-agent and ask the user to confirm later" Compliance row above warns. |
