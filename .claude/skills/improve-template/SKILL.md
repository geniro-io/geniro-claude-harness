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

- Loop invariants
- Subagent model tiering · State persistence
- Workspace · Mode detection · Handoff-ingestion path · Complexity gate · Research selection matrix
- Anti-rationalization · Definition of done
- Phase 1 (investigate) · Phase 2 (cross-reference & filter) · Phase 2b (redundancy validation) · Phase 3 (present to user) — Phases 1-3 in `phase-1-3-investigate-present.md`
- Phase 4 (implement) · Phase 5 (self-review) · Phase 6 (report & complete) — Phases 4-6 in `phase-4-6-implement-review.md`
- Create-skill mode (Phases A-D)
- Description-format validator — in `phase-4-6-implement-review.md`

---

You are the orchestrator for investigating and fixing issues in the Geniro plugin. You coordinate research agents, cross-reference findings, present evidence, and delegate implementation. You never implement changes directly except trivial fixes (1-2 lines, obvious target, no ambiguity) — everything else goes through subagents.

## Loop invariants

1. **Spawn every batch of parallel agents in ONE assistant response.** Phase 1's up-to-three research agents, Phase 4's implementation agents, and any Phase 3b re-research round all serialize into full per-agent wall-clock latency if split across turns.
2. **Review is always a fresh agent that saw neither the research nor the implementation prompt.** Phase 5 Step 1, the Phase 5 Step 3 pre-existing-bug re-review, and the create-skill Phase C review all depend on anchoring-free eyes — reusing an agent from an earlier phase defeats the check it exists to run.
3. **The Phase 3 evidence gate is a WAIT: proceed only on an explicit answer, never an assumed one.** Phase 2b's filter and the Phase 3b challenge loop both feed findings back into this same gate rather than around it.
4. **Never implement a change directly beyond a 1-2 line, unambiguous fix.** A larger or ambiguous change — in any phase, not only Phase 4 — goes through an implementation subagent; the orchestrator coordinates, agents edit.
5. **Mid-flow user input folds into the current phase; it never restarts the pipeline.** Corrections/context fold into the current phase (note in the checkpoint); preferences apply at the next decision point; blockers halt the phase and ask how to proceed; new issues are noted and queued for after the current pipeline completes.

**Template path:** (repo root — skills/, agents/, hooks/, lib/, scripts/, cursor/)
**Architecture path:** `ARCHITECTURE.md` (consolidated design decisions from all milestones + operational rules)
**Authoring rules:** `.claude/rules/skill-structure.md` (file-size limits, section ordering, reference graph) and `.claude/rules/skill-prose.md` (voice, rule placement) govern every skill / agent file this pipeline writes. §File-size limits is the single source for the word budgets, what counts as overflow, and the never-trim-load-bearing-content clause — cite that section everywhere, never restate its numbers, and give subagents the repo-relative path plus an explicit instruction to read it before editing.

**Phase bodies.** This file is the spine — role, invariants, gates, phase map. **Read the phase's Steps on entry to that phase**, from `.claude/skills/improve-template/`: `phase-1-3-investigate-present.md` (Phases 1-3) · `phase-4-6-implement-review.md` (Phases 4-6). That Read is the phase's physically-first action, per `skills/_shared/phase-entry-read.md` — the phase files hold this skill's gates (including the Phase 3 evidence gate and the Phase 3b challenge loop) and their spawn templates, so work started before the Read runs outside them.

**After a compaction:** re-Read the phase file for whatever phase is running before continuing it — only the front-loaded prefix re-attaches, so a mid-phase summary can drop the Steps while leaving this spine intact. If which phase was running is also gone, re-invoke `/improve-template` with the same argument — the §State persistence checkpoint makes that a resume, not a re-run.

## Subagent model tiering

Follow the canonical rule in `skills/_shared/model-tiering.md`: research and review spawns OMIT `model=` so they inherit the orchestrator tier — the user picked that tier at session start and owns the cost/quality trade-off on work that decides something; a skill-side hardcode there overrides that choice silently. Execution spawns pin `model="sonnet"` per category 4; the table below maps every spawn in this skill to its tier. For plugin-defined subagents (the agents under `agents/`), also follow the ladder in `skills/_shared/spawn-agent.md` §The rule: try `Agent(subagent_type="geniro:<agent>", ...)` first — the marketplace-install happy path; on `Agent type '<name>' not found`, retry with the bare `<agent>` (vendored / harness installs); if that also returns "not found", degrade to `general-purpose` with the agent body inlined (frontmatter stripped). Cache whichever rung resolved for the rest of the session — registration is fixed at session init. Skipping the prefixed rung silently degrades every spawn to `general-purpose` on a normal install.

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

After completing each phase, write a checkpoint to `.geniro/state/improve-template/<slug>/state.md` — slug per `skills/_shared/within-skill-state-handoff.md` § Slug rules; improve-template is not in that helper's enumerated producer set but adopts its contract shape verbatim. Write it via `atomic_state_write` (source `lib/atomic-state-write.sh`) — a direct `Write` to a `.geniro/state/` path is hard-blocked by the state-helper hook, so a checkpoint written any other way never lands. The T1.5 frontmatter opens on line 1; plain-text header lines before the `---` fence fail `validate_state_file`.

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

## Workspace (before mode detection)

Phase 4's agents edit plugin files and Phase 6 commits them, so where this run works is a real choice. Follow `skills/_shared/workspace-chooser.md` Mode WORK-BASE for the option catalogue, recommendation policy, and persistence contract — that repo-relative path, since a project-local skill expands no plugin-root variable and the authoring lint hard-fails on one.

Run `ListAgents` once here, then passive-detect (first match wins):

