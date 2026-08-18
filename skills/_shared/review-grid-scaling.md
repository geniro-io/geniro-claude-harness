# Reviewer dimension grid scaling by change size

Canonical scaling table for the always-fire reviewer-dimension set. `/geniro:implement` Phase 3 and `/geniro:review` Phase 2 each cite this table rather than restating it — but the two skills key off different size signals, so each gets its own column below rather than one shared tier vocabulary neither literally computes.

## The rule

Scale the always-fire dimension set by the run's own size signal. A conditional dimension — one with its own trigger, independent of size (`optimizations`, `design`, `pr-metadata`, `spec-compliance`, `custom:*` in `/geniro:review`) — is untouched by this table and keeps firing on its own trigger at every tier.

**`/geniro:implement`** reads a four-level `change_scope` estimate from the codebase-explorer-agent (Step 6, `${CLAUDE_PLUGIN_ROOT}/agents/codebase-explorer-agent.md` §Output Schema):

| `change_scope` | Dimensions fired |
|---|---|
| `trivial` | `bugs`, `tests` |
| `small` | `bugs`, `security`, `tests`, `code-quality` |
| `medium` / `big` | Full always-fire set — `bugs`, `security`, `architecture`, `tests`, `code-quality` |

**`/geniro:review`** has no four-level signal to key off. Its Phase 1 §12 size triage (`${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md`) is a single binary boundary — >8 files OR >400 LOC — plus a per-file Trivial/Substantive classification; neither tiers into four levels, and inventing a third tier for it guesses a level the run cannot compute, with a wrong guess silently dropping 4 of the 6 always-fire dimensions. Its column is two-level instead:

| Size signal (§12 boundary) | Dimensions fired |
|---|---|
| Under boundary (≤8 files AND ≤400 LOC) | `bugs`, `security`, `tests`, `conventions` |
| At or over boundary | Full always-fire set — `bugs`, `security`, `architecture`, `tests`, `conventions`, `regressions` |

**Risk overrides — both skills have one, from a different field each.** `risk-tier: high` forces `/geniro:review`'s full always-fire set regardless of its size signal — a small diff that trips a hard escalation signal (an auth/permissions change, a new external integration, a schema or migration, …) still gets full coverage, because size alone under-counts a high-stakes small diff; `phase-1-triage-reference.md` §9 computes this field from the 9 hard-escalation signals in `effort-scaling.md` §"Step 1: Check for hard escalation signals". `/geniro:implement` gets the equivalent override from a different field it already has: any matched signal in the codebase-explorer's `Risk flags` (Step 6, same Output Schema) forces its full always-fire set regardless of `change_scope`.

## Why narrowing here is legitimate

An orchestrator that trims a reviewer's coverage on its own mid-run judgment is the failure `/geniro:review`'s declared-vs-actual completeness gate exists to catch — that kind of trim is invisible until Phase 4 audits it after the fact. This table is a different shape: the narrowed set is decided from the size signal alone, before the spawn batch fires, announced to the user in the same spawn-echo line the batch always emits, and recorded in `spawn_dims_declared[]` — the same declaration each skill's own completeness gate re-reads. Coverage dropped by size is visible at the moment it drops, never assumed; a silent trim is one nobody could see coming, and this one is exactly the set the user was told about.

## Applying the table

1. Resolve the size signal from the consuming skill's own column above — `change_scope` for `/geniro:implement`, the §12 boundary for `/geniro:review`.
2. If the run's risk override fires (`risk-tier: high` for `/geniro:review`, any matched `Risk flags` signal for `/geniro:implement`), use the full always-fire set — skip step 3.
3. Otherwise, look up the skill's own column above for the dimension set.
4. Declare the resolved set in `spawn_dims_declared[]` and the spawn-echo line before firing.
