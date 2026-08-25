---
name: geniro-setup
description: "Use when starting on a new codebase or after a major plugin update. Detects tech stack, generates a project-specific CLAUDE.md (stack, commands, conventions, domain), and validates it. Re-run mode runs a migration sweep. Singleton bootstrap."
context: main
---
<!-- Generated from skills/setup/SKILL.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->


# Setup: AI-driven plugin setup

## Contents

- Path constraints
- Subagent model tiering
- Loop invariants
- Anti-rationalization
- Definition of done
- Budgets — quality-first
- ACI per-phase tool surface
- Termination case → state mapping
- Memory I/O
- Phase 0 — pre-flight
- Phase 1 — Detect · Phase 2 — Interview · Phase 3 — Generate · Phase 4 — Validate · Phase 5 — Done
- State file schema
- Cross-references

---

6-phase loop: **Pre-flight → Detect → Interview → Generate → Validate → Done**. Turns an unfamiliar repository into a Geniro-ready project in one supervised run. **Singleton bootstrap** — one canonical state file at `<PRIMARY_ROOT>/.geniro/state/setup/state.md` (no `<slug>/` subdir, no parallel runs). Supports `init` (first time) and `re-run` (refresh after stack changes). Uninstall is out of scope.

**Runtime portability.** `${CLAUDE_PLUGIN_ROOT}` is a path placeholder Claude Code substitutes into file references, never a shell export — it reads empty in a Bash call under every host, Claude Code included, so an empty probe is no evidence of another runtime (`CLAUDECODE` in the environment marks Claude Code). Resolve the root by working these in order: the ancestor directory of this file containing `.claude-plugin/plugin.json`; a copy of the referenced file sitting beside this one (the Cursor build ships each skill's own phase and reference files there); a plugin checkout inside the workspace. Substitute the resolved root for every `${CLAUDE_PLUGIN_ROOT}` occurrence and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. **Work the rungs with a command, not a judgment:** the run's first Bash call lists the directory this file was read from and each candidate root, and its output is echoed verbatim before anything else. Read the rungs against that output — a path it does not show did not resolve, and a file it does not show cannot be read, however confidently a later step would report otherwise. A ladder that resolves is bookkeeping, not a finding: keep the echo to the probe output and the resolved root, and reserve a degraded-run notice for a rung that actually failed. Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md` before deciding a step cannot run here: it substitutes mechanisms, not steps, and routes a host with no one to ask to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/non-interactive-host.md`. **When no rung resolves, the files are missing but the contract is not** — open your first message by naming what is unavailable, run every phase and gate this skill declares, never let the project's own rules stand in for its decision gates, and take no outward-facing action (ready-for-review PR, merge, force-push, protected-branch push, posted comment, tracker transition) without an explicit answer.

**Scope discipline:** CLAUDE.md is auto-loaded on every run in this project, so every section has to justify that recurring cost — keep what changes how a task is executed, and leave anything the model can read on demand from the project's own docs where it already lives.

**Read the phase's Steps on entry to that phase**, from `${CLAUDE_PLUGIN_ROOT}/skills/setup/`: `phase-0-preflight.md` · `phase-1-detect.md` · `phase-2-interview.md` · `phase-3-generate.md` · `phase-4-validate.md` · `phase-5-done.md`. That Read is the phase's physically-first action and carries a one-line echo, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — the phase files hold this skill's gates and their helper call sites, so work started before the Read runs outside them. The singleton state file's `phase:` says where to resume, including after a compaction.

## Path constraints

**Pass `${CLAUDE_PLUGIN_ROOT}` (plugin files) or a fully resolved absolute path (project files) to Read, Write, Edit, Glob, and Grep** — these tools do not expand `~`, so a literal `~` directory gets created.

Resolve the user's Claude config dir once, honoring `CLAUDE_CONFIG_DIR`:

```bash
CLAUDE_USER_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
```

## Subagent model tiering

Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`, plugin-agent spawns OMIT `model=` and inherit the orchestrator tier. Setup has a single spawn — the verification subagent — a documented carve-out. This table is the one place its tier and reason are stated; the §4.1 spawn site and the Cross-references entry point here.

| Spawn | Tier | Why |
|---|---|---|
| Verification subagent (validate generated CLAUDE.md against codebase) | `sonnet` ceiling | Mechanical check-and-report: runs a fixed check list and emits PASS/DRIFT lines the orchestrator re-decides from, so its output does not scale with orchestrator tier. A short generated CLAUDE.md sizes below the ceiling (`model-tiering.md` §Sizing a non-judgment spawn) |

## Loop invariants

The canonical loop invariants (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md`) apply, with five setup-specific bindings:

