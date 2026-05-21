# P-X8 — Self-learning extensions

**Status:** Specification (pre-implementation) — 5 sub-items accepted 2026-05-21, 3 deferred
**Scope:** L2 entry-type additions, query-side scoring + decay, /instructions validate length cap
**Depends on:** M1 (T3 append-only `learnings.jsonl`), M2 (L2 schema + lifecycle + reflection cycle), M7 (/debug Phase 1 hypothesis tracking), M10b (/instructions validate operation)
**Followed by:** implementation across emit-learning + query-learnings + 4 skills (/debug, /implement, /refactor, /instructions) + 1 hook (M3 SessionStart notice extension)

---

## 1. Purpose

Extend Geniro's L2 episodic-memory subsystem (M2) along three axes identified by the 2026-05-21 self-learning investigation:

1. **Write more signal** — record failure trajectories that today disappear: discarded hypotheses (/debug), rejected suggestions (every AUQ-emitting skill), retry sequences (/implement self-review fix-loop, /debug fix-attempts, /refactor blocked transformations).
2. **Read smarter** — rank query results by recency × trust × access-count instead of returning matching entries in append order. Surface a stale-entry archival nudge at the M3 SessionStart hook so `learnings.jsonl` doesn't balloon over years of usage.
3. **Catch L4 bloat early** — warn when `.geniro/instructions/*.md` files cross the empirical 200-LOC adherence ceiling.

