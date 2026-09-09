# Instructions — `list` mode

Mode body for `${CLAUDE_PLUGIN_ROOT}/skills/instructions/SKILL.md`. Read on Phase-1 dispatch to `list`. The spine keeps the scope set, the file shapes, the frontmatter reference, the invariants and the tool surface — this file carries the Steps.

---

### Step 1 — Scan directory

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/repo-root.sh"; PRIMARY_ROOT="$(_geniro_repo_root)"
ls -la "$PRIMARY_ROOT"/.geniro/instructions/ 2>/dev/null
ls -la "$PRIMARY_ROOT"/.geniro/instructions/review-extra/ 2>/dev/null
```

A listing that comes back empty from a linked worktree means the main checkout has no instruction files — not that this worktree lacks a copy. The resolver already looked there.

### Step 2 — Present results

If empty:

```
No instruction files found.

Run `/geniro:instructions create global` to create your first instruction file,
or `/geniro:instructions create code-style` for project-wide style rules.
```

Else, one row per scope in `SKILL.md` §Valid scope set — including the not-yet-created ones, so the user sees the whole surface — with `review-extra/` as a nested group and a totals footer:

```
Custom instructions in .geniro/instructions/ (project: my-project):

global.md 348 B modified 3 days ago
memory.md (none)
implement.md (none — create with /geniro:instructions create implement)
... one row per remaining scope ...
review-extra/ (directory — 2 files)
├── sql-bindings.md 1.6 KB modified 4 days ago
└── accessibility-aria.md 2.1 KB modified 1 day ago

<total> scopes total · <n> active · <n> not-yet-created
```

Add `--with-content` flag to dump file bodies inline (truncated at ~2000 chars per file).
