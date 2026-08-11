# Canonical state-tier specification

**Canonical reference for every state file in `.geniro/`.** See `ARCHITECTURE.md` §State Files for the design decisions behind this spec.

Helpers reference this spec:
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` — write helper for T1.5, T2, T3 CRUD, and append-only.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md` — validates frontmatter against this spec.

## Contents

- Tier model — the four tiers and their lifecycle contracts
- Path roots — which files live under each tier (plus the tier-exempt TDD-cycle state file)
- No ad-hoc state files under `.geniro/state/` — free-form files bypass the validator, restore hook, and cleanup
- Frontmatter contract — common-base + tier-specific required fields
- T2 `open_questions` array schema — the handoff gate substrate
- `authored_tests` array schema — the debug-handoff test record
- Format rules — frontmatter fence + body conventions, incl. the `## Errors` unanswered-gate entry
- Concrete examples — one worked frontmatter per tier/layout
- Validation rules — what `validate_state_file` enforces
- Slug rule — computing the session-bound slug

---

## Tier model

Every state file in `.geniro/` belongs to exactly one tier, determined by its path root and lifecycle contract — with one documented exception, the TDD-cycle state file (see §Path roots → Tier-exempt).

| Tier | Purpose | Lifecycle | Worktree routing | Concurrency |
|---|---|---|---|---|
| **T1 — TASK ephemeral** | Transient subagent outputs / scratch (no frontmatter) | Created mid-run; deleted at the owning run's terminal exit | cwd-relative | path-scoped via `<task-dir>` |
| **T1.5 — TASK durable** | Frontmatter-bearing task artifacts owned by one skill run, but needed by downstream consumer skills (`/geniro:review` spec-compliance, `/geniro:implement` Adjustment Routing, `/geniro:debug`, `/geniro:refactor`) | Created at Phase 0; **survives Phase Ship** | cwd-relative | path-scoped via `<task-dir>` or `<skill>/<slug>` or singleton `<skill>/state.md` |
| **T2 — HANDOFF** | Inter-skill data handoff | Created by producer; overwritten on next produce; not auto-deleted | primary-worktree (via `primary-worktree.md` Mode A) | branch-scoped path |
| **T3 — PERSISTENT** | Cross-session knowledge & user content | Never auto-deleted; CRUD or append-only | primary-worktree always | declared via `concurrency:` sub-attribute |

**T1 vs T1.5 distinction.** T1 = ephemeral transient outputs without frontmatter — canonical list: the §T1 table below; they never pass through `validate_state_file` and are deleted at terminal exit via the shared helper `${CLAUDE_PLUGIN_ROOT}/lib/clean-task-transients.sh` (`clean_task_transients <task-dir>` — the single source of the list; timing per the note under that table). T1.5 = frontmatter-bearing durable artifacts (`spec.md`, `state.md`, `plan-*.md`, `milestone-*.md`) that downstream consumer skills read after the producing skill ships; the cleanup never touches them. T1.5 surviving is the point: the user keeps the spec, the state log, and the milestone breakdown for audit or for re-running `/implement` against the same task-dir.

**Who cleans what, and when.**

| Skill | Cleanup at terminal exit |
|---|---|
| `/implement` | `clean_task_transients` before EVERY terminal `phase:` write — `done`, `aborted`, `debug-handoff`, `self-review-only`, `ship-committed-only` — not only the Ship path. |
| `/plan` | `clean_task_transients` on `done` and `aborted`. A plan-only or milestone-sliced run would otherwise leave `.research-*.md` behind, since milestone slicing runs `/implement` in a different task-dir and it never reaches the parent planning dir. `/implement`'s own run stays a backstop. |
| `/debug`, `/refactor`, `/onboard`, `/investigate`, `/audit-instructions` | `rm -rf` the whole `.geniro/state/<skill>/<slug>/` dir — state.md plus any scratch written there. The `/geniro:update` migration walk scans only `.geniro/planning`, so nothing else would ever sweep these. `/audit-instructions` deletes its slug dir at the Phase 5 action gate; the dated report at `.geniro/state/audit-instructions/report-<date>.md` lives outside the slug dir and survives (§Path roots → T1.5). |
| `/review` | `rm -rf` `.geniro/state/review/<branch-slug>/` at the Phase 6 terminal write, when the test gate created it. It is keyed by branch rather than by run, so without this every reviewed branch leaves a directory behind permanently — and `/review` writes no state.md there, so session-restore never surfaces it either. |
| `/resolve` | `clean_task_transients` on `.geniro/state/resolve/<slug>/` before every terminal `phase:` write — transients go, the dir stays. It is a spec producer whose `spec.md` and handoff are consumed downstream by `/implement`, so an `rm -rf` would delete the deliverable, the same reason `/plan` retains its planning task-dir and `/setup` its singleton. |

