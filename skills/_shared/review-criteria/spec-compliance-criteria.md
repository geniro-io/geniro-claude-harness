# Spec compliance review criteria

Conformance audit of the diff **against the plan / spec**: what the spec asked for that the diff omits or gets wrong. The other dimensions own the diff's code quality. The spec is the **primary rubric** and the diff the side-input — the inverse of every other reviewer — but the spec is a fallible human artifact: a divergence can mean the diff is wrong OR the spec is (§Spec-premise validation).

This dimension fires whenever PLAN CONTEXT is non-`none`, PR or not. With no PR there is no PR body or metadata: treat PR-body and PR-metadata evidence as absent, accept commit messages (`git log` over the reviewed range), code comments, or docs in its place, and apply the draft / bot-author / revert bullets of §Common false positives only when the PR metadata exists. The `[ALIGNS-WITH-PLAN]` / `[DIVERGES-FROM-PLAN]` tags of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-context.md` do not apply — findings here are inherently divergences.

## Contents

- schema-aware mode
- LINEAR CONTEXT supplement (workflow integration)
- Spec-premise validation
- What to check
- Common false positives
- Severity tagging
- Cross-PR scope split (peer-PR context)
- Output anchor

---

## schema-aware mode

A spec.md with `geniro_kind: design-doc` and `geniro_schema_version` `m5-v1` through `m5-v4` arrives **section-tagged**: 1 Objective, 2 Scope — Included, 3 Scope — Excluded, 4 Assumptions, 5 Risks, 6 Steps, 7 Tools Required, 8 Approval Points, 9 Validation, 10 Rollback-Recovery, 11 Done Condition, plus the frontmatter goal-state block. In section 4, a `pending: <owner> — …` line is an open decision awaiting its owner, not a claim about the code; check it against nothing in the diff. Every finding cites the section (or frontmatter field) it rests on.

**Prose fallback:** when frontmatter is absent, run every check except the Done Condition (check 10) and Tools Required ones — there is no section anchor to cite. State it in your report — `Coverage: prose mode — Done Condition and Tools Required checks skipped, no section anchor to cite` — so the orchestrator lands a `## Caveats` line. Never an `open_questions[]` entry: the answer changes nothing the review posts (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2).

## LINEAR CONTEXT supplement (workflow integration)

When the `LINEAR CONTEXT:` slot is non-`none`, the Linear issue's **Acceptance Criteria** act as a rubric ON TOP OF section 9. Both sources present: merge them into one rubric; a conflict between them is a dedicated HIGH finding citing both verbatim. Linear ACs only: they become the sole rubric for check 4. PLAN CONTEXT only (no Linear, or the fetch failed): unchanged, with the Phase 1 fail-open caveat in `## Caveats`. A Linear-AC finding's title starts "Linear AC: " and its `Evidence:` quotes the block verbatim: `LINEAR CONTEXT Acceptance Criteria, item 2: "API returns 404 when user not found"`.

## Spec-premise validation (classify the divergence before assigning blame)

Each candidate finding is a divergence, and its two possible causes route to opposite outcomes — classify BEFORE emitting. Ground the check in live code (Read / Grep / Bash), not the spec's own words: **is the spec's premise still true in the codebase?**

