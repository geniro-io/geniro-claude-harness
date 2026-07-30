# /geniro:review Phase 6 — action-gate handoff

Detailed contract for `/geniro:review` Phase 6 (Action Gate Handoff). The `/geniro:review` SKILL.md retains a 2-3 line summary + a pointer here; cross-skill consumers (`/geniro:implement` handoff resolution, `_shared/` gate helpers, criteria files) read individual sections by § anchor.

State.md `phase: action-gate` during this phase.

**Handoff schema version: `m6-v3`** (the producer writes `geniro_schema_version:` into the handoff frontmatter at its Phase 5.1 write — `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-5-6-emit-handoff.md` §5.1). Consumers accept `m6-v1`, `m6-v2`, and `m6-v3`; per-version field-presence contract:

- `m6-v1` (legacy): no per-finding verification fields at any severity; bare deferred list.
- `m6-v2`: the four verification fields (`Validation` / `Recommended-action` / `Verification-confidence` / `Verification-evidence`) present on every kept finding (CRITICAL / HIGH / MEDIUM), emitted by the Phase 4.2 per-finding verifier; `Validation:` admits `unverified` (orchestrator-assigned when the verifier failed to spawn — see the presence rules below); bare deferred list.
- `m6-v3`: as `m6-v2`, plus `## Deferred — sub-threshold` entries carry the structured block schema (D-prefixed id, `File:`, `Why deferred:`, `Suggested fix:` — see §"Deferred-entry schema" below) and `## Findings` admits `[USER-ELECTED]`-tagged promotions from the §4.6 include-deferred gate.

Within `m6-v2`/`v3`, a producer that verified only HIGH findings emits verification fields on HIGH findings only; consumers treat absence on CRITICAL or MEDIUM the same as `m6-v1` absence — apply the "treat as confirmed + one-line warning" fallback.

## Contents

- §1 — Reporter behavior (no fix loop)
- §2 — Gate chain (firing order)
- §2.5 — Pre-gate: resolve open questions (Invariant A)
- §2.6 — Handoff file template (written in Phase 5.1), incl. the PR-state snapshot-field contract
- §3 — Step 0: open-decision per PRODUCT-DECISION finding (Invariant B initial flip)
- §3.5 — Finalize report (draft → final) before the handoff is offered
- §4 — Action gate (consolidated decision)
- §4.6 — Include-deferred gate (chained after the "/geniro:implement findings" pick)
- §5 — Round-N escalation
- §6 — Failing-tests gate
- §7 — Action == Post drill. **Conditional, and now a separate file** — `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff-post.md` carries §7.0 (fail-closed guard, four invariants) through §7.8 (post-posting overturn reconciliation). Reachable only when the Action gate's pick is "Post Draft PR review", never when `pr-ref: none`. Read that file on that pick; skip it otherwise.
- §8 — Empty-answer handling (universal)
- §9 — Terminal state mapping

---

## 1. Reporter behavior — no fix loop

/geniro:review does not apply fixes. The Phase 6 handoff message never includes "I'll fix these now" language. The fix path routes to /geniro:implement (manual, or via the Phase 6 handoff line).

**Skip the Phase 6 GATES only when the review produced nothing to decide** — ALL FOUR hold:

- Zero kept findings remain in `## Findings` after Phase 4.2 (at any severity, not only CRITICAL / HIGH / MEDIUM).
- Zero `Decision Type: PRODUCT-DECISION` findings — a Path-B LOW is still the user's call and still needs the §3 open-decision gate.
- `## Deferred — sub-threshold` is empty — otherwise the §4.6 include-deferred gate has entries to offer.
- `## Authored Tests` is empty — otherwise the §6 Failing-tests gate has a commit policy to settle.

**The §3.5 finalize step is outside that skip and runs on every pass.** It is a silent draft→final flip, not a gate, and the handoff written at Phase 5.1 carries `report_status: draft`. Skipping it strands a clean review at `draft` forever — which then trips /geniro:implement's draft warning and fails Invariant D in the §7.0 Pre-Post guard if the user ever posts that round's findings.

**The §4 Action gate is outside that skip too, and fires on every pass** — this is what §2's "fires once whenever this phase fires" means. A clean review still leaves one live decision (run another round, or exit and keep the report), and `/geniro:review`'s Definition of Done requires the Action pick in `approvals[]` unconditionally, so a skipped gate ends the phase with no recorded terminal choice for the §9 mapping to resolve. Its option set is unchanged — `Post Draft PR review` already omits itself on zero findings per §Post-option presence — but phrase the question around the clean result rather than a finding count, since "how should I proceed with the 0 findings" reads as a defect to the user. So a "skip" pass runs §3.5, then §4, then exits.

Severity alone does not decide the gate skip. An all-LOW review still carries decisions: the open-decision gate for a LOW product-decision, the Post option (which §4 keeps present for a finding of any severity), and the include-deferred gate that exists precisely for sub-threshold entries. Skipping on "no CRITICAL / HIGH / MEDIUM" exits before all three.

---

## 2. Gate chain — fire each as a separate AUQ

Phase 6 surfaces up to 4 sequential top-level gates. Each one decides a different thing and must be its own `AskUserQuestion` call — never collapse them into a single summary question, never paraphrase the question text, never merge options across gates.

**Firing order:**

