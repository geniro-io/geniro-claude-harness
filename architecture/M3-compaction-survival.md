# M3 — Compaction-Survival Hook & Helper Refresh Contracts

**Status:** Specification (pre-implementation)
**Scope:** SessionStart hook redesign, additionalContext assembly, helper refresh contracts, corruption recovery flow, non-resumable-actions surfacing
**Depends on:** M1 (state-files framework — `validate_state_file`, `atomic_state_write`, T1/T2/T3 layout, `non-resumable-actions` schema); M2 (memory layer model — L1/L2/L3/L4, six shared helpers)
**Followed by:** M4+ (per-skill integration — every consumer SKILL.md declares its refresh sites, persists T2 handoff facts to state.md)

---

## 1. Purpose

Define how the plugin restores working context across the four `SessionStart` boundaries (compact / resume / startup / clear) so that:

- Working-surface state (active task, custom-instruction rules, spec) is re-established without skill-side ceremony.
- Domain memory (L3 semantic, L2 episodic) is loaded **on demand** through helpers, not duplicated by the hook.
- Corrupt T1 state files surface immediately with a fixed, three-option recovery flow — never silently partial.
- Side-effects already completed (`git push`, posted PR comments, dispatched notifications) are surfaced as **hard-imperative do-not-repeat** warnings.
- User explicit-reset intent (`/clear`) is respected.

---

## 2. Architecture overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  SessionStart event (source ∈ {compact, resume, startup, clear})             │
└─────────────────────────────┬────────────────────────────────────────────────┘
                              │
            ┌─────────────────┴─────────────────┐
            │  matcher: "compact|resume|startup"│  (clear is NOT matched)
            └─────────────────┬─────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  hooks/session-start-restore.sh         │
        │  ───────────────────────────────────────│
        │  1. Read $SOURCE from input             │
        │  2. Resolve active task via M1 slug     │
        │     + frontmatter branch fallback       │
        │  3. Pre-flight validate_state_file      │
        │     (M1 helper) — fail-fast on corrupt  │
        │  4. Parse non-resumable-actions[]       │
        │  5. Assemble additionalContext blocks   │
        │  6. Emit systemMessage one-liner        │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Next user turn — model sees:           │
        │  • Working surface pointers (Q1)        │
        │  • Recovery directive (if validation    │
        │    failed)                              │
        │  • Non-resumable warning (if any)       │
        │  • Resume protocol steps                │
        └─────────────────────────────────────────┘
                                      │
                                      ▼
        Model executes resume protocol:
        • Read state.md → identify phase
        • Invoke load-custom-instructions (MODE: refresh)
        • Invoke load-semantic (MODE: refresh) — fingerprint check fires
        • Read spec.md / plan.md as referenced by state.md
        • Continue from next incomplete phase
