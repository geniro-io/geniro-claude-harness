# Phase 6 Action-Gate Handoff Reference

Detailed contract for `/geniro:review` Phase 6 (Action Gate Handoff). SKILL.md retains a 2-3 line summary + a pointer here.

State.md `phase: action-gate` during this phase.

**Handoff schema version: `m6-v2`.** Bumped from `m6-v1` — per-finding body schema extended with verification fields (`Validation` / `Recommended-action` / `Verification-confidence` / `Verification-evidence`) emitted by the Phase 4.2 per-finding verifier. Producer writes the value into the handoff frontmatter (`geniro_schema_version:` per SKILL.md §5.1 Handoff file write). Consumers accept BOTH `m6-v1` (legacy — verification fields absent) AND `m6-v2` (rich — verification fields mandatory on every kept finding: CRITICAL / HIGH / MEDIUM). Within m6-v2, a producer that verified only HIGH findings emits verification fields on HIGH findings only; consumers treat absence on CRITICAL or MEDIUM the same as `m6-v1` absence on HIGH — apply the "treat as confirmed + one-line warning" fallback.

## Contents

- §1 — Reporter behavior (no fix loop)
- §2 — Gate chain (firing order)
- §2.5 — Pre-gate: resolve open questions (Invariant A)
- §2.6 — Handoff file template (written in Phase 5.1)
- §3 — Step 0: open-decision per PRODUCT-DECISION finding (Invariant B initial flip)
- §3.5 — Finalize report (draft → final) before the handoff is offered
- §3.7 — Suggest improvements (reflection, read-only)
- §4 — Action gate (consolidated decision)
- §5 — Round-N escalation
- §6 — Failing-tests gate
- §7 — Action == Post drill (sub-sections 7.0 fail-closed guard with four invariants → 7.8 posting-failure semantics)
- §8 — Empty-answer handling (universal)
- §9 — Terminal state mapping

---

## 1. Reporter behavior — no fix loop

/geniro:review does not apply fixes. The Phase 6 handoff message never includes "I'll fix these now" language. The fix path routes to /geniro:implement (manual, or via the Phase 6 handoff line).

`--simplify` flag does NOT change this. The flag biases Phase 2 reviewer attention but the output is still a finding list for consumption by other skills.

**Skip Phase 6 entirely when:**
- Zero actionable findings remain (CRITICAL + HIGH + MEDIUM all zero after Phase 4.2).

---

## 2. Gate chain — fire each as a separate AUQ

Phase 6 surfaces up to 4 sequential top-level gates. Each one decides a different thing and must be its own `AskUserQuestion` call — never collapse them into a single summary question, never paraphrase the question text, never merge options across gates.

**Firing order:**

