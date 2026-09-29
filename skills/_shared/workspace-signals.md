# Workspace signals — shared Step 0 detection

Canonical definitions for the workspace signals more than one skill collects before it decides where to run. `/geniro:implement` Step 0a, `/geniro:review` Phase 1 Step 0, and `/geniro:debug` Phase 0 Step 0.2 all open with this set; each then adds its own skill-specific signals, which stay in that skill's own reference file.

All three callers detect the same four the same way, and they must: implement and review hand work to each other, and debug hands work to implement too, so a divergent reading of "am I in a worktree" sends the receiving skill to a different checkout than the one its handoff assumes. Defining them more than once is how that divergence arrives.

## Contents

- The shared signals
- Why `PROTECTED_BRANCH` has no per-project override

## The shared signals

| Signal | How detected |
|---|---|
| `CURRENT_BRANCH` | `git branch --show-current` |
| `CURRENT_TOPLEVEL` | `git rev-parse --show-toplevel` |
| `IN_WORKTREE` | `CURRENT_TOPLEVEL` is registered in `git worktree list --porcelain` AND is NOT the porcelain `bare` row or the main worktree row. The porcelain registry is the source of truth; the `.claude/worktrees/<slug>/` path convention is a sanity check, NOT the primary signal. |
| `PROTECTED_BRANCH` | `CURRENT_BRANCH ∈ {main, master, develop, trunk}` |

## Why `PROTECTED_BRANCH` has no per-project override

The set is fixed. There is no `protected_branches` key and no reader for one — `.geniro/safety.json`'s `allow_patterns` only waives the force-add guard's bypass ID. A skill that offers to honor a per-project override is promising a configuration surface that does not exist, which is worse than silence: the user edits a file, nothing changes, and the failure is invisible.

No per-project setting adds a branch to the set. If a real override is ever wanted, it needs a key, a reader in every consuming skill, and a row here — not a parenthetical in one skill's table.
