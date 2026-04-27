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

Before spawning agents, check `.geniro/knowledge/learnings.jsonl` for existing answers to this question or closely related topics (Grep with keywords from the question). If a comprehensive answer exists, present it and ask the user if they want fresh investigation.

If the question is ambiguous, use the `AskUserQuestion` tool to clarify scope before spawning agents. Ask one focused question, not multiple.

## Phase 2: Investigate (parallel agents)

Spawn 1-3 agents in ONE response — all Agent() calls in the same assistant turn, NOT one per turn — matching the literal "Agents needed" set from Phase 1 Step 1. No agent is unconditional; each must pass the Phase 1 Step 2 skip criteria. When only one agent is spawned, it is still spawned via `Agent(...)` (not inlined) so Phase 4 self-review can verify its findings against a fresh transcript.

Replace every `{{placeholder}}` with actual content before spawning.

### Agent A: Codebase Analyst (when not skipped by Phase 1 Step 2)

```
Agent(prompt="""
## Task: Codebase Investigation
Answer the following question by analyzing the codebase:

**Question:** {{user's question}}
**Target area:** {{files/modules/patterns to focus on}}

### Investigation strategy:
1. Find all files relevant to the question (Glob for patterns, Grep for keywords)
2. Read key files fully — do not skim
3. Trace execution paths, data flow, or dependency chains as needed
4. Identify patterns, conventions, and edge cases
5. Note any inconsistencies, dead code, or surprising behavior

### Output format:
**Files examined:** [list with line counts]

**Findings:**
For each relevant discovery:
- What: [specific finding with file:line references]
- Evidence: [code snippet or pattern observed]
- Relevance: [how this answers the question]

**Gaps:** [what you couldn't determine from code alone]

Do NOT speculate. If the code doesn't answer a sub-question, list it as a gap.
""", description="Investigate: codebase analysis", model="sonnet")
```

### Agent B: Git Historian (for How current/forward-looking, Why, Risk, What-if)

```
Agent(prompt="""
## Task: Git History Investigation
Research the git history to answer:

**Question:** {{user's question}}
**Target area:** {{files/modules to focus on}}

### Investigation strategy:
1. `git log --oneline -30 -- {{target files}}` — recent changes
2. `git log --all --oneline --grep="{{relevant keywords}}"` — commits mentioning the topic
3. `git blame {{key files}}` — who wrote critical sections and when
4. `git log --diff-filter=A -- {{target files}}` — when files were first added
5. For "why" questions: read commit messages in detail for rationale

### Output format:
**Timeline:** [key events in chronological order]

**Findings:**
For each relevant discovery:
- What: [commit hash, date, author, change summary]
- Evidence: [commit message excerpt or diff summary]
- Relevance: [how this answers the question]

**Patterns:** [trends in how this area evolves — refactors, bug fixes, feature additions]

Do NOT speculate about intent beyond what commit messages state.
""", description="Investigate: git history", model="sonnet")
```

### Agent C: Internet Researcher (for How forward-looking, Why, What-if, Compare, Risk)

```
Agent(prompt="""
## Task: Internet Research
Research external sources to help answer:

**Question:** {{user's question}}
**Target area:** {{technologies, patterns, or concepts involved}}

### Investigation strategy:
1. Use WebSearch for each query. Use WebFetch to read full page content when a search result looks highly relevant.
2. Search for official documentation of relevant frameworks/libraries
3. Search for best practices, known issues, or common patterns
4. Search for comparisons or alternatives if the question involves choices
5. Search for security advisories or deprecation notices if relevant

### Output format:
**Sources consulted:** [list with URLs]

**Findings:**
For each relevant discovery:
- What: [specific finding]
- Source: [URL or reference]
- Relevance: [how this answers the question]
- Reliability: [official docs / widely-accepted / single source / opinion]

**Consensus:** [what most sources agree on, if applicable]
**Disagreements:** [where sources conflict, if applicable]

Report facts with sources. Flag opinions as opinions.
""", description="Investigate: internet research", model="sonnet")
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

Spawn a fresh review agent to verify the draft answer. This agent must NOT have seen the research prompts — it reviews with fresh eyes.

Default the verifier to `sonnet` (well-scoped: check references, flag over-claims). Only escalate to `opus` if the user explicitly opted in to deep synthesis for an ambiguous cross-subsystem question — otherwise keep `sonnet`.

```
Agent(prompt="""
## Task: Verify Investigation Answer
Review this answer for accuracy, completeness, and honesty. You were NOT involved
in the research — verify with fresh eyes.

**Original question:** {{user's question}}

**Draft answer:**
{{full draft answer from Phase 3}}

### Verification checklist:
1. **Spot-check Phase 2.5**: Phase 2.5 already had the orchestrator re-verify cited claims. Pick 2-3 load-bearing claims at random; re-Read their cited file:lines and confirm the snippet still matches. If a sample fails, that's a Phase 2.5 gap — flag it as a blocker, not a single-claim correction.
2. **Completeness**: Does the answer fully address the question? Any obvious gaps?
3. **Honesty**: Is every load-bearing claim backed by an artifact (Evidence Standard kinds 1-5)? Are unverified claims listed in "Open questions" rather than smuggled in with caveats?
4. **Clarity**: Would someone unfamiliar with this code understand the answer?
5. **Over-claims**: Does the answer claim certainty where evidence is actually weak?
6. **Missing context**: Is there important context the answer should mention but doesn't?

### For each issue found:
- Location in the answer
- Issue description
- Severity: blocker (factually wrong) / warning (incomplete) / nit (clarity)
- Suggested fix

If no issues: report "VERIFIED — answer is accurate and complete"
""", description="Review: verify investigation answer", model="sonnet")
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
- "Save key findings to memory" — persist important discoveries
- "Done — answer is sufficient"

If user wants to dive deeper: re-enter Phase 2 with refined scope (reuse prior findings as context). Max 2 dive-deeper rounds — track the count in your own scratchpad; if the user needs more, suggest starting a fresh `/geniro:investigate` with the refined question.
If user wants to save findings: extract non-obvious architectural insights, design rationale, or gotchas. Save as `project` memory. Before writing, check if an existing memory covers this topic — UPDATE rather than duplicate.

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
- [ ] Parallel research agents completed (Phase 2)
- [ ] Findings cross-referenced and synthesized (Phase 3)
- [ ] Answer self-reviewed by fresh agent (Phase 4)
- [ ] Answer presented with cited artifacts, Sources, and explicit Open questions for any unverified claims (Phase 5)
- [ ] Follow-up offered to user

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
