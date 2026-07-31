# Instructions — Phase 1 block-type reference

Phase-1 sub-body for `${CLAUDE_PLUGIN_ROOT}/skills/instructions/SKILL.md`. Read at `${CLAUDE_PLUGIN_ROOT}/skills/instructions/phase-1-parse.md` §Block-type routing when the resolved mode is `create` or `edit`, and again on any resumption of an authoring step. `list`, `validate`, and `delete` author no block and never read it.

## Block-type detection (which section the request fills)

A `create`/`edit` request implies WHICH block to author, not just which scope. Map the user's intent to the block type so the right section is filled:

| User intent (examples) | Block type | Scope |
|---|---|---|
| "always do X" / "never Y" / a standing rule | `## Rules` | the named/contextual scope |
| "run X after `<phase>`" / "run X before `<phase>`" / a project-specific step at a phase boundary (e.g. duplicate the plan into OpenSpec, archive after ship) | `## Additional Steps` → `### After <phase>` or `### Before <phase>` (e.g. `### After user-approve` for `/plan`, `### Before ship` for `/implement`) | the per-skill scope |
| "run X every time a new worktree is created" / a per-worktree workspace bootstrap (e.g. build a per-worktree code index for an MCP) | `## Additional Steps` → `### After worktree-setup` (a cross-skill event anchor, not a phase) | `global` |
| "hard limit" / "must not exceed" / a gate | `## Constraints` | the named scope |
| "verify facts against my <source>" / "cross-check status from <db/MCP>" | `## Data Sources` (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md`) | `global` or per-skill |
| "the unit suite doesn't cover X" / "only the integration run proves Y" / "what our checks actually verify" | `## Verification Surface` | `global` or per-skill |
| "change how memory/knowledge works" / "store learnings in my MCP" / "use a custom memory backend" | `## Memory Backend` (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/memory-backend.md`) | `memory` (its own dedicated file) |

When the block type is ambiguous, ask in the Step 4 interview; default a vague "add a rule" to `## Rules`. The `## Additional Steps` anchor must name a real phase-enum value for the scope, prefixed `After` or `Before` (enums in `${CLAUDE_PLUGIN_ROOT}/skills/instructions/instructions-authoring-reference.md` §5) — for a `/plan` post-approval step use `### After user-approve`. The sole exception is `### After worktree-setup`: a cross-skill event anchor (hosted in `global.md`, not a per-skill file) that fires when any skill creates a new worktree rather than at a phase boundary.
