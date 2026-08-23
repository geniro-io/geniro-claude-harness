# Instructions — `edit` mode

Mode body for `${CLAUDE_PLUGIN_ROOT}/skills/instructions/SKILL.md`. Read on Phase-1 dispatch to `edit`. The spine keeps the scope set, the file shapes, the frontmatter reference, the invariants and the tool surface — this file carries the Steps.

---

### Step 1 — Read the existing file for the scope Phase 1 resolved

If missing, branch to `create`. Else display current body inline.

### Step 2 — Pick the edit path

- **Question:** "How would you like to edit `<scope>`?"
- **Options:**
- `Apply the change you described` — offered when the invocation already names a concrete change ("change the test command in my implement rules to `pnpm test:ci`"). Draft the edited body, show what changed, and gate the write on the same AUQ as the dialogue path.
- `Open in editor (external)` — Print absolute path; instruct user to edit externally and re-run `/geniro:instructions validate <scope>` when done. Exit.
- `Rewrite via dialogue` — Interview-style sequence of AUQs (Add a Rule / Add an Additional Step / Add a Constraint / Remove a Rule by number / Done). Apply edits to an in-memory copy; final write AUQ-gated.
- `Cancel`

### Step 3 — Re-validate (review-extra only)

After editing a `review-extra` file, re-run the lint rule set against the edited file. If any rule fails, AUQ revert vs keep-and-fix-later.

### Step 4 — Show updated file

```
Updated `.geniro/instructions/<scope>.md`. The new rules take effect the next time you run `/geniro:<scope>` (or any affected skill for global.md), unless this worktree has its own differing copy of the file — that copy takes precedence here.
```

### Body section invariants (post-edit)

- `## Rules` section present (may be empty list; skip for `review-extra/<slug>.md` — uses `# Criteria` instead).
- `## Additional Steps` section present (omitted for the rules-only scopes `code-style`, `review-extra/<slug>`, `review`, `resolve`, `debug`, `onboard`, `investigate`, `reflect`; for `implement`/`plan`/`refactor` it carries at most that scope's one legal anchor, §5; for `global` the section is optional and, when present, carries only the cross-skill `### After worktree-setup` event anchor).
- `## Constraints` section present (may be empty list; skip for `review-extra/<slug>.md` — uses `# Criteria` instead).
- Frontmatter (for `review-extra/<slug>.md`) parses YAML cleanly.

Violations are not auto-fixed; `validate` surfaces them on next invocation.
