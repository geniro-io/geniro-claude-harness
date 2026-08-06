# Phase-entry read (canonical, shared)

## Contents

- §Why this exists — what a skipped phase body actually costs
- §The rule — first action, then echo
- §Echo contract
- §When to re-read
- §Anti-rationalization

**Status:** Authoritative for entering a phase whose Steps live in a sibling file. Every skill whose SKILL.md is a spine plus per-phase files cites this contract at its phase-bodies pointer.

## Why this exists

A skill split into a spine plus phase files reaches the model as the spine alone. The phase file is a Read the run has to issue for itself, and "Read X on entry" is a natural-language directive the model routinely treats as already-satisfied — the same failure `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` §Why this exists documents for instruction loading.

The cost is not that the run works from a vaguer description of the phase. A phase file carries three things the spine deliberately does not:

- **The phase's gates** — the approval questions, the decision trees, the stop conditions. A spine names that a gate exists; the branch conditions that decide whether it fires live in the phase file.
- **The executable helper invocations** — the call sites with their resolved parameters (`SKILL_SLUG` / `LOAD_TIER` / `MODE`, spawn slots, state-write contracts). The spine mentions the helpers descriptively; the phase file is where they are actually invoked.
- **The step ordering** that makes a later step's precondition true.

So a skipped phase Read does not degrade the phase — it deletes the phase's gates while leaving the work. The run proceeds, produces output, and looks successful, because nothing downstream re-checks a gate that never fired. One skipped Phase-1 body has been observed removing a workspace-approval gate and the project-instruction load in the same run: the run created a branch and edited source without ever asking, and never loaded the project's rules, because both lived behind that one Read.

## The rule

**The phase-body Read comes before any step of the phase.** No inspection of the project and no spawn precedes it — not a `git status` probe, not a Glob, not an Agent call. The phase's steps begin in the turn after.

Two things are explicitly NOT displaced, because they are bookkeeping rather than phase work: the `phase:` stamp a skill writes to state.md on entry, and a `MODE: initial-load` memory load a skill prescribes as its own first action. Where those are ordered first, they stay first — this contract governs the order of the phase's *steps*, and the file it makes you Read is usually where those very loads are invoked.

Then echo, per below. The Read alone is not the contract — an unechoed Read is indistinguishable from a skipped one for anyone reviewing the run, including a later compaction-resume of it.

## The rule binds every deferred hop, not just the first

A spine that points at a phase file is the common shape, but not the only one. The contract binds any Read that a run must issue for itself to reach a gate:

- **The spine hop.** Where a skill's phase map lives in a loop spine of its own, reading that spine is bound too. A run that skips the spine and opens phase files directly emits every phase echo and looks compliant while never seeing the spine's own gates.
- **The second hop.** A phase file that defers its decision trees, gate wording, or an executable invocation to a further file — a `*-reference.md`, a criteria rubric, a mode body — has not delivered the gate; it has delivered a pointer. Read that file before the step that needs it, and echo it the same way. A phase file that describes itself as a running order is a phase file whose gates are all one hop away.
- **A dispatched body.** Where a skill routes to one of several operation files rather than numbered phases, the dispatched file is that run's phase body.

Echo each hop you take, naming the file. What the echo buys is that a reader can tell which hops a run actually made.

The echo carries only as far as this context. Where the obligation runs inside a subagent, or where one phase writes what a later phase gates on, the proof has to travel in an artifact instead — `${CLAUDE_PLUGIN_ROOT}/skills/_shared/skip-visibility.md` owns those two forms.

## Echo contract

Print exactly one line when the Read returns:

```
Phase <N> (<name>) — loaded <filename>.
```

Examples:

```
Phase 1 (Analyze) — loaded phase-1-analyze.md.
Phase 0 (Mode detect) — loaded phase-0-mode-detect.md.
```

The echo is user-visible proof the Read fired, and it is the only such proof — no hook enforces this contract, by design.

## When to re-read

Re-Read the phase file on every re-entry to that phase, not just the first: a resumption from a checkpoint, a return after an escalation, and — most importantly — after a compaction. Claude Code re-attaches only a skill's front-loaded prefix after a summary, so a phase body read before the compaction is gone, while the spine that names it survives. That asymmetry is what makes a mid-phase compaction the highest-risk moment for silently losing a gate.

A conditional phase whose trigger did not fire is skipped along with its file — no Read, no echo.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "The spine already describes Phase N — I know what it does, so the Read is ceremony." | The spine names the phase's purpose; the phase file holds its gates and its helper call sites with resolved parameters. Knowing what a phase is for tells you nothing about which approval question fires under the current signals. What you would skip is the branch conditions, not the summary. |
| "This task is small / the diff is trivial — the full phase procedure is overkill." | Task size changes what the steps do, never whether the gates apply. The workspace gate, the approval gates, and the instruction load are the parts that exist precisely so a small task cannot quietly become an unreviewed change on the wrong branch. |
| "I read the phase file earlier in this session, so it is still in context." | It is in context until the first compaction, which drops it while leaving the spine. Re-entering a phase after a summary with only the spine is the exact state this contract exists for — re-Read on every re-entry. |
| "I'll start the obvious setup work now and read the phase file once real work begins." | Setup IS the phase's first steps, and in several skills those steps are the gates — a workspace decision, a mode detection, a scope confirmation. Work done before the Read is work done outside whatever the Read would have gated, and it cannot be un-done by reading afterwards. |
| "The Read fired; the echo is redundant noise." | The echo is the only observable that distinguishes a run that honored this contract from one that skipped it — nothing else in the trace records it. Its cost is one line; its absence makes the skip invisible to the user and to any later review of the run. |
| "I'll read every phase file up front, then never worry about it." | Pre-loading the whole tree spends the compaction re-attach budget on phases the run may never enter, and the phases most at risk are the late ones whose files are then the first dropped. Read on entry, re-read on re-entry. |
