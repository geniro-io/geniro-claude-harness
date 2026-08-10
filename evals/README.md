# evals/ — the geniro eval pipeline

One mechanism lives here: **[`loop/`](loop/)** — the module-agnostic improvement
loop for plugin content (review criteria, the spec-claim check, and the
instruction- and plugin-audit rubrics today; plan/implement/debug next).
Design and rationale: [`loop/DESIGN.md`](loop/DESIGN.md); quickstart:
[`loop/README.md`](loop/README.md); driven interactively by the repo-local
`/eval-loop` skill.

Shared statistics live in [`lib/eval-stats.sh`](lib/eval-stats.sh) (Wilson +
task-clustered seeded bootstrap, single-sourced jq defs; unit-tested by
`tests/evals/eval-stats.sh`).

Predecessors — the Agent-SDK full-skill run-harness (Phases 0–C) and the
`cursor-review/` v1 content stand with its H1–H6 experiment ledger — were
deleted 2026-08-09 in favor of `loop/` (one mechanism, not two); git history
holds them. The criteria charter trim those experiments justified ships in
`skills/_shared/review-criteria/`.
