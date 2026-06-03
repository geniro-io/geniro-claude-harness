# PR Metadata Review Criteria

Quality checks for the **PR's own title and description** (not the code diff). The diff is reviewed by the other diff-anchored dimensions; this dimension audits the prose authored by the PR creator — clarity, completeness, expected sections, and alignment with what actually changed.

This dimension fires only when input is a PR ref (`pr-ref != none`); it is skipped for local files, branches, or diff ranges. The reviewer emits findings without a `path:lines` anchor — the orchestrator routes them into the top-level review `body` field of the `gh api` POST in Phase 6, not as inline comments.

## Contents

- What to Check
- Common False Positives
- Severity Tagging
- Output Anchor

---

## What to Check

### 1. Title — Imperative Verb Opener

A PR title should describe an action: "Add user authentication", "Fix race in queue worker", "Drop dead config option". Past-tense ("Added X", "Fixed Y") and noun-only titles ("User authentication", "Queue race") are weaker — they describe a topic, not a change.

**How to detect:**
- Read `pr.title` from the PR-metadata slot in the prompt.
- Check that the first word (after any prefix like `[ENG-123]` or `feat:`) is an imperative verb: Add, Fix, Drop, Remove, Replace, Refactor, Update, Move, Rename, Introduce, etc.

**Red flag:** title starts with past-tense ("Added", "Fixed", "Updated"), gerund ("Adding", "Fixing"), or no verb at all.

### 2. Title — Convention Conformance (when repo uses one)

Many repos adopt Conventional Commits (`feat:`, `fix:`, `chore:`) or Linear/Jira issue-id prefixes (`[ENG-123]`, `PROJ-456`). When the repo uses a convention, the PR title should follow it.

**How to detect:**
- Sample the project's last 10 merged-commit titles via `git log --merges --pretty=format:'%s' -10` (already in the agent's reachable scope).
- If ≥7 of the 10 follow the same prefix pattern, the repo uses a convention. Flag PR titles that deviate.
- If <7 of 10 follow a pattern, the repo does not enforce one — skip this check (do not invent a convention).

**Red flag:** repo's modal pattern is `^(feat|fix|chore|docs|refactor)(\(.+\))?: ` (≥7/10) and this PR's title lacks it.

### 3. Description — Presence and Substance

