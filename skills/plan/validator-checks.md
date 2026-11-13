# Phase 7 validator — check set

Canonical definitions of the mechanical validator checks fired in `/geniro:plan` Phase 7.

**Two execution surfaces, one contract.** A check decidable by a command is scripted: `${CLAUDE_PLUGIN_ROOT}/lib/validate-plan-spec.sh` runs it and its `check_id` appears in the printed rows — that emitted set, not a count restated here, enumerates the scripted checks, so adding one only means editing the script's own call list. The judgment checks turn on reasoning no command can make, so they stay prose the orchestrator applies itself. §The checks records which kind each is, and the run reports every check in §Contents' number order.

**Hard-fail handling:** `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-7-validator.md` §7.3.

## Contents

- Running the checks
- The checks: scripted table (1 `single_objective` / 2 `bounded_scope` / 4 `allowed_tools` / 6 `budget` / 7 `checkpoints` / 10 `placeholder_scan` / 11 `schema_completeness` / 12 `workflow_refs_consistency` / 13 `launch_config_consistency` / 14 `effort_tier`), then the judgment checks 3 `source_materials` / 5 `forbidden_actions` / 8 `validation_method` / 9 `stopping_condition`
- Check API contract

---

## Running the checks

Run the scripted checks first:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/validate-plan-spec.sh"
validate_plan_spec ".geniro/planning/<task-slug>/spec.md"
```

One TAB-separated `check_id status finding_text fix_hint` row per scripted check, in check-number order. `rc 0` = nothing failed (a `warn` or `skip` still exits 0), `rc 1` = at least one row is a `fail`, `rc 64` = no path passed, `rc 65` = path unreadable.

Then apply every judgment check below yourself against the same spec.md (`source_materials` also reads state.md `## Tool log`), and report every check in number order. Do not re-derive a scripted check by hand: the script is the rule, and a hand-run second opinion on it is a second home that drifts.

---

## The checks

### Scripted checks

Each script row carries its own finding text and `fix_hint`; this table records only what each check decides.

