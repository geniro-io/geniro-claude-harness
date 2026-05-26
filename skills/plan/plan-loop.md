# Plan Loop

Canonical phase pattern for `/geniro:plan`.



**Defect-fix scope:** D1 (no auto-commit at Phase 6 — defer to Phase 8), D2 (state.md mandatory throughout), D3 (Phase 0 Refine path removed — DESIGN_DOC → «start fresh»), D4 (Phase 1 Echo contract replaces unverifiable ≥2-citation rule), D5 (Phase 9 hand-off menu = 2 options replaces 4).

This file is the single source of truth. Skills cite this file; do NOT inline-paste the loop logic.

---

## HARD-GATE

> Do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action until the Phase 8 user-approve AUQ has been answered «Approve». The gate is binding for Phases 0–8. The Phase 9 hand-off is the only authorized release point.

---

## Phase 0 — Mode detect

State.md `phase: mode-detect` during this phase. Light cost — a single design-doc-detect.md helper call.

### 0.1 $ARGUMENTS resolution

Use `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md` helper unchanged. Returns:

- **IDEA(topic)** — free-form text; proceeds to Phase 1 with topic as initial context.
- **DESIGN_DOC(path)** — existing design doc; flows to AUQ.
- **CODE_REFERENCE(path)** — error per design-doc-detect.md per-consumer table: «code reference passed to /plan; pass a topic or design-doc path. Did you mean /geniro:implement <path>?». Exit without writing state.md.
- **None** (empty $ARGUMENTS) — fires empty-argument AUQ:
 - `header`: "Topic"
 - `question`: "What do you want to plan?"
 - `options[]` (single-select, 3 options + Other free-text): "New feature" / "Existing problem to solve" / "Cancel"
 - Non-empty answer (via a picked option OR free-text Other) → IDEA mode; «Cancel» → terminal without state.md.
 - Persist outcome to `approvals[]` with `category: disambiguate_arguments` .

### 0.2 DESIGN_DOC mode AUQ (D3 fix — Refine path removed)

Fire `AskUserQuestion` with:
- `header`: "Existing design doc"
- `question`: "Design doc already exists at `<path>`. What now?"
- `options[]` (single-select, 2 options):
 - **Start fresh with this as context** (Recommended) — load the doc into Phase 1 explore context; run the full 10-phase loop (Phases 0–9; Phase 2 fires only when the UI trigger matches per §"Phase 2 — Visual Companion"); emit a new spec.md at a fresh task-dir.
 - **Cancel** — exit without writing state.md.

**On "Start fresh"** → flow to Phase 1 with the doc body inlined into Phase 1 research-agent prompts under a `## Prior Design Doc` section. The doc is NOT used as section template (D3 fix); Phase 5 uses the 10-section schema unconditionally.

**On "Cancel"** → exit immediately. Surface terminal message: "Cancelled before planning started".

### 0.3 Task-dir + state.md creation (D2 fix — state.md mandatory)

After mode is resolved (IDEA or DESIGN_DOC-fresh-start):

1. **Resolve task slug.** Inputs: $ARGUMENTS topic OR basename(design-doc) sans extension. Output: kebab-case slug ≤40 chars.
2. **Task-dir:** `.geniro/planning/<task-slug>/`.
3. **state.md:** `.geniro/planning/<task-slug>/state.md`. Write via `atomic_state_write`. Full frontmatter + body template (frontmatter fields `tier`/`producer`/`branch`/`phase`/`status`/`non-resumable-actions`/`approvals`/`task_slug`/`mode`; body sections `# State: <topic>` / `## Inputs` / `## Tool log` / `## Errors` / `## Open Questions`) in `${CLAUDE_SKILL_DIR}/plan-auq-reference.md` §1.
4. **Transition.** `phase: explore` via `atomic_state_write`.

### 0.4 Cancel handling

If state.md already created when user cancels (e.g., deep cancel via Other): write `phase: aborted` + `## Termination reason: user-cancelled-at-phase-0` via `atomic_state_write` before exit.

---

## Phase 1 — Explore

State.md `phase: explore` during this phase.

