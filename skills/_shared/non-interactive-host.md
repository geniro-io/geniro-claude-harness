# Non-interactive host — running a skill with no one to ask

Applies when a skill runs where no user can answer mid-run: a cloud or background agent, a scheduled or CI run, a batch evaluation. Under an interactive host nothing here applies.

**Detection is two signals, and both have to hold.** The host exposes no structured-question tool under any name, AND the run was launched with no human in the loop — a single launch prompt that expects one final report rather than a conversation. Resolve the question tool by name first (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md` §Tool substitutions): a tool you have not searched for is not a tool you lack, and several hosts name it something other than `AskUserQuestion`. Reaching this file because the question tool was hard to find is the expensive mistake — it converts every one of the user's decisions into yours.

## Contents

- The rule — a gate is deferred, never deleted
- Pre-answers — the sanctioned channels
- Tier 1 — setup gates take the most reversible option
- Tier 2 — safety gates halt and hand back
- The outward-facing floor
- Reporting what was not asked
- Anti-rationalization

## The rule — a gate is deferred, never deleted

A gate exists because the choice belongs to the user. Losing the ability to ask changes who is present, never who decides. So every gate this skill declares still fires; what changes is what firing means:

- **Tier 1 (setup)** — resolve to the most reversible option, record it as a deferred decision, and surface it in the run's final report.
- **Tier 2 (safety)** — stop the run and hand the question back. Never pick.

A run that reaches the end with no deferred-decision block and no pre-answers took every choice silently. That is the failure this file exists to prevent, and it looks like success from the inside.

## Pre-answers — the sanctioned channels

A choice the user made before the run started is answered, not deferred. Two channels carry one, and only these two:

- `launch_config:` in the spec's frontmatter (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md`) — the designed pre-answer surface for exactly this situation.
- The launch modifiers parsed from `$ARGUMENTS` (workspace / ship / `freshness:` / `--deep`), per the skill's own modifier table.

Record a pre-answered gate in `approvals[]` the way an interactive run would, noting its source. The doctrine boundary in `launch-config-schema.md` binds unchanged here: a pre-answer covers setup, and cannot pre-authorize a Tier 2 gate.

**A launch prompt is not a pre-answer.** "Implement CI-263 and ship it" authorizes the run; it does not select among the ship gate's options, because the user never saw them. Free-text intent read as blanket consent is how a draft-grade default becomes a ready-for-review PR nobody approved.

## Tier 1 — setup gates take the most reversible option

Setup gates choose between paths that differ in convenience, not in what they risk: the workspace choice, the depth chooser, the branch-freshness strategy, the ship mode, the tracker kickoff status. With no pre-answer, take the option the skill marks `(Recommended)` when one exists, and otherwise the option that is easiest to undo — the narrower scope, the reversible write, the branch you can delete.

Persist each to `approvals[]` with `source: non-interactive-default`, so a later interactive resume can tell a defaulted choice from one the user actually made.

## Tier 2 — safety gates halt and hand back

Tier 2 is every gate whose trigger is an event rather than a setup step — it fires because the run found something. Two families:

- **The Always-WAIT set** named in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md` §"Doctrine boundary — setup only, never safety": new-dependency adoption, runaway-scope escalation, an unresolved handoff `open_questions[]` entry, and a spec claim the fact-check refuted.
- **Anomaly gates** — the run detected a state it was not expecting and asks what to do: the working tree on a different branch than the run targeted, production files modified outside this run's set, files staged that the review never saw, a fix loop past its round cap, a test suite accepted red.

On either, stop. Leave the working tree as it stands, uncommitted; write the open question into the task's state file if one exists; end the run with a report naming the question, its options, and what answering it would take. Do not advance `phase:` past the gate, and do not substitute a default — an anomaly gate fires precisely because the run's own model of the situation is already known to be wrong, which is the worst possible moment to trust its judgment over the user's.

## The outward-facing floor

Independent of tier, a non-interactive run performs none of these without an explicit answer through a sanctioned channel: a ready-for-review PR, a merge, a force-push, a push to the default or a shared/protected branch, a posted PR or issue comment, a tracker status transition, or a dependency install.

Ship degrades to the most reversible form the skill defines. Commit, push a private feature branch that has no open PR, and open a **draft** PR is the ceiling; where even that is unauthorized, stop after the commit and say so.

**One carve-out.** A tracker transition the project's own workflow file declares for this exact event (`### On task start`, `### On task completion`) is authorized — the user wrote that rule, which is the standing answer. A transition the run improvises because it seems helpful is not.

## Reporting what was not asked

The run's final report — and the body of any PR it opens — carries a **Deferred decisions** block, one line per gate that could not be asked:

```
- Ship mode — took "Open draft PR"; alternatives were "Open PR (ready for review)" and "Just push (no PR)". No human answered.
```

State plainly, once, that the run was non-interactive and which decisions that displaced. A report that narrates only what was done reads as a fully approved change, and the PR outlives the session that made the calls.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "Nobody can answer, so the gate is moot — I'll use my judgment." | The gate marks a decision the user owns; absence changes who is in the room, not whose call it is. Judgment substituted here is invisible afterwards, because a skipped gate leaves no trace in the diff. |
| "The launch prompt said to ship it, so the ship gate is pre-answered." | Free-text intent authorizes the run, not a specific option inside it — the user never saw the options. Only `launch_config` and the launch modifiers pre-answer a gate. |
| "A draft PR is safe, so ready-for-review is barely different." | Draft is the reversible form: no reviewers paged, no approval clock, no signal that a human vouched for it. Ready-for-review asserts exactly that, on the user's behalf, without them. |
| "I'll take the defaults now and ask at the end." | A question asked after the irreversible action is a notification. Everything reversible may proceed; everything Tier 2 stops where it stands. |
| "Halting wastes the whole run." | A halted run keeps every commit-free edit it made and hands back one answerable question. A run that guessed past a Tier 2 gate hands back work the user has to audit before they can trust any of it — which costs more than the run saved. |
| "I'll write the deferred-decisions block only if something notable was defaulted." | The block is how the user learns which choices were made for them; filtering it by your own sense of notability is the same substitution the tiers exist to prevent. A run with nothing to report writes the block empty and says so. |
