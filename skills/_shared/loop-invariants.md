# Canonical agent-loop invariants

The agent-loop invariants every Geniro orchestrator skill upholds, regardless of phase count. A skill cites this file and then adds its own skill-specific invariants (e.g. `/geniro:implement` adds subagent-delegation and single-`in_progress`-todo rules; `/geniro:review` adds the Reporter boundary). This is the single source — consuming skills reference it rather than restating the list.

1. **One result per tool call.** Every Edit / Write / Bash / Agent spawn produces exactly one structured result. A failed spawn yields a result with `status: failed` — never an absent one.
2. **Args validated before execution.** Bash commands built from `$ARGUMENTS` or state-file fields pass input sanity-checks; paths are absolute; slugs match the project's naming rules.
3. **Permission before side-effect.** Any tool call that mutates external state (`git push`, `gh pr create`, a posted PR comment, a tracker write) is preceded by an `AskUserQuestion` approval or a recorded prior approval.
4. **Bounded, structured tool results.** Subagent and Bash output is capped (truncate-with-marker, or summarize) before it reaches downstream reasoning, so a single large result can't crowd the orchestrator's context.
5. **Escalation gates, not silent abort.** Bounded retry loops surface to the user via `AskUserQuestion` at exhaustion — and earlier when the loop stops converging (no forward progress, the same failure recurring, or cost/scope drifting past the expected tier). Never a silent abort, never an infinite loop, never the full retry budget spent against an unmoving wall.
6. **Final answer grounded in observations.** A completion claim quotes actual tool output (a push ref, PR URL, commit SHA, test result) — never "it succeeded" without evidence. Read the state-file `## Tool log` before claiming a clean state.
7. **Errors, denials, cancellations, timeouts → structured observations.** A failed command, denied permission, hook-blocked write, subagent timeout, or non-zero exit becomes a structured observation entry — never silently skipped.

These seven are skill-agnostic. A skill's own SKILL.md lists any additional invariants its workflow needs.
