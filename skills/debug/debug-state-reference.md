# Debug — detailed reference

Detail sections extracted from `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md` to keep the main skill body lean. The orchestrator reads this file when SKILL.md references one of the sections below by name.

## Contents

1. State machine — full ASCII diagram + state semantics
2. State file schema — frontmatter + body sections (T1.5 state.md, T2 handoff files)
3. Infrastructure investigation — signals + investigation checklist
4. Isolation techniques — binary search, git bisect, profiling
5. Stall diagnosis taxonomy — 8-component missing-component table
6. Adversarial Mode templates — A5 spawn prompt + A6 findings template
7. Extended examples — intermittent timeout + verify recent changes
8. Open-PR scan — check open PRs for an existing fix (Scientific Mode Phase 1)
9. L2 emit payload shapes — canonical `emit_learning` call shapes (`diagnosis` Phase 3 §3.3, `discarded_hypothesis` Phase 1 §1.5, `pitfall` Adversarial Mode A4 step 6)

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
                                                               │         writes the terminal ship-summary-only)
                                                               └── aborted (terminal)

investigate ── (§1.6 second refuted/clarified verifier round) ── phase-1-verification-stalled ──┬── investigate (try-different-hypothesis loop-back)
                                                                                                  ├── propose (proceed-with-unverified; no phase write)
                                                                                                  └── aborted (terminal)

[entry] → adversarial-mode-detect ── adversarial-investigate ── adversarial-ship ──┬── done
                                                                                   └── adversarial-aborted (terminal — zero red tests)
