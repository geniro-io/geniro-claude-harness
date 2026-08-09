# Adapter: Agent-SDK run-harness (promotion gate, not a sweep engine)

The full-skill pipeline at `evals/run-harness/` + `evals/run-suite.sh` stays the
final gate: after a candidate wins screen + confirmation here, the landed skill
change must pass one full-skill run (orchestration regression: gates fire,
handoff shape holds, nothing posts) before the champion is refreshed.

It is NOT wired as a per-call adapter on purpose: a full-skill run costs ~$2 and
~6 min, and most of that spend is orchestration that is invariant under content
changes — pure noise on the metrics this loop iterates on. Use it once per
promotion, via its own documented flow (`evals/README.md` §"End-to-end").
