# Review brief

`/geniro:review` blocks for several minutes while its dimension reviewers run as one parallel batch. This module defines an optional companion deliverable produced inside that same window: a short brief that orients the human on the change under review — why it exists, what it structurally does, where it concentrates, how it is verified, and what is still open — so there is something useful to read while the reviewers work. It is a reading aid, not an extra pass over the diff, and it renders no verdict.

It orients a reader *ahead of* the findings, so it is worth only as much as the lead time it keeps: a brief that arrives once the reader has worked through the report has spent the run's tokens telling them what they just read.

## Contents

- Content contract — what the brief carries, in what order, and what it never says
- Coverage declaration — the brief states what it skipped
- Isolation invariant — the brief never reaches a reviewer or verifier
- Medium selection — Artifact or a markdown file, and how the run picks
- Spawn template — the `Agent(...)` call and its prompt slots
- Caller contract — when the opt-in resolves, when the spawn fires, and when the result is materialized

## Content contract

The brief maps the change; it never assesses it. It carries five parts, in this order, because rationale is what a diff cannot show on its own and is what a reader most needs before looking at code:

1. **Why the change exists** — the rationale, drawn from the PR body, the commit messages, and any linked issue.
2. **What it structurally does** — what is new, what moved, what was deleted, and the entry points into the affected system.
3. **Where the change concentrates** — which files carry most of it, and what else in the repo depends on those files. A statement about structure and blast radius, never a risk rating.
4. **How the change is verified** — the tests, checks, or fixtures already present in the diff, and which parts of the change have none.
5. **Open questions** — what the reader should work out for themselves while reading, not what the brief has already decided for them.

The brief describes and asks; it does not rate. No part above carries a severity label, a merge verdict, a quality judgment, a review-effort score, or an evaluative adjective ("straightforward", "low-risk", "clean", "mechanical", "well-structured"). A reassuring framing can collapse defect detection by up to 93 percentage points, biased hard toward missed defects over false alarms — so a brief that reads as reassurance is the single most damaging thing it could produce, independent of whether that reassurance happens to be accurate.

Every structural relationship in the brief is written in prose with a pointer attached, never drawn. No sequence diagrams and no other generated visuals: visual elements carry no association with review outcome, and developers rank them least useful of the content types tested — so a diagram here spends tokens and reading attention for nothing back.

**Every claim carries a checkable pointer** — a `file:line`, a symbol name, or a call path. This is the highest-leverage single rule in this contract: showing localized evidence alongside an AI's output roughly halves both automation and anchoring bias. An unpointed claim is exactly the shape of output that biases a reader hardest.

**Length is budgeted against the reader's attention, not the wait.** Defect detection collapses on a long diff, and more background context has been shown to make detection worse, not better — so a short brief is the evidence-backed form, not a compromise made for time. Aim for something a reviewer reads in about two minutes. Cover what the diff itself does not show; a file-by-file narration of the diff belongs to the diff, not to the brief.

## Coverage declaration

The brief states what it did not read: a file skipped for size, a diff truncated at its source, a generated or vendored path excluded on sight, anything the run could not resolve. Readers working alongside an AI fixate less on the areas it stayed silent about — an unstated gap becomes the reader's blind spot rather than a known limitation they can compensate for.

This is a required section of the brief's output on every run. When nothing was skipped, it says exactly that rather than being left out.

## Isolation invariant

The brief never enters a reviewer's or a verifier's input, at any phase, and no later phase feeds it into one. This file is the canonical statement of that rule; other files reference it here rather than restating it.

The reviewers' independence from each other is what makes their findings worth aggregating, and the framing bias described in §Content contract is exactly what breaks that independence if a reassuring or judgment-laden brief leaks into a reviewer's context — the same collapse in detection, seeded across every dimension at once instead of costing one human reader their own read. The pipeline holds this invariant by construction for the reviewer batch: the brief is spawned alongside it, never ahead of it, so every reviewer prompt is already composed and fired before the brief's first word exists. It holds by discipline, not construction, for every later verifier spawn — the Phase 4.2 per-finding verifier and the Phase 6 "Challenge this finding" spawn both fire after the brief has landed; nothing about the flow's shape keeps it out of their prompts, so the brief is simply never composed into one. State the rule anyway, because the risk is a later edit — a verification pass, or the report synthesis that quietly starts reading the brief once it exists as a file or a URL sitting right there in state.

## Medium selection

The brief materializes as one of two forms, and the run asks the user which:

