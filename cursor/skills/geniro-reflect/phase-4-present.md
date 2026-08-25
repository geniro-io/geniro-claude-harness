<!-- Generated from skills/reflect/phase-4-present.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Reflect — Phase 4: Present and route

Phase file for `/geniro:reflect`. The spine — role, phases overview, statelessness, invariants, anti-rationalization, budgets, tool surface — is `${CLAUDE_PLUGIN_ROOT}/skills/reflect/SKILL.md`.

---

## Phase 4: Present and route

**Refresh custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: reflect`, `LOAD_TIER: pipeline`, `MODE: refresh`. Compaction since the previous load may have silently dropped the rules — re-Read all files and echo per the helper's contract. Phases 2-3 ingest whole transcripts and pre-inlined extracts, exactly the kind of load that triggers a mid-run compaction; this phase writes rules and dedupes against the project's existing ones, so it needs them current.

A candidate carrying `Recurrence-eligible: yes` never enters the walk — its lesson has already been seen 3+ times, so hand it to `/geniro:instructions create`, which collects its own approval; walking it here would be the second prompt for the same rule (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` §"Recurrence-eligible candidates").

Walk the remaining candidates one at a time per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` §Presentation — render each candidate as a self-contained chat message first: the exact rule text in a fenced code block, where it lands, and the transcript evidence behind it as a quoted block — then fire its own lean `AskQuestion`, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering and the visual language in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md`. Options per candidate: **Write this rule** / **Skip this rule** / **Skip the rest**.

**On approval**, write before rendering the next candidate, routed per the improvement-routing §Routing table:

- **CLAUDE.md / `.claude/rules/<scope>.md` / ADR** — an ordinary file edit by the orchestrator; these are user-visible project files, and the approval you just collected is the authorization.
- **`.geniro/instructions/<skill>.md` / `code-style.md`** — hand off to the `/geniro:instructions create` patterns, or write via `atomic_state_write` (`source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"`); direct `Edit`/`Write` is hook-blocked there (invariant #5).
- **Project rules/hooks (CI, lint, project-local hooks)** — outside this skill's tool surface: name the exact change (which config, which check) in chat and let the user apply it in their own automation.
- **Memory (native auto-memory)** — no file write exists to route to; state the approved preference plainly in the chat response so Claude Code's own auto-memory captures it.
- **Learnings** — `${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §Caller contract; never a raw write to the append-only log.

**On decline** (Skip this rule / Skip the rest / explicit no), log it so future runs stop re-suggesting it:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/emit-rejection.sh"
emit_rejection_if_signal "/geniro:reflect" global rule_candidate "<candidate one-liner>" "<picked option>"
```

**Zero candidates passing the bar** is a valid, common outcome. Say so plainly in one sentence; do not pad the result. Whether the walk ran or not, close with the echo line `Reviewed for improvements: <N> candidate(s)` plus one line naming what was mined — the sessions analyzed, or this session when `--this-session` ran — so a zero is distinguishable from a dropped step.

## Definition of done

These are the load-bearing exit gates — the checks that, if skipped, break the read-only contract, write a rule the user never approved, or let a declined candidate re-surface forever.

- [ ] The running session entered evidence only because `--this-session` asked for it; on every other shape it was excluded by the final-user-turn identity check, not by file growth alone (Phase 1 step 4)
- [ ] Every approved candidate was written through the mechanism its target routes to — an ordinary file edit only for CLAUDE.md / `.claude/rules/` / an ADR, `atomic_state_write` or the emit helpers for every `.geniro/` path (invariant #5)
- [ ] Every decline was logged via `emit_rejection_if_signal`, so the same candidate stops re-surfacing
- [ ] Closing echo `Reviewed for improvements: <N> candidate(s)` fired — including at N=0, where it is the only signal the run completed rather than dropped a step
- [ ] No transcript modified, moved, or deleted; no write outside the approved rules and the rejection/learning emits