```

Each escalation edge leaves the phase whose gate writes it: `phase-1-escalated` from `investigate` (the stall gate), `phase-1-verification-stalled` from `investigate` (the §1.6 verification-stalled gate, on a second consecutive refuted/clarified verifier round), `phase-2-escalated` from `propose` (the fix-loop gate).

**Terminal states:** `done`, `ship-summary-only`, `aborted`, `adversarial-aborted`. The SessionStart recovery treats all four as "task complete — no resume needed".

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
approvals: []                         # categories: branch_freshness, disambiguate_mode, multi_path_fix, verification_stalled, deep_mode_choice, existing_fix_pr
deep-mode: <true|false>               # optional, set by the --deep flag or the Phase 0 Debug-depth chooser; missing reads as false
baseline-dirty-paths: []              # git status --porcelain changed-path list captured at Phase 0 entry (Step 0.3, Scientific Mode only), before this run touches anything; Phase 3 §3.1's working-tree check subtracts it
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
- `## Feedback Loop` (Command — the minimised form / Expected output / Actual output / Re-run cost / Determinism — includes any rate-raising attempt + outcome for intermittent bugs)
- `## Hypotheses` (Hypothesis / Evidence For / Evidence Against / Status / Test Plan / Result per hypothesis)
- `## Root Cause` (Validation: confirmed | unverified / Verification-evidence — written by §1.6's independent verification)
- `## Proposed Fix`
- `## Reproduction Test`
- `## Accepted Limitations` (optional, path B)
- `## Tool log` — selective logging (adversarial-tester-agent spawns, stall escalations)
- `## Errors`
- `## Open Questions` (stall AUQ + outcome)
- `## Resolved Questions` (Phase 3 §3.0 Pre-gate writes resolution mirror here)
- `## Termination reason` (only on terminal aborted-state)
- `## Persisted approvals` (render of frontmatter approvals[])

Body sections (Adversarial Mode):

- `## Diff Scope` (range + file count + LOC)
- `## Authored Tests` (table: # / Path / Targeted source / Category / Confidence / F→P status)
- `## Re-verification Results` (per authored test, written by A4 step 4: path / pre-rerun F→P status / kept or discarded / discard reason if discarded)
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
deep-mode: <true|false>               # propagated from state.md; producer→consumer in lockstep; missing reads as false
approvals: []
non-resumable-actions: []
authored_tests: []                    # entry fields: id, path, intent, mode, f_to_p_status,
                                      #   related_hypotheses, targeted_source, confidence
open_questions: []                    # entry-field schema: ${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md §T2
---
```

Body: full content of findings template + body sections (`## Tool log` / `## Errors` / `## Open Questions` (human-readable mirror of frontmatter) / `## Resolved Questions` / `## Persisted approvals`).

Both arrays are present on every handoff and may be empty `[]`; the per-field schema, enums, and producer/consumer responsibilities live in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` — `open_questions[]` under §T2, `authored_tests[]` under §Producer-specific extensions. Restating the fields here is what lets them drift out of step with /geniro:implement's consumer, so read the schema there rather than from a copy.

Debug-specific values within those schemas: `mode:` matches the handoff's top-level `mode:` discriminator (`scientific` here, `adversarial` for the adversarial handoff); `source:` names the gate that raised the question (`phase-1-stall-gate`, `phase-1-missing-data-gate`, `phase-3-cannot-verify`); `resolution.resolved_by:` is `debug`, `implement`, or `manual`.

The `open_questions[]` frontmatter array is the machine-readable source of truth. The body `## Open Questions` section is a human-readable mirror; the body `## Resolved Questions` section mirrors resolutions written back by the Phase 3 Pre-gate or by /geniro:implement's Phase 1 handoff-resolution step gate.

The `authored_tests[]` frontmatter array is the machine-readable source of truth for the F→P tests this debug run produced. Body lines `**Reproduction test:**` (scientific) and `**Test file:**` (adversarial, A6 template) remain as human-readable mirrors of this array. Consumers (notably /geniro:implement Phase 1 handoff-resolution step) prefer the frontmatter; legacy handoffs at `geniro_schema_version: m7-v1` lack this field, so the consumer protocol in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/debug-handoff.md` falls back to body-string parsing in that case.

### from-debug-adversarial-<branch>.md (T2 — handoff, Adversarial Mode)

Path: `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md`. Same schema as from-debug-<branch>.md with `mode: adversarial` and `phase: adversarial-ship` discriminators; the `deep-mode: <true|false>` field propagates here too (producer→consumer in lockstep; missing reads as false). Body: A6 Adversarial Findings template + body sections.

---

## 3. Infrastructure investigation

When symptoms suggest the bug may not be in the code (timeouts, intermittent failures, environment-specific errors, deployment regressions), investigate infrastructure before or alongside code hypotheses.

**Signals requiring at least one infrastructure hypothesis:** timeouts; intermittent failures (error rate >0 but <100%); environment-only manifestation (works locally, breaks in staging/prod); latency degradation without a code change; symptoms correlating with a deployment, config change, secret rotation, or scale event.

**What to investigate:** logs, service health, environment/config diffs between the working and broken environments, and resource limits. The entries that get missed sit inside those categories — **certificate expiry**, **secret rotation**, and **connection-pool size vs active connections** — each breaks a running system while every code path is still correct.

**Hypothesis quality bar:** "The database connection pool is exhausted under load" is testable — names the resource, condition, and observable signature. "Something is wrong with the server" is NOT a hypothesis — no variable to toggle, no falsifiable prediction.

---

## 4. Isolation techniques

Once a hypothesis is confirmed, narrow down to exact code location.

**Binary search:** Disable half the relevant code path, check if the bug reproduces. Narrow iteratively. O(log N) iterations. Use when the confirmed hypothesis points to a general region but exact line/branch is unclear.

**Git bisect:** For regressions, walk the good→bad range to identify the commit that introduced the bug. Use when the bug was absent at a prior commit.

**Profiling:** For performance bugs, use the language's profiler for quantitative data (timing, memory, allocation count). Code inspection cannot distinguish "slow because of N+1 query" from "slow because of N^2 allocation."

**Pick the cheapest technique:** binary search if the region is large; git bisect if the regression boundary is known; profiling if the symptom is quantitative. Don't run all three.

---

## 5. Stall diagnosis taxonomy

When /geniro:debug stalls (the stall gate fires — threshold defined in `${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-1-investigate.md` §1.7), classify the root-cause-of-the-stall as a missing component:

| # | Missing component | Symptom | AUQ option label | AUQ description |
|---|---|---|---|---|
| A | **Missing instruction** | Hypothesis tests don't converge because the orchestrator lacks a project-specific rule (e.g., "we use SQS not Kafka here") | "Missing project rule" | Paste the rule or point to a CLAUDE.md / `.geniro/instructions/*` section |
| B | **Missing source-of-truth** | Test results contradict reasonable assumptions because canonical state (DB row, prod log line, third-party API response) is unreachable | "Missing source of truth" | Paste the DB row / log line / API response |
| C | **Missing tool** | Orchestrator cannot read the artifact format (binary blob, proprietary protocol, sandboxed environment) | "Missing tool" | Provide the parsed/decoded form, or specify a tool the user can run locally |
| D | **Missing validator** | Hypothesis tests "pass" via narrative-only Result but cannot be objectively verified (e.g., race-condition theories) | "Missing validator" | Author a deterministic re-runnable check (curl + grep, SQL query, regex on log) |
| E | **Missing permission rule** | Hypothesis blocked by safety-hook or `.geniro/safety.json` denial | "Missing permission" | Add the relevant pattern to `.geniro/safety.json` `allow_patterns` |
| F | **Missing sandbox signal** | Tests inconclusive because environment differs from production (Docker vs. host, ARM vs. x86) | "Missing sandbox signal" | Re-run in the production-like environment and paste the captured signal |
| G | **Missing eval** | Bug type has no existing regression test pattern in the project — hypotheses cannot be expressed in the existing test framework | "Missing eval pattern" | Author a new test pattern (parameterized fuzzer, mutation-test seed, etc.) |
| H | **Missing recovery path** | All hypotheses confirmed but the fix path is unclear because the bug spans a DI / generated-code / framework-internal layer | "Missing recovery path" | Specify whether the production-source escape hatch is acceptable, or escalate as architectural |

**AUQ rendering:** stall gate fires `AskUserQuestion` with header "Stall diagnosis". Render the most likely missing-component categories plus an "Abandon — present partial findings" option (AUQ maxItems=4, so typically the top 3 categories + Abandon) — the model picks categories based on stall context (inconclusive-test outputs, hypothesis types tried). "Abort" comes via "Other". Each option's `preview` (where helpful) shows what Phase 1 will do next.

**Persistence:** same structured-entry pattern as the Scientific-mode stall gate (`${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-1-investigate.md` §1.7 Stall escalation gate). Write a structured `open_questions[]` entry with `source: phase-1-stall-gate`, `question: <verbatim category text>`, `related_hypotheses: [<inconclusive H-IDs>]`, `status: unresolved`. On user pick of any surfaced missing-component category, update to `status: resolved` with `resolution.picked` and `resolution.resolved_by: debug`. On Abandon or Abort, the entry stays `unresolved` and Phase 3 §3.0 Pre-gate surfaces it before the escalation AUQ.

---

## 6. Adversarial Mode templates

### A5 spawn template

```
Agent(subagent_type="adversarial-tester-agent", prompt="""
## Task: Adversarial Edge-Case Test Authoring (Debug — Verify Changes)

WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
DEEP-MODE: [state.md frontmatter `deep-mode:`; missing reads as false]
PROJECT SEARCH POLICY: [verbatim global.md search rules, or `none declared`; governs every lookup, not just the first]

### Diff (changed files + contents)
[Pre-inline `git diff <resolved-range>` output AND full contents of every changed source file from Step 1]

### Shared Edge-Case Checklist (READ this file yourself at runtime — do NOT paste here)
`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/tests-criteria.md`

### Project Test Framework
- Test command (from CLAUDE.md Essential Commands): [e.g. `pnpm test`, `pytest`]
- Test-file naming convention: [project's pattern — e.g. `*.test.ts` adjacent to source]
- Exemplar test files (1-2, pre-inlined): [closest existing test files to the changed code]

### Hypothesis Seeds
none — adversarial mode runs a fresh pass (no prior reviewer findings available in debug).

### Output
Write your report to `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md` (resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A) via the atomic-write helper — a direct Edit/Write to any `.geniro/state/` path is hard-blocked by the state-helper enforcement hook, so write it with `source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"` then `atomic_state_write "<path>" <<'EOF' … EOF`. Authored test files go to the project's normal test paths. Do NOT git add/commit/push.

Emit the complete T2 frontmatter, not only the test array — an omitted `branch`/`worktree` routes every consumer into the degraded fallback (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/debug-handoff.md` §Step 4 Case C), which drops the relocation suggestion your tests need to be found by. (`/geniro:review` sidesteps this by writing its handoff orchestrator-side; fixing what you emit here is the smaller change for this producer.) Field semantics for `from-debug-adversarial-<branch>.md` are canonical at this file's §2 above — read it rather than guessing a field's shape. Required keys: `tier`, `producer`, `consumer`, `schema-version`, `branch`, `worktree`, `timestamp`, `geniro_kind`, `geniro_schema_version`, `mode`, `phase`, `status`, `deep-mode`, `approvals`, `non-resumable-actions`, `authored_tests`, `open_questions`. The values this mode fixes: `tier: T2`, `producer: debug`, `consumer: implement`, `schema-version: 1`, `geniro_kind: debug-handoff`, `geniro_schema_version: m7-v2`, `mode: adversarial`, `phase: adversarial-ship`, `status: done`, `approvals: []`, `non-resumable-actions: []` (you make no persisted-AUQ pick and complete no non-resumable action), `open_questions: []` (every gate that populates this array belongs to Scientific Mode — this pass raises none). `branch` = BRANCH, `worktree` = WORKTREE, `deep-mode` = DEEP-MODE (the slots above); `timestamp` = a live clock read at write time.

`authored_tests: [...]` carries one entry per RED test kept after your 3× flake check — the consumer (/geniro:implement Phase 1 handoff-resolution step) reads this field to relocate the tests into its worktree. Read the entry schema at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` § Producer-specific extensions and fill every field from your run; the values this mode fixes are `mode: adversarial` (matching the top-level `mode:` discriminator), `f_to_p_status: red-on-current` (the only status valid for a kept adversarial test), `targeted_source` = the production file the test attacks, `confidence` mirroring your A6 Confidence column, and `path` resolved against your own `git rev-parse --show-toplevel`.

`authored_tests: []` (empty array) is the correct form for the zero-red-tests terminal outcome. Body `**Test file:**` lines remain the human-readable mirror; the frontmatter is the contract.

### F→P invariant
A test that passes today proves nothing about the bug, and a flaky failure proves even less — keep only a test that fails 3 times in a row on the current code. If it passes today, delete the test and mark `discarded-cannot-repro`. Flaky = discard.

### Scope
Diff-only — the orchestrator resolved the scope above. Do NOT author tests for files outside the changed-files list. Hard cap: 10 authored tests.

Anchor: WORKTREE is your root — run every Bash call from it (`cd <WORKTREE> && …`) and resolve every file path under it.
""", description="Adversarial tests: /geniro:debug verify-changes")
```

### A6 findings template

After re-verification, present this block directly in chat and persist (via the agent's write at A4 step 3 + the orchestrator's re-verify delta if tests were discarded):

```markdown
## Adversarial Findings

**Diff scope:** [range + file count + LOC]

**Hypotheses generated:** [N]
**Tests authored (kept after re-verify):** [M]
**Tests discarded (F→P failed on re-run):** [K]

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

**Zero red tests?** [If M == 0 after re-verify: state plainly "no bugs found in scanned diff" — this is a valid outcome.]
```

If zero red tests survive, skip escalation entirely and go directly to Cleanup. Otherwise proceed to escalation per A4 step 6.

---

## 7. Extended examples

### Example 1: Cache not invalidating

`/geniro:debug User sees stale data after profile update` → two competing hypotheses (cache invalidation broken vs. update endpoint never called); logging confirms the first, isolating a cache-key mismatch as the `[ROOT-CAUSE]` → propose patching the cacheKey builder in `src/cache/user.ts` to include the user ID, verified by monkey-patch → findings persisted to `from-debug-<branch>.md`, escalated to /geniro:implement, `diagnosis` emitted with tags=[cache, invalidation, user-role].

### Example 2: Intermittent timeout

```
/geniro:debug API endpoint times out randomly under load
```

→ Phase 1 Observe: Happens ~5% of requests during stress test
→ Hypothesis 1 (code): Database query too slow; Hypothesis 2 (infra): External service timeout
→ Test: Profile database queries, check service logs
→ Result: Hypothesis 2 confirmed (service is slow)
→ Phase 2 Propose: add timeout + fallback around the external service call
→ Verify: local experiment shows timeouts disappear with monkey-patch
→ Phase 3 Escalate: /geniro:implement with the proposed patch

### Example 3: Verify recent changes (Adversarial Mode)

```
/geniro:debug verify last changes
```

→ Phase 0 Mode detect: anchored "verify last changes" → Adversarial
→ A2 Diff resolution: `git diff main...HEAD` (per scope-anchor rule #3)
→ A4 Step 3: Spawn `adversarial-tester-agent` with pre-inlined diff + framework + exemplars
→ A4 Step 4: Independently re-run 7 authored tests; 5 fail RED, 2 pass-today (discarded)
→ A6 Adversarial Findings persisted to `from-debug-adversarial-<branch>.md`
→ Escalate: /geniro:implement with the authored tests as escalation targets

---

## 8. Open-PR scan — already fixed elsewhere?

Phase 1 (Scientific Mode) sub-step referenced from `${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-1-investigate.md` §1.2. Checks whether an open PR already fixes the bug under investigation, so a debug session does not re-investigate something a teammate is already patching. The probe itself — the query, relevance scoring, the top-5 cap, and unreachable-source handling — is `${CLAUDE_PLUGIN_ROOT}/skills/_shared/prior-work-scan.md` §2 (Open pull requests) / §3 (Bounds) / §4 (On a hit) / §5 (Unreachable handling); this section covers only the inputs debug feeds it and what debug does with a hit. Read-only; never opens, edits, or comments on a PR (debug's no-ship boundary holds).

**When it runs.** After §1.2 Observe & repro, once the symptom and suspect files are known, before §1.4 Hypothesize — those are exactly the inputs the scan needs, and Adversarial Mode's diff-only flow (no symptom, no Observe & repro) never produces them. Scientific Mode only, for that reason.

**Inputs debug supplies.** `suspect_files` — the suspect / recently-changed files §1.2 identified. `keywords` — distinctive tokens from the symptom or error string (function names, error codes, unique phrases), stop-words dropped.

**On a strong hit**, `AskUserQuestion` (header `"Existing fix"`; question names the matched PR and why it matched):

- **Review that PR's diff first** — if it resolves the bug, skip the hypothesis loop and go to Phase 3, naming the existing PR in the findings **Proposed fix** line (`already fixed in open PR #N <url> — no new patch needed`) so it reaches the downstream consumer through the persisted handoff body (§3.1), not just chat. If it does not resolve the bug, record why in `## Hypotheses` and keep investigating.
- **Test it as a hypothesis** — form a hypothesis that the PR's change fixes the bug and test it against the feedback loop like any other hypothesis (§1.5).
- **Ignore — keep investigating** — discard the match and proceed to §1.4.

Persist the pick to state.md frontmatter `approvals[]` category `existing_fix_pr` via `atomic_state_write`, so the session-start restore re-applies it across a compaction or resume. The matched PR itself rides to the consumer in the findings body above, not a new handoff field.

---

## 9. L2 emit payload shapes — canonical `emit_learning` call shapes

`emit_learning` reads a single JSON object on stdin; a YAML payload exits 64, and mis-named or missing `ext` sub-fields silently drop the typed extension. Mirror the shapes below exactly — the field names match the helper contract in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §Example callers.

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

Substitute the run's real values: `scope` = the affected file/module path glob; `summary` = the one-line root-cause statement; `tags` inferred from affected files + hypothesis category; `ext.symptom` / `ext.root_cause` / `ext.fix` = the confirmed observation, isolated cause, and proposed patch. After a `rc=0` return, echo `Recorded learning: <summary>` per the helper's §Caller contract — the helper writes silently, so the echo is the only in-session signal it ran. On a non-zero return, surface the plain-English failure line (rc=64 missing field / 68 oversized / 69 write-failed) rather than swallowing it.

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

### `pitfall` (Adversarial Mode A4 step 6)

Same invocation form. One entry per RED test kept after the A4 step 4 re-verification — no `ext` block:

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

Substitute the run's real values: `scope` = the production source path the kept test targets (its `targeted_source`); `summary` = the defect in one line (mirrors the A6 **Hypothesis** line); `tags` inferred from the A6 **Category** column plus the changed files. `trust: verified` — the re-verified F→P run (A4 step 4) is the captured artifact. `pitfall` is a user-facing type per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §Caller contract rule 1: echo `Recorded learning: <summary>` after a `rc=0` return, and surface a non-zero return per that section's rule 3 rather than swallowing it.
