# Investigate Phase 3 — synthesize+review+present

Phase file for `/geniro:investigate`; the spine is `${CLAUDE_PLUGIN_ROOT}/skills/investigate/SKILL.md`.

## Contents

- Step 0: Refresh custom instructions
- Step 1: Synthesize draft
- Step 2: Fresh verifier agent
- Step 3: Present + Sources + Open questions
- Step 4: Follow-up
- Step 5: Record the answer as a learning (with trust label)
- Step 6: Cleanup

---

State.md `phase: present`. Synthesizes verified findings, a fresh verifier agent re-checks, presents to user, emits L2 `discovery` with trust label.

### Step 0: Refresh custom instructions

**Refresh custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: investigate`, `LOAD_TIER: pipeline`, `MODE: refresh`. Compaction may have dropped the rules — re-Read all files and echo per the helper's contract.

### Step 1: Synthesize draft

After Phase 2 Step 2/3 complete (every load-bearing claim verified or routed):

#### Cross-reference

- Identify where agents agree — carry the convergent claims into the draft.
- Identify where agents disagree or have gaps — flag them in the draft for the Step 2 verifier, or for a Step 4 dive-deeper round.
- Single-source claims get no "lower confidence" label — Phase 2 Step 2 already re-verified them like any other claim.

#### Draft the answer

Copy the template for the question type (How / Why / What-if / Compare / Risk) from `${CLAUDE_PLUGIN_ROOT}/skills/investigate/investigate-taxonomy-reference.md` §4 and fill in the evidence, keeping its section shape.

### Step 2: Fresh verifier agent

Spawn a fresh verifier agent for the draft; it must NOT have seen the research prompts and spawns as `general-purpose` per §Subagent spawn contract (`model=` from `subagent-model:` when set, else omitted). Spawn template (acceptance criteria, pre-inlined files, 6-item checklist, output schema): `${CLAUDE_PLUGIN_ROOT}/skills/investigate/investigate-taxonomy-reference.md` §3.

#### Process review results:
- **Blockers**: Fix the answer (orchestrator corrects directly — these are text edits, not code).
- **Warnings**: Add missing context or caveats to the answer.
- **Nits**: Apply if they improve clarity.
- **Verified**: Proceed to Step 3.

If blockers are found, fix, then re-verify with another fresh agent that receives the full corrected draft (in the template's Draft answer slot) with the changed sections marked, plus the findings they answer. Scope its checks to the marked sections; the rest was verified in round 1. **Max 1 re-review round** — at the limit, present with the remaining blockers flagged.

### Step 3: Present + Sources + Open questions

Present the synthesized, reviewed answer, its prose in the plain layer of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Two explanation layers (cites and Sources carry the technical layer). Include:
- The structured answer from Step 1 (post-review fixes applied).
- "Sources": every cited artifact (file:line, command output, query result, user-provided data), plus agents used.
- "Open questions": sub-questions neither evidence-backed nor resolvable via the missing-data gate, each with the data that would settle it.

Save the same content, no frontmatter, to `$(_geniro_unit_dir <branch>)/investigate-<topic-slug>.md` (`<branch>`: state.md `branch:`; binding rules: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §Path roots), the answer piped through `redact_secrets` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/redact-secrets.md`) into `atomic_state_write_cmd`, with `${CLAUDE_PLUGIN_ROOT}/lib/unit-dir.sh` sourced in the same call — the answer can quote a secret and the file outlives the run. `<topic-slug>`: kebab-case from the question, ≤40 chars, as in `/geniro:plan`'s task slug. Then tell the user the saved path in one plain line.

### Step 4: Follow-up

Use the `AskUserQuestion` tool — a plain-text option list bypasses the approvals persistence the tool records (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions) — with header "Follow-up" and question "Want to dig deeper?" with options:
- "Dive deeper into [specific aspect]" — re-enter Phase 2 with narrower scope, reusing the prior findings as context; capped per SKILL.md §Quality-first budgets "Dive-deeper rounds" (persist the count to state.md frontmatter `dive_round:` via `atomic_state_set_field`, so a compaction-resume doesn't reset it). Each round re-runs Step 3's save over the same file with the updated answer. At limit, suggest fresh `/geniro:investigate` with refined question.
- "I have a follow-up question" — start a new investigation. Before that, run Step 5 (learning emit, when its trigger applies) and Step 6 (cleanup), writing `present-summary-only` as the terminal value — skipping straight to a fresh invocation would leak the state directory and drop the learning.
- "Done — answer is sufficient" — print a short `### Next steps` closing block: plain text, no further question, suggesting a follow-up command ONLY where the investigation's outcome makes it genuinely applicable — `/geniro:debug <symptom>` if the answer surfaced a bug, `/geniro:plan <feature>` if it motivates a feature or larger change, `/geniro:implement <task>` if a small direct code change is the clear next move; when nothing applies, close with a single line stating the investigation is complete. Then run Step 5 (learning emit, when its trigger applies) and Step 6 (cleanup), writing `done` as the terminal value — ending without them leaks the state directory and drops the learning.

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
- `trust: verified` — investigation was code-grounded only (no web-research agents spawned, OR web results were not load-bearing to the final answer); code the orchestrator re-read in a shallow clone of an external repository at its recorded commit sha counts as code-grounded.
- `trust: retrieved` — web-research findings were load-bearing to the final answer.
- `trust: inferred` — N/A for /geniro:investigate (model-deduced claims do not pass Evidence Standard's confidence-driven action).

**Trigger:** emit when the investigation produced a substantive structured answer (not a quick reference lookup). Heuristic: ≥2 agents spawned OR question type is one of How / Why / What-if / Compare / Risk. Skip for "quick lookup" classifications (Current-code trace / Commit archaeology / External docs lookup).

### Step 6: Cleanup

Every terminal exit runs this — `done` after "Done", `present-summary-only` after "I have a follow-up question"; a skipped cleanup leaks the scratch directory. Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Cleanup contract. Write the terminal `phase:` first, so a surviving state file reads as complete to SessionStart recovery. When state.md `## Scope` recorded a `CLONE_ROOT`, read it before the delete and remove that clone directory too.

```bash
STATE_DIR="$(source "${CLAUDE_PLUGIN_ROOT}/lib/unit-dir.sh" && _geniro_state_dir investigate)"; [ -n "$STATE_DIR" ] && rm -rf "$STATE_DIR/"
```

The saved answer stays; it and the Step 5 learning are the run's durable output.
