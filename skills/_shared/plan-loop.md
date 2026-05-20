# Plan Loop (M5)

Canonical phase pattern for `/geniro:plan` (M5). Sole consumer: `skills/plan/SKILL.md`. Replaces pre-M5 `brainstorming-loop.md` (renamed via `git mv`; body rewritten against the M5 spec).

**Spec source:** `architecture/M5-plan-redesign.md` (Phase 0 §6-7, Phase 1 §8, Phase 3 §10, Phase 4 §11, Phase 5 §12, Phase 6 §13, Phase 7 §14, Phase 8 §15, Phase 9 §16; schemas §17-19; memory I/O §21).

**Defect-fix scope (M5 §5):** D1 (no auto-commit at Phase 6 — defer к Phase 8), D2 (state.md mandatory throughout), D3 (Phase 0 Refine path removed — DESIGN_DOC → «start fresh»), D4 (Phase 1 Echo contract replaces unverifiable ≥2-citation rule), D5 (Phase 9 hand-off menu = 2 options replaces 4).

This file is the single source of truth. Skills cite this file; do NOT inline-paste the loop logic.

---

## HARD-GATE

> Do NOT invoke any implementation skill, write any code, scaffold any project, или take any implementation action until the Phase 8 user-approve AUQ has been answered «Approve». The gate is binding for Phases 0–8. The Phase 9 hand-off is the only authorized release point.

---

## Phase 0 — Mode detect (§7)

State.md `phase: mode-detect` during this phase. Light cost — а single design-doc-detect.md helper call.

### 0.1 $ARGUMENTS resolution

Use `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md` helper unchanged. Returns:

- **IDEA(topic)** — free-form text; proceeds к Phase 1 с topic as initial context.
- **DESIGN_DOC(path)** — existing design doc; flows к §0.2 AUQ.
- **CODE_REFERENCE(path)** — error per design-doc-detect.md per-consumer table: «code reference passed к /plan; pass а topic or design-doc path. Did you mean /geniro:implement <path>?». Exit без writing state.md.
- **None** (empty $ARGUMENTS) — fires empty-argument AUQ:
  - `header`: "Topic"
  - `question`: "What do you want к plan?"
  - `options[]` (single-select, 3 options + Other free-text): "New feature" / "Existing problem to solve" / "Cancel"
  - Non-empty answer (via а picked option OR free-text Other) → IDEA mode; «Cancel» → terminal без state.md.
  - Persist outcome к `approvals[]` с `category: disambiguate_arguments` per М1 P-M1-1 (М5 §22.1 schema extension).

### 0.2 DESIGN_DOC mode AUQ (D3 fix — Refine path removed)

Fire `AskUserQuestion` с:
- `header`: "Existing design doc"
- `question`: "Design doc already exists at `<path>`. What now?"
- `options[]` (single-select, 2 options):
  - **Start fresh с this as context** (Recommended) — load the doc into Phase 1 explore context; run full 9-phase loop (Phases 0-9, Phase 2 DROPPED per §"Phase 2 — DROPPED"); emit а new spec.md at а fresh task-dir.
  - **Cancel** — exit без writing state.md.

**On "Start fresh"** → flow к Phase 1 с the doc body inlined into Phase 1 Explore-agent prompts under а `## Prior Design Doc` section. The doc is NOT used as section template (D3 fix); Phase 5 uses the §17 10-section schema unconditionally.

**On "Cancel"** → exit immediately. Surface terminal message: "Cancelled before planning started".

### 0.3 Task-dir + state.md creation (D2 fix — state.md mandatory)

After mode is resolved (IDEA или DESIGN_DOC-fresh-start):

1. **Resolve task slug** per M1 §Slug rules. Inputs: $ARGUMENTS topic OR basename(design-doc) sans extension. Output: kebab-case slug ≤40 chars.
2. **Task-dir:** `.geniro/planning/<task-slug>/` (M1 canonical).
3. **state.md:** `.geniro/planning/<task-slug>/state.md`. Write via M1 `atomic_state_write`. Initial frontmatter per M5 §7.3:
   ```yaml
   ---
   tier: T1
   producer: plan
   schema-version: 1
   branch: <git-branch>
   worktree: <git-rev-parse-show-toplevel>   # M1 optional, recommended для cross-worktree resume
   timestamp: <ISO-8601 UTC>
   phase: mode-detect
   status: in-progress
   non-resumable-actions: []
   approvals: []
   task_slug: <slug>
   mode: <IDEA|DESIGN_DOC>
   ---

   # State: <topic>

   ## Inputs
   - $ARGUMENTS: "<raw>"
   - mode: <IDEA|DESIGN_DOC>
   - design-doc-path (if DESIGN_DOC): <abs-path>

   ## Tool log

   ## Errors

   ## Open Questions
   ```