```

---

## 3. Trigger sources (Q9)

Hook registered as:

```json
"SessionStart": [
  {
    "matcher": "compact|resume|startup",
    "hooks": [
      {
        "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start-restore.sh",
        "statusMessage": "Restoring Geniro context..."
      }
    ]
  }
]
```

**Per-source behavior:**

| Source | Hook fires? | Phrasing prefix in additionalContext | Rationale |
|---|---|---|---|
| `compact` | yes | "Context was compressed by compaction." | Context partial — re-establish critical surfaces |
| `resume` | yes | "Restoring from prior session." | L4 may have been edited in parallel session; M1 schema may have bumped |
| `startup` | yes | "Active task detected at startup." (only if active task found) | Fresh launch + in-flight task → auto-orient |
| `clear` | **no** | n/a | User explicit reset; auto-reload disrespects intent |

**Silent-on-no-active-task:** when source is `startup` AND no active T1 state.md exists for the current branch, the hook still emits — but additionalContext contains only L4 rule pointers + CLAUDE.md (no "active task" block). systemMessage is suppressed in this case (avoid spam on cold launches).

---

## 4. Inject scope (Q1)

The hook restores **working surface only**. Domain memory is on-demand via helpers.

**Always injected (pointers, model performs the Reads):**

| File | Tier | Why |
|---|---|---|
| `CLAUDE.md` | project root | Project-level context |
| `.geniro/planning/<task-dir>/state.md` | L1 (T1) | Active task phase + resume anchor |
| `.geniro/planning/<task-dir>/spec.md` | L1 (T1) | Task specification |
| `.geniro/planning/<task-dir>/plan.md` | L1 (T1) | Execution plan (if present) |
| `.geniro/instructions/global.md` | L4 (T3) | Routed via `load-custom-instructions` (MODE: refresh) |
| `.geniro/instructions/code-style.md` | L4 (T3) | Routed via `load-custom-instructions` (MODE: refresh) |
| `.geniro/instructions/<active-skill>.md` | L4 (T3) | Routed via `load-custom-instructions` (MODE: refresh) |
| `.geniro/planning/_FEATURES.md` | T3 CRUD | Active feature backlog |

**Never injected by hook (skill-driven via helpers):**

- L3 semantic files (`.geniro/planning/_project.md`, `_CODEBASE_MAP.md`, etc. — M2 layout reconciliation 2026-05-18) — model invokes `load-semantic` (MODE: refresh) per resume protocol; fingerprint drift check fires once per refresh.
- L2 episodic (`learnings.jsonl`) — request/response only via `query-learnings`; never load-into-context wholesale.
- T2 handoff files (`from-<producer>-<branch>.md`) — see §9 (skill-driven; state.md is canonical resume payload).

---

## 5. Hook procedure

**Read-only guarantee:** `hooks/session-start-restore.sh` **never modifies state.md** under any source path. Hook responsibilities are restricted к: read state.md, run M1 `validate_state_file`, assemble `additionalContext`, emit `systemMessage`. If `validate_state_file` fails, the hook reports the failure (per Block 3 §6) but does not auto-repair. State writes are the consumer-skill's exclusive responsibility — this preserves the audit trail и keeps the hook idempotent across re-runs.

`hooks/session-start-restore.sh` (`git mv` from `post-compact-notification.sh`; see §11):

```
1. Consume stdin; extract:
   - .source  (compact|resume|startup|clear)
   - .cwd     (defensive — honor for cwd-relative reads)
2. If source == clear → exit 0 (no output).
3. Compute current branch slug per M1 §Slug rules.
4. Resolve active T1 state file (Q8):
   a. Try `.geniro/planning/<slug>/state.md`.
   b. If miss → glob `.geniro/planning/*/state.md`, grep frontmatter `branch:` field,
      match current branch (mtime tiebreak if multiple).
   c. If still miss → no active task; proceed to assembly with empty L1 block.
5. If active state file found → pre-flight validation (Q5):
   a. Invoke M1 `validate_state_file <path>` (sourced from shell helper).
      If helper script not present (M1 PR-0 has not landed) → set
      validation_status=skipped and add notice to additionalContext.
   b. On exit 0 → validation_status=pass.
   c. On non-zero → validation_status=fail (capture stderr line).
6. Parse frontmatter (yq):
   - producer (active skill)
   - spec-file pointer (state.md may reference it)
   - non-resumable-actions[]
7. Assemble additionalContext per §6.
8. Emit hookSpecificOutput.additionalContext + systemMessage (§10).
```

---

## 6. additionalContext assembly (template)

The hook emits ONE `additionalContext` string composed of fixed blocks. Blocks appear in this order; absent data → block omitted.

### Block 1 — Source-phrased prefix (always)

```
{compact: "Context was compressed by compaction (SessionStart source: compact)."
 resume:  "Restoring from prior session (SessionStart source: resume)."
 startup: "Active task detected at startup (SessionStart source: startup)."}
