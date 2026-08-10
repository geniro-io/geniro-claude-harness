---
name: geniro-onboard
description: "Use when starting fresh in an unfamiliar codebase and need rapid orientation. Scans structure and conventions; produces _CODEBASE_MAP.md with architecture, module graph, critical paths, entry points. Skip for specific Q&A (/geniro:investigate) or bug investigation (/geniro:debug)."
context: main
model: inherit
allowed-tools: [Read, Bash, Glob, Grep, Agent, AskUserQuestion]
argument-hint: "[optional: --focus area1,area2 --depth N --cap N]"
---
<!-- Generated from skills/onboard/SKILL.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->


# Onboard: rapid codebase orientation

## Contents

- Arguments
- Outputs — the 8-section `_CODEBASE_MAP.md` template
- State machine
- Loop invariants
- Anti-rationalization
- Quality-first budgets
- ACI per-phase tool surface
- Definition of done
- Phase 1 — Discover
- Phase 2 — Map
- State file schema

---

2-phase loop (Discover → Map). Generates a structured map that serves as a reference for the session.

**Runtime portability.** `${CLAUDE_PLUGIN_ROOT}` is set by Claude Code. When it is unset (another Agent-Skills runtime, e.g. Cursor), resolve it before following any reference: the plugin root is the ancestor directory of this file containing `.claude-plugin/plugin.json` — substitute it for every `${CLAUDE_PLUGIN_ROOT}` occurrence and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md` before deciding a step cannot run here — it substitutes mechanisms, not steps.

## Arguments

- **No arguments** — full codebase scan; produces the 8-section `_CODEBASE_MAP.md` (default mode).
- `--focus area1,area2,...` — scope-limiter. Scans all, but concentrates the map output on focus areas; non-focus areas get summary-level coverage.
- `--depth N` — limit directory scanning to N levels deep. Useful for large monorepos where full traversal is too slow. Orthogonal to `--focus` (combine as needed).
- `--cap N` — raise the default read budget to N (cap owned by §1.3 Step 2). Pass it up front; the budget is not raised mid-run.

Combined examples: `--depth 2 --focus auth,api` (scan monorepo at depth 2, concentrate on auth+api).

## Outputs

**Primary artifact:** `<PRIMARY_ROOT>/.geniro/planning/_CODEBASE_MAP.md` (underscore-prefixed L3 registry). Resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A so the map persists across worktrees and isn't lost when a linked worktree is removed.

8-section template:
1. **Project Overview** — name, purpose, language/stack, entry points
2. **Directory Structure** — file organization, key folders
3. **Module Relationships** — module dependency graph
4. **Architecture Patterns** — recurring design patterns (MVC, DDD, Hexagonal, etc.)
5. **Key Files & Configuration** — package.json, tsconfig, docker-compose, migrations
6. **Conventions & Defaults** — naming, testing patterns, error handling
7. **Critical Paths** — user request flow, deployment pipeline, job system
8. **Tech Debt & Notes** — gotchas, legacy code, anti-patterns

When `--focus <area1,area2>` is provided: sections 3 / 4 / 6 / 7 concentrate detail on the focus areas; non-focus areas appear as one-line summary entries. Sections 1 / 2 / 5 / 8 cover the full scanned scope regardless of focus.

**Map quality bar** — two checks: an executable one (`wc -l` on the written file: under 1000 lines) and a rubric one (skimmable in 5 minutes — a reader gets oriented from headers and summaries alone, without reading every entry).

## State machine

```
[entry]
  └── discover ──┬── aborted (terminal — user picks 'Abort' at the repo-size cap)
                 ├── routed  (terminal — empty/near-empty repo, recommend `/geniro:investigate`)
                 └── map ──┬── done
                           └── map-truncated (terminal — user picked 'Truncate at top 50'; map ships from truncated scan)
