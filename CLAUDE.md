# Geniro Plugin

Production-grade Claude Code plugin with AI-driven setup, multi-agent workflows, and safety hooks.

## Getting Started

Run `/geniro:setup` to analyze your codebase and generate a tailored configuration:
- Project-specific CLAUDE.md with detected tech stack, commands, and conventions

## Available Skills

The current skill set is 12 skills. The 8 deleted skills (`/brainstorm`, `/decompose`, `/follow-up`, `/deep-simplify`, `/features`, `/learnings`, `/cleanup`, `/vendor`) have their replacements documented in the right-hand column; their `skills/` directories have been removed.

| Skill | Purpose |
|-------|---------|
| `/geniro:plan` | Spec-first planning — turns a vague idea into an approved 11-section `spec.md`: explore → uncapped clarify grill → 2-3 critic-tested approaches → 3 clustered section approvals → mechanical validate → adversarial spec-challenge → user approval → handoff. Decision gates render message-first per `_shared/gate-rendering.md`. Big tasks emit sibling `milestone-N.md` files; an optional `launch_config` spec block pre-answers `/implement`'s setup questions. Flags: `--prd` (problem-discovery pre-phase), `--deep` (wider search + 3-vote claim verification), `--artifact` (live visual plan page per `_shared/plan-artifact.md`). Commits only after final approval. |
| `/geniro:implement` | 3-phase autonomous executor (Analyze → Implement → Self-review-and-Ship) consuming `spec.md` from `/plan` or an inline task. Workspace + branch-freshness setup, parallel knowledge-retrieval/codebase-explorer research, pre-edit spec fact-check, TodoWrite decomposition with end-of-phase test runs, then parallel reviewer + adversarial-tester self-review, a minor-findings disposition gate (unfixed low-priority findings: fix now or list in the ship report), a test-quality gate, and an action-gated Ship step. Consumes handoffs from `/review`, `/debug`, `/resolve` and blocks edits while their `open_questions[]` are unresolved. `--deep` deepens self-review and the spec fact-check. |
| `/geniro:review` | Read-only 6-phase review of a diff/branch/PR: triage → mechanical pre-pass → parallel single-dimension reviewers (7 always-fire + conditional + custom) → multi-signal filter → fresh-agent verification of every surviving finding → persisted report + handoff with `open_questions[]`. Never edits code or tracker status; downstream consumers apply the fixes. Set-aside minor findings persist in the report and are user-electable into the fix list (chained gate after the handoff pick) or the PR post. `--deep` adds multi-angle passes + majority verification. |
| `/geniro:resolve` | Read-only PR-feedback triage: syncs the workspace to the PR head/base, reads unresolved review threads + failing CI checks, verifies and reproduces each item, then emits a comment-keyed `spec.md` + handoff for `/implement` — which applies the fixes and, at Ship, posts the drafted replies and resolves the threads. Never edits code, never posts to the PR itself. |
| `/geniro:debug` | Scientific-method bug investigation (Investigate → Propose → Ship): observe → hypothesize → test → isolate root cause, author a text fix proposal + failing reproduction test, then hand off to `/implement`. Never edits production source, never ships. Adversarial mode authors F→P tests against a diff. `--deep` runs the deeper investigation mode. |
| `/geniro:refactor` | Zero-behavior-change restructuring (Plan → Apply → Verify): tier-scaled smell detection, HIGH-step approval, per-step regression checks with a blocked-step protocol, independent review. Never ships — the working-tree diff is the deliverable; product decisions escalate to `/implement`. |
| `/geniro:onboard` | Rapid orientation in an unfamiliar codebase: scans structure (≤50-file default cap) and writes `<PRIMARY_ROOT>/.geniro/planning/_CODEBASE_MAP.md` on the canonical 8-section template. `--focus` / `--depth` limit scope. |
| `/geniro:investigate` | Evidence-based Q&A over code, git history, and the internet: classifies the question, spawns 1-3 matching research agents, re-verifies load-bearing claims, presents a cited answer with save-routing. Never ships code. |
| `/geniro:instructions` | Stateless CRUD (list / create / edit / validate / delete) over `.geniro/instructions/` — the project-rules layer. Scopes: `global`, `code-style`, `memory`, `review-extra/<slug>`, per-skill. Also manages the optional `## Data Sources`, `## Memory Backend`, and `## Additional Steps` blocks. Writes resolve to the primary worktree. |
| `/geniro:actions` | CRUD + runner over `.geniro/actions/` — user-authored workflow helpers (Slack/PR/release automations) with mandatory `risk_class` frontmatter. `run <name>` executes directly: invoking IS the authorization, no confirmation gate. |
| `/geniro:setup` | Singleton bootstrap (Detect → Interview → Generate → Validate): detects the stack from lockfiles/configs, interviews for ambiguous detections + integrations (issue tracker, OpenSpec), generates a project-specific CLAUDE.md, and verifies it via a read-only subagent. Re-run mode sweeps `MIGRATION.md` first. |
| `/geniro:update` | Pulls the latest plugin version with integrity checks: user-content snapshot + survival diff, retry backoff, hash sanity check, then a per-entry `MIGRATION.md` walk with maintainer-written auto-fixes. `--dry-run` previews. |

