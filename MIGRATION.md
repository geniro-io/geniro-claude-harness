# Migration Notes

Plugin-maintainer-authored breaking-change log consumed by `/geniro:update` Phase 4 and the `/geniro:setup` re-run migration sweep.

**Consumption contract (both consumers).** The `## vX.Y.Z` headings group changes into feature cohorts for human readability — they track plugin features, not the package's semver version, so a cohort's heading number can sit outside the installed package's version range while its features are already live (the "v3.0.0" cohort shipped across several 2.x releases). Consumers therefore do NOT select entries by version range. Walk *every* `### <name>` entry across *all* sections and run its `Auto-detect:` command — these are read-only (`grep` / `find` / `ls` / `printf`-class only — never mutate) and report whether THIS install is affected. The auto-detect output is the sole relevance signal: an empty result means the install is already current for that entry and it is skipped. This contract governs entry selection and the relevance signal; each consumer applies and re-verifies an entry's `Auto-fix:` per its own interaction model.

For users installing the plugin fresh (no pre-existing `.geniro/`), this file is purely informational — `/geniro:setup` writes the current schema directly.

---

## v3.0.0

### `config-weakening` safety hook removed

The `block-config-weakening.sh` PreToolUse hook — which hard-blocked edits to an existing linter / formatter / type-checker config file (eslint / prettier / biome / ruff / tsconfig / golangci) so a check could not be silenced at edit time — has been removed, along with its `config-weakening` allowlist pattern ID. Editing those config files is no longer guarded at edit time, so intentional config tuning no longer needs a bypass; `/geniro:review` still flags a config change that weakens a rule when it reads the resulting diff.

**Action required:** Optional — if your project's `.geniro/safety.json` `allow_patterns` lists `config-weakening`, that entry is now an inert no-op and can be removed. Leaving it in place causes no harm.

**Auto-detect:** `grep -l 'config-weakening' .geniro/safety.json 2>/dev/null`

**Auto-fix:** Manual-only — remove the `"config-weakening"` string from `.geniro/safety.json` `allow_patterns` if present (a user-file JSON edit; left in place it is harmless).

**Severity:** LOW — the hook lived in the plugin (auto-removed on update); the only user-side residue is an inert allowlist entry.

---

### spec.md section 9 gains an optional per-criterion `verify:` command

