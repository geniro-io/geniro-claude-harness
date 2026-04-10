# Custom Instructions

Project-specific rules and steps that apply to core geniro skills (implement, plan, review, refactor, debug, follow-up). Edit this file to customize how skills behave in your project. Skills read this file at the start of each run.

## Rules

Add project-specific rules that all skills should follow. Each rule should be a single, clear constraint.

Examples (replace with your own):
- Always update relevant documentation when modifying public APIs
- Include a CHANGELOG entry for user-facing changes
- Never modify shared components in `packages/shared/` without updating all consumers
- Run `pnpm run full-check` before marking any task complete

## Additional Steps

Add custom steps that skills should execute at specific points. Use the phase names from each skill (e.g., "After implementation", "Before shipping", "After review").

### After implementation
<!-- Steps to run after code changes are applied (implement Phase 4, follow-up Phase 4) -->

### Before shipping
<!-- Steps to run before committing/pushing (implement Phase 7, follow-up Phase 6) -->

### After review
<!-- Steps to run after code review completes (review Phase 4) -->

## Constraints

Add hard limits that skills must respect.

Examples (replace with your own):
- Maximum PR size: 500 lines changed
- Always include tests for new public functions
- Database migrations must be backwards-compatible
