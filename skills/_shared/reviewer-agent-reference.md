# Reviewer agent — reference

Companion to `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md`. Detail the reviewer reads while scoring. Lives in `skills/_shared/`, not `agents/`, so nothing spawns it as a subagent.

## Confidence rubric

Canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §4 — the score bands and the four scoring adjustments that map evidence, systemic-ness, and nearby mitigations onto the number. Read that section before scoring your first finding; the percentage is an advisory hint, not the admission filter (`reviewer-agent.md` §Confidence Scoring explains why).
