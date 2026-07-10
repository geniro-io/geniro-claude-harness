# Spec Compliance Review Criteria

Conformance audit of the diff **against the plan / spec** — what the spec promised but the diff omits (checks 1-11), and what the diff implements contrary to the spec's stated behavior (check 12). The diff's code quality (correctness, security, architecture, tests, optimizations, guidelines, conventions, design) is owned by the other reviewer dimensions; this dimension owns SPEC→DIFF conformance only. The spec is the **primary rubric** for what the change intended; the diff is the side-input — the inverse of every other reviewer, which is diff-anchored. But the spec is a fallible human artifact, not ground truth: a divergence between spec and diff can mean the diff is wrong OR the spec is wrong. Before flagging an omission or contradiction as a defect against the implementation, rule out that the code deliberately and correctly departed from a spec premise the live code contradicts (see §Spec-premise validation) — otherwise a correct implementation gets blamed for the spec's own error.

This dimension fires conditionally: PLAN CONTEXT must be non-`none` AND either the input is a PR ref OR the change carries `risk-tier: high`. It is skipped for local files, branches, or diff ranges with no plan context attached. The reviewer emits findings without a `path:lines` anchor — the orchestrator routes them into the top-level review `body` field of the `gh api` POST in Phase 6, alongside PR-METADATA findings under a dedicated `## Spec Compliance` section, not as inline comments. The plan-context tagging convention in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-context.md` (`[ALIGNS-WITH-PLAN]` / `[DIVERGES-FROM-PLAN]`) does not apply here — findings in this dimension are inherently divergences, so the tag is implicit.

## Contents

- schema-aware mode
- LINEAR CONTEXT supplement (workflow integration)
- Spec-premise validation
- What to Check
- Common False Positives
- Severity Tagging
- Cross-PR Scope Split (peer-PR context)
- Output Anchor

---

## schema-aware mode

When the spec.md being audited carries `geniro_kind: design-doc` + `geniro_schema_version` of `m5-v1` OR `m5-v2` OR `m5-v3` OR `m5-v4`, PLAN CONTEXT is delivered as a **section-tagged blob** with 11 named sections per the schema (plus the frontmatter goal-state block; `m5-v2` and `m5-v3` additionally surface `workflow_refs[]` if present, `m5-v3` enriches each entry with parent-epic + sibling chain fields, and `m5-v4` adds the optional `launch_config` block):

- Section 1: Objective
- Section 2: Scope — Included
- Section 3: Scope — Excluded
- Section 4: Assumptions
- Section 5: Risks
- Section 6: Steps
- Section 7: Tools Required
- Section 8: Approval Points
- Section 9: Validation
- Section 10: Rollback-Recovery
- Section 11: Done Condition

Findings MUST cite the specific section (or frontmatter field) violated/missing — e.g., `Evidence: section 2 (Scope.Included) names "src/api/auth/*" but diff touches no auth file`. The 11 checks below name the canonical section anchors.

**Prose fallback:** when frontmatter is absent (unstructured PLAN CONTEXT), run checks 1-9 and 12. Skip checks #10 (Done Condition) and #11 (Tools Required) — there's no section anchor to cite. Emit a structured `open_questions[]` entry with `source: spec-compliance`, `status: unresolved`, `question: "PLAN CONTEXT lacks structured frontmatter — checks 10 (Done Condition) and 11 (Tools Required) skipped. Confirm whether these are covered out-of-band, or upgrade the spec/design doc to the structured schema."`.

## LINEAR CONTEXT supplement (workflow integration)

When the `LINEAR CONTEXT:` slot is non-`none` (workflow integration fetched a Linear issue per Phase 1), the Linear issue's **Acceptance Criteria** field acts as an additional rubric ON TOP OF PLAN CONTEXT section 9. Two-source reconciliation:

- **Both present (PLAN CONTEXT section 9 AND Linear ACs):** ACs from both sources are merged into a single rubric. Tests must reference behaviors from each. Conflicts (PLAN-AC1 contradicts Linear-AC1) are surfaced as a dedicated finding with severity HIGH, citing both sources verbatim.
- **Only Linear ACs present (no PLAN CONTEXT OR PLAN CONTEXT lacks section 9):** Linear ACs become the sole rubric. Apply check #4 (Tests for Stated Acceptance Criteria) against the Linear AC list.
- **Only PLAN CONTEXT present (no Linear OR Linear fetch failed):** unchanged from §What to Check rubric. The fail-open caveat from Phase 1 surfaces in `## Caveats`.

