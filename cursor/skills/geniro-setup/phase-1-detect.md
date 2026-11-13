<!-- Generated from skills/setup/phase-1-detect.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Setup Phase 1 — Detect

Phase file for `/geniro:setup`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md`.

### 1.1 Mode detect and state-file rehydration

Deterministic resolution (no AUQ):

```
if exists(<PRIMARY_ROOT>/.geniro/state/setup/state.md):
    rehydrate via ${CLAUDE_PLUGIN_ROOT}/lib/validate-state-file.sh
    if frontmatter.phase == "failed":
        surface the `## Termination reason` body section, then mode = re-run
        (a failed run has no phase left to resume into — start fresh)
    elif frontmatter.phase != "done":
        resume from frontmatter.phase
    else:
        mode = re-run (a prior /geniro:setup completed; user is re-invoking)
elif exists(CLAUDE.md) or exists(AGENTS.md):
    mode = re-run (no state file, but a prior instruction file exists — merge into it rather than overwrite)
else:
    mode = init
```

Write `mode: init | re-run` to state frontmatter; persists across the run.

**Pick the instruction file** (`detected.instruction_file`): AGENTS.md when it exists and CLAUDE.md is absent or only imports it (`@AGENTS.md`); otherwise CLAUDE.md, created in init mode. Claude Code does not read AGENTS.md natively, so when CLAUDE.md is absent, §3.3 also creates it holding the single line `@AGENTS.md`. Every later "CLAUDE.md" in this skill's generation, merge, and validation means `instruction_file`.

### 1.2 Query past learnings

After load-custom-instructions, query past learnings for prior `discovery` entries tagged `setup` — route per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.md` §"Memory backend override" (under a declared `## Memory Backend` block, the declared read tool is merged with the file query under `mirror` and replaces it under `replace`):

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh"
query_learnings --type discovery --tag setup --limit 10
```

Surface in `## Phase log` as `Prior /geniro:setup runs: N (last: <timestamp>, stack: <stack>)`. If N ≥ 1, this is at least the 2nd `/geniro:setup` — useful context for Interview.

### 1.3 Locate plugin source

Set `TEMPLATE_DIR` to `${CLAUDE_PLUGIN_ROOT}`, falling back to `$ARGUMENTS` when that is unset or does not look like a plugin root. Test the candidate by the presence of an `agents/` directory inside it — a path that merely exists proves nothing, and a wrong `TEMPLATE_DIR` surfaces much later as missing templates mid-generation. When neither candidate passes, transition to Phase Failed with an `## Errors` row rather than continuing on a guess.

### 1.4 Codebase scan (Evidence Block standard)

Read whatever exists; don't assume. Detect the stack via **lockfile / config presence**, NOT inference: the manifest+lockfile pair for the project's stack captures `pkg_mgr`, `lang`, and `scripts: {...}` where the manifest defines one — `package.json` + `package-lock.json` is `pkg_mgr: npm`, `lang: node`, and the same pattern holds for yarn/pnpm/bun, Python (uv/poetry/pip), Rust (`Cargo.lock`), Go (`go.sum`), Ruby (`Gemfile.lock`), and Java (`pom.xml`/`build.gradle*`).

Each detection records `{ file: <path>, line: <N>, snippet: "<exact text>" }` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. No inference without evidence — if `package.json` exists but no lockfile, `pkg_mgr: unknown` (Interview asks).

Beyond the stack, read: tool configs (linter, formatter, test runner, module resolution) for explicit conventions only; existing AI-tool instructions (`.cursorrules`, `AGENTS.md`, and the like) for domain rules, not just their presence; project documentation and API specs (README, `docs/`, ADRs, OpenAPI) for domain context — endpoints, auth, entities, not full content; env docs (`.env.example`) for variable names and comments, never values; issue-tracker signals and the monorepo layout.

**Spec-driven-development tooling (read-only):** an `openspec/` directory (the default OpenSpec root; a non-default checkout shows the same `project.md` / `specs/` / `changes/` children under a different top-level dir). Store the resolved root as `$OPENSPEC_ROOT` (empty when absent) for the Phase 2 OpenSpec integration question.

Store as `$PROJECT_KNOWLEDGE` for Phase 3.

### 1.5 Skill inventory

List `${CLAUDE_PLUGIN_ROOT}/skills/` — every subdirectory except `_shared` is a skill — into state frontmatter `skill_inventory` (slugs). Name a skill in user-facing text only when `skills/<slug>/` exists.

### 1.6 Detect output

All-results land in state frontmatter `detected:` block. The default branch is captured via `git symbolic-ref --short refs/remotes/origin/HEAD` (fallback `git branch --show-current`) into `default_branch_candidates`, surfaced in the Phase 5 report as `Default branch: <branch> (auto-detected)`. Phase log captures one summary line:

```
[<timestamp>] detect complete — stack=node/npm, lang=node, pkg_mgr=npm, has_tests=true (jest), skill_inventory=<count from §1.5>, evidence_count=14
```

Transition to Phase 2.
