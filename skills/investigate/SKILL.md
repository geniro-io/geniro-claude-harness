---
name: investigate
description: "Use when answering deep codebase questions that need evidence — repo structure, code behavior, git history, or internet sources. Parallel research agents produce cited answers. Skip for bug fixes (/geniro:debug) or codebase mapping (/geniro:onboard)."
context: main
model: inherit
allowed-tools: [Read, Bash, Glob, Grep, Agent, AskUserQuestion, WebSearch, WebFetch]
argument-hint: "[question about the codebase, e.g. 'how does auth work?', 'why was X pattern chosen?']"
---

# Investigate: deep codebase Q&A

## Contents

- State machine
- Loop invariants
- Anti-rationalization
- Quality-first budgets
- Subagent model tiering · Subagent spawn contract
- Evidence Standard
- ACI per-phase tool surface
- Git constraint
- Definition of done
- Phase 1 (Classify+Scope) · Phase 2 (Investigate+Verify) · Phase 3 (Synthesize+Review+Present)
- State file schema
- Examples

---

3-phase loop (Classify+Scope → Investigate+Verify → Synthesize+Review+Present). Spawns parallel research agents to analyze code, git history, and internet sources, then synthesizes, verifies with a fresh agent, and presents the answer.

**Runtime portability.** `${CLAUDE_PLUGIN_ROOT}` is set by Claude Code. When it is unset (another Agent-Skills runtime, e.g. Cursor), resolve it before following any reference: the plugin root is the ancestor directory of this file containing `.claude-plugin/plugin.json` — substitute it for every `${CLAUDE_PLUGIN_ROOT}` occurrence and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. Tool and hook substitutions for non-Claude-Code runtimes: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md`.

## State machine

state.md `phase:` enum: `classify` → `investigate` → `present` → `done` (happy path). Terminal states: `done`, `present-summary-only`, `aborted`, `routed` (the SessionStart recovery treats all as "task complete — no resume"). Non-terminal states roll back to phase-entry on compaction-resume and re-run idempotently. Escalation states (`classify-escalated`, `investigate-escalated`) surface to the user as "task was paused — last AUQ options" so the user re-picks without losing context. The `present-loop` sub-state fires on Phase 3 Step 4 "dive deeper" follow-up (max 2 rounds).

Full ASCII state diagram in `${CLAUDE_PLUGIN_ROOT}/skills/investigate/investigate-taxonomy-reference.md` §1.

**After a compaction, re-invoke this skill before running a phase whose steps are not in context** — only the first ~5,000 tokens of a skill are re-attached after a summary; state.md `phase:` says where to resume.

## Loop invariants

The canonical agent-loop invariants in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` apply, with two investigate-specific bindings:

- **Invariant #4 (bounded structured tool results)** — research-agent outputs (Codebase / Git / Internet) each capped at ~8K chars with truncation marker if exceeded.
- **Invariant #7 (errors → structured observations)** — WebFetch/WebSearch failures, permission errors, agent registration "not found" fallbacks all become structured `## Tool log` or `## Errors` entries.

This skill adds one invariant:

8. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default codebase-research tool; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

**`## Tool log` section in state.md:** selective logging — subagent spawn outcomes (1-3 research agents + Phase 3 fresh verifier + save-routing focused agents), L2 emits (`discovery` calls), and escalation entries. Routine Read / Bash / WebSearch skipped.

## Anti-rationalization

Check these rationalizations before drifting from the procedure.