Findings from Linear-AC mismatches carry the prefix "Linear AC: " in the Cause field to distinguish from PLAN CONTEXT ACs (e.g., "Linear AC: ENG-123 specifies "API returns 404 when user not found"; no test asserts 404 path"). The `Evidence:` field quotes verbatim from the LINEAR CONTEXT block: `LINEAR CONTEXT Acceptance Criteria, item 2: "API returns 404 when user not found"`.

## Spec-premise validation (classify the divergence before assigning blame)

Every candidate finding below — an omission (checks 1-11) or a contradiction (check 12) — is a divergence between what the spec asked for and what the diff did. A divergence has two possible causes, and they route to opposite outcomes — classify which BEFORE emitting the finding. You have Read / Grep / Bash; use them to ground the check against the live code, not against the spec's own words.

For each candidate divergence, ask: **is the spec's premise still true in the current codebase?**

- Check whether the file / module / endpoint / entity / column / API the spec references still exists and still matches the spec's assumption. Examples of a contradicted premise: the spec says "update table `foo`" but `foo` was renamed to `bar` and the diff correctly updates `bar`; the spec says "add `/v1/x`" but the codebase standard moved to `/v2` and the diff adds `/v2/x`; the spec says "call `helper()`" but `helper` was deleted and the diff inlines its logic.

- **If the code's departure is grounded** (the spec premise is contradicted by the live code, and the diff's choice is the correct one given current reality), the divergence is a **spec-defect, not a code omission**. Emit it as:
  - **Decision Type:** `[INTENT-CHECK]` — the user decides whether to fix the spec or the code. Never `[FIX-NOW]` against the implementation; the implementation is not broken.
  - **Severity:** cap at MEDIUM (advisory). A stale spec is not a HIGH/CRITICAL code omission.
  - **Cause:** phrase as "spec may be stale: `<spec premise>` is contradicted by `<code reality>`", NOT "diff omitted X".
  - **Evidence:** cite TWO live-code facts, each with `file:line` — (1) the fact that contradicts the spec's premise, AND (2) the fact establishing the diff's departure is the *correct* response, not merely that the premise is stale. Quote the spec fragment alongside them. The second citation is the load-bearing guard against under-reporting: "the premise looks stale" is not enough to clear the implementation — you must show the omission is the right call. Cite (1) but not (2) → inconclusive (see below), not a spec-defect.
  - **Also emit a structured `open_questions[]` entry** (`source: spec-compliance`, `status: unresolved`) so the decision actually gates the handoff — an `[INTENT-CHECK]` tag alone surfaces the note in the PR body but fires no interactive decision gate. Phrase: "Spec premise `<premise>` is contradicted by `<code reality>` (`file:line`); the diff correctly departed. Decide: fix the spec, change the code to match the spec, or accept the divergence." This reuses the same channel as §Cross-PR Scope Split — same `open_questions[]` plumbing, same handoff gating.

- **If the code's departure is NOT grounded** (the spec premise still holds and the diff genuinely skipped a still-valid scoped item, or implemented it contrary to the stated behavior), emit the standard finding per §What to Check at its normal severity.

This is skip-when-clean: it only runs when a real divergence surfaces, and it never rewrites the spec — it flags the spec as possibly-wrong and routes the decision to the user via the `open_questions[]` gate above. When the grounding check is inconclusive (you cannot cite BOTH live-code facts — the premise contradiction AND the correctness of the departure), default to the standard finding per §What to Check but note the uncertainty in `Evidence:`.

## What to Check

### 1. Scope Completeness

The spec enumerates files, modules, endpoints, entities, or surfaces that the change must touch; the diff omits one or more of them. This is the most common spec-compliance gap: the spec said "update A, B, and C"; the diff updates A and B.

