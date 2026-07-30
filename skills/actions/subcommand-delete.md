# Actions — `delete` sub-command (Phase 6)

Sub-command body for `${CLAUDE_PLUGIN_ROOT}/skills/actions/SKILL.md`. Read on Phase-1 dispatch to `delete`. The spine keeps the invariants, the anti-rationalization table, the tool surface and the termination mapping — this file carries the Steps.

## Phase 6: `delete` sub-command

### Step 1 — Resolve target copy

Apply `${CLAUDE_PLUGIN_ROOT}/skills/actions/actions-reference.md` §Target resolution. Its Step 4 resolves which copy to delete — the canonical main-repo copy by default, the local branch copy when only it exists or the user picks it. Continue with `<resolved-path>`.

### Step 2 — Confirm + high-risk warning

Read action's frontmatter `risk_class`. AUQ:

- **Question:** "Delete `<resolved-path>`? This cannot be undone unless the file is committed to git." (For `risk_class: high`, prepend: "⚠ This high-risk action will be permanently removed; if it represents critical workflow, consider versioning it first via `/geniro:actions edit <resolved-slug>` and renaming to `<resolved-slug>-archived`.")
- **Options:** `Delete the file` / `Cancel` (Recommended)

### Step 3 — Execute

If confirmed:

```bash
rm -f "<resolved-path>"
rmdir "$(dirname "<resolved-path>")" 2>/dev/null # silently if empty
```

Print: "Deleted `<resolved-path>`."

The `.geniro/` deletion guard hook **allows** per-file `rm -f` of `.geniro/actions/<slug>.md` (per the hook's "Per-file `rm -f` remain allowed" rule); only bulk deletion is blocked.