- **Invariant #2 (args validated before execution)** — every Write to `CLAUDE.md` / `.geniro/instructions/*.md` preceded by Read-then-diff in re-run mode.
- **Invariant #3 (permission before side-effect)** — Write to project root files (`CLAUDE.md`, `.gitignore`) is AUQ-gated at the §3.3 batch gate in Phase Generate; user-config writes outside PROJECT_ROOT (the §3.6 statusline copy + `settings.json` edit) fold into that same batch AUQ, with the `settings.json` replacement firing its own §3.6 `AskQuestion` when an entry already points elsewhere — and any further mid-phase choice this skill reaches is routed through that same tool, never chat prose, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions.
- **Invariant #4 (bounded structured tool results)** — verification subagent output truncated per the §4.1 subagent-prompt cap; over-long reports trigger AUQ.
- **Invariant #5 (escalation gates, not silent abort)** — the validation retry loop escalates via AUQ (`accept-with-warnings | abort | start-over`) rather than aborting silently; retry cap and round count owned by `${CLAUDE_PLUGIN_ROOT}/skills/setup/phase-4-validate.md` §4.2.
- **Invariant #7 (errors → structured observations)** — Detect failures written to `## Errors`, not swallowed.

`## Tool log` selective logging: record verification subagent spawns + every Write to project root or `.geniro/`. Skip routine Read/Bash inside Detect.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I already know this stack, skip Detect" | Detect's scan output is what Phase 3 generates the Tech Stack / Validation Commands / domain-facts sections from (`phase-3-generate.md` §3.2). Skip it and generation has no project facts to write from, so Phase 4's Template-artifact / Generic-placeholder checks (`verification-checks.md`) flag the result as DRIFT and force a regeneration round. |
| "No docs to read, skip documentation scan" | Check first. README.md, CONTRIBUTING.md, .cursorrules — even partial docs contain domain knowledge that improves CLAUDE.md. |
| "Default settings are fine, skip Interview" | §2.2 is where Detect's `unknown` fields and ambiguous guesses get corrected before Phase 3 generates CLAUDE.md from them. Skip it and those unresolved values ship straight into the file, where Phase 4's verification subagent reports them as DRIFT — an extra regeneration round for what one AUQ would have fixed. |
| "The generated files look correct, skip Validate" | Placeholder text and wrong-language content are invisible without systematic scanning. |
| "I already verified everything in my own checks, skip the verification subagent" | You generated the files — you're blind to your own mistakes. The independent subagent catches residual placeholders, broken paths, and cross-file inconsistencies you anchored past. |
| "I'll add the Geniro skill table / hooks list / path rules to CLAUDE.md" | No — CLAUDE.md is project-specific. Everything on the `verification-checks.md` §Excluded content list lives in plugin files and is loaded automatically; copying it into CLAUDE.md wastes tokens on every run. |
| "I'll add preference questions to the interview to customize defaults" | No — skill defaults are built into each skill. Setup detects the codebase and generates CLAUDE.md; it does not configure skill behavior. |
| "The user said 'looks good' — setup is done, skip Phase Done cleanup" | No — Phase Done deletes the state file (which has zero value once DONE). Forgetting to delete leaves stale state for the next re-run. |

## Definition of done

These are the load-bearing exit gates — the invariants that, if skipped, make the setup incomplete or unsafe. Per-phase mechanics live in their phase files; this list is the final correctness/contract check, not a re-listing of every step.

- [ ] Generated CLAUDE.md contains no Geniro-plugin content — every entry on `${CLAUDE_PLUGIN_ROOT}/skills/setup/verification-checks.md` §Excluded content checked and absent
- [ ] Verification subagent passed within the retry cap, or resolved via the final-round AUQ escalation (cap owned by `${CLAUDE_PLUGIN_ROOT}/skills/setup/phase-4-validate.md` §4.2)
- [ ] L2 `discovery` emit fired
- [ ] State file deleted on the success path
- [ ] All user interactions used `AskQuestion`
- [ ] If re-run mode + plugin-version delta: restart-session warning emitted

## Budgets — quality-first

