# Migration Notes

Plugin-maintainer-authored breaking-change log consumed by `/geniro:update` Phase 4. Each release version (`## vX.Y.Z`) lists changes user content must adapt to; auto-detect commands are safe (`grep` / `find` / `ls` only — never mutate) and report whether THIS install is affected.

For users installing the plugin fresh (no pre-existing `.geniro/`), this file is purely informational — `/geniro:setup` writes the current schema directly.

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

**Auto-detect:** `ls .geniro/instructions/*.md 2>/dev/null | grep -vE '/(global|code-style|user-preferences|implement|plan|review|debug|refactor|onboard|investigate)\.md$'`

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

### New L4 file `user-preferences.md`

`user-preferences` was added as the 4th pipeline-tier loader file (alongside `global.md`, `<skill>.md`, `code-style.md`). Older installs lack it; pipeline skills emit one "No user-preferences.md found — skipping." line per Step 0 (harmless info).

**Action required:** Run `/geniro:setup` re-run mode — Interview phase captures `default_branch` / `default_reviewer_set` / `ship_mode_default` / `communication_style` answers and writes them to `.geniro/instructions/user-preferences.md`. Alternative: `/geniro:instructions create user-preferences` for manual authoring.

**Auto-detect:** `[ ! -f .geniro/instructions/user-preferences.md ] && echo affected`

**Auto-fix:** manual-only — requires `/geniro:setup` re-run or `/geniro:instructions create user-preferences` to capture user preferences interactively.

**Severity:** LOW — pipeline skills function without it (treated as "no preferences set"); creating it customizes default behavior.

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

**Severity:** LOW — orphan files inert; new skills read the current paths only. Cleanup purely cosmetic.

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

`/geniro:setup` re-run is **intentionally conservative**: it re-generates only `CLAUDE.md` (with conflict-resolution merge preserving user edits) and the 4 standard L4 instruction files (`global`, `code-style`, `user-preferences`, and the 7 per-skill files). User-authored `.geniro/instructions/review-extra/*`, `.geniro/actions/*`, `.geniro/knowledge/learnings.jsonl`, `.geniro/planning/*` artifacts are **never** touched.

Orphan-file cleanup is therefore a **user decision surfaced by this MIGRATION.md** (or manual investigation) → user runs `/geniro:instructions delete <scope>` / `/geniro:actions delete <slug>` / shell `rm` per the per-entry guidance above. There is no "destructive sweep" mode in `/setup` by design — the cost of accidental deletion exceeds the value of automation.
