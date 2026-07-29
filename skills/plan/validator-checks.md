# Phase 7 validator — 13 checks

Canonical definitions of the mechanical validator checks fired in `/geniro:plan` Phase 7. These are deterministic, script-checkable rules executed orchestrator-side, near-zero token usage.

**Status:** Authoritative. The orchestrator runs all checks in sequence; each returns `(check_id, status, finding_text, fix_hint)`. Output: list of failing checks → state.md `## Open Questions` body section.

**Hard-fail handling:** see `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-7-validator.md` §7.3 — 3 auto-revision rounds, then AUQ to user with 3 options (accept-as-is / re-revise / abort).

## Contents

- good-goal criteria: 1 `single_objective` / 2 `bounded_scope` / 3 `source_materials` / 4 `allowed_tools` / 5 `forbidden_actions` / 6 `budget` / 7 `checkpoints` / 8 `validation_method` / 9 `stopping_condition`
- Additional checks: 10 `placeholder_scan` / 11 `schema_completeness` / 12 `workflow_refs_consistency` / 13 `launch_config_consistency`
- Check API contract

---

## good-goal criteria

### 1. `single_objective`

**Rule:** Section 1 (Objective) body contains exactly one sentence ending in a period, stated as a goal (imperative "Add X." or declarative "X is added." — not interrogative).

**Heuristic:** sentence-count and final-token check (final token is a period, not `?`).

**Fix hint on fail:** "Section 1 must be exactly one goal sentence ending in a period. Got: <N> sentences OR a question. Rewrite as a single goal statement."

### 2. `bounded_scope`

**Rule:** Sections 2 (Scope.Included) AND 3 (Scope.Excluded) BOTH have at least one bullet OR section 3 has body content "none — open scope" with explicit rationale.

**Heuristic:** bullet-count in each section.

**Fix hint on fail:** "Either section 2 OR section 3 has zero bullets and no "none with rationale" note. Add bullets, OR explicitly state "none — open scope" with a one-line rationale in section 3."

### 3. `source_materials`

**Rule:** state.md `## Tool log` body has ≥1 Agent entry with `status: ok` per effort tier:
- Trivial: ≥1 (OR explicit "scope-bound, no exploration needed" note)
- Small: ≥1
- Medium: ≥2
- Big: ≥3

Also: spec.md section 6 (Steps) cites ≥1 file:line reference per non-trivial step.

**Heuristic:** parse `## Tool log` YAML entries, count Agent + status:ok; for section 6, regex match `<path>:<line>` or `<path>:<line>-<line>` pattern.

**Fix hint on fail:** "Phase 1 explore did not produce enough citations for effort tier <tier>. Re-spawn research agents with sharper sub-queries, OR if scope-bound, add explicit "scope-bound, no exploration needed" entry to ## Tool log."

### 4. `allowed_tools`

**Rule:** frontmatter `tools_required` field is a non-empty list (if spec section 7 "Tools Required" is non-empty body) OR field is `null` (if section 7 body is "none").

**Heuristic:** field presence + body alignment.

**Fix hint on fail:** "Section 7 says '<body>' but frontmatter tools_required is <value>. Sync them: empty body ↔ null field; non-empty body ↔ matching list."

### 5. `forbidden_actions`

**Rule:** frontmatter `forbidden_actions` is a non-empty list when the task touches sensitive areas (auto-detected: presence of `auth`/`secret`/`migration`/`payment` keywords in section 1 Objective OR section 2 Scope.Included). Otherwise `null` is OK.

**Heuristic:** keyword scan, then field-presence check.

**Fix hint on fail:** "Sensitive keyword detected in objective/scope, but forbidden_actions is null. Add at least one explicit 'do NOT …' rule (e.g., 'do NOT bypass auth middleware')."

### 6. `budget`

**Rule:** frontmatter `budget` block has all 3 sub-fields (`max_files_to_edit` / `max_lines_changed` / `time_budget`). Values may be `null` for unbounded, but the keys must be present — the validator checks key presence, not value.

**Heuristic:** YAML key presence check.

**Fix hint on fail:** "Frontmatter `budget` block missing key <name>. Add the key with value `null` if unbounded."

### 7. `checkpoints`

**Rule:** frontmatter `checkpoints` is a non-empty list if section 6 (Steps) has ≥5 steps. Each checkpoint must reference a step-N anchor or section-name that exists.

**Heuristic:** step-count by counting the section's checkbox items (`- [ ] N.` lines), equivalently the `<!-- step-N -->` anchors — not a bare leading digit, since steps render as `- [ ] N. …` checkboxes; for each checkpoint entry, verify `step_anchor` resolves to an actual step.