No hard kill caps — the quality-first doctrine in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §"Budgets — quality-first (canonical)" applies. Aborting mid-bootstrap leaves the project in a half-configured state, so this skill's own gates escalate rather than abort:

| Layer | Lever | Why |
|---|---|---|
| **Class-B escalation gates** | Validation retry loop → AUQ (cap owned by `${CLAUDE_PLUGIN_ROOT}/skills/setup/phase-4-validate.md` §4.2) | Drift past the cap means structural disagreement; surface to user |
| | Verification report truncation per the §4.1 subagent-prompt cap | Long reports inflate context without commensurate signal |
| **Architecture constraints** | Singleton state file (no `<slug>/`) | Parallel `/geniro:setup` runs would race and corrupt `CLAUDE.md` |

## ACI per-phase tool surface

| Phase | Allowed tools | Forbidden tools |
|---|---|---|
| `detect` | `Read`, `Bash` (read-only: `git`, `find`, `grep`, `cat`), `Glob`, `Grep`, `Agent` | `Write`, `Edit`, mutating `Bash`, `mcp__github__*` |
| `interview` | `AskQuestion`, `Read` | `Write`, `Edit`, mutating `Bash` |
| `generate` | `Read`, `Write`, `Edit`, `Bash` (mkdir, chmod), `AskQuestion` | `mcp__github__*`, network egress (`curl`, `gh`, `git push`) |
| `validate` | `Read`, `Bash` (read-only), `Agent` (verification subagent), `AskQuestion` | `Write`, `Edit` |
| `done` (cleanup) | `Bash` (rm of state file), `AskQuestion` (the §5.2 map-the-codebase question), `Read` (the §5.4 compaction-resume re-read of `setup-rerun-reference.md`), inline invocation of `/geniro:onboard` on that question's "Map codebase now" pick | everything else |

External sends are not part of `/geniro:setup` ACI. Users wire those via `/geniro:actions` if needed.

## Termination case → state mapping

| Cause | Phase enum on exit | `## Termination reason` body section |
|---|---|---|
| User aborted at Validate AUQ (rejected generated content) | `failed` | "user-aborted at Validate AUQ — generated content rejected; restart via re-run mode" |
| Validation drift cleared after retry | `done` | not written (success path) |
| Validation retry-cap escalation (`phase-4-validate.md` §4.2) — "Abort setup" pick | `failed` | "user aborted at the validation escalation gate — remaining drift unresolved; restart via re-run mode" |
| Validation retry-cap escalation (`phase-4-validate.md` §4.2) — "Accept with warnings" pick | `done` | not written (success path; remaining DRIFT items noted in `## Open Questions`; state file deleted at Phase Done unless `mode == re-run`, per `phase-5-done.md` §5.3) |
| Validation retry-cap escalation (`phase-4-validate.md` §4.2) — "Start over" pick | `detect` (non-terminal — restarts Phase 1) | not written (run continues, not terminated) |
| Generation hit write-protection | `failed` | "write-protected target — bypass via `.geniro/safety.json` then re-run" |
| Bootstrap completed without drift | `done` | not written |

## Memory I/O

| Layer | Read at | Write at | Notes |
|---|---|---|---|
| CLAUDE.md (not a memory layer) | Phase 1 (existing AI-tool config scan) | Phase 3 (project-specific CLAUDE.md) | Project-only content per `${CLAUDE_PLUGIN_ROOT}/skills/setup/verification-checks.md` §Excluded content. Preserves user customizations via orchestrator-inline merge |
| L2 learnings.jsonl | Phase 1 (prior `discovery` query, tag `setup`) | Phase 4 (one `discovery` row on `done`) | `trust: verified` — code-grounded |
| L3 `.geniro/planning/_*.md` | not read | not written | `/geniro:setup` and `/geniro:onboard` are different skills with non-overlapping write surfaces |
| L4 `.geniro/instructions/*.md` | Phase 0 (rules-only load via `load-custom-instructions.md`) | Optional `global.md` if user opted in | Standard format (`## Rules`, `## Additional Steps`, `## Constraints`) |

## Phase 0: Pre-flight

`phase: pre-flight` · Steps: `phase-0-preflight.md`. Load custom instructions, resolve `PRIMARY_ROOT` and `PROJECT_ROOT`. Exit when both are resolved and the load echoed.

## Phase 1: Detect