1. **Pre-gate — Resolve Open Questions:** fires once when state.md frontmatter `open_questions[]` has any entry with `status: unresolved`. Chain one AUQ per such entry (cap-extension when >4). Always-WAIT. MUST complete before any other Phase 6 gate fires — these questions gate what /geniro:review posts. Full procedure: §2.5 below.
2. **Step 0 — Open-decision (per finding):** fires once per `Decision Type: PRODUCT-DECISION` finding kept by the Phase 3 §3.3 KEEP/FILTER judgment. Skipped when zero PRODUCT-DECISION findings remain.
3. **Action (Always-WAIT):** fires once whenever this phase fires — the consolidated top-level decision. User picks ONE next step: /geniro:implement / Post Draft PR / Continue rounds / Skip.
4. **Failing tests:** fires once when the state file's `## Authored Tests` section is non-empty — picks the commit policy for AI-authored tests. Firing order relative to Action gate conditional:
- **Action == Post AND `## Authored Tests` non-empty:** Failing-tests fires BEFORE the Post drill (GitHub reviews API rejects comments whose `path` is absent from `commit_id`'s tree).
- **Action != Post OR `## Authored Tests` empty:** Failing-tests fires AFTER Action gate's path completes.

Sequential: do not fire gate N+1 until gate N's answer is collected.

---

## 2.5. Pre-gate — Resolve Open Questions

This gate runs FIRST in Phase 6 — before Step 0, Action, and Failing-tests gates — whenever state.md frontmatter `open_questions[]` carries any entry with `status: unresolved`.

**Why it runs first.** An open question here is one whose answer changes what the Action gate is choosing between (e.g., "API seeder additions in-scope or split into a separate PR?" — the answer changes which findings get posted). Letting Action gate fire first means the user picks "/geniro:implement findings" without realizing those questions still gate the implementation.

**What this gate does NOT ask.** /geniro:review records an open question ONLY when it cannot determine the answer itself and the answer changes what it posts — a genuine scope or judgment call. It does NOT record (so never surfaces here) a "how should X be fixed?" question: a reporter doesn't decide fixes, a finding carries its own recommended action, and /geniro:implement resolves fix specifics when it fixes. It also does not pose anything it could verify itself — a checkable claim is verified into a finding, not recorded as a question (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md` §4).

**Procedure:**

1. Read frontmatter `open_questions[]`. Filter to entries with `status: unresolved`.

2. For each unresolved entry, fire one `AskUserQuestion` call. The renderer picks one of three tiers in order — the **first tier whose required source data is available** wins:

   **Tier 1 — Producer-authored rich entry (preferred).** When the entry carries `context` / `evidence` / `options` / `recommendation` fields per the extended schema in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2 `open_questions`:
   - `header`: `"Open question"` (literal — never paraphrase)
   - **chat block + `question`**: render per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Single-finding gate (§ Message-first rendering), sourcing fields from the entry:
     - chat block — render `context` as the self-contained What / Concern / Why explanation in plain English (expand any reviewer shorthand), with `evidence[0].file:lines` as the Evidence line; when `related_findings[]` is non-empty, name the highest-severity related finding's severity and the source dimension (entry's `source`, e.g. `spec-compliance`, `bugs`) inside the explanation
     - lean `question` — the plain-English title (first sentence of the entry's `question`) + `evidence[0].file:lines` if present, then a pointer to the chat block
   - `options[]` — one per `options[]` entry in the question:
     - `label` — option's `label`
     - `description` — option's `description`
     - `preview` — leave empty or a one-line recap; the `context` / `evidence[]` body lives in the chat block (§ Message-first rendering), not the side-box. When `recommendation.option_id == this.id`, position that option first, suffix its `label` with ` (Recommended)`, and state the producer's rationale in the chat block
   - When `recommendation.option_id` is set, position THAT option first in the `options[]` array and suffix its `label` with ` (Recommended)`.

   **Tier 2 — Cross-reference into `## Findings` body.** When the entry has `related_findings: [F1, F2, ...]` non-empty but lacks the Tier 1 rich fields, read those finding blocks from the same handoff file's `## Findings` body (per the multi-line "Per-finding body schema" defined later in this same reference file, after the Wontfix-path note below). Apply `per-finding-question.md` § Single-finding gate rendering directly against the first related finding's body — Evidence / Suggested-fix / Confidence / Origin all flow from the finding fields. When >1 related findings exist, prefer the highest-severity finding; mention the others as `"Also gates: F2, F3"` in the question body.

   **Tier 3 — Legacy synth fallback.** When neither Tier 1 nor Tier 2 source data is available (bare `question:` only):
   - chat block + `question`: render a chat block first per § Message-first rendering — expand the terse `question:` field into a plain-English explanation of what is being asked and why (use whatever `context` / `evidence` exists); the lean AUQ `question` then restates it. Do NOT fire the bare reviewer phrasing as the question
   - `options`: synthesized from the question text. For ambiguity-resolution patterns, supply 3-4 concrete options derived from the question:
     - Scope question ("X in-scope or split?") → "In scope — keep in this PR" / "Split — revert X to a separate PR" / "Out of scope — drop entirely"
     - Verification question ("Cannot confirm Y exists; verify?") → "Yes — Y exists and matches" / "No — Y is wrong; revise PR title/body" / "Unknown — skip verification"
     - Acceptance question ("Accept Z pattern or refactor?") → "Accept Z as-is" / "Refactor Z to <suggested-alternative>" / "Defer — file follow-up"
   - When the question doesn't fit a fixed pattern, supply 2-3 options + rely on user "Other" for free-form. Never auto-resolve.
   - Tier 3 is the documented failure mode the schema exists to avoid — emit a `## Errors` notice: `open_questions[].id=<q-id> rendered via Tier 3 (terse) — producer should fill context/evidence/options fields next round`.

3. After the user picks (always-WAIT — empty answer = upstream bug, re-ask), update the entry in-place via `atomic_state_write`:
   - `status: resolved`
   - `resolution.picked`: chosen option text (verbatim)
   - `resolution.at`: ISO-8601 UTC timestamp
   - `resolution.asked_in_phase`: `phase-6-pre-gate`
   - `resolution.resolved_by`: `review`
   Preserve the `id`, `source`, `question`, and `related_findings` fields.

4. Mirror the resolution into the body `## Resolved Questions` section per the schema example in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2.

5. When >4 unresolved entries, chain into a second AUQ batch per the AskUserQuestion cap-extension pattern.

6. After the last entry resolves, every `open_questions[]` entry MUST be in `{resolved, wontfix}` before proceeding to Step 0 / Action / Failing-tests. Verify by re-reading the frontmatter; if any `unresolved` remains, loop back to step 2.

---

## 2.6 Handoff file template (written in Phase 5.1)

Phase 5.1 writes the handoff at `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` via `atomic_state_write` — never a direct Edit/Write on the canonical state path (the `enforce-state-helper` hook warn-flags direct writes initially and flips to a hard-block in a future release). `<PRIMARY_ROOT>` resolves per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A.

The canonical handoff is a one-shot producer→consumer artifact; /geniro:review extends it with `phase:` / `status:` / `round:` / `approvals[]` so a compaction mid-run can recover. The file behaves as a handoff AT REST (after Phase 5 persist) and as a working state file DURING THE RUN.

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"
atomic_state_write "<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md" <<'EOF'
---
tier: T2
producer: review
schema-version: 1
branch: <git-branch>
timestamp: <ISO-8601 UTC>
consumer: implement
geniro_kind: state-handoff
geniro_schema_version: m6-v2
task_slug: review-<branch>
phase: <triage|mechanical-prepass|llm-spawn|filter|stratify|persist|action-gate|done|aborted|escalated>
status: <in-progress|done|failed>
report_status: <draft|final>          # whole-report lifecycle — see state-tier-spec.md /geniro:review producer fields (missing reads as final)
mode: <standard|tdd>
deep-mode: <true|false>               # --deep fan-out (3x passes + 3-vote); missing reads as false
round: <int>
risk-tier: <standard|high>
pr-ref: <owner/repo#num|null>
pr-url: <https://...|null>
pr-head-sha: <40-char SHA|null>
pr-title: <verbatim title|null>
pr-body: <verbatim body|null>
plan-context-ref: <abs-path|null>
linear-task-ref: <ENG-123|null>
linear-parent-ref: <ENG-100|null>
simplify-mode: <true|false>
resolved-threads-snapshot: [<path:line entries|null>]
approvals: []
non-resumable-actions: []
open_questions:                       # MUST be present; MAY be empty []
  - id: q1                            # short stable anchor
    source: <reviewer-dim or producer-step>
    question: <verbatim question text>
    related_findings: [F1, F4]        # optional — finding IDs this question gates
    status: unresolved                # enum: unresolved | resolved | wontfix
    resolution:                       # populated when status moves out of `unresolved`
      picked: <chosen option>
      at: <ISO-8601 UTC>
      asked_in_phase: <phase name>
      resolved_by: <skill that ran the resolution AUQ>
---

# Review: <topic / branch>

## Summary
- Branch: <branch>
- Scope: <N files reviewed of <T> changed in the PR>; when N < T (commonly a stacked PR) also "<M> files excluded — owned by ancestor PR #<n> (<K> review threads, <U> unresolved); reviewed there, not missed" per `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §2.1 (omitted when the review covered the whole PR)
- Mode: <standard|tdd>
- Round: <N>
- Risk-tier: <standard|high>
- Dimensions spawned: [<list>]
- Mechanical pre-pass: [lint:N, schema:M, secrets:K]
- Finding totals: CRITICAL=<X>, HIGH=<Y>, MEDIUM=<Z>

## Findings

### CRITICAL
<list>

### HIGH
<list>

### MEDIUM
<list>

## Deferred — sub-threshold
<list, surfaced for user awareness>

## Filtered
<!-- Findings demoted out of ## Findings: verifier-refuted (reason: refuted-by-verifier), not-actionable (real-but-unreachable per the §3.6 actionability bar in phase-4-verification-reference.md), test-challenged (`[CHALLENGED-BY-TEST]`), already-resolved-on-PR, or Phase 3 convention-filtered. Kept visible with original severity + reason so the user can re-elevate; never propagated to ## Findings, open_questions[], or the Post drill. -->
<list, or empty>

## Authored Tests
<!-- Populated only when the test-confirmation gate authored tests; lists each AI-authored test file by path. Empty otherwise. The Failing-tests gate fires when this section is non-empty. -->
<list of test file paths, or empty>

## Tool log
<reviewer spawns + side-effects>

## Errors
<failed spawns, gh fail-open, mechanical-prepass failures>

## Open Questions
<!-- Human-readable mirror of frontmatter `open_questions[]`. Frontmatter is source of truth. -->

### q1 — <source>: <one-line summary>
**Status:** unresolved
**Question:** <verbatim question>
**Related findings:** F1, F4
**Why this gates downstream action:** <one sentence — e.g., "drives whether to revert api seeders or update spec.forbidden_actions">

### q2 — ...

<!-- If open_questions[] is empty, this section reads: "No open questions — handoff is unconditionally actionable." -->

## Resolved Questions
<!-- Populated when downstream consumer (or /geniro:review's §2.5 Pre-gate) resolves an entry; mirrors frontmatter `open_questions[].resolution`. -->

### q1 — <source>: <one-line summary>
**Picked:** <chosen option>
**At:** <ISO-8601 UTC>
**Resolved by:** <skill — review | implement | manual>
**Phase:** <phase that ran the resolution AUQ>

## Termination reason
<rendered per §9 — only on aborted | escalated state>

## Persisted approvals
<rendered from approvals[] frontmatter for user-readability>
EOF
```

Each finding under `## Findings` renders as the multi-line per-finding body block below (NOT a one-liner) — the Phase 3 §3.3 KEEP/FILTER judgment preserves every reviewer-agent field; dropping fields to reach a one-liner is the failure mode the schema prevents.

---

**Per-finding body schema (referenced by §2.5 Tier 2 + §3).** Each finding under the handoff's `## Findings` body renders as a sub-section block so consumers can build rich AUQs per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Single-finding gate without re-deriving Evidence / Why-matters / Suggested-fix from outside the handoff:

```markdown
### F1 — [NEW|PRE-EXISTING] [optional: CONFIRMED-BY-TEST|CHALLENGED-BY-TEST|POSTED-TO-PR|ALREADY-RESOLVED-ON-PR] <short title>
- **Severity:** CRITICAL | HIGH | MEDIUM | LOW
- **File:** path/to/file.ts:42-48
- **Decision Type:** FIX-NOW | TESTABLE | PRODUCT-DECISION | INTENT-CHECK
- **Cause:** ROOT-CAUSE | SYMPTOM | UNKNOWN
- **Confidence:** NN%
- **Origin:** llm:<dim> | mechanical:<check>
- **Why this matters:** <1-sentence impact, verbatim from reviewer-agent output>
- **Suggested fix:** <concrete improvement text, verbatim — synthesis form for PRODUCT-DECISION>
- **Evidence:**
  ```<lang>
  <2-5 lines from reviewer-agent Evidence: codeblock>
  ```
  OR (command-based form): `Command:` / `Exit code:` / `Tail (last 3 lines):`
- **Validation:** `confirmed | refuted | clarified` [every kept finding — CRITICAL / HIGH / MEDIUM; emitted by Phase 4.2 per-finding verifier; ABSENT on LOW (which never enters Phase 4.2)]
- **Recommended-action:** `fix-now | testable | product-decision | intent-check | drop` [every kept finding — verifier override; when `Validation: clarified`, this field supersedes the original `Decision Type:` for downstream routing]
- **Verification-confidence:** `1 | 2 | 3 | 4 | 5` [every kept finding — coarse 1-5 scale, distinct from the LLM `Confidence: NN%` field above]
- **Verification-evidence:** `"<literal quote from cited file:line or caller chain>"` [every kept finding — verifier's grounding citation, distinct from the reviewer's `Evidence:` codeblock above]
- **Options:** [PRODUCT-DECISION only — omit for other types]
  - `<option-id>`: `<short label>` — `<one-line trade-off>`
- **Recommendation:** <option-id> — <one-sentence rationale> [PRODUCT-DECISION only]
- **step0_status:** `pending | resolved | wontfix` [PRODUCT-DECISION only — omit for other types]
```

The `step0_status:` field is the runtime sentinel that §3 (Step 0 per-finding gate) flips from `pending` → `resolved` after the user's AUQ pick lands. Phase 5.1 writes every PRODUCT-DECISION finding with `step0_status: pending`; §3 step 3 flips it to `resolved`. §7.0 re-reads `## Findings` and aborts the Post drill on any remaining `pending` — the defensive analog of the `open_questions[].status: unresolved` check, since the AUQ chip labels (`"Open question"` for §2.5, `"Open decision"` for §3) are not tags and must never leak into a PR comment as if they were.

**Verification fields — presence rules.** The four `Validation` / `Recommended-action` / `Verification-confidence` / `Verification-evidence` fields are MANDATORY on every kept finding (CRITICAL / HIGH / MEDIUM) that lands in `## Findings`. Phase 4.2 spawns one fresh `reviewer-agent` per §4.1 survivor regardless of severity; verdicts of `validation: refuted` are filtered before reaching the handoff, so any finding present here carries `Validation: confirmed` or `Validation: clarified`. The fields are ABSENT on LOW findings — including a LOW `PRODUCT-DECISION` admitted via §4.1 Path B (decision-type) — because no LOW finding enters the Phase 4.2 verifier (§4.2 runs on Path-A survivors, `severity >= MEDIUM`). A Path-B LOW `PRODUCT-DECISION` still carries `step0_status: pending` (it IS a PRODUCT-DECISION, so the §3 open-decision gate fires for it) but no `Validation`/verification fields. When `Validation: clarified`, the verifier judged the original reviewer's finding partially correct but mis-classified; the `Recommended-action:` value carries the corrected routing and supersedes the original `Decision Type:` for §3 gate firing and downstream consumer decisions.

**Verification fields — back-compat for legacy handoffs.** Two legacy cases produce findings without the four verification fields:
1. `m6-v1` (pre-Phase-4.2) writers — no findings carry verification fields at any severity.
2. `m6-v2` writers that verified only HIGH findings — HIGH findings carry verification fields; CRITICAL and MEDIUM findings do not.

Consumers (§7.0 fail-closed guard, /geniro:implement Phase 1 handoff-resolution step) treat a missing `Validation:` on any CRITICAL/HIGH/MEDIUM finding as `Validation: confirmed` and surface a one-line chat warning so the user knows Phase 4.2 verification was not actively run for that finding. This mirrors the existing `step0_status: missing → resolved` back-compat behavior documented above — the safety improvement post-dates these handoffs, so missing-field MUST NOT block the Post drill that worked before the field existed.

**Backward-compatible parsing.** Consumers (Phase 6 §2.5 Tier 2 lookup, §3 per-finding gate, /geniro:implement Step 12) accept BOTH the rich multi-line block above AND the legacy one-liner shape `- [NEW|PRE-EXISTING] path:lines — <description> — decision: ... — recommendation: ... — confidence: NN% — origin: ...` produced by older /geniro:review runs. Legacy one-liners fall back to the terse rendering (§2.5 Tier 3 / per-finding-question.md degraded mode); rich blocks unlock the full Single-finding gate shape. **Legacy handoffs predate the `step0_status:` sentinel** — when §7.0 parses a legacy one-liner with `Decision Type: PRODUCT-DECISION` (or its lowercase one-liner form `decision: PRODUCT-DECISION`) and no `step0_status:` sub-field, treat it as `step0_status: resolved` (the safety improvement post-dates these handoffs) and surface a one-line chat warning so the user knows Invariant B was not actively re-verified for that finding. Never treat a missing field as `pending` — that would false-positive on every legacy handoff and block the Post drill that worked before the field existed.

**Wontfix path.** If the user picks "Other" with explicit text like "ignore" / "skip" / "not now", set `status: wontfix` and `resolution.picked` to the user's text. Wontfix entries do NOT block downstream gates — they're recorded but de-prioritized. Downstream consumers treat `wontfix` as "user acknowledged and chose to defer".

**No skipping.** The pre-gate cannot be deferred to /geniro:implement or to the Post drill. Resolving here makes the Action gate's options meaningful (e.g., "/geniro:implement findings" now points to a known-scope target). Resolving downstream creates the failure mode this gate exists to prevent.

---

## 3. Step 0 — Open-decision gate (per-finding, Always-WAIT)

Before recommending which skill to run, surface every `Decision Type: PRODUCT-DECISION` finding kept by the Phase 3 §3.3 KEEP/FILTER judgment to the user — they pick the resolution path; orchestrator NEVER picks on their behalf. The orchestrator must not auto-resolve multi-path findings even when the reviewer's `recommendation:` field appears obvious.

**For each kept finding with `Decision Type: PRODUCT-DECISION` (read from state file):**

1. Read the finding's `Options:` sub-list AND body sub-fields (`evidence:`, `why-matters:`, `suggested-fix:`). For CRITICAL / HIGH / MEDIUM findings, confirm the Phase 4.2 verifier passed before firing the AUQ: the `Validation:` field MUST be `confirmed` or `clarified`. A `Validation: refuted` finding should already be filtered upstream at Phase 4.2 — if encountered here, it indicates a producer-side schema violation; emit an entry to state.md's `## Errors` body section (`phase: action-gate`, `error: refuted-finding-reached-step-0-gate`, finding ID) and skip the AUQ for that finding. A missing `Validation:` on a CRITICAL/HIGH/MEDIUM finding (legacy handoff per §2 back-compat) is treated as `confirmed` — proceed with the AUQ but surface the one-line warning.
2. Fire `AskUserQuestion` per the canonical shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Single-finding gate, which mandates § Message-first rendering: FIRST render the finding to chat as a self-contained block (what the code does / the concern / why it matters / evidence / options, in plain English — expand any reviewer shorthand so the question stands on its own), THEN fire a lean AUQ. Set `header: "Open decision"`. Build the chat block and the lean `question` + option `label`+`description` from the finding's `options:` sub-list and body sub-fields (`evidence:`, `why-matters:`, `suggested-fix:`) per the spec's Source-field map. Leave each option's `preview` empty or a one-line recap — never the finding body, which the truncating/often-absent side-box cannot hold. Append ONE standard disposition beyond the finding's own `options:` bullets — `label: "Keep off the PR — I'll handle this"`, `description: "Record the decision for you; do not include this finding in anything posted to the PR."` — the audience control for a residue the PR author cannot action (a governance / legal / data-classification / business-intent question): it routes the decision to you, not onto the PR. It occupies one AUQ option slot, so when the finding's own `options:` already lists 4, chain a follow-up per the cap-extension rule (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Cap-extension) — never drop or merge an existing option to make room.
3. Update the finding line in the state file via `atomic_state_write` (never a raw `Edit`/`Write` — the handoff is a canonical state path and raw writes trip the `enforce-state-helper` hook): replace `recommendation:` field with user's chosen option text AND set `step0_status: resolved` (or `step0_status: wontfix` when the user picks "Other" with skip/defer text). Preserve `options:`, `evidence:`, `why-matters:`, `suggested-fix:`. The state file is the handoff to the next skill, so the chosen path AND the body travel with the finding. The `step0_status` flip is the sentinel §7.0 re-reads to verify this gate actually fired — without it, a §3-skipped finding ships to PR as if the AUQ header `"Open decision"` were a tag. When the user picks the **Keep off the PR** disposition, set `step0_status: resolved`, write `recommendation: keep-off-pr`, AND add `post-disposition: off-pr` to the finding line — §7.1 reads `post-disposition: off-pr` and drops the finding from the post set, so a residue you chose to handle yourself never reaches the PR author.

When more than 4 PRODUCT-DECISION findings exist OR a single finding's `Options:` carries `(more-options-exist: chain-follow-up)`: chain `AskUserQuestion` calls per cap-extension pattern.

Always-WAIT in every mode. If empty answer returns, fall back to plain text and re-ask — never default to the reviewer's synthesis.

Skip entirely when zero PRODUCT-DECISION findings remain after the Phase 3 §3.3 KEEP/FILTER judgment.

---

## 3.5 Finalize the report (draft → final)

The handoff written in Phase 5.1 carries `report_status: draft`. After §2.5 (Pre-gate) and §3 (open-decision gate) clear, and BEFORE the §4 Action gate offers the handoff, flip it to `final`:

1. Re-verify every `open_questions[]` entry is `{resolved, wontfix}` and every PRODUCT-DECISION finding is `step0_status: {resolved, wontfix}` — the same invariants §7.0 re-reads. If any is still `unresolved` / `pending`, loop back to the owning gate; do NOT finalize.
2. Set frontmatter `report_status: final` via `atomic_state_write`.

This is a re-verify-plus-one-field-flip, NOT a re-bake — the per-finding decisions already persisted in §3 step 3. The field exists so the §4 Action gate's handoff option and the §7.0 public-post guard can assert the report is no longer provisional: a report still at `draft` means a decision gate did not clear, and the handoff would route an un-finalized report. Keep this step — a future "simplification" pass that strips it silently re-opens the gap the user reported (the handoff offered before their decisions land).

No AUQ fires here — finalize is silent. The user already answered the decision gates; a separate "finalize?" confirmation would be friction without new information.

The report file existed on disk as `draft` throughout the decision window (Phase 5.1 wrote it for crash-recovery). Finalizing in place — rather than writing the file only after decisions — is deliberate: a mid-gate compaction must still recover the dearly-bought findings. "No file until the user decides" trades crash-recovery for a guarantee the `draft` marker already provides.

---

## 3.7 Suggest improvements (reflection, read-only)

Runs after §3.5 finalize and BEFORE the §4 Action gate — only when Phase 6 fires (a zero-actionable-findings run skips Phase 6 entirely per §1, and this step with it). /geniro:review is a read-only reporter: this step proposes project-rule updates but never writes a project file itself. The review diff is the strongest rule-discovery surface in the plugin — a convention violated across several findings is exactly the signal that should become a project rule.

1. **Spawn the reflection agent (read-only).** Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` §"Reflection-agent feed", spawn `reflection-agent` (mode `review`) via the registration ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` (OMIT `model=`). Pass: the kept findings (the same `## Findings` set the handoff carries), the diff they were raised against, the rule-file paths to dedupe against (`CLAUDE.md`, `.claude/rules/*`, `.geniro/instructions/*`), and prior declines (`query-learnings --type user_rejected_suggestion --tag auq-rejection --scope review/<branch>`).

2. **Skip silently when the agent returns no candidates.** No echo, no AUQ.

3. **Surface candidates.** Group by target per the helper's §Routing table and fire ONE `AskUserQuestion` (header "Improvements"). Because /geniro:review never mutates project files, the options route rather than apply:
   - **"Capture as rules now"** — hand instruction-scoped candidates (`.geniro/instructions/*`, `code-style.md`) to `/geniro:instructions create`; list the CLAUDE.md / `.claude/rules/` / ADR candidates in chat for the user to apply manually or carry into `/geniro:implement`. /geniro:review writes none of them.
   - **"Review one-by-one"** — walk candidates individually; same routing per pick.
   - **"Skip"** — write nothing.
   A `Recurrence-eligible: yes` candidate routes to `/geniro:instructions create` directly — it restates a rule already seen 3+ times.

4. **Echo + log.** Echo `Reviewed for improvements: <N> candidate(s)`. On Skip or an explicit decline, log via `emit_rejection_if_signal` (`${CLAUDE_PLUGIN_ROOT}/lib/emit-rejection.sh`; scope `review/<branch>`, category `improvement_candidate`) so the same suggestion does not re-surface next round.

Advisory only: this step never blocks the Action gate, and a spawn failure fails open (skip with a one-line notice).

---

## 4. Action gate (Always-WAIT)

**Precondition — `report_status: final`.** The §3.5 finalize step runs immediately before this gate. If the report is still `draft`, a decision gate did not clear — loop back to §3.5 (which re-verifies and re-fires the owning gate); do NOT offer the handoff against a provisional report.

The consolidated top-level decision. Use `AskUserQuestion` (do NOT print options as plain text) with header "Action". Mark the severity-recommended escalation option with " (Recommended)" in its label.

**Literal AskUserQuestion shape** — copy and substitute the bracketed slots; do NOT paraphrase option labels, do NOT merge options across rows, do NOT drop options other than `Post Draft PR review` (the only conditional one):

```
AskUserQuestion(
  header="Action",
  question="How should I proceed with the <N> findings?",
  multiSelect=False,
  options=[
    {
      "label": "/geniro:implement findings",          # append " (Recommended)" when CRITICAL>=1 OR HIGH>=2
      "description": "Exit /geniro:review. You then run `/geniro:implement <handoff-path>` — it applies the fixes and asks before committing or pushing (a branch with an open PR prompts before that push; picking this routes the findings, it does not authorize a push)."
    },
    {
      "label": "Post Draft PR review",         # present when pr-ref non-none AND >=1 finding of any severity (incl. LOW/deferred) unposted AND not kept-off-PR (post-disposition: off-pr excluded from the count); OMIT when pr-ref:none OR no findings at all OR all already [POSTED-TO-PR] OR every remaining finding is kept-off-PR
      "description": "Post findings as a PENDING review on <pr-ref> (private to you, no notifications fire until you click Submit on github.com)."
    },
    {
      "label": "Continue rounds (re-review)",
      "description": "Loop back to Phase 1, round counter++. Round-N escalation gate fires when round >=3."
    },
    {
      "label": "Skip — keep findings on disk", # append " (Recommended)" when CRITICAL=0 AND HIGH<=1
      "description": "Terminal exit. Handoff file persists at .geniro/state/handoff/from-review-<branch>.md; resume later with /geniro:implement <path> or /geniro:review."
    }
  ]
)
```

After the user picks, surface ONE follow-up chat line stating the chosen next command verbatim (e.g., `Run: /geniro:implement .geniro/state/handoff/from-review-<branch>.md`) — the user runs the slash command themselves; the orchestrator NEVER auto-invokes /geniro:implement.

**Severity-driven recommendation:**
- Any CRITICAL OR ≥2 HIGH findings → `/geniro:implement` is "(Recommended)"
- 0 CRITICAL AND ≤1 HIGH findings → "Skip — keep findings on disk" is "(Recommended)"

**Question:** "How should I proceed with the N findings?"

**Options (≤4 per AUQ cap):**

- **/geniro:implement findings (Recommended when CRITICAL/HIGH count >0)** — exit /geniro:review, suggest the next command `/geniro:implement .geniro/state/handoff/from-review-<branch>.md`. /geniro:implement pre-loads the findings, applies the fixes, and asks before committing or pushing — choosing this routes the work, it does not pre-authorize a ship.
- **Post Draft PR review** — present whenever state file's `pr-ref:` is non-`none` AND at least one finding of any severity (including LOW / deferred / sub-threshold) remains unposted (no `[POSTED-TO-PR]` tag from prior run) AND not kept off the PR (`post-disposition: off-pr` from the §3 open-decision gate). LOW / deferred awareness findings count as postable — an all-LOW review still offers this option. On selection, drill into granularity sub-question (Step 2 below) before any `gh api` call. Posting is an external write to a public surface — the skill never posts without explicit approval; picking this option IS the approval.
- **Continue rounds (re-review)** — when round ≥3 fires Round-N escalation gate; otherwise loops back to Phase 1 increment round counter.
- **Skip — keep findings on disk** — terminal exit; user can resume later.

"Post" is omitted only when `pr-ref: none`, OR no findings exist at all, OR every finding already carries `[POSTED-TO-PR]`, OR every remaining finding is kept off the PR (`post-disposition: off-pr`) — findings of any severity (including LOW / deferred / sub-threshold) count as postable, so an all-LOW review still presents the option. The Action gate is mutually exclusive — user chooses ONE path.

**Persist user pick to `approvals[]`** with category `action_gate`, written via `atomic_state_write` (never a raw `Edit`/`Write` on the handoff — that trips the `enforce-state-helper` hook).

Do NOT auto-invoke /geniro:implement — surface the suggestion only. The user runs the slash command themselves; the state file path is the handoff channel.

---

## 5. Round-N escalation gate

When round ≥3 AND user picks "Continue rounds", fire a secondary AUQ:

- **Continue (round 4)** — re-enter Phase 1 with round counter incremented; risk of infinite loop if user picks repeatedly (capped at round 5 hard ceiling — round 6 attempts auto-trigger "Escalate to user").
- **Escalate to user — structured handoff** — terminal `escalated` state; emits one structured `open_questions[]` frontmatter entry per unresolved next-step (`source: round-N-escalation`, `status: unresolved`), AND writes a chat-surface summary. Downstream consumers gate on the entries per the `open_questions[]` contract in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md`.
- **Abort** — terminal `aborted` state; `## Termination reason: repeated-failure: round-limit-3`.

Persist user pick to `approvals[]` with category `round_n_escalation`, written via `atomic_state_write`.

---

## 6. Failing-tests gate

Fires when `## Authored Tests` section is non-empty. Firing order conditional per gate chain.

- **Header:** "Failing tests"
- **Question:** "How should the N failing tests authored during the test-confirmation step be handled? They are AI-authored — review before merging. If you just chose to post findings as a Draft PR review, the comment bodies reference these test files by path — pushing them to the PR's branch is what makes those references resolve for PR reviewers."

**Options:**
- "Commit failing tests on current branch" — orchestrator stages only the test files listed in `## Authored Tests` (never `git add -A` / `git add.`), composes a commit message following the repo's commit style (check `git log -5 --oneline` first), and commits via HEREDOC. **Recommended in Standard mode and in TDD mode without a PR ref** — except when user selected "Post" in Action gate, in which case commit+push is Recommended.
- "Commit + push to current branch's upstream" — same as commit-only, then `git push`. **Recommended in TDD mode when a PR ref is present, and also Recommended in any mode when user selected "Post"** — load-bearing, not cosmetic.
- "Leave uncommitted" — tests stay on disk for user to review and stage manually.

Never use `--no-verify`, `--amend`, or destructive flags. If a pre-commit hook fails, surface the failure and stop — do not retry or bypass.

Persist user pick to `approvals[]` with category `failing_tests_commit_policy`, written via `atomic_state_write`.

---

## 7. Action == Post drill (PR-ref input only)

When user picked "Post" in the Action gate:

1. If `## Authored Tests` is non-empty: fire Failing-tests gate FIRST (push lands before `gh api` POST).
2. Continue with Steps 1.5-6 below.

When Action != Post or Post option was omitted, skip Steps 1.5-6 and proceed to Failing-tests (when applicable) and cleanup.

### 7.0 Step 0 — Unresolved-ambiguity guard (fail-closed)

Before any of the Post-drill steps below fire, re-read state.md and verify FOUR invariants. If any fails, abort the Post drill — never post to GitHub with unresolved ambiguity, missing user picks, refuted findings baked in, or a provisional (un-finalized) report.

**Invariant A — no `open_questions[]` left `unresolved`.** The §2.5 Pre-gate runs first in Phase 6 and should leave zero entries with `status: unresolved` by the time Action gate fires.

**Invariant B — every PRODUCT-DECISION finding has `step0_status: resolved` (or `wontfix`).** The §3 Step 0 per-finding gate runs after §2.5 and flips each PRODUCT-DECISION finding's `step0_status: pending` → `resolved` once the user's AUQ pick lands. A finding still at `pending` here means §3 never fired for it — and §7.5 would route it to `comments[]` by `File:` sentinel alone, with either AUQ chip label (`"Open question"` from §2.5 or `"Open decision"` from §3) potentially leaking into the comment body as if it were a tag.

**Invariant C — every kept finding (CRITICAL / HIGH / MEDIUM) has `Validation: confirmed` or `Validation: clarified`.** The Phase 4.2 per-finding verifier should filter `validation: refuted` findings before they reach the handoff. Any kept finding in `## Findings` carrying `Validation: refuted` indicates a producer-side filter failure; posting it to GitHub would surface a finding the verifier already judged incorrect. This guard re-checks at the external-effect boundary as defense-in-depth — refuted should never reach Post. Missing `Validation:` on a CRITICAL / HIGH / MEDIUM finding (legacy handoff per §2 back-compat) is NOT a violation: treat as `confirmed` and proceed with the one-line warning. The guard rejects `refuted` and field-mismatch (non-enum values), not absence.

**Invariant D — `report_status: final`.** The §3.5 finalize step flips the report from `draft` to `final` after the §2.5 Pre-gate and §3 open-decision gate clear. A report still at `draft` here means finalize never ran — a decision gate is open, or the flip was lost — and posting a provisional report to a public surface is the failure this guard prevents. Missing `report_status` reads as `final` (back-compat per the state-tier-spec single-source rule), so the guard rejects an explicit `draft`, not absence.

This §7.0 check is the fail-closed second line of defense for ALL FOUR invariants: if a producer wrote a new `open_questions[]` entry mid-phase, if `atomic_state_write` raced with a parallel resolver, if §3 was conflated with §2.5 / skipped under orchestrator drift, if Phase 4.2's filter pass dropped a `refuted` entry from the filter list but left it in `## Findings`, or if §3.5 finalize was skipped under drift and left the report `draft`, the upstream gates' invariants might not hold. Verify defensively.

**Procedure:**

1. Read state.md frontmatter via `Bash: cat ... | head` and parse `open_questions[]`. Read the `## Findings` body section and parse each finding's `Severity:`, `Decision Type:`, `step0_status:`, AND `Validation:` fields.
2. Build four filter lists: (a) `open_questions[]` entries with `status: unresolved`; (b) findings with `Decision Type: PRODUCT-DECISION` AND `step0_status: pending`; (c) findings with `Severity: CRITICAL | HIGH | MEDIUM` AND (`Validation: refuted` OR `Validation:` set to a non-enum value); (d) frontmatter `report_status` explicitly set to `draft` (missing reads as `final` — not a violation).
3. If any of the four lists is non-empty:
   - Surface a one-line chat warning naming the count of each non-empty list (e.g., `"Can't post yet: 2 open questions still need your answer + 1 finding needs a decision from you + 1 finding the verifier couldn't confirm."`) and the first 1-2 affected items.
   - Append a `## Errors` entry to state.md via `atomic_state_write` with `phase: action-gate`, `error: post-drill-aborted-on-unresolved-ambiguity`, the unresolved question IDs, the pending finding IDs, AND the refuted/invalid finding IDs.
   - Re-fire the §2.5 Pre-gate for any unresolved `open_questions[]` entries (if list (a) non-empty).
   - Re-fire the §3 Step 0 per-finding gate for any `step0_status: pending` PRODUCT-DECISION findings (if list (b) non-empty).
   - For list (c) refuted/invalid findings: do NOT auto-resolve. Refuted findings must be moved to `## Filtered` (with `reason: verifier-refuted`) by re-running Phase 4.2's filter pass — surface a chat instruction: `"Re-run /geniro:review to re-fire Phase 4.2 per-finding verification, OR manually move the refuted finding(s) to ## Filtered."` Then abort Phase 6 entirely (terminal state `aborted`, `## Termination reason: producer-schema-violation: refuted-finding-in-handoff`) — the user re-runs /geniro:review rather than racing a manual edit against a pending Post.
   - For list (d) (report still `draft`): re-run the §3.5 finalize step — it re-verifies lists (a) + (b) and flips `report_status: final`. If (a) / (b) are non-empty, finalize loops to their owning gates first.
   - After resolution loops for lists (a) + (b) + (d) complete, loop back to step 1 of this section. Do NOT proceed to §7.1 until step 3 finds ALL FOUR filtered lists empty.
4. When step 3 finds all four filtered lists empty, proceed to §7.1.

This guard exists because posting a draft PR review with unresolved ambiguity, missing user picks, verifier-refuted findings buried in the body, or a report the user has not finished deciding would push it onto the PR author or downstream reviewer — exactly the failure mode the `open_questions[]` array, `step0_status:` sentinel, `Validation:` field, and `report_status` lifecycle are designed to prevent. The four invariants are independent (different arrays, different gates, different producer phases) so the guard must check all four; checking only some leaves the remaining paths uncovered.

### 7.1 Step 1.5 — Resolved-thread dedup (input-side filter)

The post-drill's eligible-finding set is every unposted finding across BOTH `## Findings` (kept CRITICAL / HIGH / MEDIUM + any LOW `PRODUCT-DECISION` admitted via §4.1 Path B) and `## Deferred — sub-threshold` (LOW awareness items) — once the user has chosen to post, severity no longer gates postability. Before showing eligible findings to the user, exclude findings whose `path:lines` overlaps an entry in the state file's `resolved-threads-snapshot:`. Overlap rule: finding `<P>:A-B` overlaps a snapshot entry `<Q>:L` when `P == Q` AND `A <= L <= B`. Path equality is required.

For each matching finding, append `[ALREADY-RESOLVED-ON-PR]` to its tag list and add `reason: already-resolved-on-pr` annotation when moving to `## Filtered`. The Step 2 granularity AUQ and Step 3 per-finding gate count only non-excluded findings.

Also exclude any finding carrying `post-disposition: off-pr` (set by the §3 open-decision gate when the user picked "Keep off the PR — I'll handle this"): append `[KEPT-OFF-PR]` to its tag list, move it to `## Filtered` with `reason: user-kept-off-pr`, and never place it in the inline `comments[]` or the body. This is the audience control for a decision residue the PR author cannot action — the decision is recorded for the reviewer, not posted to the PR.

When Step 1.5 empties the post set, fall back to Skip semantics — do not call `gh api` POST; surface `All eligible findings were excluded (already-resolved threads or kept-off-PR) — nothing drafted on PR` once in chat.

### 7.2 Step 2 — Granularity gate

Chain a follow-up `AskUserQuestion` with header "Post mode":

- **Question:** "Send all unposted findings (including LOW / deferred awareness items) in a single batched review, or pick which ones to post?"
- **Options:**
- "Send all (Recommended)" — single batched review event minimizes per-finding AUQ calls and dodges secondary rate limits with a single POST.
- "Pick one-by-one" — chained `multiSelect` prompts; you choose which findings to include.

### 7.3 Step 3 — Per-finding gate

Fires only on "Pick one-by-one". Iterate over the eligible-findings list (filtered by Step 1.5 when applicable — Step 3.5 is mode-independent and applies no filter). For each finding, fire ONE `AskUserQuestion` per canonical Single-finding gate shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md`. Calling-skill-set fixed menu: finding's own `Options:` is ignored; calling-skill menu is the three options below.

- **`header`:** `"Post finding?"`
- **Chat render (first):** render the finding to chat per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering — a self-contained block (what the code does / the concern / why it matters / evidence, in plain English) so the user decides whether to post from an explained finding, not a side-box snippet.
- **`question`** (lean): the plain-English one-line title, then the ask:
```
<plain-English one-line title> — `path:lines`

Full explanation above. Post this finding to the PR as an inline comment, or skip?
```
- **`options[]`** (three fixed options):
- "Post this finding" — adds finding to post set; iteration continues.
- "Skip this finding" — omits; iteration continues.
- "Stop posting (skip remaining)" — exit loop entirely; all unseen findings treated as Skip.
- **`preview`**: leave empty or a one-line recap; the finding body lives in the chat block (§ Message-first rendering), not the side-box.

After loop completes (or user picked "Stop posting"), aggregated post set is the union of "Post" picks. If empty, treat as Skip and proceed without firing `gh api` POST.

### 7.4 Step 3.5 — Post-set (mode-independent)

The posted set is the same in Standard and TDD mode: every kept finding posts. TDD mode is purely additive — it authors failing tests for the testable findings and appends a `**Failing test:** \`<path>\`` line to each `[CONFIRMED-BY-TEST]` finding (per §7.6) — but it never removes a finding from the post set. There is no mode-dependent filter here.

This step is retained as a no-op so the surrounding `§7.x` section numbers stay stable — removing it would renumber `§7.5` onward and break the cross-references that point at those sections.

### 7.5 Step 4 — Post via the GitHub reviews API

Parse `<owner>/<repo>/<number>` from the state-file Summary's `pr-url`. Pass snapshotted `pr-head-sha` as `commit_id` — but see head-SHA freshness rule. ONE `gh api` call posts the entire review.

**Head-SHA freshness — re-fetch when authored tests were just pushed.** When Failing-tests gate fired BEFORE this step AND user picked "Commit + push", the local push advanced the PR's head past `pr-head-sha`. Re-fetch:

```bash
gh pr view <pr-ref> --json headRefOid --jq '.headRefOid'
```

Use the returned value as `commit_id`. Also overwrite state file's `pr-head-sha:` with the re-fetched value. Without this re-fetch, API rejects comments whose `path` is not present in `commit_id`'s tree with `Validation Failed: path could not be resolved`.

**Split the post set:**
- Findings with `File: <path>` whose line is present in the diff's `commit_id` tree → inline `comments[]` array. Inline-anchor every such finding regardless of severity — a LOW finding on a changed line is still an inline comment, never a body bullet. Severity gates whether a finding is kept (Phase 4.1), not where a kept finding renders.
- Findings with `File: <path>` whose line is OUTSIDE the diff (the line is unchanged, so the reviews API rejects the inline comment with `path could not be resolved`) → top-level review `body` under a `## Findings on unchanged lines` section, each rendered as `**<SEVERITY>** \`<path>:<line>\` — <description>` so the reader can still locate it. This is the ONLY sanctioned route for a real file-finding into the body — it exists because GitHub cannot anchor a comment to a line absent from the diff, not as a catch-all for findings the orchestrator would rather batch. A finding whose line IS in the diff must never land here.
- Findings with `File: PR-METADATA` → top-level review `body` under `## PR Metadata` section.
- Findings with `File: SPEC-COMPLIANCE` → top-level review `body` under `## Spec Compliance` section.

```bash
jq -nc \
--arg sha "<pr-head-sha-or-re-fetched-sha>" \
--arg body "<concatenated-body: summary header + ## Findings on unchanged lines + ## PR Metadata + ## Spec Compliance sections>" \
--argjson comments '<comments-json — inline-anchored findings only>' \
'{commit_id: $sha, body: $body, comments: $comments}' \
| gh api --method POST "/repos/<owner>/<repo>/pulls/<number>/reviews" --input -
```

Omit `event` entirely from the jq payload — the review is created in PENDING state (visible only to the reviewer on github.com's "Finish your review" panel; no notifications fire until human submits). Never set `event` to `APPROVE`, `REQUEST_CHANGES`, or `COMMENT`. `event: "PENDING"` is INVALID; omission is the correct mechanism.

Each comment object:

```json
{
"path": "<file path relative to repo root>",
"line": <last line>,
"side": "RIGHT",
"start_line": <first line, ONLY when range spans multiple lines; OMIT for single-line>,
"start_side": "RIGHT",
"body": "**<SEVERITY>** — <description>\n\n**Recommendation:** <recommendation>"
}
```

**Persist non-resumable-action.** Append to state file's `non-resumable-actions[]`

```yaml
non-resumable-actions:
- action: pr-review-comment-batch
completed-at: <ISO-8601>
pr-ref: <owner>/<repo>#<num>
finding-count: <N>
comment-ids: [<id1>, <id2>,...]
```

### 7.6 PR-comment body content rules (hard)

GitHub PR comments are public, audience-expanding output. Each comment body opens with the severity badge per the §7.5 comment-object template (`**MEDIUM** — <description>`) and MUST contain ONLY: severity badge, finding's plain-language description, recommendation, and (for `[CONFIRMED-BY-TEST]` findings) the appended `**Failing test:** \`<test-path>\`` line. The orchestrator's internal finding handle (`M1`, `M1b`, `L5`, …) is a chat/handoff cross-reference only — it MUST NOT prefix or appear in a comment title; the PR author has no map for `M1b`.

**MUST NOT** add to the body or top-level review body:
- Plugin branding (`Geniro`, `/geniro:` prefix, "Generated by …" footers).
- Decision-type tags (`[FIX-NOW]`, `[TESTABLE]`, `[PRODUCT-DECISION]`, `[INTENT-CHECK]`).
- AUQ `header:` chip labels echoed as if they were tags (`[Open question]`, `[Open decision]`). These literals are reserved for the §2.5 Pre-gate and §3 Step 0 AUQs that gate downstream action; echoing them in a PR comment body re-projects unresolved ambiguity onto the PR author, which is the exact failure mode those gates exist to prevent. If a finding reads as an open question, it has not completed §3 — abort the post and re-fire the gate per §7.0, do not relabel it for the PR.
- Pipeline phase names (`Phase 4.3`, `judge pass`, `relevance filter`, `test-confirmation gate`).
- Confidence numerics (no `*Confidence: NN%*`).
- State-file paths or schema references.
- User-decision artifacts (`user picked X`, `approved by user`).
- Internal tags (`[CONFIRMED-BY-TEST]`, `[CHALLENGED-BY-TEST]`, `[POSTED-TO-PR]`, `[NEW]`, `[PRE-EXISTING]`, `[ALIGNS-WITH-PLAN]`, `TRUNCATED`).
- Internal finding IDs / orchestrator labels (`M1`, `M1a`, `M1b`, `M2`, `M3`, `L1`…`L7`, `F1`…, and any `<letter><digit>` handle assigned to enumerate findings in the chat summary or handoff). They exist only to cross-reference findings off the PR; the comment body opens with the severity badge, never a finding handle.
- Internal knowledge-base references — incident IDs (`incident 4`), learning IDs (`learning B.1.5`), and the project's internal incident-report cross-references (a `B.x.y`-style token when it is introduced by the word `incident`/`learning` or appears as a bare parenthetical cross-reference, e.g. `(incident 4 / learning B.1.5)`). These index a private incident log / learnings store the PR author cannot open, so the bare ID reads as noise. The `incident`/`learning` keyword or the parenthetical cross-reference shape is what identifies the pattern — a bare `<letter>.<digit>.<digit>` that is a genuine code fact under review (a spec section ref, a test-case ID, a version) is NOT this pattern and stands. Cite the failure mode in plain language ("the documented backdated-migration-ordering failure") and drop the parenthetical ID — or substitute a shareable link if the reviewer briefing carries one.

The reviewer-agent's `description:` and `recommendation:` fields go into the body verbatim — if they legitimately mention any of these strings about the code under review, they stand as-is. The rule constrains orchestrator body-composition, not reviewer findings about the code. **One class is the exception inside the verbatim fields: internal knowledge-base references** (the `incident N` / `learning X.Y.Z` / `B.x.y` patterns in the bullet above). Unlike a code symbol named `M1`, an incident/learning ID is never a fact about the code under review — it indexes a private log the reader cannot open — so it is scrubbed even mid-sentence in a reviewer's `description:`/`recommendation:`: strip the parenthetical ID (or swap in a shareable link) and keep the surrounding plain-language description intact.

**Enforcement — scrub before POST (hard).** §7.6 is otherwise advisory — an orchestrator naturally echoes its own finding handle (`**M1b …`), skill branding (`## /geniro:review …`), or a `handoff`/state-path reference into the composed title and summary, so the rules leak under drift. Before the `gh api POST /reviews`, scan the assembled top-level `body` and every `comments[].body` against the MUST-NOT set above; on a hit in orchestrator-composed text (comment title, summary header, section prose) strip or rewrite it and re-scan until clean — never POST a body that still matches. A token inside a reviewer's verbatim `description:`/`recommendation:` about the code under review stands per the note above; the scrub targets composition, not the reviewer's words. Match only the orchestrator-prepended title/prefix and the summary/section framing — never the verbatim `description:`/`recommendation:` segment a finding carries (a reviewer that legitimately writes "the `L2` cache" or names a code symbol `M1` stands; the leak vector is a handle in the *title slot*, `**M1b — …`, not a token mid-sentence). The lone exception is the internal knowledge-base cross-reference class (`incident N` / `learning X.Y.Z`, and a `B.x.y` token in that incident/learning context per the bullet above): scrub it wherever it appears, INCLUDING mid-sentence inside a reviewer's verbatim `description:`/`recommendation:` — replace the parenthetical ID with nothing (or a shareable link) and preserve the rest of the sentence. A bare `<letter>.<digit>.<digit>` that is a genuine code fact (a spec section, a test-case ID, a version) is not this class and stands. An incident/learning index is never a code fact, so the verbatim carve-out does not protect it. This is the external-effect-boundary analog of the §7.0 guard.

### 7.7 Step 5 — Persist `[POSTED-TO-PR]` markers

Parse POST response to extract review's `id` field. Second call to derive per-comment URLs:

```bash
gh api "/repos/<owner>/<repo>/pulls/<number>/reviews/<review-id>/comments"
```

Match each returned comment back to its source finding by `(path, line)`. For each matched comment, append `[POSTED-TO-PR]` to the finding's tag list and add `posted-to-pr: <html_url>` to the line in the state file. The idempotency contract: the next `/geniro:review` run against the same PR reads these markers and excludes already-posted findings.

If the GET fails (rate limit, transient error), persist `[POSTED-TO-PR]` markers without `posted-to-pr:` URLs — the dedupe contract holds (marker IS the key).

After markers persisted, surface ONE chat-surface line:

```
Drafted N findings as a pending review on <pr-url>. Open the PR and click "Finish your review" → Submit when ready — pending reviews are private to you and fire no notifications until submit.
```

### 7.8 Step 6 — Posting-failure semantics

If the `gh api` call fails (non-zero exit, HTTP error, missing scopes, secondary rate limit): surface the error verbatim to the user and stop — do not retry, do not fall back, do not bypass with `--no-verify`-style flags, do not silently downgrade to top-level `gh pr comment`. No partial state is written: leave per-finding `[POSTED-TO-PR]` tags off entirely so user can re-run cleanly after fixing the underlying issue. Mirrors fail-closed semantics.

Append to state file `## Errors`:

```yaml
- phase: persist
stage: pr-review-comment-post
error: <verbatim gh stderr>
consequence: post-aborted-no-state-mutation
```

---

## 8. Empty-answer handling (universal)

If `AskUserQuestion` returns an empty answer at any prompt in Phase 6, fall back to plain text and re-ask once — never promote empty to a default Yes. After one re-ask, if still empty, treat as Skip and proceed without posting.

---

## 9. Terminal state mapping

| User pick | Terminal state | `## Termination reason` body |
|---|---|---|
| /geniro:implement findings | `done` | (omitted) |
| Post Draft PR review (successful POST) | `done` | (omitted) |
| Post Draft PR review (POST failed) | `aborted` | `tool-unavailable: gh-api-post` |
| Continue rounds → Round-N → Abort | `aborted` | `repeated-failure: round-limit-3` |
| Continue rounds → Round-N → Escalate | `escalated` | (omitted; surfaced in `## Open Questions`) |
| Skip — keep findings on disk | `done` | `modifier-exit: skip-action` |

The SessionStart hook surfaces `## Termination reason` on resume so model and user see context, not bare "aborted".