`/geniro:plan` specs may now attach an optional `verify: <shell command>` line to a section 9 (Validation) criterion — a single acceptance command for that criterion, distinct from the project-wide test suite. After the end-of-phase suite goes green, `/geniro:implement` runs each `verify:` command once (via its own Bash, not `test-runner-agent`), classifies the result on the existing `{ALL_GREEN, HAS_FAILURES, INFRA_ERROR}` verdict taxonomy, and attaches the result as evidence; a failing `verify:` routes into the same message-first escalation prompt so the human stays the ship decider. The field is OPTIONAL and backward-compatible — a spec with no `verify:` line behaves exactly as before (prose-only verification). The validator (`validator-checks.md` check #8 `validation_method`) gains a shape-only sub-rule: a present `verify:` must be a non-empty command string; it never executes the command. `verify:` is a body-level field (not frontmatter), so it is independent of `geniro_schema_version` (m5-v1 / m5-v2).

**Action required:** None — existing specs without `verify:` keep working unchanged. New `/geniro:plan` runs may add `verify:` lines per criterion; `/geniro:implement` picks them up organically.

**Auto-detect:** N/A — additive optional field (absent `verify:` = prior behavior); nothing to detect in an existing install.

**Auto-fix:** Manual-only — none required.

**Severity:** LOW — additive optional spec field with graceful absence handling; no schema-version bump, no state migration.

---

### `/geniro:review` re-runs can collapse unchanged repeat findings into a Carried-over section

A round ≥2 `/geniro:review` re-run now offers a "Repeat findings" choice at the re-review gate: move unchanged repeats (issues raised in an earlier round and never fixed, surfacing identically this round) into a collapsed `## Carried-over from round <N>` handoff section, or keep every repeat in the main findings list. The choice routes presentation only — under either pick every repeat stays in the report and in the handoff, and a repeat that strengthened since last round (fresh convergence, a newly-reachable code path, or a verifier confirmation absent before) still promotes back to the active `## Findings` list. The pick persists as a new `approvals[]` category `rereview_repeat_handling`. A first review or fresh-PR round has no prior round to carry over from, so the section and the choice never appear there.

**Action required:** None — first-review and fresh-PR runs are unaffected; the new section and gate only appear on a round ≥2 re-run, and the collapse is opt-in per run.

**Auto-detect:** N/A — additive `/geniro:review` behavior, no existing install state to migrate.

**Auto-fix:** Manual-only — none required.

**Severity:** LOW — additive re-review behavior with an opt-in section and a new approvals category; no schema-version bump, no state migration.

---

### `/geniro:actions run` no longer asks for confirmation

The run-mode risk-class confirmation gate is removed. Previously `/geniro:actions run <name>` confirmed before executing — a 1-click prompt for `medium` actions and a Cancel-default prompt for `high` actions. Now every action runs directly: invoking `/geniro:actions run <name>` IS the authorization, so no "are you sure?" prompt fires regardless of `risk_class`. The `risk_class` frontmatter field is unchanged and still required — it now drives only the `list` Risk column, the `delete` high-risk warning, the validate lint rules, and the L2 learning tag. Operational WAIT points are unaffected (cross-worktree confirmation, free-text action picker, tool-scope gap prompt, and any `[AUQ]`/`## Confirm:` checkpoint an action author placed inside the body). The run-mode rejection-signal emit to `learnings.jsonl` is also removed (there is no longer a confirmation to reject).

**Action required:** None — existing actions and their `risk_class:` values keep working as-is; the only change is that runs no longer prompt.

**Auto-detect:** N/A — behavior change in the shipped skill with no project-state impact.

**Auto-fix:** Manual-only — none required.

**Severity:** LOW — removes a prompt; no schema, state, or user-file change.

---

### `--tdd` / `--standard` flags removed from `/geniro:review`

The Standard/TDD mode axis is gone from `/geniro:review`. The post-review test-confirmation gate is now the only test question: it fires automatically in every run whose kept findings include testable ones, offering to author failing tests for them — your approval gates the authoring, and the Failing-tests gate still gates any commit/push of the authored tests. Passing `--tdd` or `--standard` no longer changes behavior (test authoring never filtered the posted finding set, so the post set is unchanged). The `mode:` frontmatter field and `- Mode:` summary line are dropped from new review handoffs; values persisted by older runs (`mode: tdd` / `mode: standard`, `tdd_mode_choice` approvals) are read by no consumer and are ignored harmlessly.

**Action required:** None — remove `--tdd` / `--standard` from any saved command aliases, actions, or notes that invoke `/geniro:review`; the flags are now inert.

**Auto-detect:** N/A — flag removal with no project-state impact; stale `mode:` values in pre-update handoff files are ignored and disappear when `/geniro:review` next overwrites the handoff.

**Auto-fix:** Manual-only — none required.

**Severity:** LOW — behavior-preserving removal; old state-file values degrade to no-ops.

---

### `--simplify` flag removed from `/geniro:review`

The `--simplify` flag (and its `simplify-mode` handoff field) is gone from `/geniro:review`. The reuse / quality / efficiency lens it added is now covered by the always-on review dimensions — architecture (reuse, premature abstraction), conventions (modal-pattern drift), optimizations (efficiency), and guidelines (naming, dead code) — at their standard thresholds. Applying a simplification is downstream work (`/geniro:implement` or `/geniro:refactor`), not part of producing a review. Passing `--simplify` no longer changes behavior (it is read as ordinary argument text and ignored); the dedicated `simplify-criteria.md` reference file is removed.

**Action required:** None — remove `--simplify` from any saved command aliases, actions, or `.geniro/instructions/review*.md` rules that invoke `/geniro:review`; the flag is now inert. A project that relied on the aggressive simplify thresholds still gets the same finding classes from the standard dimensions at their normal thresholds.

**Auto-detect:**

```bash
grep -rl -- '--simplify' .geniro/instructions/ .geniro/actions/ 2>/dev/null
```

**Auto-fix:** Manual-only — drop the now-inert `--simplify` token from the matched instruction/action files.

**Severity:** LOW — behavior-preserving removal; the flag degrades to a no-op and the simplify lens persists via the standard dimensions.

---

### New gate-render guard hard-blocks blind decision questions

`hooks/enforce-gate-render.sh` is a new PreToolUse hard-block (exit 2) on the `AskUserQuestion` tool. A decision question that references content "above" (in the question text, option labels, or option descriptions) while the current turn contains no visible assistant message is blocked — the user would be answering blind, violating the message-first gate contract (`skills/_shared/gate-rendering.md`). A block is NOT a user denial: the stderr message instructs the model to write the full gate render as an ordinary chat message and then re-ask the same question. The hook reverse-scans the transcript back to the last real user message (2000-record cap, one 0.4s retry against the transcript lazy-flush race) and fails open on missing jq (loud), missing transcript, cap overflow, or a garbage transcript.

**Action required:** None for typical installs — questions preceded by their context message pass untouched. If a workflow legitimately fires bare "above"-referencing questions, add `gate-render` to `.geniro/safety.json` `allow_patterns`.

**Auto-detect:** N/A — only reveals itself when a blocked question occurs (fail-loud); the hook output prints the exact bypass ID to add.

**Auto-fix:** Manual-only — render the gate message before re-asking, or add `gate-render` to `.geniro/safety.json` `allow_patterns` to opt out.

**Severity:** LOW — fail-loud with a recovery directive; the model re-renders and re-asks, and no data loss is possible.

---

### `Validation:` enum on m6-v2 review handoffs gains `unverified`

The per-finding `Validation:` field in `.geniro/state/handoff/from-review-<branch>.md` admits a fourth value, `unverified` — orchestrator-assigned when the Phase 4.2 per-finding verifier fails to spawn after retry (never agent-emitted). The finding stays in the report (fail-open), is excluded from the PR post set, and is surfaced under `## Caveats`. A pre-update consumer reading a post-update handoff treats `unverified` as a value outside its three-value enum at the Pre-Post guard and aborts the post — fail-loud, no silent corruption.

**Action required:** None for current installs. If a PR post aborts on an unexpected `Validation:` value, the consuming session is running an older plugin version — update it (or re-run `/geniro:review` after resolving the failed verifier spawn) and retry.

**Auto-detect:**

```bash
grep -l "Validation: unverified" .geniro/state/handoff/from-review-*.md 2>/dev/null
```

**Auto-fix:** Manual-only — update the plugin in the consuming session, or re-run `/geniro:review` to regenerate the handoff once verifier spawns succeed.

**Severity:** LOW — cross-version skew only; the Pre-Post guard fails loud at the posting boundary.

---

### State-helper enforcement now hard-blocks direct writes to `.geniro/` state paths (incl. Bash-side)

`hooks/enforce-state-helper.sh` flips from warn-mode to hard-block, and now also covers the `Bash` tool. Direct `Edit`/`Write`/`MultiEdit` to a canonical state path under `.geniro/` (`.geniro/state/`, `.geniro/planning/`, `.geniro/knowledge/`, `.geniro/instructions/`, `.geniro/actions/`, `.geniro/workflow/`, `.geniro/.geniro-state.json`) is blocked (exit 2), as are Bash-side writes into the same paths (redirection `>`/`>>`, `tee`, in-place `sed -i`, `cp`/`mv` destinations, `dd of=`). Reads stay allowed, commands invoking the sanctioned helpers (`atomic_state_write` / `atomic_state_append`) are allowed, and paths under `.geniro/state/tdd/` are exempt (the TDD-order hook writes that file via its own mktemp + mv procedure). The prior warn-mode let a consumer session ignore 42 warnings in one run; the block makes the contract enforceable.

**Action required:** Route writes to `.geniro/` state paths through `atomic_state_write` / `atomic_state_append` (per `skills/_shared/atomic-state-write.md`). If a workflow legitimately needs to bypass the guard, add `enforce-state-helper` to `.geniro/safety.json` `allow_patterns`.

**Auto-detect:** N/A — only reveals itself when a blocked write occurs (fail-loud); the hook output prints the exact bypass ID to add.

**Auto-fix:** Manual-only — route writes through `atomic_state_write` / `atomic_state_append`, or add `enforce-state-helper` to `.geniro/safety.json` `allow_patterns`.

**Severity:** MEDIUM — fail-loud with the bypass ID; no silent corruption possible, but a workflow that hand-wrote a state file directly will now stop until migrated to the helper or allowlisted.

---

The v3 release lands the /implement 3-phase rewrite, MANDATORY /review spawn list with pre/post-spawn verification gates, /plan workflow_refs[] tracker linkage (m5-v2 schema), per-section AUQ `preview` field with restored Phase 2 Visual Companion, structured `open_questions[]` in T2 handoffs with a 3-gate safety chain, T1/T1.5 state tier split for Ship-cleanup preservation, and universal `model: inherit` for all plugin subagents. Seven changes need user attention; auto-fix is provided where mechanical, manual review is called out where judgment is needed.

### Post-task improvement suggestions now fire across implement / refactor / review / plan / onboard

A new read-only `reflection-agent` (with inline equivalents in /plan and /onboard) synthesizes durable project-rule improvement candidates at the end of a task and offers to route them to CLAUDE.md / `.claude/rules/` / `.geniro/instructions/` / ADR. `/implement` Phase 3 moves its "Suggest Improvements" step ahead of the Ship-mode prompt (previously a post-PR trailing step that got dropped on wrap-up); `/review`, `/plan`, and `/onboard` gain the step for the first time. The user approves before anything is written — instruction-scoped rules hand off to `/geniro:instructions create`; declines are logged so they do not re-surface.

**Action required:** Informational — the agent and steps ship with the update automatically; no project-state migration. Expect a new optional "Improvements" prompt at the end of these skills (skipped silently when nothing durable was learned).

**Auto-detect:** N/A — additive behavior change; nothing to detect in an existing install.

**Auto-fix:** Manual-only — none required.

**Severity:** LOW — additive and opt-in at the prompt; on an Opus orchestrator session, each `/implement` / `/refactor` / `/review` run adds one more read-only subagent spawn (set orchestrator tier via `/model sonnet` if cost-sensitive).

---

### Ship cleanup now preserves durable artifacts (T1 → T1.5 split)

`/geniro:implement` Phase 3 Ship sub-step now preserves `spec.md`, `state.md`, `plan-*.md`, `milestone-*.md` (the new T1.5 durable layer). Only transient working files (`.kr-out.md`, `.ce-out.md`, `.tr-out.md`, `.adversarial-out.md`, `.spec-challenge-out.md`, `.research-out.md` / `.research-<facet>.md`, `notes.md`, `playwright-verify.png`) delete at terminal exit. Downstream `/geniro:review` spec-compliance and `/geniro:implement` adjustment routing now find their context reliably across runs.

**Action required:** Delete leftover transient files inside finished task-dirs. These are left by runs that predate the cleanup contract OR by any run that ended without reaching its cleanup (interrupted session, killed terminal) — the detector cannot distinguish file origin, only that the file outlived its run. This entry deliberately doubles as a recurring sweep: it is the system's only channel for catching transients left by interrupted runs, so re-detection on a later update means NEW leftovers appeared since the last sweep, not that the previous fix failed.

Both commands below share one liveness predicate: a transient is a leftover only when its task-dir's `state.md` is missing or terminal (`phase:` done/aborted/routed/failed/ship-committed-only/self-review-only/debug-handoff/ship-summary-only/adversarial-aborted/verify-summary-only/reverted/adr-documented/map-truncated/present-summary-only, or `status:` done/completed/failed/aborted/routed — mirroring the session-restore hook's full terminal sets in `hooks/session-start-restore.sh`). Transients inside a live task-dir are the working files of an in-flight run, not leftovers — they are never matched, and they become detectable once that task finishes. A status-blind glob here once flagged (and would have deleted) a running `/implement` task's research outputs. `notes.md` is deliberately excluded from this sweep: the name is plausibly user-authored content, so an external sweep deleting it risks data loss — `/geniro:implement`'s own in-run cleanup handles its `notes.md`.

