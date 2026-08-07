# /improve-template — create-skill mode

Mode body for `.claude/skills/improve-template/SKILL.md`. Read on entry to create-skill mode, at the point mode detection routes there — the default improve-existing-skill and process-handoff paths never take this branch and never read this file.

## Contents

- Phase A — Gather requirements (interactive)
- Phase B — Draft (one author-agent spawn, then validate)
- Phase C — Review (fresh agent)
- Phase D — Report & commit (reuse Phase 6)

---

## Create-skill mode (3-phase author flow)

When mode detection routes to create-skill, run this flow instead of the
Investigate → Filter → Implement pipeline.

### Phase A: Gather requirements (interactive)

1. **Determine target.** Ask via `AskUserQuestion` with header "Skill kind":
   - **Plugin-facing** (`/geniro:<name>`) — adds to `skills/<name>/SKILL.md` in the plugin
   - **Project-local** (`/<name>`) — adds to `.claude/skills/<name>/SKILL.md` in the user's project
   - **Plugin-internal helper** (no slash invocation) — `_shared/<name>.md` referenced by other skills

2. **Ground the recommendations.** Read `.claude/rules/skill-structure.md` and `.claude/rules/skill-prose.md` — the maintained authoring rules this skill will be judged against in Phase B and Phase C. WebFetch `https://docs.claude.com/en/docs/claude-code/skills` only when the new skill touches a Claude Code surface you are unsure of; a failed fetch is not a blocker.

3. **Interview the user** via 3-5 sequential `AskUserQuestion` calls (one question per AUQ — don't batch in this phase, the answers compound):
   - **Trigger**: "What should activate this skill? (1-3 phrases or contexts users would describe)" — collect to use in the description's "Use when" clause
   - **Anti-trigger**: "When should this skill explicitly NOT fire?" — collect to use in description's "Skip for" clause
   - **Inputs**: "What does the skill receive? ($ARGUMENTS shape, files, conversation context)"
   - **Outputs**: "What artifacts does it produce? (files written, commits made, comments posted, AskUserQuestion gates fired)"
   - **Tools needed**: "Which Claude Code tools does the skill need? (Read, Write, Edit, Bash, Grep, Glob, Agent, AskUserQuestion, WebSearch, WebFetch, TodoWrite, MCP servers)"
   - (Optional, if applicable) **Subagents**: "Does this skill spawn subagents? Which existing agent definitions, or new ones?"
   - (Optional, if applicable) **Workflow file integration**: "Should this skill read from `.geniro/workflow/*.md` (Linear, GitHub Issues, etc.)?"

4. **Pre-existing-instruction check.** Spawn a generic Agent (`subagent_type="general-purpose"`, `model=` omitted — inherits orchestrator tier) with a focused prompt: pre-inline (a) the proposed skill's purpose + trigger + outputs, (b) the existing skills inventory (`Glob skills/**/SKILL.md` summary as a list of `name | description-first-line` pairs), (c) the project-local skills inventory (`Glob .claude/skills/**/SKILL.md`). The agent's task: read each existing skill's full description (and the first 30 lines of any with significant trigger overlap), then return a structured table with columns `name | overlap-level (none|partial|significant) | overlap-rationale | recommendation (proceed | extend-existing | reject)`. The orchestrator decides KEEP (proceed to Phase B) or REJECT (route the user to the existing skill instead). Without this check, the codebase accumulates near-duplicate skills.

### Phase B: Draft (one author-agent spawn, then validate)

1. **Spawn an author agent** (general-purpose, `model=` omitted — inherits orchestrator tier) with:
   - The full Phase A interview transcript (pre-inlined)
   - The path target (`skills/<name>/SKILL.md` or `.claude/skills/<name>/SKILL.md`)
   - Constraints (pre-inlined): description rules from `phase-4-6-implement-review.md` §Description-format validator + reference depth ≤1 hop + edit-in-place principle, plus an instruction to read `.claude/rules/skill-structure.md` § File-size limits for the size rule
   - 1-2 exemplar SKILL.md files closest in shape to the proposed skill (e.g., for a small command-style skill, point at `skills/instructions/SKILL.md`; for a multi-phase pipeline, point at `skills/refactor/SKILL.md`)
   - Output instructions: "Write the SKILL.md file using the Write tool. Follow the structure of the exemplars. Description must follow `.claude/rules/skill-structure.md` §Frontmatter hygiene (length budget, third person, 'Use when' AND 'Skip for' clauses). Read `.claude/rules/skill-structure.md` § File-size limits and size the file by it; `skills/implement/implement-reference.md` is the canonical example of the SKILL-plus-reference split it asks for."

2. **Validate (Phase 4 Step 3 validation gate from improve-template's existing flow)** — including the description-format checks in `phase-4-6-implement-review.md` §Description-format validator.

### Phase C: Review (fresh agent)

Run the standard Phase 5 self-review with a fresh agent that did NOT see the author prompt. Review checklist for create-skill is:
- All Phase A interview answers reflected in the SKILL.md
- Description meets all 6 format rules (`phase-4-6-implement-review.md` §Description-format validator checks 1-6)
- No invented tools (every tool in `allowed-tools` actually exists in Claude Code's tool surface)
- No invented `CLAUDE_PLUGIN_ROOT`-rooted references (every cited path actually exists)
- Frontmatter valid (name, description, allowed-tools, model)
- Sections present follow the order in `.claude/rules/skill-structure.md` §Section ordering
- Front-loaded sections (role statement, phases overview, loop invariants, anti-rationalization) sit within that section's front-load budget

Process review results per the existing Phase 5 routing (Blockers → fresh fix agent, max 1 round).

### Phase D: Report & commit (reuse Phase 6)

Same Phase 6 as improve-existing-skill mode; Step 3 is a no-op.
