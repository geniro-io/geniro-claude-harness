# Workflow: OpenSpec Integration

This project uses [OpenSpec](https://github.com/Fission-AI/OpenSpec) for spec-driven development. Skills read this file at runtime to adapt their behavior: when it is present, `/geniro:plan` offers to duplicate an approved plan into a standard OpenSpec change proposal.

## Contents

- Configuration
- Detection
- Plan Skill Behavior
- CLI

## Configuration

```yaml
openspec:
  enabled: true
  directory: openspec        # the OpenSpec root, relative to the repo root. Default "openspec"; set to a custom path when this repo configures one.
```

`/geniro:plan` reads `directory` as the OpenSpec root for every write — `<directory>/changes/<change-id>/` and `<directory>/specs/<capability>/`. Edit it here if the team moves the OpenSpec root.

## Detection

`/geniro:plan` confirms the configured `directory` still exists (read-only) before offering the duplicate. When `enabled: false` or the directory is gone, the offer stays dormant — no behavior change.

## Plan Skill Behavior

When this file enables the integration AND the OpenSpec directory exists, `/geniro:plan` (after the user approves the plan) offers to duplicate the approved plan into an OpenSpec change proposal under `<directory>/changes/<change-id>/` — `.openspec.yaml` marker, `proposal.md`, `tasks.md`, requirement deltas under `specs/<capability>/`, and `design.md` for larger changes — cross-linked to the Geniro `spec.md` and committed alongside it. It generates through this repo's own OpenSpec tooling and conventions: it reads an existing change as the template and uses the `openspec` CLI / `/opsx:*` commands where they can scaffold, so the result matches the installed OpenSpec version rather than a reverse-engineered format. The Geniro `spec.md` remains the source of truth `/geniro:implement` consumes; the OpenSpec change is a parallel, cross-linked duplicate. Full contract: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/openspec-integration.md`.

The `--openspec` / `--no-openspec` modifier on `/geniro:plan` pre-answers the per-plan offer; otherwise it is a one-line suggestion the user accepts or declines per plan.

## CLI

The `openspec` CLI is optional. When it is installed, `/geniro:plan` runs `openspec validate <change-id> --strict` after writing the change and surfaces any issue. When it is absent, the written files still follow OpenSpec's documented format. Install it with the team's OpenSpec setup (e.g. `npm install -g @fission-ai/openspec` or per the project's chosen package manager).