4. **Transition.** `phase: explore` via `atomic_state_write`.

### 0.4 Cancel handling

If state.md already created when user cancels (e.g., deep cancel via Other): write `phase: aborted` + `## Termination reason: user-cancelled-at-phase-0` via `atomic_state_write` before exit.

---

## Phase 1 — Explore (§8)

State.md `phase: explore` during this phase.

### 1.1 Memory layer loading (replaces pre-M5 LOAD_TIER: rules-only)

At Phase 1 entry, load **L4 + L3 + L2** (full tier, NOT rules-only):

- **L4:** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` с `SKILL_SLUG: plan`, `LOAD_TIER: pipeline`, `MODE: refresh`. Scope = `plan` + `global` + `code-style`.
- **L3:** `source "${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-semantic.sh" && load_semantic`. Default top-2 (`_project.md` + `_CODEBASE_MAP.md`). Fingerprint drift check fires; surface drift к user.
- **L2:** `source "${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.sh" && query_learnings --tag <inferred> --scope <topic-area> --limit 5`. Skipped if topic is too generic к infer tags.
- **Cross-layer resolution:** `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md` protocol if L4/L3/L2 disagree.

Rationale: pre-M5 /brainstorm loaded only L4 rules. The audit found Phase 1 Explore agents worked blind к prior decisions (L2) и codebase map (L3) → repeated rediscovery. M5 closes the gap.

### 1.2 Effort-tier-scaled Explore spawns (§8.2)

Detect effort tier from $ARGUMENTS shape using `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`:

| Tier | Spawns |
|---|---|
| Trivial (single-file config tweak, typo fix, rename) | 1 agent OR 0 if obviously scope-bound |
| Medium (feature addition touching 2-5 files) | 2 agents (existing-impl + integration-surface) |
| Big (subsystem-level change ≥10 files) | 3-4 agents (subsystem-A + subsystem-B + cross-cutting + conventions) |

Use the built-in `Agent(subagent_type="Explore", ...)` agent — NOT а plugin-defined agent (per system-prompt registered agents list). Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` (6 required fields).

All spawns в а single assistant response per the parallel-spawn rule. Per-spawn output schema: `[{file, lines, observation}]`; cap ~4000 chars (truncate с marker).

### 1.3 Echo contract (D4 fix — replaces unverifiable ≥2-citation rule)

Each Phase 1 Explore spawn writes а structured entry к state.md `## Tool log` via `atomic_state_write`:

```yaml
## Tool log
- ts: 2026-05-17T10:42:13Z
  tool: Agent
  detail: "Explore: existing auth flow integration points"
  status: ok
  summary: "found 3 files, 1 convention pattern"
  citations:
    - src/auth/oauth.ts:42-58
    - src/auth/__tests__/oauth.test.ts:14-29
    - src/middleware/session.ts:88-101
```

