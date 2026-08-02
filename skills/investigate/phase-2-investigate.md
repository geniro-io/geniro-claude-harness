# Investigate Phase 2 — investigate+verify

Phase file for `/geniro:investigate`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/investigate/SKILL.md`.

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

If Step 2 left any load-bearing claim unverified AND only the user can supply the missing artifact, write `phase: investigate-escalated` to state.md via `atomic_state_write` — a compaction while the question is outstanding then resumes as "task was paused — your previous options:" instead of silently re-running Phase 2 — then PAUSE and use the `AskUserQuestion` tool (do NOT output options as plain text — use the tool's structured UI) BEFORE drafting the answer. Header: "Missing data". Phrase the question concretely; offer 2-4 specific options for what data the user can provide. Example: "Paste the failing request/response body" / "Paste the log line at the moment of the bug" / "I don't have it — proceed without"

If the user picks "I don't have it / skip", drop the corresponding claim — do NOT synthesize around it. If the user provides data, write `phase: investigate` back, treat the data as evidence kind (5) per the Evidence Standard, and re-enter Step 2 to re-verify the claim against the new artifact. Loop max twice; if still unverified, drop the claim and explicitly note the gap in the final answer.

State.md `## Open Questions` body section logs missing-data gate question + user pick. State.md transitions: `investigate` → `present` once all claims verified or routed.
