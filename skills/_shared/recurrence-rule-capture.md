# Recurrence → rule-capture offer

Canonical recurrence-driven rule-capture offer, shared by `/geniro:debug` (Phase 3 exit) and `/geniro:refactor` (Phase 3 emit). When a learning the skill just emitted has now recurred enough times to be a real pattern (not a one-off), this offers to turn it into a user-authored project rule — without ever auto-writing one.

Three caller slots parameterize the procedure:

| Slot | Meaning | /geniro:debug | /geniro:refactor |
|---|---|---|---|
| `{LEARNING_NOUN}` | the kind of learning being promoted | `diagnosis` | `pattern` |
| `{SCOPE_ROUTING}` | the per-skill starting-scope suggestion | style/convention → `code-style.md`; workflow/process → `debug.md`; architecture/global → `global.md`; otherwise the user picks | `discovery` pattern extracted → `code-style.md`; `discovery` architectural insight → `global.md`; `pitfall` refactor-specific footgun → `refactor.md`; otherwise the user picks |
| `{REJECTION_ARGS}` | the three `emit_rejection_if_signal` positional args | `"/geniro:debug" "debug/<scope>" "promote_diagnosis_to_rule"` | `"/geniro:refactor" "refactor/<scope>" "promote_pattern_to_rule"` |

---

## Procedure

The caller has just emitted its `{LEARNING_NOUN}` learning. `emit-learning` appends silently and echoes nothing, so the recurrence count is not available from the emit return — read it back first.

0. **Read back the recurrence count.** Re-query to read it, filtered to the just-written entry's `dedup_key`, and read `recurrence_count` off the matched entry — route the read per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.md` §"Memory backend override" (the declared backend read tool under a `## Memory Backend` block, else `source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh" && query_learnings --include-superseded`). Under `mode: replace` the file-based recurrence counter no-ops (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/memory-backend.md` §6), so a count is obtainable only if the backend tracks recurrence — when none is obtainable, treat it as below threshold and surface nothing (never fabricate a count). Gate everything below on the value — when `recurrence_count >= 3` (this exact `{LEARNING_NOUN}` has now been recorded three or more times — a real recurring pattern, not a one-off), run steps 1-4. Below the threshold, surface nothing — single or twice-seen entries do not warrant a rule.

1. **Dedupe check first.** Grep the existing project rules under `.geniro/instructions/` for the entry's keywords. If a rule already covers this pattern, skip the offer entirely — surface a one-line note that an existing rule already covers it and continue.

2. **Otherwise, ask.** Fire an `AskUserQuestion` (header "Capture as rule") — question: "This pattern has come up repeatedly — want to capture it as a project rule?" with the recurring entry summary and recurrence count in the description. Options (plain-English labels):
   - **Save as a project rule** — hand off to `/geniro:instructions create` so the user authors the rule there.
   - **Refine, then save as a rule** — same handoff; the user reshapes the wording before saving.
   - **Merge into an existing rule** — same handoff; the user folds it into a related rule.
   - **Don't save** — decline; nothing is written.

3. **On a save / refine / merge pick:** hand off to `/geniro:instructions create` — the user authors the rule there. Suggest a starting scope from `{SCOPE_ROUTING}`. Do NOT auto-write any instruction file — the user stays the source of truth for project rules.

4. **Log a decline.** After the AUQ resolves (any outcome), source `${CLAUDE_PLUGIN_ROOT}/lib/emit-rejection.sh` and invoke once; the helper no-ops unless the pick is an explicit decline ("Don't save" or cancel), so a future run does not re-offer a rule the user has already passed on. Pass no recommended arg — the three accept options ("Save as a project rule" / "Refine, then save as a rule" / "Merge into an existing rule") are not rejections:

```bash
emit_rejection_if_signal \
{REJECTION_ARGS} \
"Capture recurring {LEARNING_NOUN} as project rule" "<picked label>"
```
