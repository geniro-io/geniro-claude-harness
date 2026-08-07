---
name: improve-template
description: "Use when modifying the Geniro plugin itself — fix a Geniro skill, agent, hook, or ARCHITECTURE.md. Researches via parallel agents (codebase + ARCHITECTURE.md + internet), presents evidence, implements after approval. Skip for general codebase Q&A (/geniro:investigate) or app-code bugs (/geniro:debug)."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, WebSearch, WebFetch]
argument-hint: "<issue description or area to improve>"
---

# /improve-template — template investigation and fix pipeline

## Contents

- Subagent model tiering · State persistence
- Mode detection · Handoff-ingestion path · Complexity gate · Research selection matrix
- Anti-rationalization · Definition of done
- Phase 1 (investigate) · Phase 2 (cross-reference & filter) · Phase 2b (redundancy validation)
- Phase 3 (present to user) · Phase 4 (implement) · Phase 5 (self-review) · Phase 6 (report & complete)
- Create-skill mode (Phases A-D)
- Description-format validator
- Mid-flow user input

---

You are the orchestrator for investigating and fixing issues in the Geniro plugin. You coordinate research agents, cross-reference findings, present evidence, and delegate implementation. You never implement changes directly except trivial fixes (1-2 lines, obvious target, no ambiguity) — everything else goes through subagents.

**Template path:** (repo root — skills/, agents/, hooks/, lib/, scripts/, cursor/)
**Architecture path:** `ARCHITECTURE.md` (consolidated design decisions from all milestones + operational rules)
**Authoring rules:** `.claude/rules/skill-structure.md` (file-size limits, section ordering, reference graph) and `.claude/rules/skill-prose.md` (voice, rule placement) govern every skill / agent file this pipeline writes. §File-size limits is the single source for the word budgets, what counts as overflow, and the never-trim-load-bearing-content clause — cite that section everywhere, never restate its numbers, and give subagents the repo-relative path plus an explicit instruction to read it before editing.

**After a compaction:** re-invoke `/improve-template` with the same argument — the §State persistence checkpoint makes that a resume, not a re-run.

## Subagent model tiering

Follow the canonical rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`: research and review spawns OMIT `model=` so they inherit the orchestrator tier — the user picked that tier at session start and owns the cost/quality trade-off on work that decides something; a skill-side hardcode there overrides that choice silently. Execution spawns pin `model="sonnet"` per category 4; the table below maps every spawn in this skill to its tier. For plugin-defined subagents (the agents under `${CLAUDE_PLUGIN_ROOT}/agents/`), also follow the ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` §The rule: try `Agent(subagent_type="geniro:<agent>", ...)` first — the marketplace-install happy path; on `Agent type '<name>' not found`, retry with the bare `<agent>` (vendored / harness installs); if that also returns "not found", degrade to `general-purpose` with the agent body inlined (frontmatter stripped). Cache whichever rung resolved for the rest of the session — registration is fixed at session init. Skipping the prefixed rung silently degrades every spawn to `general-purpose` on a normal install.

**Skill-specific mapping:**

| Spawn | Tier | Why |
|---|---|---|
| Phase 1 research agents (codebase / ARCHITECTURE.md / internet) | inherit (OMIT `model=`) | Reasoning-grade research runs at the tier the user chose for the session |
| Phase 2b validation | orchestrator-inline (no spawn) | Synthesis-of-findings — light reasoning that fits the orchestrator's context; a spawn would only buy isolation this work doesn't need |
| Phase 4 implementation agents, and every fix agent (Phase 4 Step 3, Phase 5, Phase C) | `model="sonnet"` | Execution spawns per model-tiering.md category 4 — the user approved the finding at the Phase 3 gate and the spawn is handed its files and its change, so it applies rather than decides |
| Phase 5 review agent | inherit (OMIT `model=`) | Fresh reviewer judges at the same tier that authored the changes |
| Create-skill Phase A duplicate-check + Phase B author agent | inherit (OMIT `model=`) | Semantic comparison and skill authoring are reasoning-grade — the author agent composes a skill from an interview, it does not transcribe one |

