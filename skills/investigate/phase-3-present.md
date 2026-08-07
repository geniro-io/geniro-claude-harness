# Investigate Phase 3 — synthesize+review+present

Phase file for `/geniro:investigate`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/investigate/SKILL.md`.

## Contents

- Step 0: Refresh custom instructions
- Step 1: Synthesize draft
- Step 2: Fresh verifier agent
- Step 3: Present + Sources + Open questions
- Step 4: Ask what to save · Step 4a: Save-routing
- Step 5: Record the answer as a learning
- Step 6: Cleanup

---

State.md `phase: present`. Synthesizes verified findings, a fresh verifier agent re-checks, presents to user, offers save-routing AUQ, emits L2 `discovery` with trust label.

### Step 0: Refresh custom instructions

**Refresh custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: investigate`, `LOAD_TIER: pipeline`, `MODE: refresh`. Compaction since the previous load may have silently dropped the rules — re-Read all files and echo per the helper's contract. This phase's Step 4a save-routing writes into the user's tree (CLAUDE.md / ADR / learnings) after Phase 2's research-and-verify stretch, the longest context-consuming part of the run — the refresh runs before that write, not after.

### Step 1: Synthesize draft

After Phase 2 Step 2/3 complete (every load-bearing claim verified or routed):

#### Cross-reference

- Identify where agents agree — carry the convergent claims into Phase 2 Step 2 re-verification.
- Identify where agents disagree or have gaps — flag for Phase 2 Step 2 re-verification or the Phase 2 Step 3 missing-data gate.
- Single-source claims get no "lower confidence" label — they get the same Phase 2 Step 2 re-verification treatment as any other claim.

#### Draft the answer

Structure the answer based on question type. Five literal markdown templates (How / Why / What-if / Compare / Risk) — each with the expected sections (Overview / Execution Flow / Key Details for How; Decision / Evidence / Trade-offs for Why; Direct Impact / Ripple Effects / Risks / Recommendation for What-if; per-dimension comparison table for Compare; Risk Assessment table + Mitigations for Risk) — in `${CLAUDE_PLUGIN_ROOT}/skills/investigate/investigate-taxonomy-reference.md` §5. Copy the matching template and fill in evidence — follow its section shape so answers stay consistent and reviewable.

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

### Step 4: Ask what to save

Use the `AskUserQuestion` tool (do NOT output options as plain text) with header "Follow-up" and question "Want to dig deeper?" with options:
- "Dive deeper into [specific aspect]" — re-enter Phase 2 with narrower scope, reusing the prior findings as context; **max 2 dive-deeper rounds** (persist the count to state.md frontmatter `dive_round:` via `atomic_state_write`, so a compaction-resume mid-dive doesn't silently reset it). At limit, suggest fresh `/geniro:investigate` with refined question.
- "I have a follow-up question" — start a new investigation. Before that, run Step 5 (learning emit, when its trigger applies) and Step 6 (cleanup), writing `present-summary-only` as the terminal value — the answer already presented here is the same substantive output the "Done" pick emits a learning for, and skipping straight to a fresh invocation would leak this run's state directory and drop it.
- "Save key findings to memory" — persist important discoveries (see Step 4a for routing — CLAUDE.md Domain Context, ADR, learnings.jsonl, or collaboration memory). Step 4a's routing IS the answer for this pick; once it completes, continue to Step 5 and Step 6, writing `done` as the terminal value.
- "Done — answer is sufficient" — print a short `### Next steps` closing block: plain text, no further question, suggesting a follow-up command ONLY where the investigation's outcome makes it genuinely applicable — `/geniro:debug <symptom>` if the answer surfaced a bug, `/geniro:plan <feature>` if it motivates a feature or larger change, `/geniro:implement <task>` if a small direct code change is the clear next move; when nothing applies, close with a single line stating the investigation is complete. Then run Step 5 (learning emit, when its trigger applies) and Step 6 (cleanup), writing `present-summary-only` as the terminal value — ending here without them leaks the state directory and drops the learning.

### Step 4a: Save-routing (when user picks "Save key findings to memory")

Read `${CLAUDE_PLUGIN_ROOT}/skills/investigate/save-routing.md` now and follow it, echoing per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — the Step 4 pick is the parent consent, and per-finding consent exists only behind this Read, so skipping it turns N approvals into one blanket save with nothing recording the difference. It carries the four routing classes (CLAUDE.md Domain Context / ADR / past learnings / collaboration memory), the focused-agent recipe each one uses, and the one-finding-at-a-time approval walk all live there. The other three Step 4 picks never read it.

Never default every finding to learnings.jsonl, and never batch them into one save action: both are what the routing and the per-finding walk exist to prevent.

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

No `<untrusted_external_data>` envelope wrapping — trust-label propagation IS sufficient for baseline awareness.

**Trigger:** emit when the investigation produced a substantive structured answer (not a quick reference lookup). Heuristic: ≥2 agents spawned OR question type is one of How / Why / What-if / Compare / Risk. Skip for "quick lookup" classifications (Current-code trace / Commit archaeology / External docs lookup).

### Step 6: Cleanup

Every terminal exit runs this — `done` after save-routing, `present-summary-only` after a "Done — answer is sufficient" pick OR the "I have a follow-up question" pick, `routed` from the Phase 1 Step 1.5 external-lookup exit, `aborted` from either escalation state. The `/geniro:update` migration walk scans only `.geniro/planning`, so a terminal that skips this leaks the run's scratch directory with nothing to sweep it later. Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Cleanup contract:

```bash
rm -rf .geniro/state/investigate/<slug>/ 2>/dev/null || true
```

No handoff file to delete. Chat answer is the deliverable. Persistent artifacts from save-routing (CLAUDE.md, ADRs, learnings.jsonl) STAY.