```

Terminal states: `done`, `map-truncated`, `aborted`, `routed`. The SessionStart recovery treats all as "task complete — no resume". Non-terminal states (`discover`, `map`) roll back to phase-entry on compaction-resume and re-run idempotently.

## Loop invariants

The canonical agent-loop invariants in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` apply throughout /geniro:onboard, with two onboard-specific bindings:

- **Invariant #4 (bounded structured tool results)** — repo-scan output (file list, directory tree) is bounded; long lists truncated with marker.
- **Invariant #7 (errors → structured observations)** — permission errors during scan and missing access become `## Errors` body section entries.

This skill adds one invariant:

S1. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default codebase-research tool; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

**`## Tool log` section in state.md:** selective logging — log L3 writes (`_CODEBASE_MAP.md` write via `update-semantic`), L2 emits (`discovery` calls), and escalation entries. Routine Read / Bash skipped.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "Let me document every file" | Exhaustive maps are unreadable. Sample key files, focus on structure and relationships. |
| "I need more detail on this module" | The codebase map captures architecture, not implementation. Module-level detail belongs in the code; the map's job is orientation. |
| "The code is self-documenting" | Code shows what, not why. Note the critical paths (user flow, deploy flow) and what's unclear. |
| "I'll create the map and move on" | A map nobody references is waste. Update it as you learn more, reference it when planning. |
| "The repo has 5000 files but I'll just scan everything — better safe than sorry" (or "it's monorepo-scale, so bypass the cap silently" / "add a wall-time kill cap so long discovery aborts cleanly") | Both directions break the same contract. The read budget — not a hard abort — is what bounds cost: sample the most relevant files and record what was covered in `## Scope`. Expansion is explicit (`--cap N` up front, or the §1.3 Step 2 AUQ), so raising it on your own authority defeats the cost control; a wall-time kill cap would abort legitimate complex discovery mid-stride, and a repo too large for the sample to represent already escalates via that AUQ. |
| "Defer compaction-survival to downstream skills — /geniro:onboard is mostly scan." | The contract IS /geniro:onboard's contract — state.md frontmatter, `approvals[]`, `## Tool log`, `## Errors`. Without them, compaction mid-scan loses scan progress and the user re-runs from scratch. The `## Tool log` in particular is what records the scan process — which directories were covered, which raised permission errors — so a failed onboard stays diagnosable without repeating the whole scan. |

## Quality-first budgets

No hard kill caps — the quality-first doctrine in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §"Budgets — quality-first (canonical)" applies. All limits below are escalation gates that surface to the user.

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Repo-size scan cap | owned by §1.3 Step 2 (override via `--cap N`) | §1.3 Step 2 | A repo too large for that sample to represent it escalates via AUQ — §1.3 Step 2 owns the threshold, the option list and the `approvals[]` persistence. |

**Architecture constraints (design intent, not budget):**
- No parallel agent spawns — /geniro:onboard is a solo orchestrator skill. The codebase scan that produces `_CODEBASE_MAP.md` runs orchestrator-inline (Read / Grep / Glob / read-only Bash) so the orchestrator owns the synthesis end-to-end; for narrow locator side queries during the scan (e.g., "where is the build entry point defined?"), spawn `codebase-research-agent` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

## ACI per-phase tool surface

**Phase 1 (Discover):**
- Allowed: Read / Grep / Glob / Bash (read-only commands: `git status`, `find . -type f`, `wc -l`) / AskUserQuestion (the §1.3 repo-size-cap expansion gate).
- Explicitly blocked: production-source Edit/Write, `git add` / `git commit` / `git push`. Agent spawns limited to `codebase-research-agent` for narrow locator side queries during the scan (no parallel agent spawns — /geniro:onboard is a solo orchestrator skill).

