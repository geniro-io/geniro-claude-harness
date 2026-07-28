# /geniro:review — Phase 5 & Phase 6

Phase bodies for `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md`. Read on entry to Phase 5. The spine keeps the phase headings, the loop invariants, the anti-rationalization table, and the Definition of done — this file carries the Steps.

## Contents

- Phase 5 — Persist & emit
  - 5.0 Repeat findings (re-run rounds)
  - 5.1 Handoff file write
  - 5.2 Old state-file fallback
  - 5.3 Auto-emit pitfall learnings on convergence
  - 5.4 PR comment posting (conditional — gated by Phase 6)
  - 5.5 Idempotent re-entry
- Phase 6 — Action gate handoff (gate chain + operational rules)

---

## Phase 5 — Persist & emit

State.md `phase: persist`.

### 5.0 Repeat findings (re-run rounds)

On a round ≥2 re-run, an admitted finding carrying the `repeat-of-prior-round` marker stays in the main `## Findings` list with a "seen since round <N>" annotation, every gate intact, and a `<R> repeated unchanged from round <N-1>` clause on the Disposition line. Skipped on a first review / fresh-PR round. Full mechanics: `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §7 (Repeat-finding presentation).

### 5.1 Handoff file write

Path: `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md`. `<PRIMARY_ROOT>` resolved per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A.

**Write via `atomic_state_write`** — never a direct Edit/Write (the `enforce-state-helper` hook hard-blocks direct writes to the canonical state path).

**`open_questions[]` rich-field authoring contract.** When composing `open_questions[]` entries from kept findings, fill the optional `context` / `evidence` / `options` / `recommendation` fields per the schema in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2. The reviewer-agent output already carries Evidence / Why-matters / Suggested-fix / Options per `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output Format — copy them into the open_question entry, do NOT discard them at composition time. Bare `question:` entries trigger the `review-handoff.md` §2.5 Tier 3 fallback (terse AUQ), which the user experiences as the failure mode the rich-field schema was added to prevent. For non-finding open_questions (e.g., process / scope / verification questions surfaced by spec-compliance or pr-metadata reviewers), author `context` + `options` + `recommendation` inline — the reviewer's `## Why this matters` and `## Suggested fix` synthesis fields are still the source material; the consumer has no other way to render the question richly.

**Verify what's verifiable; record only genuine decisions.** Before writing a finding or an `open_questions[]` entry that asks the author to confirm something, check it yourself against the diff, the code, and git history — a finding states a verified fact, it does not ask the reader to verify what /geniro:review can determine (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md` §4). Record an `open_questions[]` entry ONLY for a genuine judgment call whose answer changes what /geniro:review posts (e.g. "are these seeder additions in-scope for this PR?" — the answer determines whether that finding gets posted; the `review-handoff.md` §2.5 Pre-gate surfaces these). Do NOT record a "how should X be fixed?" question — a finding carries its own recommended action, and /geniro:implement decides fix specifics when it fixes.

**`step0_status:` producer-side initialization contract.** When writing each PRODUCT-DECISION finding into `## Findings`, also write `step0_status: pending` as the last sub-field of its body block (schema at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §"Per-finding body schema"). This is the runtime sentinel the open-decision gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §3) flips to `resolved` (or `wontfix`) after the per-finding AUQ pick lands, and the §7.0 Pre-Post guard re-reads to fail-close before posting. Omit the field entirely for non-PRODUCT-DECISION findings — its presence is the marker that the open-decision gate owes them an AUQ.

**`report_status:` producer-side initialization.** Write frontmatter `report_status: draft` on this Phase 5.1 handoff write. The report is provisional — written now so a mid-gate compaction recovers the findings, but not yet authoritative. The Phase 6 finalize step (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §3.5) flips it to `final` only after the decision gates clear; the handoff offer and the §7.0 public-post guard refuse to fire against a `draft`.