| Your reasoning | Why it's wrong |
|---|---|
| "I already know the answer from reading the code" | You read one perspective. Parallel agents catch what you missed — git history reveals intent, internet reveals context. |
| "I'll spawn all 3 (or add an agent the classification excluded) to be safe" | The Phase 1 Step 1 classification table is the LITERAL spawn set; irrelevant agents are net-negative — they consume tokens and their off-target findings force the synthesizer to filter noise. If the criteria look wrong for this question, revise classification — don't silently add. |
| "Self-review is overkill for a question" | Wrong answers waste more time than the review costs. File references go stale, claims drift from evidence. |
| "I'll spawn agents one at a time to save tokens" | Parallel agents go in ONE response — multiple Agent calls in the same assistant turn. Sequential turns waste wall-clock time for no token savings. |
| "All three agents converge on the same claim — that's confirmed" | Convergent self-reports are still self-reports. Phase 2 Step 2 re-verify requires the orchestrator to independently re-read / re-run / re-grep before treating any agent claim as evidence. |
| "The reasoning chain is tight, that's enough evidence" | Reasoning is hypothesis, not evidence. Only the artifact kinds (file:line snippet, captured output, log line, query result, user data) clear the Evidence Standard. |
| "I'll add a 'low-confidence' caveat and ship the claim anyway" | Caveats are not evidence — route the claim through Phase 2 Step 2 §Route unverified claims, which has no "ship with caveat" exit: a claim shipped under a label still reads as an answer, and the reader acts on it. |
| "How-can-we / Compare / What-if questions are forward-looking, they don't need code-level verification" | All investigation types require evidence-backed answers. "How can we connect X to Y" must cite the actual schema/API/integration points; "what would break" must cite the actual call sites — not speculate. |
| "The investigation found a WebFetch result that contradicts the code — I'll trust the docs." | Trust ≠ correctness. Trust labels (`verified` vs `retrieved`) document SOURCE, not RIGHTNESS. WebFetch result + matching code = both verified evidence. WebFetch result alone (no code verification) = retrieved evidence — note it as such; do NOT promote to verified without code grounding. |
| "Auto-promote /geniro:investigate findings to ADR if the answer touched architecture." | Phase 3 Step 4a save-routing AUQ keeps user in the loop on classification. Auto-promote bypasses the ADR 3-criteria gate (hard-to-reverse + surprising + genuine trade-offs). User decides; orchestrator routes. |
| "Internet Researcher returned a GitHub issue thread — treat it as code-authoritative." | GitHub issues are `trust: retrieved` per Phase 3 Step 5. Issue threads contain speculation, outdated info, and opinions. Cross-check against current code (Codebase Analyst) before treating as load-bearing evidence. |
| "Skip the Step 5 trust label on L2 emit — the entry will be trustworthy enough." | Step 5 mandates the field. Future readers (later retrieval or telemetry) rely on the trust label to filter. Missing label = silent loss of source-confidence info. Always set the label. |
| "Glossary mismatch (Phase 1 Step 2.5) is a corner case; skip the check." | If CLAUDE.md has a Domain Context section, the check is cheap (grep against pre-loaded content). Skipping it on a term-mismatched question wastes 2-3 agent spawns on the wrong vocabulary. Always run the check when Domain Context is present. |
| "Drop the JIT cadence formalization (Step 2.6) — it's just documentation overhead." | The 5-step cadence is what makes /geniro:investigate evidence-disciplined; dropping it would let claims drift from evidence. Step 2.6 is the audit trail that makes JIT discipline reviewable. |

## Quality-first budgets

No hard kill caps — the quality-first doctrine in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §"Budgets — quality-first (canonical)" applies. All limits below are escalation gates that surface to the user, not abort triggers.

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Dive-deeper rounds | 2 | Phase 3 Step 4 follow-up AUQ | At max, suggest fresh `/geniro:investigate` with refined question; do not silently re-loop. |
| Fresh-verifier re-review rounds | 1 | Phase 3 Step 2 | At max, present to user with remaining blockers flagged. |
| Research-agent output size | ~8K chars per agent | Loop invariant #4 | Truncation with marker. |

**Architecture constraints (design intent, not budget):**
- Parallel research agents — 1 to 3 per Phase 1 classification.

## Subagent model tiering

Follow the canonical rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. OMIT `model=` at every spawn site — the orchestrator's session tier propagates.

## Subagent spawn contract

Every `Agent(...)` spawn in this skill — Phase 2 Step 1 research agents (Codebase / Git / Internet), Phase 3 Step 2 fresh verifier agent, and Phase 3 Step 4a save-routing agents — satisfies the six pre-inlined fields in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`, because a spawn missing a field makes the subagent re-discover scope from scratch and drift. Co-cite `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` for runtime degradation when invoking plugin-defined agents: the plugin-defined `codebase-research-agent` (Phase 2 Codebase Analyst, plus codebase-locator side queries during Phase 3 synthesis) is spawned via this ladder; the Git Historian, Internet Researcher, fresh verifier, and save-routing agents are general-purpose spawns.

## Evidence Standard

A claim is evidence-backed only when it cites a canonical artifact kind. Kinds 1-5 are defined in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` § What counts as an artifact. /geniro:investigate adds one kind for its external-research mode:

| # | Kind | Example |
|---|---|---|
| 6 | External documented fact (WebFetch / WebSearch source URL + verbatim quote) | `https://docs.example.com/api → 'rate limit is 100 req/min'` |

Reasoning, paraphrased agent claims, "looks consistent", convergent agent self-reports, and "I inferred from context" are not evidence — they are hypotheses that still need verification.

If the orchestrator's tools cannot produce evidence for a load-bearing claim, the claim is unverified: an answer synthesized around it reads as authoritative while resting on nothing. Use the Phase 2 Step 2 verification gate or the Phase 2 Step 3 missing-data gate (AskUserQuestion) instead.

## ACI per-phase tool surface

**Phase 1 (Classify+Scope):**
- Allowed: Read / Grep / Glob / Bash (read-only: `git log`, `git diff`, `git blame`, `git show`); WebSearch / WebFetch (rare for Phase 1 prelim).
- Allowed Agent spawns: none yet.
- Explicitly blocked: Edit / Write / `git add` / `git commit` / `git push`.