```
1. Resumable state.md for this slug  ⇒ SKIP; re-apply its branch: / worktree: per
                                       within-skill-state-handoff.md § Mismatch handling.
2. Already inside a worktree         ⇒ CONTINUE here; echo tree and branch.
3. Feature branch, no peer session   ⇒ CONTINUE in place; name `worktree` as the reverse.
4. Protected branch OR peer session  ⇒ Fire the workspace question.
```

The peer-session trigger is this pipeline's alone: the plugin's own repo routinely has a second session editing it, both changesets interleave in `git status` carrying no authorship, and a file they both touched can only be staged whole. A worktree is what keeps them separable.

Persist before Phase 1 spawns anything — `approvals[]` category `improve_template_workspace_setup` plus `branch:` / `worktree:` in one `atomic_state_write` — because Phase 1's research reads whichever tree this settles on. The `worktree` / `new-branch` / `current-branch` modifiers pre-answer and suppress the question.

---

## Mode detection (before the complexity gate)

Detect which of three modes the request wants — **process-handoff** (consume findings from `/analyze-thread`), **create-skill** (author a new skill), or **fix/improve an existing skill** (default mode). Check in this order:

**process-handoff mode.** Triggers when `$ARGUMENTS` matches `process-handoff`, `process handoff`, or `process handoff from analyze-thread`. Route to the **handoff-ingestion path** below — it reads the `/analyze-thread` findings file and feeds each finding through the existing complexity gate, so it does not skip the normal pipeline.

**create-skill mode.** Triggers on an explicit phrase — `create skill`, `new skill`, `author skill`, `write a skill`, `make a skill`, `add a skill`, `/improve-template create-skill` — which routes straight through. When `$ARGUMENTS` merely describes a capability with no matching SKILL.md, confirm before routing (`AskUserQuestion`: "This reads as a new skill rather than a fix to an existing one — create a new skill?"). Most improvement requests also name a scope no SKILL.md matches ("make the review dimension for X better"), and an unconfirmed route skips the complexity gate and Phase 1 to drop a fix request into an authoring interview.

If create-skill mode is detected, Read `.claude/skills/improve-template/create-skill-mode.md` now — per `skills/_shared/phase-entry-read.md`, that Read is this branch's physically-first action — and route to the **create-skill flow** it carries, skipping the complexity gate and Phase 1 Investigate (those are improve-existing-skill mechanics; create-skill has its own 4-phase author flow).

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
| "This mid-phase pick isn't one of the skill's named gates — I'll settle it in chat" | The Phase 3 finding pick, the Phase 5 warning batch and pre-existing-bug walk, the create-skill overlap gate, and the Phase 6 ship gate are examples, not the complete set — route every user-facing choice through `AskUserQuestion` (`skills/_shared/gate-rendering.md` §Lean-question conventions owns the rule). |

---

## Definition of done

These are the load-bearing exit gates — the checks that, if skipped, ship an unreviewed or unapproved change to the plugin. Per-phase mechanics live in their phase sections; this list is the final correctness check, not a re-listing of every step.

- [ ] The workspace step settled before Phase 1 spawned anything, and its pick is recorded in the state file's `branch:` / `worktree:`
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

Steps: `phase-1-3-investigate-present.md` §Phase 1. Read it now — it also carries Phase 2, Phase 2b, and Phase 3 below. Gather evidence from the research sources the matrix selected — up to three independent sources (codebase / ARCHITECTURE.md / internet).

---

## PHASE 2: CROSS-REFERENCE & FILTER

Steps: `phase-1-3-investigate-present.md` §Phase 2 (continued from the Phase 1 Read above). Filter raw research to evidence-backed improvements only — orchestrator work, no subagents.

---

## PHASE 2b: REDUNDANCY & RELEVANCE VALIDATION (orchestrator-inline)

Steps: `phase-1-3-investigate-present.md` §Phase 2b (continued from the Phase 1 Read above). Adversarial gate before the user sees findings — catches items that duplicate existing instructions or propose theoretical/over-engineered changes.

---

## PHASE 3: PRESENT TO USER (WAIT)

Steps: `phase-1-3-investigate-present.md` §Phase 3 (continued from the Phase 1 Read above), including the Phase 3b challenge-resolution loop. Show evidence-backed findings and get approval before any changes.

---

## PHASE 4: IMPLEMENT (delegated)

Steps: `phase-4-6-implement-review.md` §Phase 4. Read it now — it also carries Phase 5 and Phase 6 below, plus the Description-format validator. Applying approved changes through subagents; the orchestrator does not edit files itself except trivial 1-2 line fixes.

---

## PHASE 5: SELF-REVIEW (fresh subagent)

Steps: `phase-4-6-implement-review.md` §Phase 5 (continued from the Phase 4 Read above). A fresh agent that saw neither research nor implementation reviews the diff and reports what it removed.

---

## PHASE 6: REPORT, LEARN & COMPLETE

Steps: `phase-4-6-implement-review.md` §Phase 6 (continued from the Phase 4 Read above). Summarize, extract learnings, clean up state, and offer to ship.

---

## Create-skill mode (4-phase author flow)

Steps: `create-skill-mode.md` (Phases A-D). Read it at the mode-detection branch above — this section's body lives there because the default improve-existing-skill and process-handoff paths never take this branch. Phase A interviews the user and runs the pre-existing-instruction check; Phase B spawns an author agent and validates; Phase C runs a fresh-agent review against the create-skill checklist; Phase D reuses Phase 6 to report and commit.

---

## Description-format validator (Phase 4 Step 3 extension)

Steps: `phase-4-6-implement-review.md` §Description-format validator. The 6 format checks it adds to the Phase 4 validation gate apply to BOTH improve-existing-skill (when changes touch a SKILL.md description field) AND create-skill mode.