Transients left behind by an interrupted run are swept by the `/geniro:update` migration walk; that sweep is deliberately recurring rather than one-shot.

---

## Path roots

### T1 — ephemeral transient outputs (no frontmatter; deleted at terminal exit)

| Path | Producer |
|---|---|
| `.geniro/planning/<task-dir>/.kr-out.md` | knowledge-retrieval-agent (subagent report) |
| `.geniro/planning/<task-dir>/.ce-out.md` | codebase-explorer-agent (subagent report) |
| `.geniro/planning/<task-dir>/.tr-out.md` | test-runner-agent (subagent report) |
| `.geniro/planning/<task-dir>/.adversarial-out.md` | adversarial-tester-agent (subagent report) |
| `.geniro/state/review/<branch-slug>/.adversarial-out.md` | adversarial-tester-agent, when `/review` runs its test gate outside a planning task-dir |
| `.geniro/state/resolve/<slug>/.spec-challenge-out.md` | spec-challenge pass, `/resolve` |
| `.geniro/planning/<task-dir>/.research-out.md` | codebase-research-agent (subagent report) |
| `.geniro/planning/<task-dir>/.research-<facet>.md` | /plan Phase 1 per-facet research |
| `.geniro/planning/<task-dir>/.spec-challenge-out.md` | spec-challenge pass scratch report (/plan Phase 7.5, /implement fact-check) |
| `.geniro/planning/<task-dir>/notes.md` | Orchestrator ad-hoc scratch |
| `.geniro/planning/<task-dir>/playwright-verify.png` | Pre-Ship Visual Verification screenshot |

These files carry no frontmatter and never pass through `validate_state_file`. They are cleaned mechanically via targeted `rm -f` before every terminal `phase:` write of the owning run (Ship and all other terminal transitions); leftovers from interrupted runs are swept by the `/geniro:update` migration walk.

### T1.5 — three valid layouts (producer-bound; survives Ship)

| Path root | Layout | Producer category |
|---|---|---|
| `.geniro/planning/<task-dir>/` | Multi-file task-dir (`state.md` + `spec.md` + `plan-*.md` + `milestone-*.md`) | **Task-bound skills** producing durable artifacts — `/geniro:implement`, `/geniro:plan` |
| `.geniro/state/<skill>/<slug>/` | Subdir-per-slug; canonical `state.md` inside | **Session-bound skills** — `/geniro:debug`, `/geniro:refactor`, `/geniro:onboard`, `/geniro:investigate`, `/geniro:resolve`, `/geniro:audit-instructions` |
| `.geniro/state/<skill>/state.md` | **Singleton** — no `<slug>/` subdir | **Singleton-lifecycle skills** — `/geniro:setup` |

**Frontmatter-less companion artifact inside a T1.5 skill dir.** `/geniro:audit-instructions` persists dated reports at `.geniro/state/audit-instructions/report-<date>.md` — directly under the skill dir, outside any `<slug>/` subdir. No frontmatter, never passed through `validate_state_file`, written via `atomic_state_write` like every `.geniro/state/` path; it deliberately survives slug cleanup so the next run reads the latest report as its do-not-flag input.

**One named exception to "survives Ship."** `/geniro:setup` deletes its singleton `state/setup/state.md` at its Done phase — the only Geniro state file deleted on success. Bootstrap state describes a one-shot run that is over: no downstream skill reads it, and a stale copy makes the next invocation resolve to `re-run` against a run that already finished. The exception is scoped to that one path; every other T1.5 file survives past Ship as the tier defines.

### T2

- `.geniro/state/handoff/from-<producer>-<branch>.md`

### T3

- `.geniro/knowledge/` — append-only (`learnings.jsonl`)
- `.geniro/instructions/` — CRUD (rule sets)
- `.geniro/actions/` — CRUD (workflow actions)
- `.geniro/workflow/` — CRUD (integration config)
- `.geniro/planning/_FEATURES.md`, `_CODEBASE_MAP.md`, `_project.md`, `_architecture.md`, `_focus-<area>.md` — CRUD global registries (`_` prefix = visual cue for persistent-global)

### Tier-exempt — TDD-cycle state file

