# /geniro:resolve — Phase 3 & Phase 4

Phase bodies for `${CLAUDE_PLUGIN_ROOT}/skills/resolve/SKILL.md`. Read on entry to Phase 3, and again on any resumption of Phase 3 or Phase 4, including after a compaction. The spine keeps the state machine, the loop invariants, the anti-rationalization table, and the Definition of done — this file carries the Steps.

## Contents

- PHASE 3: CLARIFY
- PHASE 4: EMIT

---

## PHASE 3: CLARIFY

State.md `phase: clarify`. For `needs-clarification` items only (skip the phase when none). Each ambiguous item is its own gate — render it, ask, collect the answer, then move to the next; never batch items into one `AskUserQuestion`, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md` § Single-finding gate ("One finding per call"; the `gate-render` hook hard-blocks a batched gate).

1. Render each ambiguous item as a **self-contained chat message** — the comment, the code it points at, why it is ambiguous, a visual (the code path or before/after it concerns, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md` § Finding-type visual map), and the options — in the shared visual language per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md`. The message is the rendering surface; the AUQ `preview` side-box is too small.
2. Fire ONE lean AskUserQuestion for that one item, then collect the answer before rendering the next — the option set is the item's interpretations plus an **"Explain further"** aid and a **"Challenge this comment"** aid; picking Challenge spawns a fresh `finding-verifier-agent` re-check of the comment, and a `refuted` result reclassifies the item to `wontfix` and drops its gate. Persist each pick to `approvals[]` (category `comment_clarification`) and write the resolved answer into the item's `open_questions[]` entry; a deferred item stays `status: unresolved` and travels to `/geniro:implement` for re-gating. Once the last ambiguous item is answered or deferred, write `phase: emit`. Full mechanics — the two aids' exact behavior, the >4-option cap-extension, the `related_comments` linkage: `resolve-reference.md` §2.5.

---

## PHASE 4: EMIT

State.md `phase: emit`.

**Step 0 — Refresh custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: resolve`, `LOAD_TIER: pipeline`, `MODE: refresh`. Compaction since the previous load may have silently dropped the rules — re-Read all files and echo per the helper's contract. This phase writes the comment-keyed spec + handoff after three phases of PR fetches, per-thread verification, and clarify gates — the longest context-consuming stretch of the run.

1. **Author the spec.** `atomic_state_write` the spec to `.geniro/state/resolve/<slug>/spec.md` — beside this run's `state.md`, in the retained slug dir (SKILL.md §Loop invariants #8) — in the standard spec schema (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md`) with `producer: resolve`, plus the `## Comment Resolution Map` body section (`resolve-reference.md` §3). The fix items become Steps (§6); each fix's acceptance check becomes a §9 `verify:` line; the Map links each row to its Step. Carry `workflow_refs[]` if the PR links a tracker ticket.
2. **Spec-challenge (advisory).** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md` with `MODE: plan`, `SPEC_PATH: .geniro/state/resolve/<slug>/spec.md`, `TASK_DIR: .geniro/state/resolve/<slug>/`, `EFFORT_TIER:` the Phase 1 tier, `DEEP: false`. Fail-open; `keep-with-modifications` hardens the spec before handoff, and `re-plan` sends the item whose claim it refuted back through the Step-5 demotion rules instead of shipping the spec around it.
3. **Write the handoff.** `atomic_state_write` to `.geniro/state/handoff/from-resolve-<branch>.md` (T2) with `spec_path:` (the Step-1 path — `/geniro:implement` walks this key first when resolving its spec source, and it is the only route to a spec that lives outside `.geniro/planning/`; without it the consumer reads the handoff alone and never sees the Steps or the §9 `verify:` lines) + `open_questions[]` (the ambiguous items) + `comment_resolutions[]` (the review-comment fix/wontfix/answer items — `resolve-reference.md` §4) + `pr-ref` / `pr-url` / `pr-head-sha`. CI items appear in the spec Steps but NOT in `comment_resolutions[]` (#5).
4. **Hand off.** Print the next command: `/geniro:implement .geniro/state/resolve/<slug>/spec.md`, and name the handoff file beside it so the consumer picks up `comment_resolutions[]` + `open_questions[]`. State that `/geniro:implement` applies the fixes and, at ship, posts the replies + resolves the threads (the user may also fix by hand — then they resolve the threads on GitHub themselves). Write `phase: done`.