Both axes are benchmark-validated: Reflexion-style failure-reflection writes lifted HumanEval pass@1 from 80→91% ([arxiv 2303.11366](https://arxiv.org/abs/2303.11366)); write-time consolidation à la Mem0 beat OpenAI memory by +26 pts on LOCOMO with −90% tokens ([arxiv 2504.19413](https://arxiv.org/abs/2504.19413)); MemoryBank's Ebbinghaus decay is the canonical answer to unbounded-append rot ([arxiv 2305.10250](https://arxiv.org/abs/2305.10250)).

**Out of scope (deferred):** see §10.

---

## 2. Decision matrix

| ID | Title | Decision | Effort | Source pattern (citation) |
|---|---|---|---|---|
| **P-X8-1** | `discarded_hypothesis` L2 type for /debug | Accept | M | Reflexion verbal-reflection-on-failure (+11 pts HumanEval) |
| **P-X8-2** | `user_rejected_suggestion` L2 type | Accept | S | Mem0 turn-boundary extraction (+26 pts LOCOMO) |
| **P-X8-3** | `retry_failure_sequence` L2 type | Accept | M | Reflexion + Voyager-inverse (don't write failures-as-successes; write failures-AS-failures) |
| **P-X8-4** | Score-based ranking + auto-deprecate stale | Accept | M | MemoryBank Ebbinghaus decay; Zylos pruning |
| **P-X8-5A** | 200-LOC cap warning in /instructions validate | Accept | XS | Anthropic Claude Code memory docs (200-line adherence guideline) |
| **P-X8-5B** | Ignored-promotion tracking | Defer | — | (DenisSergeevitch playbook +10.6% — requires telemetry to calibrate) |
| **P-X8-6** | `--scope-fuzzy` flag in query-learnings | Defer | — | Voyager top-K + A-MEM Zettelkasten — superseded by tag-matching coverage |
| **P-X8-7** | Bayesian trust update | Defer | — | SuperLocalMemory — relevant in multi-agent adversarial, not single-user Geniro |

Accepted total effort: ~XS+S+M+M+M ≈ 1.5-2 days. Deferred items preserved with trigger conditions in §10.

---

## 3. New L2 entry types

Three new `type:` values extend the M2 §5.1 typed-extension table. Schema for each follows the same pattern: required `ext.*` fields enumerated below, all other base/optional fields per M2 §5.1.

### 3.1 `discarded_hypothesis` (P-X8-1)

**Required `ext.*`:** `hypothesis` (string), `evidence_against` (string), `tested_by` (string — short description of the test/check that eliminated it).

**Emitter:** `/geniro:debug` Phase 1 §1.4 (after each ELIMINATE decision in the hypothesis log).

**Trigger:** Every hypothesis ELIMINATED in Phase 1 generates one entry. No threshold — the value is recurrence-pattern detection across sessions, not single-emit signal.

**Default trust:** `verified` — orchestrator ran the eliminating test/check, so the elimination is grounded.

**Sliding-window cap:** Keep at most 5 latest `discarded_hypothesis` entries per `(producer, scope)` pair. On 6th emit, auto-supersede the oldest (set its `deprecated: true`). This bound is the Reflexion sliding-window rule — prevents the discarded-hypothesis log from drowning out diagnoses at retrieval time.

**Example:**
```jsonl
{"ts":"2026-05-21T10:15:00Z","producer":"/geniro:debug","scope":"services/payments/refunds.py","summary":"env-vars differ — eliminated (env identical local/CI)","tags":["bug","ci","env-vars"],"type":"discarded_hypothesis","ext":{"hypothesis":"env-vars differ between local and CI","evidence_against":"diff <(env | sort) <(ssh ci env | sort) returns empty","tested_by":"manual env diff"},"trust":"verified"}
```

**Read site:** `/geniro:debug` Phase 1 §1.1 (existing query-learnings call) — surface as `Past investigations in this scope ruled out: <list of hypothesis fields>`. Skill prompt block already exists; the discarded-hypothesis entries surface alongside `diagnosis` entries with a distinct label.

---

### 3.2 `user_rejected_suggestion` (P-X8-2)

**Required `ext.*`:** `suggestion` (string — what was offered), `auq_category` (string — M1 §T1 `approvals[]` category if present, else `ad-hoc`), `rejection_signal` (enum: `picked_non_recommended` | `explicit_cancel` | `explicit_no`).

**Emitter:** M1 `approvals[]` writer — when the AUQ result is written to state.md frontmatter, the writer also emits an L2 entry IF the picked option was either (a) not the option marked `(Recommended)`, or (b) one of `Cancel` / `No` / `Skip` / `Reject`.

**Trigger:** Every qualifying AUQ resolution. No threshold — preferences signal is single-emit by design.

**Default trust:** `verified` — user explicitly typed/clicked the rejection.

**Bound:** No sliding-window cap (preference data is high-signal; let the M2 §5.2 supersede chain handle natural updates when the user changes mind).

**Example:**
```jsonl
{"ts":"2026-05-21T11:30:00Z","producer":"/geniro:plan","scope":"global","summary":"user rejected Redis for session storage (chose Postgres instead)","tags":["plan","session-storage","redis","postgres"],"type":"user_rejected_suggestion","ext":{"suggestion":"Use Redis for session storage","auq_category":"approach_selection","rejection_signal":"picked_non_recommended"},"trust":"verified"}
```

**Read sites:**
- `/geniro:plan` Phase 4 (approach selection): if matching `user_rejected_suggestion` exists for current topic, surface as note in the approach-presentation AUQ so the rejected approach is either omitted or presented with the historical-rejection context.
- `/geniro:implement` Phase 1 (ship-mode prep): query for `auq_category: ship_mode_default` rejections — if user consistently rejects auto-merge, default the AUQ recommendation to draft-PR.
- `/geniro:actions` run-mode (risk-class confirm): query for matching action `slug` rejections — if user rejected this action 3+ times in last 30 days, surface as warning before running.

**Caveat per master plan P-MP-1 #5 (no approval state confusion):** This L2 entry is informational for future-session pattern matching. It does NOT bypass M1 `approvals[]` (which remains per-task and authoritative for the current run). The two layers complement, not duplicate.

---

### 3.3 `retry_failure_sequence` (P-X8-3)

**Required `ext.*`:** `phase` (string — e.g. `self-review`, `fix-attempts`, `transformation`), `attempts` (array of objects `{round: int, failure: string}`), `resolution` (enum: `passed` | `escalated` | `aborted`).

**Emitter:**
- `/geniro:implement` Phase 2 §6.3 final exit (self-review fix-loop): if `retry_count ≥ 2` and resolution was `passed` or `escalated`, emit.
- `/geniro:debug` Phase 2 §2.5 final exit (fix-attempts): if `fix_attempts ≥ 2` and resolution was `passed` or `escalated`, emit.
- `/geniro:refactor` Phase 2 final exit (blocked-transformations): if `blocked_count ≥ 2`, emit.

**Trigger:** `retry_count ≥ 2` to avoid trivial-noise from single-typo retries (Reflexion sliding-window rule applied as а threshold).

**Default trust:** `verified` — failures observed by orchestrator's own test/lint/review re-runs.

**Bound:** Sliding-window cap = 3 latest `retry_failure_sequence` per `(producer, scope, phase)` triple. Older entries auto-supersede with `deprecated: true`.

**Example:**
```jsonl
{"ts":"2026-05-21T12:00:00Z","producer":"/geniro:implement","scope":"services/api/orders.py","summary":"self-review fix-loop needed 3 rounds — common misses: null-check, error-type","tags":["self-review","api","null-check","error-handling"],"type":"retry_failure_sequence","ext":{"phase":"self-review","attempts":[{"round":1,"failure":"missing null-check on order.customer"},{"round":2,"failure":"wrong error type — returned ValueError, expected HTTPException"}],"resolution":"passed"},"trust":"verified"}
```

**Read site:** Phase 1 `query_learnings` call in /implement, /debug, /refactor — if matching `retry_failure_sequence` exists for nearby scope, surface as pre-flight hint: `Past similar work needed N rounds; common misses: <comma-join of failure summaries>`. This primes Phase 2 reviewer-agent prompts с known failure modes.

---

## 4. Decay / pruning (P-X8-4)

### 4.1 Score-based ranking at read time

`query-learnings.sh` adds а **read-time score** computed per entry. Score is NOT persisted к the entry — it's a function of the entry's fields at query time:

```
score = recency_decay × trust_weight × access_weight

where:
  recency_decay = exp(-Δdays / τ),  τ = 90 days (env-overridable via GENIRO_DECAY_TAU_DAYS)
  trust_weight  = { verified: 1.0, retrieved: 0.66, inferred: 0.33 }
  access_weight = 1.0 + log10(1 + access_count),  access_count from optional `access_count` field (absent = 0)
```

`recency_decay` is the Ebbinghaus-curve approximation per MemoryBank ([arxiv 2305.10250](https://ar5iv.labs.arxiv.org/html/2305.10250)). τ=90 days = "after а quarter, an unread entry's weight halves; after а year, it's ~2% of fresh". `trust_weight` reuses the P-M2-3 trust hierarchy at floor-confidence-equivalents.

`access_count` is а new optional base field, incremented by а thin helper `record_access "<dedup_key>"` (callable from query-learnings post-return). The helper does а single `jq` mutation on the entry in-place — exceeding the 4096-byte POSIX-atomic-append guarantee is impossible because the helper rewrites the line, not appends. Concurrency: best-effort, no lock; an occasional missed increment is acceptable (counter, not ledger).

### 4.2 New flag `--score-min N`

Default behavior is unchanged (no score filter — all matching entries returned in append order). With `--score-min 0.3`, query-learnings filters out entries below the threshold AND sorts remaining results by score DESC.

**Default threshold guidance** (informational, callers pick their own):
- `--score-min 0.5` — high-signal only (recently-emitted verified entries).
- `--score-min 0.3` — balanced (recommended default for Phase 1 read calls).
- `--score-min 0.1` — almost everything (mostly for debugging).
- (no flag) — return everything, original behavior.

### 4.3 `archive-stale.sh` helper

New helper `skills/_shared/archive-stale.sh` walks `learnings.jsonl` and flips `deprecated: true` on every entry where `score < 0.1 AND age > 180 days` AND `access_count == 0` (never-read AND old AND already low-score). The helper:

- **Never deletes** — flips `deprecated: true` only. Audit trail preserved.
- **Never auto-runs** — requires explicit user invocation OR M3 SessionStart hook notice (see §4.4).
- **Idempotent** — re-runs are safe; already-deprecated entries skipped.
- **Reports** — prints summary of how many entries deprecated, with per-type breakdown.

Exit codes: `0` success, `1` no entries match criteria, `2` IO error.

### 4.4 M3 SessionStart notice extension

`hooks/session-start-restore.sh` (M3) gains а new optional Block 5e: stale-learnings notice. Emitted when `wc -l learnings.jsonl > 5000` AND `archive-stale.sh --dry-run` reports ≥50 candidates. Body:

```
ℹ️ learnings.jsonl: 5,243 entries, 87 stale candidates (score<0.1, age>180d, never read).
Run `.geniro/skills/_shared/archive-stale.sh` to flip them to deprecated:true (audit-preserving — never deletes).
```

Read-only — never auto-runs. User decides when to clean up.

---

## 5. 200-LOC cap warning (P-X8-5A)

`/geniro:instructions validate` gets а new check:

- **Severity:** LOW
- **Threshold:** 200 lines (default; env-overridable via `--max-lines N`)
- **Source citation:** Anthropic Claude Code memory docs ("longer files consume more context and reduce adherence").
- **Scope:** All `.geniro/instructions/*.md` files AND `.geniro/instructions/review-extra/*.md` files.

**Output example:**
```
LOW: code-style.md is 380 lines.
Anthropic guidance recommends <200 lines for L4 instruction files
(model adherence drops with length).
Suggestions:
  - Split into code-style-database.md + code-style-api.md
  - Or remove rules now obvious/internalized
```

Implementation: single `wc -l` invocation per file, +5-10 lines in `skills/instructions/SKILL.md` Phase validate. The check is purely informational (LOW severity, warning); does NOT block validate from passing.

`--max-lines 0` disables the check entirely.

---

## 6. Helper changes (summary)

| Helper | Change | Section |
|---|---|---|
| `_shared/emit-learning.sh` | No code change. Schema extension is data-only — new `type:` values fit existing typed-extension pattern. | §3 |
| `_shared/query-learnings.sh` | Add `--score-min N` flag; compute score per entry; sort DESC by score when filter active. Add optional `access_count` increment via new `record_access` sub-helper. | §4.1, §4.2 |
| `_shared/archive-stale.sh` | NEW. Walks `learnings.jsonl`, flips `deprecated: true` on stale entries. | §4.3 |
| `hooks/session-start-restore.sh` | Add optional Block 5e — stale-learnings notice. Read-only. | §4.4 |
| `skills/instructions/SKILL.md` (Phase validate) | Add `--max-lines N` flag + LOW-severity length check. | §5 |
| `skills/debug/SKILL.md` (Phase 1 §1.4) | Emit `discarded_hypothesis` per ELIMINATE decision. Sliding-window cap = 5 per scope. | §3.1 |
| `skills/implement/SKILL.md` (Phase 2 §6.3) | Emit `retry_failure_sequence` if retry_count ≥ 2. | §3.3 |
| `skills/debug/SKILL.md` (Phase 2 §2.5) | Emit `retry_failure_sequence` if fix_attempts ≥ 2. | §3.3 |
| `skills/refactor/SKILL.md` (Phase 2 exit) | Emit `retry_failure_sequence` if blocked_count ≥ 2. | §3.3 |
| M1 `approvals[]` writer (shared) | Emit `user_rejected_suggestion` on rejection-signal AUQ resolutions. | §3.2 |
| `skills/plan/SKILL.md` (Phase 4), `skills/implement/SKILL.md` (Phase 1), `skills/actions/SKILL.md` (run-mode) | Add `user_rejected_suggestion` query at relevant decision points. | §3.2 |

Architecture/M2 §5.1 typed-extension table — extend with three new rows. M2 §5.3 reflection-cycle table — extend with new emit-trigger rows.

---

## 7. Integration: per-skill emit/read summary

| Skill | New emit sites | New read sites |
|---|---|---|
| `/geniro:debug` | Phase 1 §1.4 (`discarded_hypothesis`), Phase 2 §2.5 (`retry_failure_sequence`) | Phase 1 §1.1 (existing query extended to surface `discarded_hypothesis`) |
| `/geniro:implement` | Phase 2 §6.3 (`retry_failure_sequence`), shared M1 writer (`user_rejected_suggestion` on Phase 3 ship-mode AUQ) | Phase 1 (existing query extended to surface `retry_failure_sequence`, `user_rejected_suggestion`) |
| `/geniro:refactor` | Phase 2 exit (`retry_failure_sequence`), shared M1 writer (`user_rejected_suggestion` on Phase 1 HIGH-step AUQ) | Phase 1 (existing query extended) |
| `/geniro:plan` | shared M1 writer (`user_rejected_suggestion` on Phase 4 approach AUQ) | Phase 4 (new query for prior rejections) |
| `/geniro:actions` | shared M1 writer (`user_rejected_suggestion` on Phase 5.3 risk-class AUQ) | run-mode (new query for action-slug rejections) |
| `/geniro:review` | — | Phase 1 (existing query extended) |
| `/geniro:onboard` | — | Phase 1 (existing query extended) |
| `/geniro:investigate` | — | Phase 1 (existing query extended) |
| `/geniro:setup` | — | — |
| `/geniro:instructions` | — (validate-only change is independent) | — |
| `/geniro:update` | — | — |

---

## 8. Anti-pattern check (P-MP-1)

Per master-plan P-MP-1 lint criterion, P-X8 must not reintroduce any of the 12 anti-patterns. Status:

| # | Anti-pattern | P-X8 status |
|---|---|---|
| 1 | One giant prompt | ✅ N/A — no prompt changes |
| 2 | One giant tool | ✅ N/A — helper changes scoped |
| 3 | Unbounded autonomous loop | ✅ Sliding-window caps on `discarded_hypothesis` (5 per scope) and `retry_failure_sequence` (3 per scope+phase); decay (§4.1) bounds query result set |
| 4 | Autonomous external sends в first release | ✅ N/A — no new external sends |
| 5 | No approval state | ✅ §3.2 explicitly notes `user_rejected_suggestion` complements (not duplicates) M1 `approvals[]` |
| 6 | No durable plans or goals | ✅ N/A — preserves M1 state framework |
| 7 | No compaction strategy | ✅ §4.4 SessionStart Block 5e extends М3 — does NOT replace existing additionalContext blocks |
| 8 | All connectors loaded up front | ✅ N/A |
| 9 | High-risk tools without policy | ✅ `archive-stale.sh` is local-fs only; `deprecated: true` flip is reversible by direct edit |
| 10 | Subagents before single-agent MVP measured | ✅ N/A — no new subagent spawns |
| 11 | Dynamic timestamps в plugin-distributed Markdown | ✅ `ts` is in user-data file (`learnings.jsonl`), not plugin Markdown |
| 12 | Non-deterministic agent registration | ✅ N/A |

Additionally, per master-plan §159 «Auto-promote L2→L4» anti-rationalization: P-X8 does NOT add auto-promotion. The 200-LOC cap warning (P-X8-5A) is а LINT warning on existing L4 files, NOT а promotion path. L4 curation stays user-controlled (P-M4-5 preservation).

---

## 9. Migration plan

P-X8 is a pure additive extension over M1-M10. No breaking changes.

### 9.1 Pre-existing `learnings.jsonl` files

Existing entries without the new types continue to work — query-learnings returns them as before. New types are additive в the M2 §5.1 typed-extension table.

### 9.2 Pre-existing query-learnings calls

Existing call sites pass no `--score-min` flag, so behavior is unchanged (return-all-matching, append order). New call sites can opt into scoring by adding the flag. No mass refactor required.

### 9.3 Optional `access_count` field

Entries without `access_count` are treated as `access_count: 0` in score computation. No backfill needed; entries gain а count organically as they're queried.

### 9.4 `archive-stale.sh` first run

On а repo with а large pre-existing `learnings.jsonl`, the first `archive-stale.sh` run may mark thousands of entries `deprecated: true`. This is intentional (the threshold criteria already exclude high-signal/recent entries). Recommended first invocation: `archive-stale.sh --dry-run` to preview, then real run.

### 9.5 MIGRATION.md entry

Add а new section to MIGRATION.md under the next plugin version (e.g. v1.85.0):

```markdown
### NEW L2 entry types — `discarded_hypothesis`, `user_rejected_suggestion`, `retry_failure_sequence`

P-X8 extends M2 §5.1 typed-extension table. Existing entries unaffected — readers may opt into surfacing new types.

**Action required:** None — additive. Optional: rerun affected skills to generate new entry types organically.

**Auto-detect:** N/A — informational.

**Severity:** LOW.
```

---

## 10. Out of scope (deferred items)

### 10.1 P-X8-5B — Ignored-promotion tracking

**Status:** Deferred 2026-05-21.

**Trigger conditions for resumption:**
- Telemetry (P-X6) ships AND data shows >30% of L4-promotion suggestions are ignored.
- User reports false-positive bias (skills suggesting same promotion repeatedly with no signal).

**Why deferred:** Attribution problem без telemetry — user mid-edit а file через built-in Edit tool (not /instructions edit) is invisible к the tracker. Calibrating «ignored count threshold» (3? 5? 10?) needs usage data we don't have.

**Preserved deliverables:**
- New L2 type `promotion_suggested {l2_dedup_key, l4_target_scope}` paired-emit on promotion-surfacing.
- Cross-check on `/instructions edit <scope>` invocation.
- AUQ «5 similar suggestions ignored — drop this rule type?» surface mode.

### 10.2 P-X8-6 — `--scope-fuzzy` flag in query-learnings

**Status:** Deferred 2026-05-21.

**Trigger conditions for resumption:**
- Usage data shows tag-matching recall is consistently missing entries that scope-fuzzy would catch.
- Embedding-based retrieval (semantic similarity, beyond fuzzy-path) becomes feasible — at which point P-X6 unblocks both.

**Why deferred:** Most L2 entries are tagged with general tags (e.g. `[stripe, payments, idempotency]`). Query-learnings already cross-matches via `--tag`. Scope-fuzzy adds а second matching axis but tag-matching already does similar work. Marginal value vs implementation cost.

**Preserved deliverables:**
- `--scope-fuzzy <basename|parent-dir|both>` flag в query-learnings.sh.
- basename mode caveat: false-positive risk (Toggle.tsx в unrelated dirs); parent-dir is safer.
- Phase 2 (embedding-based) deferred к P-X6.

### 10.3 P-X8-7 — Bayesian trust update

**Status:** Deferred 2026-05-21.

**Trigger conditions for resumption:**
- Geniro moves to multi-agent adversarial settings (e.g., agents can inject entries from external sources).
- Observed memory-poisoning incident (а retrieved entry leads к а documented production bug).
- P-X6 telemetry shows non-trivial rate of contradicted entries.

**Why deferred:** Memory poisoning is а real risk in adversarial multi-agent systems. Geniro is single-user/single-agent — bad entries are rare, manual `deprecated: true` flag via direct edit covers it. The plumbing cost (every reading skill must conditionally append «yes/no this worked» outcomes) is high vs. unmeasured benefit.

**Preserved deliverables:**
- Optional `verifications: [{at, outcome}]` audit array.
- `effective_trust = base_trust × (positive / total)` compute in query-learnings.
- Per-skill modification: reading skills append `{outcome: confirmed|contradicted}` post-use.
- Modify-variant: limit к `retrieved`/`inferred` entries (skip `verified` — Geniro default).

---

## 11. Open questions

| ID | Question | Resolution path |
|---|---|---|
| OQ-X8-1 | τ=90 days for recency_decay — empirically right? | Calibrate after 3 months of usage data. Currently env-overridable via `GENIRO_DECAY_TAU_DAYS`. |
| OQ-X8-2 | Should `access_count` increment be on every query or only on entries actually USED (e.g., cited in subsequent skill output)? | Defer к P-X6 telemetry. For now: increment on every successful query return — simpler, slight over-count acceptable. |
| OQ-X8-3 | `user_rejected_suggestion` for non-AUQ rejections (e.g., user manually edits спе.md to remove an approach mentioned in /plan output)? | Out of scope. AUQ-only is the bright line — anything else needs attribution rules that don't exist yet. |
| OQ-X8-4 | `retry_failure_sequence` for /review fix-rounds — М6 has stratify→fix→re-review cycles | Adding /review к §3.3 emitter list is а follow-up, not required for P-X8 MVP. М6 doesn't have а bounded fix-loop like /implement does; needs separate threshold definition. |

---

## 12. Test coverage

New tests required (mirror existing M2 test pattern):

- `tests/memory/emit-learning.sh` — extend with cases for the three new types (required ext fields validated, optional fields passed through).
- `tests/memory/query-learnings.sh` — extend with `--score-min` cases (filter + sort behavior, edge cases at τ boundaries).
- `tests/memory/archive-stale.sh` — NEW. Dry-run mode, idempotency, criteria correctness (score < 0.1 AND age > 180d AND access_count == 0).
- `tests/skills/instructions-validate-max-lines.sh` — NEW. 200-line threshold, env override, severity classification.
- `tests/skills/debug-discarded-hypothesis.sh` — NEW. Sliding-window cap enforcement (6th emit supersedes oldest).
- `tests/skills/implement-retry-failure-sequence.sh` — NEW. Threshold (≥2 retries), resolution-state correctness.

---

## Appendix A — Worked example: a /debug session with P-X8 active

User runs `/geniro:debug "users-service tests fail in CI"`.

**Phase 1 §1.1 — query-learnings:**
```bash
query_learnings --tag ci --scope services/users --score-min 0.3 --limit 5
```
Returns (sorted by score DESC):
1. `discarded_hypothesis` from 3 weeks ago: «env-vars differ — eliminated» (score=0.78)
2. `diagnosis` from 6 months ago: «postgres connection pool exhausted in CI — fixed by setting maxPool=20» (score=0.41 — old but verified)

Skill surfaces:
```
Past investigations in services/users ruled out:
  - env-vars differ (tested 2026-04-30 by manual env diff)
Past diagnoses:
  - postgres connection pool exhausted in CI (fixed 2025-11-12)
```

**Phase 1 §1.4 — orchestrator hypothesizes new candidates:**
- H1: «test isolation broken — shared db state»
- H2: «race condition in users-service startup»
- H3: «CI runner timezone differs»

After running tests, H1 ELIMINATED (each test creates its own schema), H3 ELIMINATED (TZ=UTC enforced). H2 CONFIRMED — race on connection-pool init.

Per P-X8-1: H1 and H3 emit `discarded_hypothesis`. Sliding-window check: scope `services/users` had 1 prior discarded_hypothesis (the env-vars one from §1.1), now gains 2 more → total 3 (under cap of 5; no supersede needed).

**Phase 2 §2.5 — fix attempts:**
- Attempt 1: add startup gate → fail (race shifted, didn't eliminate)
- Attempt 2: use connection-pool lazy-init → fail (third-party lib needs ready conn at module-load)
- Attempt 3: wrap module-load in awaited Promise.resolve(pool.connect()) → pass

Per P-X8-3: `retry_failure_sequence` emit (fix_attempts=3 ≥ 2 threshold):
```jsonl
{"type":"retry_failure_sequence","ext":{"phase":"fix-attempts","attempts":[...],"resolution":"passed"}}
```

**Phase 3 ship + Phase 4 reflection:**
- Diagnosis emit (existing M7 behavior): root_cause + fix.
- New discarded-hypothesis count: 3 (under cap).
- New retry-failure entries: 1 (under cap of 3 per scope+phase).
- Six months later, а new user-service flake appears — the new /debug Phase 1 surfaces all this prior context, **including the failed-fix attempts**, helping the orchestrator skip dead-ends faster.
