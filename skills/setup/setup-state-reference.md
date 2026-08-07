# Setup — state file schema

Full state.md schema for `/geniro:setup`, extracted from SKILL.md §State file schema. Read this file when writing or validating the setup state file.

Path: `<PRIMARY_ROOT>/.geniro/state/setup/state.md`. Durable singleton at the T1.5 tier, with one deliberate, named exception to that tier's survives-past-ship rule: `/geniro:setup` deletes the file at Phase Done (`phase-5-done.md` §5.3). No downstream skill reads bootstrap state, and a stale copy makes the next invocation resolve to `re-run` against a run that already finished.

## Frontmatter

```yaml
---
tier: T1.5
producer: setup
schema-version: 1
branch: <git-branch> # may be empty if not a git repo
timestamp: 2026-05-19T14:32:00Z # last-updated ISO-8601 UTC
phase: detect # detect|interview|generate|validate|done|failed
status: in-progress # in-progress|done|failed
non-resumable-actions: [] # typically empty (/geniro:setup ships no external sends)
approvals: [] # no preference questions; AUQ-only for detection confirm + onboard prompt
geniro_kind: setup-state
geniro_schema_version: m10a-v1
worktree: /absolute/path # cross-check on rehydration
mode: init # init | re-run
plugin_version: 2.21.1 # from .claude-plugin/plugin.json; the §5.4 restart-warning compares this against the current plugin.json version (missing on a pre-field state file → no delta computable → no warning)
detected:
stack: node/npm
lang: node
pkg_mgr: npm
test_runner: jest
has_eslint: true
default_branch_candidates: [main]
evidence:
- {file: package.json, line: 5, snippet: "\"name\": \"my-project\""}
skill_inventory:
- {slug: implement, purpose: "..."}
# ... one entry per skill in the `phase-1-detect.md` §1.5 inventory
write_targets:
- {path: CLAUDE.md, op: write, loc: 45}
validate_rounds: 1
---
```

## Body sections

```markdown
## Phase log
[2026-05-19T14:00:00Z] init → detect (mode=init)
[2026-05-19T14:02:00Z] detect complete — stack=node/npm, evidence_count=14
[2026-05-19T14:05:00Z] interview → detection confirmed, tracker: Linear
[2026-05-19T14:10:00Z] generate → CLAUDE.md written (45 lines, project-specific only)
[2026-05-19T14:30:00Z] validate round 1 → 0 DRIFT
[2026-05-19T14:32:00Z] → done

## Tool log # selective logging
[14:02:00] Detect: read package.json (evidence #1), package-lock.json (#2),...
[14:30:00] validate: spawn verification subagent → 0 drift items

## Errors # Block 5b (only on failure)
(empty)

## Open Questions # Block 5c (populated on accept-with-warnings)
(empty)

## Persisted approvals # Block 5d (renders frontmatter approvals[])
(empty — no preference questions in current /geniro:setup)

## Termination reason # only set on `failed`
```
