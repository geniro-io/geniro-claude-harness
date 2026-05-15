# Spec Compliance Review Criteria

Completeness audit of the diff **against the plan / spec** — what the spec promised but the diff omits. The diff's code quality (correctness, security, architecture, tests, optimizations, guidelines, conventions, design) is owned by the other reviewer dimensions; this dimension owns SPEC→DIFF completeness only. The spec is the source of truth; the diff is the side-input — the inverse of every other reviewer, which is diff-anchored.

This dimension fires conditionally: PLAN CONTEXT must be non-`none` AND either the input is a PR ref OR the change carries `risk-tier: high`. It is skipped for local files, branches, or diff ranges with no plan context attached. The reviewer emits findings without a `path:lines` anchor — the orchestrator routes them into the top-level review `body` field of the `gh api` POST in Phase 6, alongside PR-METADATA findings under a dedicated `## Spec Compliance` section, not as inline comments. The plan-context tagging convention in `skills/review/plan-context-reference.md` (`[ALIGNS-WITH-PLAN]` / `[DIVERGES-FROM-PLAN]`) does not apply here — findings in this dimension are inherently divergences, so the tag is implicit.

## What to Check

### 1. Scope Completeness

The spec enumerates files, modules, endpoints, entities, or surfaces that the change must touch; the diff omits one or more of them. This is the most common spec-compliance gap: the spec said "update A, B, and C"; the diff updates A and B.

**How to detect:**
- Extract scoped items from the PLAN CONTEXT slot in the prompt: explicit file paths, module names, table names, endpoint paths, "must include X", "add Y to Z", bulleted "the following will change:" lists.
- For each scoped item, check the changed-files list in `DIFF CONTEXT` for a corresponding entry (path match, basename match, or a file under the named module).
- If a scoped item has no matching changed file, flag it.

**Red flag:** a file, module, endpoint, or entity named in the plan is absent from the diff's changed-files list.

### 2. Migration Presence When Plan Mentions Migration

The spec mentions a schema change but the diff has no migration file. The reviewer should not have to infer this — when the plan commits to a schema change, the diff must carry the artifact.

**How to detect:**
- Scan PLAN CONTEXT for: "migration", "schema change", "add column", "drop column", "rename column", "new table", "data backfill", "DDL", "alter table", or named schema-change patterns.
- Check `DIFF CONTEXT` for files under `migrations/`, `db/migrations/`, `prisma/migrations/`, `alembic/versions/`, `liquibase/`, or the project's migration directory (look at where prior migrations live).
- If the plan mentions a schema change AND no migration file is present in the diff, flag.

**Red flag:** plan mentions a schema or data-shape change; the diff has no migration file.

### 3. Rollback / down() When Migration Touches Data

A migration file in the diff performs data writes (INSERT / UPDATE / DELETE / data backfill / column population) but has no corresponding rollback path: no `down()` method (TypeORM / Prisma / Knex / Sequelize / SQLAlchemy), no reverse migration file, no documented manual-rollback procedure.

**How to detect:**
- For each migration file in the diff, Read it.
- Check whether the migration body contains data-mutating statements: `INSERT`, `UPDATE`, `DELETE`, calls to a repository / ORM model, scripted backfill loops.
- For data-mutating migrations, check for: a `down()` / `revert()` / `downgrade()` method that meaningfully reverses the change; a paired reverse migration file in the same change set; or an explicit `// no rollback — see runbook` comment with a runbook reference.
- Flag when a data-mutating migration has none of those.

**Red flag:** a data-mutating migration with no rollback path documented in code or the PR body.

### 4. Tests for Stated Acceptance Criteria

The PR body or plan lists numbered acceptance criteria ("AC1: …", "AC2: …", bulleted "must …" / "should …" / "the system will …"); the diff's test files contain no assertion that references each AC's behavior.

**How to detect:**
- Extract AC text from PLAN CONTEXT: explicit "## Acceptance criteria" / "## ACs" sections, numbered "AC1/AC2/…" lists, bulleted "must …" / "should …" lines under a feature heading.
- For each AC, derive 2–4 keyword anchors from its text (verbs, entity names, error conditions).
- Grep the diff's test files (`**/*.{test,spec}.*`, `**/__tests__/**`, `tests/**`) for the keyword anchors.
- Flag any AC whose keyword anchors appear in no test file.

**Red flag:** an AC is enumerated in the plan; no test in the diff references its behavior.

### 5. Feature-Flag Wiring When Plan Mentions One

The plan mentions a flag-gated rollout, but the diff has no flag-key references and no flag-evaluation calls. Shipping the change without the flag means the rollout strategy described in the spec is not actually achievable.