1. **Pre-gate — Resolve Open Questions:** fires once when state.md frontmatter `open_questions[]` has any entry with `status: unresolved`. Chain one AUQ per such entry, fired in sequence (cap-extension per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Cap-extension — within a single entry only, never batching entries). Always-WAIT, and it completes before any other Phase 6 gate fires — these questions gate what /geniro:review posts. Full procedure: §2.5 below.
2. **Step 0 — Open-decision (per finding):** fires once per `Decision Type: PRODUCT-DECISION` finding kept by the Phase 3 §3.3 KEEP/FILTER judgment. Skipped when zero PRODUCT-DECISION findings remain.
3. **Action (Always-WAIT):** fires once whenever this phase fires — the consolidated top-level decision. User picks ONE next step: /geniro:implement / Post Draft PR / Continue rounds / Skip. Two picks drill into sub-gates of their own path, not extra top-level gates: "Post Draft PR review" drills into the §7 Post drill, and "/geniro:implement findings" drills into the §4.6 include-deferred gate when `## Deferred — sub-threshold` is non-empty.
4. **Failing tests:** fires once per gate-chain pass when the state file's `## Authored Tests` section is non-empty — picks the commit policy for AI-authored tests; a later chat-text commit/push request re-fires it (§6). Firing order relative to Action gate conditional:
- **Action == Post AND `## Authored Tests` non-empty:** Failing-tests fires BEFORE the Post drill (GitHub reviews API rejects comments whose `path` is absent from `commit_id`'s tree).
- **Action != Post OR `## Authored Tests` empty:** Failing-tests fires AFTER Action gate's path completes.

Sequential: do not fire gate N+1 until gate N's answer is collected.

---

## 2.5. Pre-gate — Resolve Open Questions

This gate runs FIRST in Phase 6 — before Step 0, Action, and Failing-tests gates — whenever state.md frontmatter `open_questions[]` carries any entry with `status: unresolved`.

**Why it runs first.** An open question here is one whose answer changes what the Action gate is choosing between (e.g., "API seeder additions in-scope or split into a separate PR?" — the answer changes which findings get posted). Letting Action gate fire first means the user picks "/geniro:implement findings" without realizing those questions still gate the implementation.

**What this gate does NOT ask.** /geniro:review records an open question ONLY when it cannot determine the answer itself and the answer changes what it posts — a genuine scope or judgment call. Fix-detail questions and self-verifiable claims are excluded at record time by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md` §4, so neither ever reaches this gate.

**Procedure:**

1. Read frontmatter `open_questions[]`. Filter to entries with `status: unresolved`.

2. For each unresolved entry, fire one `AskUserQuestion` call. Every tier renders message-first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering. When the unresolved queue holds ≥2 entries, each render opens with the decision-queue tracker (`✔ Decision 1 — <short tag> · ● Decision 2 of N — <short tag> · ○ …`) — the denominator is the count of unresolved `open_questions[]` entries, already persisted; the tracker is presentation-only per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Visual rendering language. The renderer picks one of three tiers in order — the **first tier whose required source data is available** wins:

   **Tier 1 — Producer-authored rich entry (preferred).** When the entry carries `context` / `evidence` / `options` / `recommendation` fields per the extended schema in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2 `open_questions`:
   - `header`: `"Open question"` (literal — never paraphrase)
   - **chat block + `question`**: render per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Single-finding gate (§ Message-first rendering), sourcing fields from the entry:
     - chat block — instantiate the § Message-first rendering template from the entry's fields: the `### 🧭 Decision needed:` title and `**In one sentence:**` opener from the entry's `question`; the conversational lead from `context` in plain English (expand any reviewer shorthand); `**Why it matters:**` with `evidence[0].file:lines` as its parenthetical cite; a visual per § Finding-type visual map. When `related_findings[]` is non-empty, name the highest-severity related finding's severity and the source dimension (entry's `source`, e.g. `spec-compliance`, `bugs`) inside the lead
     - lean `question` — the plain-English title (first sentence of the entry's `question`) + `evidence[0].file:lines` if present, then a pointer to the chat block
   - `options[]` — one per `options[]` entry in the question:
     - `label` — option's `label`
     - `description` — option's `description`
     - `preview` — empty or a one-line recap (per per-finding-question.md); the `context` / `evidence[]` body lives in the chat block. When `recommendation.option_id == this.id`, position that option first, suffix its `label` with ` (Recommended)`, and state the producer's rationale in the chat block
   - When `recommendation.option_id` is set, position THAT option first in the `options[]` array and suffix its `label` with ` (Recommended)`.

   **Tier 2 — Cross-reference into `## Findings` body.** When the entry has `related_findings: [F1, F2, ...]` non-empty but lacks the Tier 1 rich fields, read those finding blocks from the same handoff file's `## Findings` body (per the multi-line "Per-finding body schema" defined later in this same reference file, after the Wontfix-path note below). Apply `per-finding-question.md` § Single-finding gate rendering directly against the first related finding's body — the finding's Evidence / Why-matters / Suggested-fix / Confidence / Origin fields map onto the chat-render slots per that spec's § Source-field map. When >1 related findings exist, prefer the highest-severity finding; mention the others as `"Also gates: F2, F3"` in the question body.

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

5. Each entry gets its own `AskUserQuestion` call, fired in sequence with a message-first render before each (per step 2); cap-extension per § Cap-extension applies within a single entry only, never batching entries into one call.

6. After the last entry resolves, every `open_questions[]` entry is in `{resolved, wontfix}` before proceeding to Step 0 / Action / Failing-tests. Verify by re-reading the frontmatter; if any `unresolved` remains, loop back to step 2.

---

## 2.6 Handoff file template (written in Phase 5.1)

Phase 5.1 writes the handoff at `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` via `atomic_state_write` — never a direct Edit/Write (the `enforce-state-helper` hook hard-blocks direct writes to the canonical state path). `<PRIMARY_ROOT>` resolves per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A.

The canonical handoff is a one-shot producer→consumer artifact; /geniro:review extends it with `phase:` / `status:` / `round:` / `approvals[]` so a compaction mid-run can recover. The file behaves as a handoff AT REST (after Phase 5 persist) and as a working state file DURING THE RUN.

The heredoc below is quoted (`<<'EOF'`) so the `${CLAUDE_PLUGIN_ROOT}` and `$(…)` tokens inside placeholder descriptions stay literal. Substitute every `<…>` placeholder with a real value before the write — and for time-bearing fields (`timestamp:`, every `completed-at:`) substitute a live clock read computed as `date -u +%Y-%m-%dT%H:%M:%SZ` in the same Bash call, never a model-supplied or rounded value (a quoted heredoc will NOT interpolate `$(date …)`, so it must be substituted, not pasted as the literal command; `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` §Timestamp sourcing).

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
geniro_schema_version: m6-v3
task_slug: review-<branch>
phase: <triage|mechanical-prepass|llm-spawn|filter|stratify|persist|action-gate|done|aborted|escalated>
status: <in-progress|done|failed>
report_status: <draft|final>          # whole-report lifecycle — see state-tier-spec.md /geniro:review producer fields (missing reads as final)
deep-mode: <true|false>               # --deep fan-out (angle-diverse passes + gated verify); missing reads as false
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
resolved-threads-snapshot: [<path:line entries|null>]        # read by §7.1 dedup check 1
pr-bot-comments-snapshot: [<path:line entries|null>]         # read by §7.1 dedup check 2
pr-formal-reviews-snapshot: [<reviewer:body entries|null>]   # read by §7.1 dedup check 3
prior-round-summary: <text|null>                       # written/read across re-run rounds (§7)
spawn_dims_declared: [<dim-slug>, ...]   # producer-run: the dimension set declared before the Phase 2 batch fired
spawn_dims_count: <int>                  # producer-run: length of spawn_dims_declared
custom_reviewers: []                     # producer-run: discovered custom review dimensions (short spawn-spec scalars, never criteria bodies)
mechanical_prepass_attempted:            # producer-run: one entry per pre-pass check, value in {findings, clean, error}
  lint: <findings|clean|error>
  schema: <findings|clean|error>
  secret: <findings|clean|error>
approvals: []
non-resumable-actions: []
open_questions:                       # always present; may be empty []
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
- Scope: <N files reviewed of <T> changed in the PR>; when N < T (commonly a stacked PR) also "<M> files excluded — owned by ancestor PR #<n> (<K> review threads, <U> unresolved); reviewed there, not missed" (omit the clause when the review covered the whole PR). Naming the ancestor and its thread counts is what distinguishes a deliberately narrowed scope from a review that silently skipped files
- Round: <N>
- Risk-tier: <standard|high>
- Dimensions spawned: [<the `actual` set per §"Dimensions spawned — `declared` vs `actual`" below, naming any declared-but-missing dimension with its skip reason>]
- Mechanical pre-pass: [lint:N, schema:M, secrets:K]
- Finding totals: CRITICAL=<X>, HIGH=<Y>, MEDIUM=<Z>
- Disposition: <K> kept · <P> posted · <W> withheld (<reasons — e.g. already-on-PR, kept-off-PR, unverified; omit zero-count reasons>) · <D> deferred · <R> repeated unchanged from round <N-1> (omit the clause when <R> is zero; a repeat stays in `## Findings` like any other kept finding — see the per-finding body schema below)

## Findings

### CRITICAL
<list>

### HIGH
<list>

### MEDIUM
<list>

## Deferred — sub-threshold
<!-- One block per set-aside finding, per the §"Deferred-entry schema" below the template. Read by the §7 post drill and the §4.6 include-deferred gate. -->
<deferred-entry blocks, or empty>

## Filtered
<!-- Findings demoted out of ## Findings, each with a `reason:` (non-exhaustive — e.g. verifier-refuted, not-actionable, no-action-needed, user-kept-off-pr, test-challenged, already-resolved-on-pr, overturned-after-post, convention-filtered). Kept visible with original severity + reason so the user can re-elevate; never propagated to ## Findings, open_questions[], or the Post drill. -->
<list, or empty>

## Authored Tests
<!-- Populated only when the test-confirmation gate authored tests; lists each AI-authored test file by path. Empty otherwise. The Failing-tests gate fires when this section is non-empty. -->
<list of test file paths, or empty>

## Caveats
<!-- One line per fail-open or coverage gap the run hit — a failed PR/tracker fetch, a thin mechanical pre-pass, a dropped custom reviewer, a finding left `Validation: unverified`, a test that flipped green on re-run. The section is where every fail-open path in the producer lands, so it is part of the skeleton even on a clean run. -->
<list, or empty>

## Accepted Gaps
<!-- Written only when the user answered "Skip the missing reviewers and continue" at the producer's post-spawn completeness gate; names each declared dimension that never returned. Empty otherwise. -->
<list, or empty>

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
<rendered per §9 — only on the aborted terminal; escalated surfaces its reason in ## Open Questions>

## Persisted approvals
<rendered from approvals[] frontmatter for user-readability>
EOF
```

Each finding under `## Findings` renders as the multi-line per-finding body block below (NOT a one-liner) — the Phase 3 §3.3 KEEP/FILTER judgment preserves every reviewer-agent field; dropping fields to reach a one-liner is the failure mode the schema prevents.

**Write/rewrite discipline — schema comes from the template, never from memory.** Any full handoff write (Phase 5.1 first write) or rewrite (a later round updating the file, a re-author after compaction, any whole-file replacement) follows this procedure — re-authoring the handoff from memory drops the identity frontmatter, renames fields (`pr-head-sha` → `pr-head-oid`, breaking the §7.4 freshness check that then reads null), collapses the per-finding verification fields into a prose line (downstream parses it as legacy `m6-v1`), and drops snapshot fields the same run's Post drill needs:

1. **Before writing, re-read the source schema.** Re-read the §2.6 template above (or, for a rewrite, the prior handoff being updated) and take the field set from there — the frontmatter keys, the per-finding verification fields (present since `m6-v2`), and the `## ` section list. Do not reconstruct any of them from memory.
2. **Write via `atomic_state_write`** with the full frontmatter + body skeleton, every finding rendered as the multi-line per-finding body block (not a prose collapse). Because the frontmatter is re-authored from the template, every full write — first write or rewrite — lands `report_status: draft`; the §3.5 finalize step re-runs afterwards, so a rewrite can never leave a stale `final` behind.
3. **After writing, self-check (grep) presence.** Grep the written file for the identity frontmatter keys (`tier:`, `producer:`, `schema-version:`, `geniro_kind:`, `geniro_schema_version:`, `task_slug:`), the producer-run declaration keys the verification gates read back (`spawn_dims_declared:`, `spawn_dims_count:`, `mechanical_prepass_attempted:`), AND the mandatory per-finding verification field labels on each kept finding (`Validation:`, `Recommended-action:`, `Verification-confidence:`, `Verification-evidence:`) — exempting LOW findings (including `[USER-ELECTED]` promoted LOWs, which carry none per the presence rules). Any missing key means the write dropped schema — re-author from the template, do not patch by memory.
4. **On a rewrite, preserve every prior frontmatter field.** A field present in the prior version is preserved unless an explicit contract drops it (e.g. a documented schema migration). Fields are dropped by contract, never by omission. Before overwriting, capture the prior frontmatter key set (grep the file's keys); after writing, diff against it — a key that vanished without a contract is a regression. The snapshot fields (`resolved-threads-snapshot:`, `pr-bot-comments-snapshot:`, `pr-formal-reviews-snapshot:`) are the easiest to lose on a rewrite and are exactly what the §7.1 Post-drill dedup reads.

**Definition of Done (write/rewrite):** the written handoff carries every identity frontmatter key and every mandatory per-finding verification field from the §2.6 template, and a rewrite preserved every frontmatter field the prior version carried (verifiable by the before/after key diff in steps 3-4).

---

**PR-state snapshot fields — the dedup contract.** The three `*-snapshot:` fields above capture the PR's pre-existing review surface at triage time, and the §7.1 already-on-PR dedup is their only consumer. Their shapes differ because their sources do:

- `resolved-threads-snapshot:` — `path:line` entries, one per PR review thread already marked resolved. Carries a line, so §7.1 check 1 matches by range overlap.
- `pr-bot-comments-snapshot:` — `path:line` entries, one per still-open bot review comment. Also carries a line, so check 2 applies the same range-overlap rule.
- `pr-formal-reviews-snapshot:` — `reviewer:body` entries, one per human or author formal review. Free prose with NO line, which is why check 3 falls back to the conservative basename-plus-keyword match instead of a range rule.

Each field is `null` when the producer had nothing to capture (no PR ref, or `gh` unavailable at triage). A `null` or absent snapshot means "nothing to dedup against" — the dependent check is skipped, never treated as "no overlap found". A rewrite that drops these fields silently re-enables double-posting, which is why the §2.6 rewrite discipline names them explicitly.

**Dimensions spawned — `declared` vs `actual`.** Two dimension sets exist during a review run, and the Summary line records the second:

- **`declared`** — the dimension set the producer committed to BEFORE firing the parallel reviewer batch, persisted to frontmatter as `spawn_dims_declared` (with `spawn_dims_count` as its length). It is the intent.
- **`actual`** — the dimensions that came back with a recorded structured reviewer result. It is the outcome.

`Dimensions spawned:` carries `actual`, never `declared`, and names each dimension in `declared − actual` with its skip reason. Sourcing the line from the producer's dimension grid (the table that says which dimensions *should* fire for this run) reports intent as outcome — the exact drift the producer's post-spawn declared-vs-actual gate exists to catch, re-introduced one layer down in the artifact a downstream consumer reads.

---

**Per-finding body schema (referenced by §2.5 Tier 2 + §3).** Each finding renders as a sub-section block so consumers can build rich AUQs per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Single-finding gate without re-deriving Evidence / Why-matters / Suggested-fix from outside the handoff. Every finding — including an unchanged repeat from a prior round — lives under the handoff's `## Findings` body:

```markdown
- [ ] F1 — [NEW|PRE-EXISTING] [optional: CONFIRMED-BY-TEST|CHALLENGED-BY-TEST|POSTED-TO-PR|ALREADY-RESOLVED-ON-PR|ALREADY-RAISED-ON-PR|USER-ELECTED] **<short title>** · <SEVERITY> [optional: · seen since round <N>]
  - **Severity:** CRITICAL | HIGH | MEDIUM | LOW
  - **File:** path/to/file.ts:42-48
  - **Decision Type:** FIX-NOW | TESTABLE | PRODUCT-DECISION | INTENT-CHECK
  - **Confidence:** NN%
  - **Origin:** llm:<dim> | mechanical:<check>       [which producer found it — NOT the reviewer-agent's own `Origin:` field, whose value set is different; see the mapping note below]
  - **Why this matters:** <1-sentence impact, verbatim from reviewer-agent output>
  - **Suggested fix:** <concrete improvement text, verbatim — synthesis form for PRODUCT-DECISION>
  - **Evidence:**
    ```<lang>
    <2-5 lines from reviewer-agent Evidence: codeblock>
    ```
    OR (command-based form): `Command:` / `Exit code:` / `Tail (last 3 lines):`
  - **Validation:** `confirmed | refuted | clarified | unverified` [every kept finding — CRITICAL / HIGH / MEDIUM; emitted by Phase 4.2 per-finding verifier, except `unverified`, which only the orchestrator assigns when the verifier failed to spawn (finding-verification.md §4.5); ABSENT on LOW (which never enters Phase 4.2)]
  - **Recommended-action:** `fix-now | testable | product-decision | intent-check | drop` [every kept finding — verifier override; when `Validation: clarified`, this field supersedes the original `Decision Type:` for downstream routing]
  - **Verification-confidence:** `1 | 2 | 3 | 4 | 5` [every kept finding — coarse 1-5 scale, distinct from the LLM `Confidence: NN%` field above]
  - **Verification-evidence:** `"<literal quote from cited file:line or caller chain>"` [every kept finding — verifier's grounding citation, distinct from the reviewer's `Evidence:` codeblock above]
  - **Options:** [PRODUCT-DECISION only — omit for other types]
    - `<option-id>`: `<short label>` — `<one-line trade-off>`
  - **Recommendation:** <option-id> — <one-sentence rationale> [PRODUCT-DECISION only]
  - **step0_status:** `pending | resolved | wontfix` [PRODUCT-DECISION only — omit for other types]
```

**`Origin:` — producer→handoff mapping.** The name carries a different value set on each side of the write, so map it explicitly rather than copying it through. `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output Format emits `Origin: [NEW] | [PRE-EXISTING]` — *newness*, whether the defect sits in changed or unchanged code — and that value lands in this block's **title-line tag** (`[NEW]` / `[PRE-EXISTING]`), never in the `Origin:` sub-field. The `Origin:` sub-field above carries *provenance*: `llm:<dim>` for the reviewer dimension that reported it, `mechanical:<check>` for a Phase 1.5 pre-pass check, which the reviewer output does not state (the orchestrator knows it from which spawn returned the finding). A writer that copies the agent's `Origin:` straight into the sub-field produces `Origin: [NEW]`, which no consumer can resolve to a dimension.

**The `- [ ]` checkbox is the addressed-tracker (presentation-only).** Every finding is written unchecked (`- [ ]`); the engineer ticks it (`- [x]`) by hand as they resolve that finding. No gate, consumer, or guard reads its checked state — they parse the `- **<Field>:**` sub-fields and the frontmatter — and it is never carried into a posted PR comment (the §7.5 pre-POST scrub composes comment bodies fresh). The `· <SEVERITY>` suffix on the title line mirrors the `Severity:` sub-field for at-a-glance scanning; the sub-field stays the canonical value the §3 / §7.0 gates read. The title line leads with the plain-text finding id (`F<n> — …`) and bolds only the short title — some markdown previews break a bold-led checkbox item with nested detail lines, so plain-text-lead keeps the checkbox inline. A handoff written before this rendering existed shows the finding header as `### F<n> — <title>` — same block, same fields; consumers parse by the `- **<Field>:**` labels and the frontmatter, never by the header shape.

The `step0_status:` field is the runtime sentinel that §3 (Step 0 per-finding gate) flips from `pending` → `resolved` after the user's AUQ pick lands. Phase 5.1 writes every PRODUCT-DECISION finding with `step0_status: pending`; §3 step 4 flips it to `resolved`. §7.0 re-reads `## Findings` and aborts the Post drill on any remaining `pending` — the defensive analog of the `open_questions[].status: unresolved` check, since the AUQ chip labels (`"Open question"` for §2.5, `"Open decision"` for §3) are not tags and must never leak into a PR comment as if they were.

**Verification fields — presence rules.** The four `Validation` / `Recommended-action` / `Verification-confidence` / `Verification-evidence` fields are MANDATORY on every kept finding (CRITICAL / HIGH / MEDIUM) that lands in `## Findings`. Phase 4.2 produces one `finding-verifier-agent` verdict per §4.1 survivor regardless of severity (co-located survivors share a spawn per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §4); verdicts of `validation: refuted` are filtered before reaching the handoff, so any finding present here carries `Validation: confirmed`, `Validation: clarified`, or — when the verifier failed to spawn after retry — the orchestrator-assigned `Validation: unverified` (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §4.5). `unverified` is a legal present value meaning the verifier never ran: consumers keep the finding, treat it as NOT postable (excluded from the §7.1 post set), and surface a one-line warning that it was not independently verified. The fields are ABSENT on LOW findings — including a LOW `PRODUCT-DECISION` admitted via §4.1 Path B (decision-type) — because no LOW finding enters the Phase 4.2 verifier (§4.2 runs on every kept CRITICAL / HIGH / MEDIUM finding, admitted by Path A or Path B; LOW is the only severity it skips). A Path-B LOW `PRODUCT-DECISION` still carries `step0_status: pending` (it IS a PRODUCT-DECISION, so the §3 open-decision gate fires for it) but no `Validation`/verification fields. When `Validation: clarified`, the verifier judged the original reviewer's finding partially correct but mis-classified; the `Recommended-action:` value carries the corrected routing and supersedes the original `Decision Type:` for §3 gate firing and downstream consumer decisions. A `[USER-ELECTED]` promotion out of `## Deferred — sub-threshold` (§4.6) follows the same rules: a promoted LOW carries no verification fields; a promoted evidence-less MEDIUM carries all four fields on the finding-verification.md §4.5 spawn-failure convention — `Validation: unverified`, `Verification-confidence: 1`, `Verification-evidence: "user-elected promotion — verifier never ran"`, `Recommended-action:` mirroring its original Decision Type — because the verifier never ran for a deferred entry and user election does not verify it; an accounted state excluded from the §7.1 post set like any other `unverified` finding.

**Verification fields — back-compat for legacy handoffs.** Two legacy cases produce findings without the four verification fields:
1. `m6-v1` (pre-Phase-4.2) writers — no findings carry verification fields at any severity.
2. `m6-v2` writers that verified only HIGH findings — HIGH findings carry verification fields; CRITICAL and MEDIUM findings do not.

Consumers (§7.0 fail-closed guard, /geniro:implement Phase 1 handoff-resolution step) treat a missing `Validation:` on any CRITICAL/HIGH/MEDIUM finding as `Validation: confirmed` and surface a one-line chat warning so the user knows Phase 4.2 verification was not actively run for that finding. This mirrors the existing `step0_status: missing → resolved` back-compat behavior documented above — the safety improvement post-dates these handoffs, so a missing field does not block the Post drill that worked before the field existed.

**Backward-compatible parsing.** Consumers (Phase 6 §2.5 Tier 2 lookup, §3 per-finding gate, /geniro:implement Step 12) accept BOTH the rich multi-line block above AND the legacy one-liner shape `- [NEW|PRE-EXISTING] path:lines — <description> — decision: ... — recommendation: ... — confidence: NN% — origin: ...` produced by older /geniro:review runs. Legacy one-liners fall back to the terse rendering (§2.5 Tier 3 / per-finding-question.md degraded mode); rich blocks unlock the full Single-finding gate shape. **Legacy handoffs predate the `step0_status:` sentinel** — when §7.0 parses a legacy one-liner with `Decision Type: PRODUCT-DECISION` (or its lowercase one-liner form `decision: PRODUCT-DECISION`) and no `step0_status:` sub-field, treat it as `step0_status: resolved` and surface a one-line chat warning so the user knows Invariant B was not actively re-verified for that finding. Never treat a missing field as `pending` — that would false-positive on every legacy handoff and block the Post drill that worked before the field existed.

**Deferred-entry schema (referenced by §4.6 + §7.1).** Each entry under `## Deferred — sub-threshold` renders as a compact block mirroring the kept-finding checkbox shape — D-prefixed ids (`D1`, `D2`, …), plain-text lead, bolded short title (same markdown-preview rationale as the kept-finding title line above):

```markdown
- [ ] D1 — **<short title>** · <SEVERITY>
  - **Severity:** LOW | MEDIUM | HIGH | CRITICAL       [LOW: below the severity threshold; MEDIUM/HIGH/CRITICAL: `severity >= MEDIUM` that failed all four §4.1 admission signals]
  - **File:** path/to/file.ts:42-48
  - **Why deferred:** below the fix threshold | MEDIUM without Evidence Block
  - **Suggested fix:** <1-2 lines, verbatim from the reviewer output>
  - **Decision Type:** FIX-NOW | TESTABLE | INTENT-CHECK   [optional — never PRODUCT-DECISION, which §4.1 Path B keeps out of this section]
```

The schema exists because two consumers parse these entries: the §7 post drill anchors each posted deferred entry's comment by its `File:` path:line (§7.4) and matches POST responses back by (path, line) (§7.6), and the §4.6 include-deferred gate promotes entries into `## Findings` re-rendered as full per-finding blocks — a bare prose list supports neither. **Legacy bare-list entries** (no `File:` sub-field, written by m6-v1/v2 producers) stay awareness-only: the §4.6 include-deferred gate skips them with a one-line notice, and the post drill falls back to listing them in the top-level review body under the `## Findings on unchanged lines` shape when no path:line can be parsed.

**Wontfix path.** If the user picks "Other" with explicit text like "ignore" / "skip" / "not now", set `status: wontfix` and `resolution.picked` to the user's text. Wontfix entries do NOT block downstream gates — they're recorded but de-prioritized. Downstream consumers treat `wontfix` as "user acknowledged and chose to defer".

**No skipping.** The pre-gate cannot be deferred to /geniro:implement or to the Post drill. Resolving here makes the Action gate's options meaningful (e.g., "/geniro:implement findings" now points to a known-scope target). Resolving downstream creates the failure mode this gate exists to prevent.

---

## 3. Step 0 — Open-decision gate (per-finding, Always-WAIT)

Before recommending which skill to run, surface every `Decision Type: PRODUCT-DECISION` finding kept by the Phase 3 §3.3 KEEP/FILTER judgment to the user — they pick the resolution path, and the orchestrator does not resolve a multi-path finding on their behalf even when the reviewer's `recommendation:` field looks obvious.

**For each kept finding with `Decision Type: PRODUCT-DECISION` (read from state file):**

Read the `## Findings` body section, scanning each finding's `Decision Type:` and `step0_status:` fields — every kept finding, including an unchanged repeat from a prior round, lives there.

1. Read the finding's `Options:` sub-list AND body sub-fields (`evidence:`, `why-matters:`, `suggested-fix:`). For CRITICAL / HIGH / MEDIUM findings, check the `Validation:` field before firing the AUQ — four cases. `confirmed` or `clarified` → proceed. `Validation: refuted` should already be filtered upstream at Phase 4.2 — if encountered here, it indicates a producer-side schema violation; emit an entry to state.md's `## Errors` body section (`phase: action-gate`, `error: refuted-finding-reached-step-0-gate`, finding ID) and skip the AUQ for that finding. `Validation: unverified` (the verifier never ran — spawn failed after retry, per finding-verification.md §4.5) → proceed with the AUQ but surface a one-line warning that the finding was not independently verified; the decision is the user's either way, so the missing verification is disclosed, not blocking. A missing `Validation:` (legacy handoff per §2 back-compat) is treated as `confirmed` — proceed with the AUQ but surface the one-line warning.
2. **Render the finding to chat first.** Before any `AskUserQuestion` fires, render the finding to chat as a self-contained block instantiating the § Message-first rendering template at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Single-finding gate. The render must be a SEPARATE, already-emitted assistant message that exists BEFORE the AUQ fires — same-turn text does not satisfy the contract; honor the render-exists check ("Scrub before the AUQ fires") in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Single-finding gate. The decision queue for its tracker is the kept PRODUCT-DECISION finding set (tracker only when ≥2 remain). Expand any reviewer shorthand so the question stands on its own. Build the chat block from the finding's `options:` sub-list and body sub-fields (`evidence:`, `why-matters:`, `suggested-fix:`) per the spec's § Source-field map. The option set also carries the "Explain further" reading aid per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Explain-further option (writes no decision, consumes no round cap; surfaces via the § Cap-extension chained call when decision options fill 4 slots). It also carries a **"Challenge this finding"** option per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Challenge-finding option: picking it spawns one fresh `finding-verifier-agent` (the Phase 4.2 verifier mechanism — spawn via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`, OMIT `model=`) primed with the user's stated objection, then re-renders the finding with the returned `confirmed` / `refuted` verdict + fresh evidence and re-fires this gate. A `refuted` verdict demotes the finding to `## Filtered` (written via `atomic_state_write`) and drops its gate; a `confirmed` verdict re-presents the same options. The challenge writes no resolution and never flips `step0_status` — only a resolution path does (step 4).

   **Then fire the lean `AskUserQuestion`.** Set `header: "Open decision"`. Build the lean `question` + option `label`+`description` from the same finding fields per the spec's § Source-field map. Leave each option's `preview` empty or a one-line recap (per per-finding-question.md) — never the finding body.
3. **Append the "Keep off the PR" disposition to the AUQ options — mandatory, every PRODUCT-DECISION AUQ.** Beyond the finding's own `options:` bullets, add ONE standard option: `label: "Keep off the PR — I'll handle this"`, `description: "Record the decision for you; do not include this finding in anything posted to the PR."` Why it is its own step: the keep-on-PR / keep-off-PR call belongs to the user — it is the audience control for a residue the PR author cannot action (a governance / legal / data-classification / business-intent question). Omitting the option does not drop the decision; it silently transfers it to the orchestrator at payload time (§7.1), which is the exact failure this step prevents. The option occupies one AUQ slot, so when the finding's own `options:` already lists 4, chain a follow-up per the cap-extension rule (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Cap-extension) — never drop or merge an existing option to make room.
   - **Definition of Done (this step):** every PRODUCT-DECISION finding's AUQ chain carries the literal `"Keep off the PR — I'll handle this"` label in one of its calls' `options[]`. Verify per finding, not per call — a finding whose options overflow 4 slots fires two or more chained calls, so the call count exceeds the finding count by design.
4. Update the finding line in the state file via `atomic_state_write`: replace `recommendation:` field with user's chosen option text AND set `step0_status: resolved` (or `step0_status: wontfix` when the user picks "Other" with skip/defer text). Preserve `options:`, `evidence:`, `why-matters:`, `suggested-fix:`. The state file is the handoff to the next skill, so the chosen path AND the body travel with the finding. The `step0_status` flip is the sentinel §7.0 re-reads to verify this gate actually fired — without it, a §3-skipped finding ships to PR as if the AUQ header `"Open decision"` were a tag. When the user picks the **Keep off the PR** disposition, set `step0_status: resolved`, write `recommendation: keep-off-pr`, AND add `post-disposition: off-pr` to the finding line — §7.1 reads `post-disposition: off-pr` and drops the finding from the post set, so a residue you chose to handle yourself never reaches the PR author. When the user's pick instead resolves the finding with **no change to the code** (accept-as-is / keep the current behavior / confirms the existing code is fine), the finding needs no action: set `step0_status: resolved`, write the chosen text into `recommendation:`, AND add `post-disposition: no-action` to the finding line. §7.1 reads it and drops the finding from the post set — a decision that ends in "leave it as it is" is nothing the PR author can act on, so it belongs in the report, not as a PR comment.

Fire one `AskUserQuestion` call per PRODUCT-DECISION finding, in sequence — render the finding, ask, collect the answer, then move to the next. Many findings means many sequential calls, never several findings batched into one call's `questions[]` array (the tabbed multi-question prompt the user submits all at once; the `gate-render` hook hard-blocks it). Cap-extension per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Cap-extension applies when ONE finding's option set overflows 4 slots (its own `Options:` plus the appended "Keep off the PR", "Explain further", and "Challenge this finding" options) — chain follow-up calls for that single finding, never batch multiple findings.

Always-WAIT. If empty answer returns, fall back to plain text and re-ask — never default to the reviewer's synthesis.

Skip entirely when zero PRODUCT-DECISION findings remain after the Phase 3 §3.3 KEEP/FILTER judgment.

---

## 3.5 Finalize the report (draft → final)

The handoff written in Phase 5.1 carries `report_status: draft`. After §2.5 (Pre-gate) and §3 (open-decision gate) clear, and BEFORE the §4 Action gate offers the handoff, flip it to `final`:

1. Re-verify every `open_questions[]` entry is `{resolved, wontfix}` and every PRODUCT-DECISION finding is `step0_status: {resolved, wontfix}` — the same invariants §7.0 re-reads. Scan PRODUCT-DECISION findings in the `## Findings` body section — every kept finding, including an unchanged repeat from a prior round, lives there. If any entry/finding is still `unresolved` / `pending`, loop back to the owning gate; do NOT finalize.
2. Set frontmatter `report_status: final` via `atomic_state_write`.

This is a re-verify-plus-one-field-flip, NOT a re-bake — the per-finding decisions already persisted in §3 step 4. The field exists so the §4 Action gate's handoff option and the §7.0 public-post guard can assert the report is no longer provisional: a report still at `draft` means a decision gate did not clear, and the handoff would route an un-finalized report. Keep this step — stripping it silently re-opens the handoff-offered-before-decisions-land failure mode.

No AUQ fires here — finalize is silent. The user already answered the decision gates; a separate "finalize?" confirmation would be friction without new information.

---

## 4. Action gate (Always-WAIT)

**Precondition — `report_status: final`.** The §3.5 finalize step runs immediately before this gate. If the report is still `draft`, a decision gate did not clear — loop back to §3.5 (which re-verifies and re-fires the owning gate); do NOT offer the handoff against a provisional report.

**Render the wrap-up to chat first.** Before the AUQ fires, render a wrap-up chat message in the visual language of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Visual rendering language; the two-step rules (separate already-emitted message) apply per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering, and the render-exists check per the same contract's § Single-finding gate, "Scrub before the AUQ fires". The render carries:

- **All-decided tracker line** — only when open decisions were resolved this run (§2.5 entries and/or §3 findings): `✔ Decision 1 — <short tag> · ✔ Decision 2 — <short tag>` — every stop `✔`, because this gate fires only after those gates cleared.
- `**In one sentence:**` what this gate decides — what to do with the <N> confirmed findings.
- **Kept-findings digest** — a mini-table, one row per non-zero severity: severity · count · example finding tag (a 2-4 word plain-English tag).
- **Set-aside count** — when `## Deferred — sub-threshold` holds any entry: one line naming how many more were set aside below the fix bar. The digest above counts only what cleared §4.1, so without this line the kept set reads as the whole finding set, and a heavily filtered review is indistinguishable from a quiet one.
- **All-cosmetic line** — when every kept finding is LOW and none is disqualified by the `**Excludes:**` list in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1: state affirmatively, in one line, that nothing found blocks. Say it rather than leaving it to be inferred from a short table — silence reads as "the review did not look", and the affirmative sentence is the only thing that distinguishes a clean result from an absent one. Omit the line when a disqualifier applies; that list is the single source for what disqualifies, never restated here.
- **Volume line** — when the kept plus set-aside count exceeds the number of changed files: one line saying so as a fact about the change, not about the findings. A finding list longer than the file list is a signal that the change is carrying more than one concern, and a render that only enumerates hands over the items while withholding the pattern the user would act on.

Then fire the lean AUQ below.

The consolidated top-level decision. Use `AskUserQuestion` (do NOT print options as plain text) with header "Action". Mark the severity-recommended escalation option with " (Recommended)" in its label.

**Literal AskUserQuestion shape** — copy and substitute the bracketed slots; do NOT paraphrase option labels, do NOT merge options across rows, do NOT drop options other than `Post Draft PR review` (the only conditional one). On a clean pass the gate still fires with the question re-phrased per §1's Action-gate carve-out:

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
      "label": "Post Draft PR review",         # present or omitted per §Post-option presence below
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

After the user picks — and, on the `/geniro:implement findings` pick, after the §4.6 include-deferred gate resolves — surface ONE follow-up chat line stating the chosen next command verbatim (e.g., `Run: /geniro:implement .geniro/state/handoff/from-review-<branch>.md`) — the user runs the slash command themselves; the orchestrator never auto-invokes /geniro:implement.

**Post-option presence.** "Post Draft PR review" is present whenever `pr-ref:` is non-`none` AND at least one finding of any severity (including LOW / deferred / sub-threshold) remains unposted (no `[POSTED-TO-PR]` tag) AND not kept off the PR (`post-disposition: off-pr`) AND not resolved to need no action (`post-disposition: no-action`) — an all-LOW review still presents it. Omit it only when `pr-ref: none`, OR no findings exist at all, OR every finding already carries `[POSTED-TO-PR]`, OR every remaining finding is `post-disposition: off-pr` or `no-action`. Posting is an external write to a public surface — this gate is mandatory before ANY review posting: fire it and wait; never auto-post (even a draft), never publish, never substitute a chat-text "submit it yourself" line for the pick. Picking it IS the approval; the post creates a PENDING draft the user submits themselves (per §7.4). The Action gate is mutually exclusive — user chooses ONE path.

**Persist user pick to `approvals[]`** with category `action_gate`, written via `atomic_state_write`.

Do NOT auto-invoke /geniro:implement — surface the suggestion only. The user runs the slash command themselves; the state file path is the handoff channel.

---

## 4.6 Include-deferred gate (chained after the "/geniro:implement findings" pick)

Fires when the §4 Action-gate pick is `"/geniro:implement findings"` AND `## Deferred — sub-threshold` holds ≥1 entry. Zero entries → skip silently (no no-op menus). It resolves BEFORE the §4 follow-up echo line and before the Failing-tests gate — the echo names the handoff the user will run, so the fix list must be settled first. Structurally this is the "/geniro:implement findings" pick's drill-down — a sub-gate of the Action path like the §7.2 granularity gate on the Post pick, not a fifth top-level gate.

**Message-first render.** Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering, emit a separate chat message listing each deferred entry in plain English — short title · `file:line` · one line on why it was set aside ("below the fix threshold" → "a minor improvement below the fix bar"; "MEDIUM without Evidence Block" → "flagged without enough supporting evidence to confirm") — then fire the lean AUQ. The § Single-finding gate "Scrub before the AUQ fires (hard)" rule applies to every question string: no "sub-threshold" / "deferred" / severity shorthand ("D1 (LOW)") — say "minor findings below the fix threshold".

**Lean `AskUserQuestion`** — `header: "Minor findings"`:
- **Question:** "The review also set aside <N> minor findings below the fix threshold. Include them in the fix list for /geniro:implement?"
- **Options (3):**
  - `"Leave them in the report (Recommended)"` — the recommendation is conservative per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Recommended-label policy: these findings never passed the Phase 4.2 verification pass, so the recommended option must not steer toward acting on them. They stay visible in the report either way.
  - `"Include all in the fix list"`
  - `"Let me pick"` — run the § Multi-select pick loop in per-finding-question.md (≤4 findings per chained call).

**On include (all or picked)** — rewrite the handoff per the §2.6 write/rewrite discipline (full-file `atomic_state_write`, preserve every prior frontmatter field):

1. MOVE each included entry out of `## Deferred — sub-threshold` INTO `## Findings`, re-rendered as the full per-finding body block with `[USER-ELECTED]` appended to its title-line tag list. Severity stays as scored — never inflated.
2. Verification fields per the §"Verification fields — presence rules" USER-ELECTED convention: a promoted LOW carries none; a promoted evidence-less MEDIUM carries all four fields on the spawn-failure convention, excluded from any post set.
3. The report is already `report_status: final` at this point, and the rewrite in step 1 lands it back at `draft` (§2.6 write/rewrite discipline, step 2). Re-run the §3.5 finalize silently after the rewrite — safe, because a promotion can never introduce a PRODUCT-DECISION (§4.1 Path B keeps those out of `## Deferred — sub-threshold` by construction), so no decision gate re-opens.
4. A legacy bare-list entry with no `File:` sub-field is skipped with a one-line notice (it cannot be re-rendered as a per-finding block) and stays in the report for awareness.

**Persist the pick** to `approvals[]` category `deferred_inclusion` (value: `leave-in-report` | `include-all` | `include-picked` plus the included ids) via `atomic_state_write`. On a compaction-resume, check `approvals[]` before re-firing, like the other Phase 6 gates.

**Empty answer:** the §8 rule applies — re-ask once, then treat as the conservative "Leave them in the report".

The §9 terminal mapping is unchanged — the "/geniro:implement findings" pick still terminates `done`.

---

## 5. Round-N escalation gate

When round ≥3 AND user picks "Continue rounds", fire a secondary AUQ:

- **Continue (round 4)** — re-enter Phase 1 with round counter incremented; risk of infinite loop if user picks repeatedly (capped at round 5 hard ceiling — round 6 attempts auto-trigger "Escalate to user").
- **Escalate to user — structured handoff** — terminal `escalated` state; emits one structured `open_questions[]` frontmatter entry per unresolved next-step (`source: round-N-escalation`, `status: unresolved`), AND writes a chat-surface summary. Downstream consumers gate on the entries per the `open_questions[]` contract in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md`.
- **Abort** — terminal `aborted` state; `## Termination reason: repeated-failure: round-limit-3`.

Persist user pick to `approvals[]` with category `round_n_escalation`, written via `atomic_state_write`.

---

## 6. Failing-tests gate

This is the commit-POLICY gate — it decides whether to commit/push the tests already authored, and it fires unconditionally whenever the handoff's `## Authored Tests` section is non-empty, even when the Action gate already completed or the session is wrapping up. A chat-text request to commit or push the authored tests — at any later point — is answered by firing THIS gate, never by executing directly: chat text is never a gate. It is distinct from the earlier test-AUTHORING gate, which offered to write those tests during the stratify phase and populated `## Authored Tests`. Do not conflate the two: authoring produced the files, this gate decides where they go.

Firing order relative to the Action gate is conditional per the gate chain (§2).

- **Header:** "Failing tests"
- **Question:** "How should the N failing tests authored during the test-confirmation step be handled? They are AI-authored — review before merging. They fail by design, so once pushed the branch's checks will stay red until the findings are fixed or the tests are removed. If you just chose to post findings as a Draft PR review, the comment bodies reference these test files by path — pushing them to the PR's branch is what makes those references resolve for PR reviewers."

**Options:**
- "Commit failing tests on current branch" — orchestrator stages only the test files listed in `## Authored Tests` (never `git add -A` / `git add .`), composes a commit message following the repo's commit style (check `git log -5 --oneline` first), and commits via HEREDOC. **Recommended** — except when user selected "Post" in Action gate, in which case commit+push is Recommended.
- "Commit + push to current branch's upstream" — same as commit-only, then `git push`. **Recommended when user selected "Post" in Action gate** (the posted comment bodies reference the test files by path; pushing makes those references resolve) — load-bearing, not cosmetic.
- "Leave uncommitted" — tests stay on disk for user to review and stage manually.

Never use `--no-verify`, `--amend`, or destructive flags. If a pre-commit hook fails, surface the failure and stop — do not retry or bypass.

Persist user pick to `approvals[]` with category `failing_tests_commit_policy`, written via `atomic_state_write`.

---

## 7. Action == Post drill (PR-ref input only)

Fires only when the Action gate's pick is "Post Draft PR review". Unreachable when `pr-ref: none`.

**On that pick, read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff-post.md`** — it carries
§7.0 through §7.8: the fail-closed guard's four invariants, the already-on-PR dedup, the granularity
and per-finding gates, the `gh api` POST contract, the body content rules, the `[POSTED-TO-PR]`
marker persistence, failure semantics, and post-posting overturn reconciliation. External citations
of `§7.0`-`§7.8` resolve to that file.

Nothing lands on a public PR without passing §7.0. Skip this section entirely on every other pick.

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
