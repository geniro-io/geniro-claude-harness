---
name: geniro:investigate
description: "Deep investigation of codebase questions with parallel research agents. Analyzes repo structure, code behavior, git history, and internet sources to produce evidence-backed answers. Do NOT use for bug fixes (/geniro:debug), implementation (/geniro:implement), or codebase orientation (/geniro:onboard)."
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

## Question

$ARGUMENTS

**If `$ARGUMENTS` is empty**, use the `AskUserQuestion` tool with header "Investigation" and question "What would you like to investigate?" with options "How does [feature] work?" / "Why was [pattern/decision] chosen?" / "What are the risks of changing [area]?" / "Compare approaches for [goal]". Do not proceed until a question is provided.

## Phase 1: Classify & Scope

### Step 1: Parse the question

Classify into one of:

| Type | Description | Agents needed |
|---|---|---|
| **How** | How does X work? Trace execution, data flow | Codebase + Git |
| **Why** | Why was X chosen? Design rationale, history | Git + Internet |
| **What-if** | What happens if we change X? Impact analysis | Codebase + Internet |
| **Compare** | Compare approaches for X | Internet + Codebase |
| **Risk** | What are the risks of X? | Codebase + Git + Internet |

### Step 2: Identify scope

From the question, extract:
- **Target area**: which files, modules, or patterns are relevant
- **Depth needed**: surface-level overview vs deep trace
- **Internet needed**: yes if question involves best practices, alternatives, framework internals, or "why" questions about external dependencies

Before spawning agents, check `.geniro/knowledge/learnings.jsonl` for existing answers to this question or closely related topics (Grep with keywords from the question). If a comprehensive answer exists, present it and ask the user if they want fresh investigation.

If the question is ambiguous, use the `AskUserQuestion` tool to clarify scope before spawning agents. Ask one focused question, not multiple.

## Phase 2: Investigate (parallel agents)

Spawn 2-3 agents in ONE response — all Agent() calls in the same assistant turn, NOT one per turn — based on the classification from Phase 1. Always spawn the Codebase agent. Add Git and/or Internet agents based on the question type.

Replace every `{{placeholder}}` with actual content before spawning.

### Agent A: Codebase Analyst (always spawned)

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

### Agent B: Git Historian (for How, Why, Risk, What-if)

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

### Agent C: Internet Researcher (for Why, What-if, Compare, Risk)

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

## Phase 3: Synthesize

After all agents complete, synthesize findings yourself (no subagent — this is orchestrator work).

### Step 1: Cross-reference

- Identify where agents agree (convergent evidence = high confidence)
- Identify where agents disagree or have gaps
- Flag findings supported by only one source as lower confidence

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

### Step 3: Mark confidence

For each major claim in the answer, mentally tag it:
- **High confidence**: multiple sources agree, code confirms
- **Medium confidence**: single source or code-only without history context
- **Low confidence**: inference, no direct evidence — mark explicitly as "likely but unconfirmed"

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
1. **Accuracy**: For every file:line reference, read the actual file and verify the claim
2. **Completeness**: Does the answer fully address the question? Any obvious gaps?
3. **Honesty**: Are confidence levels appropriate? Are speculations marked as such?
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

If blockers are found, fix and re-verify with another fresh agent. Max 1 re-review round.

## Phase 5: Present

### Step 1: Deliver the answer

Present the synthesized, reviewed answer to the user. Include:
- The structured answer from Phase 3 (post-review fixes applied)
- A "Sources" section listing key files examined and agents used
- Confidence markers on any claims that are medium or low confidence

### Step 2: Offer follow-up

Use the `AskUserQuestion` tool (do NOT output options as plain text) with header "Follow-up" and question "Want to dig deeper?" with options:
- "Dive deeper into [specific aspect]" — re-run with narrower scope
- "I have a follow-up question" — start a new investigation
- "Save key findings to memory" — persist important discoveries
- "Done — answer is sufficient"

If user wants to dive deeper: re-enter Phase 2 with refined scope (reuse prior findings as context). Max 2 dive-deeper rounds — if the user needs more, suggest starting a fresh `/geniro:investigate` with the refined question.
If user wants to save findings: extract non-obvious architectural insights, design rationale, or gotchas. Save as `project` memory. Before writing, check if an existing memory covers this topic — UPDATE rather than duplicate.

If user picks "Done — answer is sufficient": chain a second `AskUserQuestion` to route them to any follow-up action the investigation surfaced. Skip this second question if the user already indicated they are done with the topic entirely.
- **Question:** "Anything to act on from this investigation?"
- **Header:** "Next step"
- **Options:**
  - label: "Fix a bug I found" — description: "Run `/geniro:debug <symptom>` to investigate and propose a fix"
  - label: "Implement a change (non-trivial)" — description: "Run `/geniro:plan` to design the change before building"
  - label: "Implement a quick change" — description: "Run `/geniro:follow-up <what to change>` for trivial/small fixes"
  - label: "Nothing — just wanted the answer" — description: "End here. Resume your prior work."

## Git Constraint

Do NOT run `git add`, `git commit`, `git push`, or `git checkout`. You may use `git log`, `git diff`, `git blame`, and `git show` for investigation.

## Compliance — Do Not Skip Phases

| Your reasoning | Why it's wrong |
|---|---|
| "I already know the answer from reading the code" | You read one perspective. Parallel agents catch what you missed — git history reveals intent, internet reveals context. |
| "The question is simple, skip the agents" | Simple questions get simple agent prompts. The structure catches blind spots even for "obvious" answers. |
| "Self-review is overkill for a question" | Wrong answers waste more time than the review costs. File references go stale, claims drift from evidence. |
| "I'll skip internet research, it's a code question" | Even code questions benefit from framework docs, known issues, and deprecation context. Skip only when truly irrelevant (Phase 1 classification). |
| "I'll spawn agents one at a time to save tokens" | Parallel agents go in ONE response — multiple Agent() calls in the same assistant turn. Sequential turns waste wall-clock time for no token savings. |
| "The user seems to want a quick answer" | A wrong quick answer is worse than a correct 30-second-slower answer. Run the pipeline. |

## Definition of Done

- [ ] Question classified and scoped (Phase 1)
- [ ] Parallel research agents completed (Phase 2)
- [ ] Findings cross-referenced and synthesized (Phase 3)
- [ ] Answer self-reviewed by fresh agent (Phase 4)
- [ ] Answer presented with confidence markers and sources (Phase 5)
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
