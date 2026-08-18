<!-- Generated from skills/plan/loop-phase-6-write-spec.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Phase 6 — Write spec.md

The spine is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`; this file carries the Steps.

State.md `phase: write-spec` during this phase.

### 6.0 Refresh custom instructions

**Refresh custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: plan`, `LOAD_TIER: pipeline`, `MODE: refresh`. Compaction since the previous load may have silently dropped the rules — re-Read all files and echo per the helper's contract.

The loop's only other load site is Phase 1. This phase authors `spec.md`, so the project's rules have to be the ones on disk now, not the ones read before the grill and approach rounds.

### 6.1 Write contract

Path: `.geniro/planning/<task-slug>/spec.md`.

Content: the `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md` schema + frontmatter with goal block + optional `workflow_refs[]` + body sections (`## Considered Alternatives` from Phase 4, optional `## Milestones` from Phase 5 milestone-mode).

**Frontmatter assembly — `workflow_refs[]`:** copy state.md `## Workflow Refs` block (populated by Phase 1.4) into spec.md frontmatter `workflow_refs:` field verbatim (YAML re-emission). Skip when state.md `## Workflow Refs` is empty / absent — `workflow_refs:` is then omitted from spec.md frontmatter entirely (the field is OPTIONAL per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md` §workflow_refs).

Set the schema version from what the copied `workflow_refs[]` actually carry:
- `m5-v3` when any copied entry carries a chain-enrichment field — `parent_ref.title`, `parent_ref.status`, `parent_ref.scope`, `siblings[]`, or `chain_fetched_at` (populated by Phase 1.4's chain assembly).
- `m5-v2` when `workflow_refs:` is present but carries no enrichment field (a plain tracker fetch with no chain).
- `m5-v1` / `m5-v2` both stay valid for pure inline-task /geniro:plan with no tracker linkage; downstream readers accept all four (m5-v1 .. m5-v4).

The Phase 7 validator shape-checks `workflow_refs` on m5-v2 / m5-v3 / m5-v4, so an m5-v1 spec carrying the field would escape validation — never emit m5-v1 when `workflow_refs:` is present.

Write spec.md (and state.md / each `milestone-N.md`) via `atomic_state_write` — source `${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh`, then feed the full file content on stdin via a heredoc, the same helper used for every state.md write. The `enforce-state-helper` hook hard-blocks a direct `Edit`/`Write` to anything under `.geniro/planning/**` or `.geniro/state/**`, so the helper is the only working write path for these artifacts:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"
atomic_state_write ".geniro/planning/<slug>/spec.md" <<'EOF'
---
<spec frontmatter>
---

<spec body — per spec-template.md schema>
EOF
```

After writing spec.md, append a `## Tool log` entry to state.md via `atomic_state_write`:

```yaml
- ts: 2026-05-17T11:08:00Z
 tool: atomic_state_write
 detail: ".geniro/planning/<slug>/spec.md"
 status: ok
 result_ref: "<bytes-count>"
```

**Artifact** — after spec.md is written, fire the update for this site (call-site table in `loop-artifact-call-sites.md`).

### 6.2 NO auto-commit

`git commit` does NOT fire at Phase 6 exit — it is deferred to Phase 8 post-approval to avoid per-revision commits polluting git history. At Phase 6 exit, spec.md sits unstaged on disk; state.md `phase: validate` is written before Phase 7 entry.

### 6.3 Milestone-mode write fan-out

If `approvals[]` carries a `milestone_slice` entry picked "Slice into milestones" (written at Phase 5, or at a Phase 7.5 milestone re-open), Phase 6 writes the top-level spec.md AND every `milestone-N.md` in a single phase pass. Each `milestone-N.md` follows the same schema scoped to its slice.

### 6.4 Idempotent re-entry (compaction-safe)

If Phase 6 is re-entered after compaction, the model:
1. Reads state.md `approvals[]` — every `section_<id>` approval is present per Phase 5.
2. Re-authors spec.md content from the persisted approvals.
3. Re-writes spec.md (overwrite via `atomic_state_write`, since this is idempotent regeneration).
4. Re-appends a `## Tool log` entry with note `(re-entry — post-compaction regeneration)`.