**Skills deleted:**

| Deleted | Replacement |
|---|---|
| `/geniro:brainstorm` | Merged → `/geniro:plan` |
| `/geniro:decompose` | Merged → `/geniro:plan` (milestones as output mode) |
| `/geniro:follow-up` | Absorbed → `/geniro:implement` (handles any size via spec input) |
| `/geniro:deep-simplify` | Dropped — reuse/quality/efficiency now covered by `/geniro:review` standard dimensions (architecture / conventions / optimizations) |
| `/geniro:features` | Manual `_FEATURES.md` or via `/geniro:plan` |
| `/geniro:learnings` | Auto-step in `/geniro:implement` Phase 3 and `/geniro:debug` |
| `/geniro:cleanup` | Dropped — niche |
| `/geniro:vendor` | Dropped — no cloud-runner requirement |

## Path Rules

**NEVER use `~` in file paths passed to Read, Write, Edit, or Glob tools.** The `~` is NOT expanded by these tools and creates a literal `~` directory. Always use `${CLAUDE_PLUGIN_ROOT}` for plugin files or fully resolved absolute paths for project files.

## State Files

Every state file under `.geniro/` belongs to exactly one tier and must be written through the atomic-write helpers — not direct `Edit`/`Write` calls.

| Tier | Paths | Helper |
|------|-------|--------|
| **T1 — TASK ephemeral** (transient working artifacts, targeted `rm -f` at terminal exit — Ship cleanup and every other terminal transition of the owning run) | `.geniro/planning/<task-dir>/.{kr,ce,tr,adversarial,research,spec-challenge}-out.md` (subagent OUTPUT_PATH reports) · `.geniro/planning/<task-dir>/.research-<facet>.md` (per-facet research outputs from /plan Phase 1) · `.geniro/planning/<task-dir>/notes.md` (scratch) · `.geniro/planning/<task-dir>/playwright-verify.png` (visual-verify artifacts) | `atomic_state_write` |
| **T1.5 — TASK durable** (survives Phase Ship; design artifacts user may want to keep) | `.geniro/planning/<task-dir>/{spec,state}.md` · `.geniro/planning/<task-dir>/plan-*.md` · `.geniro/planning/<task-dir>/milestone-*.md` · `.geniro/state/<skill>/<slug>/state.md` (`/debug`, `/refactor`, `/onboard`, `/investigate`) · `.geniro/state/setup/state.md` singleton (`/setup`) | `atomic_state_write` |
| **T2 — HANDOFF** (inter-skill, overwritten by producer) | `.geniro/state/handoff/from-<producer>-<branch>.md` (carries structured `open_questions[]` for safety-gated consumer transitions) | `atomic_state_write` |
| **T3 — PERSISTENT CRUD** | `.geniro/instructions/*` · `.geniro/actions/*` · `.geniro/workflow/*` · `.geniro/planning/_*.md` · `.geniro/docs/*` (spin-out targets) | `atomic_state_write` (caller does optimistic mtime check first) |
| **T3 — PERSISTENT append-only** | `.geniro/knowledge/learnings.jsonl` | `atomic_state_append` |

