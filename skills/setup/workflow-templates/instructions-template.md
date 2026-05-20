# Custom Instructions

Project-specific rules и steps that apply к Geniro pipeline + discovery skills (implement, plan, review, refactor, debug, onboard, investigate). Edit this file к customize how skills behave в your project. Skills read this file at the start of each run и at every phase-boundary refresh via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`.

## Rules

Add project-specific rules that all skills should follow. Each rule should be а single, clear constraint.

Examples (replace с your own):
- Always update relevant documentation when modifying public APIs
- Include а CHANGELOG entry for user-facing changes
- Never modify shared components в `packages/shared/` без updating all consumers
- Run `pnpm run full-check` before marking any task complete

## Additional Steps

Add custom steps that skills should execute at specific points. Use the **lowercase-hyphenated phase enum** from each skill (M4-M9 — e.g., `After implement`, `Before ship`, `After self-review`). Validate via `/geniro:instructions validate` к catch typos.

### After implement
<!-- Steps к run after code changes are applied (M4 /implement Phase 2 — analyze → implement) -->

### Before ship
<!-- Steps к run before committing/pushing (M4 /implement Phase 3 — Ship sub-step) -->

### After self-review
<!-- Steps к run after self-review completes (M4 /implement Phase 3) -->

## Constraints

Add hard limits that skills must respect.

Examples (replace с your own):
- Maximum PR size: 500 lines changed
- Always include tests для new public functions
- Database migrations must be backwards-compatible
