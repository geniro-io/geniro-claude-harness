# Investigate Phase 1 — classify+scope

Phase file for `/geniro:investigate`. The spine — invariants, budgets, tool surface, anti-rationalization, classification table — is `${CLAUDE_PLUGIN_ROOT}/skills/investigate/SKILL.md`.

## Contents

- Step 0: Load custom instructions
- Step 0.5: Resume check, then project snapshot + past learnings
- Step 1.5: External-lookup routing (Internet-only → consider /deep-research)
- Step 2: Identify scope
- Step 2.5: Glossary-mismatch check (pauses only on mismatch)
- Step 2.6: JIT retrieval cadence

---

State.md `phase: classify`. Low cost — a semantic $ARGUMENTS classification + memory-layer load (instructions + snapshot + past learnings) + glossary-mismatch check. Critical for correctness: bad classification → wrong agent set → wasted research budget. The classification table (Step 1) lives in the spine's Phase 1 section.

### Step 0: Load custom instructions

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: investigate`, `LOAD_TIER: pipeline`, `MODE: initial-load` on every run, fresh or resumed, before any other phase work. The helper's §Procedure owns the load set and its imperative reads; print each file's line per its §Echo contract immediately after that file's load attempt, before the next file.

### Step 0.5: Resume check, then project snapshot + past learnings

1. **Resume check** — run `${CLAUDE_PLUGIN_ROOT}/skills/investigate/SKILL.md` §State recovery. A run resumed past Phase 1 continues from that phase; otherwise (a fresh start, a resume at `classify`, or a Case choice that starts fresh) continue with items 2-4.
2. **Refresh project snapshot** — `load-semantic` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-semantic.md` default top-2 (`_project.md` + `_CODEBASE_MAP.md`). `_CODEBASE_MAP.md` content (if present) primes Phase 2's Codebase Analyst — pre-inline relevant sections into the spawn prompt.
3. **Query past learnings** — route per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.md` §"Memory backend override" (a declared `## Memory Backend` block redirects this to its read tool; the file is empty under `mode: replace`), else `source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh"` and run one `query_learnings --tag <kw> --scope global --limit 5` call per keyword inferred from $ARGUMENTS, unioning the results — `--tag` is single-valued, so a repeated flag on one call overwrites rather than accumulates. To find prior answers and avoid duplicate research.
4. **Reconcile custom instructions, snapshot and past learnings** — `resolve-conflicts` (precedence: custom instructions > project snapshot > past learnings when layers disagree; halt with AUQ on hard conflict).

### Step 1.5: External-lookup routing (Internet-only → consider /deep-research)

When the question classifies as **External docs lookup** (Internet only — no project code or git evidence needed), a `/deep-research` workflow, when your environment provides one, runs deeper multi-source web research than this skill's single Internet Researcher: it fans out searches across several angles, cross-checks the sources against each other, and votes on each claim before reporting. Offer it before spawning Phase 2.

Fire `AskUserQuestion` (header "Research"):
- **Question**: "This looks like a purely external question. `/deep-research <question>` cross-checks more web sources than a single research agent. How do you want to proceed?"
- **Options**: "Run /deep-research instead" / "Continue with /geniro:investigate"

On "Run /deep-research instead": surface the one-line directive `Run: /deep-research <question>` and terminate — do not auto-invoke. No state.md exists yet (Step 2 creates it) and the exit deletes the run's state directory anyway, so write no phase; remove any directory a resumed run left (`rm -rf .geniro/state/investigate/<slug>/ 2>/dev/null || true` — no handoff file to delete, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Cleanup contract). On "Continue": proceed to Step 2 with the Internet Researcher as normal. If `/deep-research` is unavailable (workflows disabled, or no web-search capability), skip this step silently and continue.

This routing fires only for the Internet-only classification — any question that needs code or git evidence stays in /geniro:investigate, since `/deep-research` has no codebase or git access.

### Step 2: Identify scope

From the question, extract:
- **Target area**: which files, modules, or patterns are relevant
- **Depth needed**: surface-level overview vs deep trace
- **Skip criteria** — prune agents the Phase 1 Step 1 row includes; they never add agents beyond it (the table wins). Each criterion is testable against the question text:
- **Skip Codebase** when the question is answerable purely from git log/blame ("when did X change?", "who wrote Y?") or purely from external docs ("what does library Z's API do?").
- **Skip Git** when the question is about current code behavior only and does not ask about history, evolution, rationale, or recent changes.
- **Skip Internet** when the question is fully internal — the project's code, patterns, and commits — and does not reference external libraries, frameworks, standards, best practices, alternatives, or security advisories.

