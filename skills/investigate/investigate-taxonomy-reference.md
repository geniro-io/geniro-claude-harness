# Investigate — Detailed Reference

Detail sections extracted from `skills/investigate/SKILL.md` to keep the main skill body lean. The orchestrator reads this file when SKILL.md references one of the sections below by name.

## Contents

1. State machine — full ASCII diagram
2. State file schema — frontmatter + body sections
3. Phase 2 research-agent spawn templates (Codebase / Git / Internet)
4. Phase 3 fresh reviewer-agent spawn template
5. Answer-structure templates per question type (How / Why / What-if / Compare / Risk)
6. Extended examples (Design Rationale, Impact Analysis, Forward-looking integration)

---

## 1. State machine — full ASCII diagram

```
[entry]
└── classify ──┬── investigate ──┬── present ──┬── done
│ │ └── present-summary-only (terminal — "Nothing — just wanted the answer" pick)
│ │
│ └── investigate-escalated ──┬── investigate (user supplies missing data → resume)
│ ├── present (user picks "drop unverified claims" → continue with gaps)
│ └── aborted (terminal)
│
└── classify-escalated ──┬── classify (user resolves glossary mismatch → resume)
├── aborted (terminal)
└── routed (terminal — question intent doesn't match /investigate scope; route to /onboard, /debug, etc.)

present ──┬── (happy: flows to done)
└── present-loop ──┬── investigate (Phase 3 Step 4 follow-up "dive deeper" → re-enter Phase 2 with narrower scope; max 2 rounds)
└── done (user picks "save findings" → save-routing AUQ executes → done)
```

Terminal states: `done`, `present-summary-only`, `aborted`, `routed`. The SessionStart recovery treats all as "task complete — no resume". Non-terminal states roll back to phase-entry on compaction-resume and re-run idempotently. Escalation states (`classify-escalated`, `investigate-escalated`) surface to the user as "task was paused — last AUQ options" so the user re-picks without losing context.

---

## 2. State file schema