**Auto-detect:**

```bash
find .geniro/planning -maxdepth 2 \( -name '.kr-out.md' -o -name '.ce-out.md' -o -name '.tr-out.md' -o -name '.adversarial-out.md' -o -name '.spec-challenge-out.md' -o -name '.research-*.md' -o -name 'playwright-verify.png' \) -exec sh -c '
  for f do
    s="${f%/*}/state.md"
    if [ ! -f "$s" ] || grep -Eq "^phase:[[:space:]]*(done|aborted|routed|failed|ship-committed-only|self-review-only|debug-handoff|ship-summary-only|adversarial-aborted|verify-summary-only|reverted|adr-documented|map-truncated|present-summary-only)[[:space:]]*$|^status:[[:space:]]*(done|completed|failed|aborted|routed)[[:space:]]*$" "$s"; then
      printf "%s\n" "$f"
    fi
  done' sh {} + 2>/dev/null
```

**Auto-fix:**

```bash
find .geniro/planning -maxdepth 2 \( -name '.kr-out.md' -o -name '.ce-out.md' -o -name '.tr-out.md' -o -name '.adversarial-out.md' -o -name '.spec-challenge-out.md' -o -name '.research-*.md' -o -name 'playwright-verify.png' \) -exec sh -c '
  for f do
    s="${f%/*}/state.md"
    if [ ! -f "$s" ] || grep -Eq "^phase:[[:space:]]*(done|aborted|routed|failed|ship-committed-only|self-review-only|debug-handoff|ship-summary-only|adversarial-aborted|verify-summary-only|reverted|adr-documented|map-truncated|present-summary-only)[[:space:]]*$|^status:[[:space:]]*(done|completed|failed|aborted|routed)[[:space:]]*$" "$s"; then
      rm -f "$f"
    fi
  done' sh {} + 2>/dev/null
```