**How to detect:**
- Scan PLAN CONTEXT for: "feature flag", "toggle", "flag rollout", "ramp", "gating", "killswitch", "gradual rollout", a named flag key (UPPER_SNAKE_CASE constants are common).
- Identify the project's flag client by sampling existing call sites: `featureFlags.is(...)`, `useFlag(...)`, `getVariation(...)`, `gb.isOn(...)`, `unleash.isEnabled(...)`, `launchdarkly.variation(...)`, `flag(...)`.
- Grep the diff for the identified flag-client call shape AND for any flag-key string literal mentioned in the plan.
- Flag when the plan mentions flag-gated rollout AND the diff has no flag client call AND no flag-key literal.

**Red flag:** plan describes a flag-gated rollout; diff has no flag-evaluation wiring.

### 6. Documented Deploy Ordering When Multi-Write Coordination Changes

The plan describes a change that involves multiple writers — a live handler plus a reconcile job, a migration plus a backfill, an event projector plus a snapshot table, dual-write transitions — but the diff carries no documented deploy order (PR body deploy-steps list, runbook reference, JSDoc on the migration, or comments at the writer entry points).

**How to detect:**
- Scan PLAN CONTEXT for multi-writer signals: "reconcile", "backfill", "dual-write", "shadow write", "projector", "snapshot", "live handler + …", "event-driven … plus migration", "rollout in stages", "phase 1 / phase 2".
- For matching plans, scan the PR body for a deploy-order heading: "## Deploy order", "## Rollout", "## Runbook", a numbered deploy-steps list, or a link to an external runbook.
- Also scan the diff's migration files and writer entry points for JSDoc / leading comments that name the deploy step.
- Flag when multi-writer coordination is named in the plan AND no deploy ordering is documented anywhere reachable.

**Red flag:** multi-writer change named in the plan; no deploy order in PR body, runbook, or code comments.

### 7. Test Plan for Stated Semantic Shifts

The plan describes a value-semantic change — a column meaning shifts, a return-value contract changes, an enum value's behavior changes, a fail-open default becomes fail-closed — but the diff's PR body has no Before/After table or behavior matrix, and the test files do not assert the new semantic at the boundary where it takes effect.

**How to detect:**
- Scan PLAN CONTEXT for semantic-shift markers: "from X to Y", "behavior changes to", "previously … now …", "fail-open → fail-closed", "default changes from", "now returns", "column meaning becomes".
- For each named shift, scan the PR body for a Before/After section: `## Before` / `## After` headings, a markdown table with "Before" / "After" columns, or an explicit "## Behavior change" callout with old vs new.
- Scan diff test files for assertions that name both the old and new behavior or assert the boundary condition at which the shift takes effect.
- Flag when a semantic shift is named in the plan AND neither the PR body nor the tests document the boundary.

**Red flag:** semantic shift named in the plan; no Before/After in the PR body and no boundary assertion in the tests.

### 8. Configuration / Environment Variable Wiring When Plan Adds Settings

The plan names a new configuration value, environment variable, or runtime setting that operators must provide; the diff has no corresponding entry in the project's config surface (env-example file, config schema, settings module) and no documentation of the new value in the PR body or runbook.

**How to detect:**
- Scan PLAN CONTEXT for: "config", "configuration", "environment variable", "env var", "setting", "tunable", "threshold", a named UPPER_SNAKE_CASE token that looks like an env var, or a "configurable via …" phrase.
- For each named setting, check the diff for entries in: `.env.example` / `.env.sample`, the project's config schema file (Zod / Joi / Pydantic / Convict / Viper), a `config/*.{ts,js,py,yaml}` file, or a `settings.py` / `application.yml`.
- Also scan the PR body for documentation of the new value: name, default, allowed range.
- Flag when the plan names a new setting AND the diff has no config-surface entry AND the PR body does not document it.

**Red flag:** plan names a new config or env var; diff has no config-surface entry and no documentation.

### 9. Observability for Stated Operational Concerns

The plan names an operational concern that requires observability — a rollout to monitor, a failure mode to watch, an SLO to defend, an error budget to track — but the diff adds no metrics emission, no log statements at the relevant boundary, and no alert / dashboard reference. Operators cannot see whether the change is working in production.

**How to detect:**
- Scan PLAN CONTEXT for observability triggers: "monitor", "alert", "SLO", "SLA", "error budget", "rollout watch", "metric", "dashboard", "we'll watch …", "track the rate of …", "log when …".
- Identify the project's metric / logging clients by sampling existing call sites: `metrics.increment(...)`, `statsd.timing(...)`, `prometheus_client.Counter(...)`, `logger.info(...)`, `log.warn(...)`, `tracer.startSpan(...)`.
- Grep the diff for the identified client shapes at the writer / handler entry points named in the plan.
- Flag when the plan names an operational concern AND the diff has no metric, log, or trace emission at the relevant boundary.

