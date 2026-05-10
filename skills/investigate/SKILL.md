---
name: geniro:investigate
description: "Use when answering deep codebase questions that need evidence — repo structure, code behavior, git history, or internet sources. Parallel research agents produce cited answers. Skip for bug fixes (/geniro:debug) or codebase mapping (/geniro:onboard)."
context: main
model: inherit
allowed-tools: [Read, Bash, Glob, Grep, Agent, AskUserQuestion, WebSearch, WebFetch]
argument-hint: "[question about the codebase, e.g. 'how does auth work?', 'why was X pattern chosen?']"
---

# Investigate: Deep Codebase Q&A

Use this skill to answer complex questions about the codebase that require multi-source research. Spawns parallel agents to analyze code, git history, and internet sources, then synthesizes and self-reviews the answer before presenting.

## Subagent Model Tiering

Follow the canonical rule in `skills/_shared/model-tiering.md`. Every `Agent(...)` spawn MUST pass `model=` explicitly.

## Subagent Spawn Contract

Every `Agent(...)` spawn in this skill — Phase 2 research agents (Codebase / Git / Internet), Phase 4 self-review agent, and the Step 2a save-routing agents — MUST satisfy the 6-field pre-inlined-context contract in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` (task scope / acceptance criteria / file paths with content / prohibited tools / output schema / model tier). The checklist is the authoritative requirement; the spawn templates below pre-populate every field. Subagents do NOT inherit the orchestrator's session state — bare prompts force re-discovery and silently drift from intended scope. Co-cite `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` for runtime degradation when invoking plugin-defined agents (none in this skill today; the rule applies if a future research agent is promoted to a custom agent type).

**Skill-specific mapping** — research scope drives model choice:

| Spawn | Tier | When |
|---|---|---|
| Codebase exploration (file discovery, grep, structural mapping) | `sonnet` | Always — needs cross-file reasoning, but bounded scope |
| Internet research (docs, GitHub issues, blog posts) | `sonnet` | Default — narrow focused queries |
| Git history / blame analysis | `sonnet` | Reasoning over commit messages and diffs |
| Final synthesis across multiple research streams | `opus` | When investigation question is ambiguous OR involves architectural reasoning across 3+ subsystems |
| Final synthesis (simple lookup) | `sonnet` | Default — well-scoped questions with clear answer |

## Evidence Standard

A claim is evidence-backed ONLY when it cites one of these artifact kinds:

| # | Kind | Example |
|---|---|---|
| 1 | File:line + verified snippet (orchestrator re-read confirms text matches) | `src/auth.ts:42-58` snippet pasted |
| 2 | Captured command output (grep / test run / build / git command output) | `git log --oneline ... → 3 commits, latest abc123` |
| 3 | Log line or stack trace from the running system | `ERROR 2026-04-01 ... NullPointerException at ...` |
| 4 | Query result against the actual datastore | `SELECT count(*) FROM users WHERE ... → 17 rows` |
| 5 | User-provided artifact (screenshot, log paste, data dump, config snippet) | user pastes failing request body |

Reasoning, paraphrased agent claims, "looks consistent", convergent agent self-reports, and "I inferred from context" are NOT evidence. They are hypotheses that still need verification.

If the orchestrator's tools cannot produce evidence for a load-bearing claim, the claim is unverified — DO NOT synthesize an answer around it. Use the Phase 2.5 verification gate or the missing-data gate (AskUserQuestion) instead.

## Question

$ARGUMENTS

**If `$ARGUMENTS` is empty**, use the `AskUserQuestion` tool with header "Investigation" and question "What would you like to investigate?" with options "How does [feature] work?" / "Why was [pattern/decision] chosen?" / "What are the risks of changing [area]?" / "Compare approaches for [goal]". Do not proceed until a question is provided.

## Phase 1: Classify & Scope

### Step 0: Load custom instructions

Load `.geniro/instructions/global.md` if present. Apply its **Rules** and **Constraints** sections throughout the run (e.g., "always cite file:line", "never query prod without the read-replica proxy"). Phase-specific "Additional Steps" entries may not have matching phases in this skill — apply where they fit, otherwise skip.

### Step 1: Parse the question

Classify into one of. The "Agents needed" column is the literal spawn set — 1, 2, or 3 agents.

| Type | Description | Agents needed |
|---|---|---|
| **Current-code trace** | "How does this function / module work right now?" — behavior lives in the code itself. | Codebase only |
| **Commit archaeology** | "When/who/why did this line change?" answerable purely from git log/blame. | Git only |
| **External docs lookup** | "What does library X's Y API do?" / "What changed in framework Z between versions?" — answer is external, no project specifics needed. | Internet only |
| **How (current state)** | How does X work today? Trace execution + evolution. | Codebase + Git |
| **How (forward-looking)** | How CAN we do X / connect X to Y / integrate W? Requires evidence from current code (what's already there to build on), git (what's been tried before), and internet (external interfaces, library capabilities). Skip Internet ONLY when both X and Y are fully internal — rare edge case, e.g. "connect table A to table B inside our own DB". | Codebase + Git + Internet |
| **Why** | Why was X chosen? Design rationale requires current code patterns + history + industry context. | Codebase + Git + Internet |
| **What-if** | What happens if we change X? Impact in our code + external compatibility. | Codebase + Internet |
| **Compare** | Compare approaches for X (ours vs alternatives). | Codebase + Internet |
| **Risk** | What are the risks of X? Evidence needed from all three. | Codebase + Git + Internet |

### Step 2: Identify scope

From the question, extract:
- **Target area**: which files, modules, or patterns are relevant
- **Depth needed**: surface-level overview vs deep trace
- **Skip criteria** — apply ONLY to prune agents the Phase 1 Step 1 row already includes. They never *add* agents beyond the table's literal set (the table wins). Each criterion is testable against the question text:
  - **Skip Codebase** when the question is answerable purely from git log/blame ("when did X change?", "who wrote Y?") or purely from external docs ("what does library Z's API do?") — and the classified row does not include Codebase.
  - **Skip Git** when the question is about current code behavior only and does not ask about history, evolution, rationale, or recent changes — and the classified row does not include Git.
  - **Skip Internet** when the question is fully internal — our code, our patterns, our commits — and does not reference external libraries, frameworks, standards, best practices, alternatives, or security advisories — and the classified row does not include Internet.

### Step 2.5: Glossary-mismatch check (WAIT if mismatch found)

CLAUDE.md is auto-loaded and may contain a "Domain Context" section (added by `/geniro:setup` Phase 3.1) listing domain entities, safety rules, and API contracts. Before Phase 2 spawn, check whether the user's question uses terms that conflict with the documented glossary — investigating with the wrong vocabulary returns the wrong answer.

Procedure:

1. **Extract domain terms from the question** — proper-noun-shaped tokens, role names, entity names (e.g., "tenant", "workspace", "task", "invoice"). Skip generic technical terms ("function", "endpoint", "cache").
2. **Grep the auto-loaded CLAUDE.md content for each term**. Look for: definition lines (`**Tenant** — ...`), entity lists (`Domain entities: Tenants, Workspaces, ...`), and safety-rule mentions.
3. **Classify each match:**
   - **No match** — the term may be new domain vocabulary (route to Phase 5 auto-extract); proceed without challenge.
   - **Exact match** — the user's term aligns with the glossary; proceed.
   - **Mismatch** — the user's term appears in the glossary but the question's usage suggests a different meaning (e.g., user says "workspace" meaning "browser tab" but glossary defines "workspace" as "tenant container"). FIRE the gate.
4. **If mismatch found:** use `AskUserQuestion` with header "Glossary" before spawning Phase 2 agents:
   - **Question**: "Your CLAUDE.md defines `<term>` as `<glossary definition>`. Your question seems to use `<term>` as `<inferred usage>`. Which one should I investigate?"
   - **Options**: "Use the glossary definition" / "Use my new meaning (and note the divergence in the answer)" / "Both — these are genuinely different concepts that share a name (please pick disambiguating names)"
5. Record the resolution in the answer's Sources section so the synthesized answer carries the disambiguation forward.

Skip this step entirely when CLAUDE.md has no Domain Context section, when the question has no domain-shaped terms, or when all terms are exact matches. When in doubt, skip — false positives waste user time more than false negatives waste investigation budget.

Before spawning agents, check `<PRIMARY_ROOT>/.geniro/knowledge/learnings.jsonl` for existing answers to this question or closely related topics (resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A; Grep with keywords from the question). If a comprehensive answer exists, present it and ask the user if they want fresh investigation.

If the question is ambiguous, use the `AskUserQuestion` tool to clarify scope before spawning agents. Ask one focused question, not multiple.

## Phase 2: Investigate (parallel agents)

Spawn 1-3 agents in ONE response — all Agent() calls in the same assistant turn, NOT one per turn — matching the literal "Agents needed" set from Phase 1 Step 1. No agent is unconditional; each must pass the Phase 1 Step 2 skip criteria. When only one agent is spawned, it is still spawned via `Agent(...)` (not inlined) so Phase 4 self-review can verify its findings against a fresh transcript.

Every spawn below pre-populates the 6 required fields from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` (task scope, acceptance criteria, file paths with content, prohibited tools, output schema, model tier) and obeys the runtime-degradation rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` (bare-name first; degrade to `general-purpose` only on "Agent type not found"). Replace every `{{placeholder}}` with actual content before spawning; pre-inline file contents under `## Pre-Inlined Files` rather than expecting the agent to re-Glob.

