# Definition of Done — `/geniro:refactor`

The run-completion checklist of `/geniro:refactor` (spine: `${CLAUDE_PLUGIN_ROOT}/skills/refactor/SKILL.md`). Read at Phase 3 entry; walk it before the terminal `phase:` write.

These are the load-bearing exit gates and safety invariants — the checks that, if skipped, break the zero-behavior-change guarantee or the no-ship boundary. Per-phase mechanics (tier classification, smell detection, plan building) live in their phase sections; this is the final correctness/contract check, not a re-listing of every step.

- [ ] Tests green before AND after the run — baseline captured (Phase 1) and final regression run captured as an Evidence Block (Phase 2 §2.4); the zero-behavior-change guarantee held
- [ ] PRODUCT-DECISION findings escalated to `/geniro:implement` (always-WAIT), never fixed in-skill
- [ ] CRITICAL/HIGH non-PD findings → 1-round fix loop; past that → "Findings remain" AUQ
- [ ] Blocked-ratio cap exceeded (§Budgets) → stuck AUQ fired (user picks; never silent abort)
- [ ] L2 emit fired with `discovery` or `pitfall` type + required `ext.*` fields
- [ ] Custom post-verify steps executed — any `### After verify` subsection in the loaded `.geniro/instructions/refactor.md` ran, or none was loaded (Phase 3 §3.6)
- [ ] No `git commit` / `git push` / `gh pr create` — diff stays uncommitted (user or /geniro:implement ships)
- [ ] Cleanup completed
