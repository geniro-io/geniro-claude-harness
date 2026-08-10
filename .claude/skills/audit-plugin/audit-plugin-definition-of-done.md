# Definition of done — `/audit-plugin`

The run-completion checklist of `.claude/skills/audit-plugin/SKILL.md`. Read at entry to Phase 5 (the terminal phase), and walk it before the cleanup-and-commit step closes the run.

- [ ] Phase 1 battery ran; output captured in checkpoint
- [ ] Selected reviewers spawned in one response; outputs collected
- [ ] Every admitted finding re-verified by orchestrator Read (machine findings exempt); every kept T0/T1 carries a cold verifier verdict
- [ ] Subtraction sweep ran and is reported — what was examined and what was rejected — whether or not it yielded findings (the subtraction-sweep invariant)
- [ ] Report written to `design/scratch/plugin-audit-<date>.md` with health summary, tier tables, verdicts, filtered list, subtraction sweep
- [ ] Every finding rendered to chat (all tiers, low included) before the gate — no tier collapsed to a bare count
- [ ] Every approved finding assigned to exactly one fix agent, and every touched file to exactly one allowlist; unowned ones echoed (the finding-ownership invariant)
- [ ] Every mechanism-deletion proposal put to its own gate with its explanation rendered, none carried by a blanket approval, and the ones kept recorded as considered-and-kept (the no-blanket-deletion invariant)
- [ ] Action gate fired; fixes (if approved) applied, battery re-run green, findings re-checked, and every `§` citation into a changed file re-resolved
- [ ] Every fix to a hook, a `lib/` helper, or a test carries a test that fails without it
- [ ] Every behavioral instruction fix carries a measurement, or is reported as an unmeasured change
- [ ] Every finding survived the oracle test; every decidable class the round found either ships a hard check or is named in the report as one nobody built
- [ ] State cleaned up; commit offered
