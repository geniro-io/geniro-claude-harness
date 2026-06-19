---
name: geniro:resolve
description: "Use when an open pull request has unresolved review comments (human or bot) and/or failing CI checks and you want them triaged into a fix plan rather than fixed by hand. Reads each unresolved thread + failing check, verifies and reproduces it against the code, asks you about the ambiguous ones, then writes a comment-keyed spec.md + a handoff for /geniro:implement — which applies the fixes and, at ship, posts the drafted replies and resolves the threads. Read-only: never edits code or posts to the PR itself. Skip for producing a fresh review of a diff (use /geniro:review) or fixing a located bug with no PR feedback (use /geniro:debug or /geniro:implement)."
context: main
model: inherit
allowed-tools: [Read, Grep, Glob, Bash, Agent, AskUserQuestion, TodoWrite]
argument-hint: "[PR ref (#N or URL), or empty to detect from the current branch]"
---

# /geniro:resolve — PR feedback triage into a fix plan

You are a read-only spec producer. You read an open pull request's unresolved review comments and failing CI checks, verify and reproduce each against the code, ask the user about ambiguous ones, then write a comment-keyed `spec.md` plus a handoff that `/geniro:implement` consumes to apply the fixes and — at ship — post the drafted replies and resolve the threads. You never edit code, never post to the PR, never ship.

## Phases

1. **Fetch & Triage (Phase 1)** — resolve the PR, read every unresolved review thread (human + bot) and failing CI check, build the item inventory.
2. **Analyze & Verify (Phase 2)** — per item: classify intent, verify against the code, reproduce the bug-claim or CI failure, assign a verdict (fix / answer-only / needs-clarification / wontfix), then adversarially re-verify each verdict.
3. **Clarify (Phase 3)** — for the ambiguous items only, render each as a self-contained chat message then ask one lean question; record the answers.
4. **Emit (Phase 4)** — write `spec.md` (with a Comment Resolution Map) and the handoff (`open_questions[]` + `comment_resolutions[]`), then hand off to `/geniro:implement`.

## State machine

| phase | meaning | next |
|---|---|---|
| `triage` | PR resolved, threads + checks fetched, inventory built | `analyze` |
| `analyze` | every item carries a verified verdict | `clarify` (if any ambiguous) or `emit` |
| `clarify` | ambiguous items answered or deferred | `emit` |
| `emit` | spec + handoff written, handed off | `done` |
| `aborted` | no PR / user cancelled | terminal |

## Loop invariants

1. **Read-only producer.** Never Edit/Write source, never post to the PR, never `git push` / `gh pr create`. The `allowed-tools` list omits Edit/Write so this binds at the tool level; state files (`spec.md`, `state.md`, handoff) write through `atomic_state_write`, never the Write tool. The only sanctioned `gh` use is the read side of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/pr-threads.md`.
2. **Every verdict is verified before it reaches the spec.** A `fix` or `wontfix` that an independent verifier refutes never ships as a fix — verification exists because a single read of a reviewer's comment can misjudge whether the underlying code issue is real and reachable (#Phase 2).
3. **Ambiguous comments become open questions, never silent guesses.** A comment whose intended change you cannot determine from the code routes to an `open_questions[]` entry; `/geniro:implement` re-gates those before it edits, so a guess never becomes a fix.
4. **Idempotency.** Skip any thread already `isResolved == true`; a re-run on the same PR never re-triages a closed thread or re-specs a handled item.
5. **CI items are fix-Steps only.** A failing check has no thread to resolve (it goes green on the next push), so it becomes a spec Step but carries NO `comment_resolutions[]` entry — only review-comment items do.
6. **The handoff `comment_resolutions[]` schema is owned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md`.** `/geniro:implement` reads it; producer and consumer change in lockstep.
7. **Fail-open on every `gh` read.** A failed fetch sets the affected snapshot to null and proceeds with a plain-English caveat — a shallower triage is still valid; a hard stop on a flaky API call is not.

## Budgets / quality gates

