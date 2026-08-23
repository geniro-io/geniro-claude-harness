# Debug handoff detection (canonical, shared)

**Status:** Authoritative for consuming `/geniro:debug` T2 handoff files.

When `/geniro:debug` ran earlier in the same project, it left T2 handoff files at `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md` (scientific mode — canonical) and/or `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md` (adversarial mode — canonical) — and authored regression tests at the project's normal test paths. Consumer skills detect those artifacts on startup and, if the authored tests are missing from the user's current working tree, surface a relocation suggestion (suggest only — never auto-execute cross-branch git operations) — an implementation about to start cannot run a regression test absent from its working tree.

## Step 1: Scan

Resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A — the handoff files always live in the primary worktree's `.geniro/state/handoff/` regardless of where this scan runs from. Compute `<branch>` = `git branch --show-current` (fall back to detached-<short-sha> per the slug rules in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md`). Glob the canonical paths; for each that exists, read fully.

**Canonical paths:**
- `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md`
- `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md`

If neither exists, this whole file is a no-op — skip to your next step.

## Step 2: Extract

**Source-branch / source-worktree** (both handoff variants):
- frontmatter `branch:` field → record as `debug-source-branch`. Falls back to body `**Source branch:**` line for legacy files.
- frontmatter `worktree:` field → record as `debug-source-worktree`. Falls back to body `**Source worktree:**` line for legacy files.
- When both variants are present, prefer values from `from-debug-<branch>.md` (scientific) over the adversarial variant for consistency; only fall back to adversarial values when the scientific field is absent.

**Authored test paths — prefer frontmatter (m7-v2+), fall back to body parse (legacy m7-v1):**

1. Check frontmatter `geniro_schema_version` field on each handoff file present.
2. **If `m7-v2` or later** — parse the frontmatter `authored_tests: [...]` array (see schema in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §Producer-specific extensions). For each entry, take `path` and add to `authored-test-paths`. Skip entries with `f_to_p_status: escape-hatch` (they have no on-disk test file). Capture each entry's `intent`, `mode`, `f_to_p_status`, `related_hypotheses`, `targeted_source`, `confidence` alongside the path so downstream consumers can surface them in context summaries without re-reading the file.
3. **If frontmatter lacks `authored_tests[]` (legacy `m7-v1`)** — fall back to body string parse:
   - `from-debug-<branch>.md`: body `**Reproduction test:**` line → strip the path token (everything before the first comma or first `(`); trim whitespace. Skip if value is `none` or starts with `escape hatch:`.
   - `from-debug-adversarial-<branch>.md`: for each body `**Test file:**` line → strip path token (everything before the first ` (` or first `:`); trim whitespace.

**When persisting to a state file** (e.g., implement's `<task-dir>/state.md` keys `Authored-tests:` / `Debug-source-branch:`): write `Authored-tests:` as comma-separated relative paths on a single line. Consumers split on `,` and trim each token before re-resolving. Optionally also persist `Authored-tests-intent:` as a parallel comma-separated list of intents (one per path, same order) when consumed from m7-v2+ frontmatter — preserves the producer's per-test annotation for downstream Phase 2 todo-decomposition.

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
 cp <debug-source-worktree>/<path> <current-worktree>/<path> # repeat per file

Skip if you intend to re-author them in this branch instead.
```

The user runs the commands themselves — never invoke them via Bash. Cross-branch / cross-worktree file operations have no plugin precedent and conflict with `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` "Forbidden discovery moves".

**Case B2 — All PRESENT but `debug-source-branch` differs from current branch.** Typical of implement Option A (`git checkout -b <new-branch>`) where uncommitted test files follow the working tree to the new branch. Surface a one-line note in the Phase 1 context summary: `Debug ran on '<debug-source-branch>'; you are now on '<current-branch>'; all <N> authored test(s) carried over to the new working tree.` No commands suggested — the tests are already where they need to be.

**Case C — State files exist but `Source branch:` / `Source worktree:` fields are missing.** Treat the existence check as the only signal: if any authored path is missing, surface a degraded suggestion ("Debug findings detected; <N> authored test(s) missing — source branch unknown, run `git log --all -- <path>` to locate") and skip the explicit `git checkout` recommendation. Do not block the consumer skill.

## Anti-rationalization

| Reasoning | Why it's wrong |
|---|---|
| "I'll auto-run `git checkout <other-branch> -- <path>`" | Forbidden by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md`. Suggest-only. |
| "The tests exist on the source branch — close enough, skip the warning" | Missing in current worktree means the implementation that's about to start cannot run them. The user needs to know. |
| "Debug findings are old — assume stale and ignore" | The consumer doesn't know how old. Surface them; let the user decide. |
| "I'll embed this scan in Phase 2 instead of Phase 1" | The git-workspace decision in implement Phase 1 Step 0 (Workspace setup) depends on knowing whether debug authored anything. Detection MUST happen at startup. |