### 1.1 Memory layer loading

At Phase 1 entry, load **L4 + L3 + L2** (full tier, NOT rules-only):

- **L4:** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: plan`, `LOAD_TIER: pipeline`, `MODE: refresh`. Scope = `plan` + `global` + `code-style`.
- **L3:** `source "${CLAUDE_PLUGIN_ROOT}/lib/load-semantic.sh" && load_semantic`. Default top-2 (`_project.md` + `_CODEBASE_MAP.md`). Fingerprint drift check fires; surface drift to user.
- **L2:** `source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh" && query_learnings --tag <inferred> --scope <topic-area> --limit 5`. Skipped if topic is too generic to infer tags.
- **Cross-layer resolution:** `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md` protocol if L4/L3/L2 disagree.

Loading all three layers ensures research agents have full context — prior decisions (L2), codebase map (L3), and user rules (L4) — preventing repeated rediscovery.

### 1.2 Effort-tier-scaled research spawns

Detect effort tier from $ARGUMENTS shape using `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`:

| Tier | Spawns |
|---|---|
| Trivial (single-file config tweak, typo fix, rename) | 1 agent OR 0 if obviously scope-bound |
| Medium (feature addition touching 2-5 files) | 2 agents (existing-impl + integration-surface) |
| Big (subsystem-level change ≥10 files) | 3-4 agents (subsystem-A + subsystem-B + cross-cutting + conventions) |

