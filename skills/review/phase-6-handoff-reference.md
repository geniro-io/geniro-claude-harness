# Phase 6 Action-Gate Hand-off Reference

Detailed contract for `/geniro:review` Phase 6 (Action Gate Hand-off). SKILL.md retains a 2-3 line summary + a pointer here.

State.md `phase: action-gate` during this phase.

**Handoff schema version: `m6-v2`.** Bumped from `m6-v1` — per-finding body schema extended with verification fields (`Validation` / `Recommended-action` / `Verification-confidence` / `Verification-evidence`) emitted by the Phase 4.2 per-finding verifier. Producer writes the value into the handoff frontmatter (`geniro_schema_version:` per SKILL.md §5.1 Handoff file write). Consumers accept BOTH `m6-v1` (legacy — verification fields absent) AND `m6-v2` (rich — verification fields mandatory on every kept finding: CRITICAL / HIGH / MEDIUM). Within m6-v2, a producer running the pre-hoist Phase 4.2 (HIGH-only verification) emits verification fields on HIGH findings only; consumers treat absence on CRITICAL or MEDIUM as legacy-pre-hoist, applying the same "treat as confirmed + one-line warning" fallback as `m6-v1` absence on HIGH.

## Contents

- §1 — Reporter behavior (no fix loop)
- §2 — Gate chain (firing order)
- §2.5 — Pre-gate: resolve open questions (Invariant A)
- §2.6 — Handoff file template (written in Phase 5.1)
- §3 — Step 0: open-decision per PRODUCT-DECISION finding (Invariant B initial flip)
- §4 — Action gate (consolidated decision)
- §5 — Round-N escalation
- §6 — Failing-tests gate
- §7 — Action == Post drill (sub-sections 7.0 fail-closed guard with three invariants → 7.8 posting-failure semantics)
- §8 — Empty-answer handling (universal)
- §9 — Terminal state mapping

---

## 1. Reporter behavior — no fix loop

This skill confirms: /geniro:review does NOT apply fixes. Phase 6 hand-off message NEVER includes "I'll fix these now" language. The /geniro:implement option routes to /geniro:implement skill (manual or via Phase 6 hand-off line).

`--simplify` flag does NOT change this. The flag biases Phase 2 reviewer attention but the output is still a finding list for consumption by other skills.

**Skip Phase 6 entirely when:**
- Zero actionable findings remain (CRITICAL + HIGH + MEDIUM all zero after Phase 4.2).

---

## 2. Gate chain — fire each as a separate AUQ

Phase 6 surfaces up to 4 sequential top-level gates. Each one decides a different thing AND MUST be its own `AskUserQuestion` call — never collapse them into a single summary question, never paraphrase the question text, never merge options across gates.

**Firing order:**

