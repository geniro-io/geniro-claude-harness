# Audit-pipeline discipline (canonical, shared)

Shared contracts for the audit-shaped skills — `/geniro:audit-instructions`. Each consuming skill keeps its own dimensions, severity-tier definitions, and spawn template; this file is the single home for the machinery every audit runs identically: the pipeline invariants, the reviewer finding schema, and the fix-round discipline. A consuming skill cites the section it needs rather than restating it, and states its domain specifics beside the citation.

## Shared invariants

Every audit-shaped skill runs under these. A consuming skill cites this section and then lists only the invariants its own domain adds.

1. **No unverified finding ships.** A reviewer finding is admitted only after the orchestrator Reads the cited `file:line` and confirms the quoted evidence exists there — reviewers hallucinate locations, and one fabricated `path:line` poisons trust in the whole report.
2. **Report before fix.** Fixes happen only after the action gate — an audit that silently edits while scanning destroys the baseline its own findings cite.
3. **Parallel spawns in one response.** Every reviewer spawn goes in the same assistant turn; sequential turns serialize the batch's wall-time.
4. **The do-not-flag list is binding.** The consuming skill's endorsed-patterns list overrides any reviewer's instinct — re-flagging an endorsed pattern is the audit's own false-positive failure mode.
5. **Every run sweeps for subtraction.** The subtraction dimension runs on every audit, whatever the run's scope or depth, and its verdict names what was examined and what was rejected even when it yields nothing. A repo accretes through rounds that never looked, and an unreported sweep is indistinguishable from a skipped one. The result is never mandated: zero findings is valid, a manufactured deletion is not.
6. **Every approved finding has an owner.** Before spawning fix agents, assert that the union of their finding lists equals the approved set, and echo any finding with no owner. A finding assigned to nobody is work the user approved and never received.
7. **A whole mechanism is never removed on a blanket approval.** A subtraction proposal to delete an entire mechanic — a phase, gate, step, spawn, check, surface, or section — gets its own gate and its own explanation, whatever the user picked at the action gate. Every other finding changes something the user can inspect afterwards; a deleted gate leaves nothing behind to inspect, because the run that would have objected is the one removed.

The consuming skill binds invariants 4, 5 and 7 to its own vocabulary — which list is the do-not-flag list, which dimension is the subtraction sweep, and what counts as a whole mechanism in its domain — beside its citation of this section.

## Finding output contract

Every reviewer returns a Markdown table with EXACTLY these columns, one row per finding, capped at 25 rows (rank by impact; note "N further low-impact items omitted" if capped):

| Column | Content |
|---|---|
| `id` | `D<dim>-<n>` (e.g. `D3-4`); sub-reviewer spawns keep their unique label (`D5a-2`, `D4-shardB-1`) |
| `tier` | per the consuming skill's severity-tier table |
| `file:line` | Real location — verified by the reviewer with Read before reporting. Use `file:start-end` for ranges. |
| `issue` | One sentence, plain English |
| `evidence` | Verbatim quote (≤2 lines) from the cited location — the orchestrator re-verifies this quote exists |
| `fix` | Concrete suggested change, one sentence |
| `effort` | S / M / L |

A finding without a verifiable `file:line` + `evidence` is inadmissible — drop it rather than guessing a location. A consuming skill may narrow a column's rules for its domain (a secrets-auditing skill cites location and shape in `evidence`, never the value); the narrowing lives in that skill's reference, beside its citation of this section.

## Fix-round discipline

Applies after approved findings are grouped into disjoint file allowlists and the fix agents are spawned. Three things reliably happen — plan for them rather than treating each as an exception:

1. **An agent finds more instances of its defect class outside its own files.** It reports them; ground-truth the claim with a grep before routing it to the owning agent. Never let it reach across its allowlist.
2. **An agent judges a finding's stated fix wrong and says so instead of complying.** Treat that as the mechanism working. Verify the correction yourself, then amend the report row — a fix instruction written from a grep hit can be wrong in ways only the editing agent sees, and a report that ships the wrong instruction teaches the next round the wrong thing.
3. **A correct fix inside one scope breaks a reference in another.** A renamed heading, a stale mirror copy, a citation into moved text. After the round, re-check every cross-reference and mirror pair into a changed file, and route each repair to whoever owns the referencing file. Warning the agents in their briefs does not prevent it — re-check regardless.

**An agent that dies mid-run has usually already written its edits.** Ground-truth the working tree rather than assuming either outcome — a per-finding grep tells you what landed far faster than re-spawning.

**Verification, in order.** Re-run the consuming skill's mechanical battery (scoped where the battery supports it); Read each changed location to confirm the finding is resolved; re-run any execution harness a finding was established with — a claim proved by measurement is closed by measurement, not by reading the diff. A check failing mid-round usually means another agent is mid-write on a file it reads — re-run at the end rather than treating it as a regression.

**Do the once-per-round integration steps last, never per-agent** — regenerating a build artifact or mirror from sources several agents edited, accepting a baseline, completing a deletion across referencing files: each writes files every agent would race on. The consuming skill names its own integration steps beside its citation of this section.
