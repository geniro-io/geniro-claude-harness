<!-- Generated from skills/instructions/mode-delete.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Instructions — `delete` mode

Mode body for `${CLAUDE_PLUGIN_ROOT}/skills/instructions/SKILL.md`. Read on Phase-1 dispatch to `delete`. The spine keeps the scope set, the file shapes, the frontmatter reference, the invariants and the tool surface — this file carries the Steps.

---

### Step 1 — Resolve + read existing file

If missing: print "nothing to delete" and exit. Else continue.

### Step 2 — Confirm

AUQ 2-option: `Confirm delete` / `Cancel`. Show file size + last-modified for context. For `review-extra/<slug>.md`, the slug must be specified (no bulk-delete).

### Step 3 — Execute

```bash
rm -f "$PRIMARY_ROOT"/.geniro/instructions/<scope>.md
# OR for review-extra:
rm -f "$PRIMARY_ROOT"/.geniro/instructions/review-extra/<slug>.md
```

The `.geniro/` deletion guard hook **allows** per-file `rm -f` of `.geniro/instructions/<scope>.md` (per the hook's "Per-file `rm -f` remain allowed" rule); only bulk `rm -rf .geniro/instructions/` is blocked.

Clean up empty parent dirs silently:

```bash
rmdir "$PRIMARY_ROOT"/.geniro/instructions/review-extra/ 2>/dev/null
rmdir "$PRIMARY_ROOT"/.geniro/instructions/ 2>/dev/null
```

For `review-extra` ALL: explicitly refused with "Use `/geniro:instructions delete review-extra <slug>` per-file; bulk delete protected by guard hook."
