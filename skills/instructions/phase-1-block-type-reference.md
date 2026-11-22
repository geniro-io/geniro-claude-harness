# Instructions — Phase 1 block-type reference

Phase-1 sub-body for `SKILL.md`. Read at `phase-1-parse.md` §Block-type routing when the mode is `create` or `edit`, and again on any resumption of an authoring step. `list`, `validate`, and `delete` never read it.

## Block-type detection

Map the user's intent to a block type; the placement question below confirms it:

| User intent (examples) | Block type | Scope |
|---|---|---|
| "always do X" / "never Y" / a standing rule | `## Rules` | the named/contextual scope |
| "run X after `<phase>`" / a step at a phase boundary (a discovery stage before the plan takes shape, duplicate the plan into OpenSpec, archive after ship) | `## Additional Steps` → `### After <anchor>`, only where the catalogue (`instructions-authoring-reference.md` §5) lists one at that boundary | the per-skill scope |
| "run X before `<phase>`" | the PRECEDING catalogued anchor ("before the plan takes shape" is `### After explore`, "before any code" is `### After analyze`), offered as a placement candidate, never silently | the per-skill scope |
| a step at a boundary no anchor covers | no block: say so plainly and offer only the real points (Placement question); a subsection that parses but never fires misleads | n/a |
| "run X every time a new worktree is created" / a per-worktree bootstrap | `## Additional Steps` → `### After worktree-setup` | `global` |
| "hard limit" / "must not exceed" / a gate | `## Constraints` | the named scope |
| "verify facts against my <source>" / "cross-check status from <db/MCP>" | `## Data Sources` (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md`) | `global` or per-skill |
| "the unit suite doesn't cover X" / "only the integration run proves Y" / "what our checks actually verify" | `## Verification Surface` | `global` or per-skill |
| "change how memory/knowledge works" / "store learnings in my MCP" / "use a custom memory backend" | `## Memory Backend` (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/memory-backend.md`) | `memory` (its own dedicated file) |

Default a vague "add a rule" to `## Rules`.

## Placement question (where the instruction takes effect)

Runs once per concrete instruction: right away when the `create` request names one, otherwise after the Step 4 interview produces each one. `edit` asks it when adding a rule, step or constraint (changing an existing line keeps its place), offering only the blocks and anchors §5 grants the file being edited. Skip it when the catalogue offers one point (`memory`, `review-extra`).

After the mode and intent are parsed, build 2-4 candidates from §5: the inferred one first, then the nearest alternatives a reader could mean — the same instruction as that skill's `## Rules`, as `global` `## Rules` (every skill), and that skill's step anchor when the request names a moment. When no insertion point covers the requested moment ("before review starts", "before ship"), say so plainly before the question and offer only real points.

Ask one `AskUserQuestion`: header `Placement`, question "Where should this instruction take effect?", inferred option first with ` (Recommended)`, each label `<scope> · <block or anchor>` (`plan · Rules`, `plan · After explore step`, `global · Rules`), each description the catalogue's "Takes effect" cell in plain English, naming who reads it (that skill only, or every skill) from the "Read by" cell. Render the candidates in chat first only when the descriptions cannot carry the difference.

The pick fixes scope, block and anchor, replaces `phase-1-parse.md` §Ambiguity resolution's question for `create`/`edit`, and keeps its 3-round cap.
