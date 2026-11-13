<!-- Generated from skills/plan/loop-phase-8-user-approval.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Phase 8 — User approval

The spine is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`; this file carries the Steps.

## Contents

- 8.0 Refresh custom instructions
- 8.1 Approval gate — closure
- 8.2 Shape — message-first
- 8.3 Revision-round escalation
- 8.3.5 Launch config — pre-define implement settings
- 8.4 Approve → git commit
- 8.5 Record a learning (conditional)
- 8.6 Custom post-approval steps

State.md `phase: user-approve` during this phase.

### 8.0 Refresh custom instructions

**Refresh custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: plan`, `LOAD_TIER: pipeline`, `MODE: refresh`. Re-Read all files and echo per the helper's contract.

The nearest prior load site is Phase 6 (§6.0), itself a refresh of Phase 1 (§1.1). §8.6 below executes any user-authored `### After user-approve` block from this load — that block has to be the one currently on disk, not the one read before validation and the spec challenge.

### 8.1 Approval gate — closure

Phase 8 closes the loop with a final whole-spec approval. Apply the Gate presentation contract.

**Re-entry check (crash/compaction resume).** Before rendering the summary or firing the gate, check `approvals[]` for a `final_approve` entry. §8.4 step 1 writes it after the §8.3.5 question is answered, so its presence alone shows both questions are settled — a run with nothing to commit never writes a `git-commit` entry, so that entry cannot be the key. When present, a prior pass crashed or compacted before the §8.6 `phase: handoff` write: do NOT re-render §8.2's summary or re-fire its AUQ or the §8.3.5 question. Resume at the first piece of work with no record: the §8.4 spec.md rewrite (`lifecycle: approved`, `launch_config:` rebuilt from its `approvals[]` entry), the §8.4 commit (skip it when a `git-commit` entry exists or `git status --porcelain` shows every file it stages clean, since the commit already landed), then whichever of §8.5 / §8.6 has none (the `Recorded learning:` tool-log entry, the loaded `### After user-approve` execution), and continue to the §8.6 transition.

### 8.2 Shape — message-first

**Artifact** — fire the before-gate update for this site (call-site table in `loop-artifact-call-sites.md`) before the final-approval AUQ.

