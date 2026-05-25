# AUQ-rejection L2 emit helper

**Status:** Authoritative for converting AUQ rejection-signal picks into cross-session L2 entries. Called by skills that surface choice AUQs where the user can explicitly reject a suggestion (e.g., approach selection, ship-mode confirmation, action risk-class gate).

## Relationship to `approvals[]`

| Layer | Purpose | Lifetime |
|---|---|---|
| T1 `approvals[]` frontmatter | Task-scoped record of every AUQ resolution; survives compaction but deleted on Ship | One task |
| L2 `user_rejected_suggestion` (via this helper) | Cross-session pattern signal — "user typically rejects X" | Forever (or until pruned) |

The two layers complement: `approvals[]` stays the authoritative within-task record; L2 captures **only** rejection-signal subset for future-session pattern matching. Acceptance (picked == recommended, no explicit-no signal) is NOT recorded to L2 — no rejection signal to learn from.

## API

```bash
source lib/emit-rejection.sh

emit_rejection_if_signal \
    <producer> <scope> <auq_category> <suggestion> <picked> [recommended]
```

**Args:**
- `<producer>` — emitting skill ID (e.g., `/geniro:plan`)
- `<scope>` — file/module/topic context (or `global`)
- `<auq_category>` — approvals[] category (e.g., `approach_choice`, `ship_mode_default`, `risk_class_high`)
- `<suggestion>` — what the user was offered (one line)
- `<picked>` — what the user picked (label of selected option)
- `[recommended]` — optional; the option marked `(Recommended)` if any

**Exit codes:**
- `0` — emitted to L2, or no-op (no rejection signal detected, normal acceptance path)
- `64` — missing required arg
- `1` — emit-learning helper error

## Rejection signals

| Signal | Condition | Example |
|---|---|---|
| `explicit_cancel` | `picked` matches /cancel|abort/i | User picked "Cancel walk" |
| `explicit_no` | `picked` matches /^no/i OR /reject/i OR /don't|do not/i | User picked "No — we don't want Redis" |
| `explicit_skip` | `picked` matches /skip/i | User picked "Skip for now" |
| `picked_non_recommended` | `recommended` supplied AND `picked != recommended` | User picked Postgres when Redis was recommended |

If multiple match (e.g., picked = "Skip and cancel") the **first** keyword wins (cancel order).

## When skills should invoke

**Required:**

| Skill | AUQ site | Suggested args |
|---|---|---|
| /geniro:plan | Phase 4 approach selection AUQ | producer=/geniro:plan, scope=<topic>, auq_category=approach_choice, suggestion=<approach name>, picked=<user's choice>, recommended=<recommended approach if any> |
| /geniro:implement | Phase 3 ship-mode AUQ | producer=/geniro:implement, scope=<branch-or-topic>, auq_category=ship_mode, suggestion=<offered ship mode>, picked=<user's choice>, recommended=<recommended ship mode> |
| /geniro:actions | run-mode risk-class confirm AUQ | producer=/geniro:actions, scope=actions/<slug>, auq_category=risk_class_<low\|medium\|high>, suggestion=Run <slug> action, picked=<user's choice>, recommended=Run |

**Optional:** any skill with an AUQ that has a clear "yes/no" or "recommended/alternative" semantic can invoke this helper. Skills with only-informational AUQs (e.g., section-by-section confirm) should NOT invoke — no rejection signal there.

## Read-side protocol

Skills that **read** these L2 entries (to surface "user previously rejected X" hints) should:

1. Call `query-learnings --type user_rejected_suggestion --tag auq-rejection [--tag <category>] --scope <current>` at Phase 1 of relevant skill.
2. Surface result count to user in pre-AUQ display:
   ```
   Info: User previously rejected <suggestion> in <scope> on <ts>.
   ```
3. Use surfaced info to re-rank or omit the rejected option from current AUQ — but do NOT silently skip the AUQ entirely. Pattern is informational, not gating.

Suggested read sites:
- /plan Phase 4 (before showing approach AUQ)
- /implement Phase 1 (during ship-mode prep)
- /actions run-mode (before risk-class confirm)

## Example flow

```
User: /geniro:plan implement session storage

/plan Phase 4 surfaces 3 approaches:
  - Redis (Recommended)
  - Postgres
  - In-memory with file-snapshot

User picks: Postgres

-> approvals[] writer appends:
   {category: approach_choice, picked: Postgres, recommended: Redis, ...}

-> emit_rejection_if_signal /geniro:plan global approach_choice \
    "Redis" "Postgres" "Redis"
   -> signal = picked_non_recommended
   -> L2 entry:
     {type: user_rejected_suggestion,
      ext: {suggestion: "Redis", auq_category: approach_choice,
            rejection_signal: picked_non_recommended}}

Two weeks later:
User: /geniro:plan implement caching layer

/plan Phase 1 query-learnings --type user_rejected_suggestion --scope global
-> surfaces: "User previously rejected Redis (approach_choice, 2 weeks ago)"

/plan Phase 4: Skip Redis from approach list, or surface with notice
  "(previously rejected by user)".
```

## Test coverage

`tests/memory/emit-rejection.sh` exercises:
- Explicit cancel/abort/no/reject/skip signals
- picked_non_recommended detection
- picked == recommended (no-op)
- Missing args rejection (rc=64)
- Payload field correctness (producer, scope, type, ext.*)