**Severity:** LOW — leftover transient files are inert; both `/geniro:plan` (on `done`/`aborted`) and `/geniro:implement` (on every terminal exit) now clean their own scratch via the shared `clean_task_transients` helper, so a completed plan-only or milestone-sliced run no longer leaves `.research-*.md` behind (that was a systematic leak — `/geniro:implement` cleaned only the task-dir it ran in, never the parent planning dir of a milestone slice). With that closed, an interrupted or killed run is the remaining way a transient outlives its cleanup, and this entry is the recurring sweep that catches those — periodic re-detection after an interrupted run is expected behavior, not a sign a prior fix failed.

---

### Universal `model: inherit` cost trade-off

All plugin subagents (`reviewer-agent` / `knowledge-retrieval-agent` / `codebase-explorer-agent` / `test-runner-agent` / `adversarial-tester-agent`) now declare `model: inherit` in frontmatter, and spawn sites OMIT the `model=` argument. If your orchestrator session is on Opus, every reviewer-agent per `/review` and every Phase-3 spawn per `/implement` also runs on Opus — significantly higher cost than the prior hardcoded Sonnet floor. To restore the cheaper baseline, switch orchestrator tier via `/model sonnet` before running `/review` or `/implement`.

Two carve-outs deliberately retain hardcoded tier per `skills/_shared/model-tiering.md`: `/geniro:setup` Phase 4 verification subagent (Sonnet under a tightly constrained NO-Write/Edit tool budget — safety contract, not preference) and `ui-preview-gate.md` UI-description spawn (Haiku for mechanical transformation work).

**Action required:** Informational. If cost-sensitive, set orchestrator tier explicitly per session via `/model sonnet`. User-authored custom reviewers (`.geniro/instructions/review-extra/*.md`) may declare an explicit `model:` field to opt OUT of inherit on a per-reviewer basis.

**Auto-detect:** N/A — informational; the change is unconditional after update.

**Auto-fix:** Manual-only — user picks their orchestrator tier per session; the plugin no longer overrides.

**Severity:** HIGH — silent cost increase on the first `/review` or `/implement` run post-update is user-surprising; this warning surfaces the change before invocation.

---

### `reviewer-agent` maxTurns bumped 80 → 100

`agents/reviewer-agent.md` frontmatter bumped to `maxTurns: 100` for worst-case PR review headroom (15+ changed files with cross-module dependency chains). Plugin-managed installs auto-update; vendored copies under `.claude/agents/geniro-*-reviewer-agent.md` retain the old value and may truncate mid-review.

**Action required:** Bump vendored copies to match.

**Auto-detect:** `grep -l 'maxTurns: 80' .claude/agents/geniro-*reviewer-agent.md 2>/dev/null`

**Auto-fix:**

```bash
for f in .claude/agents/geniro-*reviewer-agent.md; do
  [ -f "$f" ] && sed -i.bak 's/^maxTurns: 80$/maxTurns: 100/' "$f" && rm -f "$f.bak"
done
```

**Severity:** LOW — only affects vendored installs; the plugin-managed path auto-refreshes.

---

### New `codebase-research-agent` replaces built-in `Explore` for cross-skill codebase research

`agents/codebase-research-agent.md` is a new plugin-defined specialist (6th agent in the agents/ directory). It replaces the built-in Claude Code `Explore` subagent for every plugin skill's codebase research (`/plan` Phase 1, `/debug` Phase 1, `/implement` Phase 2 ad-hoc, `/review` Phase 1 peer-PR scout, `/refactor` Phase 1 wide locator queries, `/onboard` Phase 1 narrow locators, `/investigate` Phase 2 Codebase Analyst). Two reasons: built-in `Explore` is pinned to Haiku 4.5 (breaking the orchestrator-tier-inherits rule for evidence-gathering subagents), and it is exposed to upstream bug [anthropics/claude-code#38928](https://github.com/anthropics/claude-code/issues/38928) on MCP-heavy host sessions. The new agent declares `model: inherit` and is unaffected by the bug as a plugin-defined custom agent. Canonical invocation contract: `skills/_shared/context-isolation-checklist.md` § Codebase research. Plugin-managed installs pick up the new agent automatically; vendored installs need to copy the new file.

**Action required:** Re-vendor the agent file for vendored installs.

**Auto-detect:** `[ ! -f .claude/agents/geniro-codebase-research-agent.md ] && ls .claude/agents/geniro-*.md >/dev/null 2>&1 && echo "vendored install missing codebase-research-agent"`

**Auto-fix:**

```bash
# Re-run the vendor copy step if the install is vendored
if ls .claude/agents/geniro-*.md >/dev/null 2>&1; then
  cp "${CLAUDE_PLUGIN_ROOT}/agents/codebase-research-agent.md" .claude/agents/geniro-codebase-research-agent.md
fi
```