**schema cite:** section 2 (Scope — Included). Each bullet there is a scoped item the diff must touch. Section 4 (Assumptions) often contains conditional scope ("assuming the auth middleware is in place, …") — cross-check.

**How to detect:**
- Extract scoped items from PLAN CONTEXT: schema-aware mode, parse section 2 bullets; in fallback mode, scan for explicit file paths, module names, table names, endpoint paths, "must include X", "add Y to Z", bulleted "the following will change:" lists.
- For each scoped item, check the changed-files list in `DIFF CONTEXT` for a corresponding entry (path match, basename match, or a file under the named module).
- If a scoped item has no matching changed file, flag it.

**Red flag:** a file, module, endpoint, or entity named in section 2 is absent from the diff's changed-files list.

### 2. Migration Presence When Plan Mentions Migration

The spec mentions a schema change but the diff has no migration file. The reviewer should not have to infer this — when the plan commits to a schema change, the diff must carry the artifact.

**schema cite:** section 6 (Steps) — schema-change steps are enumerated here. Section 10 (Rollback-Recovery) — companion rollback step.

**How to detect:**
- Scan PLAN CONTEXT for: "migration", "schema change", "add column", "drop column", "rename column", "new table", "data backfill", "DDL", "alter table", or named schema-change patterns. In schema mode, look in section 6 step bodies + section 10.
- Check `DIFF CONTEXT` for files under `migrations/`, `db/migrations/`, `prisma/migrations/`, `alembic/versions/`, `liquibase/`, or the project's migration directory (look at where prior migrations live).
- If the plan mentions a schema change AND no migration file is present in the diff, flag.

**Red flag:** plan mentions a schema or data-shape change; the diff has no migration file.

### 3. Rollback / down When Migration Touches Data

A migration file in the diff performs data writes (INSERT / UPDATE / DELETE / data backfill / column population) but has no corresponding rollback path: no `down` method (TypeORM / Prisma / Knex / Sequelize / SQLAlchemy), no reverse migration file, no documented manual-rollback procedure.

**schema cite:** section 10 (Rollback-Recovery). When section 10 specifies a rollback procedure, verify the diff carries the corresponding artifact (down method or reverse migration file).

**How to detect:**
- For each migration file in the diff, Read it.
- Check whether the migration body contains data-mutating statements: `INSERT`, `UPDATE`, `DELETE`, calls to a repository / ORM model, scripted backfill loops.
- For data-mutating migrations, check for: a `down` / `revert` / `downgrade` method that meaningfully reverses the change; a paired reverse migration file in the same change set; or an explicit `// no rollback — see runbook` comment with a runbook reference.
- Flag when a data-mutating migration has none of those.

**Red flag:** a data-mutating migration with no rollback path documented in code or the PR body.

### 4. Tests for Stated Acceptance Criteria

The PR body or plan lists numbered acceptance criteria ("AC1: …", "AC2: …", bulleted "must …" / "should …" / "the system will …"); the diff's test files contain no assertion that references each AC's behavior.

**schema cite:** section 9 (Validation). Acceptance criteria are owned by this section.

**How to detect:**
- Extract AC text from PLAN CONTEXT: explicit "## Acceptance criteria" / "## ACs" sections, numbered "AC1/AC2/…" lists, bulleted "must …" / "should …" lines under a feature heading.
- For each AC, derive 2–4 keyword anchors from its text (verbs, entity names, error conditions).
- Grep the diff's test files (`**/*.{test,spec}.*`, `**/__tests__/**`, `tests/**`) for the keyword anchors.
- Flag any AC whose keyword anchors appear in no test file.

**Red flag:** an AC is enumerated in the plan; no test in the diff references its behavior.

### 5. Feature-Flag Wiring When Plan Mentions One

The plan mentions a flag-gated rollout, but the diff has no flag-key references and no flag-evaluation calls. Shipping the change without the flag means the rollout strategy described in the spec is not actually achievable.

**schema cite:** section 6 (Steps) — flag-wiring step. Section 8 (Approval Points) — flag-flip approval gate.