### Agent A: Codebase Analyst (when not skipped by Phase 1 Step 2)

```
Agent(model="sonnet", description="Investigate: codebase analysis", disallowedTools=["Edit", "Write", "NotebookEdit"], prompt="""
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
Agent(model="sonnet", description="Investigate: git history", disallowedTools=["Edit", "Write", "NotebookEdit"], prompt="""
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
Agent(model="sonnet", description="Investigate: internet research", disallowedTools=["Edit", "Write", "NotebookEdit"], prompt="""
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

## Phase 2.5: Verify (orchestrator re-checks each load-bearing claim)

Before synthesizing the answer, the ORCHESTRATOR (not a subagent) independently re-verifies every claim that will end up as evidence in the answer. Agent self-reports are inputs, not proof.

### Step 1: Extract load-bearing claims

From the agent findings, list each claim that would appear as `Evidence:` in the synthesized answer — file:line references, command outputs, commit hashes, package versions, behavior descriptions.

### Step 2: Re-verify each claim against ground truth

For each claim, run the matching check yourself:

| Claim kind | Re-verification |
|---|---|
| File:line snippet | Read the file, confirm the snippet text matches at the cited lines |
| Grep / search result | Re-run the grep yourself, compare hit count and matched lines |
| Command output | Re-run the command, compare output |
| Commit / blame | Run `git show <hash>` or `git blame -L <range> <file>`, compare |
| External fact (library version, API behavior) | Re-fetch the source URL or re-search; compare wording |

A claim is **verified** when the orchestrator's own re-run matches the agent's report. A claim is **unverified** when the orchestrator cannot reproduce the agent's report OR cannot run the check at all (no DB access, no service access, no credentials, no logs).

### Step 3: Route unverified claims

For each unverified claim, choose ONE:
- **Drop** it from the answer (the answer must work without this claim)
- **Request data** from the user via the Phase 3 missing-data gate (Step 1 below) — needed when the claim is load-bearing AND only the user can provide the artifact (production logs, runtime state, screenshots, dataset access, credentials)

Do NOT advance to Phase 3 synthesis until every load-bearing claim is either verified or has a pending user-data request.

## Phase 3: Synthesize

After all agents complete, synthesize findings yourself (no subagent — this is orchestrator work).

### Step 0: Missing-data gate (WAIT)

If Phase 2.5 left any load-bearing claim unverified AND only the user can supply the missing artifact, PAUSE and use the `AskUserQuestion` tool (do NOT output options as plain text — use the tool's structured UI) BEFORE drafting the answer. Header: "Missing data". Phrase the question concretely; offer 2-4 specific options for what data the user can provide. Examples:

- "Paste the failing request/response body" / "Paste the log line at the moment of the bug" / "I don't have it — proceed without"
- "Confirm the production schema for table X" / "Provide a screenshot of the broken UI" / "I don't have it — proceed without"
- "Share the relevant rows from dataset Y (CSV / sample paste)" / "I don't have access" / "Skip this sub-question"

If the user picks "I don't have it / skip", drop the corresponding claim — do NOT synthesize around it. If the user provides data, treat it as evidence kind (5) per the Evidence Standard and re-enter Phase 2.5 Step 2 to re-verify the claim against the new artifact. Loop max twice; if still unverified, drop the claim and explicitly note the gap in the final answer.

### Step 1: Cross-reference

- Identify where agents agree — convergent agent reports are still self-reports, NOT verified evidence; carry them into Phase 2.5 re-verification
- Identify where agents disagree or have gaps — flag for Phase 2.5 re-verification or the Phase 3 Step 0 missing-data gate
- Single-source claims do NOT get a "lower confidence" label — they get the same Phase 2.5 re-verification treatment as any other claim

### Step 2: Draft the answer

Structure the answer based on question type:

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

### Step 3: Confidence-driven action (no caveats-as-substitute)

For each major claim, check it has a verified artifact per the Evidence Standard. Confidence labels are NOT a substitute for evidence — they drive action:

- **Verified** (artifact 1-5 produced + Phase 2.5 re-check passed): include the claim with the artifact cited inline.
- **Unverified but verifiable**: re-enter Phase 2.5 with a specific re-check before drafting.
- **Unverified and only the user can supply the artifact**: route through the Phase 3 Step 0 missing-data gate.
- **Unverifiable** (no path to evidence): omit the claim. Note the gap explicitly in the answer's "Open questions" section. Do NOT ship a labelled "low-confidence" claim as a substitute for evidence.

## Phase 4: Self-Review (fresh agent)

Spawn a fresh review agent to verify the draft answer. This agent must NOT have seen the research prompts — it reviews with fresh eyes. The spawn satisfies the 6-field contract in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` and obeys the runtime-degradation rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`.

Default the verifier to `sonnet` (well-scoped: check references, flag over-claims). Only escalate to `opus` if the user explicitly opted in to deep synthesis for an ambiguous cross-subsystem question — otherwise keep `sonnet`.

```
Agent(model="sonnet", description="Review: verify investigation answer", disallowedTools=["Edit", "Write", "NotebookEdit"], prompt="""
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
1. **Spot-check Phase 2.5**: Phase 2.5 already had the orchestrator re-verify cited claims. Pick 2-3 load-bearing claims at random; re-Read their cited file:lines and confirm the snippet still matches. If a sample fails, that's a Phase 2.5 gap — flag it as a blocker, not a single-claim correction.
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

### Process review results:
- **Blockers**: Fix the answer (orchestrator corrects directly — these are text edits, not code)
- **Warnings**: Add missing context or caveats to the answer
- **Nits**: Apply if they improve clarity
- **Verified**: Proceed to Phase 5

If blockers are found, fix and re-verify with another fresh agent. Max 1 re-review round — track the count in your own scratchpad; at the limit, present what you have to the user with the remaining blockers flagged, and stop.

## Phase 5: Present

### Step 1: Deliver the answer

Present the synthesized, reviewed answer to the user. Include:
- The structured answer from Phase 3 (post-review fixes applied)
- A "Sources" section listing key files examined and agents used — every cited artifact (file:line, command output, query result, user-provided data) is listed
- An "Open questions" section listing any sub-questions that could not be evidence-backed AND were not resolvable via the missing-data gate. Be explicit about what data would settle each one — do NOT paper over with a "low-confidence" caveat.

### Step 2: Offer follow-up

Use the `AskUserQuestion` tool (do NOT output options as plain text) with header "Follow-up" and question "Want to dig deeper?" with options:
- "Dive deeper into [specific aspect]" — re-run with narrower scope
- "I have a follow-up question" — start a new investigation
- "Save key findings to memory" — persist important discoveries (see Step 2a for routing — learnings.jsonl, ADR, OR CLAUDE.md Domain Context)
- "Done — answer is sufficient"

### Step 2a: Save-routing (when user picks "Save key findings to memory")

Before writing to a single store, classify each finding to its proper destination per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md`:

Every save-routing Agent() spawn below MUST satisfy the 6-field pre-inlined-context contract in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` (task scope / acceptance criteria / file paths with content / prohibited tools / output schema / model tier) AND obey the runtime-degradation rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` (bare-name first; degrade to `general-purpose` only on "Agent type not found"). The save-routing agents do not currently use a custom subagent type (they spawn as `general-purpose` directly), but the spawn-agent.md rule still applies for any future promotion to a plugin-defined agent.

1. **Domain-vocabulary findings** — the investigation surfaced a new domain entity, role, or business-rule term that wasn't in CLAUDE.md's Domain Context. Examples: "the codebase calls X a `Tenant` but production calls it a `Workspace`" / "there's a hidden `BillingAccount` entity that wraps `Subscription`+`PaymentMethod`+`Invoice`."
   - Route: **CLAUDE.md** "Domain Context" section.
   - Method: present the proposed addition (1-3 lines per term) via `AskUserQuestion` with header "Domain term", options "Add to CLAUDE.md (Recommended)" / "Save as learning instead" / "Skip — not durable enough".
   - On approval: investigate's `allowed-tools` does NOT include Write/Edit (research-only by design). Spawn a focused Agent (`model="sonnet"`, no `subagent_type`) per the 6-field checklist (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`) and runtime-degradation rule (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`) with the proposed term-block pre-inlined (field 3) and the instruction: "Read CLAUDE.md, locate the `## Domain Context` section (create one before the first `##`-level section if missing — confirm via the orchestrator's prior AskUserQuestion answer pre-inlined here), append the proposed term-block at the section's end, do not modify other sections. Report the resulting diff." Pin task scope (field 1), acceptance criteria (field 2: "Domain Context section contains the proposed term-block; no other sections modified"), allowed mutation surface (field 4: only CLAUDE.md), output schema (field 5: returned diff), and model tier (field 6: sonnet). This preserves investigate's research-only identity while enabling the auto-extract; the agent does the file write.
2. **Architectural decisions meeting all 3 ADR criteria** (hard to reverse + surprising + genuine trade-offs) — route to **ADR** per `_shared/improvement-routing.md` § ADR target. Draft the ADR using the template; ask user before creating `docs/adr/` if the directory doesn't exist. Same pattern as #1: investigate has no Write tool, so spawn a focused Agent under the same checklist + spawn-agent.md contract (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` + `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`) with the drafted ADR content + target path pre-inlined; agent writes to `docs/adr/NNNN-<slug>.md`.
3. **Reusable technical insights** (gotchas, lightweight architectural decisions, surprising coupling) — route to **`<PRIMARY_ROOT>/.geniro/knowledge/learnings.jsonl`** following `_shared/learnings-extraction.md` (the canonical doc references the primary-worktree resolver). Apply the Reflect → Abstract → Generalize pre-pass. Same pattern as #1/#2: spawn a focused Agent under the same checklist + spawn-agent.md contract (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` + `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`) to append the JSON entry to the file (or use the auto-memory path if the entry maps to project-memory shape).
4. **User preferences about how to collaborate** — route to **auto-memory** (`feedback_*`). Auto-memory is created via Claude Code's native memory feature — no file write needed, so this path doesn't require the agent-spawn workaround.

Findings can route to multiple stores when they're load-bearing in different ways (e.g., a domain term that's also an ADR-worthy decision). Do NOT batch all findings into one save action — present them grouped by target so the user sees what goes where.

If user wants to dive deeper: re-enter Phase 2 with refined scope (reuse prior findings as context). Max 2 dive-deeper rounds — track the count in your own scratchpad; if the user needs more, suggest starting a fresh `/geniro:investigate` with the refined question.
If user wants to save findings: follow Step 2a save-routing (above) — classify each finding to CLAUDE.md Domain Context (new domain terms), ADR (architectural decisions meeting 3 criteria), `<PRIMARY_ROOT>/.geniro/knowledge/learnings.jsonl` (reusable insights), or auto-memory (collaboration preferences). Do NOT default everything to learnings.jsonl. Before writing to any store, check if an existing entry covers the topic — UPDATE rather than duplicate.

If user picks "Done — answer is sufficient": chain a second `AskUserQuestion` to route them to any follow-up action the investigation surfaced. Skip this second question if the user already indicated they are done with the topic entirely.
- **Question:** "Anything to act on from this investigation?"
- **Header:** "Next step"
- **Options:**
  - label: "Fix a bug I found" — description: "Run `/geniro:debug <symptom>` to investigate and propose a fix"
  - label: "Implement a change (non-trivial)" — description: "Run `/geniro:implement` to design and build the change (its Phase 2 architect+skeptic produces a plan you approve before code)"
  - label: "Implement a quick change" — description: "Run `/geniro:follow-up <what to change>` for trivial/small fixes"
  - label: "Nothing — just wanted the answer" — description: "End here. Resume your prior work."

## Git Constraint

Do NOT run `git add`, `git commit`, `git push`, or `git checkout`. You may use `git log`, `git diff`, `git blame`, and `git show` for investigation.

## Compliance — Do Not Skip Phases

| Your reasoning | Why it's wrong |
|---|---|
| "I already know the answer from reading the code" | You read one perspective. Parallel agents catch what you missed — git history reveals intent, internet reveals context. |
| "I'll spawn all 3 to be safe" | Irrelevant agents are net-negative — they consume tokens and their off-target findings force the synthesizer to filter noise. Phase 1 Step 2 skip criteria drive the set, not safety defaults. |
| "Self-review is overkill for a question" | Wrong answers waste more time than the review costs. File references go stale, claims drift from evidence. |
| "The question mentions a library, but I'll skip Internet — I can answer from code" | The skip criteria require evidence, not guesses. If the question references an external dependency, framework, or standard, Internet is in the set. Use the Phase 1 Step 2 rules, not intuition. |
| "The classification says 1 agent but I'll add Codebase for safety" | The classification table is the literal spawn set. Adding an agent the skip criteria excluded is the over-spawn anti-pattern in miniature. If the criteria look wrong for this question, revise the question's classification — don't silently add agents. |
| "I'll spawn agents one at a time to save tokens" | Parallel agents go in ONE response — multiple Agent() calls in the same assistant turn. Sequential turns waste wall-clock time for no token savings. |
| "The user seems to want a quick answer" | A wrong quick answer is worse than a correct 30-second-slower answer. Run the pipeline. |
| "All three agents converge on the same claim — that's confirmed" | Convergent self-reports are still self-reports. Phase 2.5 requires the orchestrator to independently re-read / re-run / re-grep before treating any agent claim as evidence. |
| "The reasoning chain is tight, that's enough evidence" | Reasoning is hypothesis, not evidence. Only the artifact kinds (file:line snippet, captured output, log line, query result, user data) clear the Evidence Standard. |
| "I'll add a 'low-confidence' caveat and ship the claim anyway" | Caveats are not evidence. Phase 3 Step 3 requires verified / re-verify / ask-user / omit — there is no "ship with caveat" path. |
| "How-can-we / Compare / What-if questions are forward-looking, they don't need code-level verification" | All investigation types require evidence-backed answers. "How can we connect X to Y" must cite the actual schema/API/integration points; "what would break" must cite the actual call sites — not speculate. |

## Definition of Done

- [ ] Question classified and scoped (Phase 1)
- [ ] Glossary-mismatch check executed against CLAUDE.md Domain Context (Phase 1 Step 2.5); resolved via AskUserQuestion if mismatch found
- [ ] Parallel research agents completed (Phase 2)
- [ ] Findings cross-referenced and synthesized (Phase 3)
- [ ] Answer self-reviewed by fresh agent (Phase 4)
- [ ] Answer presented with cited artifacts, Sources, and explicit Open questions for any unverified claims (Phase 5)
- [ ] Follow-up offered to user; if user picks "Save key findings", findings routed per Step 2a (CLAUDE.md / ADR / learnings.jsonl / memory) NOT defaulted to a single store

---

## When to Use This Skill

**Use `/geniro:investigate`:**
- "How does X work in this codebase?"
- "Why was this pattern/library/approach chosen?"
- "What would break if we changed X?"
- "Compare approach A vs B for our use case"
- "What are the risks of doing X?"
- Complex questions requiring multiple sources of evidence

**Don't use:**
- Bug with unclear root cause → use `/geniro:debug`
- Need to implement something → use `/geniro:implement`
- First time in the codebase → use `/geniro:onboard`
- Simple factual question answerable by reading one file → just read the file

---

## Examples

### Example 1: Understanding a Feature
```
/geniro:investigate how does the authentication flow work?
```
→ Codebase agent traces auth middleware, token validation, session management
→ Git agent finds when auth was added and major changes
→ Synthesize into execution flow with file:line references
→ Self-review verifies all references are accurate
→ Present: flow diagram + key files + edge cases

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
→ Phase 2.5 verifies: re-Read the schema files cited; re-run the grep for prior connector code; confirm the analytics-API endpoint exists per docs
→ If a credential / API key / sample dataset is needed and not present, route through Phase 3 Step 0 missing-data gate
→ Synthesize: integration approach grounded in cited files + existing schema + verified external API
→ Self-review verifies all references; present with explicit "open questions" if any sub-question lacked evidence