**Severity:** LOW — additive feature. Skills that try to spawn `codebase-research-agent` on a vendored install missing the new file fall through to step 3 of the runtime-degradation ladder (`general-purpose` with body inlined) and still work, just with one wasted "not found" round-trip on first spawn.

---

### `/review` handoff per-finding body gains verification fields (schema m6-v1 → m6-v2)

`/geniro:review` Phase 4.2 was rewritten to spawn one fresh `reviewer-agent` per HIGH-severity finding (no tier-scaling — ALL HIGHs verified). Each verifier emits `Validation: confirmed | refuted | clarified`, `Recommended-action`, `Verification-confidence` (1-5 coarse scale), and `Verification-evidence` (literal file:line quote). (A fourth `Validation:` value, `unverified`, was added later — orchestrator-assigned when the verifier failed to spawn, never agent-emitted; see the dedicated entry above.) These 4 fields persist into the T2 handoff per-finding body schema. The `geniro_schema_version` field in `.geniro/state/handoff/from-review-<branch>.md` bumps from `m6-v1` to `m6-v2`; downstream consumers (Phase 6 §7.0 fail-closed guard, /implement Phase 1 Step 12) accept both. Legacy `m6-v1` handoffs read by an `m6-v2` consumer treat the 4 missing fields on HIGH findings as `Validation: confirmed + warn` (mirrors the `step0_status: pending` back-compat pattern).

A new `regressions` reviewer dimension is added as the 8th always-fire dim (between `conventions` and the conditional dims). Catches unintended deletes + behavior changes outside stated intent. Spec.md / PR body / commit messages serve as intent source; when absent, behavior-mutating hunks emit INTENT-CHECK findings for the user to confirm at the §3 Step 0 gate.

**Action required:** None — backward compatible. Existing `m6-v1` handoffs continue to work. New `/review` runs produce `m6-v2` handoffs with the verification fields populated.

**Auto-detect:** N/A — schema version bump is producer-driven; legacy reads degrade gracefully.

**Auto-fix:** N/A.

**Severity:** LOW — additive schema change with graceful absence handling. Reviewers (custom or built-in) that hardcoded the 7-always-fire count in their authoring conventions should bump to 8.

---

### spec.md frontmatter gains optional `workflow_refs[]` (schema m5-v1 → m5-v2)

`/geniro:plan` now persists Linear / Jira / GitHub-Issues / Asana tracker references into spec.md frontmatter. The new field is OPTIONAL — old spec.md files without it remain valid. `/geniro:implement` Step 0 treats absence as "no tracker linkage" and proceeds without workflow on-task-start hooks. `/geniro:debug` and `/geniro:refactor` Phase 1 entry read the cached `status` field as priming context (read-only — never mutates tracker state). The `geniro_schema_version` field bumps from `m5-v1` to `m5-v2`; downstream readers accept both.

Per-entry shape: `{kind, issue_id, url, fetched_at, title?, suggested_branch?, status?, parent_ref?}`. Phase 7 validator gains check #14 `workflow_refs_consistency` — warns when `.geniro/workflow/<kind>.md` is missing; fails on structural field-presence violations; skipped on `m5-v1` specs.

**Action required:** None — backward compatible. New `/plan` runs against tracker URLs gain the field organically.

**Auto-detect:** N/A.

**Auto-fix:** N/A.

**Severity:** LOW — additive schema change with graceful absence handling.

---

### `/plan` per-section AUQ with `preview` field + Phase 2 Visual Companion restored

`/geniro:plan` Phase 5 now opens one AUQ per section with rendered `preview` content (no more "pre-fill all 10 sections" batch). Phase 3 + Phase 4 options also carry `preview` (consequence-of-picking / ASCII data-flow + code identifier + tradeoff). Phase 2 Visual Companion is restored for UI-shaped topics — fires only on UI trigger (Phase 1 surfaced UI files OR topic carries a UI noun) and calls `skills/_shared/ui-preview-gate.md` to produce a textual UI preview before any code is written.

Any user `.geniro/instructions/plan.md` rule referencing the dropped pre-fill batch step or describing Phase 2 as "DROPPED" becomes stale and may mislead the model.

**Action required:** Re-read your `.geniro/instructions/plan.md` (if present) for references to the dropped batch step or to "Phase 2 dropped"; rewrite to match the new section-by-section incremental authoring pattern and the conditional Visual Companion.

**Auto-detect:** `grep -El 'pre-fill (all|the) (sections|10 sections)|Phase 2 (is )?(DROPPED|dropped|not used)' .geniro/instructions/plan.md 2>/dev/null`

**Auto-fix:** Manual-only — judgment-driven rule rewrite. `/geniro:instructions validate` surfaces drift on next run.

**Severity:** MEDIUM — stale custom rules degrade `/plan` UX; visible only on next `/plan` invocation.

---

### `/review` MANDATORY spawn list + post-spawn verification gate

`/geniro:review` Phase 2 step 2.2 now writes `spawn_dims_declared: [...]` + `spawn_dims_count: N` to state.md frontmatter at spawn-batch entry; Phase 4 §4.0 verifies actual spawns match the declaration (catches the silent-skip bug where reviewers reasoned themselves into dropping dimensions). The spawn list is MANDATORY: 7 always (bugs / security / architecture / tests / optimizations / guidelines / conventions) + up to 3 conditional (design / pr-metadata / spec-compliance) + N custom from `.geniro/instructions/review-extra/`. Custom-reviewer discovery moved from Phase 2 entry into Phase 1.5 mechanical pre-pass so Phase 2 has zero cognitive load for it.

