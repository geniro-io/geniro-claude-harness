# Definition of done — `/geniro:audit-instructions`

The run-completion checklist of `${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/SKILL.md`. Read at entry to Phase 5 (the terminal phase), and walk it before the cleanup-and-commit step closes the run.

- [ ] Phase 1 battery ran; output captured in checkpoint
- [ ] Selected reviewers spawned in one response; outputs collected (a `--quick` run selects none)
- [ ] Every admitted finding re-verified by orchestrator Read (machine findings exempt); every kept T0/T1 carries a cold verifier verdict. A `--quick` run skips Phase 3: its findings are machine findings plus the secret and unsafe-directive candidates you adjudicated by Read at Phase 1, and none of them carries a cold verdict
- [ ] No secret value reproduced in the report, the chat render, or any state file (invariant S1)
- [ ] Subtraction sweep ran and is reported — what was examined and what was rejected — whether or not it yielded findings (the subtraction-sweep invariant)
- [ ] Report written to `.geniro/state/audit-instructions/report-<date>.md` with health summary, tier tables, verdicts, filtered list, subtraction sweep
- [ ] Every finding rendered to chat (all tiers, low included) before the gate — no tier collapsed to a bare count
- [ ] Every approved finding assigned to exactly one fix agent, and every touched file to exactly one allowlist; unowned ones echoed (the finding-ownership invariant)
- [ ] Every whole-surface deletion proposal put to its own gate with its explanation rendered, none carried by a blanket approval, and the ones kept recorded as considered-and-kept (the no-blanket-deletion invariant)
- [ ] Action gate fired; fixes (if approved) applied, battery re-run clean, findings re-checked
- [ ] Slug-scoped state cleaned up; commit offered for the fixed files only