`phase: detect` · Steps: `phase-1-detect.md` §1.1-§1.6. Rehydrate or pick `mode: init | re-run`, query past learnings, locate the plugin source, scan the codebase for stack/conventions/docs (Evidence Block standard), reconcile the skill inventory. Exit when `detected:` and `skill_inventory` are written to state frontmatter and the Phase log summary line is recorded.

## Phase 2: Interview

`phase: interview` · Steps: `phase-2-interview.md` §2.1-§2.5. Reuse persisted `approvals[]` answers where present; otherwise confirm detection, resolve any Detect ambiguity, and ask the optional-integration and custom-instructions questions. Exit when every AUQ slot in this phase has a persisted answer.

## Phase 3: Generate

`phase: generate` · Steps: `phase-3-generate.md` §3.0-§3.6. Re-run mode runs the migration sweep and pre-write audit first (`setup-rerun-reference.md`); then generate project-only CLAUDE.md content, write every §3.3 target under the batch AUQ, apply re-run merge rules, create runtime directories + `.gitignore` re-include, and install the statusline. Exit when every §3.3 write target exists (or was explicitly skipped by the user's edit pick) and the batch AUQ is recorded in `approvals[]`.

## Phase 4: Validate

`phase: validate` · Steps: `phase-4-validate.md` §4.1-§4.3. Spawn the read-only verification subagent against the generated CLAUDE.md; on DRIFT, regenerate only the affected sections and retry up to the §4.2 cap, then escalate via AUQ. Exit when a round returns zero DRIFT items (or the escalation AUQ resolves the run per §4.2), and the `discovery` learning has been emitted.

## Phase 5: Done

`phase: done` · Steps: `phase-5-done.md` §5.1-§5.4. Print the final report, offer to map the codebase (skipped on re-run), delete the singleton state file (the one named exception to the T1.5 survives-past-ship rule — kept only when `phase-5-done.md` §5.3's full exception condition holds), and emit the restart-session warning on a re-run plugin-version delta. Exit when the state file is deleted (or deliberately kept per the exception) and the final report has been printed.

## State file schema

Path: `<PRIMARY_ROOT>/.geniro/state/setup/state.md`. Durable singleton at the T1.5 tier, with one deliberate, named exception to that tier's survives-past-ship rule: `/geniro:setup` deletes the file at Phase Done (§5.3). Bootstrap state describes a one-shot run that is over — no downstream skill reads it, and a stale copy makes the next invocation resolve to `re-run` against a run that already finished. The exception is scoped to this one path; every other T1.5 file survives. Full frontmatter + body-section schema: `${CLAUDE_PLUGIN_ROOT}/skills/setup/setup-state-reference.md` — read it before every state write.

## Cross-references

- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` — singleton state-file tier definition (`/geniro:setup` writes a T1.5 durable file, deleted at Phase Done per the named exception in §State file schema) and body sections (Tool log, Errors, Open Questions, Persisted approvals, Termination reason).
- `${CLAUDE_PLUGIN_ROOT}/skills/setup/setup-rerun-reference.md` — every re-run-only procedure (§3.0 sweep, §3.1 pre-write audit, §3.4 merge rules, §5.4 restart warning); an `init` run never reads it.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/migration-walk.md` — the §3.0 re-run sweep's parse / auto-detect / classify / re-verify procedure, shared with `/geniro:update`'s per-entry walk.
- `${CLAUDE_PLUGIN_ROOT}/skills/setup/verification-checks.md` — §Excluded content (what must never reach CLAUDE.md, applied at §3.2 generation and at Validate) plus the contamination + template-residue check set the §4.1 verification subagent runs (single source for the per-language wrong-token table).
- `${CLAUDE_PLUGIN_ROOT}/skills/setup/instruction-templates/instruction-file-scaffolds.md` — the `plan.md` / `implement.md` scaffolds §3.3 writes before merging an OpenSpec block into a file that does not exist yet.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` — L2 base schema with `trust:` field and emit trigger table; the §4.3 `discovery` row conforms and matches the bootstrap trigger.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` — Evidence Block standard; §1.4 conforms.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` — model tiering; the verification subagent's `sonnet` carve-out is stated in §Subagent model tiering (section merge runs orchestrator-inline, no separate model assignment).
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gitignore-negation.md` — the §3.5 `.gitignore` re-include procedure that keeps `.geniro/workflow/` and `.geniro/instructions/` committed.