Path: `<PRIMARY_ROOT>/.geniro/state/investigate/<slug>/state.md` (resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A; compute `<slug>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Slug rules — derived from question hash + first significant words).

Write via `atomic_state_write` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"
atomic_state_write ".geniro/state/investigate/<slug>/state.md" <<EOF
---
tier: T1
producer: investigate
schema-version: 1
branch: <git-branch>
timestamp: <ISO-8601 UTC>
phase: <classify|investigate|present|*-escalated|done|present-summary-only|aborted|routed>
status: <in-progress|done|failed>
non-resumable-actions: []
approvals: []
geniro_kind: investigate-state
geniro_schema_version: m9-v1
task_slug: <slug>
worktree: <abs-path>
question_type: <one of 9 types from Phase 1 Step 1 classification>
agents_spawned: []
dive_deeper_rounds: 0
---

## Scope
<target area + skip criteria applied>

## Classification
<question type + agent set chosen>

## JIT Cadence
<§Step 2.6 5-step audit log>

## Agent Findings
<raw output from research agents>

## Verified Claims
<Phase 2 Step 2 re-verified evidence>

## Draft Answer
<pre-review version — preserved for compaction-resume>

## Reviewer Findings
<fresh-reviewer issue list>

## Final Answer
<post-review version>

## Tool log
<selective logging — subagent spawns, L2 emits, escalations>

## Errors
<WebFetch/WebSearch failures, permission errors>

## Open Questions
<missing-data gates, glossary mismatches>

## Termination reason
<only on terminal aborted/routed states>

## Persisted approvals
<render of frontmatter approvals[] (category: glossary_resolve)>
EOF
```

`approvals[]` populated when Phase 1 Step 2.5 fires (category `glossary_resolve`).

Validate before resume via `validate_state_file` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md`.

---

## 3. Phase 2 research-agent spawn templates

Each spawn pre-populates the 6 required fields from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` (task scope, acceptance criteria, file paths with content, prohibited tools, output schema, model tier) and obeys the runtime-degradation rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`. Replace every `{{placeholder}}` with actual content before spawning; pre-inline file contents under `## Pre-Inlined Files` rather than expecting the agent to re-Glob.

### Agent A: Codebase Analyst (when not skipped by Phase 1 Step 2)

```
Agent(description="Investigate: codebase analysis", disallowedTools=["Edit", "Write", "NotebookEdit"], prompt="""
## Task: Codebase Investigation (READ-ONLY)
Produce a structured findings report answering the question below by analyzing pre-inlined codebase content. This is a read-only research task — do NOT Edit, Write, or NotebookEdit (also restated here per context-isolation-checklist.md (4) belt-and-suspenders).

**Question:** {{user's question}}
**Target area:** {{files/modules/patterns to focus on}}
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]

### Acceptance criteria (self-check before reporting completion)
- Every Finding cites at least one file:line + verified snippet (Evidence Standard kind 1) or captured grep/command output (kind 2). Reasoning-only findings are rejected.
- "Files examined" lists every file you Read with line counts.
- "Gaps" section is present (may be empty) — never silently drop a sub-question.

### Pre-Inlined Files
{{paste verbatim contents of orchestrator-identified relevant files with absolute paths as headers; agents do NOT re-Glob}}

### Investigation strategy
1. Read the pre-inlined files fully — do not skim
2. Use Grep / additional Read calls only when pre-inlined files reference symbols not yet in scope
3. Trace execution paths, data flow, or dependency chains as needed
4. Identify patterns, conventions, and edge cases
5. Note any inconsistencies, dead code, or surprising behavior

### Output schema (literal shape)
**Files examined:** [list with line counts]

**Findings:**
For each relevant discovery, one block matching:
- What: [specific finding with file:line references]
- Evidence: [code snippet or grep output — verbatim]
- Relevance: [how this answers the question]

**Gaps:** [what you couldn't determine from code alone — bulleted]

Do NOT speculate. If the code doesn't answer a sub-question, list it as a gap.
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""")
```

### Agent B: Git Historian (for How current/forward-looking, Why, Risk, What-if)

```
Agent(description="Investigate: git history", disallowedTools=["Edit", "Write", "NotebookEdit"], prompt="""
## Task: Git History Investigation (READ-ONLY)
Produce a structured timeline + findings report on the git history relevant to the question. This is a read-only research task — do NOT Edit, Write, or NotebookEdit, and do NOT run mutating git operations (no `git add`, `git commit`, `git push`, `git checkout`, `git reset`). Read-only git verbs only: `log`, `blame`, `show`, `diff`.

**Question:** {{user's question}}
**Target area:** {{files/modules to focus on}}
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]

### Acceptance criteria (self-check before reporting completion)
- Every Finding cites a commit hash + commit-message excerpt or diff snippet (Evidence Standard kind 2 — captured command output). No paraphrased "the commit said".
- Timeline is chronological with explicit dates from `git log --format`.
- "Patterns" section is present (may be empty if no trend is supported by ≥3 commits).

### Pre-Inlined Files
{{paste any relevant file contents the orchestrator already read; the agent does NOT re-Read these to find file:lines}}

### Investigation strategy
1. `git log --oneline -30 -- {{target files}}` — recent changes
2. `git log --all --oneline --grep="{{relevant keywords}}"` — commits mentioning the topic
3. `git blame {{key files}}` — who wrote critical sections and when
4. `git log --diff-filter=A -- {{target files}}` — when files were first added
5. For "why" questions: read commit messages in detail for rationale

### Output schema (literal shape)
**Timeline:** [key events in chronological order, each with date + commit hash]

**Findings:**
For each relevant discovery, one block matching:
- What: [commit hash, date, author, change summary]
- Evidence: [commit message excerpt or diff summary — verbatim]
- Relevance: [how this answers the question]

**Patterns:** [trends in how this area evolves — refactors, bug fixes, feature additions; bulleted]

Do NOT speculate about intent beyond what commit messages state.
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""")
```

### Agent C: Internet Researcher (for How forward-looking, Why, What-if, Compare, Risk)

```
Agent(description="Investigate: internet research", disallowedTools=["Edit", "Write", "NotebookEdit"], prompt="""
## Task: Internet Research (READ-ONLY)
Produce a structured external-sources report answering the question. This is a read-only research task — do NOT Edit, Write, or NotebookEdit; do NOT run any local-codebase Bash commands. Use WebSearch + WebFetch only.

**Question:** {{user's question}}
**Target area:** {{technologies, patterns, or concepts involved}}
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]

### Acceptance criteria (self-check before reporting completion)
- Every Finding has a Source URL (Evidence Standard kind: external documented fact). No "I recall…" without a URL.
- Reliability label is one of: official docs / widely-accepted / single source / opinion.
- Consensus + Disagreements sections present (may be empty if N=1 source).

### Pre-Inlined Context
{{paste any pre-existing notes from the orchestrator on what's already known about the external technology, so the agent doesn't re-establish background}}

### Investigation strategy
1. Use WebSearch for each query. Use WebFetch to read full page content when a search result looks highly relevant.
2. Search for official documentation of relevant frameworks/libraries
3. Search for best practices, known issues, or common patterns
4. Search for comparisons or alternatives if the question involves choices
5. Search for security advisories or deprecation notices if relevant

### Output schema (literal shape)
**Sources consulted:** [list with URLs]

**Findings:**
For each relevant discovery, one block matching:
- What: [specific finding]
- Source: [URL or reference]
- Relevance: [how this answers the question]
- Reliability: [official docs / widely-accepted / single source / opinion]

**Consensus:** [what most sources agree on, if applicable]
**Disagreements:** [where sources conflict, if applicable]

Report facts with sources. Flag opinions as opinions.
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""")
```

---

## 4. Phase 3 fresh reviewer-agent spawn template

The verifier inherits the orchestrator's session tier (OMIT `model=`). The spawn satisfies the 6-field contract in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` and obeys the runtime-degradation rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`.

```
Agent(description="Review: verify investigation answer", disallowedTools=["Edit", "Write", "NotebookEdit"], prompt="""
## Task: Verify Investigation Answer (READ-ONLY)
Produce an issue list (or "VERIFIED") for the draft answer below. You were NOT involved in the research — verify with fresh eyes. This is a read-only review — do NOT Edit, Write, or NotebookEdit (also restated here per context-isolation-checklist.md (4) belt-and-suspenders).

**Original question:** {{user's question}}
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]

### Acceptance criteria (self-check before reporting completion)
- Every claimed issue cites a specific Location-in-answer (section name or line) and includes a Severity label.
- Spot-check (item 1 below) covers 2-3 distinct load-bearing claims, not 1 claim re-checked thrice.
- If no issues: emit literal string `VERIFIED — answer is accurate and complete`.

### Pre-Inlined Files
{{paste verbatim contents of every file cited in the draft answer's file:line references; reviewer re-Reads from these — does NOT re-Glob}}

### Draft answer
{{full draft answer from Phase 3}}

### Verification checklist
1. **Spot-check Phase 2 Step 2 re-verify**: Phase 2 Step 2 already had the orchestrator re-verify cited claims. Pick 2-3 load-bearing claims at random; re-Read their cited file:lines and confirm the snippet still matches. If a sample fails, that's a Phase 2 Step 2 gap — flag it as a blocker, not a single-claim correction.
2. **Completeness**: Does the answer fully address the question? Any obvious gaps?
3. **Honesty**: Is every load-bearing claim backed by an artifact (Evidence Standard kinds 1-5)? Are unverified claims listed in "Open questions" rather than smuggled in with caveats?
4. **Clarity**: Would someone unfamiliar with this code understand the answer?
5. **Over-claims**: Does the answer claim certainty where evidence is actually weak?
6. **Missing context**: Is there important context the answer should mention but doesn't?

### Output schema (literal shape)
For each issue found, one block matching:
- Location: [section/line in the answer]
- Issue: [description]
- Severity: [blocker | warning | nit]
- Suggested fix: [text]

If no issues: emit literal string `VERIFIED — answer is accurate and complete`.
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""")
```

---

## 5. Answer-structure templates per question type

**For "How" questions:**

```
## How [X] Works

### Overview
[1-2 sentence summary]

### Execution Flow
1. [Step with file:line reference]
2. [Step with file:line reference]
...

### Key Details
- [Important behavior or edge case]

### Diagram (if helpful)
[ASCII flow diagram of the process]
```

**For "Why" questions:**

```
## Why [X] Was Chosen

### The Decision
[What was decided and when]

### Evidence
- [From git history: commit messages, timing]
- [From code: patterns that reveal intent]
- [From internet: industry context at the time]

### Trade-offs
| Chosen approach | Alternative | Why chosen won |
|---|---|---|
```

**For "What-if" questions:**

```
## Impact of Changing [X]

### Direct Impact
- [Files that would need changes]

### Ripple Effects
- [Downstream dependencies affected]

### Risks
- [What could break]

### Recommendation
[Proceed / proceed with caution / avoid — with evidence]
```

**For "Compare" questions:**

```
## Comparison: [A] vs [B]

| Dimension | A | B |
|---|---|---|
| [relevant dimension] | [evidence] | [evidence] |

### Recommendation
[Which fits this codebase better and why]
```

**For "Risk" questions:**

```
## Risks of [X]

### Risk Assessment

| Risk | Likelihood | Impact | Evidence |
|---|---|---|---|
| [risk] | High/Med/Low | High/Med/Low | [source] |

### Mitigations
- [For each high risk: what to do about it]
```

---

## 6. Extended examples

### Example 2: Design Rationale

```
/geniro:investigate why does the project use Redis for sessions instead of JWT?
```

→ Git agent searches for commits mentioning Redis, JWT, sessions
→ Internet agent researches Redis vs JWT session trade-offs
→ Codebase agent examines current session implementation
→ Synthesize: timeline of decision + trade-offs + current state
→ Present: decision history + evidence for/against

### Example 3: Impact Analysis

```
/geniro:investigate what would break if we upgrade from Express 4 to Express 5?
```

→ Internet agent researches Express 5 breaking changes
→ Codebase agent finds all Express 4 APIs used in the project
→ Git agent checks how recently Express-dependent code was modified
→ Synthesize: breaking changes that affect this codebase specifically
→ Present: risk table + affected files + migration path

### Example 4: Forward-looking integration

```
/geniro:investigate how can we connect the user_events table to our internal analytics dataset?
```

→ Codebase agent finds existing data-export points, schema definitions, and any prior connector code
→ Git agent searches commits mentioning "analytics", "export", "etl" to surface prior approaches
→ Internet agent researches the analytics dataset's documented ingestion API and constraints
→ Phase 2 Step 2 verifies: re-Read the schema files cited; re-run the grep for prior connector code; confirm the analytics-API endpoint exists per docs
→ If a credential / API key / sample dataset is needed and not present, route through Phase 2 Step 3 missing-data gate
→ Synthesize: integration approach grounded in cited files + existing schema + verified external API
→ Self-review verifies all references; present with explicit "open questions" if any sub-question lacked evidence
