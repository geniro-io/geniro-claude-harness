# /improve-template — Phase 1-3 (investigate, cross-reference, present)

Phase body for `.claude/skills/improve-template/SKILL.md`. Read on entry to Phase 1 — Phase 1-fast fixes and create-skill mode never take this branch: Phase 1-fast runs its own steps in the spine's Complexity gate section, and create-skill mode reads `create-skill-mode.md` instead. A run that compacts before reaching Phase 1 also never takes this branch.

## Contents

- Phase 1 — Investigate (parallel research)
- Phase 2 — Cross-reference & filter
- Phase 2b — Redundancy & relevance validation (orchestrator-inline)
- Phase 3 — Present to user (WAIT), incl. Phase 3b challenge resolution

---

## PHASE 1: INVESTIGATE (parallel research)

**Purpose:** Gather evidence from the research sources the matrix selected — up to three independent sources (codebase / ARCHITECTURE.md / internet).

**Input:** User describes an issue, shows a screenshot, or names an area to improve.

### Step 1: Parse the request

Classify the request, then look up its research sources in the matrix above:
- **Bug fix** — something broken (screenshot, error, false positive). Extract: what happened, expected behavior, affected file(s).
- **Improvement** — enhance existing behavior. Extract: which skill/agent/hook, what aspect.
- **New capability** — add something missing. Extract: what, why, which files affected. Internet research is mandatory here — new patterns require external evidence.

### Step 2: Spawn the selected research agents in ONE response

Spawn ONLY the agents the matrix selected — all in the same assistant turn, NOT one per turn. Skipped sources are NOT failures; the matrix is the contract. Log omitted source(s) in the state checkpoint with the matching skip reason. The agent prompts below stay as written; just omit the agents you skip.
Replace every `{{placeholder}}` with the actual content from Step 1 before spawning.

The two codebase-facing spawns use the plugin's `codebase-research-agent`, which carries the file:line citation contract and its own output cap. The calls below are step 1 of the ladder in SKILL.md §Subagent model tiering — degrade them on `not found`. Internet research has no plugin agent and stays a general spawn.

```
Agent(prompt="""
## Task: Internet Research
Search for patterns, best practices, and known solutions related to:
{{issue description from Step 1}}

For each finding, provide:
- Source (URL or reference)
- Key pattern or technique
- Direct applicability to the issue
- Evidence strength (strong/moderate/weak)

Return findings as a structured table. Do NOT suggest implementation — research only.
""", description="Research: internet patterns")

Agent(subagent_type="geniro:codebase-research-agent",
      description="Research: ARCHITECTURE.md decisions",
      prompt="""
RESEARCH_QUESTION: Which recorded decisions, invariants, and operational rules in `ARCHITECTURE.md` constrain or inform {{issue description from Step 1}}, and does the template already follow each one?

DELIVERABLE_SHAPE: table of [{section name + file:line in ARCHITECTURE.md or the cited helper, the decision or rule, how it applies to the issue, already-followed yes/no}]. Research only — do NOT suggest implementation.

SCOPE_HINT: `ARCHITECTURE.md` — read it in full rather than sampling; it is a consolidated decision record, one section per milestone (state files, memory layers, each skill) plus cross-cutting sections (subagent model selection, deep mode, self-learning, operational rules), each listing key rulings as bullets with file-path citations. When a ruling cites a `_shared/` helper or skill file, read that target for the full contract.

OUTPUT_PATH: .geniro/state/improve-template/.research-architecture-<slug>.md

THOROUGHNESS: medium
""")

Agent(subagent_type="geniro:codebase-research-agent",
      description="Research: codebase exploration",
      prompt="""
RESEARCH_QUESTION: What is the current state of the template files related to {{issue description from Step 1}} — which files are affected, what do they do today, and where are the gaps, inconsistencies, or broken cross-references?

DELIVERABLE_SHAPE: table of [{file:line range, current behavior, gap or inconsistency found, how other template files handle the same situation}]. Research only — do NOT suggest implementation.

SCOPE_HINT: repo root — skills/, agents/, hooks/, lib/, scripts/, cursor/. Read each affected file in full rather than sampling: keyword search shows matching lines only, which misses reworded coverage of the same rule and produces false "missing" findings. `scripts/dump-md.sh [path ...]` prints every tracked `.md` file under the given paths in full. Cover cross-references in both directions (does file A reference file B correctly, are the paths valid) and check whether another skill already solves the same problem.

OUTPUT_PATH: .geniro/state/improve-template/.research-codebase-<slug>.md

THOROUGHNESS: medium
""")
```

