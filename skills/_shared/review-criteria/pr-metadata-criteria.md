# PR metadata review criteria

Quality checks for the **PR's own title and description** (the other dimensions review the code diff): does the author's prose say what changed and why, and does it match what changed? Fires only when `pr-ref != none`.

## What to check

1. **Title — imperative verb opener.** "Add user authentication", "Fix race in queue worker". Past tense ("Added"), gerund ("Adding"), or no verb at all describes a topic, not a change.
2. **Title — convention conformance.** Sample the last 10 commit titles (`git log --pretty=format:'%s' -10`, no `--merges`). When ≥7 share a prefix pattern (`feat:` / `fix:` / `[ENG-123]`), the repo uses a convention and a deviating title is flagged; below 7, skip — never invent a convention the repo does not follow.
3. **Description — substance.** Not empty, not a raw template skeleton, not under 3 sentences when the diff exceeds 20 LOC.
4. **Description — the why.** A non-trivial diff (>20 LOC) says why it is made — a "because", "to fix", or motivation heading. A trivial fix's title is its own why.
5. **Evidence — logic change.** The test or console output that now passes, showing a before and after.
6. **Evidence — UI change.** Screenshots or a recording showing a before and after (UI files per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` §UI-file detection rule), or an explicit "no visual change".
7. **Evidence — API or contract change, with a breaking-change note.** The old and new shape of a public API, migration, config schema, or exported signature, and whether callers break.
8. **Scope alignment.** The described scope matches the diff's — "Fix typo in README" over a 500-LOC, 12-file diff diverges by more than one major area.
9. **Linked issue.** Sample `gh pr list --state merged --limit 5 --json title`; when ≥3 carry an issue ID (`#NNN`, `ENG-NNN`, `PROJ-NNN`, `Fixes` / `Closes` / `Resolves #NNN`), the repo uses tickets and a PR with none in title or body is flagged; below 3, skip (same rule: no convention, no finding). With a Linear ID in play:
   - Cited but `LINEAR CONTEXT = none — MCP fetch failed (fail-open)`: emit an `open_questions[]` entry (`source: pr-metadata`, `status: unresolved`, `question: "Linear ID ENG-NNN cited but not verifiable (MCP unavailable). Confirm the issue exists and matches the PR scope, or revise the PR title/body."`) and no finding — an MCP outage is not the author's fault.
   - Cited and context populated: a LOW finding when `pr.title` materially diverges from the issue title (different verb or surface); a `[ENG-123]` prefix alone is not divergence.
   - Repo expects Linear but `LINEAR CONTEXT = none — workflow not configured`: a `## Caveats` line — "Repo uses Linear (judging by its recent PR titles) but `.geniro/workflow/linear.md` not configured — run `/geniro:setup` to enable issue context fetch".
10. **Acceptance criteria when an issue is linked.** The description restates the criteria or confirms them ("Closes #123 — all ACs from the issue are covered").
11. **Description ↔ code drift on re-review.** On round 2+ the PR body often still describes the earlier diff. Compare the current title and body against the `PRIOR-ROUND PR BODY:` slot (`none — first review` on round 1: skip). Flag a claim and the code disagreeing: a behavior the prior body described, the current body drops, and the diff still has; a claim ("behavior X is unchanged") the inter-round diff falsified; a behavior added between rounds that neither body mentions. Name the claim, the code state, and the asymmetry.

## Common false positives

- **Draft PRs** (`isDraft`): skip 3, 4, 5, 6, 8 — incomplete by design; titles and the breaking-change note (7) still apply.
- **Bot and generated PRs** (`dependabot[bot]`, `renovate[bot]`, `github-actions[bot]`, release-please, changesets, semantic-release, a `chore: release X.Y.Z` title): templated prose; emit zero findings.
- **Reverts** (`Revert "` title or `This reverts commit <sha>`): skip 4, 5-7, 10. **Cherry-picks and backports** (`[backport]` / `Cherry-pick` title, or a cited parent PR): skip 4-8 and 10.
- **Force-pushed PRs** whose earlier body was substantive: skip 3 and 4.
- **Very small diffs** (<5 LOC, ≤2 files): skip 5-7 unless the diff touches an API surface, a migration, or a UI file.

Detection signals (`isDraft`, `author.login`, `labels`, title, body) arrive in your PR-metadata slot. When one is missing, resolve it with one read-only `gh pr view --json <field>` rather than guessing "not a bot PR"; when that fails too, name the classifier you could not evaluate.

## Severity tagging

Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1. **This dim emits LOW and nothing else** — §6 of that file puts documentation and PR-description findings at LOW, a missing field the repo's PR template marks REQUIRED included; lifting one higher is how a paper cut reaches the PR past the shared gate. LOW sits below the Phase 4.1 admission gate, so these land in `## Deferred — sub-threshold` and reach the user through the Action gate's deferred table — visible, off the PR by default, promotable by a user pick. Never score one higher to clear the bar.

A body claiming behavior X is unchanged while the diff changes X is TWO findings: the description defect here (LOW) and the behavior change outside stated intent in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/regressions-criteria.md` §Severity tagging, anchored at the code where it clears admission.

## Output anchor

PR-metadata findings have no `path:lines`. Emit each with `File:` set to the literal string `PR-METADATA`, the standard reviewer-agent fields (Severity, Evidence, Why this matters, Suggested fix, Decision Type, Confidence), and `Evidence:` quoting the title or body fragment verbatim with a marker showing what is missing (e.g., "title: `Add stuff`"). The Post drill's comment composer (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §7.4) detects the `File: PR-METADATA` sentinel and routes these findings into the top-level review `body` of the `gh api` POST, never into the inline `comments[]` array.