T2 handoff (`from-review-<branch>.md`) gains structured `open_questions[]` frontmatter (`{id, source, question, related_findings, status: unresolved | resolved | wontfix, resolution}`). A 3-gate safety chain prevents posting or implementing with unresolved questions: Phase 6 Pre-gate (producer-side, fires FIRST in Phase 6) + Pre-Post-PR guard (defensive, before `gh api` POST) + Consumer-side `/implement` Phase 1 Step 12 (refuses to leave Phase 1 with unresolved entries). `/geniro:debug` Phase 3 gains the same Pre-gate pattern at the same producer position.

Old T2 hand-off files lack `spawn_dims_declared[]` / `spawn_dims_count` / `open_questions[]` fields; downstream readers (orchestrator inspection, `/update` walk) treat missing fields as "no declaration" or "no open questions" and proceed safely.

**Action required:** None — backward compatible. New `/review` and `/debug` runs gain the fields organically. If you have manual workflows that parse T2 hand-off files, update them to read the new fields when present.

**Auto-detect:** N/A — new fields populate on next `/review` or `/debug` run.

**Auto-fix:** N/A.

**Severity:** LOW — additive fields with graceful absence handling.

---

### `/implement` Phase 2 TodoWrite decomposition

`/geniro:implement` Phase 2 now uses TodoWrite to decompose the edit batch into 3-15 sequential todos with a one-in-progress invariant. No user-content format change — todos live in Claude Code's Tasks API, not state.md. Resuming a pre-v3 in-progress Phase 2 state.md re-decomposes via TodoWrite on next Phase 2 entry.

**Action required:** None — internal mechanic change.

**Auto-detect:** N/A.

**Auto-fix:** N/A.

**Severity:** LOW — visible only as a progress-indicator improvement.

---

## v2.4.0

Cleanup of orphan files and directories that survived prior migrations. These paths are not read by any current skill — purely inert. Also removes the deprecated `user-preferences.md` instruction file.

### Orphan root-level state files

`.geniro/debug/` (root-level, distinct from `.geniro/state/debug/`), `.geniro/review-findings-state.md` (root-level, distinct from `.geniro/state/review-findings-state.md`), and `.geniro/.geniro-state.json` (legacy JSON marker replaced by `.geniro/state/setup/state.md`) are orphan paths from pre-v1.84 layouts. No current skill reads or writes them.

**Action required:** Delete orphan files.

**Auto-detect:** `ls -d .geniro/debug/ 2>/dev/null; ls .geniro/review-findings-state.md 2>/dev/null; ls .geniro/.geniro-state.json 2>/dev/null`

**Auto-fix:**

```bash
rm -rf .geniro/debug/ 2>/dev/null
rm -f .geniro/review-findings-state.md 2>/dev/null
rm -f .geniro/.geniro-state.json 2>/dev/null
```

**Severity:** LOW — orphan files inert; cleanup purely cosmetic.

---

### Orphan knowledge subdirectories

`.geniro/knowledge/gotchas/`, `.geniro/knowledge/patterns/`, `.geniro/knowledge/sessions/` are non-canonical subdirectories. The canonical L2 path is `.geniro/knowledge/learnings.jsonl` only. No skill reads from these subdirectories.

**Action required:** Delete orphan subdirectories.

**Auto-detect:** `ls -d .geniro/knowledge/{gotchas,patterns,sessions}/ 2>/dev/null`

**Auto-fix:**

```bash
rm -rf .geniro/knowledge/{gotchas,patterns,sessions}/ 2>/dev/null
```

**Severity:** LOW — orphan directories inert; cleanup purely cosmetic.

---

### Orphan state files at `.geniro/state/` root

State files placed directly at `.geniro/state/` root (not in a skill subdirectory) are non-canonical. Canonical T1.5 paths follow `.geniro/state/<skill>/<slug>/state.md`. Files like `integration-flakes-grind.md` and `pre-compact-snapshot.json` at state root are task artifacts from prior sessions that were never cleaned up.

**Action required:** Delete orphan files at state root.

**Auto-detect:** `find .geniro/state/ -maxdepth 1 -type f 2>/dev/null`

**Auto-fix:**

```bash
find .geniro/state/ -maxdepth 1 -type f -exec rm -f {} + 2>/dev/null
```

**Severity:** LOW — orphan files inert; cleanup purely cosmetic.

---

### Removed `user-preferences.md` instruction file

`user-preferences.md` was removed from the plugin in v2.2.0. The file is no longer loaded by any skill — the load-custom-instructions pipeline reads only 3 files: `global.md`, `<skill>.md`, `code-style.md`. Existing `.geniro/instructions/user-preferences.md` files are inert.

**Action required:** Delete orphan file.

**Auto-detect:** `ls .geniro/instructions/user-preferences.md 2>/dev/null`

**Auto-fix:**

```bash
rm -f .geniro/instructions/user-preferences.md 2>/dev/null
```

**Severity:** LOW — file inert; no loader reads it.

---

## v1.84.0 (released 2026-05-20)

The consolidation reduced 18 skills to 11 and introduced the 3-tier state framework, 4-layer memory model, compaction-survival hook, per-skill canonical phase enums, and the `risk_class:` + `review-extra/` schemas in /actions + /instructions. The user-visible breaks below need attention from anyone whose `.geniro/` predates v1.84.

### Actions require `risk_class:` frontmatter

Actions are now gated by `risk_class: low | medium | high`. Older actions lack the field and fail `/geniro:actions validate`.

**Action required:** Run `/geniro:actions validate`. For each action surfaced, run `/geniro:actions edit <slug>` and add `risk_class:` (low = automation only; medium = external API call; high = mutating shared infrastructure).

**Auto-detect:** `find .geniro/actions -maxdepth 1 -name '*.md' -exec grep -L '^risk_class:' {} +`

**Auto-fix:**