- **A published Artifact** — offered only where the session can actually publish one. Under Cursor and any other host without that capability, the option does not appear at all (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md` maps `Artifact` to skip). Author the page as a self-contained HTML file in the session scratchpad and publish it from there; load the `artifact-design` skill before writing it — the same authoring path `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md` §Availability detection & create takes for its own page. The file medium below needs none of this.
- **A markdown file** at `<repo-root>/.geniro/state/review/brief-<branch>-<date>.md`, written with `atomic_state_write`. Resolve `<repo-root>` in the same Bash call that writes:

  ```bash
  source "${CLAUDE_PLUGIN_ROOT}/lib/repo-root.sh"
  PRIMARY_ROOT="$(_geniro_repo_root)"
  source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"
  atomic_state_write "$PRIMARY_ROOT/.geniro/state/review/brief-<branch>-<date>.md" <<EOF
  <brief content>
  EOF
  ```

  Resolving through `_geniro_repo_root` rather than a bare walk-up matters specifically inside a linked worktree, where a second, wrong `.geniro/` root is otherwise reachable (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §Path roots).

When only one medium is available, take it without asking — a question with one possible answer is a wasted turn. When a publish is attempted and fails (no plan entitlement, no active session), fall back to the markdown file, update the persisted `brief:` setting to `file` so it matches what was actually produced, and say so in one line.

This is a different fallback from the one `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md` forbids. There, a local stand-in file would be a stray HTML page nobody asked for, so that module bans it outright. Here the markdown file is one of the two forms the user could have picked from the start, so falling back to it loses nothing the user valued.

The file is written once per run and is never refreshed as findings arrive: it describes the change, and the change does not move while the review runs.

## Spawn template

No brief-authoring agent exists under `agents/`, and this module does not add one — the default spawn is `general-purpose` carrying this file's contract inline, not a named agent resolved through the registration ladder. If a caller instead routes this work through an existing named plugin agent, follow the ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` for that spawn.

```
Agent(
  subagent_type="general-purpose",
  description="Author a review brief",
  prompt=<<this file's §Content contract and §Coverage declaration, inlined verbatim>>
    + "\n\nDo not Write, Edit, or publish anything. Return the finished brief as your final message — the caller materializes it.\n\n---\n\n"
    + "TARGET: <the diff, or its resolved target>\n"
    + "PR CONTEXT: <PR body and commit messages, when TARGET is a PR — 'none, not a PR' otherwise>\n"
    + "TRACKER: <linked-issue text, when one exists — 'none' otherwise>\n"
    + "FILE INVENTORY: <the triage's changed-file list>\n"
    + "CONVENTIONS: <path to the repo's convention docs>"
)
```

OMIT `model=` so the spawn inherits the orchestrator's tier. Judging what a human most needs to see going into a review is itself a judgment call, not a mechanical transform, and judgment-grade spawns inherit the orchestrator's tier (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`).

The agent returns the brief's markdown as its result. It does not write a file and does not publish anything — the medium is the caller's decision (§Medium selection), and the caller is the only side with a publish surface.

The prompt carries five slots. `TARGET` is the diff itself, or whatever it resolves to. `PR CONTEXT` carries the PR body and commit messages when the target is a PR — the first half of where §Content contract's rationale item comes from. `TRACKER` carries any linked-issue text, the rest of that rationale. `FILE INVENTORY` is the triage's list of changed files. `CONVENTIONS` points at the repo's own convention docs, so the agent can describe a pattern as the repo's own rather than as novel. Wrap `TARGET`, `PR CONTEXT`, `TRACKER`, and `FILE INVENTORY` in the `DIFF`, `PR-BODY`, `TRACKER`, and `CHANGED-FILES` fences per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/untrusted-content-defense.md` — this agent reads the same untrusted diff, PR text, and tracker text a reviewer does, with none of a reviewer's isolation protecting it from an embedded instruction.

## Caller contract

**The opt-in resolves BEFORE the response that fires the reviewer batch; the brief spawns INSIDE that response; the caller materializes it the moment the batch returns.** Those three points are the contract, and the spawn's is the one that decides whether the brief is worth producing at all.

The spawn can only overlap a wait it starts inside of. A question asked in the batch's own response cannot be read back until that response completes — which is after the last reviewer has returned — so an opt-in asked there postpones the spawn past the entire window it exists to fill. Measured once that way on a 57-minute review of a 16-file PR: reviewers returned at 12:04 and their findings printed immediately; the brief spawned at 12:05:30, published at 12:11, and the aggregation step that should have followed the batch stood still for those seven minutes. The brief cost the run time instead of hiding inside it, and reached its reader after every finding it was meant to precede.

None of the five slots above carries the answer — the medium decides only how the caller materializes the returned markdown, never a word of what the agent writes — so the spawn never needed the answer for its prompt. It needs only to be *fireable* in the batch's response, which means the answer has to be in hand before that response starts.

**Ask it where it is free.** Any question the calling skill already fires ahead of the fan-out carries this offer as one more question in the same call, and then the answer costs nothing at all. With no such question to join, the offer stands alone immediately before the fan-out: seconds of answering time against the minutes of fan-out the brief then overlaps — the trade the measurement above settles.

The caller provides the five slots and fires this spawn in the same assistant response as the reviewer batch — one more parallel spawn alongside them, not backgrounded and not a separate turn. This borrows the co-fire mechanics of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/idle-overlap.md` Shape B — mutually independent agents in one response, neither consuming the other's output — without Shape B's own precondition that both feed the same downstream gate: the reviewers feed the next gate, the brief feeds the user, not a gate at all. Co-firing collapses the wait to the slower of the two, and puts the brief in the caller's hands at the same moment the reviewers' output is. The reviewer batch itself still never backgrounds — its output IS the next gate's input, the case that file's hard boundaries reserve for a synchronous same-response spawn — and adding the brief alongside it does not change that.

**Materialize at the batch's return, ahead of the work that consumes the findings.** In that same response the caller writes or publishes it per §Medium selection and surfaces where it landed exactly once, in plain language — a link or a path, never an internal phase name or state-file term. Deferring this to a later phase costs the reader exactly what the late spawn cost them, one phase at a time, and the last moment it is possible at all is the phase that revokes the write and publish grant.