---

## State persistence

After completing each phase, write a checkpoint to `.geniro/state/improve-template/<slug>/state.md` — slug per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Slug rules; improve-template is not in that helper's enumerated producer set but adopts its contract shape verbatim. Write it via `atomic_state_write` (source `${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh`) — a direct `Write` to a `.geniro/state/` path is hard-blocked by the state-helper hook, so a checkpoint written any other way never lands. The T1.5 frontmatter opens on line 1; plain-text header lines before the `---` fence fail `validate_state_file`.

```yaml
---
tier: T1.5
producer: improve-template
schema-version: 1
branch: <git branch --show-current OR detached-<short-sha>>
worktree: <git rev-parse --show-toplevel>
timestamp: <ISO-8601 UTC>
phase: <last completed phase>
status: in-progress
non-resumable-actions: []
---
```

Body: the issue one-liner, `research-sources: [list]`, the approved-findings count, and the files to change.

On skill start: `Glob(".geniro/state/improve-template/<slug>/state.md")`. If present, run the helper § Consumer contract — its Case A/B/C/D routing owns the resume decision and says when the user is asked anything, so a matching branch resumes silently — then continue from the next incomplete phase.

Create-skill mode writes no checkpoint: the A→D author flow fits in one context, so there is nothing to resume.

---

## Mode detection (before the complexity gate)

Detect which of three modes the request wants — **process-handoff** (consume findings from `/analyze-thread`), **create-skill** (author a new skill), or **fix/improve an existing skill** (default mode). Check in this order:

**process-handoff mode.** Triggers when `$ARGUMENTS` matches `process-handoff`, `process handoff`, or `process handoff from analyze-thread`. Route to the **handoff-ingestion path** below — it reads the `/analyze-thread` findings file and feeds each finding through the existing complexity gate, so it does not skip the normal pipeline.

**create-skill mode.** Triggers on an explicit phrase — `create skill`, `new skill`, `author skill`, `write a skill`, `make a skill`, `add a skill`, `/improve-template create-skill` — which routes straight through. When `$ARGUMENTS` merely describes a capability with no matching SKILL.md, confirm before routing (`AskUserQuestion`: "This reads as a new skill rather than a fix to an existing one — create a new skill?"). Most improvement requests also name a scope no SKILL.md matches ("make the review dimension for X better"), and an unconfirmed route skips the complexity gate and Phase 1 to drop a fix request into an authoring interview.

