## Additional Steps

### After approval

<!--
Duplicate the approved plan into an OpenSpec change proposal, using THIS repo's own OpenSpec tooling.
Fires after /geniro:plan commits the approved spec (Phase 8). Additive and fail-open: a failure here
never affects the committed Geniro spec. /geniro:setup installed this block because it detected `openspec/`.
-->

This project uses OpenSpec (spec-driven development under `openspec/`). After the plan is approved and committed, duplicate it into a standard OpenSpec change proposal. The Geniro `spec.md` stays the source of truth `/geniro:implement` consumes; the OpenSpec change is a parallel, cross-linked duplicate — never a replacement.

1. Ask once (`AskUserQuestion`, header "OpenSpec"): "Also duplicate this approved plan into an OpenSpec change proposal?" — "Yes" (recommended) / "No". On "No", stop; the Geniro spec is unaffected.

2. On "Yes", apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/repo-tooling-first.md` with these OpenSpec bindings:
   - **Artifact** = a change folder under `openspec/changes/<change-id>/`. Derive `<change-id>` as kebab-case from the spec's Objective or task slug (cap ~40 chars for folder-name readability); if `openspec/changes/<change-id>/` already exists, append `-2` / `-3` so an existing change is never overwritten.
   - **Living template** = an existing non-archived `openspec/changes/<id>/` — read one end-to-end and mirror its file set, its `.openspec.yaml` key set, its requirement/scenario style, and its change-id naming style. Skip `openspec/changes/archive/`. An existing change outranks the hand-written fallback below on any difference.
   - **Tooling** = the `openspec` CLI (`command -v openspec`) and the `/opsx:*` commands. Use a non-interactive `openspec` scaffold where one exists; do NOT re-run the interactive `/opsx:propose` (it would re-derive the plan already approved) — mirror the template instead.
   - **Hand-written fallback** (no existing change AND no scaffold): write `proposal.md` (`## Why` / `## What Changes` / `## Impact` from the spec's Objective + Scope + Risks + Rollback), `tasks.md` (numbered groups with `- [ ]` checkboxes from the spec's Steps), `specs/<capability>/spec.md` (delta: `## ADDED Requirements` → `### Requirement: <name>` → `#### Scenario: <name>` with `- **WHEN**` / `- **THEN**` bullets, derived from the spec's Validation + Done Condition — every requirement needs at least one scenario or `openspec validate --strict` fails), `design.md` for Medium/Big tasks (from the chosen approach + Considered Alternatives), and a per-change `.openspec.yaml` mirrored from an existing one (typically `schema: spec-driven` + `created: <YYYY-MM-DD>` from a live `date -u +%Y-%m-%d` read, never a model-supplied date).
   - **Validate** with `openspec validate <change-id> --strict` when the CLI is installed; surface any failure in plain English, offer a bounded fix (re-author the flagged file, re-validate; max 2 rounds — bounds cost on a secondary artifact), then continue.

3. **Cross-link.** Add a trailer line to `proposal.md`: `Generated from the Geniro plan at \`.geniro/planning/<slug>/spec.md\`.`

4. **Commit** the change folder (`git add openspec/changes/<change-id>/`). Fail-open throughout: a write or validation failure surfaces a one-line caveat and stops, but never touches the already-committed Geniro spec. If the commit itself fails after the folder was written, remove the just-written folder with a guarded command so an unset variable can never widen the delete — `[ -n "$root" ] && [ -n "$change_id" ] && rm -rf -- "$root/changes/$change_id"` — never an unguarded `rm` on an un-interpolated `openspec/changes/<change-id>/` template.
