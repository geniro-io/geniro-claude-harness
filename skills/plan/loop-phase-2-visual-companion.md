# Phase 2 — Visual Companion (UI-conditional)

A phase file of the `/geniro:plan` loop. The spine — HARD-GATE, gate presentation contract, echo contract, phase order, terminal states, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`.

State.md `phase: visual-companion` during this phase. Fires only when a UI trigger matches.

### 2.1 Trigger detection

Fire Phase 2 if **either** condition holds:

- Phase 1 research surfaced any path matching a UI file — path matches `**/components/**`, `**/pages/**`, `**/app/**`, `**/views/**`, `**/ui/**`, OR extension is `.tsx` / `.jsx` / `.vue` / `.svelte` / `.css` / `.scss` / `.sass` / `.less` / `.styled.ts` / `.styled.tsx`, OR
- $ARGUMENTS topic string contains a UI noun: `page`, `screen`, `modal`, `form`, `dashboard`, `button`, `view`, `panel`, `widget`.

No trigger → skip Phase 2 entirely. Transition `phase: clarify` and proceed to Phase 3.

### 2.2 UI preview procedure

Trigger fires → run the procedure documented at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` end-to-end. That helper spawns the UI description agent, presents the textual preview, runs the revision loop (max 3 rounds), and returns the approved description.

Caller contract (this skill's side):
- Provide the predicted affected-files list (from Phase 1 echo entries with UI-file matches), $ARGUMENTS topic, 1-2 exemplar UI files (path-only — agent reads them itself).
- Destination path: hold in-memory as Phase 5 substrate. Do NOT write a separate `ui-preview.md` artifact at the planning task-dir — the approved description feeds Phase 5 section 6 (Steps) + section 9 (Validation) directly.

### 2.3 Persistence

The approved description is appended to state.md `## UI Preview` body section via `atomic_state_write`:

```markdown
## UI Preview
<approved description verbatim, ≤200 lines per ui-preview-gate.md output constraint>
```

Phase 5 section 6 / section 9 authoring cites this block as substrate. Phase 7 validator does not gate on `## UI Preview` presence (Phase 2 is conditional; absence is valid).

### 2.4 Routing-out signal

If the user picks "Adjust the plan instead" at any revision round of ui-preview-gate.md, return to Phase 1 with the user's feedback inlined into research-agent prompts. State.md transitions `phase: explore` (re-enter) — round-count not incremented since the user is correcting the plan substrate, not the UI preview itself.