- `.geniro/state/tdd/state-<slug>.md` — a live state file under `.geniro/state/` that does NOT belong to the tier model above. It is slug-scoped, single-writer (only the orchestrator that drives the TDD cycle writes it; the PreToolUse hook `enforce-tdd-order.sh` reads it; subagents never write it), Markdown-not-JSON, and written via a custom `mktemp` + `mv -f` atomic procedure rather than `atomic_state_write`. It carries only the current RED/GREEN/REFACTOR/IDLE phase so the hook can gate `Edit`/`Write` at the right moment (the hook reads `## phase` alone — it does not store or compare a per-cycle target path) — it is not a frontmatter-bearing durable artifact and is never passed through `validate_state_file`. Full contract: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md` §State file contract.

### No ad-hoc state files under `.geniro/state/`

Every file under `.geniro/state/` conforms to one of the canonical layouts above: `state/<skill>/<slug>/state.md`, the `state/setup/state.md` singleton, `state/handoff/from-<producer>-<branch>.md`, or the documented `state/tdd/state-<slug>.md` exception. A free-form file dropped directly under `.geniro/state/` — an ad-hoc working note such as `ci-201-verification-tracker.md`, carrying no frontmatter — is invisible to `validate_state_file`, to the SessionStart restore hook, and to the terminal-exit cleanup contract — none of those know to look for it, so it neither resumes nor gets cleaned. Route a working note like that to `.geniro/planning/<task-dir>/` (the scratch tier) instead, where the cleanup contract reaches it.

Resolve the `.geniro/` root via `lib/repo-root.sh::_geniro_repo_root` — never manufacture a second `.geniro/` root inside a linked worktree. The resolver exists precisely so multi-worktree checkouts converge on the primary worktree's root; a split root fragments the file set the restore hook can discover, so a task started under one root cannot resume against the other.

---

## Frontmatter contract

### Common base — required on every state file

| Field | Type | Example |
|---|---|---|
| `tier` | enum `T1\|T1.5\|T2\|T3` (T1 used for transient outputs that omit frontmatter; not enforced when present) | `T1.5` |
| `producer` | string | `implement` |
| `schema-version` | integer | `1` |
| `branch` | string | `feature/dark-mode` |
| `timestamp` | ISO-8601 UTC | `2026-05-19T14:30:00Z` |

### Tier-specific required

| Tier | Additional required fields |
|---|---|
| T1 | none in practice — real T1 files carry no frontmatter (§Path roots → T1) and never reach the validator. A file that nonetheless declares `tier: T1` is validated against the T1.5 field set. |
| T1.5 | `phase`, `status`, `non-resumable-actions` |
| T2 | `consumer`, `open_questions` (array; MAY be empty `[]` when producer surfaced none) |
| T3 | `concurrency` (enum `append-only\|crud`) |

### Optional everywhere

| Field | When useful |
|---|---|
| `description` | T3 user-CRUD (editor display) |
| `tags` | T3 user-CRUD (editor search) |
| `worktree` | Cross-worktree debugging — absolute path to a worktree |
| `checksum` | Manual-edit corruption detection (sha256 of body) |
| `notes` | Free-form |
| `geniro_kind` | Producer schema marker — informational only |
| `geniro_schema_version` | Producer schema-version marker — informational only. For spec.md (`geniro_kind: design-doc`) the additive-optional frontmatter blocks bump it: `m5-v2`/`m5-v3` carry `workflow_refs[]` (tracker linkage + chain enrichment), `m5-v4` carries the optional `launch_config` block (`/geniro:plan`'s pre-set of `/geniro:implement`'s launch settings; canonical `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md`). All of `m5-v1`..`m5-v4` are valid downstream; each block is additive-optional (absent = unchanged behavior). |

### T1.5 optional `approvals` array

Persisted AUQ outcomes for compaction-survival — written to T1.5 `state.md` files, and carried onto T2 handoffs by the producers that write one. Only **one-time** decisions (e.g., `$ARGUMENTS` disambiguation, ship-mode). Context-dependent decisions (escalation, retry choices) are NOT persisted.

```yaml
approvals:
  - category: <category-slug>      # canonical slug
    prompt: <verbatim AUQ prompt>
    options: [<opt1>, <opt2>, ...]
    picked: <chosen option>
    at: <ISO-8601 UTC>
    asked_in_phase: <phase name>
    why: <what made this the answer>            # optional
    evidence: <file:line, quote, or command output>   # optional
    result: <what acting on the pick produced>  # optional
