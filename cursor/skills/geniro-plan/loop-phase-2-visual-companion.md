<!-- Generated from skills/plan/loop-phase-2-visual-companion.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Phase 2 — Visual Companion (UI-conditional)

The spine is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`; this file carries the Steps.

State.md `phase: visual-companion` during this phase. Fires only when a UI trigger matches.

### 2.1 Trigger detection

Fire Phase 2 if **either** condition holds:

- Phase 1 research surfaced a UI file per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` §UI-file detection rule, OR
- $ARGUMENTS topic string contains a UI noun (`page`, `screen`, `modal`, `form`, `dashboard`, `button`, `view`, `panel`, `widget`) as a whole word, singular or plural, and the change builds or changes a screen in the project's own product UI, even before any UI file exists — not config for an ops or monitoring tool (Grafana JSON, Terraform, Helm values).

No trigger → skip Phase 2. Transition `phase: clarify` and proceed to Phase 3.

### 2.2 UI preview procedure

Trigger fires → run `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` end-to-end; it returns the approved description.

Caller contract (this skill's side):
- Provide the predicted affected-files list (from Phase 1 echo entries with UI-file matches), $ARGUMENTS topic, 1-2 exemplar UI files (path-only — agent reads them itself).
- Destination: no separate `ui-preview.md` at the task-dir — the approved text lands in state.md `## UI Preview` (§2.3) and feeds Phase 5 sections 6 (Steps) and 9 (Validation).
- Preview form: pass `MOCKUP: true` when state.md has `artifact_mode: true` and the page is not recorded unavailable (`artifact_status` is not `unavailable`); otherwise omit it and the text description runs unchanged. A user who opted into the visual plan artifact already consented to publishing a page, so the mockup rides that opt-in — do not add a question for it. In mockup form, fire the before-gate artifact call for this site before the preview question, and again on each revision round (call-site table in `loop-artifact-call-sites.md`), so the user studies the mockup on the page while answering in the terminal.

### 2.3 Persistence — exit condition

Phase 2 does not transition away from `phase: visual-companion` until `## UI Preview` is written to state.md via `atomic_state_append_section --create`, in whichever form matches the exit actually taken:

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

Phase 7 does not gate on `## UI Preview`, so this exit condition is Phase 2's own to enforce; absence is valid only when the §2.1 trigger never fired. In mockup form the mockup lives on the plan page the run already tracks (`artifact_url`), so nothing about it is duplicated here; once the preview is approved, fire the update for this site (call-site table in `loop-artifact-call-sites.md`) so the page's decision panel clears.

### 2.4 Routing-out signal

If the user picks "Adjust the plan instead" at any revision round of ui-preview-gate.md: write the §2.3 routed-out sentinel, then return to Phase 1 with the user's feedback inlined into research-agent prompts. State.md transitions `phase: explore` (re-enter); the revision round-count is not incremented, since the user is correcting the plan, not the preview.
