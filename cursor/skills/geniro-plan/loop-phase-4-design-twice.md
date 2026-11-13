<!-- Generated from skills/plan/loop-phase-4-design-twice.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Phase 4.1.5 — Design it twice (Big tier, interface shape)

Read from `loop-phase-4-approaches.md` §4.1.5 on a Big-tier run whose decision is an interface or module boundary.

Runs before the §4.1 approach list is finalised — numbered after §4.1 but feeding it. Spawn 3 `codebase-research-agent` generators in ONE assistant response, per the spine §Spawn contract (OMIT `model=`), each designing under a different constraint so the designs differ in kind rather than in detail: minimal surface (1-3 entry points), maximal flexibility (many callers, extension points), optimized for the most common caller (the default case trivial). Slots as in §4.2: `RESEARCH_QUESTION` is the boundary, the constraint, and the Phase 3 decisions it must honor; `DELIVERABLE_SHAPE` is the interface (signatures, invariants, error modes), a caller usage example, what it hides, and trade-offs; `PRE_INLINED_CONTEXT` carries the Phase 1 surface, the Phase 3 closing summary, and the run's canonical terms, plus this line in every brief: "The proposed design is exempt from the file:line citation requirement — it does not exist yet; only claims about existing code cite file:line"; `OUTPUT_PATH` is `<task-dir>/.research-design-<constraint-slug>.md`.

The designs feed §4.1: the distinct ones (or a hybrid) become the interface shape of the 2-3 approaches, ahead of the §4.2 critics, which stress-test them like any other approach. Append a `## Tool log` Echo entry per spawn; on a failed spawn log a `## Errors` entry and generate from the surviving designs, or your own when none returned.