**Fix hint on fail:** "Spec has ≥5 steps but no checkpoints defined. Add at least one `{step_anchor: step-N, name:...}` entry for a natural pause point (e.g., after DB migration or test gate)."

### 8. `validation_method`

**Rule:** section 9 (Validation) has body content; either references a test type (`unit`, `integration`, `e2e`) OR specifies a manual-verification procedure.

**Sub-rule (`verify:` shape, optional field):** if a section 9 criterion carries a `verify:` field, it must be a non-empty command string. Shape-only — the validator never executes the command; /geniro:implement runs it at end-of-phase. A criterion without `verify:` still passes — the check never requires the field. Attaching one wherever a single read-only command can prove the criterion is the authoring default (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md` §9), an authoring bar rather than a validation bar.

**Heuristic:** body-non-empty + keyword/regex match; for each `verify:` occurrence, assert the remainder of the line is non-empty after trimming whitespace.

**Fix hint on fail:** "Section 9 (Validation) is empty or doesn't reference a concrete verification method. Add either a test type OR a manual procedure (e.g., 'manual: navigate to /login, click OAuth button, verify redirect'). If a criterion declares `verify:`, give it a non-empty command (or drop the empty `verify:` line)."

### 9. `stopping_condition`

**Rule:** section 11 (Done Condition) has body content matching pattern "<observable signal>" (e.g., "all 5 acceptance tests green", "PR approved by stakeholder X", "feature ships behind flag AND telemetry shows ≥1 successful use").

**Heuristic:** regex match against the stopping-condition ontology in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/done-condition-check.md` §"Stopping-condition ontology" — the canonical signal-shape set. Do not restate the patterns here: this spec-time check and the ship-time annotation must classify a clause identically, and a second copy is what lets them drift apart.

**Fix hint on fail:** "Section 11 (Done Condition) doesn't match an observable-signal phrase. Rewrite as a concrete completion criterion (e.g., '<observable signal> AND <verification>')."

---

## Additional checks

### 10. `placeholder_scan`

**Rule:** body of spec.md contains zero of: `TODO`, `XXX`, `FIXME`, `<placeholder>`, `[fill in]`, three-dot ellipsis as a standalone token (`...` alone on a line or surrounded by whitespace).

**Heuristic:** regex.

**Fix hint on fail:** "Found placeholder token '<token>' at line <N>. Replace with actual content OR remove the line."

### 11. `schema_completeness`

**Rule:** all 11 sections present with correct header text (case-sensitive match against the spec in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md`). NO extra top-level sections beyond the 11 + the optional body sections `## Considered Alternatives`, `## Milestones`, `## Problem & Evidence`, and `## Comment Resolution Map`. The optional sections are allowed-optional — present or absent both pass; the check never requires any of them. `## Problem & Evidence` appears only on PRD-mode specs (`/geniro:plan --prd`); `## Comment Resolution Map` appears only on `/geniro:resolve`-produced specs; a normal spec omits both and still passes.

**Heuristic:** parse all `## ` top-level headers; compare to the canonical list (11 required + 4 allowed-optional). A header outside that set fails; a missing optional section does not.

**Fix hint on fail:** "Section <name> missing OR misnamed at line <N>. Expected: '<canonical-header>'. Got: '<actual>'."

### 12. `workflow_refs_consistency`

**Rule:** for each entry in frontmatter `workflow_refs[]` (m5-v2, m5-v3, or m5-v4 — skipped on legacy `m5-v1` specs), a matching workflow file exists at either `./.geniro/workflow/<kind>.md` (cwd-local) OR `<PRIMARY_ROOT>/.geniro/workflow/<kind>.md` (primary fallback per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A). Per-entry required fields `kind`, `issue_id`, `url`, `fetched_at` are non-empty.

**m5-v3 chain-enrichment shape sub-checks (SHAPE-ONLY, key-presence-guarded):** when the m5-v3 fields are present on an entry, verify their shape — never their values, which are free-form fetched payload:
- Each `siblings[]` entry has a non-empty `issue_id` (the only required sibling sub-field; `title` / `status` are optional and unchecked).
- `chain_fetched_at` is non-empty when the key is present.
- `parent_ref.title` / `status` / `scope` are free-form optional cached payload — no check.

These sub-checks run on m5-v2 OR m5-v3 OR m5-v4 specs, guarded by key-presence (an entry without `siblings` / `chain_fetched_at` skips them), and never run on m5-v1.

**Heuristic:** YAML parse `workflow_refs[]`; for each entry, `test -f ./.geniro/workflow/<kind>.md || test -f <PRIMARY_ROOT>/.geniro/workflow/<kind>.md` (cwd-first, primary-fallback) + field-presence check. Skip the check entirely when `geniro_schema_version: m5-v1` OR `workflow_refs:` is absent. Inside the per-entry loop, when the entry carries `siblings`, assert each sibling has a non-empty `issue_id`; when it carries `chain_fetched_at`, assert it is non-empty.

**Status semantics:** this check returns `warn` (not `fail`) when a referenced workflow file is missing from BOTH locations — the workflow file may legitimately appear later in the project lifecycle (early-stage repos often link to trackers before authoring workflow files). Downstream skills skip workflow on-task-start hooks for unresolved kinds and continue. Field-presence violations (missing `kind` / `issue_id` / `url` / `fetched_at`, or a `siblings[]` entry missing `issue_id`) return `fail` — the entry is structurally broken.

**Fix hint on warn:** "spec.md `workflow_refs[]` references kind '<kind>' but `.geniro/workflow/<kind>.md` does not exist in cwd or primary worktree — downstream skills will skip workflow on-task-start hooks for this ref. Create the workflow file (see existing `linear.md` as template) OR remove the `workflow_refs` entry from spec.md frontmatter."

**Fix hint on fail:** "Entry <N> in `workflow_refs[]` is missing required field `<field>`. Re-run /geniro:plan with the tracker URL/ID in $ARGUMENTS so Phase 1 can re-fetch, OR hand-edit the entry to add the field."

**Fix hint on fail (sibling shape):** "Entry <N> siblings[<M>] is missing required field issue_id — re-run /geniro:plan with the tracker URL/ID so Phase 1 can re-fetch the chain, OR remove the malformed sibling entry."

### 13. `launch_config_consistency`

**Rule:** when frontmatter `launch_config:` is present (which implies `m5-v4`), each key's value is within its enum — `workspace` ∈ {`new-branch`, `current-branch`, `worktree`, `here`}; `deep_mode` ∈ {`true`, `false`}; `branch_freshness` ∈ {`merge`, `rebase`, `skip`}; `ship_mode` ∈ {`commit-no-push`, `draft-pr`, `ready-for-review`, `stop-after-review`}; and, when the optional `tracker_status` key is present, `tracker_status` ∈ {`move-to-in-progress`, `leave-unchanged`}. Shape-only — the check verifies enum membership, never executes anything. Canonical contract: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md`. Ordering note: the block is written at Phase 8.4 (after Phase 7 and any Phase 7.5 pass), so this check's present-branch fires on RE-validation of an existing spec (a later /geniro:plan run over the same task-dir); the write-time enum assertion lives in `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-8-user-approval.md` §8.4 step 2.

**Skip-when-absent:** skip the check entirely when `launch_config:` is absent — older specs without the block stay valid, mirroring how the `workflow_refs_consistency` check is skipped on legacy `m5-v1`. A legacy `m5-v1` / `m5-v2` / `m5-v3` spec that omits the block is never failed for not carrying it. The block is additive-optional: its absence is the default (`/geniro:implement` asks its Step 0 setup questions interactively) and never fails the spec.

**Heuristic:** YAML parse `launch_config`; skip the check entirely when the key is absent. When present, assert each of the four core keys (`workspace` / `deep_mode` / `branch_freshness` / `ship_mode`) is set to one of its enum values (case-sensitive); a missing core key, or an out-of-enum value, returns `fail`. The optional `tracker_status` key is key-presence-guarded: when present, assert it is in its enum; its absence does NOT fail (it is written only when the spec had a linked tracker ticket).

**Fix hint on fail:** "`launch_config.<key>` is '<value>' but must be one of {<enum>}. Set it to a valid enum value (see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md`), OR remove the `launch_config:` block to fall back to interactive /geniro:implement setup."

---

## Check API contract

The check API contract (`(check_id, status, finding_text, fix_hint)`) is fixed regardless of how the checks are executed — inline orchestrator-side logic (the default, since the orchestrator already parses spec.md and state.md) or a dedicated script.

`status` is one of `pass` / `fail` / `warn` / `skip`. Report one line per check in table order, so the transcript shows which checks ran. A check that was not actually executed reports `skip` with its reason — never `pass`. An aggregate tally ("13/13 clean") is not a validator result: it reads the same whether all thirteen ran or five did, which is exactly how a partial pass reaches the user looking like a complete one.