1. **Pre-gate — Resolve Open Questions:** fires once when state.md frontmatter `open_questions[]` has any entry with `status: unresolved` AND `gates_review != false`. Chain one AUQ per such entry (cap-extension when >4). Always-WAIT. MUST complete before any other Phase 6 gate fires — these questions gate what /geniro:review posts. Fix-path entries (`gates_review: false`) are recorded for /geniro:implement, never surfaced here. Full procedure: §2.5 below.
2. **Step 0 — Open-decision (per finding):** fires once per `Decision Type: PRODUCT-DECISION` finding kept by the Phase 3 §3.3 KEEP/FILTER judgment. Skipped when zero PRODUCT-DECISION findings remain.
3. **Action (Always-WAIT):** fires once whenever this phase fires — the consolidated top-level decision. User picks ONE next step: /geniro:implement / Post Draft PR / Continue rounds / Skip.
4. **Failing tests:** fires once when the state file's `## Authored Tests` section is non-empty — picks the commit policy for AI-authored tests. Firing order relative to Action gate conditional:
- **Action == Post AND `## Authored Tests` non-empty:** Failing-tests fires BEFORE the Post drill (GitHub reviews API rejects comments whose `path` is absent from `commit_id`'s tree).
- **Action != Post OR `## Authored Tests` empty:** Failing-tests fires AFTER Action gate's path completes.

Sequential: do not fire gate N+1 until gate N's answer is collected.

---

## 2.5. Pre-gate — Resolve Open Questions

This gate runs FIRST in Phase 6 — before Step 0, Action, and Failing-tests gates — whenever state.md frontmatter `open_questions[]` carries any entry with `status: unresolved` AND `gates_review != false`.

**Why it runs first.** A review-gating open question is one whose answer changes what the Action gate is choosing between (e.g., "API seeder additions in-scope or split into a separate PR?" — the answer changes which findings get posted). Letting Action gate fire first means the user picks "/geniro:implement findings" without realizing those questions still gate the implementation.

**What this gate does NOT ask.** Pure fix-path / how-to-resolve questions (`gates_review: false`, e.g. "the CI build is red because the PR commits failing TDD tests — how should it be resolved?") are NOT surfaced here. /geniro:review is a reporter; it does not decide fixes. Those entries stay `unresolved` and ride the handoff to /geniro:implement, which resolves them at its Phase 1 gate when the user is actually fixing. Surfacing one as a blocking AUQ — when the answer doesn't change what /geniro:review does — is the over-asking failure `gates_review` exists to prevent (see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md` §4).

**Procedure:**

1. Read frontmatter `open_questions[]`. Filter to entries with `status: unresolved` AND `gates_review != false` (the field defaults to `true` when absent — legacy entries are review-gating as before). Entries with `gates_review: false` are skipped: leave them `unresolved` so the handoff carries them to /geniro:implement.

2. For each unresolved entry, fire one `AskUserQuestion` call. The renderer picks one of three tiers in order — the **first tier whose required source data is available** wins:

   **Tier 1 — Producer-authored rich entry (preferred).** When the entry carries `context` / `evidence` / `options` / `recommendation` fields per the extended schema in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2 `open_questions`:
   - `header`: `"Open question"` (literal — never paraphrase)
   - `question`: multi-line markdown rendered per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Single-finding gate, substituting fields:
     - `<SEVERITY>` — omit (open_questions don't carry severity directly; if `related_findings[]` is non-empty, render the highest-severity related finding's severity here)
     - `<path:lines>` — entry's `evidence[0].file:lines` if present, else omit
     - `<short title>` — first sentence of `question`
     - `<type>` — entry's `source` (e.g., `spec-compliance`, `bugs`)
     - "Why this matters" line — first 1-2 lines of `context`
     - body — full `context` rendered verbatim under a `## Context` block
   - `options[]` — one per `options[]` entry in the question:
     - `label` — option's `label`
     - `description` — option's `description`
     - `preview` — option's `preview` PLUS a trailing `## Evidence` block built from the entry's `evidence[]` array (same preview body on every option — the body is per-question, not per-option) PLUS a `## Recommendation` line when `recommendation.option_id == this.id` (italicized: *"Producer recommends this option — <rationale>"*)
   - When `recommendation.option_id` is set, position THAT option first in the `options[]` array and suffix its `label` with ` (Recommended)`.

   **Tier 2 — Cross-reference into `## Findings` body.** When the entry has `related_findings: [F1, F2, ...]` non-empty but lacks the Tier 1 rich fields, read those finding blocks from the same handoff file's `## Findings` body (per the multi-line "Per-finding body schema" defined later in this same reference file, after the Wontfix-path note below). Apply `per-finding-question.md` § Single-finding gate rendering directly against the first related finding's body — Evidence / Suggested-fix / Confidence / Origin all flow from the finding fields. When >1 related findings exist, prefer the highest-severity finding; mention the others as `"Also gates: F2, F3"` in the question body.

   **Tier 3 — Legacy synth fallback.** When neither Tier 1 nor Tier 2 source data is available (bare `question:` only):
   - `question`: the entry's `question:` field, verbatim
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

6. After the last review-gating entry resolves, every `open_questions[]` entry with `gates_review != false` MUST be in `{resolved, wontfix}` before proceeding to Step 0 / Action / Failing-tests. (`gates_review: false` entries stay `unresolved` by design — recorded for the consumer.) Verify by re-reading the frontmatter; if any review-gating `unresolved` remains, loop back to step 2.

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
mode: <standard|tdd>
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
<!-- Findings demoted out of ## Findings: verifier-refuted (reason: refuted-by-verifier), test-challenged (`[CHALLENGED-BY-TEST]`), already-resolved-on-PR, or Phase 3 convention-filtered. Kept visible with original severity + reason so the user can re-elevate; never propagated to ## Findings, open_questions[], or the Post drill. -->
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

**Verification fields — presence rules.** The four `Validation` / `Recommended-action` / `Verification-confidence` / `Verification-evidence` fields are MANDATORY on every kept finding (CRITICAL / HIGH / MEDIUM) that lands in `## Findings`. Phase 4.2 spawns one fresh `reviewer-agent` per §4.1 survivor regardless of severity; verdicts of `validation: refuted` are filtered before reaching the handoff, so any finding present here carries `Validation: confirmed` or `Validation: clarified`. The fields are ABSENT on LOW findings (LOW never enters Phase 4.2 — §4.1 admits only `severity >= MEDIUM`). When `Validation: clarified`, the verifier judged the original reviewer's finding partially correct but mis-classified; the `Recommended-action:` value carries the corrected routing and supersedes the original `Decision Type:` for §3 gate firing and downstream consumer decisions.

**Verification fields — back-compat for legacy handoffs.** Two legacy cases produce findings without the four verification fields:
1. `m6-v1` (pre-Phase-4.2) writers — no findings carry verification fields at any severity.
2. `m6-v2` writers from before the verifier was hoisted to CRITICAL/MEDIUM — HIGH findings carry verification fields; CRITICAL and MEDIUM findings do not.

Consumers (§7.0 fail-closed guard, /geniro:implement Phase 1 Step 12) treat a missing `Validation:` on any CRITICAL/HIGH/MEDIUM finding as `Validation: confirmed` and surface a one-line chat warning so the user knows Phase 4.2 verification was not actively run for that finding. This mirrors the existing `step0_status: missing → resolved` back-compat behavior documented above — the safety improvement post-dates these handoffs, so missing-field MUST NOT block the Post drill that worked before the field existed.

**Backward-compatible parsing.** Consumers (Phase 6 §2.5 Tier 2 lookup, §3 per-finding gate, /geniro:implement Step 12) accept BOTH the rich multi-line block above AND the legacy one-liner shape `- [NEW|PRE-EXISTING] path:lines — <description> — decision: ... — recommendation: ... — confidence: NN% — origin: ...` produced by older /geniro:review runs. Legacy one-liners fall back to the terse rendering (§2.5 Tier 3 / per-finding-question.md degraded mode); rich blocks unlock the full Single-finding gate shape. **Legacy handoffs predate the `step0_status:` sentinel** — when §7.0 parses a legacy one-liner with `Decision Type: PRODUCT-DECISION` (or its lowercase one-liner form `decision: PRODUCT-DECISION`) and no `step0_status:` sub-field, treat it as `step0_status: resolved` (the safety improvement post-dates these handoffs) and surface a one-line chat warning so the user knows Invariant B was not actively re-verified for that finding. Never treat a missing field as `pending` — that would false-positive on every legacy handoff and block the Post drill that worked before the field existed.

**Wontfix path.** If the user picks "Other" with explicit text like "ignore" / "skip" / "not now", set `status: wontfix` and `resolution.picked` to the user's text. Wontfix entries do NOT block downstream gates — they're recorded but de-prioritized. Downstream consumers treat `wontfix` as "user acknowledged and chose to defer".

**No skipping.** The pre-gate cannot be deferred to /geniro:implement or to the Post drill. Resolving here makes the Action gate's options meaningful (e.g., "/geniro:implement findings" now points to a known-scope target). Resolving downstream creates the failure mode this gate exists to prevent.

---

## 3. Step 0 — Open-decision gate (per-finding, Always-WAIT)

Before recommending which skill to run, surface every `Decision Type: PRODUCT-DECISION` finding kept by the Phase 3 §3.3 KEEP/FILTER judgment to the user — they pick the resolution path; orchestrator NEVER picks on their behalf. The orchestrator must not auto-resolve multi-path findings even when the reviewer's `recommendation:` field appears obvious.

**For each kept finding with `Decision Type: PRODUCT-DECISION` (read from state file):**

1. Read the finding's `Options:` sub-list AND body sub-fields (`evidence:`, `why-matters:`, `suggested-fix:`). For CRITICAL / HIGH / MEDIUM findings, confirm the Phase 4.2 verifier passed before firing the AUQ: the `Validation:` field MUST be `confirmed` or `clarified`. A `Validation: refuted` finding should already be filtered upstream at Phase 4.2 — if encountered here, it indicates a producer-side schema violation; emit an entry to state.md's `## Errors` body section (`phase: action-gate`, `error: refuted-finding-reached-step-0-gate`, finding ID) and skip the AUQ for that finding. A missing `Validation:` on a CRITICAL/HIGH/MEDIUM finding (legacy handoff per §2 back-compat) is treated as `confirmed` — proceed with the AUQ but surface the one-line warning.
2. Fire `AskUserQuestion` per the canonical shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Single-finding gate. Set `header: "Open decision"`. Render the `question` text with finding's severity / `path:lines` / short-title / decision-type / `why-matters` line per spec's Source-field map; render each option's `label`+`description` from finding's `options:` sub-list bullets; render each option's `preview` with finding body (Evidence / Suggested-fix / Confidence / Origin). Do NOT collapse rendering to label + 1-line description.
3. Update the finding line in the state file via `atomic_state_write` (never a raw `Edit`/`Write` — the handoff is a canonical state path and raw writes trip the `enforce-state-helper` hook): replace `recommendation:` field with user's chosen option text AND set `step0_status: resolved` (or `step0_status: wontfix` when the user picks "Other" with skip/defer text). Preserve `options:`, `evidence:`, `why-matters:`, `suggested-fix:`. The state file is the handoff to the next skill, so the chosen path AND the body travel with the finding. The `step0_status` flip is the sentinel §7.0 re-reads to verify this gate actually fired — without it, a §3-skipped finding ships to PR as if the AUQ header `"Open decision"` were a tag.

When more than 4 PRODUCT-DECISION findings exist OR a single finding's `Options:` carries `(more-options-exist: chain-follow-up)`: chain `AskUserQuestion` calls per cap-extension pattern.

Always-WAIT in every mode. If empty answer returns, fall back to plain text and re-ask — never default to the reviewer's synthesis.

Skip entirely when zero PRODUCT-DECISION findings remain after the Phase 3 §3.3 KEEP/FILTER judgment.

---

## 4. Action gate (Always-WAIT)

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
      "label": "Post Draft PR review",         # present when pr-ref non-none AND >=1 finding of any severity (incl. LOW/deferred) unposted; OMIT only when pr-ref:none OR no findings at all OR all already [POSTED-TO-PR]
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
- **Post Draft PR review** — present whenever state file's `pr-ref:` is non-`none` AND at least one finding of any severity (including LOW / deferred / sub-threshold) remains unposted (no `[POSTED-TO-PR]` tag from prior run). LOW / deferred awareness findings count as postable — an all-LOW review still offers this option. On selection, drill into granularity sub-question (Step 2 below) before any `gh api` call. Posting is an external write to a public surface — the skill never posts without explicit approval; picking this option IS the approval.
- **Continue rounds (re-review)** — when round ≥3 fires Round-N escalation gate; otherwise loops back to Phase 1 increment round counter.
- **Skip — keep findings on disk** — terminal exit; user can resume later.

"Post" is omitted only when `pr-ref: none`, OR no findings exist at all, OR every finding already carries `[POSTED-TO-PR]` — findings of any severity (including LOW / deferred / sub-threshold) count as postable, so an all-LOW review still presents the option. The Action gate is mutually exclusive — user chooses ONE path.

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

Before any of the Post-drill steps below fire, re-read state.md and verify THREE invariants. If any fails, abort the Post drill — never post to GitHub with unresolved ambiguity, missing user picks, or refuted findings baked in.

**Invariant A — no review-gating `open_questions[]` left `unresolved`.** The §2.5 Pre-gate runs first in Phase 6 and should leave zero entries with `status: unresolved` AND `gates_review != false` by the time Action gate fires. (`gates_review: false` fix-path entries legitimately remain `unresolved` — they don't change what gets posted, so they never block the post; they ride the handoff to /geniro:implement.)

**Invariant B — every PRODUCT-DECISION finding has `step0_status: resolved` (or `wontfix`).** The §3 Step 0 per-finding gate runs after §2.5 and flips each PRODUCT-DECISION finding's `step0_status: pending` → `resolved` once the user's AUQ pick lands. A finding still at `pending` here means §3 never fired for it — and §7.5 would route it to `comments[]` by `File:` sentinel alone, with either AUQ chip label (`"Open question"` from §2.5 or `"Open decision"` from §3) potentially leaking into the comment body as if it were a tag.

**Invariant C — every kept finding (CRITICAL / HIGH / MEDIUM) has `Validation: confirmed` or `Validation: clarified`.** The Phase 4.2 per-finding verifier should filter `validation: refuted` findings before they reach the handoff. Any kept finding in `## Findings` carrying `Validation: refuted` indicates a producer-side filter failure; posting it to GitHub would surface a finding the verifier already judged incorrect. This guard re-checks at the external-effect boundary as defense-in-depth — refuted should never reach Post. Missing `Validation:` on a CRITICAL / HIGH / MEDIUM finding (legacy handoff per §2 back-compat) is NOT a violation: treat as `confirmed` and proceed with the one-line warning. The guard rejects `refuted` and field-mismatch (non-enum values), not absence.

This §7.0 check is the fail-closed second line of defense for ALL THREE invariants: if a producer wrote a new `open_questions[]` entry mid-phase, if `atomic_state_write` raced with a parallel resolver, if §3 was conflated with §2.5 / skipped under orchestrator drift, or if Phase 4.2's filter pass dropped a `refuted` entry from the filter list but left it in `## Findings`, the upstream gates' invariants might not hold. Verify defensively.

**Procedure:**

1. Read state.md frontmatter via `Bash: cat ... | head` and parse `open_questions[]`. Read the `## Findings` body section and parse each finding's `Severity:`, `Decision Type:`, `step0_status:`, AND `Validation:` fields.
2. Build three filter lists: (a) `open_questions[]` entries with `status: unresolved` AND `gates_review != false` (fix-path `gates_review: false` entries are excluded — they don't gate posting); (b) findings with `Decision Type: PRODUCT-DECISION` AND `step0_status: pending`; (c) findings with `Severity: CRITICAL | HIGH | MEDIUM` AND (`Validation: refuted` OR `Validation:` set to a non-enum value).
3. If any of the three lists is non-empty:
   - Surface a one-line chat warning naming the count of each non-empty list (e.g., `"Can't post yet: 2 open questions still need your answer + 1 finding needs a decision from you + 1 finding the verifier couldn't confirm."`) and the first 1-2 affected items.
   - Append a `## Errors` entry to state.md via `atomic_state_write` with `phase: action-gate`, `error: post-drill-aborted-on-unresolved-ambiguity`, the unresolved question IDs, the pending finding IDs, AND the refuted/invalid finding IDs.
   - Re-fire the §2.5 Pre-gate for any unresolved `open_questions[]` entries (if list (a) non-empty).
   - Re-fire the §3 Step 0 per-finding gate for any `step0_status: pending` PRODUCT-DECISION findings (if list (b) non-empty).
   - For list (c) refuted/invalid findings: do NOT auto-resolve. Refuted findings must be moved to `## Filtered` (with `reason: verifier-refuted`) by re-running Phase 4.2's filter pass — surface a chat instruction: `"Re-run /geniro:review to re-fire Phase 4.2 per-finding verification, OR manually move the refuted finding(s) to ## Filtered."` Then abort Phase 6 entirely (terminal state `aborted`, `## Termination reason: producer-schema-violation: refuted-finding-in-handoff`) — the user re-runs /geniro:review rather than racing a manual edit against a pending Post.
   - After resolution loops for lists (a) + (b) complete, loop back to step 1 of this section. Do NOT proceed to §7.1 until step 3 finds ALL THREE filtered lists empty.
4. When step 3 finds all three filtered lists empty, proceed to §7.1.

This guard exists because posting a draft PR review with unresolved ambiguity, missing user picks, or verifier-refuted findings buried in the body would push it onto the PR author or downstream reviewer — exactly the failure mode the `open_questions[]` array, `step0_status:` sentinel, and `Validation:` field are designed to prevent. The three invariants are independent (different arrays, different gates, different producer phases) so the guard must check all three; checking only one or two leaves the remaining path(s) uncovered.

### 7.1 Step 1.5 — Resolved-thread dedup (input-side filter)

The post-drill's eligible-finding set is every unposted finding across BOTH `## Findings` (kept CRITICAL / HIGH / MEDIUM) and `## Deferred — sub-threshold` (LOW awareness items) — once the user has chosen to post, severity no longer gates postability. Before showing eligible findings to the user, exclude findings whose `path:lines` overlaps an entry in the state file's `resolved-threads-snapshot:`. Overlap rule: finding `<P>:A-B` overlaps a snapshot entry `<Q>:L` when `P == Q` AND `A <= L <= B`. Path equality is required.

For each matching finding, append `[ALREADY-RESOLVED-ON-PR]` to its tag list and add `reason: already-resolved-on-pr` annotation when moving to `## Filtered`. The Step 2 granularity AUQ and Step 3 per-finding gate count only non-excluded findings.

When Step 1.5 empties the post set, fall back to Skip semantics — do not call `gh api` POST; surface `All eligible findings overlap already-resolved threads — nothing drafted on PR` once in chat.

### 7.2 Step 2 — Granularity gate

Chain a follow-up `AskUserQuestion` with header "Post mode":

- **Question:** "Send all unposted findings (including LOW / deferred awareness items) in a single batched review, or pick which ones to post?"
- **Options:**
- "Send all (Recommended)" — single batched review event minimizes per-finding AUQ calls and dodges secondary rate limits with a single POST.
- "Pick one-by-one" — chained `multiSelect` prompts; you choose which findings to include.

### 7.3 Step 3 — Per-finding gate

Fires only on "Pick one-by-one". Iterate over the eligible-findings list (filtered by Steps 1.5 + 3.5 when applicable). For each finding, fire ONE `AskUserQuestion` per canonical Single-finding gate shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md`. Calling-skill-set fixed menu: finding's own `Options:` is ignored; calling-skill menu is the three options below.

- **`header`:** `"Post finding?"`
- **`question`** (multi-line markdown, per Source-field map):
```
**<SEVERITY>** `path:lines` — <short title> — decision: <type>

**Why this matters:** <1-sentence impact from reviewer-agent's Why-this-matters: field>

Post this finding to the PR as an inline comment, or skip?
```
- **`options[]`** (three fixed options):
- "Post this finding" — adds finding to post set; iteration continues.
- "Skip this finding" — omits; iteration continues.
- "Stop posting (skip remaining)" — exit loop entirely; all unseen findings treated as Skip.
- **`preview`**: finding's full body block (Evidence / Suggested-fix / Confidence / Origin).

After loop completes (or user picked "Stop posting"), aggregated post set is the union of "Post" picks. If empty, treat as Skip and proceed without firing `gh api` POST.

### 7.4 Step 3.5 — TDD-mode post-set filter

When state-file `mode:` is `tdd`, filter the post set so findings with `Decision Type: TESTABLE` lacking a `[CONFIRMED-BY-TEST]` tag are excluded (remain visible in local report; not posted to PR).

**Retained for posting in TDD mode:**
- (a) any finding tagged `[CONFIRMED-BY-TEST]`, regardless of decision-type.
- (b) any finding with `Decision Type: PRODUCT-DECISION` or `INTENT-CHECK` (no executable behavior to gate on).
- (c) findings with `Decision Type: FIX-NOW` AND which match the "Runtime-behavior classification" rule's NON-runtime branch (typo-class — no runtime behavior to test against — per Phase 4.3).

When the filter empties the post set, fall back to Skip semantics; surface "TDD mode: no F→P-confirmed findings — nothing drafted on PR" once in chat. In Standard mode, this step is a no-op.

### 7.5 Step 4 — Post via the GitHub reviews API

Parse `<owner>/<repo>/<number>` from the state-file Summary's `pr-url`. Pass snapshotted `pr-head-sha` as `commit_id` — but see head-SHA freshness rule. ONE `gh api` call posts the entire review.

**Head-SHA freshness — re-fetch when authored tests were just pushed.** When Failing-tests gate fired BEFORE this step AND user picked "Commit + push", the local push advanced the PR's head past `pr-head-sha`. Re-fetch:

```bash
gh pr view <pr-ref> --json headRefOid --jq '.headRefOid'
```

Use the returned value as `commit_id`. Also overwrite state file's `pr-head-sha:` with the re-fetched value. Without this re-fetch, API rejects comments whose `path` is not present in `commit_id`'s tree with `Validation Failed: path could not be resolved`.

**Split the post set:**
- Findings with `File: <path>` → inline `comments[]` array.
- Findings with `File: PR-METADATA` → top-level review `body` under `## PR Metadata` section.
- Findings with `File: SPEC-COMPLIANCE` → top-level review `body` under `## Spec Compliance` section.

```bash
jq -nc \
--arg sha "<pr-head-sha-or-re-fetched-sha>" \
--arg body "<concatenated-body: summary header + ## PR Metadata + ## Spec Compliance sections>" \
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

GitHub PR comments are public, audience-expanding output. The comment body MUST contain ONLY: severity badge, finding's plain-language description, recommendation, and (for `[CONFIRMED-BY-TEST]` findings) the appended `**Failing test:** \`<test-path>\`` line.

**MUST NOT** add to the body or top-level review body:
- Plugin branding (`Geniro`, `/geniro:` prefix, "Generated by …" footers).
- Decision-type tags (`[FIX-NOW]`, `[TESTABLE]`, `[PRODUCT-DECISION]`, `[INTENT-CHECK]`).
- AUQ `header:` chip labels echoed as if they were tags (`[Open question]`, `[Open decision]`). These literals are reserved for the §2.5 Pre-gate and §3 Step 0 AUQs that gate downstream action; echoing them in a PR comment body re-projects unresolved ambiguity onto the PR author, which is the exact failure mode those gates exist to prevent. If a finding reads as an open question, it has not completed §3 — abort the post and re-fire the gate per §7.0, do not relabel it for the PR.
- Pipeline phase names (`Phase 4.3`, `judge pass`, `relevance filter`, `test-confirmation gate`).
- Confidence numerics (no `*Confidence: NN%*`).
- State-file paths or schema references.
- User-decision artifacts (`user picked X`, `approved by user`).
- Internal tags (`[CONFIRMED-BY-TEST]`, `[CHALLENGED-BY-TEST]`, `[POSTED-TO-PR]`, `[NEW]`, `[PRE-EXISTING]`, `[ALIGNS-WITH-PLAN]`, `TRUNCATED`).

The reviewer-agent's `description:` and `recommendation:` fields go into the body verbatim — if they legitimately mention any of these strings about the code under review, they stand as-is. The rule constrains orchestrator body-composition, not reviewer findings about the code.

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

Per
| User pick | Terminal state | `## Termination reason` body |
|---|---|---|
| /geniro:implement findings | `done` | (omitted) |
| Post Draft PR review (successful POST) | `done` | (omitted) |
| Post Draft PR review (POST failed) | `aborted` | `tool-unavailable: gh-api-post` |
| Continue rounds → Round-N → Abort | `aborted` | `repeated-failure: round-limit-3` |
| Continue rounds → Round-N → Escalate | `escalated` | (omitted; surfaced in `## Open Questions`) |
| Skip — keep findings on disk | `done` | `modifier-exit: skip-action` |

the SessionStart hook surfaces `## Termination reason` on resume so model and user see context, not bare "aborted".