- **Grounded departure** (the live code contradicts the premise and the diff's choice is correct): a **spec-defect, not a code omission**.
  - **Decision Type** `[INTENT-CHECK]` — the user decides whether to fix the spec or the code; never `[FIX-NOW]` against a working implementation. **Severity** capped at MEDIUM.
  - **Title:** "spec may be stale: `<spec premise>` is contradicted by `<code reality>`", never "diff omitted X".
  - **Evidence:** TWO live-code facts with `file:line` — (1) what contradicts the premise, AND (2) what shows the departure is the *correct* response, not merely that the premise is stale — plus the spec fragment. (1) without (2) is inconclusive, not a spec-defect.
  - **Also emit an `open_questions[]` entry** (`source: spec-compliance`, `status: unresolved`) so the decision gates the handoff — an `[INTENT-CHECK]` tag alone fires no gate: "Spec premise `<premise>` is contradicted by `<code reality>` (`file:line`); the diff correctly departed. Decide: fix the spec, change the code to match the spec, or accept the divergence."
- **Ungrounded departure** (the premise holds and the diff skipped a still-valid item or contradicts it): the standard finding at normal severity — also when the grounding is inconclusive, with the uncertainty noted in `Evidence:`.

## What to check

Quote the spec line for each finding. Report: (a) requirements the spec asked for that are missing or partial; (b) requirements that look implemented but where the implementation looks wrong — presence is not compliance: a wrong status code, an inverted default, a boundary handled differently than the criterion states. Quote the hunk beside the spec line.

A requirement includes the artifacts it implies, when the spec commits to them: a scoped file, module, or endpoint the diff never touches (section 2); a schema change's migration and, for a data-mutating one, a rollback path; flag wiring for a flag-gated rollout; a config or env entry for a new setting; a documented deploy order when several writers change; observability for a named operational concern; a boundary test or Before/After for a stated semantic shift; tests for acceptance criteria (check 4); the enabling artifact of the Done Condition (check 10); and the tools section 7 requires — a CLI binary checked with a read-only `which`, a library in the package manifest; an MCP connector or service endpoint is informational only.

### 4. Tests for stated acceptance criteria

Extract the criteria from PLAN CONTEXT (section 9, an `## Acceptance criteria` list, numbered AC lines, "must" / "should" bullets). Per criterion, derive 2–4 keyword anchors (verbs, entities, error conditions) and grep the diff's test files, then the existing suite when none match. A keyword match is a lead, not coverage, and is scoped to the matching case, not its file — an old case in a file the diff otherwise edits is still unchanged. A match inside a case the diff ADDS or MODIFIES counts once reading its assertion confirms it checks the criterion; a match inside an unchanged case counts only when the criterion restates behavior the diff keeps (not introduces or changes) AND reading its assertion confirms it — cite it (`file:line`) as a dimension-summary note, not a finding. Flag a criterion that introduces or changes behavior with no new or modified test, or restates kept behavior with no confirmed match anywhere in the suite.

### 10. Done condition met

Schema-aware mode only. Classify section 11's signal against `${CLAUDE_PLUGIN_ROOT}/skills/_shared/done-condition-check.md` §"Stopping-condition ontology", so this check and the ship-time annotation read a clause identically. Flag when it names an observable signal AND the diff carries no **enabling artifact** — the instrumentation, flag, migration, or test the clause depends on. The line is whether the diff could have contained the missing thing.

**Do not flag a clause purely because reading it needs a deployed system.** An outcome clause names a production value and a window ("the dashboard metric shows p95 under 400ms, one week after rollout"), as do a human approval and a post-release observation; no diff can carry that reading, so flagging it reports the criterion's own design as a defect in the change.

## Common false positives

- **Draft PRs** (`isDraft` true): incomplete scope is expected. Report only structural gaps (missing scoped item, migration, rollback) and behavior the draft already wrote that contradicts the spec.
- **Exploratory plans** (PLAN CONTEXT carries "TBD", "TODO", "follow-up", "out of scope", "future work", "tentative", "phase 2 will" near the scoped item): the plan did not commit to the scope. Downgrade findings on the deferred item one level, never below LOW; one that would fall past LOW is dropped.
- **Bot-author PRs** (`dependabot[bot]`, `renovate[bot]`, `release-please[bot]`, `github-actions[bot]`, `changesets[bot]`, or a similar automation account): the rubric does not apply; emit zero findings.
- **Trivial PRs** (<20 LOC AND one file): scope-completeness, deploy-order, observability, Done Condition, and tools expectations do not apply; the other checks fire only when their precondition visibly appears.
- **One slice of a multi-PR plan** (PLAN CONTEXT enumerates the PRs and the PR body cites its slice): restrict scope completeness to that slice.
- **Reverts and cherry-picks** (title begins `Revert "`, `Cherry-pick`, or `[backport]`): the spec is the parent change; skip unless the revert or backport introduces new scope.

The detection signals (`isDraft`, `author.login`, `labels`, title, body) arrive in your PR-metadata slot. When one is missing, resolve it with one read-only `gh pr view --json <field>`; when that fails too, name the classifier you could not evaluate.

## Severity tagging

Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1 — this dim's CRITICAL tier stays exactly §1's inclusion list (§6).

- **CRITICAL** — a data-mutating migration with no rollback path (§1's data-loss-path class by name).
- **HIGH** — a scoped item missing from the diff; a committed artifact absent (migration, flag wiring, deploy order, config entry, Done Condition artifact, required tool, boundary assertion for a fail-closed semantic shift); an implementation contradicting the spec's stated behavior with the departure not grounded in live code.
- **MEDIUM** — an acceptance criterion with no test; an operational concern with no observability; a consideration the diff only partially addresses; a semantic shift tested at its boundary but with no Before/After in the body.

Emit nothing for items the plan did not commit to: PLAN CONTEXT is the rubric, and a finding is valid only when the missing artifact traces verbatim to a plan fragment quoted in `Evidence:`. Apply the §Common false positives downgrades before tagging; a spec-defect under §Spec-premise validation overrides the severity above.

## Cross-PR scope split (peer-PR context)

When `PEER-PR CONTEXT:` is non-`none` AND LINEAR CONTEXT shows a parent epic with sibling sub-tasks (or PLAN CONTEXT enumerates a multi-PR plan), check scope completeness **against the slice this PR owns**; a sibling's items are not omissions. Emit one `open_questions[]` entry (`source: spec-compliance`, `status: unresolved`): "Parent epic ENG-100 has scope items A, B, C. This PR covers B; sibling PR #N covers A. Item C is unassigned — confirm whether C is in scope here, deferred to another sub-task, or out of scope." It gates a scope decision, so it is not a HIGH finding. When the current and peer PRs together cover every parent item, add a one-line `## Caveats` note ("Parent epic ENG-100 fully covered by [current + peer-PR list].") and no entry.

## Output anchor

Spec-compliance findings have no `path:lines`. Emit each with:
- `File:` set to the literal string `SPEC-COMPLIANCE`.
- All other reviewer-agent output fields per the standard template (Severity, Evidence, Why this matters, Suggested fix, Decision Type, Confidence).
- `Evidence:` quoting the plan fragment verbatim with a brief marker (e.g., "plan section: `## Acceptance criteria`, AC3: `…`") AND naming the missing artifact in the diff (e.g., "no file under `migrations/` in the changed-files list").

The Post drill's comment composer (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §7.4) detects the `File: SPEC-COMPLIANCE` sentinel and routes these findings into the top-level review `body` of the `gh api` POST under `## Spec Compliance`, never into the inline `comments[]` array, which needs a path-anchored line.