**How to detect:**
- Scan PLAN CONTEXT for: "feature flag", "toggle", "flag rollout", "ramp", "gating", "killswitch", "gradual rollout", a named flag key (UPPER_SNAKE_CASE constants are common).
- Identify the project's flag client by sampling existing call sites: `featureFlags.is(...)`, `useFlag(...)`, `getVariation(...)`, `gb.isOn(...)`, `unleash.isEnabled(...)`, `launchdarkly.variation(...)`, `flag(...)`.
- Grep the diff for the identified flag-client call shape AND for any flag-key string literal mentioned in the plan.
- Flag when the plan mentions flag-gated rollout AND the diff has no flag client call AND no flag-key literal.

**Red flag:** plan describes a flag-gated rollout; diff has no flag-evaluation wiring.

### 6. Documented Deploy Ordering When Multi-Write Coordination Changes

The plan describes a change that involves multiple writers — a live handler plus a reconcile job, a migration plus a backfill, an event projector plus a snapshot table, dual-write transitions — but the diff carries no documented deploy order (PR body deploy-steps list, runbook reference, JSDoc on the migration, or comments at the writer entry points).

**schema cite:** section 6 (Steps) — deploy-step ordering. Section 5 (Risks) — coordination risks typically reside here.

**How to detect:**
- Scan PLAN CONTEXT for multi-writer signals: "reconcile", "backfill", "dual-write", "shadow write", "projector", "snapshot", "live handler + …", "event-driven … plus migration", "rollout in stages", "phase 1 / phase 2".
- For matching plans, scan the PR body for a deploy-order heading: "## Deploy order", "## Rollout", "## Runbook", a numbered deploy-steps list, or a link to an external runbook.
- Also scan the diff's migration files and writer entry points for JSDoc / leading comments that name the deploy step.
- Flag when multi-writer coordination is named in the plan AND no deploy ordering is documented anywhere reachable.

**Red flag:** multi-writer change named in the plan; no deploy order in PR body, runbook, or code comments.

### 7. Test Plan for Stated Semantic Shifts

The plan describes a value-semantic change — a column meaning shifts, a return-value contract changes, an enum value's behavior changes, a fail-open default becomes fail-closed — but the diff's PR body has no Before/After table or behavior matrix, and the test files do not assert the new semantic at the boundary where it takes effect.

**schema cite:** section 1 (Objective) — semantic shift typically named here. Section 9 (Validation) — boundary tests.

**How to detect:**
- Scan PLAN CONTEXT for semantic-shift markers: "from X to Y", "behavior changes to", "previously … now …", "fail-open → fail-closed", "default changes from", "now returns", "column meaning becomes".
- For each named shift, scan the PR body for a Before/After section: `## Before` / `## After` headings, a markdown table with "Before" / "After" columns, or an explicit "## Behavior change" callout with old vs new.
- Scan diff test files for assertions that name both the old and new behavior or assert the boundary condition at which the shift takes effect.
- Flag when a semantic shift is named in the plan AND neither the PR body nor the tests document the boundary.

**Red flag:** semantic shift named in the plan; no Before/After in the PR body and no boundary assertion in the tests.

### 8. Configuration / Environment Variable Wiring When Plan Adds Settings

The plan names a new configuration value, environment variable, or runtime setting that operators must provide; the diff has no corresponding entry in the project's config surface (env-example file, config schema, settings module) and no documentation of the new value in the PR body or runbook.

**schema cite:** section 7 (Tools Required) — config / env vars / settings live alongside tool listings here. (Frontmatter `tools_required` field may also enumerate them.)

**How to detect:**
- Scan PLAN CONTEXT for: "config", "configuration", "environment variable", "env var", "setting", "tunable", "threshold", a named UPPER_SNAKE_CASE token that looks like an env var, or a "configurable via …" phrase.
- For each named setting, check the diff for entries in: `.env.example` / `.env.sample`, the project's config schema file (Zod / Joi / Pydantic / Convict / Viper), a `config/*.{ts,js,py,yaml}` file, or a `settings.py` / `application.yml`.
- Also scan the PR body for documentation of the new value: name, default, allowed range.
- Flag when the plan names a new setting AND the diff has no config-surface entry AND the PR body does not document it.

