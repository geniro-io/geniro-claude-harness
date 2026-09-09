# /geniro:resolve — Phase 1: Fetch & triage

Phase body for `${CLAUDE_PLUGIN_ROOT}/skills/resolve/SKILL.md`. Read on entry to Phase 1, and again on any resumption of it, including after a compaction. The spine keeps the state machine, the loop invariants, the anti-rationalization table and the Definition of done — this file carries the Steps.

## Contents

- The Steps
- Where the fetch shapes and the inventory schema live

---

## The Steps

state.md `phase: triage`.

**Step 0 — Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: resolve`, `LOAD_TIER: pipeline`, `MODE: initial-load`; echo per the helper's contract. Then `load_semantic` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-semantic.md` (default top-2).

1. **Resolve the PR.** From `$ARGUMENTS` (`#N` / URL), else detect from the branch via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/pr-threads.md` §1. No PR found → fire an AskUserQuestion offering a PR ref or cancel; on cancel write `phase: aborted` and exit. Capture `owner/repo`, `number`, `pr-head-sha` (`headRefOid`), `head-branch` (`headRefName`), `base-branch` (`baseRefName`).
2. **Sync the workspace to the freshest code.** Skip the whole step on a compaction-resume (the workspace was synced when the run first started). Fire two offers in sequence; each is an offer, never auto-run; persist each pick to `approvals[]` (category `branch_freshness`); fail-open on any git error with a one-line caveat:
   - **a. Local checkout → PR head.** If `git rev-parse HEAD` differs from `pr-head-sha`, the comments reference commits your local tree does not have — and the fixes must land on the PR branch, not beside it. Offer `gh pr checkout <number>` (Recommended) / keep current checkout. Detail + dirty-tree handling: `resolve-reference.md` §1.5.
   - **b. PR branch → its base.** Run `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md` FRESH-CONTINUE, substituting the PR's `base-branch` for `DEFAULT_BRANCH` (§2 of that file). If the branch is behind its base, offer merge / rebase / skip; the shared file owns the dirty-tree and conflict handling.
3. **Fetch threads, comments + checks.** Run the read side of `pr-threads.md` (§2 — unresolved review threads, the formal reviews' summary bodies, and the conversation-tab comments, humans AND bots; §3 failing CI checks). Skip §3 entirely when `--no-ci` is passed. When §2 reports the conversation tab truncated, carry that forward as a partially-read surface (#9) rather than a clean fetch. Persist `pr-ref` / `pr-url` / `pr-head-sha` and the `feedback-snapshot` from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/pr-threads.md` §2.5 to state.md via `atomic_state_write`.
4. **Build the item inventory.** Four authored surfaces become items, per the build rules in `resolve-reference.md` §1: a review thread collapses to one item (`thread_id`, `comment_id`, author, `is_bot`, path, line, conversation body); a conversation-tab comment the same way, minus the thread id it has none of; a formal review's summary body the same way again, for whatever its own inline threads do not already carry; and each failing check (name, output, annotation path:line if any). Drop `isResolved == true` threads (#7). `--bots-only` keeps only items whose `is_bot` is true and `--humans-only` only those where it is false; a CI check has no author, so neither flag drops one. Group items by file so one read of a file serves every item on it.
5. **Tier the workload.** Classify via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` (item count + file spread) → sets the verifier vote count on a contested call (#3). Write `phase: decide`.

## Where the fetch shapes and the inventory schema live

Full fetch shapes + the inventory schema: `${CLAUDE_PLUGIN_ROOT}/skills/resolve/resolve-reference.md` §1; the local-checkout-to-PR-head sync detail: §1.5. Read that reference before the step that needs it and echo it, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`. Never force `gh pr checkout` over uncommitted work — §1.5 owns that branch, and this skill's fail-open framing would otherwise make a forced checkout read as an ordinary degraded run.
