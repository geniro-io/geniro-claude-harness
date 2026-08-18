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
elif exists(CLAUDE.md):
    mode = re-run (no state file, but a prior CLAUDE.md exists — merge into it rather than overwrite)
else:
    mode = init
```

Write `mode: init | re-run` to state frontmatter; persists across the run.

### 1.2 Query past learnings

After load-custom-instructions, query past learnings for prior `discovery` entries tagged `setup` — route per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.md` §"Memory backend override": under a `## Memory Backend` block query the declared read tool (the file `.geniro/knowledge/learnings.jsonl` is empty under `mode: replace`), else:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh"
query_learnings --type discovery --tag setup --limit 10
```

Surface in `## Phase log` as `Prior /geniro:setup runs: N (last: <timestamp>, stack: <stack>)`. If N ≥ 1, this is at least the 2nd `/geniro:setup` — useful context for Interview.

### 1.3 Locate plugin source

Set `TEMPLATE_DIR` to `${CLAUDE_PLUGIN_ROOT}`, falling back to `$ARGUMENTS` when that is unset or does not look like a plugin root. Test the candidate by the presence of an `agents/` directory inside it — a path that merely exists proves nothing, and a wrong `TEMPLATE_DIR` surfaces much later as missing templates mid-generation. When neither candidate passes, transition to Phase Failed with an `## Errors` row rather than continuing on a guess.

### 1.4 Codebase scan (Evidence Block standard)

Detect via **lockfile / config presence**, NOT inference: the manifest+lockfile pair for the project's stack captures `pkg_mgr`, `lang`, and `scripts: {...}` where the manifest defines one — `package.json` + `package-lock.json` for Node/npm (`pkg_mgr: npm`, `lang: node`; also yarn/pnpm/bun), and the same pattern for Python (uv/poetry/pip), Rust (`Cargo.lock`), Go (`go.sum`), Ruby (`Gemfile.lock`), and Java (`pom.xml`/`build.gradle*`).

Each detection records `{ file: <path>, line: <N>, snippet: "<exact text>" }`. No inference without evidence — if `package.json` exists but no lockfile, `pkg_mgr: unknown` (Interview asks).

**Conventions detected** (read-only — never inferred from heuristic, only from explicit config):

- ESLint config → naming/formatting hints
- Prettier config → style hints
- `.editorconfig` → indentation rules
- `tsconfig.json` / `jsconfig.json` → module resolution
- Test runner: `jest.config.*`, `vitest.config.*`, `pytest.ini`, etc.

**Existing AI tool instructions** (read for domain rules, not just detect presence):

- `.cursorrules`, `.windsurfrules`, `.github/copilot-instructions.md`, `.continue/config.json`, `.cody/`, `AGENTS.md`, `.agents.md`

**Project documentation scan** (extract domain context):

- `README.md`, `CONTRIBUTING.md`, `CONVENTIONS.md`, `ARCHITECTURE.md`, `SECURITY.md`, `API.md`, `docs/architecture.md`, `docs/adr/`, `docs/decisions/`
- API specs: `openapi.{yaml,json}`, `swagger.{yaml,json}`, `asyncapi.{yaml,json}` (extract endpoints/auth/entities — not full content)
- Env docs: `.env.example`, `.env.sample` (variable names and comments; never values)
- GitHub knowledge: `.github/pull_request_template.md`, `.github/ISSUE_TEMPLATE/`
- Monorepo structure: `turbo.json`, `nx.json`, `pnpm-workspace.yaml`, `lerna.json`

**Spec-driven-development tooling (read-only):** an `openspec/` directory (the default OpenSpec root; a non-default checkout shows the same `project.md` / `specs/` / `changes/` children under a different top-level dir). Store the resolved root as `$OPENSPEC_ROOT` (empty when absent) for the Phase 2 OpenSpec integration question.

Store as `$PROJECT_KNOWLEDGE` for Phase 3.

### 1.5 Skill inventory

Reconcile two sources: list `${CLAUDE_PLUGIN_ROOT}/skills/` — every subdirectory except `_shared` is a skill — against the block below, which carries the purpose strings a directory listing cannot. `marketplace.json` holds only a `plugins` entry, not a per-skill array, so there is nothing to extract from it.

```yaml
skill_inventory:
- {slug: implement, purpose: "Spec-driven implementation"}
- {slug: plan, purpose: "Spec-first planning"}
- {slug: review, purpose: "Multi-dim code review"}
- {slug: resolve, purpose: "PR-feedback triage → fix plan"}
- {slug: debug, purpose: "Scientific-method investigation"}
- {slug: refactor, purpose: "Zero-behavior-change restructuring"}
- {slug: onboard, purpose: "Codebase mapping"}
- {slug: investigate, purpose: "Codebase Q&A"}
- {slug: reflect, purpose: "On-demand session-history rule mining"}
- {slug: instructions, purpose: "Custom project-rules management (create/edit/delete)"}
- {slug: audit-instructions, purpose: "Repo-wide AI-instruction audit"}
- {slug: actions, purpose: "Workflow-helper CRUD + runner"}
- {slug: setup, purpose: "Project bootstrap"}
- {slug: update, purpose: "Plugin update + integrity check"}
```

Name a skill anywhere this run produces user-facing text (the Phase 5 report's next-step suggestions, any generated content) only when it appears in **both** the listing and the block — a slug present in only one either points the user at a command that does not run or hides one that does. On a mismatch the directory decides which skills exist and the block supplies the purpose; log the delta to `## Phase log` and write the reconciled set to state frontmatter `skill_inventory`.

### 1.6 Detect output

All-results land in state frontmatter `detected:` block. The default branch is captured via `git symbolic-ref --short refs/remotes/origin/HEAD` (fallback `git branch --show-current`) into `default_branch_candidates`, surfaced in the Phase 5 report as `Default branch: <branch> (auto-detected)`. Phase log captures one summary line:

```
[<timestamp>] detect complete — stack=node/npm, lang=node, pkg_mgr=npm, has_tests=true (jest), skill_inventory=<count from §1.5>, evidence_count=14
```

Transition to Phase 2.