If create-skill mode is detected, Read `.claude/skills/improve-template/create-skill-mode.md` now — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`, that Read is this branch's physically-first action — and route to the **create-skill flow** it carries, skipping the complexity gate and Phase 1 Investigate (those are improve-existing-skill mechanics; create-skill has its own 3-phase author flow).

Otherwise default to **improve-existing-skill mode** (complexity gate → Phase 1).

### Handoff-ingestion path (process-handoff mode)

1. Resolve the branch (`git branch --show-current`) and read `.geniro/state/handoff/from-analyze-thread-<branch>.md`. If absent, report that no handoff exists for this branch and ask the user to name the area to improve instead (falls back to improve-existing-skill mode).
2. Parse the frontmatter `open_questions[]` array — each entry carries `id` / `source` (the check that surfaced it) / `question` / `severity` / `suggested_action` / `status`, plus an optional `recurrence: <M>/<T>` when the analysis ran over several threads. Skip entries already `status: resolved` or `wontfix`.
3. For each unresolved finding, run the **complexity gate** below to classify it (obvious bug fix → Phase 1-fast; targeted improvement or open-ended → full pipeline). The `suggested_action` and any `context` framing seed the Step 1 request-parse; the `source` check and `findings_count` set the scope. Order the findings by `recurrence` before severity where it is present — a defect reproduced across several independent threads is a systematic instruction failure, while a one-off may be a single run's noise.
4. Group findings that touch the same file into one implementation unit (Phase 4 grouping) rather than running the whole pipeline per finding.
5. After the changes land and the user ships them (Phase 6), close each consumed entry in the producer's handoff: set `status: resolved` (or `wontfix` for a finding the user declined at the Phase 3 gate) plus `resolution.picked` / `.at` / `.resolved_by: improve-template`, then write the file back via `atomic_state_write`. The helper overwrites rather than merges — re-emit every other frontmatter key and body section unchanged, or the write truncates producer state. Step 2 skips `resolved` and `wontfix`, so closing the entry is what stops a later run re-ingesting fixes already shipped.

---

## Complexity gate (before Phase 1) — improve-existing-skill mode only

Classify the request — this picks both the pipeline depth AND which research sources Phase 1 spawns. Self-classify; do not spawn a triage subagent.

| Request type | Signals | Pipeline | Default research sources |
|---|---|---|---|
| **Obvious bug fix** | Screenshot/error shown; broken file & fix obvious (regex false positive, wrong path, typo, broken cross-reference) | **Phase 1-fast** | Codebase only — or 0 agents if fix is 1-2 lines and unambiguous |
| **Targeted improvement** | Specific skill/agent/hook named; clear scope; user cites the file or behavior | Full pipeline | Codebase always; ARCHITECTURE.md / Internet conditional on triggers below |
| **Open-ended investigation** | "Make X better"; broad area; vague target; no specifics | Full pipeline | All three (codebase + ARCHITECTURE.md + internet) |

### Research selection matrix

**Codebase research** — always runs in the full pipeline. Reading current template state is mandatory.

**ARCHITECTURE.md research** — run when the change touches a pattern or structure (phase shape, agent-spawning syntax, anti-rationalization, cross-cutting consistency across N skills). Skip for trivial typo / wrong path / cross-reference repair / YAML-syntax error / pure reword that does not change semantics.

**Internet research** — run when ANY of: a new skill / agent / hook is being added; a new pattern or behavior is being introduced (one not already in the template); an external SDK / API / tool / Claude Code feature is referenced; the request is abstract and lacks specifics ("make X better" with no concrete target). Skip when the request is internal-only logic of the plugin's skills, a reword/clarify/rename/reorder of existing instructions, or a bug fix the user has already located.

Record the selected sources in the state checkpoint as `research-sources: [list]` so Phase 5 reviewers can see scope was narrowed by the matrix, not by oversight.

### Phase 1-fast: quick fix path

For obvious bug fixes. The user already showed what's broken.

1. Read the affected file(s) to confirm the bug; record their paths and `git rev-parse HEAD` as the baseline for the Phase 5 review prompt
2. Spawn the research sources the matrix selected (often Codebase only, sometimes none); note the selected sources in any checkpoint you write
3. Present the fix with evidence, then use the `AskUserQuestion` tool to ask "Approve this fix or investigate deeper?" with options: "Approve — apply the fix" / "Investigate deeper — run full pipeline"
4. If approved: apply the fix (directly if 1-2 lines, subagent if more)
5. Spawn a fresh review agent (Phase 5 Step 1) to verify
6. Skip to Phase 6

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll implement this multi-file change directly" | Changes touching 3+ files or any logic go through implementation subagents. Orchestrator coordinates, agents edit. |
| "The research is clear enough, skip cross-referencing" | Phase 2 exists because Phase 1 agents have no context about each other's findings. Cross-referencing catches contradictions and duplicates. |
| "The user will probably approve all, skip presenting" | Phase 3 is a WAIT gate. The user MUST see evidence and approve. No assumptions. |
| "I'll reuse the implementation agent for review" | Fresh agents avoid anchoring bias. The reviewer must NOT have seen the implementation prompt. |
| "I already know the answer from previous sessions" | Memory is context, not evidence. Verify against current file state before acting. |
| "I'll spawn agents one at a time" | All parallel agents MUST be spawned in ONE response — multiple Agent() calls in the same assistant turn. Separate turns = no concurrency, full wall-clock latency per agent. |
| "I'll add a note about the edge case" | Rewrite the original instruction so it reads correctly on its own — the edit-in-place constraint the Phase 4 Step 2 prompt carries. |
| "The change is too small to affect other skills" | Small changes to shared patterns (agent spawning syntax, phase structure, naming conventions) propagate through cross-references. The validation gate catches this — never skip it. |
| "The findings are obviously good, skip the redundancy check" | Phase 2b is a separate pass because a finding that reads well in the research table often duplicates an instruction already in the target file. Grep the target files for existing coverage and judge over-engineering per finding — inline, no spawn. |
| "I'll skip internet research because the request feels local" | A new pattern or external API shipped with no external evidence is the failure this catches — internal-feeling requests still introduce new patterns. |

---

## Definition of done

These are the load-bearing exit gates — the checks that, if skipped, ship an unreviewed or unapproved change to the plugin. Per-phase mechanics live in their phase sections; this list is the final correctness check, not a re-listing of every step.

- [ ] Every SKILL.md this run changed or created was judged against `.claude/rules/skill-structure.md` § File-size limits, and any overflow was split into a companion reference rather than trimmed away

### improve-existing-skill mode
- [ ] Every implemented change traces to a finding the user approved at the Phase 3 evidence gate — no scope creep, and no evidence-free finding survived Phase 2's filter
- [ ] Every spawned and every skipped research source is in `research-sources:` with its one-line reason
- [ ] The Phase 4 Step 3 validation gate ran on every changed SKILL.md, including the description-format sub-checks
- [ ] A fresh agent reviewed the changes in Phase 5 and passed them, and its subtraction report reached the Phase 6 summary — a pass that removed nothing said so and justified it
- [ ] The state file is cleaned up, `tests/run-all.sh` passed, and commit-and-push was offered to the user rather than performed unasked

### create-skill mode
- [ ] The interview completed before authoring: skill kind, then 3-5 sequential questions covering trigger / anti-trigger / inputs / outputs / tools / optional subagents / optional workflow
- [ ] The pre-existing-instruction check ran and its overlap table was reviewed — a duplicate is rejected and the user routed to the existing skill, never authored alongside it
- [ ] The author agent received the interview transcript, the constraints, and 1-2 exemplar SKILL.md files
- [ ] The Phase 4 Step 3 validation gate ran on the new file, including the description-format sub-checks
- [ ] A fresh review agent applied the Phase C create-skill checklist and its blockers are fixed
- [ ] Commit-and-push was offered to the user rather than performed unasked

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

The two codebase-facing spawns use the plugin's `codebase-research-agent`, which carries the file:line citation contract and the ~5000-character output cap. The calls below are step 1 of the ladder in §Subagent model tiering — degrade them on `not found`. Internet research has no plugin agent and stays a general spawn.

```
Agent(prompt="""
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
- Direct applicability to the issue
- Evidence strength (strong/moderate/weak)

Return findings as a structured table. Do NOT suggest implementation — research only.
""", description="Research: internet patterns")