1. **Render the whole spec to a chat message in the Visual rendering language** (Gate presentation contract) — the progress tracker with every prior stop `✔` and `● Final approval`, a one-sentence opener restating the Objective in plain English, Risk level (the highest per-risk severity in section 5, raised one level when frontmatter `forbidden_actions` is non-empty, with a one-line why naming the risk that set it), and every `pending: <owner>` assumption from section 4 listed by owner with the `questionnaire.md` path and the note that an owner's answer replaces that `pending:` line in the spec before /geniro:implement runs (approving leaves those decisions open). Then the three clusters in the Phase 5 §5.2 cluster table's order, each opening with its centerpiece — cluster 1 the in/out scope map; cluster 2 the public-surface block, then the steps flow diagram; cluster 3 the test-seams block, then the done-condition `☐` checklist — and one icon-headed sub-heading per section: its friendly digest, then a `**Technical detail:**` block carrying the grounding Phase 1 finding `file:line` — each cite tagged `agent-summary` (a `codebase-research-agent` spawn's reported finding) or `orchestrator-read` (this session opened the file itself — the only source at the §1.2 zero-agent Trivial path, `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-1-explore.md` §1.2/§1.5) — the Phase 4 approach it rests on, and the named files and symbols (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Two explanation layers), closing with the section's concrete example (Phase 5 §5.2 example table) and its visual (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §"Plan-unit visual map"). A "none — task scope precludes" section is a one-line note. End with the approval-expiration notice, what approving commits — the spec, saved on disk only when the project ignores the planning directory (resolve via §8.4's tracked-vs-ignored check, so the user learns this before approving), plus any glossary and ADR edits §8.4 will commit — and a `**Technical detail:**` block holding the spec's path on disk and the touched-file glob count.

2. **Ask one lean question** — header "Approve spec"; `question` a one-line recap pointing at the message above; options: "Approve — commit the plan" (Recommended) / "Request changes — I'll describe" / "Abort — stop planning". Full literal message + AUQ template in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §5.

3. **On Abort** — run the §9.2 transient cleanup (`clean_task_transients`, `loop-phase-9-handoff.md`) and walk `loop-definition-of-done.md` §Abort-path subset, then write terminal `aborted` + `## Termination reason: user-cancelled-at-phase-8`. spec.md stays on disk, uncommitted.

### 8.3 Revision-round escalation

Max 3 user-revision rounds. A "Request changes" pick asks the user to name the section(s) to change and the change. Persist it to `approvals[]` with category `revision_request` — `picked` the sections named and the change asked for, as one quoted line — and the `phase: section-approve` transition in the SAME `atomic_state_write` call, before re-authoring: Phase 5 and Phase 6 §6.4 rebuild from `approvals[]`, so an unsaved request is lost to a compaction, and separate writes would let a crash between them resume at Phase 8 on the unrevised spec. The round re-authors those sections AND any section that depends on them (Phase 5), rewrites spec.md (Phase 6), re-validates (Phase 7), re-checks the revised claims per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md` §8.5 with `SCOPE: changed-only`, then re-fires the Phase 8 AUQ. The claim re-check runs on every round, including a round that only added a step: content written after the challenge is content no verifier has read, and skipping it lets the user approve, on round 3, a spec whose newest claims were checked for shape alone. On round 3 exhaust, fire escalation AUQ with header "Revisions":
- **Accept as-is** — final answer; route through §8.3.5, then run the §8.4 post-approve steps.
- **Re-revise (kick fresh cycle)** — full round-1 restart.
- **Abort** — run the §9.2 transient cleanup (`clean_task_transients`, `loop-phase-9-handoff.md`) and walk `loop-definition-of-done.md` §Abort-path subset, then write terminal `aborted` + `## Termination reason: repeated-failure: phase-8 revision-limit-3`.

### 8.3.5 Launch config — pre-define implement settings (flag-driven or opt-in)

Fires after the user accepts the spec for commit — the §8.2 "Approve" pick or the §8.3 "Accept as-is" terminal, never on Request changes / Abort / Re-revise. It pre-answers `/geniro:implement`'s setup questions so `/implement` runs on its own; field semantics, enums, and the setup-only doctrine are canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md`.

**Flag-driven.** When §0.1 recognized any launch modifier, the flags ARE the opt-in: skip the question and build the `launch_config:` block from them (workspace modifiers → `workspace`, with `no-worktree` → `here`; `freshness:<strategy>` → `branch_freshness`; the ship modifier → `ship_mode` per §0.1), taking §5b's recommended default for each always-present field not specified and for `tracker_status`, which is included only when state.md `## Workflow Refs` is non-empty. Hold the block for §8.4 and persist it to `approvals[]` category `launch_config` via `atomic_state_append_list_item`, noting the source was `$ARGUMENTS`.

**Opt-in.** With no modifier, ask the §5b gate question, which owns its wording; it never auto-defaults, and an empty answer is re-asked. "No" — hold no block; the spec carries no pre-set and `/geniro:implement` asks interactively. "Yes — use the recommended settings" — hold §5b's defaults, asking nothing further. "Let me choose each setting" — run §5b's batched capture (`${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-launch-config-capture.md`) and hold the picks. Persist the answer, and the captured fields when any, to `approvals[]` category `launch_config`.

### 8.4 Approve → git commit

On user picks "Approve":

1. **Persist approval** to `approvals[]` with category `final_approve`.
2. **Flip spec.md `lifecycle: draft` → `lifecycle: approved`** in spec.md frontmatter via a fresh `atomic_state_write` that rewrites the whole spec (idempotent regeneration). **Fold the launch-config write into this SAME rewrite — zero extra writes:** when §8.3.5 produced a `launch_config:` block, write it into the spec frontmatter and set `geniro_schema_version: m5-v4` (additive-optional per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md` §"Version & backward-compat"; the m5-v3/m5-v2/m5-v1 chain-enrichment version rule of §6.1 still applies when no launch_config was captured). Before committing, run the scripted validator against spec.md (`${CLAUDE_PLUGIN_ROOT}/skills/plan/validator-checks.md` §Running the checks) and read its `launch_config_consistency` row (check 13) — Phase 7 ran BEFORE this write, so this is the only run that sees the block, and the script owns the enums (never re-derive them by hand). On a `fail` row, discard the §8.3.5 capture with a one-line notice ("launch-config capture discarded — `<key>` was '<value>', not a valid setting; /geniro:implement will ask its setup questions interactively") and rewrite spec.md without the block, at the schema version §6.1 set, rather than committing an invalid one.
3. **`git commit`** fires HERE (NOT in Phase 6). Resolve first whether the task-dir is tracked at all — `git check-ignore -q .geniro/planning/<slug>/spec.md` — and which documentation files this run commits: the glossary only when the grill's Tool log line shows this run wrote it and it was clean before (otherwise it holds the user's own edits, and Phase 9 names it instead), and each existing ADR file a `clarify_adr_<slug>` entry in `approvals[]` names. A documentation path the project ignores stays uncommitted on either branch (`git add` errors on it). Never `git add -f` a `.geniro/` path: it surfaces the file in IDE source-control panels, where one "discard all changes" click deletes user-authored content. Commit only this run's paths (`git commit -m … -- <paths>`), so anything the user already staged stays out.
 - **Tracked** — `git add .geniro/planning/<slug>/spec.md` + every sibling `milestone-N.md` + `questionnaire.md` when it exists (it is written for another person, so it has to reach them) + those documentation files, then `git commit -m "plan: <task-slug> — <one-line summary from section 1 Objective>" -- <paths>`.
 - **Ignored** — the spec stays on disk (the deliverable either way) and is not committed. Commit the documentation files on their own when there are any: `git add` them, then `git commit -m "docs: <task-slug> — glossary and ADRs from planning" -- <paths>`. Record the spec's skip as an `## Errors` body line (not a `non-resumable-actions[]` entry — nothing irreversible happened, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md`), and tell the user in one plain-English line that the plan is saved at `<path>` but not committed because the project ignores that directory, and that tracking it takes a `.gitignore` negation for `.geniro/planning/`. Continue to step 4.
4. **Append to `non-resumable-actions[]`** — whenever a commit actually happened (the tracked branch, or the Ignored branch's docs-only commit):
 ```yaml
 non-resumable-actions:
 - action: git-commit
 completed-at: $(date -u +%Y-%m-%dT%H:%M:%SZ)  # live clock read in the same write call — never model-supplied (atomic-state-write.md §Timestamp sourcing)
 commit-sha: <sha>
 files: [".geniro/planning/<slug>/spec.md", "<each glossary or ADR path committed>"]
 ```
5. **Finalize the visual plan artifact** — fire the update for this site (call-site table in `loop-artifact-call-sites.md`). §8.4 does not itself transition the phase — §8.6 writes `phase: handoff` once its own steps (and §8.5's) complete, so a crash between here and that write resumes at `phase: user-approve` rather than stranding the loop mid-approval; the §8.1 re-entry check covers that resume.

If the commit fails (pre-commit hook denial, working-tree-dirty conflict, etc.), render the failure to chat first, then fire the lean AUQ header "Commit" — do NOT proceed to §8.5 with a stale state:
- **Retry the commit** (Recommended) — re-run step 3's `git commit`. state.md stays `phase: user-approve`.
- **Save on disk, skip the commit** — leave spec.md and the documentation files uncommitted (Phase 9 names them); record the failure as an `## Errors` entry. state.md stays `phase: user-approve`; continue to §8.5.
- **Abort** — run the §9.2 transient cleanup (`clean_task_transients`, `loop-phase-9-handoff.md`) and walk `loop-definition-of-done.md` §Abort-path subset, then write terminal `aborted` + `## Termination reason: commit-failed-at-phase-8`.

An ignored task-dir is not a failure: it takes the step 3 Ignored branch and continues to §8.5 normally.

### 8.5 Record a learning (conditional)

Decide the emit condition first, without loading any helper: Phase 4 had ≥2 distinct approaches AND the picked approach has a recorded trade-off rationale. When it does not hold (≤1 approach, or no trade-off recorded), skip this step whole. When it holds, Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` and emit a `decision` type entry to L2:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh"
echo '{
 "producer":"/geniro:plan",
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

After §8.5, run the `### After user-approve` subsection of the `plan.md` instruction file loaded at §8.0 (anchor semantics: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` §Producer contract): execute each bullet in order, honoring any `AskQuestion` it prescribes, and skip silently when none is loaded.

**Transition.** Then write `phase: handoff` via `atomic_state_set_field` — the phase's last write, so a resume never sees `handoff` before §8.5's emit and these steps have run.
