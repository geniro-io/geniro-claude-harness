---
name: geniro:plan
description: "Use to turn а vague idea or feature request into an approved spec.md before /geniro:implement. Spec-first planning workflow: explore → clarify (≤5 questions) → propose 2-3 approaches → approve sections → write spec.md → mechanical validate → user approve → hand-off. Absorbs legacy /brainstorm + /decompose. Skip for well-formed specs already authored — use /geniro:implement <path> directly."
allowed-tools: [Read, Write, Bash, Glob, Grep, Task, AskUserQuestion, TodoWrite, WebSearch, WebFetch]
model: opus
argument-hint: <topic-string-or-design-doc-path>
---

# /geniro:plan — Spec-first planning (M5)

Turn а vague idea into an approved `spec.md` that `/geniro:implement` can consume directly. This skill is а thin wrapper around the canonical 9-phase loop в `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-loop.md`. It applies the loop verbatim and replaces pre-M5 `/geniro:brainstorm` + `/geniro:decompose` (master plan §65 — /decompose is absorbed via Phase 5 §5.3 milestone-mode).

**Spec source:** `architecture/M5-plan-redesign.md`. Read this skill в context of the architecture spec — every decision и trade-off is documented there.

**Output:**
- spec.md at `.geniro/planning/<task-slug>/spec.md` с the fixed 10-section P-M5-1 schema (§17), goal-state frontmatter (§18), и all three design-doc detection markers per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`.
- For Big tasks: sibling `milestone-N.md` files (§12.3 milestone-mode replaces deleted /decompose).
- state.md at the same task-dir tracking phase progress + AUQ answers (P-M1-1 schema).
- `git commit` of spec.md (+ milestones) — fires at Phase 8 post-approve, NOT Phase 6 (D1 defect fix).
- Phase 9 hand-off — 2-option menu (`/implement directly` / `Stop`).

The HARD-GATE в `plan-loop.md` prevents any implementation invocation until Phase 8 user-approve returns "Approve".

---

## When to use

- User has an idea but no spec yet.
- $ARGUMENTS contains а topic string OR а path to an existing design doc.
- Topic spans new functionality (vs а bug fix, which routes к `/geniro:debug`).
- Pre-implementation refinement (vs in-implementation tweaks, which route к `/geniro:implement` with the original spec + adjustment description as new $ARGUMENTS — М4 absorbs the legacy /follow-up).

## When NOT to use

- Spec already written → use `/geniro:implement <design-path>` directly. Detection is automatic per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`.
- Bug к fix → `/geniro:debug` for root cause; `/geniro:implement` for the patch.
- Code-file path (NOT а design doc) passed as $ARGUMENTS → error per Phase 0 §0.1 (design-doc-detect CODE_REFERENCE branch).

---

## Phase structure (M5 §2.1 state machine)

```
[entry]
  └── mode-detect ──┬── explore ──┬── clarify ──┬── approaches ──┬── section-approve ──┬── write-spec ──┬── validate ──┬── user-approve ──┬── handoff ──┬── done
                    │             │             │                │                     │                │              │                  │             │
                    └── aborted (terminal)                                                                                                                └── (terminal)
                    
phase-8-escalated ──┬── user-approve (Approve as-is)
                    ├── write-spec (Re-revise)
                    └── aborted
```

**Terminal states:** `done`, `aborted`. M3 SessionStart treats both as «planning complete or cancelled — no resume needed».

**Phase contracts** are defined в `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-loop.md`:

| Phase | Purpose | Plan-loop section |
|---|---|---|
| 0 | Mode detect | §"Phase 0 — Mode detect" |
| 1 | Explore (effort-tier-scaled spawns + L4+L3+L2 refresh) | §"Phase 1 — Explore" |
| 2 | DROPPED (visual companion removed — М5 §3.1) | §"Phase 2 — DROPPED" |
| 3 | Clarifying questions (≤5 one-at-a-time) | §"Phase 3 — Clarifying questions" |
| 4 | Approaches (2-3 with Recommended first) | §"Phase 4 — Approaches" |
| 5 | Section approval (fixed 10-section schema, milestone-mode) | §"Phase 5 — Section approval" |
| 6 | Write spec.md (NO auto-commit) | §"Phase 6 — Write spec.md" |
| 7 | Mechanical validator (13 checks) | §"Phase 7 — Mechanical validator" |
| 8 | User approve (schema-rich AUQ + git commit) | §"Phase 8 — User approval" |
| 9 | Hand-off (2 options: /implement / Stop) | §"Phase 9 — Hand-off" |

Execute `plan-loop.md` end-to-end. The loop encodes every defect fix (M5 §5 D1-D5) и P-M5 schema gap (P-M5-1 through P-M5-5).

---