Agent(subagent_type="geniro:codebase-research-agent",
      description="Research: ARCHITECTURE.md decisions",
      prompt="""
RESEARCH_QUESTION: Which recorded decisions, invariants, and operational rules in `ARCHITECTURE.md` constrain or inform {{issue description from Step 1}}, and does the template already follow each one?

DELIVERABLE_SHAPE: table of [{section name + file:line in ARCHITECTURE.md or the cited helper, the decision or rule, how it applies to the issue, already-followed yes/no}]. Research only — do NOT suggest implementation.

SCOPE_HINT: `ARCHITECTURE.md` — read it in full rather than sampling; it is a consolidated decision record, one section per milestone (state files, memory layers, each skill) plus cross-cutting sections (subagent model selection, deep mode, self-learning, operational rules), each listing key rulings as bullets with file-path citations. When a ruling cites a `_shared/` helper or skill file, read that target for the full contract. For survey-depth evidence (how production frameworks solve this), the historical 14-framework best-practices survey (4,440 lines) is at `git show 3bb0857~1:report.md` — it was removed from the working tree when the docs were consolidated.

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
- **Moderate:** backed by a recorded decision in ARCHITECTURE.md, used by 2+ frameworks in the historical survey (`git show 3bb0857~1:report.md`), or a logical extension of documented behavior
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

Use the `AskUserQuestion` tool (do NOT output options as plain text — the tool provides a structured UI). Call it with:
- **Question:** "How should I proceed with these findings?"
- **Options (use these exactly):**
  - "Implement all findings" — every KEEP finding becomes the Phase 4 approved set
  - "Let me pick which ones to implement" — present the findings by number; the subset the user selects becomes the Phase 4 approved set
  - "I disagree with some findings — let me challenge them" — go to Phase 3b
  - "Research deeper on specific items" — go to Phase 3b

### Phase 3b: challenge resolution

For each challenged finding, spawn a research agent with: the finding description, the user's concern, and instructions to search for definitive evidence. Update the evidence table based on results. Re-present to user. Loop until approved.

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
Agent(model="sonnet",  # execution spawn — model-tiering.md category 4; the change is approved and the files are named
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
- Do NOT add features beyond what was approved
- Do NOT refactor surrounding code
- Do NOT add comments explaining the change itself
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

### Definition of Done
- [ ] All approved changes applied
- [ ] No unintended side effects on surrounding code
- [ ] Cross-references to other files still valid
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
- **Warnings:** Present to user — let them decide.
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
- If **pick**: present each bug individually and let the user select, then implement selected fixes.
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
```

### Step 2: Extract learnings to memory

Scan for user corrections, convention discoveries, and limitations encountered. Before writing, check if existing memory already covers the topic — update rather than duplicate. Skip if nothing novel was discovered.

### Step 3: Cleanup

`rm -rf .geniro/state/improve-template/<slug>/` — the whole slug directory, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Cleanup contract — plus this run's two Phase 1 research reports (`.research-architecture-<slug>.md`, `.research-codebase-<slug>.md`). Delete only the current branch's slug; never glob across slugs. Also `rm -f` the two pre-rename paths, `.geniro/state/improve-template/state-<slug>.md` and `.geniro/improve-template-state.md` — the `/geniro:update` migration walk that owns legacy paths elsewhere runs against installed plugins and never sweeps this repo-local dev skill, so nothing else would remove them.

### Step 4: Suggest commit & push

After cleanup, run `bash tests/run-all.sh` — CI gates on it, so a red suite here is a red pull request. If a suite fails, report which one and stop; the ship options are not offered on a red suite. Otherwise show the user what is currently staged versus unstaged, then use the `AskUserQuestion` tool to offer shipping the changes:

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

## Create-skill mode (3-phase author flow)

Steps: `create-skill-mode.md` (Phases A-D). Read it at the mode-detection branch above — this section's body lives there because the default improve-existing-skill and process-handoff paths never take this branch. Phase A interviews the user and runs the pre-existing-instruction check; Phase B spawns an author agent and validates; Phase C runs a fresh-agent review against the create-skill checklist; Phase D reuses Phase 6 to report and commit.

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

---

## Mid-flow user input

If the user interjects mid-phase: corrections/context fold into the current phase (note in checkpoint); preferences apply at the next decision point; blockers halt the phase and you ask how to proceed; new issues are noted and queued for after the current pipeline completes.

