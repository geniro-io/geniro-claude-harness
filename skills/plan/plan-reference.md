# /geniro:plan Reference

Companion reference for less-common usage paths of `/geniro:plan`. The main flow lives in `${CLAUDE_PLUGIN_ROOT}/skills/plan/SKILL.md`; this file documents edge cases and the shared rules consumed.

## Contents

- DESIGN_DOC mode — no refine path
- Concrete-example per section type (Phase 5 `preview` field substrate)
- workflow_refs[] usage notes (m5-v2 schema)
- Edge cases (empty $ARGUMENTS, milestone-mode, code-references, compaction, validator hard-fail, concurrent runs)
- Cross-references (shared rules consumed)

---

## DESIGN_DOC mode — no refine path

The Phase 0 DESIGN_DOC AUQ has 2 options (per `plan-loop.md`):

- **Start fresh with this as context** (Recommended) — the prior doc is inlined into Phase 1 research-agent prompts under a `## Prior Design Doc` section. Phase 5 uses the 11-section schema unconditionally — the prior doc is context, not template.
- **Cancel** — exit without writing state.md.

If the user really wants to surgically edit an existing design doc bypassing Phase 1-4, the correct path is to open the doc directly in an editor + manually update sections + re-run `/geniro:plan` only when ready to re-emit. /geniro:plan does NOT have an in-loop "edit existing sections" mode.

---

## Concrete-example per section type

Phase 5 cluster AUQ (`plan-loop.md` §5.2) requires every `Approve` option to carry an ADR-style digest (Decision → Why → How → optional ASCII diagram) PLUS one concrete example in its `preview` field. This table supplies the example that drops into each section's question `preview`, after the DECISION/WHY/HOW lines. The shape of "concrete example" depends on section type:

| Section | Example shape (drop into the `preview` after the section body) |
|---|---|
| 1. Objective | One-line user-visible behavior statement: "User clicks X → sees Y within Z seconds" |
| 2-3. Scope (Included/Excluded) | Bullet list mapping to specific files / endpoints / UI components (path-grounded, not feature-name) |
| 4. Assumptions | Concrete invariants: "`USER.tz` always populated" — cite `file:line` where the invariant is guaranteed |
| 5. Risks | Specific failure scenario + observable symptom: "Concurrent writers race on `events.cursor` → duplicate inserts → telemetry shows 2× `event.create` rate" |
| 6. Steps | Pseudocode block OR file-by-file diff outline (3-5 lines) OR ASCII data-flow |
| 7. Tools Required | Concrete CLI / MCP list: "`mcp__linear__update_issue`, `pnpm test`, `gh pr view`" |
| 8. Approval Points | Named decisions + AUQ shape (header / question / option count) — what /geniro:implement will ask the user mid-run |
| 9. Validation | Test names + ASCII test outline: `it('rejects negative quantity')` + 3-line body sketch |
| 10. Rollback-Recovery | One-line revert command OR feature-flag toggle pseudocode (e.g., `featureFlag.disable('new-auth')`) |
| 11. Done Condition | Observable signal phrase: "all 5 acceptance tests green AND telemetry shows ≥1 successful event insert" |

The example closes out each section's `preview`, below the DECISION/WHY/HOW lines — the orchestrator does NOT render section bodies to chat AND THEN open the AUQ. Each cluster fires ONE AUQ call with one question per section, the content already in each option's `preview`. The chat says one short cluster lead-in ("Reviewing the plan's Goal & scope — 3 sections, focus an option to inspect each."). Removes the "I already see the plan" redundancy.

---

## workflow_refs[] usage notes (m5-v2)

Phase 1.4 fetches tracker references via the matching MCP (Linear / Jira / GitHub Issues / Asana) when `$ARGUMENTS` carries a URL/ID. Phase 6 copies the fetched payload from state.md `## Workflow Refs` into spec.md frontmatter `workflow_refs[]`. Downstream consumers (/geniro:implement Step 0, /geniro:review Phase 1, /geniro:debug Phase 1, /geniro:refactor Phase 1) read this field.

**Schema-version compatibility:**
- `m5-v1` — legacy schema, no `workflow_refs[]`. Still valid for inline-task /geniro:plan with no tracker linkage.
- `m5-v2` — adds optional `workflow_refs[]`. Field absent ⇔ no tracker linkage; field present ⇔ Phase 7 check #14 validates structure.

**Per-entry shape:** see `${CLAUDE_PLUGIN_ROOT}/skills/plan/spec-template.md` §`workflow_refs[]` per-entry shape — `kind` / `issue_id` / `url` / `fetched_at` required; `title` / `suggested_branch` / `status` / `parent_ref` optional.