```

**The last three fields are optional, and they change what the record is for.** The first six let a resumed session replay a decision. They do not let it check whether the decision still holds — `picked:` alone cannot distinguish a choice that is still right from one whose premise moved. So:

- `why` — the reason this was the answer at the time, in one sentence. A later reader re-reads the reason, not just the outcome.
- `evidence` — the ground truth the reason rested on: a `file:line`, a literal quote, or a command's output. This is what makes the entry falsifiable; a `why` with no `evidence` is an assertion.
- `result` — what happened when the pick was acted on. Written after the action, so it commonly lands in a later write than the rest of the entry. Its absence on a resumed run is a signal in itself: the decision was recorded but its consequence was not, which is where an interrupted run left off.

Omit any of the three when there is nothing real to put in it. An empty `why` is better than a restatement of `picked`, and a fabricated `evidence` is worse than none — see the provenance rule below, which governs all nine fields.

**Provenance — every entry records a real decision.** Write an `approvals[]` entry only for a question actually asked and answered in a run (the AUQ's resolved answer), or as an explicitly-labeled inheritance of a prior recorded entry (e.g. `picked: "<value>" (carried from round 1)`). Never synthesize an entry for a question that was not asked: `approvals[]` is the compaction-safe record of user decisions, so a fabricated entry makes a later session auto-skip a gate against a decision the user never made — the exact failure this field exists to prevent. An inherited entry carries the inherited VALUE unchanged; recording a different value under an inheritance label is fabrication, not inheritance.

### `non-resumable-actions[]` action enum

Each entry is `{action, completed-at, <action-specific-fields>}`, where `completed-at` is a live clock read (`date -u +%Y-%m-%dT%H:%M:%SZ`) interpolated in the same write call, never model-supplied (per `atomic-state-write.md` §Timestamp sourcing). The `action` value is one of a fixed enum so the SessionStart restore hook (`hooks/session-start-restore.sh`) can render a per-action resume warning — producers emit the literal string and the hook string-matches it. This table is the single source; add a new value here and to the hook's renderer in lockstep.

**Entries record actions that completed.** An action that was skipped, refused, or failed never becomes an entry, and the enum is never extended to describe one (`git-commit-skipped` and the like). The restore hook renders every entry as something irreversible that already happened out in the world, so an entry describing a non-event tells the resumed session the opposite of the truth — and lands in the hook's unknown-action fallback while doing it. A skipped or failed action belongs in the state file's `## Errors` body section (schema below).

| `action` | Emitted by | Action-specific fields |
|---|---|---|
| `git-push` | `/geniro:implement` | `target`, `ref` |
| `pr-created` | `/geniro:implement` | `pr`, `url` |
| `pr-comment-posted` | `/geniro:implement` | `pr`, `comment-id` |
| `pr-review-comment-batch` | `/geniro:review` | `pr-ref`, `finding-count`, `comment-ids` |
| `pr-comment-amended` | `/geniro:review` (review-handoff.md §7.8) | `pr-ref`, `comment-id`, `kind: edit\|reply\|delete` |
| `git-commit` | `/geniro:plan`, `/geniro:implement` | `commit-sha` |
| `slack-notify-sent` | none today — reserved | `channel`, `ts` |
| `release-tagged` | none today — reserved | `tag` |

An unrecognized `action` renders via the hook's generic fallback.

The last two carry no producer: the hook renders them and `tests/hooks/session-start-restore.sh` pins that rendering, but no skill emits either one — a `.geniro/actions/` workflow that posts to Slack or tags a release is the case they were built for, and actions are stateless, so nothing writes a state file to put them in. They stay listed because the renderer is the thing this table has to match: an enum value the hook handles but the table omits is the lockstep breaking in the direction nothing detects. Wiring a producer, or removing value + branch + test together, are both fine; dropping the row alone is not.

### T2 required `open_questions` array

Producers that surface a genuine judgment call — a scope or decision question whose answer changes what the producer posts or does — write it as a structured entry. Consumers (downstream skills) gate on `status: unresolved` before any mutating action — code edits, posting to external systems, status transitions, etc. — so the skill never acts on a question the user has not yet answered.

