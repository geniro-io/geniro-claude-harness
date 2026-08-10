# Why this task is negative

Every documented command exists (`make test`, `make lint`, `make migrate` are
all Makefile targets), every cited path resolves (`db/migrations/`, `src/api/`,
`src/evaluator.go`), and no surface contradicts another.

The task also plants six endorsed patterns a reviewer must NOT flag. Each is on
the do-not-flag list, and flagging one is this audit's own false-positive
failure mode:

1. **Generated cross-tool mirror.** AGENTS.md is byte-identical to CLAUDE.md
   below its generated-by header, and `scripts/gen-agents.sh` is the mechanism.
   Mirroring is the endorsed way to serve many tools from one source; only drift
   between the copies is a finding, and there is none.
2. **A short CLAUDE.md.** Brevity is signal density, not a coverage gap.
3. **A single-homed justified threshold.** The 30-second cache TTL is stated
   once with its reason. Only restated or contradicting values are findings.
4. **A rich trigger-keyword skill description.** The release-notes SKILL.md
   description is keyword-dense because the description is the routing surface
   the tool selects skills by.
5. **A reason attached to a rule an agent would rationalize around.** The
   lowercase-key rule and the forward-only migration rule each carry why —
   payload that keeps the constraint alive at an edge case, not provenance.
6. **A scoped surface carrying rules the always-on one lacks.** The Cursor rule
   states handler-local constraints and repeats nothing from the repo-wide
   surface. That division is the structure working, not a coverage gap in
   either file.

## Two traps this fixture used to plant, and why they were wrong

A negative control is only a control if a *correct* reviewer scores zero on it.
Two of the original six were not endorsed patterns at all — they were real
defects, and the champion flagged both in 4 of 4 trials across two arms, which
is what exposed them. Both are repaired above rather than re-declared.

- **The Cursor rule opened by narrating its own loading model** — "Cursor
  attaches this rule whenever a handler file is in context, so it states only
  what a handler edit needs". An agent reading that rule is already inside a
  handler edit; being told when the rule attaches changes nothing it does, and
  the rest is a statement of authoring policy addressed to a maintainer. That
  is D4 check 9 — the case for the rule, shipped with the rule.
- **The release-notes SKILL.md body restated its own description**, and drifted
  from it while doing so: the description said `merged PR titles`, the body said
  `merge commits`. Trap 4 endorses keyword density in the *description*, which
  is the routing surface. It never endorsed a body that repeats it.

The general lesson, and it applies to every fixture here: planting endorsed
patterns is not the same as verifying the rest of the tree is defect-free. The
`no unplanted defect` sweep in `tests/evals/audit-modules.sh` checks cited paths
only — content of this kind is not mechanically detectable, so a reproducible
finding on a negative control indicts the fixture until read and ruled out.