**Red flag:** plan names a new config or env var; diff has no config-surface entry and no documentation.

### 9. Observability for Stated Operational Concerns

The plan names an operational concern that requires observability — a rollout to monitor, a failure mode to watch, an SLO to defend, an error budget to track — but the diff adds no metrics emission, no log statements at the relevant boundary, and no alert / dashboard reference. Operators cannot see whether the change is working in production.

**schema cite:** section 9 (Validation) — observability requirements often live here. Section 5 (Risks) — risk-mitigation observability.

**How to detect:**
- Scan PLAN CONTEXT for observability triggers: "monitor", "alert", "SLO", "SLA", "error budget", "rollout watch", "metric", "dashboard", "we'll watch …", "track the rate of …", "log when …".
- Identify the project's metric / logging clients by sampling existing call sites: `metrics.increment(...)`, `statsd.timing(...)`, `prometheus_client.Counter(...)`, `logger.info(...)`, `log.warn(...)`, `tracer.startSpan(...)`.
- Grep the diff for the identified client shapes at the writer / handler entry points named in the plan.
- Flag when the plan names an operational concern AND the diff has no metric, log, or trace emission at the relevant boundary.

**Red flag:** plan names a monitoring or operational concern; diff has no observability emission at the named boundary.

### 10. Done Condition Met

The spec's section 11 (Done Condition) names an observable signal that defines completion (e.g., "all 5 acceptance tests green", "PR approved by stakeholder X", "feature ships behind flag AND telemetry shows ≥1 successful use"). The diff must achieve, or visibly progress towards, that signal — not just touch the named files.

**Skip when not schema-aware mode** (no section 11 anchor). Per the prose fallback (top of file), this check fires only when `geniro_kind: design-doc` frontmatter is present.

**schema cite:** section 11 (Done Condition) — the canonical completion criterion. Cross-check the /geniro:plan validator check #9 (`stopping_condition`) — the spec validator that ensured section 11 has a concrete observable signal.