**T1 vs T1.5 — terminal-exit cleanup contract.** Each skill that writes into a planning task-dir runs the targeted `rm -f` on its T1 files before its own terminal `phase:` write, via the shared helper `lib/clean-task-transients.sh` (`clean_task_transients <task-dir>` — the single source of the T1 list). `/implement` runs it before EVERY terminal `phase:` write (`done`, `aborted`, `debug-handoff`, `self-review-only`, `ship-committed-only`) — not only the Ship path; `/plan` runs it on `done`/`aborted`. T1.5 files survive so the user retains the spec, state log, and milestone breakdown for future reference, audit, or re-runs of `/implement` against the same task-dir. `/plan` cleaning its own scratch closes the leak where a plan-only or milestone-sliced run left `.research-*.md` behind (in milestone slicing `/implement` runs in a different task-dir, so it never reached the parent planning dir); `/implement`'s run stays a backstop, and transients left by an interrupted run are swept by the `/geniro:update` migration walk. The within-skill skills (`/debug`, `/refactor`, `/onboard`, `/investigate`) instead `rm -rf` their whole `.geniro/state/<skill>/<slug>/` dir at terminal exit (state.md + any scratch the run wrote there), since the migration walk scans only `.geniro/planning`. Per memory rule: "when a producer adds an output field, every durable state-file schema between producer and consumer must be updated in lockstep" — schema changes propagate across producer and consumer state files.