**Phase 2 (Map):**
- Allowed: Read / `update-semantic` (the lock-guarded write mechanism for `_CODEBASE_MAP.md`) / `update_fingerprint` / `emit-learning` helper invocations / AskUserQuestion / Bash (`atomic_state_write` for state transitions; the §2.5 cleanup of the run's scratch state).
- Explicitly blocked: direct `Write`/`Edit` to `_CODEBASE_MAP.md` (route through `update-semantic` — `.geniro/planning/_*.md` is a guarded persistent path), production-source Edit/Write, `git add` / `git commit` / `git push`.

The safety hooks apply across every phase; the complete list and what each blocks is in `${CLAUDE_PLUGIN_ROOT}/HOOKS.md`. Runtime denies stay enforced.

---

## Definition of done

These are the load-bearing exit gates — the invariants that, if skipped, make the onboarding incomplete or unsafe. The 8-section map content is enforced by the §2 template, not re-listed here.

- [ ] `_CODEBASE_MAP.md` created/updated at `<PRIMARY_ROOT>/.geniro/planning/_CODEBASE_MAP.md` via `update-semantic`, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md`
- [ ] Every critical path the scanned scope exposes is traced and documented, or `## Critical Paths` says none was found
- [ ] Map line count under 1000 (`wc -l` on `_CODEBASE_MAP.md`; use `--focus` for large repos)
- [ ] Map is skimmable in 5 minutes — headers and summaries alone orient a reader (§Outputs)
- [ ] Project-snapshot fingerprint refreshed via `update_fingerprint` (per §2.2)
- [ ] L2 `discovery` emit fired per trigger conditions
- [ ] Next-steps suggestions printed at the end of the report (per §2.4)
- [ ] State.md cleaned up per §2.5

---

## Phase 1 — Discover

State.md `phase: discover`. Low cost — a repo-size scan + Glob + initial Read of project entry files. Exits to Phase 2 only when scan is bounded and repo-size cap is respected.

### 1.1 Step 0 — Mode detect

Parse `$ARGUMENTS` per §Arguments and echo the resolved mode. Transient — no state.md row.

### 1.2 Step 1 — Load custom instructions + past learnings

On Phase 1 entry:

1. **Load custom instructions** — `load-custom-instructions(SKILL_SLUG: onboard, LOAD_TIER: pipeline, MODE: initial-load)` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` § Echo contract.
2. **Refresh project snapshot** — `load-semantic` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-semantic.md` default top-2 (`_project.md` + `_CODEBASE_MAP.md`). If `_CODEBASE_MAP.md` already exists, the previous map is loaded as context (informs incremental update strategy). `CODEBASE_MAP.md` (without underscore) is also read once for compatibility.
3. **Query past learnings** — route per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.md` §"Memory backend override" (a declared `## Memory Backend` block redirects this to its read tool; under `mode: replace` the local file is empty, so only the backend read recalls anything), else `source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh" && query_learnings --tag onboard --scope global --limit 5`. Surfaces prior architectural decisions and gotchas relevant to the scan (matches the `scope: global` discovery entries this skill emits in §2.3).
4. **Cross-layer conflict resolution** — `resolve-conflicts` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md` (precedence: custom instructions > project snapshot > past learnings when layers disagree; halt with AUQ on hard conflict).

Echo lines are mandatory per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` § Echo contract.

### 1.3 Step 2 — Bounded repo scan

**Procedure:**

1. **Top-level discovery** — `Glob("*")` at repo root (`pwd` resolved via `git rev-parse --show-toplevel`). Read top-level structure markers: README.md, package.json / pyproject.toml / Cargo.toml / go.mod, .github/, src/.
2. **Estimate scan size** — count the repo's source files, honoring its ignore rules and any `--depth N`; record `scan_depth: N` in state.md frontmatter so Phase 2 mapping honors the same bound.
3. **Apply the read budget:** sample within it — files chosen for relevance (entry points, manifests, top-level modules), not directory order — and proceed: 50 files by default, `--cap N` to raise it, `--focus` to narrow what gets sampled, `--depth N` to bound traversal. Proceeding is the default because the question is unanswerable before the user has seen anything about the repo, and the budget already bounds the cost. Escalate only when the repo is large enough that a 50-file sample can no longer represent it (50,000+ files) and no `--focus` or `--cap` was given: auto-apply `--depth 2` so traversal doesn't stall, then fire the repo-size scan cap AUQ — header "Repo-size cap":
- **"Narrow to specific areas"** — user supplies focus areas (the `--focus <area>` flag); re-run scan with that filter.
- **"Expand scan (specify cap)"** — user provides explicit cap (e.g. 200, 500). **Persists to state.md `approvals[]` with category `expand_scope`.**
- **"Truncate at top 50"** — proceeds with top 50 most-likely-relevant files. Terminal state on completion: `map-truncated`.
- **"Abort"** — terminal `aborted`.

**Approvals-persistence:** before firing the expand-scope AUQ, check state.md frontmatter `approvals[]` for a prior entry with `category: expand_scope`. If found, use prior `picked` (typical compaction-resume scenario). The state.md `## Persisted approvals` section renders this.

**Edge cases:**
- **Empty or near-empty repo** (no source files found): terminal `routed` with suggestion "Repo appears empty. Use `/geniro:investigate` to clarify project state." Write the terminal phase first, then run the §2.5 cleanup, as with every other terminal exit.
- **Permission errors on key directories** — log to `## Errors` body section; note gaps in final map's `## Tech Debt & Notes`.

### 1.4 Step 3 — Scan structure

Within the scanned scope, gather the evidence sections 1 / 2 / 5 of the map need — directory structure, stack and tooling, and the files that configure them.

State.md update: `phase: discover` → `phase: map`. `## Scope` body section captures the scanned-file list + applied cap.

---

## Phase 2 — Map

State.md `phase: map`. Builds `_CODEBASE_MAP.md` (underscore-prefixed) with the 8-section template + optional `--focus` concentration.

### 2.0 Refresh custom instructions

**Refresh custom instructions** — `load-custom-instructions(SKILL_SLUG: onboard, LOAD_TIER: pipeline, MODE: refresh)` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` § Echo contract. Compaction since Phase 1's initial load may have silently dropped the rules — re-Read and echo before composing the map.

### 2.1 Compose the codebase map content

Canonical path: `<PRIMARY_ROOT>/.geniro/planning/_CODEBASE_MAP.md`. Resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A so the map persists across worktrees.

Compose the map content in-context using the 8-section template from §Outputs above — do not write it to disk yet. Apply `--focus` concentration per the rule in §Outputs (sections 3 / 4 / 6 / 7 concentrate on focus areas; 1 / 2 / 5 / 8 stay full-scope). §2.2 persists the composed content through the `update-semantic` helper.

### 2.2 Persist the codebase map

Persist the composed map through `update-semantic` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/update-semantic.md` — that helper IS the write mechanism, holding the `.codebase-map.lock` for an atomic lock-guarded write. Do NOT write `_CODEBASE_MAP.md` with the `Write` tool directly: `.geniro/planning/_*.md` is a guarded persistent path and a direct write trips the state-helper enforcement hook and double-writes the file.

Call it with `--file codebase-map` per its §API; the branch this skill has to decide is which operation each piece of the composed map takes:

- **First onboard** (no prior map) — append the whole map, split into section-sized blocks so each stays under the helper's per-call byte ceiling. Append creates the file if it is missing.
- **Incremental re-run** (prior map exists) — replace each changed entry by its line prefix; append the genuinely new ones. Never re-append a section the map already carries.

Exit codes (including the over-ceiling and lock-held cases) and the defer-and-retry pattern for a held lock belong to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/update-semantic.md` §API — apply them from there rather than from memory.

After the map persists, refresh the project-snapshot fingerprint — `update_fingerprint` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-semantic.md` §API. Every other skill's staleness check compares the current stack files against that fingerprint; leaving it stale keeps the "re-run /geniro:onboard" warning firing after a successful onboard, which teaches users to ignore the one signal that says the map is out of date.

### 2.3 Record what the scan learned

After `_CODEBASE_MAP.md` write:

- `emit-learning` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` — emit a `discovery` type entry. Required `ext.{area, insight}`. Default trust `verified` (code-grounded). After a successful emit, echo `Recorded learning: <summary>` to the user, per that file's §"Caller contract". Exact payload: `${CLAUDE_PLUGIN_ROOT}/skills/onboard/onboard-reference.md` §2.

**Trigger:** emit on **first successful onboarding of a new codebase** OR **major architectural shift detected** (existing `_CODEBASE_MAP.md` content significantly diverges from previous version — heuristic: compare section counts / module-count delta / new top-level entries). Skip when re-running onboard against a stable codebase (no architectural change).

### 2.4 Print next steps

After the map ships, end the onboarding report with a printed "Next steps" block — suggestions only, no question:

```
### Next steps
- Run `/geniro:plan <idea>` to draft an approved spec for a feature against the new map.
- Run `/geniro:investigate <question>` to dig deeper into a subsystem.
- Run `/geniro:implement <task>` to design and build a change directly.
- Review `_FEATURES.md` (the manual feature backlog), or run `/geniro:plan` to author one.
```

### 2.5 Cleanup

Run this after EVERY terminal `phase:` write — `done`, `map-truncated`, `routed`, and `aborted` alike, not only the happy path — never before: the write's own `mkdir -p` would silently recreate a slug dir a preceding cleanup just removed, leaving it behind despite cleanup having "run". The migration walk scans `.geniro/planning`, never `.geniro/state`, so a slug directory left behind by an early exit has no later sweep and persists indefinitely.

State.md `phase: map` → `done` on the happy path. Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Cleanup contract:

```bash
rm -rf .geniro/state/onboard/<slug>/ 2>/dev/null || true
```

**Persistent artifacts STAY:** `_CODEBASE_MAP.md` is T3 — never auto-deleted.

---

## State file schema

Path: `.geniro/state/onboard/<slug>/state.md` (cwd-relative — within-skill resume-from-compaction state per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` § "Artifacts NOT in scope"; compute `<slug>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Slug rules).

Write via `atomic_state_write` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"
atomic_state_write ".geniro/state/onboard/<slug>/state.md" <<EOF
---
tier: T1.5
producer: onboard
schema-version: 1
branch: <git-branch>
timestamp: <ISO-8601 UTC>
phase: <discover|map|done|map-truncated|aborted|routed>
status: <in-progress|done|failed>
non-resumable-actions: []
approvals: []
geniro_kind: onboard-state
geniro_schema_version: m9-v1
task_slug: <slug>
worktree: <abs-path>
focus_areas: []
scan_cap: <N>          # default owned by §1.3 Step 2
scan_depth: <N|null>
---

## Scope
<files / symbols / top-level dirs scanned; applied cap; --focus areas if any>

## Codebase Map Draft
<incremental scan results before final _CODEBASE_MAP.md write>

## Tool log
<selective logging — L3 writes, L2 emits, escalation entries>

## Errors
<permission errors, tool failures>

## Termination reason
<— only on terminal aborted/routed states; >

## Persisted approvals
<render of frontmatter approvals[] (category: expand_scope)>
EOF
```

`approvals[]` populated when the expand-scope AUQ fires at §1.3 Step 2 (category `expand_scope`).

## State recovery

On skill start: compute `<slug>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` §Slug rules, Glob `.geniro/state/onboard/<slug>/state.md`. If present: source `${CLAUDE_PLUGIN_ROOT}/lib/validate-state-file.sh` and run `validate_state_file` on it — on failure fire the recovery AskUserQuestion from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md` instead of consuming a corrupt file. On pass, run the helper §Consumer contract (Case A/B/C/D mismatch handling) — a same-cwd resume against a different branch's state file otherwise consumes it silently — then resume from the next incomplete phase.

---

## _CODEBASE_MAP.md format example

Full 8-section worked example (sample TypeScript/Express project) in `${CLAUDE_PLUGIN_ROOT}/skills/onboard/onboard-reference.md` §1. The 8-section template in §Outputs is the operative spec; the example illustrates the rendering.