Phase 7 validator (§14.2 check #3) requires ≥1 Agent entry с `status: ok` per effort tier (Trivial ≥1 OR explicit "scope-bound, no exploration needed"; Medium ≥2; Big ≥3). The Echo contract makes "no related code found" auditable via M3 SessionStart re-injection.

### 1.4 Transition к Phase 3

Model synthesizes findings into а brief inline summary held в context (no separate artifact). The summary feeds Phase 3 question generation и Phase 5 section authoring. State.md `phase: clarify` written before Phase 3 entry.

**Skip к Phase 4 if Trivial:** when effort tier is Trivial AND Explore returned 0-1 findings AND topic is а narrow text-edit, Phase 3 is skipped. Write а one-line note к state.md `## Open Questions`: "Phase 3 skipped — trivial task, no ambiguity surfaced".

---

## Phase 2 — DROPPED (§9 rationale)

Phase 2 of pre-M5 /brainstorm was а visual companion (textual UI sketch + AUQ). M5 drops it:

1. Sketch did NOT persist into spec.md.
2. Phase 5 sections (§17.2 sections 6 & 9) absorb UI intent when the topic warrants.
3. Visual companion fired UNCONDITIONALLY — high friction for non-UI tasks.

Migration: UI intent now belongs в Phase 3 clarifying questions ("should we add а new screen or extend an existing view?") и Phase 5 section content.

---

## Phase 3 — Clarifying questions (§10)

State.md `phase: clarify` during this phase.

### 3.1 Question generation

Model identifies up к 5 highest-leverage ambiguities from:
- Phase 1 Explore findings ("found 3 auth flows — which one is the integration surface?")
- L2 query-learnings ("prior decision favored Approach X — does it apply here?")
- L4 code-style rules

Questions MUST be grounded в Phase 1 findings (D4 fix). Generic «what tech stack?» questions are forbidden — the model can answer those from L3 `_project.md`.

### 3.2 One-at-a-time AUQ shape

Fire questions sequentially, **never** as а multi-question form. Each AUQ:
- `header`: ≤12 chars (e.g., "Auth method", "Integration", "Scope")
- `question`: 1-2 sentences ending в а question mark
- `options[]`: 2-4 explicit choices. Include а "Skip — proceed с stated assumption" option as the last choice when applicable
- `multiSelect: false` unless explicitly multi-select

### 3.3 Persistence (P-M1-1 closure)

Each answered AUQ → append entry к state.md frontmatter `approvals[]` via `atomic_state_write` BEFORE proceeding к the next question:

```yaml
approvals:
  - category: clarify_<dim>          # e.g., clarify_auth_method
    prompt: "Which existing auth flow should the new feature integrate with?"
    options: ["OAuth (src/auth/oauth.ts)", "JWT (src/auth/jwt.ts)", "Skip — proceed assuming OAuth"]
    picked: "OAuth (src/auth/oauth.ts)"
    at: 2026-05-17T10:50:00Z
    asked_in_phase: clarify
```

On compaction-resume, M3 §6 Block 5d renders this; model re-reads `approvals[]` и skips already-answered questions.

### 3.4 Cap exhaustion

If а 6th clarification arises, force consolidation OR proceed к Phase 4 с stated assumptions. The 5-AUQ cap is а quality-first signal — more than 5 means Phase 1 underspecified OR the topic is too vague для а single /plan session.

---

## Phase 4 — Approaches (§11)

State.md `phase: approaches` during this phase.

### 4.1 Approach generation

Model synthesizes Phase 1 explore + Phase 3 answers into 2-3 distinct approaches. Each approach:
- **Name** (3-5 word label)
- **Summary** (2-3 sentences)
- **Trade-off** (1 sentence: gain vs give-up)
- **Effort estimate** (Trivial / Medium / Big per effort-scaling.md)

### 4.2 AUQ shape

Single-select; `Recommended` first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md`.

- `header`: "Approach"
- `question`: "Which approach do you want к pursue?"
- `options[]`:
  - Approach 1 (Recommended) — label: "<Name> (Recommended)"; description: summary + trade-off
  - Approach 2 — label: "<Name>"; description: summary + trade-off
  - Approach 3 (if generated) — label: "<Name>"; description: summary + trade-off

### 4.3 Persistence

User pick → append к `approvals[]` с category `approach_choice`. Other approaches captured к body section `## Considered Alternatives`:

```markdown
## Considered Alternatives

### Inline Refactor (rejected)
Summary: ...
Trade-off: smaller surface change, but locks into existing module shape.
Why rejected: violates new boundary established в Q3 2026 architecture review.
```

`## Considered Alternatives` is copied к spec.md body verbatim в Phase 6. M4 /implement reads but не gates on it.

---

## Phase 5 — Section approval (§12)

State.md `phase: section-approve` during this phase.

### 5.1 Section template (P-M5-1)

Use the **fixed 10-section P-M5-1 schema** detailed в M5 §17 (and reproduced в `skills/plan/spec-template.md`):

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
11. Done Condition  (header «## 11.» — schema counts 10 sections starting at ## 1; this is section #10 by count)

М5 does NOT support "1-6 sections scaled by complexity" (pre-M5 free-form). Every spec.md has exactly the same 10 sections — schema-stable downstream consumers.

For Trivial tasks, sections 4 / 5 / 10 may have body content «none — task scope precludes» с brief rationale. Headers MUST exist; bodies MAY be «none с rationale».

### 5.2 Per-section AUQ

One AUQ per section, sequentially:

1. **Pre-fill all 10 sections** в а single batch BEFORE the first per-section AUQ — lets the user see flow и catch cross-section issues early.
2. **Render the section к the user** (write content к chat as а markdown block).
3. **Fire AUQ** с header "Section: <name>":
   - **Approve** (Recommended) — proceed к next section.
   - **Revise — I'll describe** — user provides revision text; model re-authors и re-fires AUQ (max 3 revisions per section).
   - **Skip — accept as-is с warning** — proceed without explicit approve (rare; sections like Rollback-Recovery on trivial tasks).
4. **Persist** each pick к `approvals[]` с category `section_<id>` (e.g., `section_objective`, `section_scope_included`).

After 10 sections approved → transition к Phase 6.

### 5.3 Milestone-mode (§12.3 — absorbs /decompose)

If during section authoring the model detects а Big task (effort tier Big AND section 6 «Steps» has ≥10 discrete steps OR estimated wall-time ≥1 day), fire а new AUQ BEFORE Phase 6 entry:

- `header`: "Milestone slicing"
- `question`: "This task is large enough к slice into milestones. Slice it now или keep as а single spec?"
- `options[]`:
  - **Slice into milestones** (Recommended for Big) — model proposes 3-7 milestone names; user approves; Phase 6 emits sibling `milestone-N.md` files alongside `spec.md`.
  - **Keep as а single spec** — Phase 6 emits only spec.md; /implement consumes the whole thing.

If "Slice into milestones" picked:
1. Fire а follow-up AUQ с the proposed milestone names (single-select for «approve all» или multi-select pick per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md`).
2. After approval, Phase 6 writes the top-level spec.md (с section 6 «Steps» listing milestones и а new body section `## Milestones` indexing the sibling files) PLUS each `milestone-N.md` с its own 10-section P-M5-1 schema scoped к the milestone.
3. Persist к `approvals[]` с category `milestone_slice`.

Hand-off (Phase 9) offers `/implement milestone 1` for sliced specs.

Rationale: /decompose was deleted (master plan §65). М5 absorbs the milestone-authoring responsibility — but only when the task warrants it. For Medium/Trivial, the milestone-mode AUQ does not fire.

---

## Phase 6 — Write spec.md (§13)

State.md `phase: write-spec` during this phase.

### 6.1 Write contract

Path: `.geniro/planning/<task-slug>/spec.md` (M1 canonical).

Content: §17 P-M5-1 schema (10 sections) + frontmatter с §18 P-M5-2 goal block + body sections (`## Considered Alternatives` from Phase 4, optional `## Milestones` from §5.3).

Use the `Write` tool. The plan-mode mutation guard (§19) allows `Write` only под `.geniro/planning/**` AND `.geniro/state/**` — а write к anywhere else is blocked at PreToolUse.

After writing spec.md, append а `## Tool log` entry к state.md via `atomic_state_write`:

```yaml
- ts: 2026-05-17T11:08:00Z
  tool: Write
  detail: ".geniro/planning/<slug>/spec.md"
  status: ok
  result_ref: "<bytes-count>"
```

### 6.2 NO auto-commit (D1 fix)

М5 does **not** `git commit` at Phase 6 exit. The pre-M5 auto-commit violated Always-WAIT — а Phase 8 «Request changes» would force а second commit per round.

The `git commit` is deferred к Phase 8 §15.4 post-approval. At Phase 6 exit, spec.md sits unstaged on disk; state.md `phase: validate` written before Phase 7 entry.

### 6.3 Milestone-mode write fan-out

If milestone-mode was picked в Phase 5 §5.3, Phase 6 writes the top-level spec.md AND every `milestone-N.md` в а single phase pass. Each `milestone-N.md` follows the same P-M5-1 schema scoped к its slice.

### 6.4 Idempotent re-entry (compaction-safe)

If Phase 6 is re-entered after compaction (M3 SessionStart), the model:
1. Reads state.md `approvals[]` — every `section_<id>` approval is present per Phase 5.
2. Re-authors spec.md content from the persisted approvals.
3. Re-writes spec.md (overwrite — `Write`, not `Edit`, since this is idempotent regeneration).
4. Re-appends а `## Tool log` entry с note `(re-entry — post-compaction regeneration)`.

---

## Phase 7 — Mechanical validator (§14)

State.md `phase: validate` during this phase.

### 7.1 Mechanical pass-through (not Opus self-prompt)

Pre-M5 Phase 7 was а free-form Opus self-prompt. M5 replaces с а **deterministic validator** — script-checkable rules executed orchestrator-side. No LLM round-trip per check.

### 7.2 Validator checks (§14.2 — 13 checks)

See `skills/plan/validator-checks.md` for the canonical check definitions (9 P-M5-4 good-goal criteria + 4 legacy linter checks). Each check returns `(check_id, status, finding_text, fix_hint)`. Run all 13 в sequence.

### 7.3 Hard-fail handling

If any check fails:
1. Write findings к state.md `## Open Questions` body as а structured list (one bullet per failed check, с `fix_hint`).
2. Re-author the failing sections (orchestrator-side: model re-reads its own draft + validator findings + `fix_hint`s, и rewrites only the failing sections).
3. Re-run validator. **Max 3 auto-revision rounds.**
4. If round 3 still fails → fire `AskUserQuestion` с header "Validator hard-fail":
   - **Accept as-is** — proceed к Phase 8 с the failed checks documented в `## Open Questions`; user has final say.
   - **Re-revise** — kick а fresh round-1 cycle (rare; usually indicates schema misunderstanding).
   - **Abort** — terminal `aborted` + `## Termination reason: phase-7-validator-hard-fail`.

### 7.4 No transition к Phase 8 if validator hard-fails

The validator is а gate, not advisory. Phase 8 user-approve MUST see а validator-clean spec.md (or one where hard-fails were explicitly accepted by the user via §7.3 path A). Protects от the «user approves blind» failure mode.

---

## Phase 8 — User approval (§15)

State.md `phase: user-approve` during this phase.

### 8.1 Approval AUQ — P-M5-5 closure

Pre-M5 Phase 8 AUQ body was «Spec committed к <path>. Review it?» — user approved blind. M5 fires а **schema-rich AUQ** carrying P-M5-5 fields inline в the question body.

### 8.2 AUQ shape

- `header`: "Approve spec"
- `question`: multi-line markdown rendering the schema digest:

  ```
  Spec ready at .geniro/planning/<slug>/spec.md.

  **Objective:** <section 1 body — single sentence>

  **Scope:** <bullet count от section 2 Included + section 3 Excluded summary>

  **Approval Points:** <bullet list от section 8 «Approval Points», max 5 shown с «… and N more» if >5>

  **Risk class:** <auto-computed: «low» / «medium» / «high» based on section 5 Risks bullet count + section 7 forbidden_actions field>

  **Rollback:** <section 10 body summary, 1-2 sentences>

  **Done Condition:** <section 11 body — observable signal>

  **Scope summary:** <touched-file glob count от section 2 Scope.Included>

  **Expiration:** Approval valid for the current planning session; re-approval needed if spec.md is edited after this point.

  How do you want к proceed?
  ```

- `options[]`:
  - **Approve — proceed к hand-off** (Recommended) — Phase 9 fires next.
  - **Request changes — I'll describe** — fires а sub-AUQ for revision text; revisions re-run affected sections (max 3 user-revision rounds before §8.3 escalation).
  - **Abort — discard spec** — terminal `aborted` + `## Termination reason: user-rejected-at-phase-8`; spec.md remains on disk но не committed.

### 8.3 Revision-round escalation

Max 3 user-revision rounds (Phase 8 → re-enter affected sections in Phase 5 → re-validate в Phase 7 → re-fire Phase 8 AUQ). On round 3 exhaust, fire escalation AUQ с header "Phase 8 exhausted":
- **Accept as-is** — final answer; proceed к hand-off.
- **Re-revise (kick fresh cycle)** — full round-1 restart; rare.
- **Abort** — terminal `aborted` + `## Termination reason: repeated-failure: phase-8 revision-limit-3`.

### 8.4 Approve → git commit (D1 fix)

On user picks "Approve":

1. **Persist approval** к `approvals[]` с category `final_approve`.
2. **Flip spec.md `lifecycle: draft` → `lifecycle: approved`** in spec.md frontmatter via а fresh Write (idempotent regeneration per §6.4; the only field changing is `lifecycle:`). Per §17.1 design-doc lifecycle marker.
3. **`git commit`** fires HERE (NOT in Phase 6):
   - `git add .geniro/planning/<slug>/spec.md` + every sibling `milestone-N.md`
   - `git commit -m "plan: <task-slug> — <one-line summary от section 1 Objective>"`
4. **Append к `non-resumable-actions[]`** per M3 §8:
   ```yaml
   non-resumable-actions:
     - action: git-commit
       completed-at: <ISO-8601 UTC>
       commit-sha: <sha>
       files: [".geniro/planning/<slug>/spec.md"]
   ```
5. **Transition к Phase 9** (`phase: handoff`).

If commit fails (pre-commit hook denial, working-tree-dirty conflict, etc.), surface а structured error к user — do NOT proceed к Phase 9 с а stale state. Fall back к §8.3 escalation с the error inlined.

### 8.5 L2 emit (conditional, §21.2)

If Phase 4 had ≥2 distinct approaches AND the picked approach has а recorded trade-off rationale, emit а `decision` type entry к L2:

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.sh"
echo '{
  "type":"decision",
  "scope":"<task-area>",
  "summary":"approach: <name>",
  "tags":[...],
  "trust":"verified",
  "ext":{"options":[...], "chosen":"<picked>", "reasoning":"<trade-off>"}
}' | emit_learning
```

Dedup + sanitization automatic per M2 §5.2. Skipped if Phase 4 had ≤1 approach или no trade-off rationale recorded.

---

## Phase 9 — Hand-off (§16, D5 fix)

State.md `phase: handoff` during this phase.

### 9.1 Hand-off menu (D5 fix — 2 options replaces 4)

Fire `AskUserQuestion` с header "Next step":

- **/implement directly** (Recommended) — exit /plan, suggest the next command. For non-milestone specs: `/implement .geniro/planning/<slug>/spec.md`. For milestone specs: `/implement .geniro/planning/<slug>/milestone-1.md`.
- **Stop — keep spec для later** — terminal exit; spec sits on disk; user resumes when ready via `/implement <path>`.

Pre-M5 options для `/features add` и `/decompose` removed — both skills deleted (master plan §65, §68). Milestone responsibility is absorbed into Phase 5 §5.3. Backlog responsibility was always vestigial — а design doc on disk IS the backlog entry.

### 9.2 Persistence

User pick → append к `approvals[]` с category `handoff`:

```yaml
- category: handoff
  prompt: "Next step?"
  options: ["/implement directly", "Stop — keep spec for later"]
  picked: "/implement directly"
  at: <ISO-8601 UTC>
  asked_in_phase: handoff
```

### 9.3 Terminal transition

- **/implement** picked → emit а one-line directive в chat (`Next: /implement .geniro/planning/<slug>/spec.md`); do NOT auto-invoke /implement (user agency). State.md `phase: done`.
- **Stop** picked → emit а one-line directive (`Spec saved. Resume via: /implement .geniro/planning/<slug>/spec.md`); state.md `phase: done`.

Both paths terminate в `done`. M3 SessionStart recovery treats it as completed.

---

## Definition of Done

`/geniro:plan` run is complete when:

- [ ] Phase 0 mode detection ran via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`; mode is IDEA или DESIGN_DOC-fresh-start; CODE_REFERENCE errored с corrective hint.
- [ ] state.md created at `.geniro/planning/<slug>/state.md` via `atomic_state_write` с M1 §T1 frontmatter.
- [ ] Phase 1 loaded L4 + L3 + L2 (full tier); per-spawn Echo contract entries persisted к `## Tool log`.
- [ ] Phase 3 used `AskUserQuestion` one-at-a-time, ≤5 questions, single dimension per question; each answer persisted к `approvals[]`.
- [ ] Phase 4 presented 2-3 approaches с Recommended first; pick persisted к `approvals[]`; other approaches captured к `## Considered Alternatives`.
- [ ] Phase 5 used per-section AUQ for the fixed 10-section P-M5-1 schema; each pick persisted к `approvals[]`.
- [ ] Phase 5 §5.3 milestone-mode AUQ fired if Big-task detected.
- [ ] Phase 6 wrote spec.md к `.geniro/planning/<slug>/spec.md` с all three design-doc markers (M1 path + HTML comment + YAML frontmatter `geniro_kind: design-doc`).
- [ ] Phase 6 did NOT auto-commit (D1 fix).
- [ ] Phase 7 mechanical validator ran 13 checks; hard-fail surfaced findings к `## Open Questions`; max 3 auto-revision rounds respected.
- [ ] Phase 8 schema-rich AUQ fired с P-M5-5 fields inline; user picked one of 3 options; max 3 user-revision rounds respected.
- [ ] On Phase 8 Approve: `git commit` fired; `non-resumable-actions[]` updated; L2 `decision` emit conditional fired.
- [ ] Phase 9 hand-off AUQ fired с 2 options (D5 fix); pick persisted к `approvals[]`.
- [ ] HARD-GATE released only on Phase 8 "Approve".
- [ ] Terminal state.md `phase: done` (или `aborted` с `## Termination reason` body line).

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "This task is too simple to need а design" | "Simple" projects are where unexamined assumptions cause the most wasted work. Design can be short (Phase 5 Trivial = sections 4 / 5 / 10 с body «none с rationale»); presenting и approving is mandatory. HARD-GATE applies to EVERY task. |
| "I'll skip Phase 8 user re-review, my Phase 7 validator is enough" | Validator catches mechanical defects (placeholders / contradictions / scope creep); user catches intent defects (wrong abstraction / missing constraint). Different defect classes; both required. |
| "I'll batch all sections into one Phase 5 AUQ к save round-trips" | Forbidden. Section-by-section AUQ enables surgical revisions; batched AUQ forces batched edits across every section if any one needs changes. The round-trip cost is real но cheap; the batched-edit cost on disagreement is much higher. |
| "I'll keep the Phase 2 visual companion — nice when planning UI" | Dropped (§9). Sketch did NOT persist into spec.md; UI intent belongs в Phase 3 questions + Phase 5 sections 6 (Steps) / 9 (Validation) at the right granularity. |
| "I'll write the design doc с only the YAML frontmatter — that's enough" | Defense in depth requires all three markers (path + HTML comment + frontmatter). See `design-doc-detect.md` § Why defense in depth — each marker survives а different user action. |
| "Phase 4 — 4 or 5 approaches gives the user more choice" | More than 3 indicates Phase 3 didn't narrow scope; loop back к Phase 3 с а tighter scope-boundary question. |
| "Auto-commit at Phase 6 is convenient — drop а commit if Phase 8 rejects" | D1 fix. Rejection-induced commit-drop = forced `git reset` / `git revert`. Pre-M5 pattern polluted git history (every revision round left а commit). Phase 8 post-approve commit is а single commit per approved spec. |
| "I'll skip persisting Phase 3 clarifying answers — they're trivial" | Metaswarm anti-pattern. Compaction mid-Phase-5 loses 5 AUQs of user input. P-M1-1 `approvals[]` persistence is non-negotiable. |
| "I'll bypass the plan-mode mutation guard для performance" | §19 guard is а safety contract, not а perf knob. Adds <1ms per Write (path glob check). Bypass invites the failure mode the guard exists к prevent. |
| "Phase 0 Refine path saves three phases of re-work — keep it" | D3 fix. Refine re-derived sections from prose — structurally-lossy. Downstream consumers parse а malformed spec.md. «Start fresh с doc as context» is honest and produces а schema-clean spec.md. |
| "Hand-off menu should keep `/features add` for backlog discipline" | /features deleted (master plan §68). А «backlog» IS а spec.md saved on disk. No separate skill needed. |
| "Auto-default empty AUQ answer к the Recommended option" | Forbidden (§3.2). Empty answer = upstream Claude Code bug; fall back к plain-text re-ask. Auto-default silently mutates user intent. |
| "Add а wall-time / token kill cap so runaway /plan sessions abort cleanly" | Class-A hard caps forbidden by M5 §2.3 quality-first framing. M5 has Class-B gates (Phase 3 ≤5 AUQs, Phase 7 3-round, Phase 8 3-round) — escalate к user, do not abort. |
| "Bypass git pre-commit hooks с --no-verify when committing spec.md в Phase 8.4" | Hooks fail для а reason. Investigate root cause, не bypass. CLAUDE.md-level prohibition; М5 honors it. |