Write the full handoff frontmatter + body skeleton from the template at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §2.6 "Handoff file template" (the `atomic_state_write` heredoc block). Each finding under `## Findings` renders as the multi-line per-finding body block (NOT a one-liner) per §"Per-finding body schema" in that same reference — the title line is a `- [ ]` addressed-checkbox (written unchecked) the engineer ticks by hand as they resolve the finding, with the detail fields nested beneath it. The Phase 3 §3.3 KEEP/FILTER judgment preserves every reviewer-agent field; dropping fields to reach a one-liner is the failure mode the schema prevents.

### 5.2 Old state-file fallback

If a file exists at `<PRIMARY_ROOT>/.geniro/state/review-findings-state.md`, read it once on Phase 5 entry for resume compatibility, but always write to the canonical path. The old file is NOT auto-deleted (user may have references).

### 5.3 Auto-emit pitfall learnings on convergence

**Trigger condition:** Phase 3 orchestrator-side dedup produced a finding with `convergence_count: ≥3` (3+ reviewers reported same issue OR 2 reviewers + 1 mechanical pre-pass).

When trigger fires, **auto-emit (no AUQ)**. `emit_learning` reads a single JSON object on stdin — pipe the JSON, do not pass YAML key/value lines (a YAML block exits 64, dropping the learning):

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh"
emit_learning <<'EOF'
{"producer":"/geniro:review","type":"pitfall","scope":"<changed-file-glob>","summary":"<finding title with file:line>","tags":["<dimension>","<project-tech>"],"trust":"verified","body":"Cross-reviewer convergence: <N> reviewers + <mechanical-flag>"}
EOF
```

Required fields are `producer` / `scope` / `summary` / `tags` (a missing one exits 64). Dedup + sanitization per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md`. After a successful emit (`rc=0`), echo `Recorded learning: <summary>` while the report is being assembled (not after it's delivered), per that file's §"Caller contract"; on a non-zero return, print one plain-English line so the dropped learning is visible rather than swallowed.

### 5.4 PR comment posting (conditional — gated by Phase 6)

If Phase 6 user picks "Post Draft PR" option, post the finding list as a PENDING review per the canonical procedure in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §7.4 — one `gh api POST` call with the `event` field omitted; /geniro:review never submits the review it creates, and this holds across rounds. Persist the §7.4 `non-resumable-actions[]` entry via `atomic_state_write` in the same drill. `mcp__github__pull_request_review_write` is NOT used here — the MCP wrapper does not surface the per-comment `path` / `line` / `side` fields required for inline anchoring, so the canonical tool is `gh api` directly per the reference. PR post fails fail-closed per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §7.7 — write `## Errors` entry + abort Phase 5; never silently downgrade to top-level `gh pr comment` or retry with `event: COMMENT`.

Full Post drill (Steps 0-6) in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §7 — load it here, on this branch, not with the rest of the handoff contract.

### 5.5 Idempotent re-entry

If Phase 5 re-enters after compaction:
1. Read state.md `non-resumable-actions[]` — if PR post already completed, skip re-post.
2. Re-read findings from Phase 3 dedup output (held in context OR re-runs Phase 3 if context lost).
3. Re-write `from-review-<branch>.md` (overwrite — `atomic_state_write` handles atomicity).
4. Re-writing resets `report_status: draft`; Phase 6 finalize re-runs and re-flips to `final` after the decision gates clear (idempotent — re-entry never leaves a stale `final`).

---

## Phase 6 — Action gate handoff

State.md `phase: action-gate`. **Full contract:** `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §1-§6 and §8-§9.

Read §7 (the GitHub reviews-API Post drill) only if the Action gate's pick is "Post Draft PR review" — it is a third of that file, it is unreachable when `pr-ref: none`, and §5.4 already cites the two subsections it needs by anchor. Loop invariant #9 and the §7.0 Pre-Post guard bind only on that same path, so they are satisfied vacuously on every other pick.

Summary of the gate chain (each gate is its own AUQ — never collapsed):

1. **Pre-gate — Resolve Open Questions** fires first whenever frontmatter `open_questions[]` has any entry with `status: unresolved`. Chain one AUQ per such entry (cap-extension >4). Always-WAIT. Resolutions persist back via `atomic_state_write`. Complete this before any other gate, because the later gates act on findings whose ambiguity these questions resolve. Full procedure: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §2.5. Skipped when zero unresolved entries.
2. **Open-decision gate** — for each kept finding whose state-file `Decision Type:` field is `PRODUCT-DECISION` — judgment calls the reviewer won't resolve for you — render the finding to chat first, then fire one lean AUQ (header `Open decision`), per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering. Skipped when none.
   - **Finalize (silent — no AUQ).** After the open-decision gate clears, flip the report from `draft` to `final` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §3.5). The Action gate's handoff option and the public-post guard both require `final`, so the handoff is never offered against a report whose decisions are still open.
   - **Rule/improvement mining** — for durable rule mining, run `/geniro:reflect` on demand to analyze recent sessions for rule candidates.
3. **Action gate** — render the wrap-up chat message first (all-decided tracker + one-sentence opener + kept-findings severity digest, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §4), then fire `AskUserQuestion` with the canonical 4 options. Never collapse into chat text ("Want me to apply these now?" / "Should I push?" / "apply the fix now" / "add the test now") — that bypasses the persisted-pick contract and silently drops options the user might want (e.g., Post Draft PR review). The canonical 4 option labels below are an allowlist: substituting an ad-hoc "apply the fix" / "add the test" / "what next?" option (or applying any fix from /geniro:review) is forbidden — fixes route to `/geniro:implement findings`. Option labels (verbatim, do not paraphrase):
   - `"/geniro:implement findings"` — append ` (Recommended)` when CRITICAL≥1 OR HIGH≥2; exits /geniro:review and the model surfaces `/geniro:implement .geniro/state/handoff/from-review-<branch>.md` as the next command. Its description must disclose that /geniro:implement applies the fixes and asks before committing/pushing — picking it routes the findings, it does not authorize a ship (per the §4 literal description).
   - `"Post Draft PR review"` — present whenever `pr-ref:` is non-`none` AND at least one finding of any severity (including LOW / deferred / sub-threshold) remains unposted. OMIT only when `pr-ref: none`, OR no findings exist at all, OR every finding already carries `[POSTED-TO-PR]` from a prior round.
   - `"Continue rounds (re-review)"` — Round-N escalation gate fires when round ≥3.
   - `"Skip — keep findings on disk"` — append ` (Recommended)` when CRITICAL=0 AND HIGH≤1.

   Full AskUserQuestion shape (literal block), descriptions, and severity-driven recommendation rule: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §4. Persist user pick to `approvals[]` with category `action_gate` via `atomic_state_write` (never a raw write on the handoff path).
   - **Include-deferred gate (chained).** When the pick is `"/geniro:implement findings"` and the report holds set-aside minor findings, a chained question asks whether to include them in the fix list, resolving before the follow-up echo line; skipped silently when none. Canonical contract: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §4.6.
4. **Failing-tests gate** — fires unconditionally whenever state.md `## Authored Tests` is non-empty (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §6). A chat request to commit/push authored tests — whenever it arrives — re-fires this gate instead of executing directly.

Operational rules:

- **Reporter behavior** — no fix loop inside /geniro:review. /geniro:implement self-review (5-dim parallel) is a separate skill with a separate contract.
- **Round-N escalation gate** when round ≥3 + "Continue rounds" pick — secondary AUQ (Continue / Escalate / Abort). Terminal `aborted` records `## Termination reason: repeated-failure: round-limit-3`.
- **Pre-Post unresolved-ambiguity guard** (§7.0) — defensive re-check before `gh api POST /reviews`: aborts the Post drill if any `open_questions[]` entry has `status == unresolved`, OR any PRODUCT-DECISION finding has `step0_status: pending`, OR any kept CRITICAL/HIGH/MEDIUM finding still carries `Validation: refuted` (it should have been filtered at Phase 4.2), OR the report is still `report_status: draft` (the §3.5 finalize step never ran). Fail-closed second line of defense against producers writing new entries mid-phase or the open-decision gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §3) being skipped under drift.
---
