<!-- Generated from skills/plan/loop-phase-2-visual-companion.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Phase 2 — Visual Companion (UI-conditional)

The spine is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`; this file carries the Steps.

State.md `phase: visual-companion` during this phase. Fires only when a UI trigger matches.

### 2.1 Trigger detection

Fire Phase 2 if **either** condition holds:

- Phase 1 research surfaced any path matching a UI file — path matches `**/components/**`, `**/pages/**`, `**/app/**`, `**/views/**`, `**/ui/**`, OR extension is `.tsx` / `.jsx` / `.vue` / `.svelte` / `.css` / `.scss` / `.sass` / `.less` / `.styled.ts` / `.styled.tsx`, OR
- $ARGUMENTS topic string contains a UI noun: `page`, `screen`, `modal`, `form`, `dashboard`, `button`, `view`, `panel`, `widget`.

No trigger → skip Phase 2 entirely. Transition `phase: clarify` and proceed to Phase 3.

### 2.2 UI preview procedure

Trigger fires → run the procedure documented at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` end-to-end. That helper spawns the UI description agent, presents the textual preview, runs the revision loop, bounded per `ui-preview-gate.md`, and returns the approved description.

Caller contract (this skill's side):
- Provide the predicted affected-files list (from Phase 1 echo entries with UI-file matches), $ARGUMENTS topic, 1-2 exemplar UI files (path-only — agent reads them itself).
- Destination path: hold in-memory as Phase 5 substrate. Do NOT write a separate `ui-preview.md` artifact at the planning task-dir — the approved text feeds Phase 5 section 6 (Steps) + section 9 (Validation) directly.
- Preview form: pass `MOCKUP: true` when state.md has `artifact_mode: true` and the page is not recorded unavailable (`artifact_status` is not `unavailable`); otherwise omit it and the text description runs unchanged. A user who opted into the visual plan artifact already consented to publishing a page, so the mockup rides that opt-in — do not add a question for it. In mockup form, fire the before-gate artifact call for this site before the preview question, and again on each revision round (call-site table in `loop-artifact-call-sites.md`), so the user studies the mockup on the page while answering in the terminal.

### 2.3 Persistence — exit condition

Phase 2 does not transition away from `phase: visual-companion` until `## UI Preview` is written to state.md via `atomic_state_write`, in whichever form matches the exit actually taken:

- **Approved (→ Phase 3).**
```markdown
## UI Preview
<approved text verbatim — the description, or the mockup's digest in mockup form; length per ui-preview-gate.md's output constraint>
```
- **Routed out (§2.4, → Phase 1 re-entry).** The assessed sentinel per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/skip-visibility.md` §The assessed sentinel:
```markdown
## UI Preview
none — Phase 2 ran and the user routed to "adjust the plan instead"; re-entering Phase 1
```

Phase 5 section 6 / section 9 authoring cites the approved-text form as substrate. Phase 7 validator does not gate on `## UI Preview` presence at all — absence is only valid when the §2.1 trigger never fired; this exit condition is Phase 2's own to enforce. In mockup form the mockup lives on the plan page the run already tracks (`artifact_url`), so nothing about it is duplicated here; once the preview is approved, fire the update for this site (call-site table in `loop-artifact-call-sites.md`) so the page's decision panel clears.

### 2.4 Routing-out signal

If the user picks "Adjust the plan instead" at any revision round of ui-preview-gate.md: write the §2.3 routed-out sentinel, then return to Phase 1 with the user's feedback inlined into research-agent prompts. State.md transitions `phase: explore` (re-enter) — round-count not incremented since the user is correcting the plan substrate, not the UI preview itself.
