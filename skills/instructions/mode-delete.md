# Instructions — `delete` mode

Mode body for `${CLAUDE_PLUGIN_ROOT}/skills/instructions/SKILL.md`. Read on Phase-1 dispatch to `delete`. The spine keeps the scope set, the file shapes, the frontmatter reference, the invariants and the tool surface — this file carries the Steps.

---

### Step 1 — Resolve + read existing file

Read `"$PRIMARY_ROOT"/.geniro/instructions/<scope>.md`. CRUD owns the main checkout's copy, so that is the file `delete` removes even when a same-named one sits in this worktree; say which path was removed in the Step 3 report. If missing: print "nothing to delete" and exit. Else continue.

### Step 2 — Confirm

AUQ 2-option: `Confirm delete` / `Cancel`. Show file size + last-modified for context. For `review-extra/<slug>.md`, the slug must be specified (no bulk-delete).

### Step 3 — Execute

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/repo-root.sh"; PRIMARY_ROOT="$(_geniro_repo_root)"
rm -f "$PRIMARY_ROOT"/.geniro/instructions/<scope>.md
# OR for review-extra:
rm -f "$PRIMARY_ROOT"/.geniro/instructions/review-extra/<slug>.md
```

The `.geniro/` deletion guard hook **allows** per-file `rm -f` of `.geniro/instructions/<scope>.md` (per the hook's "Per-file `rm -f` remain allowed" rule); only bulk `rm -rf .geniro/instructions/` is blocked.

Clean up empty parent dirs silently:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/repo-root.sh"; PRIMARY_ROOT="$(_geniro_repo_root)"
rmdir "$PRIMARY_ROOT"/.geniro/instructions/review-extra/ 2>/dev/null
rmdir "$PRIMARY_ROOT"/.geniro/instructions/ 2>/dev/null
```

For `review-extra` ALL: explicitly refused with "Use `/geniro:instructions delete review-extra <slug>` per-file; bulk delete protected by guard hook."
