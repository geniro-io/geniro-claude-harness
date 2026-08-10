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
6. **Tool-specific framing of a scoped rule.** The Cursor rule opens by naming
   its own loading model ("attaches whenever a handler file is in context") and
   states only handler-local rules — it deliberately repeats nothing from the
   repo-wide surface. Framing written for one tool's loading model is not
   wrong-surface narration, and a scoped surface carrying rules the always-on
   one lacks is the structure working, not a gap.