**Mutation responsibility:** only `/geniro:implement` MUTATES tracker state via MCP — Step 0c (kickoff: status-conditional "Move to In Progress?" / "Reopen?" prompts per the workflow file's `### On task start` block) and Phase 3 Ship (completion: status-conditional "Move to In Review?" / comment posting per `### On task completion`). `/geniro:plan` is a tracker reader — Phase 1.4 fetches issue context to inform planning, Phase 6 copies the cached payload into spec.md frontmatter; both are local-write only, never POST to tracker. `/geniro:review`, `/geniro:debug`, `/geniro:refactor` are also read-only consumers — they parse `workflow_refs[]` for priming context but never POST tracker updates.

**Staleness:** downstream readers re-fetch per the `fetched_at` staleness window defined in `${CLAUDE_PLUGIN_ROOT}/skills/plan/spec-template.md` (§`workflow_refs[]` per-entry shape). Cached `title` / `suggested_branch` / `status` fields let /geniro:implement Step 0 pre-fill AUQ defaults without re-fetching on every invocation.

**Graceful degrade:** workflow file lookup is cwd-first, then `<PRIMARY_ROOT>/.geniro/workflow/<kind>.md` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A. When the file is absent from BOTH locations, Phase 7 check #14 returns `warn` (not `fail`) — downstream skills skip workflow on-task-start hooks for that kind and continue. The workflow file may legitimately appear later in the project lifecycle.

---

## Edge cases

- **Empty $ARGUMENTS** — Phase 0 fires an `AskUserQuestion` with 3 options ("New feature" / "Existing problem to solve" / "Cancel") followed by free-text capture. Non-empty answer → IDEA mode; "Cancel" → terminal without state.md.

- **Topic spans multiple subsystems / very Big task** — the plan-loop completes normally (Phase 5 milestone-mode fires automatically per the canonical milestone-output condition in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` — Big tier with score 9+ or >15 steps). The Phase 9 hand-off recommends `/geniro:implement .geniro/planning/<slug>/milestone-1.md` for sliced specs.

- **User wants to plan WITHOUT writing a spec.md** — not supported. The committed spec.md IS the durable artifact downstream skills consume via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`. If the user insists, run /geniro:plan, pick "Stop — keep spec for later" at Phase 9 (terminal `done`, spec sits on disk but not committed). The three detection markers must still be present per Phase 6 contract.

- **`mode=CODE_REFERENCE`** — error and exit per Phase 0 (design-doc-detect helper returns CODE_REFERENCE → /geniro:plan emits error: "code reference passed to /geniro:plan; pass a topic or design-doc path. Did you mean /geniro:implement <path>?"). Do NOT fall back to `mode=IDEA` — silent misclassification of code references is the failure mode `design-doc-detect.md` Anti-rationalization warns against.

- **Compaction mid-Phase-5** — handled by the SessionStart re-injection of state.md `approvals[]` and `## Tool log`. The model re-reads `approvals[]` and skips already-answered AUQs; Phase 6 idempotent re-entry regenerates spec.md from persisted approvals.

- **Phase 7 validator hard-fail on round 3** — `plan-loop.md` escalation AUQ fires with 3 options (accept-as-is / re-revise / abort). User has agency; no silent abort.

- **Phase 8 user-revision round 3 exhaust** — `plan-loop.md` escalation AUQ fires with 3 options (accept-as-is / re-revise / abort). Terminal `aborted` records `## Termination reason: repeated-failure: phase-8 revision-limit-3`.

- **Concurrent /geniro:plan runs in different worktrees** — each worktree has its own `.geniro/planning/<task-slug>/state.md`.

---

## Cross-references

Shared rules consumed by this skill:

- `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` — canonical planning loop (Phases 0–9 plus the conditional Phase 0.5 problem-discovery and always-on Phase 7.5 spec-challenge; Phase 2 Visual Companion fires only on UI trigger). The Phase 0 / empty-argument / Phase 9 hand-off AUQs are inlined directly in plan-loop.md.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md` — Phase 0 mode detection algorithm; per-consumer behavior table for `/geniro:plan`.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` — Recommended-label policy for the Phase 4 approach AUQ + multi-select picker schema for Phase 5 milestone-name approval.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` — tier rubric used by Phase 1 effort-tier-scaled spawns and Phase 5 milestone-mode trigger.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` — Phase 2 Visual Companion procedure (UI-conditional). Spawns the UI description agent (OMIT `model=`; inherits the orchestrator tier per ui-preview-gate.md), runs the textual-preview revision loop (max 3 rounds), returns approved description to state.md `## UI Preview`.
- `${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh` — state.md write helper.
- `${CLAUDE_PLUGIN_ROOT}/lib/validate-state-file.sh` — state.md validator for resume.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` — L4 directive doc (Phase 1 entry refresh).
- `${CLAUDE_PLUGIN_ROOT}/lib/load-semantic.sh` — L3 read helper (Phase 1 entry).
- `${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh` — L2 read helper (Phase 1 entry).
- `${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh` — L2 write helper (Phase 8 conditional `decision` emit).
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md` — cross-layer L4/L3/L2 conflict protocol.
- `${CLAUDE_PLUGIN_ROOT}/skills/plan/spec-template.md` — 11-section schema template (Phase 6 input).
- `${CLAUDE_PLUGIN_ROOT}/skills/plan/validator-checks.md` — mechanical checks (Phase 7 input).
