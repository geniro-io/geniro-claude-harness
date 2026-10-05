# Debug — detailed reference

Detail sections the `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md` spine and the phase files cite by section number — the numbers are citation targets and stay fixed.

## Contents

1. State machine — full ASCII diagram + state semantics
2. State file schema — frontmatter + body sections (T1.5 state.md, T2 handoff files)
3. Infrastructure investigation — signals + investigation checklist
5. Stall diagnosis taxonomy — 8-component missing-component table
6. Adversarial Mode template — A6 findings template
8. Open-PR scan — check open PRs for an existing fix (Scientific Mode Phase 1)
9. L2 emit payload shapes — canonical `emit_learning` call shapes (`diagnosis` Phase 3 §3.3, `discarded_hypothesis` Phase 1 §1.5, `pitfall` Adversarial Mode A4 step 5)

---

## 1. State machine — full ASCII diagram

state.md `phase:` enum transitions:

```
[entry] → mode-detect ── investigate ──┬── propose ──┬── ship ──┬── done (terminal)
                                       │             │          └── ship-summary-only (terminal — "Leave it to me")
                                       │             │
                                       │             └── phase-2-escalated ──┬── ship (accept-as-documented-limitation)
                                       │                                     ├── investigate (try-different-approach loop-back)
                                       │                                     └── aborted (terminal)
                                       │
                                       └── phase-1-escalated ──┬── investigate (supply-data loop-back)
                                                               ├── ship (abandon — partial findings; Phase 3 exit
                                                               │         resolves to whichever terminal §3.2 picks)
                                                               └── aborted (terminal)

investigate ── (§1.6 second refuted/clarified verifier round) ── phase-1-verification-stalled ──┬── investigate (try-different-hypothesis loop-back)
                                                                                                  ├── propose (proceed-with-unverified; no phase write)
                                                                                                  └── aborted (terminal)

[entry] → adversarial-mode-detect ── adversarial-investigate ──┬── (A3 skip condition) ── adversarial-aborted (terminal)
                                                                └── adversarial-ship ──┬── done (Run /geniro:implement)
                                                                                       ├── adversarial-ship-summary-only (terminal — Leave it to me)
                                                                                       └── adversarial-aborted (terminal — zero red tests after F→P + flake check)
```

Each escalation edge leaves the phase whose gate writes it: `phase-1-escalated` from `investigate` (the stall gate), `phase-1-verification-stalled` from `investigate` (the §1.6 verification-stalled gate, on a second consecutive refuted/clarified verifier round), `phase-2-escalated` from `propose` (the fix-loop gate).

**Terminal states:** `done`, `ship-summary-only`, `aborted`, `adversarial-aborted`, `adversarial-ship-summary-only`. The SessionStart recovery treats all five as "task complete — no resume needed".

**Non-terminal states:** `mode-detect`, `investigate`, `propose`, `ship`, `adversarial-mode-detect`, `adversarial-investigate`, `adversarial-ship`. The recovery rolls these back to phase-entry and re-runs (idempotent — `approvals[]` ensures gates skip already-answered).

**Escalation states:** `phase-1-escalated`, `phase-1-verification-stalled`, `phase-2-escalated`. The recovery surfaces these to the user as "task was paused — your previous options:" so the user re-picks without losing context.

The `## Termination reason` body section is written on `aborted` / `adversarial-aborted` terminals.

---

## 2. State file schema

### state.md (T1.5 — session-bound, `.geniro/state/debug/<slug>/state.md`)

Frontmatter:

```yaml
---
tier: T1.5
producer: debug
schema-version: 1
branch: <git-branch>
timestamp: <ISO-8601 UTC>
phase: <enum per State Machine above>
status: <in-progress|done|failed>
non-resumable-actions: []
approvals: []                         # categories: branch_freshness, disambiguate_mode, multi_path_fix, verification_stalled, existing_fix_pr, debug_workspace_setup
baseline-dirty-paths: []              # git status --porcelain changed-path list captured at Phase 0 entry (Step 0.1), before this run touches anything; consumed by Phase 3 §3.1's working-tree check, Scientific Mode only — Adversarial Mode's ship path never reads it
geniro_kind: debug-state
geniro_schema_version: m7-v1
mode: <scientific|adversarial>
task_slug: <slug>
worktree: <abs-path>
---
```

Body sections (Scientific Mode):

