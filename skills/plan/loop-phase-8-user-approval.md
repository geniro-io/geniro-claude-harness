# Phase 8 — User approval

A phase file of the `/geniro:plan` loop. The spine — HARD-GATE, gate presentation contract, echo contract, phase order, terminal states, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`.

## Contents

- 8.1 Approval gate — closure
- 8.2 Shape — message-first
- 8.3 Revision-round escalation
- 8.3.5 Launch config — pre-define implement settings
- 8.4 Approve → git commit
- 8.5 Record a learning (conditional)
- 8.6 Custom post-approval steps

State.md `phase: user-approve` during this phase.

### 8.1 Approval gate — closure

Phase 8 closes the loop with a final whole-spec approval. Apply the Gate presentation contract.

### 8.2 Shape — message-first

**Artifact** — fire the before-gate update for this site (call-site table in `loop-artifact-call-sites.md`) before the final-approval AUQ.

1. **Render the spec summary to a chat message in the Visual rendering language** (Gate presentation contract) — the progress tracker with every prior stop `✔` and `● Final approval`, a one-sentence opener restating the Objective in plain English, then an at-a-glance digest: scope summary (sections 2-3, reusing the in/out scope map), Approval Points (section 8 — where a pause is warranted during the build, not a guaranteed stop), Risk level — the highest per-risk severity in section 5, raised one level when frontmatter `forbidden_actions` is non-empty, with a one-line why naming the risk that set it, Rollback (section 10, one line), Done Condition (section 11 rendered as a `☐` checklist — one box per observable signal), touched-file glob count, approval-expiration notice, and what approving does with the file — commits it, or saves it on disk only when the project ignores the planning directory (resolve via the §8.4 step 3 check so the user learns this before approving, not after). Include the concrete examples already authored per section so the user reviews the real plan, not a label list.

2. **Fire ONE lean AUQ** — header "Approve spec"; `question` a one-line recap pointing at the message above; options: "Approve — commit the plan" (Recommended) / "Request changes — I'll describe" / "Abort — discard spec". Full literal message + AUQ template in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §5.

### 8.3 Revision-round escalation

Max 3 user-revision rounds (Phase 8 → re-enter affected sections in Phase 5 → re-validate in Phase 7 → re-fire Phase 8 AUQ). On round 3 exhaust, fire escalation AUQ with header "Revision limit reached":
- **Accept as-is** — final answer; route through §8.3.5 (the launch-config offer — this is a user-acceptance-to-commit path, same as an §8.2 Approve) and then run the §8.4 post-approve steps (commit, then Phase 9 prints the implement command).
- **Re-revise (kick fresh cycle)** — full round-1 restart; rare.
- **Abort** — terminal `aborted` + `## Termination reason: repeated-failure: phase-8 revision-limit-3`.

### 8.3.5 Launch config — pre-define implement settings (flag-driven or opt-in)

Fires after the user accepts the spec for commit — via the §8.2 "Approve" pick OR the §8.3 "Accept as-is" revision-wall terminal (never on Request changes / Abort / Re-revise). This step pre-answers the four `/geniro:implement` setup questions at plan time so `/implement` runs on its own — the full field semantics, enum values, and the doctrine boundary live in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md`; do not restate them here. The launch-config block is built one of two ways:

**Flag-driven (any launch modifier present in `$ARGUMENTS`).** When §0.1 recognized any launch modifier — a workspace modifier, a ship modifier, `freshness:<strategy>`, or `--deep` — build the `launch_config:` block directly from them and SKIP the interactive opt-in AUQ entirely; the flags ARE the opt-in. Map each specified modifier to its field (`new-branch` / `current-branch` / `worktree` / `here` → `workspace`, with `no-worktree` → `here`; `freshness:merge` / `freshness:rebase` / `freshness:skip` → `branch_freshness`; `--deep` → `deep_mode: true`; the ship modifier → `ship_mode` per its commit-no-push / draft-pr / ready-for-review / stop-after-review mapping). For each always-present field the user did NOT specify, fall back to that field's recommended default (`workspace: new-branch`, `deep_mode: false`, `branch_freshness: rebase`, `ship_mode: draft-pr`). Include `tracker_status` only when the spec has a linked tracker ticket (state.md `## Workflow Refs` non-empty), defaulting to `move-to-in-progress`; omit it otherwise. Hold the block for the §8.4 write and persist to `approvals[]` category `launch_config` via `atomic_state_write`, noting the source was `$ARGUMENTS` modifiers.

**Opt-in (no launch modifier present).** Fall back to the interactive opt-in:

1. **Ask the launch-config gate question** per `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §5b, which owns its wording. The gate question never auto-defaults; an empty answer is re-asked.

2. **On "No"** — write no `launch_config:` block. The spec carries no pre-set; `/geniro:implement` asks its setup questions interactively as it does today. Proceed to §8.4 with the spec unchanged.

3. **On "Yes"** — fire the batched capture per §5b, which owns the per-call batching, the chained tracker-status question, and the per-field defaults an empty answer falls back to. Capture the picks into a `launch_config:` block held for the §8.4 write.

4. **Persist the pick** to `approvals[]` with category `launch_config` via `atomic_state_write` (the gate answer + the captured fields). On "No", record the declined gate answer; no block is held.

Doctrine: `launch_config` pre-answers SETUP only, never safety gates — canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md` §"Doctrine boundary — setup only, never safety".

### 8.4 Approve → git commit

On user picks "Approve":

