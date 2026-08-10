# Definition of done — `/analyze-thread`

The run-completion checklist of `.claude/skills/analyze-thread/SKILL.md`. Read at entry to Phase 4 (the terminal phase), before findings are presented and the handoff written — `phase-3-4-filter-present.md` is already re-read at Phase 4 entry, so this file travels with it.

These are the load-bearing exit gates — the checks that, if skipped, ship a wrong result. Per-phase mechanics live in their phase sections; this list is the final correctness check, not a re-listing of every step.

- [ ] The thread set resolved from `$ARGUMENTS` with no question asked, excluded this session's own log by id, and named every clamped or skipped thread to the user
- [ ] The expectation set was built from each thread's own trace, never from this checkout, and any degradation was stated and carried into the confidence of every finding that rests on it
- [ ] Every coverage check ran against a declared side or did not run at all — no "missing" row rests on an expectation the trace never established
- [ ] Phase 2 LLM-judge ran per invariant #3 with that thread's expectation set in its seed, and a judge that returned nothing usable is reported as a mechanical-only thread, never as a full judged pass
- [ ] Phase 3 cross-thread merge ran before triage: recurring defects collapsed to one finding with `threads: [...]`, recurrence raising confidence but never severity
- [ ] The coverage scoreboard rendered for every thread whose expectation set was non-empty, each gap citing the finding that carries its evidence
- [ ] Every UNCERTAIN finding got its own AUQ, fired sequentially rather than batched into one multiSelect
- [ ] Handoff written via `atomic_state_write` when the user chose to emit, with one `open_questions[]` entry per kept finding
- [ ] State file cleaned up per the helper § Cleanup contract
- [ ] No mutations to the analyzed thread file or any project file outside `.geniro/state/`
