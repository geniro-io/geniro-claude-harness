# AUQ-rejection L2 emit helper

**Status:** Authoritative for converting AUQ rejection-signal picks into cross-session L2 entries. Called by skills that surface choice AUQs where the user can explicitly reject a suggestion (e.g., approach selection, ship-mode confirmation).

## Relationship to `approvals[]`

| Layer | Purpose | Lifetime |
|---|---|---|
| T1 `approvals[]` frontmatter | Task-scoped record of every AUQ resolution; survives compaction but deleted on Ship | One task |
| L2 `user_rejected_suggestion` (via this helper) | Cross-session pattern signal — "user typically rejects X" | Forever (or until pruned) |

The two layers complement: `approvals[]` stays the authoritative within-task record; L2 captures **only** rejection-signal subset for future-session pattern matching. Acceptance (picked == recommended, no explicit-no signal) is not recorded to L2 — no rejection signal to learn from.

## API

```bash
source lib/emit-rejection.sh

emit_rejection_if_signal \
    <producer> <scope> <auq_category> <suggestion> <picked> [recommended]
```

**Args:**
- `<producer>` — emitting skill ID (e.g., `/geniro:plan`)
- `<scope>` — file/module/topic context (or `global`)
- `<auq_category>` — approvals[] category (e.g., `approach_choice`, `ship_mode`, `improvement_candidate`)
- `<suggestion>` — what the user was offered (one line)
- `<picked>` — what the user picked (label of selected option)
- `[recommended]` — optional; the option marked `(Recommended)` if any

**Exit codes:**
- `0` — emitted to L2, or no-op (no rejection signal detected; the normal acceptance path)
- `64` — missing required arg
- `1` — emit-learning helper error

## Caller contract — the helper reports its own outcome

Unlike `emit_learning`, this helper prints one line on the emit path: `Recorded a rejection pattern: <suggestion>`. It stays silent on the no-op path. So a caller passes the user's pick and surfaces whatever the helper printed — there is no rule to remember about when to echo, because the caller cannot know which path ran and the helper can.

**Surface a non-zero return.** `rc=64` (missing arg) and `rc=1` (emit-learning helper error) both mean the pick was never recorded; print one line naming the loss rather than swallowing the return code.

## Rejection signals

| Signal | Condition | Example |
|---|---|---|
| `explicit_cancel` | `picked` matches /cancel|abort/i | User picked "Cancel walk" |
| `explicit_no` | `picked` is exactly `no` / `no.` / `no,` / `no!`, OR starts with `don't` / `do not`, OR contains `reject` | User picked "No" |
| `explicit_skip` | `picked` matches /skip/i | User picked "Skip for now" |
| `picked_non_recommended` | `recommended` supplied AND `picked != recommended` | User picked Postgres when Redis was recommended |

If multiple match (e.g., picked = "Skip and cancel") the **first** keyword wins (cancel order).

## When skills should invoke

**Required:**

| Skill | AUQ site | Suggested args |
|---|---|---|
| /geniro:plan | Phase 4 approach selection AUQ | producer=/geniro:plan, scope=<topic>, auq_category=approach_choice, suggestion=<approach name>, picked=<user's choice>, recommended=<recommended approach if any> |
| /geniro:implement | Phase 3 ship-mode AUQ | producer=/geniro:implement, scope=<branch-or-topic>, auq_category=ship_mode, suggestion=<offered ship mode>, picked=<user's choice>, recommended=<recommended ship mode> |

**Optional:** any skill with an AUQ that has a clear "yes/no" or "recommended/alternative" semantic can invoke this helper. Skills with only-informational AUQs (e.g., section-by-section confirm) should not invoke — no rejection signal there.

## Read-side status

`rule_candidate` entries have a reader — `/geniro:reflect`'s prior-declines query, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` §Spawn slots. `approach_choice`, `ship_mode`, and `library_adoption` entries accumulate with no reader.

## Example flow

```
User: /geniro:plan implement session storage

/geniro:plan Phase 4 surfaces 3 approaches:
  - Redis (Recommended)
  - Postgres
  - In-memory with file-snapshot

User picks: Postgres

-> approvals[] writer appends:
   an `approvals[]` entry with `category: approach_choice`, `picked: Postgres`, `recommended: Redis`, ...

-> emit_rejection_if_signal /geniro:plan global approach_choice \
    "Redis" "Postgres" "Redis"
   -> signal = picked_non_recommended
   -> L2 entry:
     {type: user_rejected_suggestion,
      ext: {suggestion: "Redis", auq_category: approach_choice,
            rejection_signal: picked_non_recommended}}
```
