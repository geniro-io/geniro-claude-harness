# Debug Handoff Detection (canonical, shared)

**Status:** Authoritative for `/geniro:follow-up` and `/geniro:implement` Phase 1.

When `/geniro:debug` ran earlier in the same project, it left state files at `.geniro/debug/findings-state.md` (scientific mode) and/or `.geniro/debug/adversarial-tests.md` (adversarial mode) — and authored regression tests at the project's normal test paths. Consumer skills MUST detect those artifacts on startup and, if the authored tests are missing from the user's current working tree, surface a relocation suggestion (suggest only — never auto-execute cross-branch git operations).

## Step 1: Scan

Glob both paths from the project root (the toplevel returned by `git rev-parse --show-toplevel`). For each that exists, read fully.

- `.geniro/debug/findings-state.md`
- `.geniro/debug/adversarial-tests.md`

If neither exists, this whole file is a no-op — skip to your next step.

## Step 2: Extract

From `findings-state.md` (markdown — single-occurrence fields):
- `**Source branch:**` line → record as `debug-source-branch`
- `**Source worktree:**` line → record as `debug-source-worktree`
- `**Reproduction test:**` line → strip the path token (everything before the first comma or first `(`); trim leading/trailing whitespace from the result. Treat as one entry in the `authored-test-paths` set; skip if value is `none` or starts with `escape hatch:`.

From `adversarial-tests.md` (markdown — fields appear once at top, plus per-finding):
- `**Source branch:**` and `**Source worktree:**` (top of file) — overwrite the values from `findings-state.md` only if `findings-state.md` was absent (otherwise prefer the scientific-mode values for consistency)
- For each `**Test file:**` line → strip path token (everything before the first ` (` or first `:`); trim whitespace. Add to `authored-test-paths`.

**When persisting to a state file** (e.g., implement's `<task-dir>/state.md` keys `Authored-tests:` / `Debug-source-branch:`): write `Authored-tests:` as comma-separated relative paths on a single line. Consumers split on `,` and trim each token before re-resolving.

## Step 3: Verify

For each path in `authored-test-paths`, resolve relative to the current `git rev-parse --show-toplevel` and check existence with the Read tool (or `test -e` via Bash). Bucket each path as PRESENT or MISSING.

## Step 4: Decide and surface

Three cases:

**Case A — All PRESENT and `debug-source-branch` matches current branch.** Tests are already where they need to be. Surface a one-line acknowledgment in the Phase 1 context summary: `Debug findings detected (<source-branch>); <N> authored test(s) present in current working tree.` No further action.

**Case B1 — Any MISSING.** Surface a SUGGESTION block (suggest-only, do NOT auto-execute):

```
⚠ Debug authored <N> test file(s) on branch '<debug-source-branch>' (worktree '<debug-source-worktree>'); <K> are missing from your current working tree '<current-worktree>' (branch '<current-branch>').

Missing files:
  <each missing path on its own line>

To bring them along, run from your current working tree:
  git checkout <debug-source-branch> -- <space-separated missing paths>

Or copy directly if the source worktree is on disk:
  cp <debug-source-worktree>/<path> <current-worktree>/<path>   # repeat per file

Skip if you intend to re-author them in this branch instead.
```

The user runs the commands themselves — never invoke them via Bash. Cross-branch / cross-worktree file operations have no plugin precedent and conflict with `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` "Forbidden discovery moves".

**Case B2 — All PRESENT but `debug-source-branch` differs from current branch.** Typical of implement Option A (`git checkout -b <new-branch>`) where uncommitted test files follow the working tree to the new branch. Surface a one-line note in the Phase 1 context summary: `Debug ran on '<debug-source-branch>'; you are now on '<current-branch>'; all <N> authored test(s) carried over to the new working tree.` No commands suggested — the tests are already where they need to be.

**Case C — State files exist but `Source branch:` / `Source worktree:` fields are missing** (older debug run, pre-handoff-feature). Treat the existence check as the only signal: if any authored path is missing, surface a degraded suggestion ("Debug findings detected; <N> authored test(s) missing — source branch unknown, run `git log --all -- <path>` to locate") and skip the explicit `git checkout` recommendation. Do not block the consumer skill.

## Anti-rationalization

| Reasoning | Why it's wrong |
|---|---|
| "I'll auto-run `git checkout <other-branch> -- <path>`" | Forbidden by `_shared/scope-anchor.md`. Suggest-only. |
| "The tests exist on the source branch — close enough, skip the warning" | Missing in current worktree means the implementation that's about to start cannot run them. The user needs to know. |
| "Debug findings are old — assume stale and ignore" | The consumer doesn't know how old. Surface them; let the user decide. |
| "I'll embed this scan in Phase 4 instead of Phase 1" | The git-workspace decision in implement Phase 1 Step 7 depends on knowing whether debug authored anything. Detection MUST happen at startup. |
