# Definition of done — `/analyze-thread`

The run-completion checklist of `.claude/skills/analyze-thread/SKILL.md`, Read at entry to Phase 4 before findings are presented and the handoff written. These are the load-bearing exit gates — the ones that, if skipped, ship a wrong result.

- [ ] The thread set resolved from `$ARGUMENTS` with no question asked, excluded this session's own log by id, and named every clamped or skipped thread to the user
- [ ] The expectation set was built from each thread's own trace, never from this checkout, and any degradation was stated and carried into the confidence of every finding that rests on it
- [ ] Every coverage check ran against a declared side or did not run at all — no "missing" row rests on an expectation the trace never established
- [ ] Phase 2 LLM-judge ran per the one-judge-per-thread invariant with that thread's expectation set in its seed, and a judge that returned nothing usable is reported as a mechanical-only thread, never as a full judged pass
- [ ] Phase 3 cross-thread merge ran before triage: recurring defects collapsed to one finding with `threads: [...]`, recurrence raising confidence but never severity
- [ ] The coverage scoreboard rendered for every thread whose expectation set was non-empty, each gap citing the finding that carries its evidence
- [ ] The cost table rendered for every JSONL thread carrying usage fields, each driver citing the finding that carries its evidence
- [ ] Every kept finding carries a `fix_kind`, and none with a loaded-and-still-violated rule at recurrence ≥ 2 is PROSE
- [ ] Every UNCERTAIN finding got its own AUQ, fired sequentially rather than batched into one multiSelect
- [ ] Handoff written via `atomic_state_write` when the user chose to emit, with one `open_questions[]` entry per kept finding, each carrying `fix_kind`
- [ ] State file cleaned up per the helper § Cleanup contract
- [ ] No mutations to the analyzed thread file or any project file outside `.geniro/state/`