SKILL.md instructions and conversation nuance may have been lost — re-read these
files before continuing (the .geniro/instructions/* entries route through the
canonical loader, NOT direct cwd Reads; CLAUDE.md, FEATURES.md, spec/plan files
remain direct Reads):
```

### Block 2 — Suggested files (always)

```
- CLAUDE.md
- .geniro/planning/_FEATURES.md
- .geniro/instructions/global.md         (loader-routed, MODE: refresh)
- .geniro/instructions/code-style.md     (loader-routed, MODE: refresh)
[if active skill detected:]
- .geniro/instructions/<active-skill>.md (loader-routed, MODE: refresh)
[if state.md found and validation passed:]
- .geniro/planning/<task-dir>/state.md
[if spec-file frontmatter field present:]
- <spec-file-path>
[if plan-file present in task-dir:]
- .geniro/planning/<task-dir>/plan.md
```

### Block 3 — Validation failure recovery (only if validation_status=fail)

```
⚠️ STATE FILE FAILED VALIDATION
State file at <path> failed validation: <one-line-error>.
Do NOT resume from it.
On next turn, fire AskUserQuestion with the M1 recovery options:
  1. Delete state file and restart skill from spec   (lose in-flight state)
  2. Open file in editor and fix manually            (skill pauses; retry validation)
  3. Skip validation and continue (emergency)        (risk: silent corruption)
After user picks, follow the validation-helper recovery flow in M1 §Validation
helper. Suppress all state.md Reads below — pointer was withheld for safety.
```

When this block fires, **the state.md pointer in Block 2 is suppressed**. spec.md and plan.md pointers may still be present (they're separate files).

### Block 4 — M1 helper missing notice (only if validation skipped due to missing helper)

```
⚠️ M1 helpers not installed — validation skipped.
The state.md file was NOT validated by `validate_state_file` (M1 PR-0 has
not landed yet). Treat resumed state with caution — confirm `phase:` and
`status:` fields look sane before continuing.
```

### Block 5 — Non-resumable-actions warning (only if list non-empty)

Hook renders each entry from `non-resumable-actions[]` (M1 structured schema; see §8). For empty array → block omitted entirely.

```
⚠️ ALREADY COMPLETED in prior turns — DO NOT repeat:
  - git-push (target: origin/feature/dark-mode, ref: a3f9e2, completed: 2026-05-16T14:32:00Z)
  - pr-comment-posted (pr: 142, comment-id: 1834720, completed: 2026-05-16T14:35:00Z)
Resuming should re-validate code state but MUST NOT re-trigger these actions.
If a re-trigger is genuinely required (e.g., rebase + re-push), explicitly
acknowledge in your next message before performing it.
```

### Block 5b — Last-known errors (only if state.md body contains `## Errors` section)

Per master plan P-M3-1, if state.md body has а `## Errors` section, render its content verbatim into additionalContext с warning prefix. Convention: one bullet per failed approach с timestamp + tool + error reason + what was tried.

```
⚠️ ERRORS ENCOUNTERED IN PRIOR TURNS — do not repeat the same approach:
  - 2026-05-17T10:42Z · Bash `npm test` failed: TypeError in Toggle.test.tsx:34
      attempted_fix: added missing dep к useEffect array — did NOT resolve
  - 2026-05-17T10:48Z · Bash `npm test` failed: TypeError in Toggle.test.tsx:34
      attempted_fix: wrapped useState в useMemo — did NOT resolve
Consider а fundamentally different approach or escalate per M4 §6.3 (Phase 2)
или §7.4 (Phase 3).
```

**Producer responsibility (M4+):** when а tool call fails AND model attempts а fix, append entry к state.md body `## Errors` section via `atomic_state_write` (M1). Schema:

```yaml
## Errors
- ts: 2026-05-17T10:42:00Z
  tool: Bash
  detail: "npm test"
  error: "TypeError in Toggle.test.tsx:34"
  attempted_fix: "added missing dep к useEffect array"
  resolved: false
```

Separate from `## Tool log` (M4 §2.2) which is selective (subagent spawns + side-effect calls only) — routine Phase-2 test failures live в `## Errors`. On successful resolution, producer may set `resolved: true` (optional). Block 5b filters resolved entries by default — only unresolved render.

### Block 5c — Open questions (only if state.md body contains `## Open Questions` section)

Per master plan P-M3-1, if state.md body has `## Open Questions`, render its content with directive к ask user before continuing pipeline work.

```
❓ PENDING QUESTIONS FROM PRIOR TURN — ask user before continuing:
  - "spec.md mentions OAuth but doesn't specify provider — Google, GitHub, or generic?"
  - "Should the migration drop the old column immediately or в а follow-up release?"
Open Question Protocol: surface these via AskUserQuestion as your FIRST action
this turn. Do not advance pipeline phase until resolved.
```

**Producer responsibility (M4+):** when model identifies а question that needs user clarification but defers asking (e.g., wants к gather more context first), append к state.md `## Open Questions` body section. On resolution, producer removes the entry (или sets `resolved: true` field — Block 5c filters resolved by default).

Schema:

```yaml
## Open Questions
- ts: 2026-05-17T10:30:00Z
  asked_in_phase: analyze
  question: "spec.md mentions OAuth but doesn't specify provider — Google, GitHub, or generic?"
  context: "Phase 1 spec read — provider choice affects file scope в Phase 2"
  resolved: false
```

### Block 5d — Persisted approvals (only if state.md frontmatter has non-empty `approvals: []`)

Per master plan P-M3-2 (depends on P-M1-1): render persisted AUQ outcomes к remind model of one-time decisions already made — prevents re-asking after compaction.

```
✓ DECISIONS ALREADY MADE in prior turns — do NOT re-ask:
  - [ship_mode] User picked: "push + open PR"
      (asked в phase: ship · at: 2026-05-17T15:00:00Z)
  - [disambiguate_arguments] User picked: "load as spec"
      (asked в phase: analyze · at: 2026-05-17T10:30:00Z)
Use these picked values directly. Only re-ask if context has materially
changed (e.g., spec file deleted, branch switched) — explicitly acknowledge
the re-ask in your next message.
```

Hook reads `approvals[]` from state.md frontmatter (M1 P-M1-1 optional field) и iterates entries. For each: render `[category] User picked: "<picked>"` с asked-in-phase + timestamp. Empty array → block omitted entirely.

Categories rendered today: `disambiguate_arguments` (M4 §5.1) и `ship_mode` (M4 §7.5). Escalation categories (`phase_2_escalation`, `phase_3_escalation`) explicitly **not persisted** by producer — they appear neither в state.md `approvals[]` nor в this block.

### Block 6 — Resume protocol (always)

```
Resume steps:
1. Read the current skill's SKILL.md to restore phase instructions.
2. Re-invoke the canonical instruction loader at
   ${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md
   with SKILL_SLUG: <active-skill>, LOAD_TIER: <pipeline|rules-only>, MODE: refresh.
   The helper's Echo contract makes the re-Read user-visible.
3. Invoke load-semantic with MODE: refresh:
   ${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-semantic.md (MODE: refresh).
   Fingerprint drift check fires; if drift detected, soft notice surfaces.
4. Read state.md (if not suppressed by Block 3) to identify the current phase.
5. Read spec.md and plan.md (if present) for task context.
6. If a feature ID is set in state.md, read the `.geniro/planning/_FEATURES.md` row and the linked spec.
7. Continue from the next incomplete phase.
```

When LOAD_TIER cannot be determined (no active skill detected — `startup` source on
clean slate), the protocol falls back to LOAD_TIER: rules-only and the
load-semantic invocation is skipped (no domain context to refresh).

---

## 7. Helper refresh contracts

### 7.1 Which helpers have MODE: refresh (Q2)

| Helper | Has refresh? | Rationale |
|---|---|---|
| `load-custom-instructions` | **yes** | L4 = compaction-critical (rules silently violated if dropped) |
| `load-semantic` | **yes** | L3 = project facts; baseline awareness |
| `query-learnings` | **no** | Request/response; no context-resident state to refresh |
| `emit-learning` | **no** | Write-side; stateless |
| `update-semantic` | **no** | Write-side; stateless |
| `resolve-conflicts` | **no** | Derived from load-*; refreshes cascade |

### 7.2 Refresh procedure (Q3)

**Identical to initial-load.** Both helpers run the same procedure under MODE: refresh as under MODE: initial-load:

- Every Read fires again.
- Every echo line prints again (Echo contract — proof of fire).
- `primary-worktree.md` Mode A fallback applies on cwd file-not-found.
- For `load-semantic`: `.fingerprint.json` drift check fires; drift surfaces a soft notice.
- For `load-custom-instructions`: same anti-rationalization table applies (no mtime skip, no batch-Glob substitution).

### 7.3 When refresh fires (Q4)

| Helper | Initial-load | Post-compaction (via hook) | Phase-boundary refresh sites |
|---|---|---|---|
| `load-custom-instructions` | Step 0 of every consumer | yes (Block 6 step 2) | **yes** — every long-running pipeline skill declares refresh sites between phases (existing pattern) |
| `load-semantic` | Step 0 of every consumer | yes (Block 6 step 3) | **no** — L3 = facts; absence of mid-pipeline refresh acceptable; on-demand if phase explicitly needs fresh module map |

**Rationale for asymmetry:** L4 rules govern code generation (silent violation if dropped → bad code merged); L3 facts are baseline awareness (model corroborates via direct Grep/Read of code, not L3). Per-phase refresh cost amortizes only on the compaction-critical L4.

### 7.4 Compaction-immune helpers (no MODE param)

`query-learnings`, `emit-learning`, `update-semantic`, `resolve-conflicts` do not take a MODE parameter and do not change behavior on resume. Skill flow is responsible for re-invoking them when phase logic requires (e.g., `/debug` Phase 2 may explicitly `query-learnings` again after resume if its hypothesis-thread depends on prior findings).

---

## 8. `non-resumable-actions` — structured schema (M1 contract delta)

M1 Q4 required `non-resumable-actions: []` as a T1 frontmatter field but left entry shape unspecified. M3 fixes it as structured-entry array so hook can render readably.

**Canonical schema (M1 PR-0 implements; M3 hook consumes):**

```yaml
non-resumable-actions:
  - action: git-push
    target: origin/feature/dark-mode
    ref: a3f9e2
    completed-at: 2026-05-16T14:32:00Z
  - action: pr-comment-posted
    pr: 142
    comment-id: 1834720
    completed-at: 2026-05-16T14:35:00Z
  - action: slack-notify-sent
    channel: "#deploys"
    ts: 1747393200.123456
    completed-at: 2026-05-16T14:40:00Z
  - action: release-tagged
    tag: v1.85.0
    completed-at: 2026-05-16T14:45:00Z
```

**Required entry fields:** `action`, `completed-at`. **Action-specific fields** are recommended (target+ref for git-push; pr+comment-id for pr-comment-posted; etc.) so hook rendering is informative; unknown action types render as bare `action: <name>` with omitted detail.

**Producer responsibility (M4+ per-skill work):** every pipeline skill, on completing a side-effect operation, MUST append a structured entry to `non-resumable-actions` via `atomic_state_write` (re-writes whole state.md with updated frontmatter — single atomic operation per M1).

**Hook rendering:** Block 5 of additionalContext iterates entries, prints one line each:

```bash
for entry in $(yq -o=json '.non-resumable-actions[]' state.md); do
  action=$(jq -r .action <<<"$entry")
  case "$action" in
    git-push)
      target=$(jq -r .target <<<"$entry")
      ref=$(jq -r .ref <<<"$entry")
      completed=$(jq -r '.["completed-at"]' <<<"$entry")
      printf '  - git-push (target: %s, ref: %s, completed: %s)\n' "$target" "$ref" "$completed"
      ;;
    pr-comment-posted)
      pr=$(jq -r .pr <<<"$entry")
      cid=$(jq -r '.["comment-id"]' <<<"$entry")
      completed=$(jq -r '.["completed-at"]' <<<"$entry")
      printf '  - pr-comment-posted (pr: %s, comment-id: %s, completed: %s)\n' "$pr" "$cid" "$completed"
      ;;
    *)
      completed=$(jq -r '.["completed-at"]' <<<"$entry")
      printf '  - %s (completed: %s)\n' "$action" "$completed"
      ;;
  esac
done
```

---

## 9. T2 handoff — skill-only contract (no hook injection) (Q7)

The hook does **not** inject pointers to `.geniro/state/handoff/from-<producer>-<branch>.md` files. M3 imposes a contract on consumer skills instead:

**Consumer obligation (M4+ per-skill work):** at the first phase that consumes a T2 handoff (typically Phase 1), the consumer skill MUST persist key findings from the handoff into its own state.md body under a fixed section. Canonical section heading: `## Inputs from <producer>`.

**Example (`/implement` Phase 1 consuming `from-debug-<branch>.md`):**

```markdown
## Inputs from debug
Source: .geniro/state/handoff/from-debug-bugfix-toggle-flicker.md (read at 2026-05-16T15:00:00Z)

Key findings:
- Stale closure in src/components/Toggle.tsx:34 (useEffect cleanup missing dep)
- Affected commits: a3f9e2..b8c1d4
- Adversarial test added at tests/Toggle.adversarial.test.tsx

Producer's recommended fix: ...
```

**Why state.md is canonical for resume:**

- T2 file may be overwritten by a later run of the producer (M1 §T2 lifecycle: overwrite on next run).
- T2 file may be on a different worktree (primary-worktree routing per M1).
- state.md is the durable, atomic, validated, single-source-of-truth resume payload.

**Hook delegation:** since state.md (Block 2) is already injected by the hook, persisted handoff facts come along for free. No additional hook logic required.

**Implementation footnote:** if a skill author forgets to persist — the bug surfaces as "model resumed Phase 4 with missing inputs context". Mitigation: in M4+ per-skill SKILL.md, add the persist-step as a **named** sub-step of Phase 1 (not buried in narrative), and reference this section.

---

## 10. systemMessage one-liner (Q10.3)

In addition to `additionalContext` (model-visible), the hook emits a `systemMessage` (user-visible in terminal) summarizing what was restored:

**Template:**
```
Geniro: restoring context (source: <source>, active: <task-dir or "none"> · phase: <phase or "—"> · non-resumable: <N>)
```

**Examples:**
```
Geniro: restoring context (source: compact, active: feature-dark-mode · phase: Phase 4 - Implement · non-resumable: 2)
Geniro: restoring context (source: resume, active: bugfix-toggle-flicker · phase: Phase 1 - Reproduce · non-resumable: 0)
Geniro: restoring context (source: startup, active: none · phase: — · non-resumable: 0)
```

**Suppression rules:**
- `source == startup` AND `active == none` → suppress systemMessage entirely (cold launches don't need the spam).
- All other cases → emit.

**Output JSON shape:**

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "<assembled per §6>"
  },
  "systemMessage": "<one-liner per §10>"
}
```

---

## 11. Migration (Q10.1)

**File rename:**
```
git mv hooks/post-compact-notification.sh hooks/session-start-restore.sh
```

**`hooks/hooks.json` update:**
- Change `command` path.
- Change `matcher` from `"compact"` to `"compact|resume|startup"`.
- Change `statusMessage` from `"Restoring context after compaction..."` to `"Restoring Geniro context..."`.

**Body rewrite:** the existing script's 3-tier state-file lookup is replaced by the M1-canonical slug + branch-fallback procedure (§5 / Q8). The additionalContext assembly is restructured into the six blocks of §6. The systemMessage emitter is added.

**Backward-compatibility window during M1 PR rollout:** while M1 migration PRs are landing one skill at a time, the legacy state-file paths (`.geniro/state/<skill>/state-<slug>.md`, `.geniro/state/debug/HYPOTHESES-<slug>.md`) may still exist. The M3 hook does NOT scan these legacy paths — by the time M3 hook ships, M1 PR-0 must have landed (introducing the consolidated `.geniro/planning/<task-dir>/state.md` location and the helpers). For projects upgrading mid-pipeline, M1's per-skill PRs migrate state files on first invocation; the M3 hook will simply report "no active task" until that migration runs, which is correct behavior.

**Dependency order:**

```
M1 PR-0 (atomic_state_write + validate_state_file + frontmatter schema)
  ↓
M3 hook rewrite (this milestone)
  ↓
M1 PR-1+ (per-skill migrations — bring state files under the new schema)
  ↓
M4+ per-skill work (refresh sites, T2 persist obligation, non-resumable emission)
```

---

## 12. Resilience: M1 helpers absent (Q10.2)

If `validate_state_file` shell helper is not present on disk (M1 PR-0 has not landed), the hook:

1. Detects absence: `if [ ! -x "${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.sh" ]` or equivalent.
2. Sets `validation_status=skipped`.
3. Adds Block 4 (§6) to additionalContext explicitly notifying the model.
4. Continues with state.md pointer in Block 2 (no suppression).

This avoids hard breakage if the rollout order is non-canonical (e.g. user upgraded plugin to a M3-aware version but their M1 install is older). The user sees the notice in systemMessage and the model handles state.md "with caution" (a soft contract — model is asked to verify `phase:` and `status:` sanity manually before resume actions).

---

## 13. Definition of Done

- [ ] `hooks/session-start-restore.sh` exists (renamed via `git mv` from `post-compact-notification.sh`).
- [ ] `hooks/hooks.json` registers it under `SessionStart` with `matcher: "compact|resume|startup"`.
- [ ] Active T1 state file resolved via slug + frontmatter-branch fallback (Q8).
- [ ] Pre-flight `validate_state_file` runs on detected state.md (Q5). Hard-fail suppresses state.md pointer and emits Block 3.
- [ ] Missing M1 helpers detected; Block 4 emitted; behavior degrades gracefully (Q10.2).
- [ ] additionalContext assembled per §6 (6 blocks, ordered).
- [ ] `non-resumable-actions[]` parsed and rendered per §8 schema.
- [ ] systemMessage one-liner emitted per §10; suppressed on cold startup with no active task.
- [ ] `clear` source produces no output (exit 0, empty stdout).
- [ ] Helper refresh: `load-custom-instructions` and `load-semantic` accept `MODE: refresh`; identical-to-initial-load procedure (Q3).
- [ ] Phase-boundary refresh sites: only `load-custom-instructions` declares them in consumer SKILL.md (M4+ work); load-semantic does not (Q4).
- [ ] Compaction-immune helpers (`query-learnings`, `emit-learning`, `update-semantic`, `resolve-conflicts`) explicitly documented as having NO MODE parameter.
- [ ] T2 handoff contract delegated to consumer skills (Q7); state.md is canonical resume payload.
- [ ] M4+ per-skill work tracked: persist T2 handoff facts to state.md `## Inputs from <producer>`; emit structured `non-resumable-actions` entries on side-effect completion.

---

## 14. Out of scope for M3 (deferred)

- **PreCompact hook:** Anthropic's `PreCompact` event currently does not support `additionalContext`. If/when it does, M3 could add a pre-compaction save-checkpoint hook that proactively flushes ephemeral context to state.md before compaction strikes. Today's design relies on `atomic_state_write` keeping state.md durable at all times.
- **Multi-project context restoration:** if a user has multiple projects open in concurrent Claude Code sessions, each session restores independently. No cross-project handoff in scope.
- **Hook performance benchmarks:** target is <100ms hook execution; measurement and tuning deferred to post-PR-0 validation.
- **L2 inline digest:** explicitly rejected in Q1 (Option C); revisit if real-world resume UX shows model failing to `query-learnings` on resume despite resume protocol step.
- **AUQ wording polish:** Block 3 (validation failure) and the M1 recovery-AUQ prose are functional but not UX-polished; final phrasing in M1 PR-0 review.

---

## 15. Open questions for M4+

- **M4 `/implement` SKILL.md updates:** which phases declare `load-custom-instructions` refresh sites? — open in M4 §10 OQ-10 (Memory I/O section).
- **M4 `/implement` Phase 1 T2 handoff persist:** ✅ format spec'd in `architecture/M4-implement-redesign.md` §5.4 — `## Inputs from <producer>` section in state.md body, top-3 findings as bullets, link to original T2 path.
- **M4 `/implement` post-`git push`:** ✅ atomic-append pattern spec'd in `architecture/M4-implement-redesign.md` §7.5 step 4 — call M1 `atomic_state_append` after side-effect succeeds; entry schema per M3 §8 below.
- **M5 `/plan` non-resumable interactions:** does `/plan` ever produce non-resumable actions before handoff to `/implement`? (Likely no — `/plan` is read-only on production resources.) Per master plan §117, M5 owns this answer; M3 expects "no" by default.
- **M7 `/debug` resume after CONFIRMED:** if `/debug` resumes after Phase 2 CONFIRMED + fix-applied, does the resume protocol re-fire the L2 emit step? (Per Q2 design: emit-learning is write-side stateless; skill flow decides re-invocation. Document explicitly in `/debug` SKILL.md.) **Cross-cutting:** M2 §5.3 trigger contract revised in `architecture/M2-memory-layers.md` (L2 auto-emit triggers no longer reference deleted `/brainstorm` or pre-M4 architect-agent) — `/debug` keeps the `diagnosis` trigger as-is.

---

## Appendix A — Worked example: post-compaction resume with non-resumable action

> **Note on phase names:** This worked example uses an illustrative phase numbering (`Phase 5 - Implement`, `Phase 6 - Self-Review`) for narrative continuity with а pre-M4 redesign draft. The canonical /implement `phase:` enum values per `architecture/M4-implement-redesign.md` §2.1 are lowercase short tokens: `analyze` (Phase 1), `implement` (Phase 2), `self-review` (Phase 3 entry), `ship` (Phase 3 terminal sub-step), плюс escalation/terminal states (`phase-2-escalated`, `phase-3-escalated`, `debug-handoff`, `ship-committed-only`, `self-review-only`, `done`, `aborted`). The mechanics of compaction-recovery, `non-resumable-actions` surfacing, and helper refresh are unaffected by phase-name choice — phase-name strings in state.md are opaque per §5 (M3 does not enforce а phase enum; other skills define their own).

**Scenario:** user invoked `/geniro:implement "add OAuth login"` on branch `feature/oauth`. Pipeline reached Phase 5 (post-push), executed `git push origin feature/oauth`, recorded the action, then mid-Phase-6 compaction struck.

**Pre-compaction state.md (`.geniro/planning/feature-oauth/state.md`):**

```yaml
---
tier: T1
producer: implement
schema-version: 1
branch: feature/oauth
timestamp: 2026-05-16T15:42:00Z
phase: Phase 6 - Self-Review
status: in-progress
non-resumable-actions:
  - action: git-push
    target: origin/feature/oauth
    ref: 7f12758
    completed-at: 2026-05-16T15:38:00Z
spec-file: .geniro/planning/feature-oauth/spec.md
---

## Phase log
- Phase 0 done at 15:10:00Z
- Phase 1 done at 15:15:00Z
- Phase 2 done at 15:22:00Z
- Phase 3 done at 15:30:00Z
- Phase 4 done at 15:35:00Z
- Phase 5 done at 15:38:00Z (git push completed — recorded)
- Phase 6 started at 15:40:00Z

## Inputs from debug
[empty — no debug handoff for this task]
```

**Compaction fires; SessionStart source=compact triggers hook.**

**Hook execution:**

```
1. source=compact
2. slug=feature-oauth
3. state_file=.geniro/planning/feature-oauth/state.md  (slug-match hit)
4. validate_state_file → pass
5. yq frontmatter:
   - producer=implement
   - spec-file=.geniro/planning/feature-oauth/spec.md
   - non-resumable-actions[]=[{git-push, target=origin/feature/oauth, ref=7f12758, completed=2026-05-16T15:38:00Z}]
6. Assemble additionalContext (Blocks 1, 2, 5, 6 — Blocks 3 and 4 absent)
7. Emit:
```

**additionalContext (concatenated):**

```
Context was compressed by compaction (SessionStart source: compact). SKILL.md
instructions and conversation nuance may have been lost — re-read these files
before continuing (the .geniro/instructions/* entries route through the canonical
loader, NOT direct cwd Reads; CLAUDE.md, FEATURES.md, spec/plan files remain
direct Reads):

- CLAUDE.md
- .geniro/planning/_FEATURES.md
- .geniro/instructions/global.md         (loader-routed, MODE: refresh)
- .geniro/instructions/code-style.md     (loader-routed, MODE: refresh)
- .geniro/instructions/implement.md      (loader-routed, MODE: refresh)
- .geniro/planning/feature-oauth/state.md
- .geniro/planning/feature-oauth/spec.md

⚠️ ALREADY COMPLETED in prior turns — DO NOT repeat:
  - git-push (target: origin/feature/oauth, ref: 7f12758, completed: 2026-05-16T15:38:00Z)
Resuming should re-validate code state but MUST NOT re-trigger these actions.
If a re-trigger is genuinely required (e.g., rebase + re-push), explicitly
acknowledge in your next message before performing it.

Resume steps:
1. Read the current skill's SKILL.md to restore phase instructions.
2. Re-invoke the canonical instruction loader at
   ${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md
   with SKILL_SLUG: implement, LOAD_TIER: pipeline, MODE: refresh.
   The helper's Echo contract makes the re-Read user-visible.
3. Invoke load-semantic with MODE: refresh:
   ${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-semantic.md (MODE: refresh).
   Fingerprint drift check fires; if drift detected, soft notice surfaces.
4. Read state.md to identify the current phase.
5. Read spec.md and plan.md (if present) for task context.
6. If a feature ID is set in state.md, read the `.geniro/planning/_FEATURES.md` row and the linked spec.
7. Continue from the next incomplete phase.
```

**systemMessage:**

```
Geniro: restoring context (source: compact, active: feature-oauth · phase: Phase 6 - Self-Review · non-resumable: 1)
```

**Next turn model behavior (expected):**

1. Reads `skills/implement/SKILL.md`.
2. Invokes `load-custom-instructions` (refresh) — echoes 3 file Loads.
3. Invokes `load-semantic` (refresh) — echoes 2+ file Loads; fingerprint check passes (no drift).
4. Reads `state.md` → sees `phase: Phase 6 - Self-Review`, `non-resumable: [git-push]`.
5. Reads `spec.md`.
6. Continues Phase 6 — runs self-review, generates findings. Does **not** call `git push` again (Block 5 warning held).
7. If Phase 6 surfaces an issue requiring fix → patches code, commits, but **explicitly acknowledges** before any second push: "Re-pushing is required because Phase 6 found a typo in OAuth callback. Confirming with user before push." → AUQ before push.

---

*End of M3 specification.*