Spawn general-purpose research agents — `Agent(description="Research: <facet>", disallowedTools=["Edit", "Write", "NotebookEdit"], prompt="""...""")` — and OMIT both `subagent_type` (omission defaults to general-purpose, matching the /investigate Phase 2 spawn idiom) AND `model=` (the orchestrator's session tier propagates). Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` (6 required fields). Do NOT use the built-in `Explore` subagent: its narrow lookup contract (Haiku 4.5, `thoroughness: quick|medium|very thorough` queries) refuses heavyweight 6-field prompts and is unsuited for the structured `[{file, lines, observation}]` output schema this phase requires.

All spawns in a single assistant response per the parallel-spawn rule. Per-spawn output schema: `[{file, lines, observation}]`; cap ~4000 chars (truncate with marker).

### 1.3 Echo contract (D4 fix — replaces unverifiable ≥2-citation rule)

Each Phase 1 research spawn writes a structured entry to state.md `## Tool log` via `atomic_state_write`:

```yaml
## Tool log
- ts: 2026-05-17T10:42:13Z
 tool: Agent
 detail: "Research: existing auth flow integration points"
 status: ok
 summary: "found 3 files, 1 convention pattern"
 citations:
 - src/auth/oauth.ts:42-58
 - src/auth/__tests__/oauth.test.ts:14-29
 - src/middleware/session.ts:88-101
```

Phase 7 validator ( check #3) requires ≥1 Agent entry with `status: ok` per effort tier (Trivial ≥1 OR explicit "scope-bound, no exploration needed"; Medium ≥2; Big ≥3). The Echo contract makes "no related code found" auditable via SessionStart re-injection.

### 1.4 Workflow refs fetch (tracker linkage)

If `$ARGUMENTS` contains a tracker reference (Linear URL/ID, Jira key, GitHub issue URL, Asana task URL), fetch via the matching MCP and persist to state.md `## Workflow Refs` body section. This block is the source-of-truth for Phase 6 frontmatter assembly.

**Detection:** existing workflow-plumbing already detects tracker references at Phase 1 entry (file-scoped `.geniro/workflow/<kind>.md` defines per-tracker patterns). When a match resolves to `kind=<linear|jira|github-issues|asana>` and `issue_id=<id>`:

1. Fetch via the matching MCP (`mcp__linear__get_issue` for Linear, etc.). If MCP unregistered, log a `## Errors` entry and continue without persistence — graceful degrade per existing pattern.
2. Append to state.md `## Workflow Refs` via `atomic_state_write`:

```yaml
## Workflow Refs
- kind: linear
  issue_id: CI-303
  url: https://linear.app/.../CI-303/...
  fetched_at: 2026-05-26T10:42:13Z
  title: "..."
  suggested_branch: ci-303-...
  status: Todo
  parent_ref:
    kind: linear
    issue_id: CI-300
    url: ...
```

3. The fetched payload feeds Phase 1 research-agent prompts (existing behavior) AND becomes the canonical source for Phase 6 frontmatter copy. Skipped when `$ARGUMENTS` carries no tracker reference — pure inline-task /plan emits a spec.md without `workflow_refs[]`.

### 1.5 Transition to Phase 2

Model synthesizes findings into a brief inline summary held in context (no separate artifact). The summary feeds Phase 2 UI trigger detection, Phase 3 question generation, and Phase 5 section authoring. State.md `phase: visual-companion` written before Phase 2 entry (`phase: clarify` if Phase 2 trigger doesn't fire).

**Skip to Phase 4 if Trivial:** when effort tier is Trivial AND research returned 0-1 findings AND topic is a narrow text-edit, Phases 2 + 3 are skipped. Write a one-line note to state.md `## Open Questions`: "Phases 2-3 skipped — trivial task, no ambiguity surfaced".

---

## Phase 2 — Visual Companion (UI-conditional)

State.md `phase: visual-companion` during this phase. Fires only when a UI trigger matches.

### 2.1 Trigger detection

Fire Phase 2 if **either** condition holds:

- Phase 1 explore-agent surfaced any path matching the UI-file detection rule in `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` §UI-file detection (globs for `components/pages/app/views/ui` directories + JSX/TSX/Vue/Svelte/CSS/SCSS extensions), OR
- $ARGUMENTS topic string contains a UI noun: `page`, `screen`, `modal`, `form`, `dashboard`, `button`, `view`, `panel`, `widget`.

No trigger → skip Phase 2 entirely. Transition `phase: clarify` and proceed to Phase 3.

### 2.2 UI preview procedure

Trigger fires → run the procedure documented at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` end-to-end. That helper spawns the UI description agent, presents the textual preview, runs the revision loop (max 3 rounds), and returns the approved description.

Caller contract (this skill's side):
- Provide the predicted affected-files list (from Phase 1 echo entries with UI-file matches), $ARGUMENTS topic, 1-2 exemplar UI files (path-only — agent reads them itself).
- Destination path: hold in-memory as Phase 5 substrate. Do NOT write a separate `ui-preview.md` artifact at the planning task-dir — the approved description feeds Phase 5 section 6 (Steps) + section 9 (Validation) directly.

### 2.3 Persistence

The approved description is appended to state.md `## UI Preview` body section via `atomic_state_write`:

```markdown
## UI Preview
<approved description verbatim, ≤200 lines per ui-preview-gate.md output constraint>
```

Phase 5 section 6 / section 9 authoring cites this block as substrate. Phase 7 validator does not gate on `## UI Preview` presence (Phase 2 is conditional; absence is valid).

### 2.4 Routing-out signal

If the user picks "Adjust the plan instead" at any revision round of ui-preview-gate.md, return to Phase 1 with the user's feedback inlined into research-agent prompts. State.md transitions `phase: explore` (re-enter) — round-count not incremented since the user is correcting the plan substrate, not the UI preview itself.

---

## Phase 3 — Clarifying questions

State.md `phase: clarify` during this phase.

### 3.1 Question generation

Model identifies up to 5 highest-leverage ambiguities from:
- Phase 1 research findings ("found 3 auth flows — which one is the integration surface?")
- L2 query-learnings ("prior decision favored Approach X — does it apply here?")
- L4 code-style rules

Questions MUST be grounded in Phase 1 findings (D4 fix). Generic «what tech stack?» questions are forbidden — the model can answer those from L3 `_project.md`.

### 3.2 One-at-a-time AUQ shape

Fire questions sequentially, **never** as a multi-question form. Each AUQ uses `header` ≤12 chars, `question` 1-2 sentences ending in a question mark, `options[]` of 2-4 explicit choices, `multiSelect: false` unless explicitly multi-select. Include a "Skip — proceed with stated assumption" option as the last choice when applicable. **Every option carries a `preview` field** with concrete consequence content (code anchor / config diff / behavior trace, ≤6 lines per preview) — empty `Approve / Revise / Skip` options waste user attention. Full literal example with preview content in `${CLAUDE_SKILL_DIR}/plan-auq-reference.md` §2.

### 3.3 Persistence

Each answered AUQ → append entry to state.md frontmatter `approvals[]` via `atomic_state_write` BEFORE proceeding to the next question. Entry shape (category `clarify_<dim>` / prompt / options / picked / at / asked_in_phase) in `${CLAUDE_SKILL_DIR}/plan-auq-reference.md` §2.

On compaction-resume, the SessionStart re-injector renders `approvals[]` and the model re-reads it to skip already-answered questions.

### 3.4 Cap exhaustion

If a 6th clarification arises, force consolidation OR proceed to Phase 4 with stated assumptions. The 5-AUQ cap is a quality-first signal — more than 5 means Phase 1 underspecified OR the topic is too vague for a single /plan session.

---

## Phase 4 — Approaches

State.md `phase: approaches` during this phase.

### 4.1 Approach generation

Model synthesizes Phase 1 explore + Phase 3 answers into 2-3 distinct approaches. Each approach:
- **Name** (3-5 word label)
- **Summary** (2-3 sentences)
- **Trade-off** (1 sentence: gain vs give-up)
- **Effort estimate** (Trivial / Medium / Big per effort-scaling.md)

### 4.2 AUQ shape

Single-select; `Recommended` first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md`. Header "Approach"; each option carries an `description` (summary + trade-off, ≤2 lines) AND a `preview` field containing an ASCII data-flow / architecture sketch (5-10 lines) + key code identifier (new class/function/file name) + dominant tradeoff one-liner. Full literal example with preview content (Service-layer fan-out vs in-process Promise.all) in `${CLAUDE_SKILL_DIR}/plan-auq-reference.md` §3.

### 4.3 Persistence

User pick → append to `approvals[]` with category `approach_choice`. Other approaches captured to body section `## Considered Alternatives`.

** L2 emit on rejection signal:** AFTER appending to `approvals[]`, source `${CLAUDE_PLUGIN_ROOT}/lib/emit-rejection.sh` and invoke:

```bash
emit_rejection_if_signal \
 "/geniro:plan" "<topic>" "approach_choice" \
 "<recommended approach label>" "<picked label>" "<recommended label>"
```

Where `<topic>` = $ARGUMENTS topic OR `global` if not inferable. Helper detects whether picked != recommended OR picked is explicit-cancel/no/skip and emits L2 `user_rejected_suggestion` only when signal fires. Acceptance (picked == recommended, no rejection keyword) is a no-op.

**Read side:** Phase 1 query-learnings on /plan entry already runs once. Extend its consumers to surface entries with `type=user_rejected_suggestion AND tags includes 'approach_choice'` matching the current topic — display as «User previously rejected <suggestion> on <ts>» so the orchestrator can re-rank or omit the rejected approach from AUQ.

Example body:

```markdown
## Considered Alternatives

### Inline Refactor (rejected)
Summary: ...
Trade-off: smaller surface change, but locks into existing module shape.
Why rejected: violates new boundary established in Q3 2026 architecture review.
```

`## Considered Alternatives` is copied to spec.md body verbatim in Phase 6. /implement reads but not gates on it.

---

## Phase 5 — Section approval

State.md `phase: section-approve` during this phase.

### 5.1 Section template

Use the **fixed 10-section schema** detailed in (and reproduced in `skills/plan/spec-template.md`):

1. Objective
2. Scope — Included
3. Scope — Excluded
4. Assumptions
5. Risks
6. Steps
7. Tools Required
8. Approval Points
9. Validation
10. Rollback-Recovery
11. Done Condition (header «## 11.» — schema counts 10 sections starting at ## 1; this is section #10 by count)

Every spec.md has exactly the same 10 sections — schema-stable downstream consumers.

For Trivial tasks, sections 4 / 5 / 10 may have body content «none — task scope precludes» with brief rationale. Headers MUST exist; bodies MAY be «none with rationale».

### 5.2 Per-section AUQ — incremental authoring

One AUQ per section, sequentially. **Do NOT pre-fill all 10 sections in a batch** — pre-fill makes per-section approval redundant. Section N+1 is authored only after section N approval. Procedure: (1) author section N inline using Phase 1 research + Phase 3 clarifying answers + Phase 4 picked approach + (when present) Phase 2 UI Preview as substrate; (2) fire AUQ with header `"Section: <name>"` and three options (Approve / Revise — I'll describe / Skip — accept as-is with warning) each carrying a `preview` field with concrete content; (3) persist pick to `approvals[]` with category `section_<id>`; (4) transition to section N+1.

Max 3 revisions per section. Concrete-example content per section type lives in `${CLAUDE_SKILL_DIR}/plan-reference.md`. Full procedure + Option preview templates in `${CLAUDE_SKILL_DIR}/plan-auq-reference.md` §4.1.

### 5.3 Milestone-mode

Fires BEFORE Phase 6 entry when effort tier is Big AND section 6 "Steps" has ≥10 discrete steps OR estimated wall-time ≥1 day. AUQ header "Milestone slicing" with options "Slice into milestones" (Recommended for Big) and "Keep as a single spec". On slice pick, follow-up AUQ proposes 3-7 milestone names; Phase 6 emits sibling `milestone-N.md` files alongside spec.md. Persist to `approvals[]` with category `milestone_slice`. Hand-off (Phase 9) then offers `/implement milestone 1`. Full AUQ shape + follow-up procedure in `${CLAUDE_SKILL_DIR}/plan-auq-reference.md` §4.2. Milestone-mode does NOT fire for Medium/Trivial.

---

## Phase 6 — Write spec.md

State.md `phase: write-spec` during this phase.

### 6.1 Write contract

Path: `.geniro/planning/<task-slug>/spec.md`.

Content: schema (10 sections) + frontmatter with goal block + optional `workflow_refs[]` + body sections (`## Considered Alternatives` from Phase 4, optional `## Milestones` from ).

**Frontmatter assembly — `workflow_refs[]`:** copy state.md `## Workflow Refs` block (populated by Phase 1.4) into spec.md frontmatter `workflow_refs:` field verbatim (YAML re-emission). Skip when state.md `## Workflow Refs` is empty / absent — `workflow_refs:` is then omitted from spec.md frontmatter entirely (the field is OPTIONAL per `${CLAUDE_SKILL_DIR}/spec-template.md` §workflow_refs).

Frontmatter MUST carry `geniro_schema_version: m5-v2` when `workflow_refs:` is present. For pure inline-task /plan with no tracker linkage, `m5-v1` and `m5-v2` are both valid (downstream readers accept both).

Use the `Write` tool. The plan-mode mutation guard allows `Write` only under `.geniro/planning/**` AND `.geniro/state/**` — a write to anywhere else is blocked at PreToolUse.

After writing spec.md, append a `## Tool log` entry to state.md via `atomic_state_write`:

```yaml
- ts: 2026-05-17T11:08:00Z
 tool: Write
 detail: ".geniro/planning/<slug>/spec.md"
 status: ok
 result_ref: "<bytes-count>"
```

### 6.2 NO auto-commit (D1 fix)

`git commit` does NOT fire at Phase 6 exit. It is deferred to Phase 8 post-approval to avoid polluting git history with per-revision commits.

The `git commit` is deferred to Phase 8 post-approval. At Phase 6 exit, spec.md sits unstaged on disk; state.md `phase: validate` written before Phase 7 entry.

### 6.3 Milestone-mode write fan-out

If milestone-mode was picked in Phase 5 , Phase 6 writes the top-level spec.md AND every `milestone-N.md` in a single phase pass. Each `milestone-N.md` follows the same schema scoped to its slice.

### 6.4 Idempotent re-entry (compaction-safe)

If Phase 6 is re-entered after compaction, the model:
1. Reads state.md `approvals[]` — every `section_<id>` approval is present per Phase 5.
2. Re-authors spec.md content from the persisted approvals.
3. Re-writes spec.md (overwrite — `Write`, not `Edit`, since this is idempotent regeneration).
4. Re-appends a `## Tool log` entry with note `(re-entry — post-compaction regeneration)`.

---

## Phase 7 — Mechanical validator

State.md `phase: validate` during this phase.

### 7.1 Mechanical pass-through (not Opus self-prompt)

Phase 7 uses a **deterministic validator** — script-checkable rules executed orchestrator-side. No LLM round-trip per check.

### 7.2 Validator checks ( — 13 checks)

See `skills/plan/validator-checks.md` for the canonical check definitions (13 checks total). Each check returns `(check_id, status, finding_text, fix_hint)`. Run all 13 in sequence.

### 7.3 Hard-fail handling

If any check fails:
1. Write findings to state.md `## Open Questions` body as a structured list (one bullet per failed check, with `fix_hint`).
2. Re-author the failing sections (orchestrator-side: model re-reads its own draft + validator findings + `fix_hint`s, and rewrites only the failing sections).
3. Re-run validator. **Max 3 auto-revision rounds.**
4. If round 3 still fails → fire `AskUserQuestion` with header "Validator hard-fail":
 - **Accept as-is** — proceed to Phase 8 with the failed checks documented in `## Open Questions`; user has final say.
 - **Re-revise** — kick a fresh round-1 cycle (rare; usually indicates schema misunderstanding).
 - **Abort** — terminal `aborted` + `## Termination reason: phase-7-validator-hard-fail`.

### 7.4 No transition to Phase 8 if validator hard-fails

The validator is a gate, not advisory. Phase 8 user-approve MUST see a validator-clean spec.md (or one where hard-fails were explicitly accepted by the user via path A). Protects from the «user approves blind» failure mode.

---

## Phase 8 — User approval

State.md `phase: user-approve` during this phase.

### 8.1 Approval AUQ — closure

Phase 8 fires a **schema-rich AUQ** carrying fields inline in the question body.

### 8.2 AUQ shape

Header "Approve spec"; `question` body renders a multi-line schema digest (Objective from section 1 / Scope summary from sections 2-3 / Approval Points from section 8 / Risk class auto-computed from section 5 + section 7 / Rollback from section 10 / Done Condition from section 11 / touched-file glob count / approval-expiration notice). Options: "Approve — proceed to hand-off" (Recommended) / "Request changes — I'll describe" / "Abort — discard spec". Full literal question template in `${CLAUDE_SKILL_DIR}/plan-auq-reference.md` §5.

### 8.3 Revision-round escalation

Max 3 user-revision rounds (Phase 8 → re-enter affected sections in Phase 5 → re-validate in Phase 7 → re-fire Phase 8 AUQ). On round 3 exhaust, fire escalation AUQ with header "Phase 8 exhausted":
- **Accept as-is** — final answer; proceed to hand-off.
- **Re-revise (kick fresh cycle)** — full round-1 restart; rare.
- **Abort** — terminal `aborted` + `## Termination reason: repeated-failure: phase-8 revision-limit-3`.

### 8.4 Approve → git commit (D1 fix)

On user picks "Approve":

1. **Persist approval** to `approvals[]` with category `final_approve`.
2. **Flip spec.md `lifecycle: draft` → `lifecycle: approved`** in spec.md frontmatter via a fresh Write (idempotent regeneration per ; the only field changing is `lifecycle:`). Per design-doc lifecycle marker.
3. **`git commit`** fires HERE (NOT in Phase 6):
 - `git add .geniro/planning/<slug>/spec.md` + every sibling `milestone-N.md`
 - `git commit -m "plan: <task-slug> — <one-line summary from section 1 Objective>"`
4. **Append to `non-resumable-actions[]`**
 ```yaml
 non-resumable-actions:
 - action: git-commit
 completed-at: <ISO-8601 UTC>
 commit-sha: <sha>
 files: [".geniro/planning/<slug>/spec.md"]
 ```
5. **Transition to Phase 9** (`phase: handoff`).

If commit fails (pre-commit hook denial, working-tree-dirty conflict, etc.), surface a structured error to user — do NOT proceed to Phase 9 with a stale state. Fall back to escalation with the error inlined.

### 8.5 L2 emit (conditional, )

If Phase 4 had ≥2 distinct approaches AND the picked approach has a recorded trade-off rationale, emit a `decision` type entry to L2:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh"
echo '{
 "type":"decision",
 "scope":"<task-area>",
 "summary":"approach: <name>",
 "tags":[...],
 "trust":"verified",
 "ext":{"options":[...], "chosen":"<picked>", "reasoning":"<trade-off>"}
}' | emit_learning
```

Dedup + sanitization automatic.2. Skipped if Phase 4 had ≤1 approach or no trade-off rationale recorded.

---

## Phase 9 — Hand-off (, D5 fix)

State.md `phase: handoff` during this phase.

### 9.1 Hand-off menu (D5 fix — 2 options replaces 4)

Fire `AskUserQuestion` with header "Next step":

- **/implement directly** (Recommended) — exit /plan, suggest the next command. For non-milestone specs: `/implement .geniro/planning/<slug>/spec.md`. For milestone specs: `/implement .geniro/planning/<slug>/milestone-1.md`.
- **Stop — keep spec for later** — terminal exit; spec sits on disk; user resumes when ready via `/implement <path>`.

Two options: `/implement directly` or `Stop — keep spec for later`. A design doc on disk IS the backlog entry.

### 9.2 Persistence

User pick → append to `approvals[]` with category `handoff`:

```yaml
- category: handoff
 prompt: "Next step?"
 options: ["/implement directly", "Stop — keep spec for later"]
 picked: "/implement directly"
 at: <ISO-8601 UTC>
 asked_in_phase: handoff
```

### 9.3 Terminal transition

- **/implement** picked → emit a one-line directive in chat (`Next: /implement .geniro/planning/<slug>/spec.md`); do NOT auto-invoke /implement (user agency). State.md `phase: done`.
- **Stop** picked → emit a one-line directive (`Spec saved. Resume via: /implement .geniro/planning/<slug>/spec.md`); state.md `phase: done`.

Both paths terminate in `done`. SessionStart recovery treats it as completed.

---

## Definition of Done

`/geniro:plan` run is complete when:

- [ ] Phase 0 mode detection ran via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`; mode is IDEA or DESIGN_DOC-fresh-start; CODE_REFERENCE errored with corrective hint.
- [ ] state.md created at `.geniro/planning/<slug>/state.md` via `atomic_state_write` with frontmatter.
- [ ] Phase 1 loaded L4 + L3 + L2 (full tier); per-spawn Echo contract entries persisted to `## Tool log`.
- [ ] Phase 1.4 fetched `workflow_refs` via the matching MCP when `$ARGUMENTS` carried a tracker reference; payload persisted to state.md `## Workflow Refs` (skipped when no tracker reference).
- [ ] Phase 2 (Visual Companion) fired only when UI trigger matched; approved description persisted to state.md `## UI Preview` (skipped when no trigger).
- [ ] Phase 3 used `AskUserQuestion` one-at-a-time, ≤5 questions, single dimension per question; each option carried a `preview` field; each answer persisted to `approvals[]`.
- [ ] Phase 4 presented 2-3 approaches with Recommended first; each option carried a `preview` (ASCII sketch + code identifier + tradeoff); pick persisted to `approvals[]`; other approaches captured to `## Considered Alternatives`.
- [ ] Phase 5 used per-section AUQ for the fixed 10-section schema; incremental authoring (section N → AUQ → on approve author N+1); each option carried a `preview` field; each pick persisted to `approvals[]`.
- [ ] Phase 5 milestone-mode AUQ fired if Big-task detected.
- [ ] Phase 6 wrote spec.md to `.geniro/planning/<slug>/spec.md` with all three design-doc markers; `workflow_refs[]` copied from state.md when present; `geniro_schema_version: m5-v2` when `workflow_refs[]` is present.
- [ ] Phase 6 did NOT auto-commit (D1 fix).
- [ ] Phase 7 mechanical validator ran 14 checks; hard-fail surfaced findings to `## Open Questions`; max 3 auto-revision rounds respected.
- [ ] Phase 8 schema-rich AUQ fired with fields inline; user picked one of 3 options; max 3 user-revision rounds respected.
- [ ] On Phase 8 Approve: `git commit` fired; `non-resumable-actions[]` updated; L2 `decision` emit conditional fired.
- [ ] Phase 9 hand-off AUQ fired with 2 options (D5 fix); pick persisted to `approvals[]`.
- [ ] HARD-GATE released only on Phase 8 "Approve".
- [ ] Terminal state.md `phase: done` (or `aborted` with `## Termination reason` body line).

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "This task is too simple to need a design" | "Simple" projects are where unexamined assumptions cause the most wasted work. Design can be short (Phase 5 Trivial = sections 4 / 5 / 10 with body «none with rationale»); presenting and approving is mandatory. HARD-GATE applies to EVERY task. |
| "I'll skip Phase 8 user re-review, my Phase 7 validator is enough" | Validator catches mechanical defects (placeholders / contradictions / scope creep); user catches intent defects (wrong abstraction / missing constraint). Different defect classes; both required. |
| "I'll pre-fill all 10 sections upfront so the user sees the whole plan, then ask per-section approval" | Forbidden. Pre-fill makes per-section AUQ redundant — the user has already read the content; the AUQ then has nothing new to inspect. Author section N → AUQ on section N → on approve, author section N+1. Incremental authoring catches cross-section issues at the section that triggered them, not after the user has read 10 sections. |
| "Per-section AUQ options can be plain `Approve/Revise/Skip` text — the prior chat block already showed the section" | Empty AUQ options waste user attention and degrade trust ("the skill is just clicking through"). Use the AskUserQuestion `preview` field on every option to carry concrete content (UI ASCII, code snippet, behavior trace). The chat becomes a one-line "Section: X — focus an option to inspect" announcement; the AUQ IS the rendered content. |
| "I'll write the design doc with only the YAML frontmatter — that's enough" | Defense in depth requires all three markers (path + HTML comment + frontmatter). See `design-doc-detect.md` § Why defense in depth — each marker survives a different user action. |
| "Phase 4 — 4 or 5 approaches gives the user more choice" | More than 3 indicates Phase 3 didn't narrow scope; loop back to Phase 3 with a tighter scope-boundary question. |
| "Auto-commit at Phase 6 is convenient — drop a commit if Phase 8 rejects" | Rejection-induced commit-drop = forced `git reset` / `git revert`, polluting git history (every revision round would leave a commit). Phase 8 post-approve commit is a single commit per approved spec. |
| "I'll skip persisting Phase 3 clarifying answers — they're trivial" | Metaswarm anti-pattern. Compaction mid-Phase-5 loses 5 AUQs of user input. `approvals[]` persistence is non-negotiable. |
| "I'll bypass the plan-mode mutation guard for performance" | guard is a safety contract, not a perf knob. Adds <1ms per Write (path glob check). Bypass invites the failure mode the guard exists to prevent. |
| "Phase 0 Refine path saves three phases of re-work — keep it" | Refine re-derives sections from prose — structurally-lossy. Downstream consumers parse a malformed spec.md. «Start fresh with doc as context» is honest and produces a schema-clean spec.md. |
| "Hand-off menu should keep `/features add` for backlog discipline" | A «backlog» IS a spec.md saved on disk. No separate skill needed. |
| "Auto-default empty AUQ answer to the Recommended option" | Forbidden. Empty answer = upstream Claude Code bug; fall back to plain-text re-ask. Auto-default silently mutates user intent. |
| "Add a wall-time / token kill cap so runaway /plan sessions abort cleanly" | Class-A hard caps forbidden by .3 quality-first framing. has Class-B gates (Phase 3 ≤5 AUQs, Phase 7 3-round, Phase 8 3-round) — escalate to user, do not abort. |
| "Bypass git pre-commit hooks with --no-verify when committing spec.md in Phase 8.4" | Hooks fail for a reason. Investigate root cause, not bypass. CLAUDE.md-level prohibition; honors it. |