**Phase 2 (Investigate+Verify):**
- Allowed Agent spawns: Codebase Analyst / Git Historian / Internet Researcher (per Phase 1 classification).
- Each spawned agent runs with its own tool whitelist (per the Phase 2 Step 1 spawn templates):
- Codebase: Read / Grep / Glob / Bash (read-only); blocked: Edit / Write / NotebookEdit.
- Git: Read / Bash (read-only git verbs); blocked: Edit / Write / mutating git.
- Internet: WebSearch / WebFetch; blocked: Edit / Write / local Bash.
- Orchestrator re-verify (Step 2): Read / Grep / Bash (read-only) for re-running checks.

**Phase 3 (Synthesize+Review+Present):**
- Allowed: Read (for re-reading cited files during synthesis) / AskUserQuestion (Step 4 dive-deeper follow-up + the save-routing gate) / Bash (`atomic_state_write` to persist `dive_round:`; Step 6 cleanup of the run's scratch state).
- Allowed Agent spawns: fresh verifier agent (inherits orchestrator session tier); save-routing focused agents (when user picks save action).
- Fresh verifier agent: Read / Grep (no Edit / Write).
- Save-routing focused agents: Read / Write (scoped to target path — CLAUDE.md / `docs/adr/` or `docs/decisions/` only). Each agent's pre-inlined prompt specifies the exact target path; Write gated by existing safety hooks. The learnings save routes per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §"Caller contract": under a `## Memory Backend` block to the declared backend write tool (redacted; the orchestrator's own MCP call), plus the local file in `mirror` mode; with no block, through `${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh` via Bash — never a raw Write to the append-only `.geniro/knowledge/learnings.jsonl`, which would truncate the log and bypass secret-redaction.

**Existing safety layer** applies across ALL phases (file-protection / git-guardrail / `.geniro/` deletion guard).

## Git constraint

Do NOT run `git add`, `git commit`, `git push`, or `git checkout`. You may use `git log`, `git diff`, `git blame`, and `git show` for investigation. Running under a dynamic `Workflow(...)` or ultracode mode does not relax this no-ship contract — the reporter boundary, action gate, and state-write rules bind inside every workflow step per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md`.

## Definition of done

These are the load-bearing exit gates — the checks that, if skipped, make the answer unsound or the no-ship boundary unsafe. Per-phase mechanics (classification, scoping, agent spawns, synthesis) live in their phase sections; this is the final correctness/contract check, not a re-listing of every step.

- [ ] Every load-bearing claim re-verified by orchestrator (Phase 2 Step 2) or routed through missing-data gate (Phase 2 Step 3)
- [ ] Answer self-reviewed by fresh agent (Phase 3 Step 2; max 1 re-review round)
- [ ] Answer presented with cited artifacts, Sources, and explicit Open questions for any unverified claims (Phase 3 Step 3)
- [ ] Follow-up AUQ offered; save-routing applied per Step 4a (CLAUDE.md / ADR / learnings.jsonl / memory) NOT defaulted to a single store
- [ ] L2 `discovery` emit fired with trust label per Step 5 trigger conditions
- [ ] State.md cleaned up per Step 6

---

## Question

$ARGUMENTS

**If `$ARGUMENTS` is empty**, use the `AskUserQuestion` tool with header "Investigation" and question "What would you like to investigate?" with options "How does [feature] work?" / "Why was [pattern/decision] chosen?" / "What are the risks of changing [area]?" / "Compare approaches for [goal]". Do not proceed until a question is provided.

## Phase 1: Classify+Scope

State.md `phase: classify`. Low cost — a semantic $ARGUMENTS classification + memory-layer load (instructions + snapshot + past learnings) + glossary-mismatch check. Critical for correctness: bad classification → wrong agent set → wasted research budget.

### Step 0: Load custom instructions + past learnings

On Phase 1 entry:

1. **Refresh custom instructions** — Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: investigate`, `LOAD_TIER: pipeline`, `MODE: initial-load`. Both the helper's §Procedure imperative `Read` and §Echo contract are mandatory — the helper's §Procedure owns the load set.
2. **Refresh project snapshot** — `load-semantic` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-semantic.md` default top-2 (`_project.md` + `_CODEBASE_MAP.md`). `_CODEBASE_MAP.md` content (if present) primes Phase 2's Codebase Analyst — pre-inline relevant sections into the spawn prompt.
3. **Query past learnings** — route per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.md` §"Memory backend override" (a declared `## Memory Backend` block redirects this to its read tool; the file is empty under `mode: replace`), else `source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh" && query_learnings --tag <kw1> --tag <kw2> --scope global --limit 5` (one `--tag` per keyword inferred from $ARGUMENTS). To find prior answers and avoid duplicate research.
4. **Cross-layer conflict resolution** — `resolve-conflicts` (precedence: custom instructions > project snapshot > past learnings when layers disagree; halt with AUQ on hard conflict).

Echo the loaded lines per each helper's §Echo contract.

### Step 1: Parse the question

Classify the question into one of the types below. The "Agents needed" column is the literal spawn set — 1, 2, or 3 agents.