```bash
find .geniro/actions -maxdepth 1 -name '*.md' -exec grep -L '^risk_class:' {} + | while IFS= read -r f; do
  awk 'NR==1 && $0=="---" {print; print "risk_class: low"; next} {print}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
```

Adds `risk_class: low` right after the opening `---` of each affected action's frontmatter (awk, not `sed -i` — the insert-with-newline sed forms are GNU-only and fail on macOS BSD sed). A file without frontmatter is rewritten unchanged and still needs a manual `/geniro:actions edit <slug>`. Users should review and adjust to `medium` or `high` where appropriate after the fix.

**Severity:** HIGH — `/geniro:actions list` and `/geniro:actions run <slug>` validate frontmatter on every invocation; missing field surfaces as a CRITICAL lint and refuses the run.

---

### Custom-reviewer files moved to `review-extra/<slug>.md`

`.geniro/instructions/review-extra/` is now reserved for user-authored review dimensions. Older custom reviewers stored at arbitrary paths (e.g., `.geniro/instructions/my-reviewer.md`) are no longer auto-discovered by `/review`, `/implement` Phase 3, or `/refactor` Phase 3.

**Action required:** For each non-canonical instruction file acting as a custom reviewer, recreate via `/geniro:instructions create review-extra/<slug>` (interview copies the body + adds `slug` / `description` / `model` / `paths` / `severity-default` frontmatter), then `/geniro:instructions delete <old-scope>`.

**Auto-detect:** `ls .geniro/instructions/*.md 2>/dev/null | grep -vE '/(global|code-style|implement|plan|review|debug|refactor|onboard|investigate)\.md$'`

**Auto-fix:** manual-only — custom reviewer migration requires user judgment to set frontmatter fields (`description`, `model`, `paths`, `severity-default`). Run `/geniro:instructions create review-extra/<slug>` per file.

**Severity:** MEDIUM — `load-custom-reviewers.md` reads only `review-extra/*.md`; old files persist untouched but fire no reviewer-agent spawns.

---

### Orphan instruction files for 8 deleted skills

Skills dropped in the consolidation: `/brainstorm`, `/decompose`, `/follow-up`, `/deep-simplify`, `/features`, `/learnings`, `/cleanup`, `/vendor`. Their `.geniro/instructions/<scope>.md` files are no longer loaded by any skill.

**Action required:** Per-file decide: (a) migrate the rules content to the replacement skill's instruction file (mapping in CLAUDE.md "Skills deleted" section: `/follow-up` → `/implement`; `/learnings` → auto-step in `/implement` Phase 3; `/deep-simplify` → `/review` standard dimensions; `/decompose` → `/plan` milestone-mode), then (b) delete: `/geniro:instructions delete <scope>`.

**Auto-detect:** `ls .geniro/instructions/{brainstorm,decompose,follow-up,deep-simplify,features,learnings,cleanup,vendor}.md 2>/dev/null`

**Auto-fix:**

```bash
# Move rules content from deleted-skill instruction files to their replacement skill files
for pair in "follow-up:implement" "deep-simplify:review" "decompose:plan" "brainstorm:plan"; do
  old="${pair%%:*}"; new="${pair##*:}"
  src=".geniro/instructions/$old.md"; dst=".geniro/instructions/$new.md"
  if [ -f "$src" ]; then
    if [ -f "$dst" ]; then
      echo "" >> "$dst"
      echo "# Migrated from $old.md" >> "$dst"
      cat "$src" >> "$dst"
    else
      mv "$src" "$dst"
    fi
    rm -f "$src"
  fi
done
# Delete orphan files for skills with no direct replacement
rm -f .geniro/instructions/{features,learnings,cleanup,vendor}.md 2>/dev/null
```

Review the merged content after migration — some rules may need rewording for the new skill context.

**Severity:** MEDIUM — files inert (no loader reads them); rules they encoded are silently dropped until migrated to the replacement skill.

---

### L3 registry files renamed with `_` prefix

`.geniro/planning/` L3 registry files are now standardized under `_`-prefix to visually distinguish persistent-global from task-local: `_FEATURES.md`, `_CODEBASE_MAP.md`, `_project.md`, `_architecture.md`. `load-semantic.sh` reads only `_`-prefixed paths. `_CODEBASE_MAP.md` retains a one-shot backward-compat read of legacy `CODEBASE_MAP.md` per `_shared/primary-worktree.md`; the other names do NOT.

**Action required:** Rename files to add `_` prefix.

**Auto-detect:** `ls .geniro/planning/{FEATURES,CODEBASE_MAP,project,architecture}.md 2>/dev/null`

**Auto-fix:**

```bash
cd .geniro/planning && \
  [ -f FEATURES.md ]     && mv FEATURES.md     _FEATURES.md     ; \
  [ -f CODEBASE_MAP.md ] && mv CODEBASE_MAP.md _CODEBASE_MAP.md ; \
  [ -f project.md ]      && mv project.md      _project.md      ; \
  [ -f architecture.md ] && mv architecture.md _architecture.md
```

**Severity:** MEDIUM — `/plan`, `/implement`, `/onboard` report "no L3 registry found" until renamed; content is preserved, only the path needs adjusting.

---

### CLAUDE.md may reference deleted skills

`/setup`-generated CLAUDE.md from older installs lists 18 skills including the 8 deleted ones. Users following the table hit "command not found".

**Action required:** Run `/geniro:setup` re-run mode. Phase Generate detects the `<!-- geniro-setup-version: -->` marker and runs orchestrator-inline section merge — preserves user-edited prose while applying the new 11-skill table. Phase Validate verifies zero refs to dropped skills.

