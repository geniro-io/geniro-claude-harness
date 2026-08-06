# Repo tooling-first — generate artifacts through the repo's own tooling

Single source of truth for the tooling-first generation primitive. The consumer skill cites this file; do NOT inline-paste the procedure.

Before hand-writing a structured artifact that a repo's own tooling can generate — a scaffolder, generator, CLI, or project command (`make new-migration`, `rails generate`, `nx g`, `cargo generate`, an `openspec` / `/opsx:*` change scaffold, a framework's `create` command) — detect that tooling and generate through it. Hand-writing reverse-engineers a format the tooling already produces correctly, and drifts the moment the tooling's version moves. Read-only on discovery, fail-open: when no tooling is found, fall back to the consumer's own hand-written contract.

## 1. When it applies

A consumer skill is about to emit a structured artifact — a spec or change folder, a migration, a scaffolded module, a config file — into a repo that may already own tooling for that artifact class. Apply this primitive before writing. It does NOT apply to free-form prose or to an artifact no standard tool generates.

## 2. Discover the tooling (read-only)

Two read-only steps:

1. **Read an existing instance as the living template.** List the artifact's home directory and read one existing, non-archived instance end-to-end — its file set, metadata/marker files, internal structure, and naming style. An existing instance in THIS repo is the authority on the exact shape the installed tooling version produces; mirror it.
2. **Detect the generator.** Check for the CLI (`command -v <tool>`), project commands (named in `AGENTS.md` / `README` / `.claude/commands/`, or a `package.json` / `Makefile` script), and any documented refresh step. Note what exists for §3.

## 3. Generate through the tooling

- When a NON-INTERACTIVE generator or CLI scaffold exists, run it to create the skeleton, then fill the skeleton from the content the consumer already produced — so structure and marker files are tool-generated and version-correct, not reverse-engineered.
- When scaffolding is only available as an INTERACTIVE, AI-driven command that would re-derive work the consumer already produced, do NOT re-run it — replicate the artifacts it produces by mirroring the §2 template, then fill them.
- Always finish with the repo's own validator when it has one. When the repo documents a refresh step for its generated commands, surface it to the user rather than running it — it regenerates the team's tooling, which is their call.

## 4. Precedence and edge cases

- **Existing instance outranks the generic contract.** Where the §2 template and the consumer's hand-written fallback contract differ, the template wins — it reflects the installed tooling version.
- **No existing instance (the first one in the repo).** Skip the template-mirror and use the consumer's fallback contract directly; still run §2 step 2 to detect the CLI for scaffolding and validation.
- **Skip archived instances.** A repo's archive directory (e.g. `<artifact-home>/archive/`) holds shipped artifacts, not active templates — never mirror one as if current.

## 5. Boundary vs the reuse audits

This primitive is the generator-side member of the reuse family; it does not overlap the code-reuse audits:

| Primitive | Question it answers |
|---|---|
| `${CLAUDE_PLUGIN_ROOT}/skills/_shared/existing-abstraction-audit.md` | Does THIS repo already have the CODE? (don't reinvent an in-repo abstraction) |
| `${CLAUDE_PLUGIN_ROOT}/skills/_shared/library-reuse-audit.md` | Does the ECOSYSTEM already have the code? (build-vs-buy a library) |
| **this file** | Does THIS repo's own TOOLING already GENERATE the artifact? (don't hand-roll what a scaffolder produces) |

## 6. Fail-open + plain-English echo

Discovery is read-only and never blocks. A missing CLI, an empty artifact directory, or a tooling error degrades to the consumer's hand-written fallback — never to a broken run. Echo what happened in plain words and name the user's own commands, not internal identifiers:

```
I matched the shape of your existing <artifacts> (same files and naming style).
Your <tool> commands refresh with `<cmd>` — run that yourself if the generated <artifact> looks out of date.
```
