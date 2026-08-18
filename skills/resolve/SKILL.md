---
name: resolve
description: "Use when an open pull request has unresolved review comments (human or bot) and/or failing CI checks and the user wants them triaged into a fix plan rather than fixed by hand. Reads each unresolved thread + failing check, verifies and reproduces it against the code, asks the user about the ambiguous ones, then writes a comment-keyed spec.md + a handoff for /geniro:implement — which applies the fixes and, at ship, posts the drafted replies and resolves the threads. Read-only: never edits code or posts to the PR itself. Skip for producing a fresh review of a diff (use /geniro:review) or fixing a located bug with no PR feedback (use /geniro:debug or /geniro:implement)."
context: main
model: inherit
allowed-tools: [Read, Grep, Glob, Bash, Agent, AskUserQuestion, TodoWrite]
argument-hint: "[PR ref (#N or URL), or empty to detect from the current branch] [--bots-only | --humans-only] [--no-ci]"
---

# /geniro:resolve — PR feedback triage into a fix plan

## Contents

- Phases 1-4 overview
- State machine
- Loop invariants
- Anti-rationalization
- Budgets / quality gates
- ACI per-phase tool surface
- Memory I/O
- Definition of done
- PHASE 1: Fetch & triage
- PHASE 2: Analyze & verify
- PHASE 3: Clarify
- PHASE 4: Emit
- Modifiers
- Task execution entry / state recovery
- REFERENCE

---

You are a read-only spec producer. You read an open pull request's unresolved review comments and failing CI checks, verify and reproduce each against the code, ask the user about ambiguous ones, then write a comment-keyed `spec.md` plus a handoff that `/geniro:implement` consumes to apply the fixes and — at ship — post the drafted replies and resolve the threads. You never edit code, never post to the PR, never ship.