## Loop invariants (M5 §2.2)

These 7 invariants apply throughout all phases. Identical к М4 §2.2 conceptually; phase numbers и tool surface differ.

1. **One result per tool call.** Every AskUserQuestion / Write / Bash / Agent spawn produces exactly one structured result. Failed AUQ (empty-answer bug) → fall back к plain-text re-ask; never auto-default.
2. **Args validated before execution.** Bash commands constructed from $ARGUMENTS или state.md fields pass input sanity-checks. Path-based detection (design-doc-detect.md) validates file existence before treating $ARGUMENTS as а path.
3. **Permission before side-effect.** Phase 6 `Write` к `.geniro/planning/<task-dir>/spec.md` is the only mutation in the loop. `git commit` deferred к Phase 8 post-approval. No auto-mutations elsewhere — enforced by the §19 plan-mode mutation guard (frontmatter `allowed-tools` minus `Edit`; PreToolUse Bash guard allows `Write` only под `.geniro/planning/**` или `.geniro/state/**`).
4. **Bounded и structured tool results.** Phase 1 Explore-agent output capped at ~4000 chars per agent; longer truncated с marker. Output schema: `[{file, lines, observation}]`. Phase 7 validator output is а structured pass/fail list per check.
5. **Escalation gates, not silent abort.** Phase 7 validator 3-round → AUQ. Phase 8 user-revision 3-round → AUQ. Phase 3 ≤5 questions → consolidation forced. NO Class-A hard kill caps (M5 §2.3 quality-first framing).
6. **Final answer grounded в observations.** Phase 5 section content MUST cite Phase 1 explore findings (`file:line` references) — not generic prose. Phase 7 validator includes а «citations present» check (P-M5-4 #3 source-materials criterion).
7. **Errors, denials, cancellations, timeouts → structured observations.** Phase 1 Explore-agent failures → structured entry в state.md `## Errors`. Phase 0 cancel → `## Termination reason`. Phase 7 validator findings → `## Open Questions`. Never silently skipped.

`## Tool log` schema (selective logging, per М5 §2.2):

```yaml
## Tool log
- ts: 2026-05-17T10:42:13Z
  tool: Agent
  detail: "Explore: existing auth flow"
  status: ok
  summary: "found 3 relevant files, 1 convention pattern"
- ts: 2026-05-17T11:08:00Z
  tool: Write
  detail: ".geniro/planning/<task-dir>/spec.md"
  status: ok
  result_ref: "1247 bytes"
```

Each entry written via M1 `atomic_state_write`. AUQ calls do NOT need logging — `approvals[]` is the structured record.

---

## Budgets — quality-first framing (M5 §2.3)

М5 has **NO hard kill caps**. All limits are **escalation gates that surface к user**, не abort triggers. User tokens unlimited — no «task aborted: budget exhausted» failure modes.

**Quality gates (Class-B — escalate к user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Phase 3 clarifying-question count | ≤5 one-at-a-time AUQs | plan-loop.md §3.4 | Force consolidation OR proceed с stated assumptions. |
| Phase 7 → Phase 6 auto-revision rounds | 3 | plan-loop.md §7.3 | AUQ — accept-as-is / re-revise / abort. |
| Phase 8 user-revision rounds | 3 | plan-loop.md §8.3 | AUQ — accept-as-is / re-revise / abort. |
| Phase 1 Explore-agent output size | ~4K chars per agent | invariant #4 | Truncation с marker, not abort. |

**Architecture constraints (design intent, not budget):**
- Parallel Explore spawns per Phase 1: 1-4 (effort-tier-scaled per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`).
- spec.md section count: exactly 10 (§17 P-M5-1 schema).

**Explicitly NOT capped:** wall-time, total tool calls, total model turns, total cost. Same rationale as М4 §2.3.

**Rationale.** Master plan §102 phrasing «≤3 AUQ gates per-run, ≤5 helper reads, ≤5 spawns» applies к /implement, NOT /plan. /plan is а **clarification-heavy** skill — its job IS к ask questions (Phase 3 ≤5 + Phase 4 1 + Phase 5 up к 10 per-section + Phase 8 1 → ~17 AUQs typical, не 3). The pre-redesign /brainstorm shipped that pattern и user feedback was positive — М5 preserves it.

---

## State persistence (M1 + M5)

**Task directory** (M1 T1): `.geniro/planning/<task-slug>/`

**state.md frontmatter (M1 §T1 + M5 §7.3):**

```yaml
---
tier: T1
producer: plan
schema-version: 1
branch: <git-branch>
worktree: <git-rev-parse-show-toplevel>
timestamp: <ISO-8601 UTC>
phase: <state-machine-enum>
status: in-progress
non-resumable-actions: []
approvals: []
task_slug: <slug>
mode: <IDEA|DESIGN_DOC>
---
```

**Write contract.** Every state.md mutation goes through `atomic_state_write` from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.sh`. NEVER direct `Edit`/`Write` on canonical state paths — the State-helper enforcement hook will warn (and в M1 PR-final, hard-block). The §19 plan-mode mutation guard restricts Write tool to `.geniro/planning/**` OR `.geniro/state/**` while а /plan run is active.

**Validation before resume.** When Phase 0 detects а pre-existing state.md (resume path), pre-flight via `validate_state_file`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.sh"
if ! validate_state_file ".geniro/planning/<task-slug>/state.md"; then
  # Open recovery AskUserQuestion (delete-and-restart / open-in-editor / update-worktree-path / skip-emergency)
  ...
fi
```

---

## Memory I/O (M5 §21)

Full Phase 1 entry inventory + per-phase write sites. See `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-loop.md` §1.1 для full call signatures.

| Phase | Helper | Direction | Notes |
|---|---|---|---|
| Phase 1 entry | `load-custom-instructions` (MODE: refresh) | read L4 | scope = `plan` + `global` + `code-style` |
| Phase 1 entry | `load_semantic` | read L3 | top-2 default; fingerprint drift check |
| Phase 1 entry | `query_learnings` | read L2 | tags inferred от $ARGUMENTS topic |
| Phase 1 entry | `resolve-conflicts` | read protocol | fires only if L4/L3/L2 disagree |
| Phase 6 | `atomic_state_write` | write T1 | state.md `## Tool log` after spec.md Write |
| Phase 7 (hard-fail) | `atomic_state_write` | write T1 | state.md `## Open Questions` |
| Phase 8.4 | `atomic_state_write` | write T1 | state.md `non-resumable-actions[]` after git commit |
| Phase 8.5 (conditional) | `emit_learning` | write L2 | `decision` type when Phase 4 had ≥2 approaches с trade-off |

**Default trust для L2 emits**: `verified` (planning decisions are user-validated via Phase 8 AUQ).

**Cross-layer conflict surfacing (M2 §10):** when L4/L3/L2 reads disagree, apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md` protocol — soft conflict prints notice and continues; hard conflict halts с AUQ.

---

## ACI per-phase tool surface (M5 §21.5)

| Phase | Allowed | Blocked |
|---|---|---|
| Phase 0 (Mode detect) | Read / Bash (read-only: `ls`, `file`) | All mutations |
| Phase 1 (Explore) | Read / Grep / Glob / Bash (read-only) / Agent (Explore spawn) | Edit / Write outside state.md |
| Phase 2 | DROPPED | — |
| Phase 3-5 (Clarify / Approaches / Section approve) | Read / Grep / Glob / AskUserQuestion / Write (state.md only via atomic_state_write) | Edit / mutating Bash |
| Phase 6 (Write spec) | Write (scoped к `.geniro/planning/**` by §19 guard) / atomic_state_write (state.md) | Edit / mutating Bash |
| Phase 7 (Validate) | Read / atomic_state_write (state.md `## Open Questions`) | All other mutations |
| Phase 8 (User approve) | AskUserQuestion / Bash (`git add`, `git commit` only) / atomic_state_write | Edit / general-purpose Bash |
| Phase 9 (Hand-off) | AskUserQuestion / Read | All mutations |

**Layer 1 enforcement:** frontmatter `allowed-tools` excludes `Edit` (this skill never edits в place).

**Layer 2 enforcement:** `hooks/plan-mode-write-guard.sh` — PreToolUse hook scopes Write к `.geniro/planning/**` OR `.geniro/state/**` when а /plan run is active. Bypass: `plan-mode-mutation` в `.geniro/safety.json` `allow_patterns`.

**Existing safety layer:** file-protection hook, git-guardrails, `.geniro/` deletion guard apply across all phases.

---

## Task execution entry

0. **Check for existing state.md.** Glob `.geniro/planning/*/state.md` for а file matching the resolved task slug:
   - **No state.md** → fresh run. Proceed к Phase 0.
   - **state.md exists, phase in non-terminal set** → resume from `phase:` value. M3 SessionStart hook re-injects context.
   - **state.md exists, phase в terminal set** (`done` / `aborted`) → task complete. Surface terminal state к user; if $ARGUMENTS carries а new topic, derive а new slug, fresh run.

1. **Validate state.md if found** (`validate_state_file`). On fail, open recovery AUQ.

2. **TodoWrite checklist.** Add: Phase 0 Mode detect / Phase 1 Explore / Phase 3 Clarify / Phase 4 Approaches / Phase 5 Section approve / Phase 6 Write / Phase 7 Validate / Phase 8 User approve / Phase 9 Hand-off. Mark Phase 0 in_progress; update each as it completes.

3. **Begin Phase 0.** Execute `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-loop.md` end-to-end.

---

## Anti-rationalization

Per master plan P-MP-1 anti-patterns guardrail — М5 must NOT reintroduce these:

| Your reasoning | Why it's wrong |
|---|---|
| "Phase 2 visual companion should stay — it's nice when planning UI." | UI intent that matters belongs в spec.md section 6 (Steps) и section 9 (Validation). The companion's textual sketch dies в chat — it's not cited by Phase 6 spec.md write. Phase 5 sections absorb the intent at the right granularity. |
| "Phase 0 Refine path saves three phases of re-work — keep it." | Refine re-derived sections от prose — structurally-lossy. М5 D3 fix: «Start fresh с doc as context» is honest и produces а schema-clean spec.md. |
| "Phase 7 mechanical validator misses cases а smart LLM would catch." | 13 checks (P-M5-4 9 + 4 legacy linter) cover the mechanical surface. Phase 8 user-approve catches everything else — the user IS the smart-LLM check. |
| "Auto-commit at Phase 6 is convenient — drop а commit if Phase 8 rejects." | D1 fix. Rejection-induced commit-drop = forced `git reset` / `git revert`. Pre-M5 pattern polluted git history (every revision round left а commit). Phase 8 post-approve commit is а single commit per approved spec. |
| "Plan-mode mutation guard is over-engineered — model can be trusted." | The model can be reasoned-with, jailbroken, или instructed via а compromised CLAUDE.md. The frontmatter `allowed-tools` field + PreToolUse Bash guard are the only mechanical layers between а bad-intent prompt и а modified source tree. Belt + suspenders. |
| "Goal-state в spec.md frontmatter conflates planning + execution — split к goal.md." | One canonical source per H-2. М4 /implement already reads spec.md frontmatter at Phase 1 — adding goal-state к the same place is zero-overhead. Splitting creates а two-file consistency problem. |
| "5 clarifying questions is too few для complex tasks." | Phase 3 ≤5 is а quality-first signal. >5 means Phase 1 underspecified OR the task is too vague. Force consolidation — better questions, не more questions. |
| "10-section spec.md schema is too rigid для small tasks." | Sections 4 / 5 / 10 can be «none с rationale» for Trivial. The schema is structural commitment (every consumer can rely on section presence), не content commitment. |
| "Phase 7 validator hard-fail blocks user — they're stuck с auto-revision rounds." | 3-round escalation cap. On round 3, AUQ surfaces к user с «accept as-is» option. User has agency at all times. |
| "Drop the milestone-mode AUQ — а Big task can just emit а spec и the user decides later." | Slicing into milestones IS а planning decision. Punting it к /implement time means the user discovers а 50-step spec is unmanageable, и must come back к re-plan. Phase 5 §5.3 surfaces the choice when context AND attention are present. |
| "Hand-off menu should keep `/features add`." | /features deleted (master plan §68). А spec.md saved on disk IS the backlog entry. |
| "Add а wall-time / token kill cap so runaway /plan sessions abort cleanly." | Class-A hard caps forbidden by §2.3. Class-B gates only (Phase 3 ≤5, Phase 7 3-round, Phase 8 3-round) — все escalate к user, не abort. |
| "Auto-default empty AUQ answer к the Recommended option." | Forbidden. Empty answer = upstream Claude Code bug; fall back к plain-text re-ask. Auto-default silently mutates user intent. |
| "Skip persisting Phase 3 clarifying answers — they're trivial." | Metaswarm anti-pattern. Compaction mid-Phase-5 round 2 loses 5 AUQs of user input. P-M1-1 `approvals[]` persistence is non-negotiable. |
| "Bypass git pre-commit hooks с --no-verify when committing spec.md в Phase 8.4." | Hooks fail для а reason. Investigate root cause, не bypass. CLAUDE.md-level prohibition; M5 honors it. |

---

## REFERENCE

- Phase contracts (canonical): `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-loop.md`
- 10-section spec.md template: `${CLAUDE_SKILL_DIR}/spec-template.md`
- 13 validator checks: `${CLAUDE_SKILL_DIR}/validator-checks.md`
- Design-doc detection: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`
- Effort scaling: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`
- State helpers: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.sh`, `validate-state-file.sh`
- Memory helpers: `load-custom-instructions.md` (L4 directive), `load-semantic.sh`, `query-learnings.sh`, `emit-learning.sh`, `resolve-conflicts.md`
- Mutation guard hook: `${CLAUDE_PLUGIN_ROOT}/hooks/plan-mode-write-guard.sh`
- Architecture spec: `architecture/M5-plan-redesign.md`
- Edge cases + alias note: `${CLAUDE_SKILL_DIR}/plan-reference.md`