A producer records a question here ONLY when it cannot determine the answer itself and the answer changes what the producer posts or does. It does NOT record a checkable claim (verify it instead, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md` §4) and it does NOT record a pure "how should X be fixed?" question — a finding carries its own recommended action, and the downstream fixer resolves fix specifics when it fixes.

```yaml
open_questions:
  - id: q1                                          # short stable anchor (used by AUQ chaining and resolution writes)
    source: spec-compliance                         # the reviewer dim / producer step that surfaced it
    question: "API seeder additions in-scope or split into separate PR?"  # the actual question, verbatim
    context: |                                      # OPTIONAL but RECOMMENDED — 2-6 line problem framing rendered with the question
      The PR includes 3 new seeder files under db/seeders/ alongside the API
      endpoint changes; spec.md `forbidden_actions` bars seeder modifications
      outside dedicated seeder PRs.
    evidence:                                       # OPTIONAL but RECOMMENDED — code anchors with snippets, rendered in AUQ preview
      - file: db/seeders/api_users.sql
        lines: 1-12
        snippet: |
          INSERT INTO api_users (id, email, role) VALUES ...
    options:                                        # OPTIONAL but RECOMMENDED — pre-authored options used directly by the AUQ renderer
      - id: A
        label: "In scope — keep seeders in this PR"
        description: "Seeders are required for the endpoint smoke-test; splitting would block the endpoint reviewer from running tests."
        preview: |
          ## Effect
          - 3 seeder files stay in this PR
          - spec.md `forbidden_actions` gets a per-task exception line
      - id: B     # "Split — revert seeders to a separate PR" — same shape as A (label + description + preview)
      - id: C     # "Out of scope — drop entirely" — same shape as A
    recommendation:                                 # OPTIONAL — producer's recommended option + rationale
      option_id: B
      rationale: "Spec.md is explicit; honoring it preserves PR-scope hygiene. The smoke-test data gap is recoverable via a follow-up seeder PR."
    related_findings: [F1, F4]                      # optional — finding IDs this question gates (cross-reference into ## Findings body)
    related_hypotheses: [H2]                         # optional — /geniro:debug equivalent: Hypothesis IDs this question gates
    status: unresolved                              # enum: unresolved | resolved | wontfix
    resolution:                                     # populated when status moves out of `unresolved`
      picked: "Split — revert api seeders to a separate PR"
      at: 2026-05-26T13:45:00Z
      asked_in_phase: phase-6-gate
      resolved_by: review                           # which skill ran the resolution AUQ
```

**Producer responsibilities:**
- Initialize `open_questions: []` in the handoff frontmatter; never use a free-text `## Open Questions` Markdown bucket — body sections are not machine-readable.
- Each entry has `id`, `source`, `question`, `status` set; all other fields (`context`, `evidence`, `options`, `recommendation`, `related_findings`, `related_hypotheses`, `related_comments`, `resolution`) are optional. `related_hypotheses` is the `/geniro:debug`-producer equivalent of `related_findings` — it links a question to Hypothesis IDs from the debug run's `## Hypotheses` body; `related_comments` is the `/geniro:resolve`-producer equivalent — it links a question to the review-thread `thread_id`(s) that raised it.
- **Fill `context` + `evidence` + `options` + `recommendation` whenever feasible** — they're the substrate the consumer renders into a rich, self-contained chat explanation per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering. A bare `question:` field leaves the consumer to synthesize options at render time (legacy fallback), which produces terse AUQs that erode user trust.
- When the question gates a reviewer finding, populate `related_findings` so the consumer can cross-reference into the body `## Findings` section for additional detail (Confidence / Origin).
- IDs are stable within a single handoff file (q1, q2, …); they may collide across handoffs.

**Consumer responsibilities:**
- Before any mutating action that depends on the handoff (Edit/Write in /geniro:implement; status transitions in /geniro:implement Phase 3 Ship), check `open_questions[].status`. If any entry is `unresolved`, resolve the unresolved entries one per `AskUserQuestion` call, fired in sequence — message-first render before each per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering; cap-extension applies only within a single entry whose options exceed 4, never to batching entries into one call. Persist each answer back to the producer's file via `atomic_state_write`, then proceed.
- A consumer that finds `unresolved` entries and ships anyway is a contract violation.
- **`open_questions: []` clears the gate; a missing key does not.** The empty array is the producer's statement that it surfaced none — `${CLAUDE_PLUGIN_ROOT}/skills/_shared/skip-visibility.md` §The assessed sentinel in array form, and the reason the key is required rather than optional. A handoff with no `open_questions` key at all is one whose producer never reached the step that would have written it, so whether ambiguity exists is unknown — and this gate stands in front of edits to the user's tree. Say what is missing, then fire one `AskUserQuestion` (header: `"Missing key"`) — "Re-run the producer" / "Proceed without it" — persisted to `approvals[]`. Reading a missing key as "no questions" is the failure this distinction exists to prevent.

**Free-text body fallback:** the body section `## Open Questions` MAY mirror the frontmatter as a human-readable view (Markdown bullet list with `id` anchors), but the frontmatter is the source of truth. Validators check the frontmatter only; the body is informational.

**Secret redaction — every free-form T2 field.** Before the `atomic_state_write`, pipe every free-form text value bound for the handoff through `redact_secrets` (`source "${CLAUDE_PLUGIN_ROOT}/lib/redact-secrets.sh"`; API in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/redact-secrets.md`). The values, grouped by the structure that owns them:

- Each `open_questions[]` entry — `question`, `context`, `evidence[].snippet`, `options[].description`, `options[].preview`, `recommendation.rationale`.
- Each finding block in the body — the `Evidence:` codeblock, `Suggested fix:`, and `Verification-evidence:`. `Verification-evidence:` is a literal quote lifted from the cited `file:line`, present on every kept CRITICAL / HIGH / MEDIUM finding, so it carries the same exposure as the reviewer's own `Evidence:` codeblock beside it.
- Each `comment_resolutions[]` entry — `reply_draft`.

A security finding that quotes a hardcoded credential otherwise persists the secret verbatim in a file that outlives the run and ships to every downstream consumer; the `[REDACTED:…]` placeholder still locates the leak. Structured fields (ids, paths, enums, timestamps) skip the pipe. A new free-form field added to any of these structures joins this list in the same edit — the pipe is defined by what the value is, not by what happened to be enumerated when the field was introduced.

### Producer-specific extensions

Producers MAY add fields (e.g., `task_slug`, `mode`, `effort_tier`, `round`, `risk-tier`). Constraints:
- Does not shadow a common-base or tier-specific field name with different semantics — a shadowed name makes every reader's parse ambiguous.
- Is documented in the producing skill's SKILL.md / reference-file frontmatter example block.
- The validator silently passes them through — only required-field presence and enum values are checked.

**`/geniro:review` producer-specific fields:**

- `spawn_dims_declared: [<dim-slug>, ...]` — declared parallel-spawn list, written at Phase 2 entry before the batch fires. Consumed by Phase 4 §4.0 verification gate (declared-vs-actual diff). **Shared field:** `/geniro:implement` writes the same field at its own Phase 3 Step 1 — see the `/geniro:implement` entry below.
- `spawn_dims_count: <int>` — denormalized length of `spawn_dims_declared`, same shared-field note.
- `custom_reviewers: [{slug, paths_matched, model, source_path, severity_default, requires_context}, ...]` — discovered in Phase 1.5 §1.5.4 via `load-custom-reviewers.md`. Carries every short spawn-spec scalar; the unbounded `criteria-content` body is deliberately absent, because `/geniro:review`'s state file and its T2 handoff are the same physical file (`from-review-<branch>.md`), and persisting a user file's whole body into it would pay that cost twice. Phase 2 re-reads `source_path` for the body instead. Consumed by Phase 2 to merge into the spawn batch.
- `mechanical_prepass_attempted: {<check-id>: <findings|clean|error>, ...}` — per-check outcome map written by Phase 1.5 §1.5.6/§1.5.7. Consumed by the Phase 4 §4.0a declaration check. A closed value set matters: `clean` is a recorded outcome, so a healthy diff that produced no findings is distinguishable from a check that was declared and never reached.
- `report_status: <draft|final>` — whole-report lifecycle. Phase 5.1 writes `draft` so a mid-gate compaction still recovers the findings; the Phase 6 finalize step (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §3.5) flips it to `final` only after the Pre-gate (open questions) and the open-decision gate clear. The Action gate's handoff option and the §7.0 Post-drill guard both require `final`. **Back-compat (single source of this rule): a missing `report_status` reads as `final`** — mirrors the `step0_status: missing → resolved` precedent, so handoffs produced before this field exists are not retro-blocked. Other sites reference this rule; they do not restate it.
- `deep-mode: <true|false>` — set by the `--deep` flag or the Deep chooser pick; the activation also persists to `approvals[]` category `deep_mode_choice`. Multiplies the reviewer/verifier fan-out (angle-diverse passes + signal-gated verification) per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §3. Missing reads as `false`. **Shared field:** `/geniro:plan`, `/geniro:implement`, and `/geniro:debug` carry the same `deep-mode` + `deep_mode_choice` pair (canonical cross-skill contract: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §2); each deepens its own analysis phases per its `deep-mode-reference.md`. The field is therefore defined once here and not restated per producer section.

**`/geniro:implement` producer-specific fields:**

- `spawn_dims_declared: [<dim-slug>, ...]` / `spawn_dims_count: <int>` — same two fields as the `/geniro:review` entry above, written at this skill's own Phase 3 Step 1 before its fixed-grid reviewer batch fires. Consumed by Phase 3 Step 2's Round-1 declared-vs-returned check.
- `reviewed_file_set: [<path>, ...]` — frontmatter list of the CHANGED_FILES the Phase 3 fix loop's final round's reviewer-agents and adversarial-tester actually received, written at the loop's exit (`${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 3: Bounded fix loop") in the same `atomic_state_write` call as the `## Deferred Findings` body section. Ship's commit-time review-coverage guard (same file, §"Commit + Push + PR" Step 2) diffs live CHANGED_FILES against it before staging.

**`/geniro:debug` producer-specific `authored_tests` array (T2 handoff only):**

Carries every F→P reproduction test authored during the debug run as the machine-readable source-of-truth for downstream consumers. The body `**Reproduction test:**` line (scientific mode) and `**Test file:**` lines (adversarial mode) remain as a human-readable mirror; consumers prefer this frontmatter array and fall back to body parse only for legacy handoffs that predate it (those without an `authored_tests` frontmatter array).

```yaml
authored_tests:
  - id: t1                            # short stable anchor (t1, t2, ...) — collision-safe within one handoff
    path: tests/api/handler.test.ts   # relative to git rev-parse --show-toplevel of debug-source-worktree
    intent: "covers H2 — null-pointer on empty payload"   # one-line description of what the test guards
    mode: scientific                  # enum: scientific | adversarial
    f_to_p_status: red-on-current     # enum: red-on-current | green-under-patch | red-on-current+green-under-patch | escape-hatch
    related_hypotheses: [H2]          # optional — Hypothesis IDs from `## Hypotheses` body (scientific mode)
    targeted_source: src/api/handler.ts  # optional — production file the test targets (used in adversarial mode for triage)
    confidence: high                  # optional — adversarial mode only (high | medium | low)
```

**Producer responsibilities:**
- Initialize `authored_tests: []` in the handoff frontmatter even when no test was authored (e.g., scientific path B "accept as documented limitation" or adversarial zero-red-tests terminal). The empty-array form lets consumers distinguish "no tests by design" from "field absent in legacy handoff" — the array-shaped case of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/skip-visibility.md` §The assessed sentinel.
- One entry per authored test file. If a single test file holds multiple test cases, one entry covers it; the `intent` field summarizes the file-level guarantee.
- `path` is repo-root relative. Consumers re-resolve against their own `git rev-parse --show-toplevel` to handle cross-worktree consumption.
- `mode` matches the handoff's top-level `mode:` discriminator (`scientific` for `from-debug-<branch>.md`, `adversarial` for `from-debug-adversarial-<branch>.md`).
- Scientific mode `f_to_p_status: escape-hatch` paired with an `intent: "escape-hatch: <rationale>"` is valid — surfaces the §2.4 hard-to-mock chain case where the bug cannot be verified without temporary production edits (which are reverted before escalation).

**Consumer responsibilities:**
- Read `authored_tests[]` before falling back to body-string parsing. The shared consumer protocol at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/debug-handoff.md` codifies the prefer-frontmatter / fallback-to-body order.
- Resolve each `path` against the current `git rev-parse --show-toplevel` and bucket as PRESENT / MISSING. On MISSING, surface the cross-worktree relocation suggestion from `_shared/debug-handoff.md` §Step 4 Case B1 — never auto-execute `git checkout <debug-source-branch> -- <path>`.
- The array is informational, not a gate — consumers do NOT block on its presence or content. The `open_questions[]` gate remains the only Edit/Write blocker for /geniro:implement Phase 1.

**`/geniro:resolve` producer-specific fields:**

- `spec_path: <repo-relative path>` — the `spec.md` this run authored, at `.geniro/state/resolve/<slug>/spec.md`. Required on every `from-resolve-<branch>.md`. `/geniro:implement` follows it as the FIRST entry of its spec-discovery walk (`${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 1: Spec discovery walk-list") — the only route to a spec that lives outside `.geniro/planning/`. Without it a `RESOLVE_HANDOFF` auto-continue falls into inline-task mode and never loads the spec's Steps or its §9 `verify:` lines. Producers that author no spec (`/geniro:review`, `/geniro:debug`) omit the key; a consumer treats absent-or-unresolvable as fall-through, not an error.

**`/geniro:resolve` producer-specific `comment_resolutions` array (T2 handoff only):**

The `from-resolve-<branch>.md` handoff (`producer: resolve`, `consumer: implement`) carries, alongside the common `open_questions[]`, one entry per review-comment item whose verdict produces a reply. `/geniro:implement` reads it at its Ship sub-step to post the drafted replies and resolve the threads. The `## Comment Resolution Map` body section is the human-readable mirror; this array is the source of truth. CI-check items do NOT appear here — a failing check has no thread to resolve and goes green on the next push; it lives only in the spec Steps.

```yaml
comment_resolutions:                 # MAY be []; only review-comment items appear
  - thread_id: PRRT_kwDOExample      # reviewThread node id — for the resolveReviewThread mutation
    comment_id: 1234567890           # top comment databaseId — for the reply endpoint
    source: review-comment           # always review-comment here
    author: coderabbitai[bot]        # bot logins keep their suffix
    path: api/users.ts               # cited location (null when the comment is not line-anchored)
    line: 42
    verdict: fix                     # fix | answer-only | wontfix
    reply_draft: |                   # the text to post on the thread
      Addressed in <commit> — guarded the null deref; see api/users.ts:42.
    resolve_after_fix: true          # fix → true (post + resolve); answer-only / wontfix → false (post only)
    verify: "pnpm test users.spec"   # passes ⇒ the fix landed (mirrors the spec §9 criterion); null if none
    fix_step_anchor: step-3          # the spec Step that implements the fix; null for answer-only / wontfix
    status: pending                  # pending | posted | skipped (set by the consumer)
```

**Producer responsibilities (`/geniro:resolve`):**
- Initialize `comment_resolutions: []` even when empty, so the consumer distinguishes "no replies by design" from "field absent in a non-resolve handoff".
- One entry per review-comment item with verdict `fix` / `answer-only` / `wontfix`. `needs-clarification` items go to `open_questions[]` instead (resolved later, they may re-enter as a `fix`).
- `verdict: fix` sets `resolve_after_fix: true`, a `fix_step_anchor` pointing at the spec Step, and a `verify:` mirroring that Step's §9 acceptance check (or null when none exists). `wontfix` / `answer-only` set `resolve_after_fix: false` and null `fix_step_anchor` / `verify`.
- The I/O shapes for the eventual reply + resolve live in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/pr-threads.md` (write side).

**Consumer responsibilities (`/geniro:implement`):**
- Parse `comment_resolutions[]` at Phase 1 Step 12 alongside `open_questions[]`; stash it for the Ship sub-step. It is NOT an Edit/Write gate — only `open_questions[]` blocks editing.
- At the Ship sub-step, for each `verdict: fix` entry, re-verify the fix landed (run `verify:`, else confirm `fix_step_anchor`'s files are in the pushed diff). Not landed → set `status: skipped`, never resolve.
- Gate the batch behind ONE AskUserQuestion (external write, like `git push`), then via `pr-threads.md` write side post `reply_draft` and resolve the thread when `resolve_after_fix: true`. Mark `status: posted`; append a `pr-comment-posted` entry to `non-resumable-actions[]`.
- A handoff with no `comment_resolutions[]` (any non-resolve producer) skips the Ship sub-step entirely.

---

## Format rules

- Frontmatter starts on line 1 with `---`.
- Closing `---` on its own line.
- Empty line after closing fence before body.
- Body MAY use `## Section` headers; per-skill conventions for content.

### `## Errors` — the unanswered-gate entry

Neither existing frontmatter array can hold a question that fired and got no reply: `approvals[]`'s Provenance rule (§T1.5 optional `approvals` array, above) forbids synthesizing an entry for one never answered, and `open_questions[]` is a producer→consumer handoff, not a same-run resumption record. Write it here instead, in the shape the restore hook already parses:

```markdown
## Errors
- ts: <ISO-8601 UTC>
  tool: AskUserQuestion
  detail: <question header, or a short phrase naming the gate>
  error: "fired; turn ended before an answer arrived"
  attempted_fix: "none yet — discharged only by re-firing this exact question"
  status: unresolved                 # → resolved once the tool returns a real answer to THIS question
```

Discharge conditions, what does not count as an answer, and the owning site for the `unresolved → resolved` flip are canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions.

---

## Concrete examples

### T1.5 — all three layouts

```yaml
---
tier: T1.5
producer: implement
schema-version: 1
branch: feature/dark-mode
timestamp: 2026-05-19T14:30:00Z
phase: implement
status: in-progress
non-resumable-actions: []
---

## Phase log
- analyze done at 14:25:00Z
- implement started at 14:30:00Z
```

The session-bound (`/geniro:debug` etc.) and singleton (`/geniro:setup`) layouts use the identical required-field set; they differ only in `producer:` and optional producer-specific extensions (e.g. `geniro_kind: debug-state`, `mode: init`).

### T2 — handoff

```yaml
---
tier: T2
producer: review
schema-version: 1
branch: feat/ci-277
timestamp: 2026-05-26T13:30:00Z
consumer: implement
open_questions:
  - id: q1
    source: spec-compliance
    question: "API seeder additions in-scope or split into separate PR?"
    related_findings: [F1]
    status: unresolved
  - id: q2
    source: architecture
    question: "Accept parallel CwCaseCardAdapter chrome or refactor to delegate?"
    related_findings: [F3]
    status: unresolved
---
```

### T3 — CRUD (instructions)

```yaml
---
tier: T3
producer: user
schema-version: 1
branch: main
timestamp: 2026-05-19T14:30:00Z
concurrency: crud
description: "TypeScript strict-mode style rules"
tags: [typescript, style]
---
```

### T3 — append-only (learnings sidecar)

`learnings.jsonl` itself is JSONL with no frontmatter. The sidecar `learnings.jsonl.meta.yaml` carries the tier metadata:

```yaml
---
tier: T3
producer: implement
schema-version: 1
branch: main
timestamp: 2026-05-19T14:30:00Z
concurrency: append-only
schema-ref: "canonical L2 entry schema"
---
```

Per-line JSONL schema (canonical L2 entry schema): `ts`, `producer`, `scope`, `summary`, `tags`, plus optional `body`, `links`, `dedup_key`, `supersedes`, `deprecated`, `trust`, `type`, `ext`.

---

## Validation rules (summary)

`validate_state_file` enforces the frontmatter contract above (fence on line 1, required fields per tier, `schema-version: 1`, optional `checksum` / `worktree` checks); the ordered check list, exit codes, and recovery AskUserQuestion live in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md`. JSONL files use line-by-line validation: malformed lines logged and skipped.

---

## Slug rule (T1.5 session-bound layouts)

Compute the session-bound slug per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Slug rules.
