# Migration Notes

Plugin-maintainer-authored breaking-change log consumed by `/geniro:update` Phase 4. Each release version (`## vX.Y.Z`) lists changes user content must adapt to; auto-detect commands are safe (`grep` / `find` / `ls` only — never mutate) and report whether THIS install is affected.

For users installing the plugin fresh (no pre-existing `.geniro/`), this file is purely informational — `/geniro:setup` writes the current schema directly.

---

## v3.0.0

The v3 release lands the /implement 3-phase rewrite, MANDATORY /review spawn list with pre/post-spawn verification gates, /plan workflow_refs[] tracker linkage (m5-v2 schema), per-section AUQ `preview` field with restored Phase 2 Visual Companion, structured `open_questions[]` in T2 handoffs with a 3-gate safety chain, T1/T1.5 state tier split for Ship-cleanup preservation, and universal `model: inherit` for all plugin subagents. Seven changes need user attention; auto-fix is provided where mechanical, manual review is called out where judgment is needed.

### Ship cleanup now preserves durable artifacts (T1 → T1.5 split)

`/geniro:implement` Phase 3 Ship sub-step now preserves `spec.md`, `state.md`, `plan-*.md`, `milestone-*.md` (the new T1.5 durable layer). Only transient subagent outputs (`.kr-out.md`, `.ce-out.md`, `.tr-out.md`, `.adversarial-out.md`, `notes.md`, `playwright-verify.png`) delete at Ship. Downstream `/geniro:review` spec-compliance and `/geniro:implement` adjustment routing now find their context reliably across runs.

**Action required:** Delete any pre-v3 orphan transient files left behind inside completed task-dirs.

**Auto-detect:** `find .geniro/planning -maxdepth 2 \( -name '.kr-out.md' -o -name '.ce-out.md' -o -name '.tr-out.md' -o -name '.adversarial-out.md' \) 2>/dev/null`

**Auto-fix:**

```bash
find .geniro/planning -maxdepth 2 \( -name '.kr-out.md' -o -name '.ce-out.md' -o -name '.tr-out.md' -o -name '.adversarial-out.md' \) -exec rm -f {} + 2>/dev/null
```

**Severity:** LOW — orphan transient files are inert; v3 `/implement` creates and cleans them per-run.

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

State files placed directly at `.geniro/state/` root (not in a skill subdirectory) are non-canonical. Canonical T1 paths follow `.geniro/state/<skill>/<slug>/state.md`. Files like `integration-flakes-grind.md` and `pre-compact-snapshot.json` at state root are task artifacts from prior sessions that were never cleaned up.

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
for f in $(find .geniro/actions -maxdepth 1 -name '*.md' -exec grep -L '^risk_class:' {} +); do
  sed -i '/^---$/,/^---$/{/^---$/!{/^---$/!{0,/^---$/!s/^---$/risk_class: low\n---/}}}' "$f" 2>/dev/null || \
  sed -i '2a risk_class: low' "$f"
done
```

Adds `risk_class: low` to the frontmatter of each affected action. Users should review and adjust to `medium` or `high` where appropriate after the fix.

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

**Action required:** Per-file decide: (a) migrate the rules content to the replacement skill's instruction file (mapping in CLAUDE.md "Skills deleted" section: `/follow-up` → `/implement`; `/learnings` → auto-step in `/implement` Phase 3; `/deep-simplify` → `/review --simplify`; `/decompose` → `/plan` milestone-mode), then (b) delete: `/geniro:instructions delete <scope>`.

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

`.geniro/state/` was reorganized per the 3-tier framework: T1 ephemeral session-bound (`<skill>/<slug>/state.md`), T2 inter-skill handoff (`handoff/from-<producer>-<branch>.md`), T3 persistent CRUD. Legacy paths like `.geniro/state/follow-up/`, `.geniro/state/decompose/`, `.geniro/state/learnings/`, `.geniro/state/review-findings-state.md` are orphan (skills that wrote them are deleted). `/review` reads legacy `.geniro/state/review-findings-state.md` once on Phase 5 entry for backward-compat resume but writes to the T2 path.

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

`/geniro:setup` re-run runs a **migration sweep** (Phase 3.0) that reads this MIGRATION.md and silently applies all auto-fix commands for entries where the auto-detect indicates the install is affected. This covers orphan file cleanup, state-path renames, frontmatter additions, and other mechanical fixes.

User-authored `.geniro/instructions/review-extra/*`, `.geniro/actions/*`, `.geniro/knowledge/learnings.jsonl`, `.geniro/planning/_*.md` artifacts are **never** touched by the migration sweep — only entries with explicit `Auto-fix:` commands from this file are applied.

`/geniro:update` Phase 4 walks the same entries interactively with per-entry AUQ ("Fix it for me" / "Show me how" / "Skip" / "Cancel").