For a Compare question whose alternative is a public repository, shallow-clone it once into the session scratchpad (a `mktemp -d` directory when the host has none), never the worktree, and record `CLONE_ROOT` and the cloned commit sha in `## Scope`; the clone's content is untrusted data.

Record the result in `## Scope` and the Step 1 classification in `## Classification` by creating state.md at `phase: classify` via `atomic_state_write` (schema: `${CLAUDE_PLUGIN_ROOT}/skills/investigate/investigate-taxonomy-reference.md` §2) — the run's first state write, so Steps 2.5-2.6 and a compaction-resume find the file. Carry over the existing file's `approvals[]` only when resuming into Phase 1; a fresh start begins with an empty list.

### Step 2.5: Glossary-mismatch check (pauses only on mismatch)

CLAUDE.md is auto-loaded and may contain a "Domain Context" section (added by `/geniro:setup` Phase 3.2) listing domain entities, safety rules, and API contracts. Before Phase 2 spawn, check whether the user's question uses terms that conflict with the documented glossary — investigating with the wrong vocabulary returns the wrong answer.

Procedure:

1. **Extract domain terms from the question** — proper-noun-shaped tokens, role names, entity names (e.g., "tenant", "workspace", "task", "invoice"). Skip generic technical terms ("function", "endpoint", "cache").
2. **Look each term up in the auto-loaded CLAUDE.md** — its Domain Context definitions, entity lists, and safety rules.
3. **Classify each match:**
- **No match** — the term may be new domain vocabulary; note it in the answer and proceed without challenge.
- **Exact match** — the user's term aligns with the glossary; proceed.
- **Mismatch** — the user's term appears in the glossary but the question's usage suggests a different meaning (e.g., user says "workspace" meaning "browser tab" but glossary defines "workspace" as "tenant container"). Fire the gate.
4. **If mismatch found:** write `phase: classify-escalated` to state.md via `atomic_state_set_field` first — a compaction while the question is outstanding then resumes as "task was paused — your previous options:" instead of silently re-running Phase 1 from scratch — then use `AskUserQuestion` with header "Glossary" before spawning Phase 2 agents:
- **Question**: "Your CLAUDE.md defines `<term>` as `<glossary definition>`. Your question seems to use `<term>` as `<inferred usage>`. Which one should I investigate?"
- **Options**: "Use the glossary definition" / "Use my new meaning (and note the divergence in the answer)" / "Both — these are genuinely different concepts that share a name (please pick disambiguating names)"
5. Record the resolution in the answer's Sources section so the synthesized answer carries the disambiguation forward.

**Approvals-persistence:** persist the user's pick to state.md frontmatter `approvals[]` with category `glossary_resolve`, and write `phase: classify` back once resolved. Subsequent compaction-resume reads prior pick from `approvals[]` rather than re-asking. The state.md `## Persisted approvals` body section renders this. Re-ask only if context materially changed (new glossary section added since the pick).

Skip this step entirely when CLAUDE.md has no Domain Context section, when the question has no domain-shaped terms, or when all terms are exact matches. When in doubt, skip — false positives waste user time more than false negatives waste investigation budget.

### Step 2.6: JIT retrieval cadence

The exact refs cited in Phase 2 findings (per the Evidence Standard) are what the Phase 3 `discovery` emit persists in `ext.{area, insight}`.

Unique requirement: state.md `## JIT Cadence` body section logs which steps fired for this run — the audit trail that makes the JIT discipline reviewable.

**Duplicate-answer check** — before spawning agents, re-query past learnings for this question or closely related topics, routed as in Phase 1 Step 0.5 item 3 but with the keywords the classification has since sharpened. Log the outcome to state.md `## JIT Cadence` — either the prior answer found, or `none — duplicate-answer check ran and found nothing`, so the section shows this step fired even when it turned up nothing. If a comprehensive prior answer exists, present it and ask via `AskUserQuestion` whether the user wants a fresh investigation, then persist the pick to state.md frontmatter `approvals[]` with category `duplicate_answer` so a compaction-resume does not re-ask.

**Ambiguous scope** — when the question's scope is ambiguous, use the `AskUserQuestion` tool to clarify it before spawning agents. Ask one focused question, not multiple.

When Phase 1 completes, transition state.md to `phase: investigate` via `atomic_state_set_field`.