**How to detect:**
- Parse section 11 body. Extract the observable signal (regex match against ontology: `\b(tests? (pass|green))\b`, `\b(PR (approved|merged))\b`, `\b(telemetry|metric|log)\s+shows\b`, `\b(shipped|released)\s+to\b`, `\b(observable|verified|confirmed)\b`).
- For test-based signals: check the diff's test files for new/updated assertions matching the named test set OR check CI status (out of scope here — surface as informational note).
- For telemetry/log signals: check the diff for metric or log emission at the named boundary (cross-reference check #9 above).
- For approval-based signals: check the PR body / state for the named approver's review status.
- Flag when section 11 names an observable signal AND the diff carries no artifact moving towards it.

**Red flag:** section 11 specifies "<observable signal> AND <verification>" but the diff carries no artifact realizing the signal or its verification.

### 11. Tools Required Available

The spec's section 7 (Tools Required) AND/OR frontmatter `tools_required` field enumerates tools the change needs (e.g., specific CLI binaries, infra services, MCP connectors). The diff or local environment must show all listed tools are actually available — a spec promising "requires `kubectl` + `helm`" but landing in a repo without either ships broken.

**Skip when not schema-aware mode.** (No section 7 anchor.)

**schema cite:** section 7 (Tools Required) — tool listing. Frontmatter `tools_required: [list]` — may also enumerate.

**How to detect:**
- Parse section 7 body + frontmatter `tools_required`. Extract individual tool names (CLI binaries: `kubectl`, `helm`, `terraform`, `gh`; library packages; service endpoints; MCP connectors).
- For each CLI binary, run `which <tool>` via Bash (read-only — no mutation). Note absence as finding.
- For library packages, check package.json / pyproject.toml / Gemfile / Cargo.toml for the package name. Note absence.
- For MCP connectors, check the runtime tool list — note absence as informational (MCP availability is environment-specific).
- For service endpoints — out of scope (cannot verify reachability from reviewer). Surface as informational note.
- Flag when section 7 names a tool AND the environment shows the tool is not available.

**Red flag:** section 7 names tool `X` (or frontmatter `tools_required` lists `X`); `which X` returns non-zero / package.json has no `X` entry. Severity HIGH — diff cannot work without the tool.

### 12. Implemented but Divergent

For each scoped item the diff DOES touch, read the hunk against the spec's stated behavior for that item — presence is not compliance. Checks 1-11 catch what the diff omits; this check catches what it implements contrary to the spec: a wrong status code, an inverted default, a different field name, a boundary handled differently than the acceptance criterion states.

**schema cite:** section 2 (Scope — Included) — the touched item; section 9 (Validation) / section 1 (Objective) — where its stated behavior lives. In prose fallback, cite the spec fragment that states the behavior.

**How to detect:**
- Take the scoped items that HAVE a matching changed file (the complement of Check 1's miss set). For each, extract the spec's stated behavior: status codes, defaults, field names, boundary conditions, error handling — from the item's own bullet, section 9, or the acceptance criteria.
- Read the corresponding hunks and compare each stated behavior against what the code actually does.
- Run §Spec-premise validation on every candidate contradiction first: a grounded departure (the spec premise is contradicted by live code and the diff's choice is the correct one) routes to `[INTENT-CHECK]` capped at MEDIUM, as usual.
- An ungrounded contradiction (the premise still holds and the hunk contradicts it anyway) is HIGH — `Evidence:` quotes the spec fragment and the contradicting hunk side by side, so the reader sees the mismatch without re-deriving it.

**Red flag:** the diff touches a scoped item and the hunk contradicts the spec's stated behavior for it — e.g., the spec says "returns 404 when user not found"; the handler returns 400.

## Common False Positives

Skip or downgrade findings in these cases — they look like rubric violations but reflect routine PR patterns the rubric is not designed to flag:

- **Draft PRs** (`gh pr view --json isDraft` returns `true`): incomplete scope is expected while the author iterates. Skip checks 4–9, 10–11; keep checks 1–3 (scope items, migration presence, rollback) because those are structural and easier to forget than to defer intentionally, and check 12 — code the draft already wrote that contradicts the spec is a defect worth catching early, not iteration slack.
- **Exploratory / brainstorm-style plans** (PLAN CONTEXT contains "TBD", "TODO", "follow-up", "out of scope", "future work", "tentative", "phase 2 will", or similar deferral markers near the scoped item): the plan itself did not commit to the scope. Downgrade the severity by one level (CRITICAL → HIGH, HIGH → MEDIUM, MEDIUM → informational) for findings that hit the deferred item.
- **Bot-author PRs** (author user matches `dependabot[bot]`, `renovate[bot]`, `release-please[bot]`, `github-actions[bot]`, `changesets[bot]`, or a similar automation account — check `gh pr view --json author --jq '.author.login'`): the rubric does not apply. Skip every check; emit zero findings.
- **Trivial PRs** (<20 LOC AND a single file changed): scope-completeness expectations do not apply at this size. Skip checks 1, 2, 6, 7, 9, 10, 11. Keep checks 3 (rollback), 4 (AC tests), 5 (flag wiring), 8 (config), and 12 (behavior divergence) only if their preconditions visibly fire in the diff or PR body.
- **Plan covers a multi-PR effort and this PR is one slice**: when PLAN CONTEXT explicitly enumerates a multi-PR plan (e.g., "PR 1: schema; PR 2: handler; PR 3: backfill") and the PR body cites which slice it is, restrict scope-completeness to the named slice. Items belonging to later slices are not omissions.
- **Reverts and cherry-picks**: when the title begins with `Revert "` or `Cherry-pick` / `[backport]`, the spec the diff is held against is the parent change, not the original plan. Skip every check unless the revert/backport itself introduces new scope.

The detection signals above come from `gh pr view --json isDraft,author,title,body,labels` and the PLAN CONTEXT slot already threaded into the prompt at SKILL.md Phase 1 — no additional API roundtrip is needed.

## Severity Tagging

- **CRITICAL** — data-mutating migration with no rollback path (Check 3); semantic shift with fail-closed implications and no boundary assertion in tests (Check 7); flag-gated rollout with no flag wiring (Check 5). These ship broken, unsafe, or unrollable.
- **HIGH** — scoped item from the plan is missing from the diff (Check 1); migration absent when the plan mentions a schema change (Check 2); multi-writer change with no documented deploy order (Check 6); new config / env var with no config-surface entry (Check 8); Done Condition not realized in the diff (Check 10); Tools Required missing from the environment (Check 11); implementation contradicts the spec's stated behavior for a touched item, with the departure not grounded in live code (Check 12). Reviewers cannot verify or operate the change without these.
- **MEDIUM** — acceptance criterion named in the plan with no test reference (Check 4); operational concern named in the plan with no observability emission (Check 9); plan mentions a consideration the diff only partially addresses; semantic-shift PR with Before/After missing from the body but tests cover the boundary.

Do not emit findings for items the plan did not commit to. PLAN CONTEXT is the rubric here — if a check's precondition is not visible in the plan, the check does not fire. This is the load-bearing constraint that separates this dimension from inventing requirements: a finding is only valid when the missing artifact can be cited verbatim back to a specific fragment of the plan in the `Evidence:` field.

Apply the severity downgrades from the False Positives section before tagging. A precondition-met finding against an exploratory-plan item drops one level (HIGH becomes MEDIUM, MEDIUM becomes informational); a precondition-met finding against a draft PR may be suppressed entirely per the draft-PR carve-out. A divergence classified as a spec-defect by §Spec-premise validation overrides the Check-N structural severity entirely: it caps at MEDIUM and routes to `[INTENT-CHECK]`, because the gap is in the spec, not the implementation.

## Cross-PR Scope Split (peer-PR context)

When the `PEER-PR CONTEXT:` slot is non-`none` AND the LINEAR CONTEXT block shows a parent epic with sibling sub-tasks (or PLAN CONTEXT enumerates a multi-PR plan per §Common False Positives "Plan covers a multi-PR effort"), the parent's scope is split across siblings. Apply scope-completeness checks **against the slice the current PR owns**, not the whole parent:

- If LINEAR CONTEXT shows `linear-parent-ref: ENG-100` AND PEER-PR CONTEXT lists a sibling PR carrying a sibling sub-task ID (e.g., `ENG-101` while current is `ENG-102`): the parent's scope is split. Each sub-task PR owns its own slice. Items belonging to the sibling sub-task are NOT omissions on the current PR.
- Emit a structured `open_questions[]` entry with `source: spec-compliance`, `status: unresolved`, `question: "Parent epic ENG-100 has scope items A, B, C. Current PR ENG-102 covers B; sibling PR #N (ENG-101) covers A. Item C is unassigned — confirm whether C is in scope for this PR, deferred to another sub-task, or out of scope entirely."`. Not a HIGH finding — it gates a scope decision the user must make.

When ALL parent scope items appear covered across current + peer PRs combined, the multi-PR effort is complete — surface a one-line informational note in body `## Caveats`: "Parent epic ENG-100 fully covered by [current + peer-PR list]." No `open_questions[]` entry — there's nothing to resolve.

## Output Anchor

Spec-compliance findings have no `path:lines`. Emit each finding with:
- `File:` field set to the literal string `SPEC-COMPLIANCE` (no path, no line number).
- All other reviewer-agent output fields per the standard template (Severity, Cause, Evidence, Why this matters, Suggested fix, Decision Type, Confidence).
- `Evidence:` quotes the relevant fragment of the plan verbatim (with a brief surrounding marker — e.g., "plan section: `## Acceptance criteria`, AC3: `…`") AND names the missing artifact in the diff (e.g., "no file under `migrations/` in the changed-files list").

The Phase 6 Post drill's Step 4 composer (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §7.5) detects the `File: SPEC-COMPLIANCE` sentinel and routes these findings into the top-level review `body` field of the `gh api` POST under a `## Spec Compliance` section, NOT into the inline `comments[]` array (which requires a path-anchored line).