**Documented exception — TDD-cycle state file.** `.geniro/state/tdd/state-<slug>.md` is a live state file under `.geniro/state/` that is carved out of the universal atomic-write-helper claim above. It is slug-scoped, single-writer (only the TDD-order hook's orchestrator writes it; sub-agents never do — see Safety Hooks §TDD-order enforcement), Markdown-not-JSON (a half-written Markdown file is still readable; a half-written JSON object is not), and written via a custom `mktemp` + `mv -f` atomic procedure rather than `atomic_state_write` (full contract: `skills/_shared/tdd-cycle.md` §State file contract). It tracks only the current RED/GREEN/REFACTOR/IDLE phase so the PreToolUse hook can gate `Edit`/`Write` at the right moment, so it does not fit the tier model's frontmatter-bearing-artifact shape.

**Helper invocation** (from inside a skill's Bash call):

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"
atomic_state_write ".geniro/planning/<task-dir>/state.md" <<'EOF'
---
tier: T1
producer: implement
schema-version: 1
branch: <git-branch>
timestamp: <ISO-8601 UTC>
phase: implement
status: in-progress
non-resumable-actions: []
---

## Body
...
EOF
```

**Validation before resume:**

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/validate-state-file.sh"
if ! validate_state_file ".geniro/planning/<task-dir>/state.md"; then
  # Open recovery AskUserQuestion (delete-and-restart / open-in-editor / update-worktree-path / skip-emergency)
  ...
fi
```

**Full reference:**
- `skills/_shared/state-tier-spec.md` — canonical schema and per-tier required fields.
- `skills/_shared/atomic-state-write.md` — write helper, exit codes, mtime-check pattern.
- `skills/_shared/validate-state-file.md` — validator, exit codes, recovery AUQ template.

## Memory Layers

Every persisted fact lives in exactly one of four layers. Writers know **what** to record and **where**; readers know **which layer** answers a question. Anything that doesn't fit one of these layers is by definition out of scope for the memory subsystem.

| Layer | Name | Lifespan | Routing rule (writer intent → layer) | Path |
|-------|------|----------|---------------------------------------|------|
| **L1** | Working | Per-task | "Right now, phase X of task Y is running." | `.geniro/planning/<task-dir>/state.md` (T1) |
| **L2** | Episodic | Append-only event log | "In this run we observed event X." | `.geniro/knowledge/learnings.jsonl` |
| **L3** | Semantic | Current-state snapshot | "In this project, fact X is currently true." | `.geniro/planning/_*.md` |
| **L4** | Procedural | Stable rules | "When doing X, always do Y." | `.geniro/instructions/*.md` |

**Cross-layer precedence (when layers disagree): L4 > L3 > L2.** L4 is user-curated explicit rules (highest trust); L3 is drift-monitored current state; L2 is historical events with the lowest cross-layer trust. L1 is task-scoped and never conflicts cross-layer.

**Within-layer:** recency wins. L2 uses the `supersedes` chain. L3 uses fingerprint refresh / file mtime. L4 uses file mtime.

### Helper invocation

| Helper | Purpose |
|--------|---------|
| `_shared/load-custom-instructions.md` | Load L4 — `global.md` + `<skill>.md` + `code-style.md`; base dir is overridable to an external location via `GENIRO_INSTRUCTIONS_DIR` (or the plugin's `instructions_dir` install option) for sourcing instructions outside the repo |
| `_shared/subagent-instruction-load.md` | Subagent-side load of `global.md` / `code-style.md` / `memory.md` for a leaf agent (no orchestrator context reaches a fork); a reader agent carrying `mcp__*` uses its `memory.md` bullet to route its own L2 read under a `## Memory Backend` block |
| `lib/load-semantic.sh` | Load L3 — `_project.md` + `_CODEBASE_MAP.md` by default; `--extras "..."` for additional files; auto-runs fingerprint drift check to stderr |
| `lib/update-semantic.sh` | Bounded-write L3 — `--file <codebase-map\|features> --append "<line>"` or `--replace "<prefix>" "<new>"`. Per-file POSIX-O_EXCL lock; rc=11 if held |
| `lib/emit-learning.sh` | Append L2 — JSON on stdin, auto-sanitization, auto-dedup with supersede chain |
| `_shared/memory-backend.md` | Route L2 (learnings) through a project-declared `## Memory Backend` block in the dedicated `.geniro/instructions/memory.md` file — an MCP/action backend, `mode: mirror\|replace`, applied by the orchestrator at the `emit-learning` / `query-learnings` call-sites (shell can't call MCP), redact-before-store + read-only-screened + fail-open to the file. Absent file/block = built-in `learnings.jsonl`, unchanged |
| `lib/query-learnings.sh` | Read L2 — flags: `--type`, `--tag`, `--scope`, `--min-trust`, `--score-min` (recency × trust × access × recurrence ranking), `--include-superseded`, `--include-deprecated`, `--include-archive`, `--limit`. Also exports `record_access <dedup_key>` for access-count bumping |
| `lib/redact-secrets.sh` | Regex sanitization for any free-form text — called automatically by `emit_learning`; also reusable standalone |
| `lib/archive-stale.sh` | Walk `learnings.jsonl` and flip `deprecated: true` on entries matching score<0.1 + age>180d + access_count==0. Auto-runs on SessionStart (default ON, opt-out via `safety.json memory.auto_archive_stale: false`); `--dry-run` previews manually. Never deletes (audit trail). Multi-tab safe via mkdir-lock. Its stderr report also carries a verification-coverage line (verified-fraction of live, non-deprecated learnings — `verified: N/total (P%)`; `n/a` when empty). |
| `lib/emit-rejection.sh` | AUQ-rejection L2 emit helper — exports `emit_rejection_if_signal()`; detects explicit-cancel/no/skip OR picked-non-recommended signals and emits `user_rejected_suggestion` to L2. Wired in /plan, /implement Phase 3 ship-mode, /debug, /refactor, and /onboard. |
| `lib/repo-root.sh` | Resolve the repository root — exports `_geniro_repo_root` (worktree-aware: walks up for `.geniro/`, falls back to `git rev-parse --show-toplevel`, then `$PWD`). Sourced by `update-semantic` / `emit-learning` so memory writes land at the correct root across multi-worktree checkouts. |

### Conflict surfacing protocol

When a load-* helper detects layers disagreeing, the calling skill prints a notice in its output and continues using the precedence-winning value. For **hard conflicts** (L4 rule directly contradicts L3 reality), the skill halts and calls `AskUserQuestion`. Both notice format and AUQ template live in `skills/_shared/resolve-conflicts.md`.

**Full reference:**
- `skills/_shared/redact-secrets.md` · `emit-learning.md` · `query-learnings.md` · `archive-stale.md` · `emit-rejection.md` · `load-semantic.md` · `update-semantic.md` — per-helper API contracts.
- `skills/_shared/resolve-conflicts.md` — cross-layer conflict notice format.

## Custom Agent Invocation

When a skill spawns a plugin-defined agent (`reviewer-agent`, `adversarial-tester-agent`, `reflection-agent`) via the `Agent(subagent_type="<name>", ...)` tool, the registered form varies by runtime: interactive Claude Code with the plugin marketplace-installed registers agents under `geniro-claude-plugin:<agent>`; vendored / harness installs register them under bare `<agent>`; Claude Code SDK / cloud runners do not register them at all and the call hard-errors with `Agent type '<name>' not found. Available agents: …`.

**Apply the runtime-degradation rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` at every plugin-agent spawn site.** The ladder: try `Agent(subagent_type="geniro-claude-plugin:<agent>", ...)` first; on "not found", retry with bare `Agent(subagent_type="<agent>", ...)`; on "not found" again, fall back to `Agent(subagent_type="general-purpose", ...)` with the agent's `.md` body (frontmatter stripped) prepended to the prompt. Cache the resolved rung for the rest of the session — registration is fixed at session init. This is the agent-registration layer; it is independent of the MCP-tool degradation noted in the Optional MCP Dependencies section below.

## Safety Hooks (Active)

This plugin provides safety hooks that run automatically:
- **File protection** — blocks writes to `.env`, `*.key`, `*.pem`, lock files. Covers Edit/Write/MultiEdit/NotebookEdit AND Bash-side writes (redirection `>`/`>>`, `tee`, in-place `sed -i`, `cp`/`mv` destinations, `dd of=`) into the same protected paths; reads stay allowed. Per-pattern bypass: `write-env`, `write-git-internal`, `write-lockfile`, `write-cert-key`, `write-credentials`, `write-tfstate`, `write-vault`.
- **Git guardrails** — blocks destructive git operations (force-push, reset --hard, branch -D, clean -fd, mass-discard checkout/restore, filter-branch, update-ref -d, remote-branch deletion via `git push --delete` / colon-refspec)
- **`.geniro/` deletion guard** — blocks bulk deletion of `.geniro/` (which holds user-authored instructions, actions, workflow, _FEATURES.md, learnings, planning artifacts). Per-file `rm -f` and deep-path `rm -rf .geniro/<top>/<sub>/` remain allowed; bulk `rm -rf .geniro/` (including absolute/`$PWD`/`../`-prefixed and prefix-glob `.gen*` spellings), `rm -rf .geniro/<single-segment>`, `find .geniro -delete` (also `-exec rm` and `| xargs rm` forms), `git worktree remove`, and `git add -f` on `.geniro/` paths are blocked. The `git add -f` block exists because force-adding ignored files makes them visible in IDE Source Control panels, and a single "Discard All Changes" click then becomes a one-click data-loss vector — real incident: Cursor's SCM discard wiped `.geniro/actions/*.md` after they were force-added. The correct path for tracked content is `.gitignore` negation (e.g. `!.geniro/actions/` + `!.geniro/actions/**`), never `git add -f`.
- **Session-start restore** — `hooks/session-start-restore.sh`, wired as `SessionStart` with `matcher: "compact|resume|startup"` (Anthropic-canonical; `PostCompact` itself does not support `additionalContext`). `clear` is explicitly unmatched — user reset respected. Resolves the active T1 state.md via canonical slug match + frontmatter `branch:` fallback across all three layouts (planning task-dir / state-per-skill slug / state singleton); a state.md already in a terminal state — terminal `phase:` (`done`/`aborted`/`routed`/etc.) or terminal `status:` — is skipped during resolution, so a finished task is never surfaced as resumable and cannot shadow an in-flight task on the same branch in a later resolution tier; pre-flights `validate_state_file` and degrades gracefully if the helper is missing. Emits an `additionalContext` block-set: per-source prefix · suggested files (L4 instructions set — `global.md` / `memory.md` / `code-style.md` / per-skill — routed through `load-custom-instructions.md` MODE: refresh; CLAUDE.md / _FEATURES.md / state.md / spec.md / plan.md as direct Reads) · validation-failure recovery directive · helper-missing notice · structured non-resumable-actions warning (per-action rendering for git-push / pr-created / pr-comment-posted / pr-comment-amended / pr-review-comment-batch / git-commit / slack-notify-sent / release-tagged plus unknown-action fallback) · unresolved errors from state.md `## Errors` · pending Open Questions · persisted approvals from frontmatter `approvals: []` · **auto-archive of stale L2 entries (default ON, hash-gated + mkdir-locked for multi-tab safety)** · **verification-coverage line — the verified-fraction of live (non-deprecated) learnings, computed independently of the auto-archive threshold so it surfaces every session (default ON, opt-out via `safety.json memory.show_coverage: false`)** · memory-backend-active notice (shown in the coverage slot when a `## Memory Backend` block routes learnings to a `replace`-mode backend, so local coverage is absent) · resume protocol. systemMessage one-liner emitted on every source except cold startup with no active task (overridden when auto-archive runs OR a coverage line is present OR a memory-backend notice is present — user sees an "auto-archived: N" and/or "memory verified: N/total (P%)" and/or "memory backend active" suffix). Read-only on state.md — never writes; writes only to `.geniro/knowledge/learnings.jsonl` (auto-archive) and `.geniro/knowledge/.archive-stale.{hash,lock}`. Compaction-immune helpers (`query-learnings`, `emit-learning`, `update-semantic`, `resolve-conflicts`) take no MODE parameter; `load-custom-instructions` and `load-semantic` accept `MODE: refresh` (procedure identical to initial-load).
- **Evidence-on-completion** — Stop hook (warn-only) — scans last assistant message for completion phrases (e.g., "shipped", "all tests pass", "ready to ship", "Done!") that lack an Evidence Block; cites `skills/_shared/evidence-standard.md`. Stop hooks fire ~50-80% of the time, so this is a soft reminder layer, not enforcement. Bypass: `evidence-stop` in `.geniro/safety.json` `allow_patterns`.
- **TDD-order enforcement** — PreToolUse `Edit|Write|MultiEdit|NotebookEdit` (hard-block) — when `.geniro/state/tdd/state-<slug>.md` shows phase=RED, blocks `Edit`/`Write` on production-code files (test files still allowed). State file absence means the skill hasn't opted in to TDD, so no surprise blocks. Bypass: `tdd-order` in `.geniro/safety.json` `allow_patterns`.
- **State-helper enforcement** — PreToolUse `Edit|Write|MultiEdit|NotebookEdit` AND `Bash` (hard-block) — blocks direct writes to a canonical state path (`.geniro/state/`, `.geniro/planning/`, `.geniro/knowledge/`, `.geniro/instructions/`, `.geniro/actions/`, `.geniro/workflow/`, `.geniro/.geniro-state.json`). Covers `Edit`/`Write`/`MultiEdit`/`NotebookEdit` (via `file_path` / `notebook_path`) AND Bash-side writes (redirection `>`/`>>`, `tee`, in-place `sed -i`, `cp`/`mv` destinations, `dd of=`) into the same paths; reads stay allowed. Commands invoking the sanctioned helpers (`atomic_state_write` / `atomic_state_append`) are allowed — they write via their own mktemp + mv. Paths under `.geniro/state/tdd/` are exempt (the TDD-order hook's state file is written via its own mktemp + mv procedure, per `skills/_shared/tdd-cycle.md` §State file contract). Suggests `atomic_state_write` (or `atomic_state_append` for JSONL) per `skills/_shared/atomic-state-write.md`; a write under `.geniro/state/` that matches no canonical layout (`state/<skill>/<slug>/state.md`, the `state/setup/state.md` singleton, `state/handoff/from-<producer>-<branch>.md`, `state/tdd/state-<slug>.md`) gets an extra hint, since ad-hoc files there are invisible to the validator and session-restore. Bypass: `enforce-state-helper` in `.geniro/safety.json` `allow_patterns`.
- **Security pattern scan** — PreToolUse `Edit|Write|MultiEdit|NotebookEdit` (hard-block) — cheap regex scan of file content for high-signal security anti-patterns: `eval`/`exec`/`new Function`, `pickle.load`, `yaml.load` without SafeLoader, `subprocess shell=True` / `os.system`, `curl | sh`, TLS bypass (`verify=False` / `rejectUnauthorized: false` / `--insecure`), XSS sinks (`.innerHTML=` / `dangerouslySetInnerHTML` / `document.write`), weak hashes (`md5`/`sha1` via `createHash`/`hashlib`). Each pattern is scoped to applicable file extensions. On match: stderr message + exit 2; Claude can rewrite the edit, justify inline, or the project can add the pattern ID to `.geniro/safety.json` `allow_patterns`. Catches obvious string-level wins at edit time without an LLM-cost ambient review. Logic-level issues (authz bypass, IDOR, race conditions) are not regex-detectable — run `/geniro:review` for those. Bypass IDs: `sec-eval-exec`, `sec-pickle`, `sec-yaml-unsafe`, `sec-shell-injection`, `sec-curl-pipe-sh`, `sec-tls-bypass`, `sec-xss-sink`, `sec-weak-crypto`.
- **Gate-render enforcement** — PreToolUse `AskUserQuestion` (hard-block) — blocks a question that either references content "above" OR carries finding-gate evidence shorthand (finding IDs like `F5`/`M1b`, a `PRODUCT-DECISION` tag, convergence wording) when the current turn contains no visible assistant message, so decision gates can't fire blind. Bare severity words (HIGH/MEDIUM/LOW) are deliberately NOT triggers — too common in benign questions to hold the zero-false-positive bar. Retries the transcript read once before blocking (absorbs the transcript-flush race), and treats a harness-injected `<task-notification>` (a backgrounded agent/workflow coming to rest) as mid-turn feedback rather than a turn boundary — so a gate fired right after a background agent isn't falsely blocked when the render exists; fails open when jq or the transcript is unavailable. A block is not a user denial — write the gate render as an ordinary chat message, then re-fire the same question (canonical protocol: `skills/_shared/gate-rendering.md` §Turn-completion guard). Bypass: `gate-render` in `.geniro/safety.json` `allow_patterns`.

### Per-project allowlist for safety guardrails

Create `.geniro/safety.json` in your project to opt out of specific guardrail patterns:

```json
{
  "allow_patterns": ["force-push-with-lease", "clean-fd"]
}
```

Pattern IDs:
- **File protection** (Write/Edit): `write-env` (`.env`/`.env.*`), `write-git-internal` (`.git/*`), `write-lockfile` (pnpm-lock.yaml / package-lock.json / yarn.lock / bun.lockb / cargo.lock / Gemfile.lock / composer.lock / poetry.lock / Pipfile.lock / go.sum), `write-cert-key` (`*.pem`/`*.key`/`private-key*`), `write-credentials` (`credentials.*`/`secrets.*`), `write-tfstate`, `write-vault`
- **Git guardrails**: `force-push`, `force-push-with-lease`, `reset-hard`, `branch-delete-force`, `clean-fd`, `checkout-mass-discard`, `restore-mass-discard`, `update-ref-delete`, `filter-branch`, `push-delete` (remote-branch deletion via `git push --delete` / colon-refspec)
- **`.geniro/` deletion guard**: `rm-geniro-tree` (bulk `rm -rf .geniro/`), `rm-geniro-subdir` (`rm -rf .geniro/<top>/`), `rm-geniro-state-subdir` (`rm -rf .geniro/state/<skill>/`), `find-geniro-delete` (`find .geniro ... -delete` / `-exec rm` / `| xargs rm`), `worktree-remove-with-state` (`git worktree remove`), `git-add-force-geniro` (`git add -f` on `.geniro/` paths)
- **Evidence-on-completion**: `evidence-stop` (skip the Stop-hook completion-phrase warning)
- **TDD-order enforcement**: `tdd-order` (skip the RED-phase production-code Edit/Write block)
- **State-helper enforcement**: `enforce-state-helper` (the hard-block bypass for direct Edit/Write/MultiEdit/NotebookEdit AND Bash-side writes to `.geniro/` state paths)
- **Security pattern scan**: `sec-eval-exec`, `sec-pickle`, `sec-yaml-unsafe`, `sec-shell-injection`, `sec-curl-pipe-sh`, `sec-tls-bypass`, `sec-xss-sink`, `sec-weak-crypto` — each pattern individually opt-out-able when the project legitimately uses a pattern (e.g., a sandboxed `eval` interpreter, or a SHA-1 checksum for non-security use cases)
- **Gate-render enforcement**: `gate-render` (skip the block on "above"-referencing OR finding-shorthand-bearing questions fired with no visible assistant message in the current turn)

The allowlist is read from the nearest `.geniro/safety.json` walking up from the cwd.

## Optional MCP Dependencies

Some skills/agents unlock additional capabilities when a companion MCP server is available. They **gracefully degrade** when it isn't — install only the ones you need.

| MCP | Used by | Enables | Install |
|-----|---------|---------|---------|
| **Playwright** (`mcp__plugin_playwright_playwright__*`) | `/geniro:implement` Phase 3 Ship sub-step Pre-Ship Visual Verification | Screenshot loop at 375/768/1440, console/network sanity checks, keyboard-nav verification, smoke-test of the shipped change | Install the `playwright` marketplace plugin alongside this one. The tool prefix `plugin_playwright_playwright__*` is what Claude Code exposes when Playwright comes from a sibling plugin. If absent, the visual loop and smoke-test step are skipped automatically. |

To check what's available in your environment, look for `mcp__plugin_playwright_playwright__*` tools in the agent's tool list at runtime.

The plugin agents also carry a broad `mcp__*` grant so a project-configured **code-index** or **memory-backend** MCP (e.g. a graph/search service) is reachable from a subagent without naming the server in the plugin — see §Memory Layers for the memory-backend routing. That grant is read-only by contract: agents are instructed (via the inlined untrusted-content defense) to use MCP for read-only intelligence and never call an egress or mutating MCP tool.

## Editing plugin content — full reads, not grep

When the user asks to improve, review, or modify this plugin's skills/agents/rules, load the relevant files in FULL first by running:

```bash
scripts/dump-md.sh [path ...]   # e.g. scripts/dump-md.sh skills/implement skills/_shared
```

It prints every tracked `.md` file under the given paths (whole repo when no path) as a `===== <path> =====` header followed by the file's complete content. Do this BEFORE reaching for Grep: keyword search shows matching lines only, which misses reworded coverage of the same concept and produces false "missing" findings when auditing or extending skills. Grep stays fine for pinpointing an exact known string (an edit anchor, a cross-reference check) — not for surveying what a skill covers. Subagents doing gap analysis or skill edits get the same instruction: read full files, not grep hits.

## Testing & CI

Shell test suites live under `tests/` (one file per helper / hook). Run the whole set:

```bash
bash tests/run-all.sh
```

The runner discovers and executes every `tests/**/*.sh` suite — the `lib/` helpers, the safety hooks (including the data-loss guards `block-dangerous-git.sh` and `block-geniro-deletion.sh`), and `tests/authoring/lint-skills.sh` — and exits non-zero if any suite fails.

`tests/authoring/lint-skills.sh` mechanizes the manual greps in `.claude/rules/skill-structure.md` §Pre-commit verification. It **hard-fails** (exit non-zero) on the zero-false-positive correctness checks — non-Latin (Cyrillic) text in `skills/`/`agents/`, dangling `${CLAUDE_PLUGIN_ROOT}/<path>` file references, and unknown `subagent_type` spawn names — and **warns only** (never blocks) on the guideline checks: SKILL.md over the 500-line target, anti-rationalization tables over 15 rows, and decaying `file.md:NNN` line-number cross-references (line caps are guidelines, not limits).

`.github/workflows/ci.yml` runs `tests/run-all.sh` plus ShellCheck (error severity gating, warning severity advisory) on every pull request and on pushes to `main`. The release workflow tags its bump commit with `[skip ci]`, so CI never runs on the bot's version-bump push.

## Updating

This plugin updates automatically via the Claude Code marketplace. To manually check:
```
claude plugin update geniro-claude-plugin@geniro-claude-harness
```