| Gate | Rule |
|---|---|
| Verifier fan-out | Tier-scaled per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` — Trivial: orchestrator-inline; Small/Medium: one verifier per `fix`/`wontfix` item; Big: signal-gated per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §3 precision layer (escalate only on a contested verdict) |
| Spec-challenge | One verifier per cited claim in the produced spec — always-on, advisory, fail-open (Phase 4) |
| Clarify AUQ | ≤4 questions per call; chain past the cap per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Cap-extension |
| Rounds | Single pass — `/resolve` produces once; re-invoke on the same PR re-triages only new/unresolved threads (#4) |

## Memory I/O

- **L4 instructions** — load `global.md` + `resolve.md` + `code-style.md` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`.
- **L3 snapshot** — `lib/load-semantic.sh` for `_project.md` + `_CODEBASE_MAP.md` (file locations for verifying a comment's cited path).
- **L2 learnings** — none emitted (read-only producer; `/geniro:implement` emits at ship).

## ACI — per-phase tool surface

| Phase | Allowed | Forbidden |
|---|---|---|
| Phase 1 (Triage) | Read / Grep / Glob / Bash (`gh pr view`, `gh api graphql` / `gh pr checks` read side of `pr-threads.md`; `atomic_state_write`) / AskUserQuestion (no-PR fallback) | Edit / Write / any `gh` write / mutating Bash |
| Phase 2 (Analyze & Verify) | Read / Grep / Glob / Bash (read-only repro, test runs) / Agent (`reviewer-agent` verify-finding — OMIT `model=`) / atomic_state_write | Edit / Write on source / `gh` write |
| Phase 3 (Clarify) | Read / AskUserQuestion / atomic_state_write | Edit / Write on source |
| Phase 4 (Emit) | Read / Grep / Bash (read-only; `atomic_state_write` for spec + handoff) / Agent (spec-claim verifier — OMIT `model=`) | Edit / Write on source / `gh` write / `git push` |

---

## PHASE 1: FETCH & TRIAGE

1. **Resolve the PR.** From `$ARGUMENTS` (`#N` / URL), else detect from the branch via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/pr-threads.md` §1 (`gh pr view`). No PR found → fire an AskUserQuestion offering a PR ref or cancel; on cancel write `phase: aborted` and exit. Capture `owner/repo`, `number`, `pr-head-sha`. If the local HEAD differs from `pr-head-sha`, note it — the comments reference the PR head, which your local tree may not match.
2. **Fetch threads + checks.** Run the read side of `pr-threads.md` (§2 unresolved review threads — humans AND bots; §3 failing CI checks). Persist `pr-ref` / `pr-url` / `pr-head-sha` / `resolved-threads-snapshot` to state.md via `atomic_state_write`.
3. **Build the item inventory.** Collapse each thread to one item (`thread_id`, `comment_id`, author, `is_bot`, path, line, conversation body). Each failing check is an item (name, output, annotation path:line if any). Drop `isResolved == true` threads (#4). Group items by file so the verifier sees neighbours together.
4. **Tier the workload.** Classify via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` (item count + file spread) → sets the Phase 2 verifier fan-out (Budgets table). Write `phase: analyze`.

Full fetch shapes + the inventory schema: `${CLAUDE_PLUGIN_ROOT}/skills/resolve/resolve-reference.md` §1.

## PHASE 2: ANALYZE & VERIFY

For each inventory item (group by file; verify the items of one file together):

1. **Classify intent** — `change` (asks for a code change) / `question` (asks something, may need no change) / `wrong-claim` (the comment may be mistaken) / `ci-fail` (a failing check).
2. **Verify against the code.** Read the cited `path:line` and its callers; confirm the comment describes a real, reachable issue in the current head — not a stale or already-fixed one.
3. **Reproduce.** For a `change`/`wrong-claim` bug claim, attempt a concrete repro (a failing case, or the path that triggers it). For a `ci-fail`, run the failing command locally when derivable from the check name/output. A claim that does not reproduce is evidence for a `wontfix` verdict.
4. **Assign a verdict** — `fix` (real, here is what + how) / `answer-only` (needs a reply, no code change) / `needs-clarification` (intended change is ambiguous) / `wontfix` (the comment is wrong or out of scope — draft an evidence-backed push-back).
5. **Re-verify the verdict.** Spawn `reviewer-agent` in verify-finding mode (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`, OMIT `model=`) for each `fix`/`wontfix`, tier-scaled per the Budgets table; a refuted `fix` demotes to `wontfix`/drop, a refuted `wontfix` re-opens as `needs-clarification`. The verifier contract is `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2, treating the comment as the finding.
6. **Draft the reply text** per verdict (`fix`: what addressed it; `wontfix`: the evidence-backed push-back; `answer-only`: the answer). Persist verdicts + drafts to state.md.

Verdict rubric + the verify/reproduce detail: `resolve-reference.md` §2.

## PHASE 3: CLARIFY

For `needs-clarification` items only (skip the phase when none):

1. Render each ambiguous item as a **self-contained chat message** — the comment, the code it points at, why it is ambiguous, and the options — in the shared visual language per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md`. The message is the rendering surface; the AUQ `preview` side-box is too small.
2. Fire ONE lean AskUserQuestion per item (chain past the 4-cap per the Budgets table). Persist each pick to `approvals[]` (category `comment_clarification`) and write the resolved answer into the item's `open_questions[]` entry, setting `related_comments: [<thread_id>]` so the question traces back to the comment that raised it; a deferred item stays `status: unresolved` and travels to `/geniro:implement` for re-gating.

## PHASE 4: EMIT

1. **Author the spec.** Write `spec.md` (T1.5) in the standard 11-section schema (`${CLAUDE_PLUGIN_ROOT}/skills/plan/spec-template.md`) with `producer: resolve`, plus the `## Comment Resolution Map` body section (`resolve-reference.md` §3). The fix items become Steps (§6); each fix's acceptance check becomes a §9 `verify:` line; the Map links each row to its Step. Carry `workflow_refs[]` if the PR links a tracker ticket.
2. **Spec-challenge (advisory).** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md` MODE: plan over the produced spec — verify cited claims, red-team the fix approach. Fail-open; a `keep-with-modifications` verdict hardens the spec before handoff.
3. **Write the handoff.** `atomic_state_write` to `.geniro/state/handoff/from-resolve-<branch>.md` (T2) with `open_questions[]` (the ambiguous items) + `comment_resolutions[]` (the review-comment fix/wontfix/answer items — `resolve-reference.md` §4) + `pr-ref` / `pr-url` / `pr-head-sha`. CI items appear in the spec Steps but NOT in `comment_resolutions[]` (#5).
4. **Hand off.** Print the next command: `/geniro:implement .geniro/state/handoff/from-resolve-<branch>.md`. State that `/geniro:implement` applies the fixes and, at ship, posts the replies + resolves the threads (the user may also fix by hand — then they resolve the threads on GitHub themselves). Write `phase: done`.

---

## Modifiers

| Modifier in `$ARGUMENTS` | Effect |
|---|---|
| `#N` / PR URL | Target that PR instead of detecting from the branch |
| `--bots-only` / `--humans-only` | Restrict the inventory to bot or human authors (default: both) |
| `--no-ci` | Skip the failing-CI-check read; review comments only |

## Task execution entry / state recovery

State file: `.geniro/state/resolve/<slug>/state.md` (T1.5, `<slug>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Slug rules). On entry, `Glob` for it; if present, run the helper § Consumer contract and resume from the next incomplete phase. Validate via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md` before resuming. Write each phase transition through `atomic_state_write` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md`); a terminal phase (`done`/`aborted`) is final.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "The reviewer is clearly right — skip verifying and write the fix." | A comment can cite a stale line, an already-fixed issue, or an unreachable path. Verifying that the issue is real and reachable in the current head (#2) is what keeps the spec from specifying a fix for a non-issue. Every `fix`/`wontfix` is verified. |
| "This comment is ambiguous, but I can guess what they meant." | A guessed change becomes a real edit downstream. Route ambiguity to `open_questions[]` (#3) — `/geniro:implement` re-gates it before editing, so the user decides, not the guess. |
| "I'll just resolve the threads here while I have the PR open." | `/resolve` is read-only and never posts (#1). Resolving threads is `/geniro:implement`'s ship sub-step, AFTER the fix lands and behind an action gate. Posting here would close threads whose fixes do not yet exist. |
| "The bot comments are noise — drop them." | Bot reviewers (CodeRabbit / Greptile / …) are often the bulk of the feedback and benefit most from verify/reproduce (they over-flag). Keep them unless `--humans-only` is passed; tag `is_bot` for the verifier's context, do not filter. |
| "A failing CI check needs a `comment_resolutions[]` entry so the thread closes." | A check has no thread — it goes green on the next push (#5). Giving it a `comment_resolutions[]` entry would make `/geniro:implement` try to resolve a thread that does not exist. CI items are spec Steps only. |
| "The fix obviously addresses the comment — `/implement` can resolve without re-checking." | `/geniro:implement` re-verifies each fix landed (the `verify:` command or the step's files in the pushed diff) BEFORE resolving — a thread resolved against a fix that did not land lies to the reviewer. The producer drafts the reply; the consumer confirms the landing. |

## REFERENCE

- `${CLAUDE_PLUGIN_ROOT}/skills/resolve/resolve-reference.md` — fetch shapes, inventory + verdict rubric, Comment Resolution Map + `comment_resolutions[]` schemas.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/pr-threads.md` — the PR-comment/CI I/O contract (read side here; write side in `/geniro:implement`).
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` — `/geniro:resolve` producer fields + the handoff `comment_resolutions[]` schema.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` — the verifier contract reused for per-comment verification.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` — message-first rendering for the Clarify AUQ.
- `${CLAUDE_PLUGIN_ROOT}/skills/plan/spec-template.md` — the 11-section spec schema the output conforms to.