| Type | Description | Agents needed |
|---|---|---|
| **Current-code trace** | "How does this function / module work right now?" — behavior lives in the code itself. | Codebase only |
| **Commit archaeology** | "When/who/why did this line change?" answerable purely from git log/blame. | Git only |
| **External docs lookup** | "What does library X's Y API do?" / "What changed in framework Z between versions?" — answer is external, no project specifics needed. | Internet only |
| **How (current state)** | How does X work today? Trace execution + evolution. | Codebase + Git |
| **How (forward-looking)** | How CAN X be done / connect X to Y / integrate W? Requires evidence from current code (what's already there to build on), git (what's been tried before), and internet (external interfaces, library capabilities). Skip Internet ONLY when both X and Y are fully internal — rare edge case, e.g. "connect table A to table B inside the same DB". | Codebase + Git + Internet |
| **Why** | Why was X chosen? Design rationale requires current code patterns + history + industry context. | Codebase + Git + Internet |
| **What-if** | What happens if X changes? Impact in the codebase + external compatibility. | Codebase + Internet |
| **Compare** | Compare approaches for X (the project's approach vs alternatives). | Codebase + Internet |
| **Risk** | What are the risks of X? Evidence needed from all three. | Codebase + Git + Internet |

### Step 1.5: External-lookup routing (Internet-only → consider /deep-research)

When the question classifies as **External docs lookup** (Internet only — no project code or git evidence needed), a `/deep-research` workflow, when your environment provides one, runs deeper multi-source web research than this skill's single Internet Researcher: it fans out searches across several angles, cross-checks the sources against each other, and votes on each claim before reporting. Offer it before spawning Phase 2.

Fire `AskUserQuestion` (header "Research depth"):
- **Question**: "This looks like a purely external question. `/deep-research <question>` cross-checks more web sources than a single research agent. How do you want to proceed?"
- **Options**: "Run /deep-research instead" / "Continue with /geniro:investigate"

On "Run /deep-research instead": surface the one-line directive `Run: /deep-research <question>` and terminate (`phase: routed`) — do NOT auto-invoke; run the Phase 3 Step 6 cleanup on the way out. On "Continue": proceed to Step 2 with the Internet Researcher as normal. If `/deep-research` is unavailable (workflows disabled, or no WebSearch tool), skip this step silently and continue.

This routing fires ONLY for the Internet-only classification — any question that needs code or git evidence stays in /geniro:investigate, since `/deep-research` has no codebase or git access.

### Step 2: Identify scope

From the question, extract:
- **Target area**: which files, modules, or patterns are relevant
- **Depth needed**: surface-level overview vs deep trace
- **Skip criteria** — prune agents the Phase 1 Step 1 row includes; they never add agents beyond it (the table wins). Each criterion is testable against the question text:
- **Skip Codebase** when the question is answerable purely from git log/blame ("when did X change?", "who wrote Y?") or purely from external docs ("what does library Z's API do?").
- **Skip Git** when the question is about current code behavior only and does not ask about history, evolution, rationale, or recent changes.
- **Skip Internet** when the question is fully internal — the project's code, patterns, and commits — and does not reference external libraries, frameworks, standards, best practices, alternatives, or security advisories.

### Step 2.5: Glossary-mismatch check (WAIT if mismatch found)

CLAUDE.md is auto-loaded and may contain a "Domain Context" section (added by `/geniro:setup` Phase 3.2) listing domain entities, safety rules, and API contracts. Before Phase 2 spawn, check whether the user's question uses terms that conflict with the documented glossary — investigating with the wrong vocabulary returns the wrong answer.

Procedure:

1. **Extract domain terms from the question** — proper-noun-shaped tokens, role names, entity names (e.g., "tenant", "workspace", "task", "invoice"). Skip generic technical terms ("function", "endpoint", "cache").
2. **Look each term up in the auto-loaded CLAUDE.md** — its Domain Context definitions, entity lists, and safety rules.
3. **Classify each match:**
- **No match** — the term may be new domain vocabulary (route to Step 4a save-routing later); proceed without challenge.
- **Exact match** — the user's term aligns with the glossary; proceed.
- **Mismatch** — the user's term appears in the glossary but the question's usage suggests a different meaning (e.g., user says "workspace" meaning "browser tab" but glossary defines "workspace" as "tenant container"). Fire the gate.
4. **If mismatch found:** use `AskUserQuestion` with header "Glossary" before spawning Phase 2 agents:
- **Question**: "Your CLAUDE.md defines `<term>` as `<glossary definition>`. Your question seems to use `<term>` as `<inferred usage>`. Which one should I investigate?"
- **Options**: "Use the glossary definition" / "Use my new meaning (and note the divergence in the answer)" / "Both — these are genuinely different concepts that share a name (please pick disambiguating names)"
5. Record the resolution in the answer's Sources section so the synthesized answer carries the disambiguation forward.

**Approvals-persistence:** persist the user's pick to state.md frontmatter `approvals[]` with category `glossary_resolve`. Subsequent compaction-resume reads prior pick from `approvals[]` rather than re-asking. The state.md `## Persisted approvals` body section renders this. Re-ask only if context materially changed (new glossary section added since the pick).

Skip this step entirely when CLAUDE.md has no Domain Context section, when the question has no domain-shaped terms, or when all terms are exact matches. When in doubt, skip — false positives waste user time more than false negatives waste investigation budget.

### Step 2.6: JIT retrieval cadence

Retrieval is just-in-time: infer specific tags/paths/symbols from $ARGUMENTS, spawn the classified set (Steps 1-2), pre-inline the relevant file content into each spawn (Phase 2 §A/§B/§C templates), and require structured findings citing exact refs (Evidence Standard kinds 1-6, verbatim snippets not paraphrase). Those exact refs are what the Phase 3 `discovery` emit persists in `ext.{area, insight}`.

Unique requirement: state.md `## JIT Cadence` body section logs which steps fired for this run — the audit trail that makes the JIT discipline reviewable.

**Duplicate-answer check** — before spawning agents, re-query past learnings for this question or closely related topics, routed as in Phase 1 Step 0 item 3 but with the keywords the classification has since sharpened. If a comprehensive prior answer exists, present it and ask whether the user wants a fresh investigation.

**Ambiguous scope** — when the question's scope is ambiguous, use the `AskUserQuestion` tool to clarify it before spawning agents. Ask one focused question, not multiple.

## Phase 2: Investigate+Verify

State.md `phase: investigate`. Parallel research-agent spawns + orchestrator re-verify. Exits to Phase 3 only when every load-bearing claim is verified, dropped, or routed through missing-data gate.

### Step 1: Parallel research agents

Spawn 1-3 agents in ONE response — all Agent calls in the same assistant turn, NOT one per turn — matching the literal "Agents needed" set from Phase 1 Step 1. No agent is unconditional; each must pass the Phase 1 Step 2 skip criteria. When only one agent is spawned, it is still spawned via `Agent(...)` (not inlined) so the Phase 3 Step 2 fresh verifier can check its findings against a fresh transcript.

Every spawn below follows §Subagent spawn contract. Replace every `{{placeholder}}` with actual content before spawning; pre-inline file contents under `## Pre-Inlined Files` rather than expecting the agent to re-Glob.

The Codebase Analyst spawn IS `codebase-research-agent` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research — Phase 2's `[{file, lines, observation}]` deliverable maps onto the agent's `DELIVERABLE_SHAPE: "verified findings table"` slot. Git Historian and Internet Researcher remain `general-purpose` Agent() spawns (different tool surfaces — git read-verbs / WebSearch+WebFetch respectively). For narrow codebase-locator side queries during synthesis (Phase 3) — "where is the cache-key builder defined?" / "find all call sites of X" — also spawn `codebase-research-agent`.

### Agent A: Codebase Analyst (when not skipped by Phase 1 Step 2)

Read-only research agent — the plugin `codebase-research-agent` (tools: Read / Glob / Grep / Bash; writes its findings report to OUTPUT_PATH via Bash, no Edit/Write elsewhere). Produces a `Files examined` + `Findings` (file:line + verified snippet per Evidence Standard kind 2 + Relevance) + `Gaps` report. Full spawn template (acceptance criteria, pre-inlined-files convention, investigation strategy, output schema) in `${CLAUDE_PLUGIN_ROOT}/skills/investigate/investigate-taxonomy-reference.md` §3 (Agent A).

### Agent B: Git Historian (for How current/forward-looking, Why, Risk, What-if)

Read-only research agent — `disallowedTools=["Edit", "Write", "NotebookEdit"]`, plus a strict allowlist of git read-verbs (`log`, `blame`, `show`, `diff`). Produces a chronological `Timeline` + `Findings` (commit-hash + message excerpt per Evidence Standard kind 1 + Relevance) + `Patterns` report. Full spawn template in `${CLAUDE_PLUGIN_ROOT}/skills/investigate/investigate-taxonomy-reference.md` §3 (Agent B).

### Agent C: Internet Researcher (for How forward-looking, Why, What-if, Compare, Risk)

WebSearch+WebFetch agent — `disallowedTools=["Edit", "Write", "NotebookEdit"]`, no local-codebase Bash. Produces a `Sources consulted` + `Findings` (URL + Reliability label per Evidence Standard kind 6) + `Consensus` / `Disagreements` report. Full spawn template in `${CLAUDE_PLUGIN_ROOT}/skills/investigate/investigate-taxonomy-reference.md` §3 (Agent C).

### Step 2: Verify — orchestrator re-checks each load-bearing claim

Before synthesizing the answer, the orchestrator (not a subagent) independently re-verifies every claim that will end up as evidence in the answer.

#### Extract load-bearing claims

From the agent findings, list each claim that would appear as `Evidence:` in the synthesized answer — file:line references, command outputs, commit hashes, package versions, behavior descriptions.

#### Re-verify each claim against ground truth

For each claim, run the matching check yourself:

| Claim kind | Re-verification |
|---|---|
| File:line snippet | Read the file, confirm the snippet text matches at the cited lines |
| Grep / search result | Re-run the grep yourself, compare hit count and matched lines |
| Command output | Re-run the command, compare output |
| Commit / blame | Run `git show <hash>` or `git blame -L <range> <file>`, compare |
| External fact (library version, API behavior) | Re-fetch the source URL or re-search; compare wording |

A claim is **verified** when the orchestrator's own re-run matches the agent's report. A claim is **unverified** when the orchestrator cannot reproduce the agent's report OR ran the check and it failed to complete (no DB access, no service access, no credentials, no logs — cite the failure). An untried check is not an unverified claim: run it first.

#### Route unverified claims

For each unverified claim, choose ONE:
- **Drop** it from the answer (the answer must work without this claim)
- **Request data** from the user via the missing-data gate (Step 3 below) — needed when the claim is load-bearing AND only the user can provide the artifact (production logs, runtime state, screenshots, dataset access, credentials)

Do NOT advance to Phase 3 synthesis until every load-bearing claim is either verified or has a pending user-data request.

### Step 3: Missing-data gate (WAIT for user data)

If Step 2 left any load-bearing claim unverified AND only the user can supply the missing artifact, PAUSE and use the `AskUserQuestion` tool (do NOT output options as plain text — use the tool's structured UI) BEFORE drafting the answer. Header: "Missing data". Phrase the question concretely; offer 2-4 specific options for what data the user can provide. Examples:

- "Paste the failing request/response body" / "Paste the log line at the moment of the bug" / "I don't have it — proceed without"
- "Confirm the production schema for table X" / "Provide a screenshot of the broken UI" / "I don't have it — proceed without"
- "Share the relevant rows from dataset Y (CSV / sample paste)" / "I don't have access" / "Skip this sub-question"

If the user picks "I don't have it / skip", drop the corresponding claim — do NOT synthesize around it. If the user provides data, treat it as evidence kind (5) per the Evidence Standard and re-enter Step 2 to re-verify the claim against the new artifact. Loop max twice; if still unverified, drop the claim and explicitly note the gap in the final answer.

State.md `## Open Questions` body section logs missing-data gate question + user pick. State.md transitions: `investigate` → `present` once all claims verified or routed.

## Phase 3: Synthesize+Review+Present

State.md `phase: present`. Synthesizes verified findings, a fresh verifier agent re-checks, presents to user, offers save-routing AUQ, emits L2 `discovery` with trust label.

### Step 1: Synthesize draft

After Phase 2 Step 2/3 complete (every load-bearing claim verified or routed):

#### Cross-reference

- Identify where agents agree — carry the convergent claims into Phase 2 Step 2 re-verification.
- Identify where agents disagree or have gaps — flag for Phase 2 Step 2 re-verification or the Phase 2 Step 3 missing-data gate.
- Single-source claims get no "lower confidence" label — they get the same Phase 2 Step 2 re-verification treatment as any other claim.

#### Draft the answer

Structure the answer based on question type. Five literal markdown templates (How / Why / What-if / Compare / Risk) — each with the expected sections (Overview / Execution Flow / Key Details for How; Decision / Evidence / Trade-offs for Why; Direct Impact / Ripple Effects / Risks / Recommendation for What-if; per-dimension comparison table for Compare; Risk Assessment table + Mitigations for Risk) — in `${CLAUDE_PLUGIN_ROOT}/skills/investigate/investigate-taxonomy-reference.md` §5. Copy the matching template and fill in evidence — follow its section shape so answers stay consistent and reviewable.

#### Confidence-driven action (no caveats-as-substitute)

Every claim reaching the draft already carries a verified artifact or was routed — Phase 2 Step 2 §Route unverified claims is where that was decided, and it has no "ship with a caveat" exit.

A claim that surfaces here without one goes back through that routing before the draft advances; a claim with no path to evidence at all is omitted and its gap named in the answer's "Open questions" section.

### Step 2: Fresh verifier agent

Spawn a fresh verifier agent to verify the draft answer. This agent must NOT have seen the research prompts — it reviews with fresh eyes; it spawns as `general-purpose` directly, per §Subagent spawn contract (OMIT `model=`). Full spawn template (acceptance criteria, pre-inlined-files convention, 6-item verification checklist, output schema) in `${CLAUDE_PLUGIN_ROOT}/skills/investigate/investigate-taxonomy-reference.md` §4.

#### Process review results:
- **Blockers**: Fix the answer (orchestrator corrects directly — these are text edits, not code).
- **Warnings**: Add missing context or caveats to the answer.
- **Nits**: Apply if they improve clarity.
- **Verified**: Proceed to Step 3.

If blockers are found, fix and re-verify with another fresh agent. **Max 1 re-review round** — track the count in your own scratchpad; at the limit, present what you have to the user with the remaining blockers flagged, and stop.

### Step 3: Present + Sources + Open questions

Present the synthesized, reviewed answer to the user. Include:
- The structured answer from Step 1 (post-review fixes applied).
- A "Sources" section listing key files examined and agents used — every cited artifact (file:line, command output, query result, user-provided data) is listed.
- An "Open questions" section listing any sub-questions that could not be evidence-backed AND were not resolvable via the missing-data gate. Be explicit about what data would settle each one.

### Step 4: Save-routing AUQ

Use the `AskUserQuestion` tool (do NOT output options as plain text) with header "Follow-up" and question "Want to dig deeper?" with options:
- "Dive deeper into [specific aspect]" — re-enter Phase 2 with narrower scope, reusing the prior findings as context; **max 2 dive-deeper rounds** (persist the count to state.md frontmatter `dive_round:` via `atomic_state_write`, so a compaction-resume mid-dive doesn't silently reset it). At limit, suggest fresh `/geniro:investigate` with refined question.
- "I have a follow-up question" — start a new investigation.
- "Save key findings to memory" — persist important discoveries (see Step 4a for routing — CLAUDE.md Domain Context, ADR, learnings.jsonl, or collaboration memory).
- "Done — answer is sufficient" — print a short `### Next steps` closing block: plain text, no further question, suggesting a follow-up command ONLY where the investigation's outcome makes it genuinely applicable — `/geniro:debug <symptom>` if the answer surfaced a bug, `/geniro:plan <feature>` if it motivates a feature or larger change, `/geniro:implement <task>` if a small direct code change is the clear next move; when nothing applies, close with a single line stating the investigation is complete. Then run Step 5 (learning emit, when its trigger applies) and Step 6 (cleanup), writing `present-summary-only` as the terminal value — ending here without them leaks the state directory and drops the learning.

### Step 4a: Save-routing (when user picks "Save key findings to memory")

Before writing to a single store, classify each finding to its proper destination per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` — never default everything to learnings.jsonl — then surface them one at a time per the per-finding walk below. Check each target store for an existing entry covering the topic first: UPDATE it rather than adding a duplicate.

Every save-routing Agent spawn below follows §Subagent spawn contract (they spawn as `general-purpose` directly).

Anything routed to Claude Code's native memory — by route 3's auto-memory path or route 4 — carries its qualifier in the text: that store has no `trust` field, so a root cause with no captured artifact behind it is written as suspected, naming what would confirm it. Memory outlives the session, and a confidently-worded wrong diagnosis misdirects every later session that recalls it.

1. **Domain-vocabulary findings** — the investigation surfaced a new domain entity, role, or business-rule term that wasn't in CLAUDE.md's Domain Context. Examples: "the codebase calls X a `Tenant` but production calls it a `Workspace`" / "there's a hidden `BillingAccount` entity that wraps `Subscription`+`PaymentMethod`+`Invoice`."
- Route: **CLAUDE.md** "Domain Context" section.
- Method: surface each term via the per-finding walk below — **What I'd save** is the proposed 1-3 line term-block, **Where** is CLAUDE.md's Domain Context, **Why** is the vocabulary gap it closes; the lean question's "Save elsewhere" pick routes the term to a learning instead, and "Skip this finding" drops a term that is not durable enough.
- On approval: investigate's `allowed-tools` does NOT include Write/Edit (research-only by design). Spawn a focused Agent (no `subagent_type`; per §Subagent spawn contract) with the proposed term-block pre-inlined (field 3) and the instruction: "Read CLAUDE.md, locate the `## Domain Context` section (create one before the first `##`-level section if missing — confirm via the orchestrator's prior AskUserQuestion answer pre-inlined here), append the proposed term-block at the section's end, do not modify other sections. Report the resulting diff." Pin task scope (field 1), acceptance criteria (field 2: "Domain Context section contains the proposed term-block; no other sections modified"), allowed mutation surface (field 4: only CLAUDE.md), output schema (field 5: returned diff), and model tier (field 6: inherit). This preserves investigate's research-only identity while enabling the auto-extract; the agent does the file write.
2. **Architectural decisions meeting all 3 ADR criteria** (hard to reverse + surprising + genuine trade-offs) — route to **ADR** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` § ADR target. Draft the ADR using the template; write into the existing `docs/adr/` or `docs/decisions/` directory (whichever the project uses), and ask the user before creating `docs/adr/` if neither exists. Spawn a focused Agent (per the spawn contract above) with the drafted ADR content + resolved target path pre-inlined; agent writes to `<adr-dir>/NNNN-<slug>.md`.
3. **Reusable technical insights** (gotchas, lightweight architectural decisions, surprising coupling) — store this learning per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §"Caller contract" (the same routing Step 5 uses): under a `## Memory Backend` block the store routes per its mode — `replace` writes the backend only (redacted first), `mirror` writes both the backend and the local file; absent block → append to **`<PRIMARY_ROOT>/.geniro/knowledge/learnings.jsonl`** via `${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh` (resolve path prefix via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A so writes land in the main worktree). Bias hard toward flow, architectural, and recurring-mistake learnings; do NOT save narrow interface/field shapes, single-file behaviors, or facts re-derivable by reading the code. Apply the Reflect → Abstract → Generalize pre-pass before every save: if you cannot restate the finding one level up, drop it. The file-append path uses a focused spawned Agent (per the spawn contract above) since investigate has no Write tool; the backend-write path is the orchestrator's own routed store (or use the auto-memory path if the entry maps to project-memory shape).
4. **User preferences about how to collaborate** — route to Claude Code's native memory feature. It needs no file write, so this path doesn't require the agent-spawn workaround.

**Surface the to-save findings one at a time** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering and the visual language in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` — the same one-by-one walk `improvement-routing.md` §Presentation uses. For each finding, render a self-contained message:
- **What I'd save** — the exact content that will be written (term-block / ADR title + one-line decision / learning sentence), shown as it will land.
- **Where** — the routed store in plain English (Domain Context in CLAUDE.md / an ADR under `docs/adr/` / past learnings / collaboration memory).
- **Why** — why it is durable enough and why that store.

Then fire its own lean `AskUserQuestion` (header `Save N of M`), options "Save to <store>" (Recommended when durable, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Recommended-label policy) / "Save elsewhere" / "Skip this finding" / "Skip the rest". A finding load-bearing in two stores names both in **Where** and adds a "Save to both <X> and <Y>" option; past the 4-option cap, chain per §Cap-extension. Never batch all findings into one save action.

### Step 5: Record the answer as a learning (with trust label)

Emit a minimal-scope `discovery` entry, then echo `Recorded learning: <summary>` to the user per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §"Caller contract":

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh"
emit_learning <<'EOF'
{
"producer": "/geniro:investigate",
"type": "discovery",
"tags": ["investigate", "<question-derived-tags>"],
"scope": "global",
"trust": "<verified|retrieved>",
"summary": "<one-line answer summary>",
"ext": {
"area": "<top-level area>",
"insight": "<2-3 sentence finding with file:line or URL citation>"
}
}
EOF
```

**Trust label:**
- `trust: verified` — investigation was code-grounded only (no WebFetch/WebSearch agents spawned, OR WebFetch results were not load-bearing to the final answer).
- `trust: retrieved` — WebFetch/WebSearch findings were load-bearing to the final answer.
- `trust: inferred` — N/A for /geniro:investigate (model-deduced claims do not pass Evidence Standard's confidence-driven action).

Default trust: `retrieved` if WebFetch/WebSearch was load-bearing; `verified` if code-grounded only. No `<untrusted_external_data>` envelope wrapping — trust-label propagation IS sufficient for baseline awareness.

**Trigger:** emit when the investigation produced a substantive structured answer (not a quick reference lookup). Heuristic: ≥2 agents spawned OR question type is one of How / Why / What-if / Compare / Risk. Skip for "quick lookup" classifications (Current-code trace / Commit archaeology / External docs lookup).

### Step 6: Cleanup

Every terminal exit runs this — `done` after save-routing, `present-summary-only` after a "Done — answer is sufficient" pick, `routed` from the Phase 1 Step 1.5 external-lookup exit, `aborted` from either escalation state. The `/geniro:update` migration walk scans only `.geniro/planning`, so a terminal that skips this leaks the run's scratch directory with nothing to sweep it later. Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Cleanup contract:

```bash
rm -rf .geniro/state/investigate/<slug>/ 2>/dev/null || true
```

No handoff file to delete. Chat answer is the deliverable. Persistent artifacts from save-routing (CLAUDE.md, ADRs, learnings.jsonl) STAY.

---

## State file schema

T1.5 state.md path `.geniro/state/investigate/<slug>/state.md` (cwd-relative — within-skill resume-from-compaction state per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` § "Artifacts NOT in scope"; slug per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md`). Write via `atomic_state_write`; validate on resume via `validate_state_file`. `approvals[]` category `glossary_resolve` populated when Phase 1 Step 2.5 fires. Full frontmatter + body sections (Scope / Classification / JIT Cadence / Agent Findings / Verified Claims / Draft Answer / Verifier Findings / Final Answer / Tool log / Errors / Open Questions / Termination reason / Persisted approvals) in `${CLAUDE_PLUGIN_ROOT}/skills/investigate/investigate-taxonomy-reference.md` §2.

---

## Examples

### Example 1: understanding a feature
```
/geniro:investigate how does the authentication flow work?
```
→ Codebase agent traces auth middleware, token validation, session management
→ Git agent finds when auth was added and major changes
→ Synthesize into execution flow with file:line references
→ Self-review verifies all references are accurate
→ Present: flow diagram + key files + edge cases

Additional worked examples (Design rationale, Impact analysis, Forward-looking integration) live in `${CLAUDE_PLUGIN_ROOT}/skills/investigate/investigate-taxonomy-reference.md` §6.