**Red flag:** plan names a monitoring or operational concern; diff has no observability emission at the named boundary.

## Common False Positives

Skip or downgrade findings in these cases — they look like rubric violations but reflect routine PR patterns the rubric is not designed to flag:

- **Draft PRs** (`gh pr view --json isDraft` returns `true`): incomplete scope is expected while the author iterates. Skip checks 4–9; keep checks 1–3 (scope items, migration presence, rollback) because those are structural and easier to forget than to defer intentionally.
- **Exploratory / brainstorm-style plans** (PLAN CONTEXT contains "TBD", "TODO", "follow-up", "out of scope", "future work", "tentative", "phase 2 will", or similar deferral markers near the scoped item): the plan itself did not commit to the scope. Downgrade the severity by one level (CRITICAL → HIGH, HIGH → MEDIUM, MEDIUM → informational) for findings that hit the deferred item.
- **Bot-author PRs** (author user matches `dependabot[bot]`, `renovate[bot]`, `release-please[bot]`, `github-actions[bot]`, `changesets[bot]`, or a similar automation account — check `gh pr view --json author --jq .author.login`): the rubric does not apply. Skip every check; emit zero findings.
- **Trivial PRs** (<20 LOC AND a single file changed): scope-completeness expectations do not apply at this size. Skip checks 1, 2, 6, 7, 9. Keep checks 3 (rollback), 4 (AC tests), 5 (flag wiring), 8 (config) only if their preconditions visibly fire in the diff or PR body.
- **Plan covers a multi-PR effort and this PR is one slice**: when PLAN CONTEXT explicitly enumerates a multi-PR plan (e.g., "PR 1: schema; PR 2: handler; PR 3: backfill") and the PR body cites which slice it is, restrict scope-completeness to the named slice. Items belonging to later slices are not omissions.
- **Reverts and cherry-picks**: when the title begins with `Revert "` or `Cherry-pick` / `[backport]`, the spec the diff is held against is the parent change, not the original plan. Skip every check unless the revert/backport itself introduces new scope.

The detection signals above come from `gh pr view --json isDraft,author,title,body,labels` and the PLAN CONTEXT slot already threaded into the prompt at SKILL.md Phase 1 — no additional API roundtrip is needed.

## Severity Tagging

- **CRITICAL** — data-mutating migration with no rollback path (Check 3); semantic shift with fail-closed implications and no boundary assertion in tests (Check 7); flag-gated rollout with no flag wiring (Check 5). These ship broken, unsafe, or unrollable.
- **HIGH** — scoped item from the plan is missing from the diff (Check 1); migration absent when the plan mentions a schema change (Check 2); multi-writer change with no documented deploy order (Check 6); new config / env var with no config-surface entry (Check 8). Reviewers cannot verify or operate the change without these.
- **MEDIUM** — acceptance criterion named in the plan with no test reference (Check 4); operational concern named in the plan with no observability emission (Check 9); plan mentions a consideration the diff only partially addresses; semantic-shift PR with Before/After missing from the body but tests cover the boundary.

Do not emit findings for items the plan did not commit to. PLAN CONTEXT is the rubric here — if a check's precondition is not visible in the plan, the check does not fire. This is the load-bearing constraint that separates this dimension from inventing requirements: a finding is only valid when the missing artifact can be cited verbatim back to a specific fragment of the plan in the `Evidence:` field.

Apply the severity downgrades from the False Positives section before tagging. A precondition-met finding against an exploratory-plan item drops one level (HIGH becomes MEDIUM, MEDIUM becomes informational); a precondition-met finding against a draft PR may be suppressed entirely per the draft-PR carve-out. The final severity tag should reflect both the structural class of the gap (Check N → CRITICAL/HIGH/MEDIUM here) AND any downgrade rule that fires from the False Positives section.

## Output Anchor

Spec-compliance findings have no `path:lines`. Emit each finding with:
- `File:` field set to the literal string `SPEC-COMPLIANCE` (no path, no line number).
- All other reviewer-agent output fields per the standard template (Severity, Cause, Evidence, Why this matters, Suggested fix, Decision Type, Confidence).
- `Evidence:` quotes the relevant fragment of the plan verbatim (with a brief surrounding marker — e.g., "plan section: `## Acceptance criteria`, AC3: `…`") AND names the missing artifact in the diff (e.g., "no file under `migrations/` in the changed-files list").

The Phase 6 Step 4 comment-body composer in `skills/review/SKILL.md` detects the `File: SPEC-COMPLIANCE` sentinel and routes these findings into the top-level review `body` field of the `gh api` POST under a `## Spec Compliance` section, NOT into the inline `comments[]` array (which requires a path-anchored line).
