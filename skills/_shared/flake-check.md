# Flake check — 3-run determinism

Canonical procedure for confirming a kept RED test's failure is a real, deterministic signal rather than flakiness, before it counts as a finding. Consumers: `/geniro:implement` Phase 3 edge-case test authoring, `/geniro:debug` Adversarial Mode.

## Procedure

Once a round's kept RED tests are demonstrated, run them together in one filtered test-command invocation, repeated 3 times total, each run captured separately. A kept test's error signature must match across all 3 rounds; one that diverges is `inconclusive` — discard and delete it. A test observed red only once is not yet a finding — flaky failures train the next reader to re-run until green and mask a real regression once it starts failing for a new reason.
