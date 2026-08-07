# Setup Phase 0 — Pre-flight

Phase file for `/geniro:setup`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md`.

**Step 0 — Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: setup`, `LOAD_TIER: rules-only`, `MODE: initial-load`. The helper's §Echo contract requires one observable line.

**Resolve `PRIMARY_ROOT`** via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A. `/geniro:setup` writes to `<PRIMARY_ROOT>/.geniro/state/setup/state.md` (singleton — main worktree only, even when invoked from a linked worktree).

`PROJECT_ROOT` is the current project root — the worktree `/geniro:setup` was invoked from (the cwd). `CLAUDE.md` is written to `PROJECT_ROOT` — a tracked repo file that belongs to the invoked checkout/branch. `.geniro/instructions/` and `.geniro/workflow/` are written to `<PRIMARY_ROOT>` — cross-session user-authored content that must survive worktree removal, per the primary-worktree contract. When invoked from a linked worktree the two diverge, so keep them distinct.

Exit criterion: custom instructions loaded and echoed, `PRIMARY_ROOT` and `PROJECT_ROOT` both resolved. Transition to Phase 1.
