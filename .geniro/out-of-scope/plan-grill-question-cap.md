# A fixed question cap on the plan grill

Stop the Phase 3 grill after a set number of questions, or make the cap configurable.

## Why this is out of scope

The cap was removed on purpose (commit 8e3c660f, "make Phase 3 a decision-tree grill (uncapped, checkpoint-gated)"). A cap cuts exploration short on a hard plan and is arbitrary on an easy one. The checkpoint (a branch resolves, 2 rounds since the last checkpoint, or the answers converge) hands the user the decision to stop: `skills/plan/loop-phase-3-grill.md`.

## Prior requests

- 2026-06-20: the old 5-question cap was removed deliberately.
- 2026-10-05: reconfirmed while comparing Pocock's `question-limits` rejection with Geniro's grill.
- 2026-11-13: reconfirmed in the Phase 3 grill rebuild on Pocock's grilling text (commit 5fb023cf).
