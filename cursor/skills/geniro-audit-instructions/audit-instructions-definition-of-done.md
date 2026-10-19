<!-- Generated from skills/audit-instructions/audit-instructions-definition-of-done.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Definition of done — `/geniro:audit-instructions`

Walk before the cleanup-and-commit step closes the run (Read at entry to Phase 5).

- [ ] Phase 1 battery ran; output captured in checkpoint
- [ ] Selected reviewers spawned in one response; outputs collected (`--quick` selects none)
- [ ] Every admitted finding re-verified by orchestrator Read (machine findings exempt); every kept T0/T1 carries a cold verifier verdict. `--quick` skips Phase 3: its findings are machine findings plus the secret and unsafe-directive candidates adjudicated by Read at Phase 1, none with a cold verdict
- [ ] No secret value reproduced in the report, the chat render, or any state file (invariant S1)
- [ ] Subtraction sweep ran and is reported — what was examined and what was rejected — whether or not it yielded findings (the subtraction-sweep invariant)
- [ ] Report written to `.geniro/state/audit-instructions/report-<date>.md` with health summary, tier tables, verdicts, filtered list, subtraction sweep
- [ ] Every finding rendered to chat (all tiers, low included) before the gate — no tier collapsed to a bare count
- [ ] Every approved finding assigned to exactly one fix agent, and every touched file to exactly one allowlist; unowned ones echoed (the finding-ownership invariant)
- [ ] Every whole-surface deletion proposal put to its own gate with its explanation rendered, none carried by a blanket approval; the ones kept recorded as considered-and-kept (the no-blanket-deletion invariant)
- [ ] Action gate fired; fixes (if approved) applied, battery re-run clean, findings re-checked
- [ ] Slug-scoped state cleaned up; commit offered for the fixed files only