1. **Persist approval** to `approvals[]` with category `final_approve`.
2. **Flip spec.md `lifecycle: draft` → `lifecycle: approved`** in spec.md frontmatter via a fresh `atomic_state_write` that rewrites the whole spec (idempotent regeneration — the fields changing are `lifecycle:`, plus the `launch_config:` block + `geniro_schema_version: m5-v4` when §8.3.5 captured one; an in-place `Edit` is hard-blocked by the `enforce-state-helper` hook on `.geniro/planning/**`). Per design-doc lifecycle marker. **Fold the launch-config write into this SAME rewrite — zero extra writes:** when §8.3.5 produced a `launch_config:` block (whether from passed modifiers or the interactive opt-in), write it into the spec frontmatter and set `geniro_schema_version: m5-v4` (additive-optional per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md` §"Version & backward-compat"; the m5-v3/m5-v2/m5-v1 chain-enrichment version rule of §6.1 still applies when no launch_config was captured). When §8.3.5 wrote no block (user picked "No" in the opt-in path), leave the spec's version and frontmatter unchanged — only `lifecycle:` flips. Before committing the rewrite, run the `launch_config_consistency` enum assertions inline on the composed block — `workspace` / `deep_mode` / `branch_freshness` / `ship_mode`, plus `tracker_status` when present, each within its enum per `${CLAUDE_PLUGIN_ROOT}/skills/plan/validator-checks.md` check 13. The Phase 7 validator passes ran BEFORE this write, so this inline assertion is the only enum check that sees the block in this run. On an out-of-enum value, discard the §8.3.5 capture with a one-line notice ("launch-config capture discarded — `<key>` was '<value>', not a valid setting; /geniro:implement will ask its setup questions interactively") and write the spec without the block rather than committing an invalid one.
3. **`git commit`** fires HERE (NOT in Phase 6). Resolve first whether the task-dir is tracked at all — `git check-ignore -q .geniro/planning/<slug>/spec.md`. The default plugin `.gitignore` ignores `.geniro/*` and negates only `workflow/`, `instructions/`, and `actions/` (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md`), so on a default setup the planning dir is deliberately untracked and there is nothing to commit.
 - **Tracked** — `git add .geniro/planning/<slug>/spec.md` + every sibling `milestone-N.md`, then `git commit -m "plan: <task-slug> — <one-line summary from section 1 Objective>"`.
 - **Ignored** — skip the commit and continue to Phase 9; the spec on disk is the deliverable either way. Never `git add -f` a `.geniro/` path: force-adding it makes the file visible in IDE source-control panels, where a single "discard all changes" click deletes user-authored content. Record the skip as an `## Errors` body line (not a `non-resumable-actions[]` entry — nothing irreversible happened, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md`), and tell the user in one plain-English line that the plan is saved at `<path>` but not committed because the project ignores that directory, and that tracking it takes a `.gitignore` negation for `.geniro/planning/`.
4. **Append to `non-resumable-actions[]`** — only on the tracked branch, where a commit actually happened:
 ```yaml
 non-resumable-actions:
 - action: git-commit
 completed-at: $(date -u +%Y-%m-%dT%H:%M:%SZ)  # live clock read in the same write call — never model-supplied (atomic-state-write.md §Timestamp sourcing)
 commit-sha: <sha>
 files: [".geniro/planning/<slug>/spec.md"]
 ```
5. **Finalize the visual plan artifact** — fire the update for this site (call-site table in `loop-artifact-call-sites.md`).
6. **Transition to Phase 9** (`phase: handoff`).

If the commit fails (pre-commit hook denial, working-tree-dirty conflict, etc.), surface a structured error to user — do NOT proceed to Phase 9 with a stale state. Fall back to escalation with the error inlined. An ignored task-dir is not a failure: it takes the step 3 Ignored branch and continues to Phase 9 normally.

### 8.5 Record a learning (conditional)

Decide the emit condition first, without loading any helper: Phase 4 had ≥2 distinct approaches AND the picked approach has a recorded trade-off rationale. When it does not hold (≤1 approach, or no trade-off recorded), skip this step whole. When it holds, Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` and emit a `decision` type entry to L2:

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

Dedup + sanitization automatic. After a successful emit, echo `Recorded learning: <summary>` to the user; on a non-zero return, surface the loss in one plain-English line — both per that file's §"Caller contract".

### 8.6 Custom post-approval steps

After §8.5, before Phase 9. Execute any user-authored post-approval steps from the L4 `plan.md` instruction file (`.geniro/instructions/plan.md`) loaded at Phase 1 §1.1. Per the `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` §Producer contract, a `## Additional Steps` subsection is anchored to a phase-enum boundary; the canonical post-approval anchor is `### After user-approve` (`user-approve` is the Phase 8 enum value, and the spec is committed at §8.4, so an `### After user-approve` subsection runs against an approved, committed spec). Run any subsection anchored to the end of `user-approve`, treating each bullet as an imperative to execute in order and honoring any `AskUserQuestion` the user's step prescribes.

This is the generic extension point for project-specific post-plan work — e.g. duplicating the approved plan into a spec-driven-development tool's change format (OpenSpec, etc.) using the project's own tooling. The plugin stays tool-agnostic: the procedure lives entirely in the project's instruction file, not in this loop. Without this step a loaded `### After user-approve` block has no execution anchor and is silently dropped once Phase 9 runs (the same failure mode `/geniro:implement`'s `### After ship` step prevents). Skip silently when no such subsection is loaded.