- `## Symptom`
- `## Reproduction Steps`
- `## Feedback Loop` (Original command — un-minimised, as first run / Command — the minimised form / Expected output / Actual output / Re-run cost / Determinism — includes any rate-raising attempt + outcome for intermittent bugs)
- `## Hypotheses` (Hypothesis / Evidence For / Evidence Against / Status / Test Plan / Result per hypothesis)
- `## Root Cause` (Validation: confirmed | unverified / Verification-evidence — written by §1.6's independent verification)
- `## Proposed Fix`
- `## Reproduction Test`
- `## Accepted Limitations` (optional, path B)
- `## Tool log` — selective logging (stall escalations, fix-loop escalations)
- `## Errors`
- `## Open Questions` (stall AUQ + outcome)
- `## Resolved Questions` (Phase 3 §3.0 Pre-gate writes resolution mirror here)
- `## Termination reason` (only on terminal aborted-state)
- `## Persisted approvals` (render of frontmatter approvals[])

Body sections (Adversarial Mode):

- `## Diff Scope` (range + file count + LOC)
- `## Authored Tests` — the column set canonical at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §`## Authored Tests` body table, shared with `/geniro:implement` Phase 3
- `## Re-verification Results` (per authored test, written by A4 step 3: path / F→P + flake-check status / kept or discarded / discard reason if discarded)
- `## Tool log`, `## Errors`, `## Termination reason`

### from-debug-<branch>.md (T2 — handoff, Scientific Mode)

Path: `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md`. Single file per branch, overwritten on next debug run.

```yaml
---
tier: T2
producer: debug
consumer: implement
schema-version: 1
branch: <git-branch>
timestamp: <ISO-8601 UTC>
worktree: <abs-path>
geniro_kind: debug-handoff
geniro_schema_version: m7-v2
mode: scientific
phase: ship
status: done
approvals: []
non-resumable-actions: []
authored_tests: []                    # entry fields: id, path, intent, mode, f_to_p_status,
                                      #   related_hypotheses, targeted_source, confidence
original_repro: <command>             # optional — the un-minimised reproduction command; self-contained (runs after §3.4
                                      #   deletes scratch files and kills debug's dev server); exits non-zero while the
                                      #   bug reproduces, zero once fixed; omitted when no such command exists
open_questions: []                    # entry-field schema: ${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md §T2
---
```

Secrets are redacted from the whole file at write time (`phase-3-ship.md` §3.1), which is why §1.3 builds the loop on environment variables.

Body: full content of findings template + body sections (`## Tool log` / `## Errors` / `## Open Questions` (human-readable mirror of frontmatter) / `## Resolved Questions` / `## Persisted approvals`).

`original_repro` is /geniro:implement's post-fix re-run of the user's actual scenario — minimising can drop a second cause, so the minimised reproduction test going green does not prove it; handoffs predating the field simply lack it. Both arrays are present on every handoff and may be empty `[]`; the per-field schema, enums, and producer/consumer responsibilities live in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` — `open_questions[]` under §T2, `authored_tests[]` under §Producer-specific extensions. Restating the fields here is what lets them drift out of step with /geniro:implement's consumer, so read the schema there rather than from a copy.

Debug-specific values within those schemas: `mode:` matches the handoff's top-level `mode:` discriminator (`scientific` here, `adversarial` for the adversarial handoff); `source:` names the gate that raised the question (`phase-1-stall-gate`, `phase-1-missing-data-gate`, `phase-3-cannot-verify`); `resolution.resolved_by:` is `debug`, `implement`, or `manual`.

The `authored_tests[]` frontmatter array is the machine-readable source of truth for the F→P tests this debug run produced. Body lines `**Reproduction test:**` (scientific) and `**Test file:**` (adversarial, A6 template) remain as human-readable mirrors of this array. Consumers (notably /geniro:implement Phase 1 handoff-resolution step) prefer the frontmatter; legacy handoffs at `geniro_schema_version: m7-v1` lack this field, so the consumer protocol in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/debug-handoff.md` falls back to body-string parsing in that case.

### from-debug-adversarial-<branch>.md (T2 — handoff, Adversarial Mode)

Path: `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md`. Same schema as from-debug-<branch>.md with `mode: adversarial` and `phase: adversarial-ship` discriminators. Body: A6 Adversarial Findings template + body sections.

---

## 3. Infrastructure investigation

When symptoms suggest the bug may not be in the code (timeouts, intermittent failures, environment-specific errors, deployment regressions), investigate infrastructure before or alongside code hypotheses.

**Signals requiring at least one infrastructure hypothesis:** timeouts; intermittent failures (error rate >0 but <100%); environment-only manifestation (works locally, breaks in staging/prod); latency degradation without a code change; symptoms correlating with a deployment, config change, secret rotation, or scale event.

**What to investigate:** logs, service health, environment/config diffs between the working and broken environments, and resource limits. The entries that get missed sit inside those categories — **certificate expiry**, **secret rotation**, and **connection-pool size vs active connections** — each breaks a running system while every code path is still correct.

**Hypothesis quality bar:** "The database connection pool is exhausted under load" is testable — names the resource, condition, and observable signature. "Something is wrong with the server" is NOT a hypothesis — no variable to toggle, no falsifiable prediction.

---

## 5. Stall diagnosis taxonomy

When /geniro:debug stalls (the stall gate fires — threshold defined in `${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-1-investigate.md` §1.7), classify the root-cause-of-the-stall as a missing component:

| # | Missing component | Symptom | AUQ option label | AUQ description |
|---|---|---|---|---|
| A | **Missing instruction** | Hypothesis tests don't converge because the orchestrator lacks a project-specific rule (e.g., "we use SQS not Kafka here") | "Missing project rule" | Paste the rule or point to a CLAUDE.md / `.geniro/instructions/*` section |
| B | **Missing source-of-truth** | Test results contradict reasonable assumptions because canonical state (DB row, prod log line, third-party API response) is unreachable | "Missing source of truth" | Paste the DB row / log line / API response |
| C | **Missing tool** | Orchestrator cannot read the artifact format (binary blob, proprietary protocol, sandboxed environment) | "Missing tool" | Provide the parsed/decoded form, or specify a tool the user can run locally |
| D | **Missing validator** | Hypothesis tests "pass" via narrative-only Result but cannot be objectively verified (e.g., race-condition theories) | "Missing validator" | Author a deterministic re-runnable check (curl + grep, SQL query, regex on log) |
| E | **Missing permission rule** | Hypothesis blocked by a permission deny | "Missing permission" | Add the permission rule to the project's Claude Code settings, or run the command yourself and paste the output |
| F | **Missing sandbox signal** | Tests inconclusive because environment differs from production (Docker vs. host, ARM vs. x86) | "Missing sandbox signal" | Re-run in the production-like environment and paste the captured signal |
| G | **Missing eval** | Bug type has no existing regression test pattern in the project — hypotheses cannot be expressed in the existing test framework | "Missing eval pattern" | Author a new test pattern (parameterized fuzzer, mutation-test seed, etc.) |
| H | **Missing recovery path** | All hypotheses confirmed but the fix path is unclear because the bug spans a DI / generated-code / framework-internal layer | "Missing recovery path" | Specify whether the production-source escape hatch is acceptable, or escalate as architectural |

---

## 6. Adversarial Mode template

### A6 findings template

After the A4 step 3 authoring-and-verification loop, present this block directly in chat and persist it via A4 step 4:

```markdown
## Adversarial Findings

**Diff scope:** [range + file count + LOC]

**Hypotheses generated:** [N]
**Tests authored (kept after F→P + flake check):** [M]
**Tests discarded (F→P or flake check failed):** [K]

### CRITICAL / HIGH findings
[For each finding, emit these labelled lines — the `**Test file:**` line is the human-readable mirror of the `authored_tests[]` frontmatter array that consumers fall back to parsing for legacy handoffs:]
- **Test file:** `<path>`
- **Targeted source:** `<file:line>`
- **Category:** <category> · **Confidence:** <0-100>
- **Hypothesis:** <what breaks and why>
- **Reproduction:** `<command>`
- **Suggested direction:** <fix direction, NOT the patch itself>

### MEDIUM findings
[same labelled shape]

### Discarded / Inconclusive
[brief list with reasons]

**Special handling:** [omit unless the authored-test secret scan hit — "fixture in `<path>` matches a secret pattern; swap in an environment variable before committing"]

**Zero red tests?** [If M == 0: state plainly "no bugs found in scanned diff" — this is a valid outcome.]
```

---

## 8. Open-PR scan — already fixed elsewhere?

Phase 1 (Scientific Mode) sub-step referenced from `${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-1-investigate.md` §1.2. Checks whether an open PR already fixes the bug under investigation, so a debug session does not re-investigate something a teammate is already patching. The probe itself — the query, relevance scoring, the top-5 cap, and unreachable-source handling — is `${CLAUDE_PLUGIN_ROOT}/skills/_shared/prior-work-scan.md` §2 (Open pull requests) / §3 (Bounds) / §4 (On a hit) / §5 (Unreachable handling); this section covers only the inputs debug feeds it and what debug does with a hit. Read-only; never opens, edits, or comments on a PR (debug's no-ship boundary holds).

**When it runs.** After §1.2 Observe & repro, once the symptom and suspect files are known, before §1.4 Hypothesize — those are exactly the inputs the scan needs, and Adversarial Mode's diff-only flow (no symptom, no Observe & repro) never produces them. Scientific Mode only, for that reason.

**Inputs debug supplies.** `suspect_files` — the suspect / recently-changed files §1.2 identified. `keywords` — distinctive tokens from the symptom or error string (function names, error codes, unique phrases), stop-words dropped.

**On a strong hit**, `AskUserQuestion` (header `"Existing fix"`; question names the matched PR and why it matched):

- **Review that PR's diff first** — if it resolves the bug, skip the hypothesis loop and go to Phase 3, naming the existing PR in the findings **Proposed fix** line (`already fixed in open PR #N <url> — no new patch needed`) so it reaches the downstream consumer through the persisted handoff body (§3.1), not just chat. If it does not resolve the bug, record why in `## Hypotheses` and keep investigating.
- **Test it as a hypothesis** — form a hypothesis that the PR's change fixes the bug and test it against the feedback loop like any other hypothesis (§1.5).
- **Ignore — keep investigating** — discard the match and proceed to §1.4.

Persist the pick to state.md frontmatter `approvals[]` category `existing_fix_pr` via `atomic_state_append_list_item`, so the session-start restore re-applies it across a compaction or resume. The matched PR itself rides to the consumer in the findings body above, not a new handoff field.

---

## 9. L2 emit payload shapes — canonical `emit_learning` call shapes

`emit_learning` reads a single JSON object on stdin; a YAML payload exits 64, and mis-named or missing `ext` sub-fields silently drop the typed extension. Mirror the shapes below exactly — the field names match the helper contract in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §Example callers; the echo and non-zero-return rules for every emit are its §Caller contract.

### `diagnosis` (Phase 3 §3.3)

Required `ext.{symptom, root_cause, fix}`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh"
emit_learning <<'EOF'
{
  "producer": "/geniro:debug",
  "scope": "src/components/Toggle.tsx",
  "summary": "Stale closure in useEffect — value missing from deps",
  "tags": ["bug", "react", "useEffect"],
  "type": "diagnosis",
  "ext": {
    "symptom": "toggle stale",
    "root_cause": "missing dep",
    "fix": "add value to deps array"
  },
  "trust": "verified"
}
EOF
```

Substitute the run's real values: `scope` = the affected file/module path glob; `summary` = the one-line root-cause statement; `tags` inferred from affected files + hypothesis category; `ext.symptom` / `ext.root_cause` / `ext.fix` = the confirmed observation, isolated cause, and proposed patch. After a successful emit, echo `Recorded learning: <summary>` — the helper writes silently, so the echo is the only in-session proof it ran.

### `discarded_hypothesis` (Phase 1 §1.5)

Same invocation form (`source "${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh"` + heredoc). Required `ext.{hypothesis, evidence_against, tested_by}`:

```json
{
  "producer": "/geniro:debug",
  "scope": "services/payments/refunds.py",
  "summary": "env-vars differ — eliminated (env identical local/CI)",
  "tags": ["bug", "ci", "env-vars"],
  "type": "discarded_hypothesis",
  "ext": {
    "hypothesis": "env-vars differ between local and CI",
    "evidence_against": "diff <(env | sort) <(ssh ci env | sort) returns empty",
    "tested_by": "manual env diff"
  },
  "trust": "verified"
}
```

Substitute the run's real values: `scope` = the file/module the hypothesis targeted; `ext.evidence_against` = the captured artifact that eliminated it (per the Evidence Standard, not narrative).

### `pitfall` (Adversarial Mode A4 step 5)

Same invocation form. One entry per RED test kept after the A4 step 3 F→P and flake-check verification — no `ext` block:

```json
{
  "producer": "/geniro:debug",
  "scope": "src/api/handler.ts",
  "summary": "Empty payload reaches the handler with no null check and throws",
  "tags": ["bug", "null-check", "api"],
  "type": "pitfall",
  "trust": "verified"
}
```

Substitute the run's real values: `scope` = the production source path the kept test targets (its `targeted_source`); `summary` = the defect in one line (mirrors the A6 **Hypothesis** line); `tags` inferred from the A6 **Category** column plus the changed files. `trust: verified` — the F→P and flake-check run (A4 step 3) is the captured artifact. After each successful emit, echo `Recorded learning: <summary>`.
