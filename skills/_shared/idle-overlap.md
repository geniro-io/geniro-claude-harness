# Idle-window overlap — fill an agent-wait with provably-independent work

A long-running skill that spawns a research or critic agent and then blocks idle waiting for it is running two large costs in series: the agent's compute AND (often) a user question that follows it. When the two are independent, overlap them — spawn the agent `run_in_background: true`, do the independent work while it computes, and drain the agent before the first step that consumes its output. Wall-clock collapses from `agent + other` to `max(agent, other)`.

Three anchors make a background overlap safe — a visible spawn, a drain before the terminal transition, and an unconditional echo — all defined in §"The contract" below. The overlapped work is a **user question** or a **second independent agent**, never a gate the spawn's output feeds.

## Two overlap shapes

**Shape A — agent-wait ↔ user question.** Spawn the research agent(s) `run_in_background: true`; in the SAME turn render-then-fire an `AskUserQuestion` whose answer does not depend on the spawn's output. The user reasons while the agent computes. Drain the agent before the first step that consumes its result.

**Shape B — co-fire independent agents.** Two or more agents that feed the same downstream gate and are mutually independent (e.g. one reads the codebase, one reads the web) fire in ONE assistant response instead of sequential sub-sections. Wall-clock collapses to the slowest single agent.

## Eligibility — provably independent only

Overlap is safe ONLY when the branches are provably independent, not merely likely so — the dependency-DAG regime, never speculative execution:

- **Shape A** — the question must be answerable without the spawn's output AND the spawn's result must not depend on the answer. If either side could inform the other, the branches are coupled: keep them serial. A user answer arriving while the agent computed against a now-changed premise is the documented stale-state failure — the overlapped result is a proposal, not a fact, until drained and checked.
- **Shape B** — each agent's inputs must be fully assembled before the co-fire, and no agent may consume another's output. If agent 2 needs agent 1's result, they are a pipeline: keep them serial.
- **Agent spawns only, never a fire-and-forget shell command.** A backgrounded agent is harness-tracked — completion re-invokes the orchestrator, the output file persists, and it is resumable by ID, so a missed return is detectable. A backgrounded shell command returns no exit code to inspect; its loss is silent (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §"Caller contract").

## The contract

1. **Visible spawn anchor.** Emit the `run_in_background: true` spawn as a visible action in the turn the overlap begins, so there is an on-transcript record it launched.
2. **Fire the overlapped work in the same turn.** Shape A: render a visible assistant message before the `AskUserQuestion`, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §"Turn-completion guard". Shape B: the co-fired agents are themselves the same-turn work.
3. **Drain before the dependent step.** Before the first step that consumes the backgrounded agent's output — and before any terminal `phase:` write or non-terminal re-entry that would re-spawn it — collect the result: read the task output file, or resume the agent by ID. The harness normally re-invokes the orchestrator with the result via a `<task-notification>`; the drain is the backstop for when that has not landed by the time the output is needed.
4. **Validate at the drain — do not trust the notification's timing.** The overlapped result is a proposal until drained. At the drain point, reconcile it against current state: if a user answer collected during the wait changed a premise the agent computed against, prefer the freshly-drained agent output and reconcile — do not blindly apply a stale in-flight result. Bare timestamps or sequence numbers are documented as insufficient; validate against the live state.
5. **Unconditional echo.** When the overlap defers a step that would otherwise be visible, echo one line proving it fired, so a silent skip is distinguishable from a dropped step.

## Hard boundaries — where overlap is forbidden

- **Never overlap past a code-edit gate.** A gate that must resolve before code changes (the /implement open-questions gate, the spec-challenge gate) may fire *earlier* via Shape A, but its resolution still blocks the transition to editing — the backgrounded work must not slip past the Edit boundary unresolved.
- **Never background an Always-WAIT safety gate** (library-adoption, runaway-scope, shared-branch ship, spec-challenge-on-drift). These stay synchronous.
- **Never background a reviewer/verifier batch whose output IS the next gate's input.** Eligibility excludes it — its output feeds the gate, so it stays a same-response blocking parallel spawn; the only overlap available there is seconds of prep against a minute of compute, which is not worth the drain complexity.
- **Respect the one-in-progress todo invariant.** A backgrounded agent overlapping a sequential-decomposition phase must not spawn parallel edit-todos.

## Anti-rationalization

| Reasoning | Why it's wrong |
|---|---|
| "The reviewers take 90s — I'll background them and draft the PR while they run." | The reviewers' output IS the fix-loop/gate input, so §Eligibility excludes them; the only overlap available is seconds of prep against a 90s wait. Background only spawns whose output the overlapped work does not need. |
| "The user will probably answer the same way — I'll ask the dependent question early too." | That is speculation, not independence. If the early answer could reshape the later question, they are coupled. Overlap only the provably code-independent questions; hold the rest until the drain. |
| "The agent already returned via `<task-notification>`, so I can skip the drain." | The notification's timing is not guaranteed — it can leak into the next turn or drop on simultaneous completion. The drain-before-dependent-step is the backstop that makes the result's arrival deterministic. |
| "It's just a shell command — I'll background it to save time." | A backgrounded shell command has no return path; its failure is silent. Only harness-tracked agent spawns qualify for overlap. |

## References

- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §"Turn-completion guard" — render-then-ask for Shape A.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` — registration ladder for every spawn.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` — OMIT `model=`.
