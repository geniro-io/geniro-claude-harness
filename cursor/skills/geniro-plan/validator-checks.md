<!-- Generated from skills/plan/validator-checks.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Phase 7 validator — check set

Canonical definitions of the mechanical validator checks fired in `/geniro:plan` Phase 7. These are deterministic, script-checkable rules, near-zero token usage.

**Two execution surfaces, one contract.** A check decidable by a command is scripted: `${CLAUDE_PLUGIN_ROOT}/lib/validate-plan-spec.sh` runs it and its `check_id` appears in the printed rows — that emitted set, not a count restated here, is the enumeration of which checks are scripted, so adding one only means editing the script's own call list. Each check's *Scripted*/*Judgment* tag below is the single record of which kind it is. The judgment checks turn on reasoning no command can make — whether a citation is load-bearing, whether an area is sensitive, whether a verification method is real, whether a done-condition names an observable signal — so they stay prose the orchestrator applies itself. Both surfaces emit the same tuple, and the run reports every check in §Contents' number order.

**Status:** Authoritative. Each check returns `(check_id, status, finding_text, fix_hint)`. Output: list of failing checks → state.md `## Open Questions` body section.

**Hard-fail handling:** see `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-7-validator.md` §7.3 — the auto-revision round cap, then AUQ to user with 3 options (accept-as-is / re-revise / abort).

## Contents

- Running the checks
- The checks: 1 `single_objective` / 2 `bounded_scope` / 3 `source_materials` / 4 `allowed_tools` / 5 `forbidden_actions` / 6 `budget` / 7 `checkpoints` / 8 `validation_method` / 9 `stopping_condition` / 10 `placeholder_scan` / 11 `schema_completeness` / 12 `workflow_refs_consistency` / 13 `launch_config_consistency` / 14 `effort_tier`
- Check API contract

---

## Running the checks

Run the scripted checks first:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/validate-plan-spec.sh"
validate_plan_spec ".geniro/planning/<task-slug>/spec.md"
```

One TAB-separated `check_id status finding_text fix_hint` row per scripted check, in check-number order. `rc 0` = nothing failed (a `warn` or `skip` still exits 0), `rc 1` = at least one row is a `fail`, `rc 64` = no path passed, `rc 65` = path unreadable.

Then apply every check tagged *Judgment* below yourself against the same spec.md (`source_materials` also reads state.md `## Tool log`), and report every check in number order. Do not re-derive a scripted check by hand: the script is the rule, and a hand-run second opinion on it is a second home that drifts.

---

## The checks

Each scripted check below states what it decides and what a `fail` means, so a returned row is actionable without opening the script; the exact predicate and the `fix_hint` text live in the script. Each judgment check carries its full rule, heuristic and fix hint, because the orchestrator is the one executing it.

### 1. `single_objective`

*Scripted.* Section 1 (Objective) is exactly one goal sentence ending in a period — imperative ("Add X.") or declarative ("X is added."), never interrogative. Fails on an empty section, a question, a missing terminating period, or more than one sentence. A dotted file path inside the sentence (`src/constants.ts:12`) is not a sentence break.

### 2. `bounded_scope`

*Scripted.* Sections 2 (Scope — Included) and 3 (Scope — Excluded) both carry at least one bullet. The single escape hatch is section 3 declaring open scope — a body opening with "none" plus a written rationale; a bare "none" fails.

### 3. `source_materials`

*Judgment.* Deciding whether a citation actually grounds its step, and whether "scope-bound, no exploration needed" is honest rather than convenient, is why this one is not scripted.

**Rule:** state.md `## Tool log` body has ≥1 Agent entry with `status: ok` per effort tier:
- Trivial: ≥1 (OR explicit "scope-bound, no exploration needed" note)
- Small: ≥1
- Medium: ≥2
- Big: ≥3

Also: spec.md section 6 (Steps) cites ≥1 file:line reference per non-trivial step, **each citation resolves**, and **each step this check exempts is named**.

**Heuristic:** parse `## Tool log` YAML entries, count Agent + status:ok; for section 6, match a `<path>:<line>` or `<path>:<line>-<line>` reference anywhere on the step's line (the `- [ ] N.` checkbox prefix does not affect it).

Then, per matched citation, decide two things a presence match cannot:

- **Does it resolve?** The path exists and the file is at least that long. A citation into a file that has since moved, shrunk, or never existed is a dangling coordinate that reads as grounding — and the executor follows it into nothing. Cheap to settle; settle it.
- **Does it cover what the step asserts?** Read the cited span and compare it against the step's claim. A citation spanning two of the six blocks a step depends on passes a presence match while supporting a claim about all six, and a citation anchored one line off the branch that decides the behavior confirms a line that is true and a step that is wrong. Where a step asserts a quantity, the cited span must be the population that quantity was counted from, or the step needs a second citation that is.

**Naming the exemptions is part of the check.** "Non-trivial" is this check's own judgment, so a run can pass it by quietly reclassifying the steps it could not ground. Report every step treated as meta or trivial by number, with the one-line reason, in the same output as the verdict. An exemption a reader can see is a decision; an exemption only the deciding run knew about is the check exempting itself.

**Fix hint on fail:** "Phase 1 explore did not produce enough citations for effort tier <tier>. Re-spawn research agents with sharper sub-queries, OR if scope-bound, add explicit "scope-bound, no exploration needed" entry to ## Tool log."

### 4. `allowed_tools`

*Scripted.* Frontmatter `tools_required` and section 7 (Tools Required) agree: a "none" body pairs with a null or absent field, a body with real content pairs with a non-empty list (inline or block form). Fails on either mismatch.

### 5. `forbidden_actions`

*Judgment.* A keyword scan is the trigger, not the verdict — whether a spec that touches `auth` genuinely needs a forbidden action, and whether the one written is the right one, is a reading of the task.

**Rule:** frontmatter `forbidden_actions` is a non-empty list when the task touches sensitive areas (auto-detected: presence of `auth`/`secret`/`migration`/`payment` keywords in section 1 Objective OR section 2 Scope.Included). Otherwise `null` is OK.

**Heuristic:** keyword scan, then field-presence check.

**Fix hint on fail:** "Sensitive keyword detected in objective/scope, but forbidden_actions is null. Add at least one explicit 'do NOT …' rule (e.g., 'do NOT bypass auth middleware')."

### 6. `budget`

*Scripted.* The frontmatter `budget` block carries all three sub-fields (`max_files_to_edit` / `max_lines_changed` / `time_budget`). Key presence only — `null` is a legal value for an unbounded key, an absent key is not.

### 7. `checkpoints`

*Scripted.* When section 6 (Steps) has ≥5 steps, frontmatter `checkpoints` is a non-empty list and every `step_anchor: step-N` resolves to a real step. Steps are counted by their `- [ ] N.` checkbox lines, equivalently by `<!-- step-N -->` anchors — not by a bare leading digit. Under 5 steps the check passes without requiring checkpoints. A checkpoint naming a section rather than a step anchor is left to the reader.

### 8. `validation_method`

*Judgment.* "References a test type" is greppable; "is a real verification method" is not — a section naming `unit` while describing nothing runnable passes the grep and fails the intent.

**Rule:** section 9 (Validation) has body content; either references a test type (`unit`, `integration`, `e2e`) OR specifies a manual-verification procedure.

**Sub-rule (`verify:` shape, optional field):** if a section 9 criterion carries a `verify:` field, it must be a non-empty command string. Shape-only — the validator never executes the command; /geniro:implement runs it at end-of-phase. A criterion without `verify:` still passes — the check never requires the field. Attaching one wherever a single read-only command can prove the criterion is the authoring default (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md` §9), an authoring bar rather than a validation bar.

**Heuristic:** body-non-empty + keyword/regex match; for each `verify:` occurrence, assert the remainder of the line is non-empty after trimming whitespace.

**Fix hint on fail:** "Section 9 (Validation) is empty or doesn't reference a concrete verification method. Add either a test type OR a manual procedure (e.g., 'manual: navigate to /login, click OAuth button, verify redirect'). If a criterion declares `verify:`, give it a non-empty command (or drop the empty `verify:` line)."

### 9. `stopping_condition`

*Judgment.* Classifying a clause as an observable signal is the same judgment the ship-time annotation makes, and the two must agree — which is why both read one ontology instead of a regex.

**Rule:** section 11 (Done Condition) has body content matching pattern "<observable signal>" (e.g., "all 5 acceptance tests green", "PR approved by stakeholder X", "feature ships behind flag AND telemetry shows ≥1 successful use").

**Heuristic:** match against the stopping-condition ontology in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/done-condition-check.md` §"Stopping-condition ontology" — the canonical signal-shape set. Do not restate the patterns here: this spec-time check and the ship-time annotation must classify a clause identically, and a second copy is what lets them drift apart.

**Fix hint on fail:** "Section 11 (Done Condition) doesn't match an observable-signal phrase. Rewrite as a concrete completion criterion (e.g., '<observable signal> AND <verification>')."

**A quantity written to satisfy this check is a claim, not a formatting fix.** The auto-revision round that repairs a section-11 failure is the one place in the loop where a check's own demand for a machine-checkable signal invites inventing the value that makes it checkable — a suite count, a row count, a duration nobody measured. The observed shape is a done condition naming a number the project never produces: perfectly checkable, permanently false, and reported by this check as a pass. So when a revision introduces or changes a quantity here, derive it from the project rather than from the sentence that needs filling, and enter it into the spec-challenge claim set as a `quantity` claim (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md` §3 item 5). Where the value cannot be derived at spec time, write the condition against the signal instead of the number — "the suite is green" beats "48 suites pass" and cannot go stale. A baseline or target in the section's outcome clause (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md` §"Section 11") is a `quantity` claim on the same terms: it was either read through a declared source or it was invented, and the claim set is where that gets settled.

### 10. `placeholder_scan`

*Scripted.* The spec body carries none of `TODO`, `XXX`, `FIXME`, `<placeholder>`, `[fill in]`, or a standalone three-dot ellipsis. Frontmatter is out of scope — a fetched tracker payload may legitimately carry a `TODO` status. The finding names the offending token and its line.

### 11. `schema_completeness`

*Scripted.* All 11 required section headers are present with their exact canonical text (case-sensitive, from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md`), and no top-level `## ` section exists outside them plus the two allowed-optional ones (`## Considered Alternatives`, `## Milestones`). Both are allowed-optional: present or absent pass equally, so a spec that omits the milestone-only section is complete.

### 12. `workflow_refs_consistency`

*Scripted.* Skipped entirely on legacy `m5-v1` or when `workflow_refs:` is absent. Otherwise every entry carries non-empty `kind` / `issue_id` / `url` / `fetched_at`, and the m5-v3 chain-enrichment fields are shape-checked where present — each `siblings[]` entry has a non-empty `issue_id`, and a present `chain_fetched_at` is non-empty. `parent_ref.title` / `status` / `scope` are free-form cached payload and are never checked.

**Status semantics:** a field-presence violation returns `fail` — the entry is structurally broken. A referenced workflow file missing from BOTH `./.geniro/workflow/<kind>.md` and `<PRIMARY_ROOT>/.geniro/workflow/<kind>.md` (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A) returns `warn`, not `fail` — the workflow file may legitimately appear later in the project lifecycle, and downstream skills simply skip workflow on-task-start hooks for unresolved kinds and continue.

### 13. `launch_config_consistency`

*Scripted.* Skipped entirely when `launch_config:` is absent — older specs without the block stay valid, mirroring the `m5-v1` skip above, and its absence is the default (`/geniro:implement` then asks its Step 0 setup questions interactively). When present, each of the four core keys (`workspace` / `deep_mode` / `branch_freshness` / `ship_mode`) is set to one of its enum values, case-sensitively, and the optional `tracker_status` is checked only when the key is there. Shape-only; nothing is executed. Canonical contract: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md`.

**Ordering note:** the block is written at Phase 8.4 (after Phase 7 and any Phase 7.5 pass), so this check's present-branch fires on RE-validation of an existing spec — a later /geniro:plan run over the same task-dir. The write-time enum assertion lives in `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-8-user-approval.md`, §8.4's launch-config enum assertion.

### 14. `effort_tier`

*Scripted.* Frontmatter carries `effort_tier`, set to one of `trivial` / `small` / `medium` / `big`, lowercase. Fails on an absent field and on any other value, `Trivial` included.

The field is not a label: Phase 5 milestone-mode fires off the Big tier, and check `source_materials`'s research-agent threshold is read per tier. Both read it by comparing against the lowercase enum, so an absent or miscased value relaxes both without saying so — the shape of failure a shipped spec cannot show you.

---

## Check API contract

The `(check_id, status, finding_text, fix_hint)` tuple is fixed regardless of which surface produced it — the script for its own emitted rows, orchestrator-side reasoning for everything tagged *Judgment*.

`status` is one of `pass` / `fail` / `warn` / `skip`. Report one line per check in table order, so the transcript shows which checks ran. A check that was not actually executed reports `skip` with its reason — never `pass`. An aggregate tally (e.g. "N/N clean") is not a validator result: it reads the same whether every check ran or only some did, which is exactly how a partial pass reaches the user looking like a complete one.
