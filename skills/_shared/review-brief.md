# Review brief

`/geniro:review` blocks for several minutes while its dimension reviewers, and then its finding verifiers, run as parallel batches. This module defines an optional companion deliverable produced inside that wait: a short brief that orients the human on the change under review — why it exists, what it structurally does, where it concentrates, how it is verified, and what is still open — so there is something useful to read while the review runs. It is a reading aid, not an extra pass over the diff, and it renders no verdict.

## Contents

- Content contract — what the brief carries, in what order, and what it never says
- Coverage declaration — the brief states what it skipped
- Isolation invariant — the brief never reaches a reviewer or verifier
- Medium selection — Artifact or a markdown file, and how the run picks
- Spawn template — the `Agent(...)` call and its prompt slots
- Caller contract — what the calling skill provides and does with the result

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

The reviewers' independence from each other is what makes their findings worth aggregating, and the framing bias described in §Content contract is exactly what breaks that independence if a reassuring or judgment-laden brief leaks into a reviewer's context — the same collapse in detection, seeded across every dimension at once instead of costing one human reader their own read. The pipeline holds this invariant by construction for the reviewer batch: the brief is not spawned until that batch has returned, so no reviewer prompt could carry it. It holds by discipline, not construction, for every later verifier spawn — the Phase 4.2 per-finding verifier may fire while the brief is still in flight, and the Phase 6 "Challenge this finding" spawn fires long after it landed; nothing about the flow's shape keeps it out of either prompt, so the brief is simply never composed into one. State the rule anyway, because the risk is a later edit — a verification pass, or the report synthesis that quietly starts reading the brief once it exists as a file or a URL sitting right there in state.

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

**The opt-in is asked in the same assistant response that fires the reviewer batch, never in a turn before it.** Ordering is the whole of it: the offer is worth making only because the brief is free in wall-clock, and a question standing ahead of the fan-out spends the user's answering time postponing the very wait the brief exists to fill. Asked alongside the batch, the reviewers are already computing while the user reads the question.

Once the answer lands, the caller provides the five slots above and fires this spawn `run_in_background: true`, then carries on with the review. Nothing downstream gates on the brief — it feeds the user, not the pipeline — which is precisely the case `${CLAUDE_PLUGIN_ROOT}/skills/_shared/idle-overlap.md` sanctions for a backgrounded spawn, its three anchors (visible spawn, drain before the dependent step, unconditional echo) applying unchanged. The reviewer batch stays synchronous and blocking: its output IS the next gate's input, the case that file's hard boundaries reserve for exactly that shape.

The drain deadline is the last point at which the caller can still write or publish — a brief still in flight past that point has nowhere to land. Once drained, the caller materializes it per §Medium selection and surfaces where it landed to the user exactly once, in plain language — a link or a path, never an internal phase name or state-file term.