| # | `check_id` | Decides |
|---|---|---|
| 1 | `single_objective` | Section 1 is one sentence ending in a period. |
| 2 | `bounded_scope` | Sections 2 and 3 each carry a bullet; section 3 may instead be "none" plus a rationale. |
| 4 | `allowed_tools` | `tools_required` and section 7 agree on none versus a non-empty list. |
| 6 | `budget` | `max_files_to_edit` and `max_lines_changed` are present (`null` is legal; `/geniro:implement`'s scope-drift trigger reads them); a missing `time_budget` only warns. |
| 7 | `checkpoints` | Advisory, warn-only: with ≥5 steps, `checkpoints` is non-empty and its anchors resolve. |
| 10 | `placeholder_scan` | The body (frontmatter is out of scope) carries no `TODO` / `XXX` / `FIXME` / `<placeholder>` / `[fill in]` / bare `...`. |
| 11 | `schema_completeness` | Every required header is present with its exact `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md` text, with no top-level section beyond them and the optional `## Considered Alternatives` / `## Milestones`. |
| 12 | `workflow_refs_consistency` | Skipped on `m5-v1` or without `workflow_refs:`; missing required fields fail. A workflow file absent from cwd and the primary worktree (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A) only warns — it may appear later. |
| 13 | `launch_config_consistency` | Skipped when `launch_config:` is absent; otherwise its keys hold enum values (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md`), shape-only. |
| 14 | `effort_tier` | Lowercase `trivial` / `small` / `medium` / `big`. Phase 5 milestone-mode and `source_materials`' per-tier threshold both read it, so an absent or miscased value relaxes both silently. |

**Ordering note (13).** The block is written at Phase 8.4, after Phase 7 and any Phase 7.5 pass, so Phase 7 never sees it. The present-branch fires at write time (`${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-8-user-approval.md` §8.4 runs the script on the rewritten spec before committing) and on re-validation in a later run over the same task-dir.

**Judgment checks (3, 5, 8, 9)** carry their full rule, heuristic and fix hint below, because the orchestrator executes them.

### 3. `source_materials`

*Judgment.*

**Rule:** state.md `## Tool log` body has ≥1 Agent entry with `status: ok` per effort tier:
- Trivial: ≥1 (OR explicit "scope-bound, no exploration needed" note)
- Small: ≥1
- Medium: ≥2
- Big: ≥3

Also: spec.md section 6 (Steps) cites ≥1 file:line reference per non-trivial step, **each citation resolves**, and **each step this check exempts is named**.

**Heuristic:** parse `## Tool log` YAML entries, count Agent + status:ok; for section 6, match a `<path>:<line>` or `<path>:<line>-<line>` reference anywhere on the step's line (the `- [ ] N.` checkbox prefix does not affect it).

Then, per matched citation, decide two things a presence match cannot:

- **Does it resolve?** The path exists and the file is at least that long. A citation into a file that has moved, shrunk, or never existed is a dangling coordinate that reads as grounding. Cheap to settle; settle it.
- **Does it cover what the step asserts?** Read the cited span and compare it against the step's claim. A citation spanning two of six blocks passes a presence match while supporting a claim about all six, and one anchored a line off the deciding branch confirms a true line and a wrong step. Where a step asserts a quantity, the cited span must be the population that quantity was counted from, or the step needs a second citation that is.

**Naming the exemptions is part of the check.** "Non-trivial" is this check's own judgment, so a run can pass it by quietly reclassifying the steps it could not ground. Report every step treated as meta or trivial by number, with a one-line reason, in the verdict's output. An exemption a reader can see is a decision; one only the deciding run knew about is the check exempting itself.

**Fix hint on fail:** "Phase 1 explore did not produce enough citations for effort tier <tier>. Re-spawn research agents with sharper sub-queries, OR if scope-bound, add explicit "scope-bound, no exploration needed" entry to ## Tool log."

### 5. `forbidden_actions`

*Judgment.* A keyword scan is the trigger, not the verdict.

**Rule:** frontmatter `forbidden_actions` is a non-empty list when the task touches sensitive areas (auto-detected: presence of `auth`/`secret`/`migration`/`payment` keywords in section 1 Objective OR section 2 Scope.Included). Otherwise `null` is OK.

**Heuristic:** keyword scan, then field-presence check.

**Fix hint on fail:** "Sensitive keyword detected in objective/scope, but forbidden_actions is null. Add at least one explicit 'do NOT …' rule (e.g., 'do NOT bypass auth middleware')."

### 8. `validation_method`

*Judgment.* A section naming `unit` while describing nothing runnable passes the grep and fails the intent.

**Rule:** section 9 (Validation) has body content; either references a test type (`unit`, `integration`, `e2e`) OR specifies a manual-verification procedure.

**Sub-rule (`verify:` shape, optional field):** if a section 9 criterion carries a `verify:` field, it must be a non-empty command string. Shape-only — the validator never executes the command; /geniro:implement runs it at end-of-phase. A criterion without `verify:` still passes — the check never requires the field. Attaching one wherever a single read-only command can prove the criterion is the authoring default (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md` §9), an authoring bar rather than a validation bar.

**Heuristic:** body-non-empty + keyword/regex match; for each `verify:` occurrence, assert the remainder of the line is non-empty after trimming whitespace.

**Fix hint on fail:** "Section 9 (Validation) is empty or doesn't reference a concrete verification method. Add either a test type OR a manual procedure (e.g., 'manual: navigate to /login, click OAuth button, verify redirect'). If a criterion declares `verify:`, give it a non-empty command (or drop the empty `verify:` line)."

### 9. `stopping_condition`

*Judgment.*

**Rule:** section 11 (Done Condition) has body content matching pattern "<observable signal>" (e.g., "all 5 acceptance tests green", "PR approved by stakeholder X", "feature ships behind flag AND telemetry shows ≥1 successful use").

**Heuristic:** match against the stopping-condition ontology in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/done-condition-check.md` §"Stopping-condition ontology" — the canonical signal-shape set. Do not restate the patterns here: this spec-time check and the ship-time annotation must classify a clause identically, and a second copy is what lets them drift apart.

**Fix hint on fail:** "Section 11 (Done Condition) doesn't match an observable-signal phrase. Rewrite as a concrete completion criterion (e.g., '<observable signal> AND <verification>')."

**A quantity written to satisfy this check is a claim, not a formatting fix.** The auto-revision round that repairs a section-11 failure invites inventing the value that makes the signal checkable — a suite count, a row count, a duration nobody measured. The observed shape is a done condition naming a number the project never produces: perfectly checkable, permanently false, and reported by this check as a pass. So when a revision introduces or changes a quantity here, derive it from the project rather than from the sentence that needs filling, and enter it into the spec-challenge claim set as a `quantity` claim (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md` §3 item 5). Where the value cannot be derived at spec time, write the condition against the signal — "the suite is green" beats "48 suites pass" and cannot go stale. A baseline or target in the section's outcome clause (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md` §"Section 11") is a `quantity` claim on the same terms: read through a declared source or invented, and the claim set settles which.

---

## Check API contract

Every check returns `(check_id, status, finding_text, fix_hint)`, whichever surface produced it.

`status` is one of `pass` / `fail` / `warn` / `skip`. Report one line per check in number order, so the transcript shows which checks ran. A check that was not actually executed reports `skip` with its reason — never `pass`. An aggregate tally (e.g. "N/N clean") is not a validator result: it reads the same whether every check ran or only some did, which is exactly how a partial pass reaches the user looking like a complete one.