**Auto-detect:** `grep -q '^\*\*Skills deleted' CLAUDE.md 2>/dev/null || grep -El '/geniro:(brainstorm|decompose|follow-up|deep-simplify|features|learnings|cleanup|vendor)\b' CLAUDE.md 2>/dev/null`

(Heading-gated + canonical-form-anchored. The first grep short-circuits when CLAUDE.md already carries the "Skills deleted" receipts heading — receipt mentions there are intentional. The second grep is anchored to the canonical `/geniro:<command>` form `/setup` writes; bare-text mentions like `learnings.jsonl` filenames don't match. If your CLAUDE.md uses non-canonical shorthand like bare `/brainstorm`, run `/geniro:setup` re-run regardless.)

**Auto-fix:** manual-only — requires `/geniro:setup` re-run which is an interactive skill invocation. Run `/geniro:setup` after `/update` completes.

**Severity:** MEDIUM — users invoking listed commands hit "not found"; other skills work normally.

---

### Legacy state-file paths superseded by T1/T2/T3

`.geniro/state/` was reorganized per the tier framework: T1.5 durable session-bound (`<skill>/<slug>/state.md`), T2 inter-skill handoff (`handoff/from-<producer>-<branch>.md`), T3 persistent CRUD. Legacy paths like `.geniro/state/follow-up/`, `.geniro/state/decompose/`, `.geniro/state/learnings/`, `.geniro/state/review-findings-state.md` are orphan (skills that wrote them are deleted). `/review` reads legacy `.geniro/state/review-findings-state.md` once on Phase 5 entry for backward-compat resume but writes to the T2 path.

**Action required:** Optional cosmetic cleanup (orphan files inert).

**Auto-detect:** `ls -d .geniro/state/{follow-up,brainstorm,decompose,learnings,deep-simplify,cleanup,vendor,features}/ 2>/dev/null; ls .geniro/state/review-findings-state.md 2>/dev/null`

**Auto-fix:**

```bash
rm -rf .geniro/state/{follow-up,brainstorm,decompose,learnings,deep-simplify,cleanup,vendor,features}/ 2>/dev/null
rm -f .geniro/state/review-findings-state.md .geniro/state/review-findings-adversarial.md 2>/dev/null
```

(Per-subdir `rm -rf .geniro/state/<x>/` and per-file `rm -f` allowed by `.geniro/`-deletion guard; bulk `rm -rf .geniro/state/` blocked.)

**Severity:** LOW — orphan files inert; new skills read the current paths only. Cleanup purely cosmetic. See also v2.4.0 entries for additional orphan paths (root-level `.geniro/debug/`, `.geniro/review-findings-state.md`, `.geniro/.geniro-state.json`, non-canonical knowledge subdirs, state-root loose files).

---

### New safety hooks may block unfamiliar operations

New safety hooks added: `enforce-state-helper.sh` (warns on direct `Edit`/`Write` to `.geniro/` state paths — suggests `atomic_state_write`), `block-geniro-deletion.sh` extended (now blocks `git add -f` on `.geniro/` paths because IDE "Discard All Changes" becomes one-click data-loss), `session-start-restore.sh` (compaction-restore — read-only, never blocks).

**Action required:** If a workflow legitimately needs to bypass a guard, add the pattern ID to `.geniro/safety.json` `allow_patterns` (full ID list in CLAUDE.md "Per-project allowlist for safety guardrails"). The hook output prints the exact ID to add.

**Auto-detect:** N/A — only reveals itself when a blocked operation occurs (fail-loud).

**Auto-fix:** N/A — no migration needed. Hooks activate automatically.

**Severity:** LOW — fail-loud with the bypass ID; no silent corruption possible.

---

### `learnings.jsonl` gained optional `trust:` field

`trust: verified | retrieved | inferred` was added to L2 entries. Entries without the field are treated as implicit `verified` for backward-compat.

**Action required:** None. Future writes carry `trust:`; old reads still work.

**Auto-detect:** N/A — informational.

**Auto-fix:** N/A — no migration needed. Backward compatible.

**Severity:** LOW — no migration needed.

---

### 4 deleted agent files (informational)

Older vendored installs may have `.claude/agents/geniro-{backend,frontend,skeptic,knowledge-retrieval}-agent.md` copied at install time. These 4 agents were removed in a prior consolidation. The plugin update overwrites the agent directory, but vendored copies under `.claude/agents/` are user-owned and untouched.

**Action required:** Optional cleanup for vendored installs only.

**Auto-detect:** `ls .claude/agents/geniro-{backend,frontend,skeptic,knowledge-retrieval}-agent.md 2>/dev/null`

**Auto-fix:**

```bash
rm -f .claude/agents/geniro-{backend,frontend,skeptic,knowledge-retrieval}-agent.md 2>/dev/null
```

**Severity:** LOW — orphan files cause a warning when Claude Code lists agents but do not break spawns (2 current agents register independently).

---

## Notes on `/setup` re-run cleanup scope

`/geniro:setup` re-run runs a **migration sweep** (Phase 3.0) that reads this MIGRATION.md and silently applies safe mechanical auto-fix commands (state-path renames, frontmatter additions, and similar) for entries where the auto-detect indicates the install is affected. Destructive cleanups (rm/delete-class, e.g. orphan-file deletion) are never silently applied — they are surfaced to `## Open Questions` for the user to run via `/geniro:update`'s per-entry walk.

User-authored `.geniro/instructions/review-extra/*`, `.geniro/actions/*`, `.geniro/knowledge/learnings.jsonl`, `.geniro/planning/_*.md` artifacts are **never** touched by the migration sweep — only entries with explicit `Auto-fix:` commands from this file are applied.

`/geniro:update` Phase 4 walks the same full entry set interactively — relevance decided by each entry's read-only auto-detect, not by version range — with per-entry AUQ ("Fix it for me" / "Show me how" / "Skip" / "Cancel").
