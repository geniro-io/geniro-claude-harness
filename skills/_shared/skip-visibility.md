# Skip visibility (canonical, shared)

## Contents

- §Why this exists — the two boundaries an echo cannot cross
- §The load report — a subagent proves its own Reads happened
- §The assessed sentinel — a producer proves its step ran
- §Anti-rationalization

**Status:** Authoritative for the two cases where the echo in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` cannot carry the proof. Every agent that loads its own instructions carries a load report; every gate whose input a different phase writes reads an assessed sentinel.

## Why this exists

An instruction the model can treat as already-satisfied needs an observable, or a skip and a compliance look identical from the outside. Inside one context that observable is the echo — a line printed when the Read returns.

The echo stops at two boundaries.

- **A spawn boundary.** A subagent's narration stays in the subagent's transcript; only its returned report reaches the orchestrator. So an agent that skipped its instruction load and an agent that honored it hand back reports that are indistinguishable, and the spawn site has nothing to check.
- **A phase boundary.** Where one phase writes a gate's input and a later phase decides on it, the echo happened in a turn the consumer never saw — and after a compaction, in a turn nobody can see. What the consumer holds is the artifact, and an artifact that was never written looks exactly like one whose producer found nothing to write.

Both are fixed the same way: move the proof out of narration and into the thing the consumer already parses.

## The load report

**Every agent whose own workflow tells it to Read something ends its returned report with a load report** — one line, in the summary section the orchestrator parses:

```
Context loaded: <item>=<state>, <item>=<state>
```

`<item>` names what the agent's contract told it to load (`criteria`, `project-rules`, `search-policy`, `memory-routing`). `<state>` is one of:

| State | Means |
|---|---|
| `read` | You opened it in this run. |
| `slot` | The spawn prompt carried it, so no read was needed. |
| `absent` | You looked; the project ships none. |
| `unreadable` | You looked; the read failed. |

`absent` and `unreadable` are deliberately separate — the first is a normal project shape, the second is usually a bad path the orchestrator passed, and collapsing them hides the one the spawn site can fix.

**The spawn site reads the line back before consuming the report.** A report arriving with no `Context loaded:` line was produced by an agent that did not run its load steps, so its conclusions rest on the plugin's defaults rather than the project's rules — say so in the run's narration rather than quietly accepting them, and re-spawn where the missing rules would have changed the agent's search or its judgment. An `unreadable` on a path the orchestrator itself passed is the orchestrator's defect: fix the path and re-spawn that one agent.

Nothing here replaces the agent's own echo. The echo is what makes the load visible while the agent runs; the report line is what makes it visible to anyone else.

## The assessed sentinel

A gate whose input another phase writes can be in more states than the artifact usually records.

**Producer side — always write the input, even when there is nothing to record.** A frontmatter array writes its empty form (`open_questions: []`). A body section keeps its heading and carries one line naming that the producing step ran:

```markdown
## Deferred — sub-threshold
none — the Phase 4 filter ran and deferred nothing
```

**Consumer side — what each reading means:**

| What you read | What it means | What to do |
|---|---|---|
| Content | The producer has something for this gate | Fire the gate |
| The `none — <step> ran …` sentinel | The producer assessed and found nothing | Skip the gate; this is the clean path |
| The key or heading absent, or present but bare | The producing step did not run | Treat the gate's precondition as unknown |

A bare-empty section reads as unknown rather than as clean, because a producer that never ran could not have written the sentinel — the sentinel is the only positive evidence available, so its absence is the signal.

**A named case: a phase's own entry obligations.** The producer need not be a subagent — when a later gate depends on a phase's own required entry steps (a body Read, an instruction refresh, an acceptance check) having actually run, that phase is a producer too, and the same shape applies. Producer side: record a completion sentinel for those obligations at the phase's own exit, including the no-op case, somewhere the later phase can still read once the turn that ran them is gone — that turn's echo does not survive the phase boundary (§Why this exists). Consumer side: read it against the same table above, not against "the run reached this phase," since a skip and a compliant run both simply continue. This is a pattern to reach for where such a dependency exists, not a standing requirement on every phase — which obligations to record, and where, is the owning skill's own contract; this file states the shape, not the fields.

**What "unknown" costs is proportional to what the gate guards.** For a gate standing in front of an external effect — a commit, a push, a posted review — resolve it before that effect: run the producing step, or ask. For an advisory gate that never blocks, one line in the run's output is the whole remedy; escalating there would trade a real skip for a false alarm on every clean run.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "The agent echoed the policy it loaded — that is the proof, so the report line is duplication." | The echo is in the agent's transcript, which the orchestrator never receives. Everything the spawn site knows about the agent arrives in the returned report, so a proof that is not in the report is a proof nobody downstream can read. |
| "The section is empty, so there is nothing to gate on — skipping is the same either way." | It is the same only when the producer ran. When it did not, skipping the gate is how an unreviewed commit, an unresolved question, or an unpushed test file reaches the user as a finished result. The sentinel is what tells the two apart. |
| "Writing `none` into an empty section is noise in the artifact." | It is the one line that distinguishes a clean run from a skipped step, and it is read by a consumer that cannot ask the producer anything. One line is what the distinction costs. |
| "The agent's contract already tells it to load the file — restating the obligation as an output field is redundant." | The contract is the instruction; the field is the observable. This class of failure exists precisely because instructions are followed silently and skipped silently, so adding a stricter instruction changes nothing a reader can check. |
| "The load report says `absent` — the project ships no rules, so I can drop the slot on the next spawn." | `absent` is one agent's result at one moment, not a project fact you may cache into your spawn construction. The push obligation in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` is unchanged by any agent's report. |
