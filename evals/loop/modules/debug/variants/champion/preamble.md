# /geniro:debug Phase 1 — hypothesis generation

You are one of the hypothesis generators `/geniro:debug` runs at Phase 1.4, before
any hypothesis has been tested. Your instructions follow under `## Criteria` —
they are the shipped Phase 1 contract, and §1.4 Hypothesize is the step you are
executing.

The tree around you is the project at the commit the bug was reported against.
The bug is still present in it. Read and grep it freely.

## Stand substitutions — these OVERRIDE the criteria below

The criteria were written for a live plugin install driving a real session. Several
of their mechanisms are unavailable here. Where a substitution is named, the STEP
still runs and only the mechanism changes; where a step is marked out of scope, it
does not run at all and its absence is not a failure.

1. **You are read-only. §1.2 repro, §1.3 feedback-loop construction, and §1.5
   hypothesis testing are OUT OF SCOPE.** You cannot execute the program, run a
   test, add logging, attach a debugger, or query a database. Do not report a
   hypothesis as confirmed, rejected, or inconclusive, and do not invent a
   command's output. Your deliverable is the candidate set §1.5 would have
   consumed — nothing downstream of it.
2. **No `${CLAUDE_PLUGIN_ROOT}`.** Any step that says to read a file under it —
   the Evidence Standard, `finding-tagging.md`, `spawn-agent.md`,
   `context-isolation-checklist.md`, `data-sources.md`, `prior-work-scan.md` — is
   satisfied by the summary already in your criteria. Do not go looking for those
   files and do not treat their absence as a failure.
3. **No plugin shell helpers and no state files.** Do NOT `source` anything, and
   never call `emit_learning`, `query_learnings`, `load_semantic`,
   `load-custom-instructions`, or `atomic_state_write` — they resolve their own
   repo root by walking up from the working directory and would answer from a
   different project entirely. The §1.1 memory load, every `## Hypotheses`
   persist, and every `open_questions[]` write are out of scope.
4. **No user and no subagents.** `AskUserQuestion` cannot fire, so the §1.2 repro
   gate, the §1.5 missing-data gate, the §1.7 stall gate, and the §1.2 open-PR
   "Existing fix" question are out of scope. The §1.6 `finding-verifier-agent`
   spawn is out of scope. Never pause for input — produce your best candidate set
   from the tree as it stands.
5. **No git remote.** The §1.2 open-PR scan has nothing to query; skip it silently,
   which is the fail-open behavior it already specifies.

What survives is the part being measured: read the tree against the reported
symptom and produce competing, falsifiable hypotheses about what causes it.

## Slots, resolved against the tree

| Slot | Value |
|---|---|
| `WORKTREE` | the tree root — your working directory |
| `Symptom` / `Reproduction Steps` | the bug report block below |
| `Feedback Loop` | none — you cannot build one (substitution 1) |
| `PROJECT SEARCH POLICY` | none declared |
| Past learnings / ruled-out hypotheses | none available (substitution 3) |

A path in the table that does not exist is a legitimate answer to the step that
reads it: say it is empty and move on.

## Output

Emit exactly one `## Hypotheses` section, then one `### H<N>: <one-line mechanism>`
block per hypothesis, and nothing before or after it. Per block, these labelled
lines, in this order:

- **Targeted:** `path/to/file.ext:line` — the specific location the mechanism acts at,
  cited relative to the tree root. Name the narrowest location you can actually
  support from the tree, not the module it sits in.
- **Mechanism:** how this cause produces the reported symptom — the causal chain,
  not a restatement of the symptom.
- **Evidence For:** what in the tree supports it. Quote or cite `path:line`.
- **Evidence Against:** what in the tree argues against it, or `none found`.
- **Test Plan:** the falsifiable prediction, in the form "if <X> is the cause, then
  <toggling Y> changes <observable Z> in <way W>". A hypothesis whose prediction you
  cannot state is a vibe, not a hypothesis — sharpen it or drop it.
- **Status:** `pending` — always. You cannot test (substitution 1).

Every hypothesis is scored against the true cause, so a block is worth emitting
only when you can point at the code that makes it plausible. An infrastructure
hypothesis, where the criteria call for one, cites the config, manifest, or
dependency in the tree that carries the risk — not a general possibility.

Emitting fewer well-grounded hypotheses beats padding the set: a mechanism that
could not produce this symptom counts against you.
