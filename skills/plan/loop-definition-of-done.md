# Definition of Done — `/geniro:plan`

The run-completion checklist of the `/geniro:plan` loop (spine: `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`). Walk the full list at Phase 9, before the terminal `phase: done` write. An `aborted` write happens at one of the five cancel paths (`plan-loop.md` §Terminal states — §0.4, §3.1, §5.2, §7.3, §8.3) instead, none of which enter Phase 9 — at each of those, walk only §Abort-path subset below before the write.

Every item below is an exit gate — a condition checkable as done or not-done once the run ends. Per-phase mechanics live in each phase's own file; this is the final contract check, not a re-listing of the steps.

`/geniro:plan` run is complete when:

- [ ] A pre-existing state.md was pre-flighted with `validate_state_file` before its `phase:` was resumed from, and a failed validation opened the recovery question instead of resuming.
- [ ] state.md lives at `.geniro/planning/<slug>/state.md` and every write to it went through `atomic_state_write`.
- [ ] Every phase ran, with two exceptions that are decisions rather than omissions: Phase 2 when its UI trigger did not match, and the Phase 1 §1.5 Trivial skip of Phases 2 and 3.
- [ ] Every gate carrying rich content rendered it to chat as a separate, already-emitted message BEFORE its lean AUQ fired (Phase 3 grill questions, Phase 4 approaches, Phase 5 section approval, Phase 8 final approval). No question pointed at a render that does not exist.
- [ ] Every decision the user made is in `approvals[]` — grill answers and checkpoint picks, the approach pick, one entry per approved section, the final approval, and the launch-config choice. A compaction resume can rebuild the run from those entries alone.
- [ ] Phase 1 loaded the memory layers for the effort tier, and every research spawn left its Echo-contract entry in state.md `## Tool log`.
- [ ] spec.md lives at `.geniro/planning/<slug>/spec.md` carrying all three design-doc markers and the `geniro_schema_version` its own content earns (Phase 6 §6.1), with one `milestone-N.md` per slice when milestone-mode was picked. Phase 6 did not commit.
- [ ] The Phase 7 validator ran the full check set in `${CLAUDE_PLUGIN_ROOT}/skills/plan/validator-checks.md` and reported one `status` line per check (any unexecuted check marked `skip`); every hard-fail either cleared inside the auto-revision rounds (§7.3) or was explicitly accepted by the user.
- [ ] HARD-GATE released only on the Phase 8 "Approve" — no implementation action was taken before that answer.
- [ ] On Approve: spec.md `lifecycle:` flipped to `approved` and `git commit` fired with its `non-resumable-actions[]` entry — or the planning dir was git-ignored, in which case the skip is recorded as an `## Errors` line and the user was told in plain English that the plan is on disk uncommitted.
- [ ] The Phase 8.5 `decision` learning fired when its condition held — before the run was declared done, so it cannot be dropped as a trailer.
- [ ] Any user-authored `### After user-approve` steps loaded from `.geniro/instructions/plan.md` executed; silently skipped when none were loaded.
- [ ] Phase 9 printed the milestone-aware `/geniro:implement <path>` command.
- [ ] `clean_task_transients` ran against the planning task-dir before the terminal `phase:` write — on `done` and `aborted` alike — leaving `spec.md` / `state.md` / `plan-*.md` / `milestone-*.md` in place.
- [ ] Terminal state.md `phase: done`, or `aborted` carrying a `## Termination reason` body line.

## Abort-path subset

The full list above presumes phases an early cancel path never reaches — spec.md, the Phase 7 validator, the Phase 8 approve. At each of the five cancel paths (§0.4, §3.1, §5.2, §7.3, §8.3 in `plan-loop.md` §Terminal states), walk only the gates that hold regardless of how far the run got, before the `aborted` write:

- [ ] Every decision made so far is in `approvals[]`.
- [ ] `clean_task_transients` ran against the planning task-dir before this write.
- [ ] Terminal state.md `phase: aborted` carries a `## Termination reason` body line naming what cancelled the run.