A PR description should be more than a one-line restatement of the title and should not be a raw template placeholder (e.g., GitHub's default `## Summary\n\n## Test plan\n` with no content filled in).

**How to detect:**
- Read `pr.body`. Check it is non-empty after trimming whitespace.
- Reject as substantive if the body matches a known-template skeleton (only `## Summary`, `## Test plan`, `## Screenshots`, etc., with no content under each heading).
- Reject as substantive if the body is < 3 sentences AND the diff is non-trivial (>20 LOC changed).

**Red flag:** empty body, or body is just the template skeleton, or body is < 3 sentences when the diff exceeds 20 LOC.

### 4. Description — "Why" Clause Present

The description should explain *why* the change is being made, not just *what* changed. Reviewers need motivation to evaluate trade-offs.

**How to detect:**
- Scan the body for "why" signals: words like "because", "to fix", "to address", "motivation", "this enables", "users were", or an explicit "## Why" / "## Motivation" / "## Context" heading.
- If none present, flag as missing-why. Note: a clear bug-fix title ("Fix off-by-one in pagination") IS the why for trivial fixes (<20 LOC); skip this check for trivial diffs.

**Red flag:** non-trivial diff (>20 LOC) with no "because" / "to fix" / motivation heading anywhere in the body.

### 5. Description — Test Plan When Logic Changed

When the diff touches non-trivial business logic (controllers, services, models, reducers, query handlers) or includes test files, the description should describe how the change was tested.

**How to detect:**
- From `DIFF CONTEXT`, count files matching `src/**/{controllers,services,models,reducers,handlers}/*` and files matching `**/*.{test,spec}.*` / `**/__tests__/**` / `tests/**`.
- If either count ≥1, scan the body for a "## Test plan" / "## Testing" / "## How to test" heading OR bulleted test-step content ("- ran `pytest …`", "- verified in browser").
- Flag when logic-or-test files changed AND no test plan is mentioned.

**Red flag:** ≥1 logic or test file changed; body contains no test-plan heading or bulleted test evidence.

### 6. Description — Screenshots When UI Changed

When the diff includes UI files (matching the UI-file detection rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` §UI-file detection rule), the description should include screenshots, recordings, or a "no visual change" note.

**How to detect:**
- From `DIFF CONTEXT`, count files matching the UI-file globs (`**/components/**`, `**/pages/**`, `**/app/**`, `**/views/**`, `**/ui/**`) or extensions (`.tsx`, `.jsx`, `.vue`, `.svelte`, `.css`, `.scss`, `.styled.ts*`).
- If ≥1 UI file changed, scan the body for: markdown image syntax (`![...](...)`), GitHub video attachments (`https://github.com/user-attachments/`), explicit "no visual change" sentence, or "## Screenshots" / "## Demo" heading with content.
- Flag when UI files changed AND no visual evidence is present.

**Red flag:** ≥1 UI file in the diff; body contains no image, no video, and no "no visual change" disclaimer.

### 7. Description — Breaking-Change Note When API/Contract Changed

When the diff changes a public API, a database migration, a config schema, or an exported function signature, the description should call out backward-incompatibility explicitly.

**How to detect:**
- From `DIFF CONTEXT`, look for: removed exports (`-export`), modified function signatures in `*.d.ts` / `*.proto` / OpenAPI specs, files under `migrations/` / `db/migrations/`, `package.json` removed dependencies, breaking-change markers in commit messages.
- If any present, scan the body for an explicit heading or callout: "## Breaking changes", "**BREAKING:**", "⚠️ migration required", or "backward-incompatible".
- Flag when such changes appear in the diff AND no breaking-change note exists.

**Red flag:** signature/migration/exported-API change visible in the diff; body silent on backward compatibility.

### 8. Description — Scope Alignment

The description should match the actual scope of the diff. A title saying "Fix typo in README" with a 500-LOC diff across 12 source files is a scope mismatch; a description that lists 5 unrelated changes when the diff only touches 1 of them is a scope-creep signal.

**How to detect:**
- Compare the description's enumerated changes (bullet lists, "## What changed" sections) against `DIFF CONTEXT`'s file list.
- If the description mentions 3+ items not visible in the diff, flag as overpromised.
- If the diff has 3+ distinct modules changed but the description names only one, flag as underpromised (likely sneaks).

**Red flag:** description's claimed scope and diff's actual scope diverge by more than one major area.

### 9. Linked Issue or Ticket

When the repo uses an issue tracker (Linear / Jira / GitHub Issues / Pivotal), most PRs should link to the issue they implement or fix.

**How to detect:**
- Check `pr.title` and `pr.body` for: `#NNN` (GitHub), `[ENG-NNN]` or `ENG-NNN` (Linear), `[PROJ-NNN]` or `PROJ-NNN` (Jira), GitHub `Fixes #NNN` / `Closes #NNN` / `Resolves #NNN` keywords.
- Sample 5 recently merged PR titles via `gh pr list --state merged --limit 5 --json title` (when reachable). If ≥3 of them carry an issue ID, the repo uses tickets — flag PRs without one.
- If <3 of 5 carry IDs, the repo does not enforce ticketing — skip this check.

**Red flag:** repo's modal pattern includes issue IDs (≥3/5 sampled) and this PR's title+body together contain none.

**LINEAR CONTEXT enhancement (workflow integration):** when the `LINEAR CONTEXT:` slot is non-`none`, the ticket ID was both detected by regex AND verified to exist via MCP fetch. Use this to distinguish two failure modes:

- **ID in title/body but LINEAR CONTEXT = `none — MCP fetch failed (fail-open)`**: emit a structured `open_questions[]` entry with `source: pr-metadata`, `status: unresolved`, `question: "Linear ID ENG-NNN cited but not verifiable (MCP unavailable). Confirm the issue exists and matches the PR scope, or revise the PR title/body."`. No finding emitted (MCP outage isn't the author's fault). The orchestrator's Phase 6 gate will require user resolution before action-gate fires.
- **ID in title/body AND LINEAR CONTEXT populated**: cross-check pr.title against `LINEAR CONTEXT.Title`. If pr.title diverges materially from issue title (different action verb / different surface area), flag as a MEDIUM finding: "PR title `<pr-title>` materially diverges from Linear issue title `<linear-title>` — verify PR addresses the right scope". Pure prefix differences (`[ENG-123]` ahead of pr-title) are NOT divergence.
- **Repo modal expects Linear AND LINEAR CONTEXT = `none — workflow not configured`**: surface a one-line informational note in `## Caveats` — "Repo uses Linear (per modal sampling) but `.geniro/workflow/linear.md` not configured — run `/geniro:setup` to enable issue context fetch".

### 10. Description — Acceptance Criteria When Issue Linked

When the PR links an issue, the description should either restate the acceptance criteria or explicitly confirm them ("Closes #123 — all ACs from the issue are covered").

**How to detect:**
- If check #9 found a linked issue, scan the body for: "## Acceptance criteria" / "## ACs" headings, bulleted criteria lists, or explicit closure language naming the criteria ("Implements #123 — UI now matches mockup at width X").
- Flag when an issue is linked AND no acceptance criteria appear AND the description is < 5 sentences.

**Red flag:** linked issue ID is present; description is terse and contains no acceptance-criteria restatement or coverage confirmation.

### 11. Description ↔ Code Drift on Re-Review

On a re-review (round 2+ of human review on the same PR), the PR body often describes the EARLIER diff before fixes pushed in response to round 1. The body claims a behavior that the code no longer has, OR omits a behavior the code now has. The scope-alignment check (#8) above compares body vs CURRENT diff in a single pass; this check adds the cross-round dimension by comparing CURRENT body to the prior-run body persisted by the orchestrator.

The Phase 5 state file at `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` carries `pr-body: <verbatim PR body>` in frontmatter (see `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` Phase 5 state-schema). On re-review, the orchestrator's Phase 1 Step 0.5 reads it before overwriting; this reviewer compares against it. SKILL.md also reads `.geniro/state/review-findings-state.md` once on Phase 5 entry if present for resume safety; write always lands at the path.

**How to detect:**
1. From the orchestrator-pre-inlined `PRIOR-ROUND PR BODY:` slot (added on round 2+; renders as `none — first review` on round 1 or when the prior-run state file has no `pr-body:`), check if a prior PR body is present.
2. If `PRIOR-ROUND PR BODY: none — first review`, skip this check entirely (no drift possible without a prior round).
3. Diff the current `pr.title` + `pr.body` (from the standard PR METADATA slot) against the prior `pr-body:` text. Identify clauses present in EITHER version but materially different:
- **Claim removed**: the prior body described a behavior X (e.g., "fast path skips when X != null"); the current body no longer mentions X. Check whether the diff still has the behavior — if yes, the current body silently omits a still-real behavior; if no, the body correctly reflects the fix and no drift exists.
- **Claim still present but no longer true**: the prior body said "behavior X is unchanged" AND the current body still says "behavior X is unchanged"; the diff between rounds shows X was actually changed in response to round 1.
- **New behavior in diff, no claim in body**: the diff adds behavior Y between rounds; neither the prior nor current body mentions Y.
4. For each material drift, surface as a finding describing the specific claim, the specific code state, and the asymmetry between them.

**Red flag:** PR body claims `<behavior X>` is `<unchanged | fast-path | removed>`; the current diff (or the inter-round diff) shows `<behavior X>` was actually `<changed | reinstated | added>` in response to a prior round of review.

**Severity:** MEDIUM — drift undermines reviewer trust but rarely changes correctness of the code itself. Elevate to HIGH when the drifted claim is load-bearing for understanding the diff's semantic impact (e.g., "fast path is unchanged" was true round 1, false round 2 — round-3 reviewers reading the body get a wrong mental model).

## Common False Positives

Skip or downgrade findings in these cases — they look like rubric violations but are routine PR patterns the rubric is not designed to flag:

- **Draft PRs** (`gh pr view --json isDraft` returns `true`): description and test plan are often incomplete by design while the author iterates. Skip checks #3 (substance), #4 (why clause), #5 (test plan), #6 (screenshots), #8 (scope alignment). Still flag #1 (imperative verb), #2 (convention prefix), and #7 (breaking-change note if API/migration changed) — these apply regardless of draft state.
- **Dependabot / Renovate / similar bot PRs** (author user matches `dependabot[bot]` / `renovate[bot]` / `github-actions[bot]` / a known dependency-bumper bot — check `gh pr view --json author --jq.author.login`): titles and bodies are templated and the rubric's prose expectations do not apply. Skip every check; emit zero findings.
- **Revert PRs** (title begins with `Revert "` or body contains `This reverts commit <sha>`): the description is auto-generated by GitHub's revert button and typically lacks a custom "why" or test plan because the change is mechanical. Skip checks #4 (why), #5 (test plan), #6 (screenshots), #10 (acceptance criteria). Flag #7 (breaking-change note) only if the reverted change is a breaking-change reversal.
- **Cherry-pick or backport PRs** (title begins with `[backport]` / `Cherry-pick` / `[cherry-pick]` or body cites a parent PR): description quality is delegated to the parent PR. Skip checks #4–#8 and #10 when a parent PR is cited; still flag #1, #2, #9.
- **Force-pushed PRs** where the body was substantive on an earlier push (detect via `gh pr view --json reviews` — if there are review comments referencing earlier content, the description may have been condensed after the prior review): downgrade severity by one level (CRITICAL → HIGH, HIGH → MEDIUM) for checks #3, #4. The author already engaged the prior reviewer; rubric-strict re-flagging is noise.
- **First-review runs** (no prior `pr-body:` in the state file because this is the first `/geniro:review` invocation against this PR): Skip entirely; it has nothing to compare against. The check fires only on round 2+ re-reviews. This is the normal case; do not emit a "no drift to check" finding.
- **Generated PRs** from automation (release-please, changesets, semantic-release, project-board automation): bodies are formulaic and the rubric does not apply. Detect via author user, title patterns (`chore: release X.Y.Z`, `Release v…`), or the presence of `release-please` / `changeset` labels. Skip every check.
- **Very small diffs** (<5 LOC AND ≤2 files changed): the rubric's structural expectations (test plan, screenshots, breaking-change note) often do not apply. Skip checks #5 (test plan), #6 (screenshots), #7 (breaking-change) unless the diff visibly touches an API surface / migration / UI file. Still flag #1 (imperative verb) and #3 (substance) if the body is empty.
- **"PR description could be more verbose" → never MEDIUM** — Suggestions to add more context, link more tickets, or include checklists are LOW. MEDIUM requires the missing field to be documented as REQUIRED in the repo's PR template or CONTRIBUTING.md, AND the omission must materially mislead reviewers.

The detection signals above come from `gh pr view --json isDraft,author,title,body,labels` — the same call already issued at SKILL.md Phase 1 "Parse input" — so no additional API roundtrip is needed.

## Severity Tagging

Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/review/severity-calibration-reference.md` §1.

- **CRITICAL** — PR title misrepresents the diff (title says "refactor", diff adds new feature); PR body empty when repo CONTRIBUTING.md requires non-empty; PR description claims behavior X is unchanged while diff demonstrably changes X.
- **HIGH** — Missing test-plan section when test files are modified; missing screenshots when UI files changed; missing breaking-change note when an exported API signature changed.
- **MEDIUM** — Missing REQUIRED field per repo's PR template (e.g., the template demands a `## Risk` section and the body omits it). The field must be in a documented template, not inferred. Scope mismatch where the diff covers a materially different feature than the title claims (e.g., title "fix bug" but diff adds 200 lines of new feature code).
- **LOW** — PR description verbosity suggestions ("add the linked Linear ticket", "include a short rationale", "mention the sunset checklist"); commit-message-format suggestions; optional-field additions; title-format polish (capitalization, prefix conventions); convention drift on non-required fields.

Do not emit findings for repos that demonstrably do not follow a given convention (modal-pattern detection rules in checks #2 and #9 must show the repo uses the convention before flagging deviations).

## Output Anchor

PR-metadata findings have no `path:lines`. Emit each finding with:
- `File:` field set to the literal string `PR-METADATA` (no path, no line number).
- All other reviewer-agent output fields per the standard template (Severity, Cause, Evidence, Why this matters, Suggested fix, Decision Type, Confidence).
- `Evidence:` quotes the relevant fragment of the title or body verbatim, with a brief surrounding-prose marker so the reader sees what was missing (e.g., "title: `Add stuff`" or "body section: `## Test plan` heading present but empty").

The Phase 6 Post drill's Step 4 composer (`${CLAUDE_PLUGIN_ROOT}/skills/review/phase-6-handoff-reference.md` §7.5) detects the `File: PR-METADATA` sentinel and routes these findings into the top-level review `body` field of the `gh api` POST, NOT into the inline `comments[]` array (which requires a path-anchored line).