### Step 3: Collect and record

Wait for all spawned agents. The two `codebase-research-agent` spawns report to their `OUTPUT_PATH` files rather than inline — read each one; the internet agent returns inline. Write key findings plus `research-sources: [list]` to the state checkpoint.

---

## PHASE 2: CROSS-REFERENCE & FILTER

**Purpose:** Filter raw research to evidence-backed improvements only. This is orchestrator work — you aggregate and filter directly, no subagents needed.

### Step 1: Build a combined findings list

Merge findings from the research agents that ran (1-3, depending on the matrix). Group by topic. Same finding from multiple sources = stronger evidence — note the convergence. If only one source ran, evidence strength caps at what that source supports.

### Step 2: Filter each finding

For each finding, assess yourself:

**Structural compatibility:**
- Compatible with template architecture? (skills = orchestrators, agents = leaf workers)
- Would it break existing patterns or cross-references?
- Which files would need changes?

**Evidence quality:**
- **Strong:** documented in official Claude Code docs, proven in production framework, or demonstrated by screenshot/error
- **Moderate:** backed by a recorded decision in ARCHITECTURE.md, or a logical extension of documented behavior
- **Weak:** single blog post, theoretical benefit, "should work" reasoning
- **Rejected:** no evidence, contradicts known limitations, or speculative

### Step 3: Build the evidence table

Keep only findings that are:
- Structurally compatible (or adaptable)
- Evidence quality: strong or moderate
- Not contradicted by other findings

Write checkpoint with approved finding count.

---

## PHASE 2b: REDUNDANCY & RELEVANCE VALIDATION (orchestrator-inline)

**Purpose:** Adversarial gate BEFORE the user sees findings — catches items that duplicate existing instructions or propose theoretical/over-engineered changes.

Orchestrator-inline validation per finding (no subagent — light synthesis that fits the orchestrator's context, which a spawn would only wrap in isolation this work doesn't need; same rationale as /review Phase 3 dedup). For each Phase 2-approved finding, the orchestrator:

1. **Redundancy check (ALIGNS / CONTRADICTS / NEUTRAL):** Grep target files for instructions covering the same ground. CONTRADICTS = duplicate; ALIGNS = compatible with existing; NEUTRAL = novel-but-non-conflicting.
2. **Relevance check (APPROPRIATE / OVER-ENGINEERED):** weigh against current scope — APPROPRIATE if needed for stated purpose; OVER-ENGINEERED if YAGNI or defensive polish.
3. **One-line rationale** captures the why.

Then tag: FILTER if CONTRADICTS (redundant) or OVER-ENGINEERED (not needed); otherwise KEEP. Write checkpoint with KEEP count. Filtered findings appear in Phase 3's "Filtered" section for transparency but are not proposed for implementation.

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

Use the `AskUserQuestion` tool — a plain-text option list bypasses the approvals persistence the tool records (`skills/_shared/gate-rendering.md` §Lean-question conventions). Call it with:
- **Question:** "How should I proceed with these findings?"
- **Options (use these exactly):**
  - "Implement all findings" — every KEEP finding becomes the Phase 4 approved set
  - "Let me pick which ones to implement" — walk the findings as multi-select `AskUserQuestion` calls (≤4 options per call, chaining past the cap), mirroring `.claude/skills/audit-plugin/phase-5-action-gate.md`'s pick path; the findings picked become the Phase 4 approved set
  - "I disagree with some findings — let me challenge them" — go to Phase 3b
  - "Research deeper on specific items" — go to Phase 3b

### Phase 3b: challenge resolution

For each challenged finding, spawn a research agent with: the finding description, the user's concern, and instructions to search for definitive evidence. Update the evidence table based on results. Re-present to user. Loop until approved.