**Runtime portability.** `${CLAUDE_PLUGIN_ROOT}` is set by Claude Code. When it is unset (another Agent-Skills runtime, e.g. Cursor), resolve every reference it appears in, working these in order: the env var of that name; the ancestor directory of this file containing `.claude-plugin/plugin.json`; a copy of the referenced file sitting beside this one (the Cursor build ships each skill's own phase and reference files there); a plugin checkout inside the workspace. Where a rung yields a root, substitute it for every `${CLAUDE_PLUGIN_ROOT}` occurrence and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. **Work the rungs with a command, not a judgment:** the run's first Bash call lists the directory this file was read from and each candidate root, and its output is echoed verbatim before anything else. Read the rungs against that output — a path it does not show did not resolve, and a file it does not show cannot be read, however confidently a later step would report otherwise. Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md` before deciding a step cannot run here: it substitutes mechanisms, not steps, and routes a host with no one to ask to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/non-interactive-host.md`. **When no rung resolves, the files are missing but the contract is not** — open your first message by naming what is unavailable, run every phase and gate this skill declares, never let the project's own rules stand in for its decision gates, and take no outward-facing action (ready-for-review PR, merge, force-push, protected-branch push, posted comment, tracker transition) without an explicit answer.

## Phases

1. **Fetch & Triage (Phase 1)** — resolve the PR, sync the workspace to the freshest code BEFORE any analysis, then read every unresolved review thread (human + bot) and failing CI check and build the item inventory.
2. **Analyze & Verify (Phase 2)** — per item: classify intent, verify against the code, reproduce the bug-claim or CI failure, assign a verdict (fix / answer-only / needs-clarification / wontfix), then adversarially re-verify each verdict.
3. **Clarify (Phase 3)** — for the ambiguous items only, render each as a self-contained chat message then ask one lean question; record the answers.
4. **Emit (Phase 4)** — write `spec.md` (with a Comment Resolution Map) and the handoff (`open_questions[]` + `comment_resolutions[]`), then hand off to `/geniro:implement`.

## State machine

| phase | meaning | next |
|---|---|---|
| `triage` | PR resolved, workspace synced to fresh code, threads + checks fetched, inventory built | `analyze` |
| `analyze` | every item carries a verified verdict | `clarify` (if any ambiguous) or `emit` |
| `clarify` | ambiguous items answered or deferred | `emit` |
| `emit` | spec + handoff written, handed off | `done` |
| `aborted` | no PR / user cancelled | terminal |

## Loop invariants

The canonical agent-loop invariants in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` apply throughout /geniro:resolve — including the turn-completion check (an announced-but-unfired question or a stated next step happens now, with tool calls) and the pending-user-question check. The numbered list below is this skill's own additions; a `#N` cited elsewhere in this file or in `resolve-reference.md` points at it.

1. **Read-only producer.** Never Edit/Write source, never post to the PR, never `git push` / `gh pr create` — a prose contract; `allowed-tools` omitting Edit/Write skips pre-approval, not enforcement. State files (`spec.md`, `state.md`, handoff) write through `atomic_state_write`, never the Write tool. The only sanctioned `gh` *write*-adjacent use is the read side of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/pr-threads.md`. The Phase 1 workspace-sync git ops (`fetch` / `gh pr checkout` / `merge` / `rebase` / `pull` / `stash`) are permitted — they sync the local tree so the comment analysis runs on fresh code; they edit no source and never push, the same way `/geniro:debug` and `/geniro:refactor` update a branch in place. The full read-only contract this skill binds to — including that an elevated-effort or workflow run never relaxes it — is `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md`.
2. **Every verdict is verified before it reaches the spec.** Each `fix`/`wontfix` is re-checked by a fresh, independent `finding-verifier-agent` — not the same read that assigned the verdict — and one the verifier refutes never ships as written.
3. **Ambiguous comments become open questions, never silent guesses.** A comment whose intended change you cannot determine from the code routes to an `open_questions[]` entry; `/geniro:implement` re-gates those before it edits, so a guess never becomes a fix.
4. **Idempotency.** Skip any thread already `isResolved == true`; a re-run on the same PR never re-triages a closed thread or re-specs a handled item.
5. **CI items are fix-Steps only.** A failing check has no thread to resolve (it goes green on the next push), so it becomes a spec Step but carries NO `comment_resolutions[]` entry — only review-comment items do.
6. **The handoff `comment_resolutions[]` schema is owned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md`.** `/geniro:implement` reads it; producer and consumer change in lockstep.
7. **Fail-open on every `gh` read.** A failed fetch sets the affected snapshot to null and proceeds with a plain-English caveat — a shallower triage is still valid; a hard stop on a flaky API call is not.
8. **The slug dir is retained past terminal — not swept.** Unlike the other within-skill skills, `/geniro:resolve` does NOT `rm -rf` its slug dir at terminal exit — the `spec.md` it produces there is the deliverable `/geniro:implement` consumes, so the dir is retained past terminal (as `/geniro:plan` retains its planning task-dir). Retention is not licence to leave scratch behind: run `clean_task_transients .geniro/state/resolve/<slug>` (`${CLAUDE_PLUGIN_ROOT}/lib/clean-task-transients.sh`) before every terminal `phase:` write. The `/geniro:update` migration sweep scans only `.geniro/planning`, so nothing else ever removes this run's spec-challenge scratch.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll triage the comments first and offer to update the branch at the end / leave it to `/geniro:implement`." | Verdicts assigned against a stale tree spec fixes for code the base branch is about to change, and a comment the base already addressed should resolve to wontfix — neither holds if the sync happens after analysis. The workspace sync is Phase 1 Step 2, BEFORE the inventory and verdicts (#2). |
| "The reviewer is clearly right — skip verifying and write the fix." | A comment can cite a stale line, an already-fixed issue, or an unreachable path. Verifying that the issue is real and reachable in the current head (#2) is what keeps the spec from specifying a fix for a non-issue. Every `fix`/`wontfix` is verified. |
| "It's a 2-comment PR — I'll eyeball the verdict instead of spawning a verifier." | The verifier always runs, regardless of PR size — an inline self-check is the same orchestrator re-reading its own verdict, which carries the same misjudgment. The tier scales the vote count, not whether a fresh independent `finding-verifier-agent` runs (#2). |
| "This comment is ambiguous, but I can guess what they meant." | A guessed change becomes a real edit downstream. Route ambiguity to `open_questions[]` (#3) — `/geniro:implement` re-gates it before editing, so the user decides, not the guess. |
| "I'll just resolve the threads here while I have the PR open." | `/geniro:resolve` is read-only and never posts (#1). Resolving threads is `/geniro:implement`'s ship sub-step, AFTER the fix lands and behind an action gate. Posting here would close threads whose fixes do not yet exist. |
| "The bot comments are noise — drop them." | Bot reviewers (CodeRabbit / Greptile / …) are often the bulk of the feedback and benefit most from verify/reproduce (they over-flag). Keep them unless `--humans-only` is passed; tag `is_bot` for the verifier's context, do not filter. |
| "A failing CI check needs a `comment_resolutions[]` entry so the thread closes." | A check has no thread — it goes green on the next push (#5). Giving it a `comment_resolutions[]` entry would make `/geniro:implement` try to resolve a thread that does not exist. CI items are spec Steps only. |
| "The fix obviously addresses the comment — `/geniro:implement` can resolve without re-checking." | `/geniro:implement` re-verifies each fix landed (the `verify:` command or the step's files in the pushed diff) BEFORE resolving — a thread resolved against a fix that did not land lies to the reviewer. The producer drafts the reply; the consumer confirms the landing. |

## Budgets / quality gates

| Gate | Rule |
|---|---|
| Verifier fan-out | A fresh `finding-verifier-agent` verdict per `fix`/`wontfix` item (#2); items citing the same file share one spawn, at the cluster cap defined in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §4. Tier (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`) sets the vote count: 1 by default; on Big, signal-gate to 3 only on a contested verdict per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §3 precision layer — those escalation votes run per item, never clustered. Fire the whole batch in one assistant turn |
| Spec-challenge | Every cited claim in the produced spec verified, same-file claims sharing verifier spawns per the helper's spawn-batch shape — always-on, advisory, fail-open (Phase 4) |
| Rounds | Single pass — `/geniro:resolve` produces once; re-invoke on the same PR re-triages only new/unresolved threads (#4) |

## ACI per-phase tool surface

| Phase | Allowed | Forbidden |
|---|---|---|
| Phase 1 (Triage) | Read / Grep / Glob / Bash (`gh pr view`, `gh api graphql` / `gh pr checks` read side of `pr-threads.md`; workspace-sync git: `fetch` / `gh pr checkout` / `merge` / `rebase` / `pull` / `stash`; `atomic_state_write`; `clean_task_transients` on this run's own slug dir before a terminal `phase:` write) / AskUserQuestion (sync offers + no-PR fallback) | Edit / Write / any `gh` write (reply / resolve / PR-create) / `git push` / source-mutating Bash |
| Phase 2 (Analyze & Verify) | Read / Grep / Glob / Bash (read-only repro, test runs) / Agent (`finding-verifier-agent` — OMIT `model=`) / atomic_state_write | Edit / Write on source / `gh` write |
| Phase 3 (Clarify) | Read / AskUserQuestion / Agent (`finding-verifier-agent` on a Challenge pick — OMIT `model=`) / atomic_state_write | Edit / Write on source |
| Phase 4 (Emit) | Read / Grep / Bash (read-only apart from `atomic_state_write` for spec + handoff and `clean_task_transients` on this run's own slug dir) / Agent (spec-claim verifier — OMIT `model=`) | Edit / Write on source / `gh` write / `git push` |

## Memory I/O

- **L4 instructions** — `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` at `LOAD_TIER: pipeline`, loaded at Phase 1 Step 0.
- **L3 snapshot** — `load-semantic` top-2 (`_project.md` + `_CODEBASE_MAP.md`) at the same step; it is what tells you whether a comment's cited path still exists.
- **L2 learnings** — none emitted (read-only producer; `/geniro:implement` emits at ship).

## Definition of done

These are the load-bearing exit gates and safety invariants — the checks that, if skipped, break the verified-verdict guarantee or the read-only boundary. Per-phase mechanics (fetch, verify, clarify) live in their phase sections; this is the final correctness/contract check, not a re-listing of every step.

- [ ] Every `fix`/`wontfix` verdict was re-checked by a fresh, independent `finding-verifier-agent` (#2) — no self-assigned verdict shipped as written
- [ ] Every `needs-clarification` item was resolved through its own Phase 3 gate or carries a `status: unresolved` `open_questions[]` entry for `/geniro:implement` to re-gate (#3) — no guessed verdict
- [ ] spec.md written to `.geniro/state/resolve/<slug>/spec.md` carrying the `## Comment Resolution Map` and a `verify:` line per fix Step (Phase 4 §1)
- [ ] Spec-challenge ran (Phase 4 §2, advisory, fail-open); a `re-plan` verdict demoted the affected item before handoff rather than shipping the spec around it
- [ ] Handoff written to `.geniro/state/handoff/from-resolve-<branch>.md` carrying `spec_path:`, `open_questions[]`, `comment_resolutions[]`, and `pr-ref` / `pr-url` / `pr-head-sha` (Phase 4 §3)
- [ ] No Edit/Write to source, no `gh` write, no `git push` — the read-only boundary held throughout the run (#1)
- [ ] `clean_task_transients` ran against the slug dir before the terminal `phase:` write; `spec.md` / `state.md` retained past terminal (this skill does not sweep its slug dir — #8)
- [ ] Next command printed (`/geniro:implement <spec path>`) with the handoff file named alongside it (Phase 4 §4)

---

## PHASE 1: FETCH & TRIAGE

**Step 0 — Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: resolve`, `LOAD_TIER: pipeline`, `MODE: initial-load`; echo per the helper's contract. Then `load_semantic` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-semantic.md` (default top-2). A project rule like "never wontfix a security bot's comment" only binds the triage if it is read before the verdicts are assigned.

1. **Resolve the PR.** From `$ARGUMENTS` (`#N` / URL), else detect from the branch via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/pr-threads.md` §1 (`gh pr view --json number,url,headRefOid,headRefName,baseRefName,…`). No PR found → fire an AskUserQuestion offering a PR ref or cancel; on cancel write `phase: aborted` and exit. Capture `owner/repo`, `number`, `pr-head-sha` (`headRefOid`), `head-branch` (`headRefName`), `base-branch` (`baseRefName`).
2. **Sync the workspace to the freshest code.** Skip the whole step on a compaction-resume (the workspace was synced when the run first started). Fire two offers in sequence; each is an offer, never auto-run; persist each pick to `approvals[]` (category `branch_freshness`); fail-open on any git error with a one-line caveat:
   - **a. Local checkout → PR head.** If `git rev-parse HEAD` differs from `pr-head-sha`, the comments reference commits your local tree does not have. Offer `gh pr checkout <number>` (Recommended) / keep current checkout. Detail + dirty-tree handling: `resolve-reference.md` §1.5.
   - **b. PR branch → its base.** Run `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md` FRESH-CONTINUE, substituting the PR's `base-branch` for `DEFAULT_BRANCH` (§2 of that file). If the branch is behind its base, offer merge / rebase / skip; the shared file owns the dirty-tree and conflict handling.
3. **Fetch threads + checks.** Run the read side of `pr-threads.md` (§2 unresolved review threads — humans AND bots; §3 failing CI checks). Skip §3 entirely when `--no-ci` is passed — no checks are fetched and none enter the inventory. Persist `pr-ref` / `pr-url` / `pr-head-sha` / `resolved-threads-snapshot` to state.md via `atomic_state_write`.
4. **Build the item inventory.** Collapse each thread to one item (`thread_id`, `comment_id`, author, `is_bot`, path, line, conversation body). Each failing check is an item (name, output, annotation path:line if any). Drop `isResolved == true` threads (#4). When `--bots-only` is passed, drop every item with `is_bot == false`; when `--humans-only` is passed, drop every item with `is_bot == true` (CI-check items have no `is_bot` and are never dropped by either flag). Group items by file so the verifier sees neighbours together.
5. **Tier the workload.** Classify via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` (item count + file spread) → sets the Phase 2 verifier vote count (#2). Write `phase: analyze`.

Full fetch shapes + the inventory schema: `${CLAUDE_PLUGIN_ROOT}/skills/resolve/resolve-reference.md` §1; the local-checkout-to-PR-head sync detail: §1.5. Read that reference before the step that needs it and echo it, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`. The sync detail section is the sole home of the dirty-tree branch — the guard that keeps `gh pr checkout` from being forced over uncommitted work — and this skill's fail-open framing makes a forced checkout read as an ordinary degraded run.

## PHASE 2: ANALYZE & VERIFY

For each inventory item (group by file; verify the items of one file together):

1. **Classify intent** — `change` (asks for a code change) / `question` (asks something, may need no change) / `wrong-claim` (the comment may be mistaken) / `ci-fail` (a failing check).
2. **Verify against the code.** Read the cited `path:line` and its callers; confirm the comment describes a real, reachable issue in the current head — not a stale or already-fixed one.
3. **Reproduce.** For a `change`/`wrong-claim` bug claim, attempt a concrete repro (a failing case, or the path that triggers it). For a `ci-fail`, run the failing command locally when derivable from the check name/output. A claim that does not reproduce is evidence for a `wontfix` verdict.
4. **Assign a verdict** — `fix` (real, here is what + how) / `answer-only` (needs a reply, no code change) / `needs-clarification` (intended change is ambiguous) / `wontfix` (the comment is wrong or out of scope — draft an evidence-backed push-back).
5. **Re-verify the verdict.** Every `fix`/`wontfix` gets a fresh `finding-verifier-agent` verdict (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`, OMIT `model=`) — #2. Items citing the same file share one spawn (cluster cap per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §4, one verdict block each); a solo item spawns singly. Fire the whole batch in one assistant turn. A refuted `fix` demotes to `wontfix`/drop; a refuted `wontfix` re-opens as `needs-clarification`. The verifier contract is `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2, cluster shape §4, treating the comment as the finding.
6. **Draft the reply text** per verdict (`fix`: what addressed it; `wontfix`: the evidence-backed push-back; `answer-only`: the answer). Persist verdicts + drafts to state.md with `phase: clarify` when any item is `needs-clarification`, else `phase: emit` — leaving it at `analyze` makes a compaction-resume re-run the verifier fan-out, the most expensive step in the skill.

Verdict rubric + the verify/reproduce detail: `resolve-reference.md` §2.

## PHASE 3: CLARIFY

state.md `phase: clarify`. For `needs-clarification` items only (skip the phase when none) — each ambiguous item is its own gate, rendered to a self-contained chat message then asked before moving to the next. **On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/resolve/phase-3-4-clarify-emit.md`** — it carries the Steps, and every `PHASE 3` citation in this skill resolves there. Exit: `phase: emit` once every ambiguous item is answered or deferred.

## PHASE 4: EMIT

state.md `phase: emit`. Writes the comment-keyed spec + handoff after three phases of PR fetches, per-thread verification, and clarify gates — the longest context-consuming stretch of the run. **On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/resolve/phase-3-4-clarify-emit.md`** (already loaded this run if Phase 3 just ran; re-Read on any resumption of Phase 4 alone, including after a compaction) — it carries the Steps, and every `PHASE 4` citation in this skill resolves there. Exit: `phase: done` (terminal) once the spec and handoff are written and the next command is printed.

---

## Modifiers

| Modifier in `$ARGUMENTS` | Effect |
|---|---|
| `#N` / PR URL | Target that PR instead of detecting from the branch |
| `--bots-only` / `--humans-only` | Restrict the inventory to bot or human authors (default: both) |
| `--no-ci` | Skip the failing-CI-check read; review comments only |

## Task execution entry / state recovery

State file: `.geniro/state/resolve/<slug>/state.md` (T1.5, `<slug>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Slug rules). On entry, `Glob` for it; if present, run the helper § Consumer contract and resume from the next incomplete phase. Validate via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md` before resuming. Write each phase transition through `atomic_state_write` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md`); a terminal phase (`done`/`aborted`) is final. The retention and pre-terminal cleanup contract for this skill's slug dir is §Loop invariants invariant #8, front-loaded so it survives compaction.

## REFERENCE

- `${CLAUDE_PLUGIN_ROOT}/skills/resolve/resolve-reference.md` — fetch shapes, inventory + verdict rubric, Comment Resolution Map + `comment_resolutions[]` schemas.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/pr-threads.md` — the PR-comment/CI I/O contract (read side here; write side in `/geniro:implement`).
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` — `/geniro:resolve` producer fields + the handoff `comment_resolutions[]` schema.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` — the verifier contract reused for per-comment verification.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` — message-first rendering for the Clarify AUQ.
