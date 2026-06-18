# Implement Skill — Reference Material

This file contains templates, examples, and detailed procedures referenced by SKILL.md. The orchestrator reads specific sections at the relevant phase — not the entire file upfront.

**Scope:** `/geniro:implement` is a 3-phase autonomous loop (Analyze → Implement → Self-review-and-Ship).

## Contents

- Phase 1: $ARGUMENTS semantic-parse table
- Phase 1: Spec discovery walk-list
- Phase 1: Subagent spawn template
- Phase 2: test-runner-agent spawn template
- Phase 2: Implement — error-handling
- Phase 3: Self-review reviewer-agent template
- Phase 3: Adversarial-tester spawn template
- Phase 3: Bounded fix loop
- Phase 3 — Ship sub-step
- Phase 3 — Adjustment Routing (Big / Medium / Small)
- Definition of Done

---

## Phase 1: $ARGUMENTS semantic-parse table

No CLI flag grammar. The orchestrator parses `$ARGUMENTS` semantically at Phase 1 entry.

| `$ARGUMENTS` shape | Mode |
|---|---|
| empty | Resume current task from `<task-dir>/state.md` if one exists; else error directing the user to provide a task description. |
| contains `continue` / `resume` (standalone word, any casing) | Resume from state.md (compaction-coupled — reads `non-resumable-actions[]` to skip side-effects already completed). |
| matches a filesystem path (rel or abs) to a `.md` file | Load as spec/plan artifact. Frontmatter validated via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`. |
| free-form description, no path match | Inline-task mode: treat `$ARGUMENTS` as a raw spec description; Phase 1 produces a minimal inline plan and proceeds. |
| ambiguous (bare slug that could be a task name OR a description) | AUQ with 2-3 disambiguation options. Persist outcome to state.md frontmatter `approvals[]` with `category: disambiguate_arguments`. |
| natural-language modifier present (`don't push`, `draft only`, `stop after review`, `with PR`, `commit only`) | Honored semantically by Phase 3 Ship sub-step (a bare `with PR`/`open PR` with no draft-vs-ready qualifier routes to the ship-mode gate rather than skipping it — see the Ship sub-step modifier table). Modifier survives in $ARGUMENTS and is consulted at relevant decision points. No CLI flag rewrite needed. |

**Workflow-integration plumbing.** Workflow files (`.geniro/workflow/*.md`) live in the primary worktree per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` (Mode A). Glob both `./.geniro/workflow/*.md` (cwd-local — uncommitted local edits win) and `<PRIMARY_ROOT>/.geniro/workflow/*.md` (primary fallback) to find all available tracker integrations. If files exist with argument-detection patterns (e.g., Linear issue IDs, GitHub URLs), apply their patterns FIRST — they may inject extra context (issue body, status transition) before the semantic-parse table above runs. Integrations are non-blocking: if a workflow's backend (e.g., MCP) is unavailable, log a warning and proceed without.

**Approvals-persistence protocol:** before firing the disambiguation AUQ, check state.md frontmatter `approvals[]` for a prior entry with `category: disambiguate_arguments` matching the current $ARGUMENTS shape. If found, use the prior `picked` value and skip the AUQ. If not found, fire AUQ → on user pick, append to `approvals[]` via `atomic_state_write` before proceeding.

---

## Phase 1: Spec discovery walk-list

When `$ARGUMENTS` does not directly carry a spec path, walk these in order and stop at the first hit:

1. `<task-dir>/spec.md` — preferred (`/geniro:plan` canonical output).
2. `<task-dir>/plan.md` — alias.
3. design-doc frontmatter detect via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md` — covers design docs that don't follow naming convention.

If none match AND $ARGUMENTS is non-empty free-form text → enter **inline-task mode**: write a brief inline plan to state.md body under `## Inline Plan` containing one-sentence goal, file list (best-effort), and approach summary. This becomes the source-of-truth for Phase 3 self-review (the `spec` field consumed by reviewer-agents).

---

## Phase 1: Subagent spawn template

Spawn `knowledge-retrieval-agent` and `codebase-explorer-agent` IN PARALLEL — one assistant response, TWO `Agent(...)` tool calls. Apply the registration-degradation ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` at every spawn site. OMIT `model=` — the frontmatter governs (codebase-explorer-agent declares `model: inherit`; knowledge-retrieval-agent declares `model: sonnet`, a mechanical-gather carve-out per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`).

### Related-task chain priming

Before spawning, apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/task-chain-context.md` (MODE: implement) to assemble the related-task chain context — the surrounding chain of work that places this task in its done-before / where-we-are / what's-next narrative. Source the tracker half from the spec frontmatter `workflow_refs[]` when present (already enriched by `/geniro:plan` on its newest spec format); when the chain's tracker fetch is stale (older than 1 hour) or absent, the helper refreshes it via MCP (fail-open). Source the milestone half from disk — when `/geniro:implement` is invoked on a `milestone-N.md`, the helper reads the sibling `milestone-*.md` files and the parent `spec.md` to place this milestone in the chain (what shipped before, what is next).

The helper returns a plain-English "TASK CHAIN CONTEXT" block. Inline it into BOTH spawn prompts via the `TASK_CHAIN_CONTEXT` slot below. Fail-open: when the helper returns empty (no tracker chain and no milestones), omit the slot from both prompts.

Read-only: `/geniro:implement` never mutates tracker / parent / sibling state from this step. Its existing status transition at Step 0c is unchanged and separate.

### Knowledge-Retrieval spawn

The orchestrator MUST have resolved `PRIMARY_ROOT` per Phase 1 entry preamble (see SKILL.md §PHASE 1) before substituting the literal `<PRIMARY_ROOT>/` token in these slots. Without that compute, the spawn template ships literal placeholder paths to the agents.

The orchestrator pre-resolves these slots and inlines them in the prompt:

| Slot | Source |
|---|---|
| `LIB_ROOT` | `${CLAUDE_PLUGIN_ROOT}/lib` — canonical plugin shell helpers |
| `KNOWLEDGE_ROOT` | `<PRIMARY_ROOT>/.geniro/knowledge` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` |
| `PLANNING_ROOT` | `<PRIMARY_ROOT>/.geniro/planning` — cross-session subset (`_FEATURES.md`, `_CODEBASE_MAP.md`, `_focus-*.md`) |
| `TASK_PLANNING_ROOT` | `$(pwd)/.geniro/planning/<task-slug>` — task-local (`spec.md`, prior `plan-*.md`) |
| `HANDOFF_DIR` | `<PRIMARY_ROOT>/.geniro/state/handoff/` |
| `TASK_DESCRIPTION` | First ~200 chars of `$ARGUMENTS` or `spec.title` |
| `INFERRED_TAGS` | Tag list inferred by the orchestrator from task description (e.g., `react,auth,bug`) |
| `TASK_CHAIN_CONTEXT` | The related-task chain block from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/task-chain-context.md`, or omitted when empty |
| `OUTPUT_PATH` | `<task-dir>/.kr-out.md` |

```
Agent(subagent_type="knowledge-retrieval-agent", description="Phase 1: Knowledge retrieval", prompt="""
LIB_ROOT: [absolute path]
KNOWLEDGE_ROOT: [absolute path]
PLANNING_ROOT: [absolute path]
TASK_PLANNING_ROOT: [absolute path]
HANDOFF_DIR: [absolute path]
TASK_DESCRIPTION: [pre-inlined]
INFERRED_TAGS: [comma-separated list]
TASK_CHAIN_CONTEXT: [pre-inlined chain block, or omit this line when empty]
OUTPUT_PATH: [absolute path under <task-dir>]

Follow the procedure in your agent file §Workflow. Write the structured
report to OUTPUT_PATH per the §Output Schema (cap ~3K chars). Do NOT mutate the
codebase or git state — read-only retrieval only.
""")
```

### Codebase-Explorer spawn

The orchestrator pre-resolves these slots and inlines them in the prompt:

| Slot | Source |
|---|---|
| `WORKTREE` | `git rev-parse --show-toplevel` |
| `SPEC_CONTENT` | Pre-inlined `spec.md` body (or `## Inline Plan` from state.md for inline-task mode) |
| `RULES_DIR` | `.claude/rules/` (absolute path under WORKTREE) |
| `SEMANTIC_MAP` | Pre-inlined `_CODEBASE_MAP.md` body (~2K tokens) |
| `TASK_CHAIN_CONTEXT` | Same related-task chain block (or omitted when empty) — gives the explorer the surrounding chain of work |
| `OUTPUT_PATH` | `<task-dir>/.ce-out.md` |

```
Agent(subagent_type="codebase-explorer-agent", description="Phase 1: Codebase exploration", prompt="""
WORKTREE: [absolute path]
SPEC_CONTENT: [pre-inlined spec.md body]
RULES_DIR: [absolute path to .claude/rules/]
SEMANTIC_MAP: [pre-inlined _CODEBASE_MAP.md body]
TASK_CHAIN_CONTEXT: [pre-inlined chain block, or omit this line when empty]
OUTPUT_PATH: [absolute path under <task-dir>]

Follow the procedure in your agent file §Workflow. Write the
structured report to OUTPUT_PATH per the §Output Schema (cap ~5K chars). Do NOT
mutate the codebase or git state — read-only reconnaissance only.

For `.claude/rules/` matching: parse YAML frontmatter `paths:` field per file;
return the LIST of relevant rule paths only — do NOT inline rule bodies. The
orchestrator JIT-loads rule bodies in Phase 2 when Edit targets match.
""")
```

### Failure handling

On missing/empty OUTPUT_PATH file OR `Agent` tool error: one silent retry. Second failure → inline-Read fallback (orchestrator Grep + Read top exemplar files and `_CODEBASE_MAP.md` rows) with `change_scope: medium` as safe default. Emit L2 `diagnosis` with `trust: retrieved`. Echo a one-line notice to user.

### Escalation signals (orchestrator-side advisory)

After reading the Codebase-Explorer report, the orchestrator scans `spec.md` for these signals and emits a one-line advisory if any match (NOT a tier override — user retains authority over `/model` selection):

| Signal | Detection grep on spec.md |
|---|---|
| New entity / migration / schema change | `\b(migration\|schema\|ALTER\|CREATE TABLE)\b` |
| Auth, permissions, or role boundary | `\b(auth\|RBAC\|permission\|role\|JWT\|OAuth\|middleware)\b` (case-insensitive) |
| 3+ modules coordinated | spec.md `## Touchpoints` section lists ≥3 distinct top-level modules |
| New external integration | `\b(API\|SDK\|MCP\|webhook\|integration)\b` AND filename like `.env\|secrets\|credentials` |
| Async / queue / background job | `\b(async\|queue\|worker\|scheduler\|cron\|background)\b` |

When ≥1 signal matches, emit: `"Spec touches <matched signals> — consider running on Opus tier if not already (current: <tier>)."` Log a `## Tool log` entry `escalation_signals: [...]`.

---

## Phase 2: test-runner-agent spawn template

Spawn `test-runner-agent` ONCE at end of Phase 2 (after all TodoWrite todos completed), and ONCE per fix-loop retry. OMIT `model=` — test-runner-agent declares `model: sonnet` in frontmatter (mechanical run-and-parse carve-out per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`). Apply the registration-degradation ladder.

The orchestrator pre-resolves these slots:

| Slot | Source |
|---|---|
| `WORKTREE` | `git rev-parse --show-toplevel` |
| `TEST_COMMAND` | Project's test command from CLAUDE.md "Essential Commands" (e.g., `pnpm --filter api test:unit`, `pytest tests/`, `go test ./...`) |
| `CHANGED_FILES` | List of paths Edited in Phase 2 (newline-separated) |
| `OUTPUT_PATH` | `<task-dir>/.tr-out.md` (overwritten per retry) |
| `MAX_FAILURES_REPORTED` | `15` (default) |

```
Agent(subagent_type="test-runner-agent", description="Phase 2: Run tests", prompt="""
WORKTREE: [absolute path]
TEST_COMMAND: [exact command string]
CHANGED_FILES: [newline-separated paths]
OUTPUT_PATH: [absolute path under <task-dir>]
MAX_FAILURES_REPORTED: 15

Follow the procedure in your agent file §Workflow. Run TEST_COMMAND ONCE,
save full stdout+stderr to a /tmp log via tee, parse the saved log (Grep), and
write the structured report to OUTPUT_PATH per the §Output Schema. Verdict ∈
{ALL_GREEN, HAS_FAILURES, INFRA_ERROR}. Do NOT edit source code, do NOT mutate
git, do NOT re-run the suite.
""")
```

---

## Phase 2: Implement — error-handling

The Phase 2 fix loop uses the structured `test-runner-agent` output (NOT raw stdout):

```
retry = 1
while retry ≤ 3:
  read <task-dir>/.tr-out.md
  if Verdict == ALL_GREEN → run ALL section-9 verify: commands (spec-driven runs only);
                            on any verify failure/refusal → Step 6 escalation (one digest naming every failed/refused criterion)
                            else → exit Phase 2 → Phase 3
  if Verdict == INFRA_ERROR → escalate AUQ immediately (don't retry blind)
  inspect the structured Failures list
  edit code (or test) to address top-priority failures
  re-spawn test-runner-agent (overwrites .tr-out.md)
  retry += 1
else:
  escalate via AskUserQuestion (debug-handoff / accept-failure / abort)
```

**Token cost.** Raw test stdout (often tens of thousands of tokens) never enters the orchestrator's main context — only the compact structured report does, so the fix loop stays cheap.

**Evidence requirement.** The Verdict block from `.tr-out.md` (Command / Exit code / Summary) attaches as the Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. Stop-hook scans for forbidden phrases (`"all tests pass"`, `"validation complete"`, `"ready to ship"`) without an attached Evidence Block.

**Tool log persistence.** Every `test-runner-agent` spawn outcome (Verdict + log-file path) is persisted to state.md `## Tool log` via `atomic_state_write`. Routine Read/Edit/Bash on local files do NOT need logging.

**Termination-reason on escalate-abort.** If the user picks "abort" at retry exhaust, write a `## Termination reason` body line: `repeated-failure: phase-2 retry-limit (<N> failing Phase 2 checks)` — source-neutral, since the escalation covers both a failing test suite AND a failing/refused spec `verify:` acceptance check.

**Phase 2 check-failure escalation digest (render before the escalation AUQ).** When the Phase 2 escalation fires, render a failure digest to chat as its own message per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering, then fire the lean AUQ. The escalation has two failure sources, and the digest + the lean AUQ's `header:` MUST name the right one — a `verify:`-command failure rendered under a "Test failure" frame with test-specific options mislabels what failed and what the user is deciding:

| Failure source | When | AUQ `header:` | Digest framing |
|---|---|---|---|
| Project test suite | retry exhaust, `INFRA_ERROR`, or an early not-converging trigger on the suite | `"Test failure"` | "the date-parsing tests are still failing" |
| Spec acceptance check (`verify:` command) | a section-9 criterion's `verify:` command returned `HAS_FAILURES` / `INFRA_ERROR` (see "Per-criterion `verify:` commands" below) | `"Acceptance check failed"` | "the acceptance check the spec attached (its `verify:` command) failed" |

A run that hits BOTH sources (a `verify:` failure after a green suite) uses the neutral header `"Checks failed"` (plain-English, no phase-number — the both-source case still has to pass the fresh-user test) and the digest names both. The three options are unchanged across all three headers — hand off to a debug investigation / accept as a documented limitation / stop — and stay accurate for either source.

The digest carries:

- `### 🧭 Decision needed:` with a plain-English one-line title — name the source (e.g. "3 fix attempts spent — the date-parsing tests are still failing", or "The spec's acceptance check (its `verify:` command) failed").
- `**In one sentence:**` what this decision settles — hand the failure to a debug investigation, accept it as a documented limitation, or stop.
- A conversational lead: what failed in plain English. For a test-suite failure, which behavior the failing tests check and what the fix attempts changed; for a `verify:`-command failure, which spec criterion the command checks and that it ran once and did not pass (acceptance checks are single-shot, not iterated). For an early trigger, state the plain-English stall reason (never the raw signal name).
- `**Why it matters:**` why this blocks the phase — for a test-suite failure, the self-review that follows assumes green tests, so proceeding means the review reads code the suite says is broken; for a `verify:` failure, the spec's own acceptance criterion is unmet, so the run does not yet satisfy the spec's Done Condition (evidence: the failing command's Command / Exit code / Summary block, or the test-runner report's same block).
- The failing items as a `☐` checklist — the failing-test names (test-suite source) OR the failed `verify:` criteria named by their plain-English intent (acceptance-check source), the test-finding shape from the same contract's §Finding-type visual map — capped at the reported failures.

Build the test-suite digest from the structured `.tr-out.md` report, never raw test stdout (the token-cost rule above); build the `verify:`-command digest from the command's captured Command / Exit code / Summary. The lean AUQ that follows carries only the title, the source-appropriate header above, and the three options from the SKILL.md Phase 2 escalation step.

### Per-criterion `verify:` commands

A spec authored by /geniro:plan may attach an optional `verify: <command>` line to a section 9 (Validation) criterion (the spec field /geniro:plan authors; its read-only doctrine is canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md` §4). It is the acceptance check for that one criterion — distinct from the project-wide TEST_COMMAND that `test-runner-agent` runs. After the end-of-phase suite reaches `ALL_GREEN`, the orchestrator runs each `verify:` command once and attaches the result as evidence.

**Cardinality — run ALL commands, then escalate ONCE.** Run every section-9 `verify:` command and collect the failed/refused set BEFORE escalating, then fire one Step 6 escalation whose `☐` checklist names every failed/refused criterion. The Step 6 escalation fires a blocking AUQ whose options all transition the phase, so it cannot return mid-loop to iterate the rest — a per-criterion "escalate then continue the loop" shape would leave a spec with two failing criteria undefined. Collect-all-then-escalate-once guarantees the user sees the complete failure set in one decision.

```
failed_or_refused = []                                          # collect across ALL criteria first
for each section-9 criterion carrying a `verify:` line:         # spec-driven runs only
  if command tokens contain a ship / deploy / external-state-mutation verb:   # side-effect screen — see below
    add {criterion, reason: "refused — side-effect"} to failed_or_refused     # never run it, never silently skip it
    continue                                                    # skip executing THIS command, keep collecting
  result = Bash(<verify command>)                               # orchestrator's own Bash, NOT test-runner-agent
  classify result on the SAME verdict taxonomy:
    exit 0                              → ALL_GREEN  (record + continue)
    non-zero assertion-style exit       → HAS_FAILURES → add {criterion, reason} to failed_or_refused
    connection-refused / server-down    → INFRA_ERROR  → add {criterion, reason} to failed_or_refused
    blocked by a safety PreToolUse hook → INFRA_ERROR  → add {criterion, reason} to failed_or_refused  (never a silent skip — surface the block)

if failed_or_refused is non-empty:
  fire ONE Phase 2 check-failure escalation digest above (the SAME message-first AUQ) using its
  acceptance-check header/framing, with EVERY entry in failed_or_refused named in the `☐` checklist
else:
  exit Phase 2 → Phase 3
```

**Side-effect screen — refuse to auto-run a ship / deploy `verify:` command.** Before executing each `verify:` command, inspect its tokens. If the command contains an external-state-mutation / ship / deploy verb, do NOT run it — skip executing THIS command and add it to the collected failed/refused set (keep collecting the rest), then it surfaces in the single Step 6 escalation with the plain-English reason: "the spec's acceptance check would push/ship/deploy, which /geniro:implement won't run on its own before the ship gate — run it yourself or remove it from the spec." Frame it exactly like the `INFRA_ERROR` path (the acceptance check could not run; the user stays the ship decider) — the three options are unchanged. Never silently skip it (a quiet skip hides that an acceptance check was refused) and never execute it (executing is the violation).

This screen is needed because a `verify:` command runs at the Phase 2 green exit — BEFORE self-review and BEFORE the commit-grade Ship AUQ. The safety PreToolUse hooks block force-push / branch-delete / `.geniro/` deletion, but they do NOT block a plain `git push`, `gh pr create`, or a `./deploy.sh` invocation — so a spec carrying `verify: gh pr create --fill` (or a deploy script) would otherwise ship the change with no Ship AUQ and no record of the irreversible action. That violates Loop-Invariant #3 (never ship without the gate). The screen is a doctrine guard, not a sandbox — a high-signal mutation-verb check on the command string, not an exhaustive side-effect analyzer. Match these verb families (case-insensitive, whole-token):

- **Source publish:** `git push` (any form, including `git push --delete`), `gh pr create`, `gh pr merge`, `git commit`.
- **Deploy / release:** `deploy`, `release`, `publish`, `helm install`, `helm upgrade`, plus deploy-CLI invocations (`kubectl apply`, `terraform apply`, `serverless deploy`, `vercel --prod`, `netlify deploy`, `fly deploy`) and any project deploy/release script named in CLAUDE.md.

A read-only acceptance check (`pnpm test`, `curl -fsS localhost:3000/healthz`, `ruff check`, `tsc --noEmit`, a read-query) carries none of these verbs and runs normally.


- **Orchestrator runs it, not `test-runner-agent`.** The runner agent's single-command leaf contract is a deliberate safety boundary — its anti-rationalization forbids it orchestrating multiple commands. Phase 2 already grants the orchestrator Bash, so it runs the `verify:` strings directly. No agent-report schema change, so no lockstep cost on the agent side.
- **Bounded single-shot.** Run each command once and report — not an iterate-to-green optimizer. The existing 3-retry fix loop already bounds convergence; a `verify:` failure surfaces to the user, it does not silently re-edit toward green.
- **A failing `verify:` surfaces, never auto-resolves.** Feed it into the same Phase 2 check-failure escalation digest under its acceptance-check header (`"Acceptance check failed"`, or `"Checks failed"` when the suite also failed) — name the failed criterion's command in plain English, e.g. "the contract-test acceptance check the spec attached is still failing"; the user stays the ship decider. A safety hook blocking the command is an `INFRA_ERROR`, never a quiet skip — the user must see that the acceptance check could not run. A command refused by the side-effect screen above routes through the same escalation with its own plain-English reason — never silently skipped, never executed.
- **Spec-driven only.** The inline-task fallback (no spec → no section 9 `verify:`) has nothing to run and skips this step cleanly. `verify:` is a body-level field, not frontmatter, so it is independent of `geniro_schema_version` (m5-v1 / m5-v2 / m5-v3).
- **Evidence.** Attach each command's Command / Exit code / Summary as an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`, alongside the suite Verdict, and persist the outcome to state.md `## Tool log` via `atomic_state_write`.

---

## Phase 3: Self-review reviewer-agent template

Spawn reviewer-agents in parallel — one call per dimension, all `Agent(...)` tool uses in the SAME assistant response. Each uses `subagent_type: "reviewer-agent"`. Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` registration-degradation ladder at every spawn site. OMIT `model=` (reviewer-agent declares `model: inherit`).

```
Agent(subagent_type="reviewer-agent", description="Self-review: <dim>", prompt="""
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
DIMENSION: bugs | security | architecture | tests | code-quality
CRITERIA (pre-inlined): [content of corresponding criteria file from ${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/ — see the reviewer dimensions table below]
CHANGED FILES (with full contents, pre-inlined): [list each file path followed by its current content]
DIFF CONTEXT: [paste `git diff <base>...HEAD` output where <base> resolves per ${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md rule 3]
SPEC CONTEXT: [pre-inline spec.md OR state.md ## Inline Plan section]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
PRIOR-ROUND FINDINGS: [paste prior-round CRITICAL/HIGH per agents/reviewer-agent.md §Step 1.7; first round: `none — first review`]

Review ONLY for [dimension]. Tag findings [SEVERITY] [NEW|PRE-EXISTING] per the output contract in agents/reviewer-agent.md §Output Format.

Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs.
""")
```

### The reviewer dimensions

| Dimension | Criteria file | Focus |
|-----------|---------------|-------|
| `bugs` | `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/bugs-criteria.md` | Logic errors, null/undefined, off-by-one, race conditions, broken invariants |
| `security` | `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/security-criteria.md` | Injection, auth/authz, secret handling, untrusted-input flows, OWASP-top-10 |
| `architecture` | `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/architecture-criteria.md` | Layering, coupling, abstractions, dead code, duplication, naming, file placement. **Also covers docs-staleness**: explicit check for README / architecture-doc / contributing-guide references to patterns or files renamed in Phase 2. **Also covers spec-compliance**: explicit check that the Phase 2 diff matches spec.md scope — no unspec'd files touched, no spec'd requirements unaddressed. **Also covers parallel-path symmetry (mirror-gap)** per architecture-criteria.md §1.6: when the diff adds a guard / replacement / cleanup on one path, verify every sibling path sharing the invariant got the same treatment. |
| `tests` | `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/tests-criteria.md` | Coverage of changed lines, edge cases, F→P invariant, brittle assertions, missing negative cases. **Pre-condition:** tests are green per Phase 2; this dim NEVER sees failing tests. |
| `code-quality` | `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/optimizations-criteria.md` + `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/guidelines-criteria.md` + `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/conventions-criteria.md` | Idiomatic style, readability, comments noise, premature abstractions, simplification opportunities. |

**Code-style pre-inline slot (code-quality + architecture reviewers only):** if the Phase 1 / Phase 3-entry L4 loader echoed `Loaded code-style.md …`, pre-inline that content under a `## Code-style instructions` header per the reviewer-agent contract. If the loader echoed `No code-style.md found — skipping.`, omit the slot. Bugs / security / tests reviewers do NOT get the slot (code-style is orthogonal).

**ACI — reviewer tool surface.** Reviewer-agents are pure-compute on the local diff: Read / Grep / Glob / Bash (read-only) only. Edit / Write / Agent / mutating Bash / external network are blocked. Enforcement: `agents/reviewer-agent.md` frontmatter `tools:` whitelist. Prompt-level reinforcement of "read-only" is a fallback layer.

**Parallel invocation:** all 5 (or fewer, on round N+1) spawns happen in ONE assistant response — multiple `Agent(...)` tool uses in the same message. Serial invocation doubles wall-time and the spec's design intent is parallelism.

### Custom reviewer dimensions (`.geniro/instructions/review-extra/`)

Round 1 only — before issuing the 5 built-in spawns, first resolve `PRIMARY_ROOT` by running the Mode A snippet from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` via Bash (the helper's Step 1 dual-globs `.geniro/instructions/review-extra/*.md` against cwd AND `<PRIMARY_ROOT>/.geniro/instructions/review-extra/*.md`, so in a linked worktree where `.geniro/instructions/` is gitignored and does not propagate on `git worktree add`, the main-worktree fallback is the only path that finds user-authored review-extra files), then apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` to discover user-authored `review-extra/<slug>.md` files. The helper returns a list of spawn-specs (slug, dimension-label `custom:<slug>`, model, criteria-content, severity-default, source-path) after applying its `paths:` filter against the changed-files list and enforcing the ≤10 cap. Append one `Agent(subagent_type="reviewer-agent",...)` call per spec to the SAME parallel batch as the 5 built-ins (one assistant turn, one parallel batch — same rule as `/geniro:review` Phase llm-spawn and `/geniro:refactor` Phase verify per `_shared/load-custom-reviewers.md` §How consumers use the spawn-specs).

Round N+1: re-fire a custom reviewer only if its prior round flagged a CRITICAL or HIGH finding (mirrors the failing-dim rule for built-ins). The custom reviewer's spawn-spec list is recomputed only on round 1; round N+1 reuses the round-1 spec cache.

If `.geniro/instructions/review-extra/` does not exist OR the glob returns zero matches after path filtering, this section is a silent no-op — the round proceeds with the 5 built-ins.

---

## Phase 3: Adversarial-tester spawn template

Phase 3 Round 1 also spawns ONE `adversarial-tester-agent` in the same parallel batch as the reviewers (adversarial-tester adds one more spawn when included). The adversarial-tester authors F→P-verified failing tests against the diff and writes them to the project's test directory. SKIPPED on either of two conditions:

- Codebase-Explorer report `change_scope: trivial`, OR
- `--no-adversarial` modifier present in `$ARGUMENTS`.

Apply the registration-degradation ladder. OMIT `model=` (adversarial-tester-agent declares `model: inherit`).

The orchestrator pre-resolves these slots:

| Slot | Source |
|---|---|
| `WORKTREE` | `git rev-parse --show-toplevel` |
| `BRANCH` | `git branch --show-current` |
| `DIFF` | `git diff <base>...HEAD` where `<base>` resolves per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` rule 3 |
| `CHANGED_FILES` | Newline-separated list of paths in DIFF |
| `TEST_DIR_HINT` | Project test directory pattern from CLAUDE.md "Essential Commands" (e.g., `tests/`, `__tests__/`, `*.test.ts` co-located) |
| `TEST_FRAMEWORK` | Detected from package.json / pyproject.toml / Cargo.toml (e.g., `vitest`, `jest`, `pytest`, `go test`) |
| `TESTS_CRITERIA` | Pre-inlined `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/tests-criteria.md` body |
| `PRIOR_REVIEW_FINDINGS` | Round 1: `none — first round`. Round 2+: CRITICAL/HIGH findings from Round N-1 reviewers (pre-inlined) |
| `OUTPUT_PATH` | `<task-dir>/.adversarial-out.md` |

```
Agent(subagent_type="adversarial-tester-agent", description="Phase 3: Adversarial edge-case hunt", prompt="""
WORKTREE: [absolute path]
BRANCH: [current branch]
DIFF: [full git diff body, pre-inlined]
CHANGED_FILES: [newline-separated paths]
TEST_DIR_HINT: [project test directory pattern]
TEST_FRAMEWORK: [detected framework]
TESTS_CRITERIA: [pre-inlined tests-criteria.md body]
PRIOR_REVIEW_FINDINGS: [Round 1: 'none — first round'; Round 2+: CRITICAL/HIGH from prior round]
OUTPUT_PATH: [absolute path under <task-dir>]

Follow the procedure in your agent file. Generate edge-case hypotheses against
the diff. Author F→P-verified failing tests (RED today) for confirmed bugs only
— each test must reproduce the bug under the current code and would pass once
the bug is fixed. Write the structured findings report to OUTPUT_PATH per the
§Output Format. Authored test files land under TEST_DIR_HINT — they become
part of the commit if Phase 3 ships clean.

Critical constraints (enforced by agent frontmatter tools whitelist):
- No production-source edits — test files only.
- No git mutation.
- No destructive Bash.
- No subagent spawning (leaf agent).

Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs.
""")
```

### Round 2+ adversarial behavior

- If Round 1 adversarial returned non-empty authored tests AND any test still fails after Round 1 fixes: re-spawn at Round 2 with PRIOR_REVIEW_FINDINGS updated.
- If all adversarial tests now pass: drop adversarial from Round 2+ (mirrors the "round N+1 ≠ all 5" rule for reviewers).
- If Round 1 adversarial returned zero authored tests (clean adversarial result): drop adversarial from Round 2+ unconditionally.

### Why no user-approval AUQ before this spawn

`/geniro:review` gates adversarial-tester spawns behind a user-approval AUQ because its contract is read-only reporter — spawning a test author is a scope expansion past contract. `/geniro:implement` is already authorized to mutate code (Phase 2 IS the mutation phase). Phase 3 adversarial test authoring is symmetric to Phase 2 code authoring, NOT a new authority surface. The spec.md approval upstream (when one exists) covers it. The scope-tier check (`change_scope: trivial` → skip) IS the mechanical gate. Use `--no-adversarial` modifier in `$ARGUMENTS` for explicit per-run opt-out.

---

## Phase 3: Bounded fix loop

```
round = 1
while round ≤ 3:
  spawn this round's agents IN PARALLEL (one assistant response):
    round 1: reviewer-agents + 1 adversarial-tester (unless skipped) + N custom reviewers
    round N+1: only dims that flagged in round N + adversarial-tester if its
               Round-N CRITICAL/HIGH remain unresolved OR any authored test still fails

  collect findings (reviewer dim outputs + adversarial-tester findings +
                    list of authored failing tests on disk)

  if no findings AND no authored adversarial tests THAT STILL FAIL:
    break  # exit to Phase 3 Ship sub-step

  apply fixes inline (single Edit-driven sub-loop, NO further agent spawns)
  re-spawn test-runner-agent; if Verdict != ALL_GREEN, rollback to Phase 2
  round += 1
else:
  # round 4 would start — DO NOT enter
  escalate via AskUserQuestion
```

**Round N+1 only re-spawns failing dimensions and the adversarial-tester (conditionally).** Dimensions that passed round N are NOT re-spawned — bounds cost and avoids re-litigating clean code. Custom reviewer specs are computed once at Round 1 entry; round N+1 reuses the cache.

**Adversarial-tester treated as the 6th dimension for fix purposes:**
- Each authored failing test counts as a HIGH finding.
- After applying fixes, the next test-runner-agent invocation reports whether the adversarial tests now pass.
- If they pass, the adversarial dim is "clean" for round N+1 (drop from re-spawn).
- Authored test files STAY on disk through Ship — they become part of the commit.

**Escalation at exhaust.** When the loop hits round 3 with unresolved findings:

1. Do NOT silently push or claim completion.
2. **Render the unresolved findings to chat first** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering — a separate, already-emitted chat message, so the user decides from explained findings rather than reviewer shorthand. With ≥2 unresolved findings, open the message with the decision-queue progress tracker (`✔` decided · `●` deciding now · `○` ahead — one stop per finding with a short plain-English tag). Each finding gets the visual-form block: the `### 🧭 Decision needed:` title, the `**In one sentence:**` opener, a conversational lead expanding what the code does and what the concern is, `**Why it matters:**` with its evidence cite, and a visual per the same contract's §Finding-type visual map. The per-dimension findings summary lives in this render — never inside the question.
3. Then fire the lean `AskUserQuestion` (header: `"Resolve findings"`) with these options:
   - **A) Hand off to /geniro:debug** — state.md transitions to `phase: debug-handoff` (terminal; run §Cleanup's transient cleanup first). Caller resumes via `/geniro:debug` using state.md as a T2 handoff.
   - **B) Accept findings and proceed to ship** — state.md adds `## Accepted Findings` body block recording the decision. Transitions to `phase: ship`. The architecture reviewer in future runs sees the accepted-findings list and may flag scope concerns.
   - **C) Abort** — state.md transitions to `phase: aborted` (terminal; run §Cleanup's transient cleanup first). Work uncommitted on disk for manual takeover.

   The Explain-further reading-aid option and the pre-fire scrub arrive via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Single-finding gate — apply that section; don't restate it here.
4. State.md records `## Termination reason` body line on aborted/handoff: `repeated-failure: phase-3 review-round-limit (<N> unresolved findings)`.

The Always-WAIT contract applies: empty `AskUserQuestion` answer = upstream bug, fall back to plain text and re-ask. NEVER auto-default to any option.

---

## Phase 3: Test-quality gate

After the bounded fix loop converges (clean exit or accepted findings), and before the Ship sub-step, run the test-quality gate when this run authored or changed test files — full contract in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/test-quality-gate.md`. It surfaces the fresh `tests`-reviewer audit of the new tests (claimed-vs-asserted scope, spec-coverage traceability, redundancy among new tests, weak assertions) as a visible decision: a clean audit records a one-line ship-report confirmation and asks nothing; open findings render message-first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §"Message-first rendering", then a lean AskUserQuestion (header: `Test quality`) offers tighten-all / pick / ship-as-is. No new agent spawn — the gate consumes the tests-dimension output already collected in the fix loop. Advisory and fail-open: it never blocks Ship and never overrides the Ship-mode AUQ.

---

## Phase 3 — Ship sub-step

### Pre-Ship Visual Verification

Runs only when BOTH conditions hold: (a) the Phase 2 changed-files list contains at least one file matching the UI-file detection rule (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` §UI-file detection rule), AND (b) Playwright MCP is available — check that `mcp__plugin_playwright_playwright__browser_navigate` is in your tool list. If Playwright MCP is NOT available, skip this entire section and note in the ship report: "Pre-Ship Visual Verification skipped — Playwright MCP not installed."

When both conditions hold, the verification is mandatory: an unreachable page — auth wall, feature flag, no running dev server, or cost concern — does NOT authorize the orchestrator to skip it silently. Surface the obstacle to the user through the step-1 dev-server choice ("Skip verification" / "Retry" / "Enter URL manually") and let the user, not a unilateral cost judgment, decide. Prompt via a STANDALONE `AskUserQuestion` with header "Smoke-test" as the ONLY question in that call — never batch it with the ship-mode AUQ. If the user picks "Yes — walk through it", execute this sequence:

1. **Detect target URL.** Probe dev-server ports in order — 3000 (Next.js), 5173 (Vite), 8080 (generic), 4321 (Astro), 4200 (Angular) — via `curl -s -o /dev/null -w "%{http_code}" http://localhost:PORT`. On the first 200, fetch `/` and check the response `<title>` or a known marker matches the project's `package.json` `name`; if uncertain, `AskUserQuestion` "Detected server on :PORT — is this the project under test?" before navigating. If no port responds, walk up from the primary changed UI file to the nearest `package.json` containing a `dev`/`start`/`serve` script (monorepo layouts: `apps/<name>/package.json`, `packages/<name>/package.json`). Choose package manager by lockfile (`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `bun.lockb` → bun, else npm). Run with `run_in_background: true`, record the PID, poll `GET /` until 200 or 30s timeout. On timeout, ask the user "Skip verification" / "Retry" / "Enter URL manually".

2. **Infer the target route.** Map the primary changed UI file to a URL path: `app/<segment>/page.tsx` → `/<segment>`, `pages/<name>.tsx` → `/<name>`, `src/routes/<name>/+page.svelte` → `/<name>`. Leaf component (e.g., `components/Button.tsx`) → fall back to `/` and ask the user where it renders. Navigate with `mcp__plugin_playwright_playwright__browser_navigate`. If the navigated page is a login / auth-gate page, or the inferred route returns 4xx or redirects away from the target (a feature-flag or permission wall), do NOT snapshot and proceed against the gated page — fire the same "Skip verification" / "Retry" / "Enter URL manually" `AskUserQuestion` so the user, not a unilateral skip, decides.

3. **Baseline snapshot.** Call `mcp__plugin_playwright_playwright__browser_snapshot` to capture the accessibility tree with element refs. Every subsequent interaction (`browser_click`, `browser_type`, `browser_fill_form`) requires a `ref` from this snapshot.

4. **Console + network sanity check.** Call `mcp__plugin_playwright_playwright__browser_console_messages` — treat any `error`-level entry as a failure worth reporting. Call `mcp__plugin_playwright_playwright__browser_network_requests` — flag same-origin 4xx/5xx responses. Re-run after step 5 and step 6.

5. **Targeted interaction.** Using refs from step 3, perform 1-3 actions that exercise the specific behavior changed in this run. Cap at 5 total interactions. Re-snapshot after each to get fresh refs.

6. **Responsive sweep** — only when the diff includes any `.css`/`.scss`/`.sass`/`.less`/`.styled.*` file, OR a JSX/TSX hunk touching `className`, `style`, or a CSS-module import. Call `mcp__plugin_playwright_playwright__browser_resize` at the three breakpoints `{width: 375, height: 667}` (mobile), then `{width: 768, height: 1024}` (tablet), then `{width: 1440, height: 900}` (desktop). Snapshot each. Skip entirely for pure logic changes.

7. **Visual record.** Final `mcp__plugin_playwright_playwright__browser_take_screenshot` with `fullPage: true`, saved under `<task-dir>/playwright-verify.png`. This is the artifact — do NOT claim a pixel-diff against a prior state (no baseline image exists).

8. **Cleanup.** If step 1 spawned a dev server (PID recorded), send `kill -TERM <pid>`; if still alive after 3s, escalate with `kill -KILL <pid>`. NEVER kill servers the user had running before verification — only clean up what this step spawned.

**Reporting:** summarize in 3-5 lines — interaction result, console/network status, responsive issues (if swept), screenshot path. If issues were found, render them to chat first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering — the issue list as a mini-table (risk · symptom you'd see · severity, the risk-finding shape from the same contract's §Finding-type visual map), each issue described in plain English with the screenshot it appears in referenced by path — then fire the lean `AskUserQuestion` with options: "Fix and re-verify" (route through Adjustment Routing Small tweak path below — this section re-fires after the next clean review if UI files remain in the diff), "Ship anyway with noted issues" (append to state.md `## Visual Verification Notes` and proceed to ship-mode AUQ), or "Abort" (`phase: aborted` terminal; run §Cleanup's transient cleanup first).

---

### Commit + Push + PR

**Step 2 — Commit.** Before staging, run `git branch --show-current` and verify the working tree is on the branch this run targeted (the Phase-1 Step-0 captured `CURRENT_BRANCH` / state.md `branch:` field). The session-start / state-snapshot branch field can go stale across compaction or an intervening branch switch — trust the live command, not the snapshot. On a mismatch, do NOT `git add` or `git commit`; fire an `AskUserQuestion` (header: "Branch check", question: "The working tree is on branch `<live>` but this run targeted `<expected>` — committing here would land the change on the wrong branch. How do you want to proceed?", options: "Move my commit to `<expected>` first" / "Commit on `<live>` anyway" / "Stop — let me sort the branch out"). Once the branch is confirmed, stage only this run's CHANGED_FILES set by name (`git add <paths>`, never `-A`/`.`). Provenance guard: diff `git status --porcelain` against CHANGED_FILES; any production file modified outside that set was authored by something other than this run — fire an `AskUserQuestion` (header: "Unexpected changes", options: "Include them — I authored them elsewhere" / "Exclude — commit only my files" / "Pause and review") rather than silently folding them into this run's commit. Then `git commit` with conventional message (e.g., `feat(auth): add OAuth login [ENG-123]`). Task ID inferred from spec.md / state.md metadata. If a workflow file specifies commit-message format (e.g., appending issue ID), follow that format.

**Step 3 — Ship-mode AUQ.** Pushing a private feature branch that has no open PR is draft-grade (it becomes visible on remote but carries no review weight); PR creation is commit-grade. The AUQ gates the PR-creation decision. Two cases make a plain push itself commit-grade, so the "Just push (no PR)" path must surface an explicit confirm rather than auto-approving: (1) the target branch is the repository's default branch or a shared/protected branch (resolve the default via `git symbolic-ref refs/remotes/origin/HEAD`; if that errors — origin/HEAD unset, common in CI shallow clones — fall back to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` rule 3, which resolves the default from local `main`/`master`; or teammates are actively committing to it) — it lands on the shared line with no PR gate; (2) the feature branch already has an open PR (`gh pr view --json state --jq .state` returns `OPEN`) AND this run was entered via a /geniro:review or /geniro:debug handoff — the push updates a live PR (CI re-runs, reviewers see the new commits) and the user's only approval was the upstream "apply the findings" pick, which authorizes editing, not shipping. In both cases, do not widen an upstream "implement the fixes" approval to authorize the push.

**Done-Condition annotation (spec-driven runs).** Before building the AUQ, on a run that resolved a real spec.md, parse the spec's section 11 (Done Condition) and apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/done-condition-check.md`. For each clause that is machine-checkable (matches the validator's stopping-condition ontology) AND affirmatively unsatisfied against the evidence the helper maps, prepend one plain-English line to the AUQ's question text so the user decides with their own completion criterion in view — e.g. "The spec's done-condition lists 'PR approved' — that's not true yet. Ship anyway?". This is advisory and skip-when-clean: when every machine-checkable clause is satisfied (or section 11 carries only free-text clauses), add nothing and proceed silently — the gate never fires with nothing to decide, mirroring the spec fact-check's restraint. Un-parseable / free-text clauses stay human-eyeball-only — never auto-graded, the guard against false-nags. The annotation rides the existing Ship AUQ's question text and obeys the caller-constraints canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/done-condition-check.md` §"What the caller does with the result" — it can only open the gate with more context, never alter the option-label allowlist or the draft-vs-commit-grade push classification, and never read as ship authorization. This is the ship-time clause-grader to the static diff-check the `architecture`/spec-compliance reviewer dimension runs in Phase 3; both read section 11. Stack any Done-Condition lines with the `## Accepted Failures` / `## Accepted Findings` disclosure below — both feed the same question text.

Use `AskUserQuestion` (header: `"Ship mode"`). These three option labels are a canonical allowlist — present them verbatim in the AUQ; never paraphrase, merge, or collapse them (e.g., never combine "Open draft PR (Recommended)" and "Open PR" into a single "open PR" / "Commit + push + open PR" label). "Open draft PR (Recommended)" must always appear as a distinct selectable option so the safe default is surfaced. (Mirrors the canonical-option-allowlist rule in /geniro:review's action gate.)

- **Label:** `"Open draft PR (Recommended)"` / **Description:** `"git push then gh pr create --draft. Safest default — lets you review before marking ready."`
- **Label:** `"Open PR"` / **Description:** `"git push then gh pr create (ready-for-review). Appends task ID to PR title."`
- **Label:** `"Just push (no PR)"` / **Description:** `"git push origin <branch>. No PR created. On your own feature branch with no open PR this is low-stakes; on a shared or default branch — or a feature branch that already has an open PR — the push is immediately visible (reviewers and CI see the new commits), so you'll be asked to confirm first."`

**Disclose overridden gates.** Before firing this AUQ, check state.md for a `## Accepted Failures` block (Phase 2 test-gate escalation) or `## Accepted Findings` block (Phase 3 review escalation). If either is present, the working tree is NOT "fully validated" — prepend a one-line disclosure to the AUQ question text: "Note: N item(s) were accepted as known limitations (<one-line summary>) and remain unresolved. Ship anyway?" Never frame the ship decision as fully validated when a gate was overridden. The disclosure also covers failures the orchestrator believes are pre-existing or flaky — these are NOT silently exempt from the gate. A RED required suite at ship time always requires the `## Accepted Failures` block + the accept-failures acknowledgement path (with any baseline-proof evidence summarized in the disclosure); the orchestrator never treats self-classified "flake" failures as already-validated.

**Spec-staleness advisory (spec-driven runs).** Before firing this AUQ, check whether a mid-run gate (an `AskUserQuestion` during Phase 2 or Phase 3) approved a material deviation from the spec's locked approach — a different storage shape, data model, algorithm, or scope than the spec's section 4 (Approach) / section 6 (Steps) describe. This is orchestrator judgment and skip-when-clean, matching the Done-Condition annotation's restraint: if the implementation followed the spec's approach, add nothing and proceed silently — the gate never fires with nothing to decide. When a deviation was approved, the saved spec.md now describes the abandoned approach while the shipped code does not — prepend one plain-English line to the AUQ's question text so the user sees the divergence before shipping: "The approved <deviation> differs from the spec's locked approach (<what the spec said>) — the saved spec.md no longer matches the shipped code. Re-run /geniro:plan to re-sync it, or keep the spec as a historical record. Ship anyway?" Never edit or rewrite spec.md from /geniro:implement: the spec.md is the user's approved upstream artifact authored by /geniro:plan, and rewriting it here would force a cross-producer schema lockstep (same reasoning as the spec fact-check's "Do not rewrite the spec" boundary) — the consumer only flags the staleness; the user or a fresh /geniro:plan run re-syncs it. This line adds context to the Ship gate only; it never changes the draft-vs-commit-grade push classification and never adds a clause to the option-label allowlist below. Stack it with the Done-Condition and `## Accepted Failures` / `## Accepted Findings` lines — all feed the same question text.

The user can always type a custom response via "Other":
- **"Review diff"** (via Other) → show diff via `git diff origin/HEAD...HEAD`, loop back to ship-mode AUQ.
- **"Don't push"** (via Other; semantically equivalent to the "don't push" inline modifier below) → commit stays local, no push. State.md → `phase: ship-committed-only` (terminal; run §Cleanup's transient cleanup first). The Phase 3 commit (step 2) has already executed at this point — this option only suppresses step 3's push, not the upstream commit.

**Approvals-persistence protocol (step 3):** before firing the ship-mode AUQ, check state.md frontmatter `approvals[]` for a prior entry with `category: ship_mode`. If found, use prior `picked` value and skip the AUQ (typical compaction-resume: user already picked in the original flow) — except when the persisted pick is "Just push (no PR)" and the live target is the default or a shared/protected branch, OR a feature branch with an open PR reached via a /geniro:review or /geniro:debug handoff (re-resolve per Step 3's two-case check): a private-no-PR push approval does not carry to a visible push, so surface the confirm before executing rather than replaying the persisted pick. If not found, fire AUQ → on pick, append to `approvals[]` via `atomic_state_write` before executing the chosen action.

**L2 emit on rejection signal:** AFTER appending to `approvals[]`, source `${CLAUDE_PLUGIN_ROOT}/lib/emit-rejection.sh` and invoke:

```bash
emit_rejection_if_signal \
"/geniro:implement" "<branch>" "ship_mode" \
"<recommended ship-mode label>" "<picked label>" "<recommended label>"
```

`<branch>` = current git branch (or `global` if not detectable). Recommended label is whichever ship-mode option carries the `(Recommended)` suffix — "Open draft PR" by default. Helper detects rejection signals and emits L2 entry — acceptance is a no-op.

**Step 4 — Non-resumable-actions update.** After each side-effect that cannot be replayed safely (`git push`, `gh pr create`, posted PR comment), append a structured entry to state.md frontmatter `non-resumable-actions[]` array via `atomic_state_write`. Entry schema `{action, completed-at, <action-specific-fields>}`, where `action` is a literal from the enum in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §`non-resumable-actions[]` action enum (`git-push`, `pr-created`, `pr-comment-posted`), and `completed-at` comes from `$(date -u +%Y-%m-%dT%H:%M:%SZ)` in the same write call, never model-supplied (`atomic-state-write.md` §Timestamp sourcing). Write occurs AFTER the side-effect succeeds — atomic, so partial-write corruption is impossible mid-crash.

**Step 5 — Emit the ship report.** After the chosen ship action completes (push / PR create / commit-only) and its side-effect is recorded (step 4), emit a ship report to chat — a human-readable summary of what shipped, carrying the Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. This is the run's final deliverable; the terminal `phase:` transition (step 6 below / SKILL.md Ship sub-step "State.md final transition") fires only AFTER this report is emitted — a bare status echo ("opened draft PR") is not a ship report and leaves the user without the evidence the Stop hook scans for. The report covers:

- **What shipped** — the files / scope changed (the CHANGED_FILES set), one line on the change.
- **Commit + branch + PR** — commit SHA, branch name, and PR URL quoted verbatim from the actual tool output (`git rev-parse HEAD`, `git branch --show-current`, the `gh pr create` URL line) — never "git push succeeded" without the ref, per Loop invariant #6.
- **Test results** — the Phase 2 / Phase 3 `test-runner-agent` Verdict block (Command / Exit code / Summary) quoted as the Evidence Block.
- **Review-round summary** — per dimension, the found / fixed counts across the self-review rounds (e.g. "3 rounds: 4 findings found, 4 fixed"); name any `## Accepted Findings` / `## Accepted Failures` carried as known limitations.
- **Deferred** — anything left for a follow-up (deferred findings, skipped visual verification, docs not yet patched) — or "nothing deferred".

**Step 6 — Trailing bookkeeping writes must not contradict what shipped.** Post-ship bookkeeping (a memory-index update, an `atomic_state_write` of the terminal state, a tracker status transition) runs after the ship report. When such a write FAILS — e.g. an `Edit` rejected by its Read-before-Edit precondition, or a tracker MCP timeout — do not end the run leaving a record that contradicts the ship that already happened (the real failure mode: an index asserting the task is "not implemented" while the PR is open). Surface the failure in plain English, fix the precondition (Read the file, then Edit), and retry the write ONCE. If the retry also fails, say so explicitly in chat — "the project record still shows this as not-shipped; the PR is open at <url> — update the record manually" — so the user knows the bookkeeping is stale and the actual ship state is the PR, not the record.

**Inline modifiers from $ARGUMENTS** (semantic parsing per Phase 1 table) override the ship-mode AUQ deterministically:

| Modifier in $ARGUMENTS | Effect |
|---|---|
| "don't push" / "no push" / "commit only" | Commit succeeds, no push. State.md → `phase: ship-committed-only` (terminal; run §Cleanup's transient cleanup first). Skip ship-mode AUQ. |
| "draft only" / "draft PR" / "open draft" | Push + `gh pr create --draft`. State.md → `phase: done`. Skip ship-mode AUQ. |
| "ready PR" / "ready-for-review" / "non-draft PR" | Push + `gh pr create` (ready-for-review). State.md → `phase: done`. Skip ship-mode AUQ. |
| "open PR" / "create PR" / "with PR" (no `draft` or `ready` qualifier) | Does NOT skip the AUQ and does NOT silently pick ready-for-review. Fires the ship-mode AUQ so the recommended draft default is surfaced — a bare "open PR" intent is ambiguous between draft and ready, so it routes through the gate rather than defaulting to the visible ready-for-review path. |
| "stop after review" | Exit Phase 3 BEFORE commit. Surface clean review status as the deliverable. State.md → `phase: self-review-only` (terminal; run §Cleanup's transient cleanup first). |

---

### Update Docs

Check whether existing docs need updating based on what was implemented. **Skip if nothing changed that affects documented surfaces.** This is a thin fallback over the Phase 3 architecture reviewer's docs-staleness check — if that reviewer already surfaced doc-update findings, they would have been fixed inline during the fix loop. This step catches anything left over.

Scan the diff against main and check:
- Do any existing docs reference patterns/files that were renamed, moved, or superseded?
- Did this implementation introduce a new pattern that should be documented as a canonical example?
- Do README, architecture docs, or contributing guides need patches?

If updates needed, delegate to a general-purpose subagent with `model="haiku"` containing the diff summary + the doc files to patch. If that spawn returns empty (`0 tokens` — the Haiku tier is unavailable under the orchestrator's context-beta, e.g. a 1M-context session), apply the empty-result fallback in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` (retry with `model=` omitted, then patch inline). Keep changes minimal — patch what's stale or add a new reference, don't rewrite docs. If no docs need updating, skip silently.

---

### Extract Learnings

Learning capture is a Phase 3 ship sub-step (step 3 — after Commit, before the Ship-mode AUQ), so it isn't a postscript that gets dropped once the PR is open. Phase 3 calls the L2 helper `emit-learning` when conditions are met.

**Emit triggers** (per the table below):

| Type | When emits |
|---|---|
| `convention` | Phase 3 architecture or code-quality reviewer reports ≥3 instances of same pattern in changed code. Threshold tuning lives in the reviewer-agent spawn prompt. |
| `decision` | Spec.md records a non-trivial approach choice with `## Considered Alternatives` section. Mirrors that decision to L2 for cross-session recall. Fires only on the inline-task path — in spec-driven mode `/geniro:plan` already emitted the decision upstream. |

**Trust default: `verified`** — entries are grounded in Phase 2 code and Phase 3 reviewer findings (test-validated on entry).

**Promotion suggestion.** When a `convention` entry is emitted, additionally surface a one-line suggestion in the Phase 3 final report:

```
[learnings] Pattern detected ≥3 times: "<convention summary>". Recorded as a learning.
→ Consider /geniro:instructions edit <scope>.md to promote as rule.
```

Scope hint follows reviewer dimension: dim=`code-quality` → suggest `code-style.md`; dim=`architecture` → suggest `global.md`; other → "appropriate scope". Suggestion fires ONLY for `convention` type — single-occurrence `decision` emits do NOT warrant promotion to a custom-instruction rule. The line is informational (no AUQ, no auto-edit) — user remains source-of-truth for custom-instruction curation.

**Project-snapshot update site.** If Phase 2 added a new module / file, call `update-semantic --file codebase-map --append "..."` to append a bounded entry to `_CODEBASE_MAP.md`. Lock-guarded; rc=11 (lock held) is a recoverable "skip-and-defer" — caller may retry later or skip silently.

---

### Suggest Improvements (project scope only)

Runs as Ship step 4 — BEFORE the Ship-mode AUQ, alongside the learnings emit — so it finalizes the work rather than trailing the PR (a post-deliverable step is the documented drop vector, same failure mode the learnings emit's ordering rule guards against).

Spawn `reflection-agent` to synthesize candidates per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` §"Reflection-agent feed" (mode `implement`): pass the committed diff + changed-file list, the Phase 3 reviewer findings, the rule-file paths to dedupe against (`CLAUDE.md`, `.claude/rules/*`, `.geniro/instructions/*`), and prior declines (`query-learnings --type user_rejected_suggestion --tag auq-rejection --scope <scope>`). The agent returns only candidates that passed the helper's §Candidate bar (each tagged `Significance: critical | general` with an `Evidence:` citation; zero candidates is the common outcome); route any `Recurrence-eligible: yes` candidate to the rule-capture offer (`/geniro:instructions create`) rather than the improvements prompt, and surface the rest via the helper's §Routing table + §Presentation. Echo `Reviewed for improvements: <N> candidate(s)`; skip the prompt silently when the agent returns none.

`AskUserQuestion` is always-WAIT here. Skip findings already captured by the learnings-emit step; this step focuses on **structural improvements** (where the project records the rule) rather than knowledge capture. Plugin-file improvements (`${CLAUDE_PLUGIN_ROOT}/…`) are out of scope — submit a PR to the plugin repo OR edit your local plugin install directly.

---

### Integration Updates

**Worktree:** if working in a worktree (from Phase 1 workspace decision), leave the session in it. Do NOT call `ExitWorktree` proactively — runtime already prompts on session exit to keep or remove the worktree.

**Integrations:** workflow files (`.geniro/workflow/*.md`) live in the primary worktree per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` (Mode A) — glob both `./.geniro/workflow/*.md` (cwd-local) and `<PRIMARY_ROOT>/.geniro/workflow/*.md` (primary fallback). If a workflow file specifies completion actions (status transitions, PR linking, comments), re-fetch the tracker issue's current `status` via MCP at ship time (the status may have changed externally during implementation) BEFORE applying the workflow file's `### On task completion` block — the block gates its questions on the current status (e.g., the Linear template skips the "Move to In Review?" prompt when already In Review or terminal). Then apply the workflow file's `### On task completion` block, passing the resolved `status` and the ship action (Commit / Commit + push / Commit + PR / Leave uncommitted) as inputs. Always ask the user before changing external state (issue status, comments). NEVER auto-update. If integration backend is unavailable, log warning and skip both the re-fetch and the questions.

**AI-disclosure prefix.** When the workflow file contains a `## AI-Disclosure Prefix` section, apply the documented prefix to any comment text the skill AUTHORS before posting via the tracker MCP. Status-only updates, assignee-only updates, commit messages, and PR descriptions are excluded per the section's exclusion list. If the AI-Disclosure section is still a TODO stub, skip authoring comments entirely — post only status-only updates.

---

### Custom post-ship steps

Execute any user-authored post-ship steps from the loaded L4 `<skill>.md` (`.geniro/instructions/implement.md`). Per the `load-custom-instructions` §Producer contract, a `## Additional Steps` subsection is anchored to a phase-enum boundary; the canonical post-ship anchor is `### After ship` (`ship` is the final non-terminal phase enum value; post-ship steps run after its work completes). Run any subsection whose phase anchor is post-ship. When a step is conditioned on a PR existing and the run did not create one (ship-mode "commit only" / "no push"), skip it.

Treat each bullet as an imperative to execute in order, honoring any `AskUserQuestion` the user's step prescribes (e.g. "ask the user whether to create a preview environment, then invoke the project's `/preview` skill and append the URLs to the PR description"). The other plugin-defined Ship steps (Update Docs / Extract Learnings / Suggest Improvements / Integration Updates) cover plugin-defined work (some pre-AUQ, some post); this step covers user-defined post-ship work. Integration Updates reads `.geniro/workflow/*.md` (tracker integrations) — a different channel — so without this step a `### After ship` block in `.geniro/instructions/implement.md` never fires.

---

### Cleanup

Run the transient cleanup directly (no agent needed). The T1 / T1.5 split contract keeps durable artifacts on disk and deletes only transient subagent outputs. This procedure runs at Ship step 8 on the ship path AND immediately before the terminal `phase:` write on every other terminal path (`aborted`, `debug-handoff`, `self-review-only`, `ship-committed-only`) — leftover transients in a finished task-dir resurface as recurring migration-walk warnings on every `/geniro:update`, so cleanup is part of completing the task, not a postscript. `rm -f` is idempotent, so files not yet created on early-exit paths are a no-op.

**Transient outputs — DELETE at terminal exit** (T1 ephemeral):

```bash
rm -f "<task-dir>"/.kr-out.md \
      "<task-dir>"/.ce-out.md \
      "<task-dir>"/.tr-out.md \
      "<task-dir>"/.adversarial-out.md \
      "<task-dir>"/.spec-challenge-out.md \
      "<task-dir>"/.research-*.md \
      "<task-dir>"/notes.md \
      "<task-dir>"/playwright-verify.png
```

These files were used once by the orchestrator or subagents during the run; they're dead weight once the task reaches a terminal state. The `.research-*.md` glob covers the `codebase-research-agent` report and `/plan`'s per-facet research files left in the same task-dir — `/plan`'s own terminal phase is read-only, so this cleanup is where they get removed.

After the rm, echo `Cleaned up transient working files from <task-dir>` — one plain line; this is the in-session signal the pre-terminal check in Ship step 9 looks for.

**Durable artifacts — PRESERVE** (T1.5 task-bound durable):

```
<task-dir>/spec.md         # /geniro:plan canonical output — needed for /geniro:review spec-compliance
<task-dir>/state.md        # frontmatter + ## Tool log + ## Adjustments — needed for Adjustment Routing
<task-dir>/plan-*.md       # versioned plans from /geniro:plan iterations
<task-dir>/milestone-*.md  # /geniro:plan Big-mode milestone splits
```

Downstream consumers (`/geniro:review`, `/geniro:debug`, `/geniro:refactor`, `/geniro:implement` Adjustment Routing) depend on these surviving Ship. Do NOT `rm -rf <task-dir>` — durable artifacts (spec / state / plan / milestone files) must survive Ship; clean only the targeted T1 scratch files.

The `.geniro/` deletion guard hook allows targeted `rm -f` under `<task-dir>` (per-file deletions). Bulk `rm -rf .geniro/planning/<task-dir>/` is also allowed (deep path), but unused under the new contract.

**Temp files** — remove temporary screenshots, `.tmp`, `.bak`, `debug-*` files (not in `node_modules` or `.git`). Kill orphaned processes on agent ports (avoid touching standard dev ports). Remove stray `.log` files. Best-effort — silent failures OK.

---

## Phase 3 — Adjustment Routing (Big / Medium / Small)

Used when ship-feedback arrives via PR comments or as a follow-up `$ARGUMENTS` invocation. All adjustments route back through `/geniro:implement` itself with the original spec + adjustment description as new $ARGUMENTS.

### Big — changes to data model, API contract, new endpoints

1. Write tweak description to state.md `## Adjustments` body section.
2. Re-enter Phase 1 (Analyze) — the adjusted spec.md or inline-plan becomes the fresh source-of-truth. State.md `phase:` transitions back to `analyze`.
3. Run Phase 2 (Implement) and Phase 3 (Self-review + Ship) per the standard pipeline.

### Medium — new logic, additional fields

1. Write tweak description to state.md `## Adjustments` body section.
2. Re-enter Phase 2 (Implement) — apply the delta, run test suite. State.md `phase:` transitions back to `implement`.
3. On green tests, run Phase 3 (Self-review + Ship).

### Small — styling, typo, logic tweak

1. Write tweak description to state.md `## Adjustments` body section.
2. Apply the edit inline, re-run test suite. State.md updates `## Tool log` with the side-effect.
3. Re-enter Phase 3 self-review (single round usually sufficient).

**Soft limits.** Big tweaks: after 2 rounds, suggest starting a new /geniro:implement session — fresh context provides clean separation. Medium/Small tweaks: after 3 rounds, surface a message recommending the user re-spec via `/geniro:plan`.

**Loop target.** After any tweak, loop back to the Ship sub-step (Phase 3). Pre-ship steps (Update Docs, Extract Learnings, Suggest Improvements) run once on first Ship entry and are NOT repeated on tweak rounds unless the tweak materially changes the docs/learnings/improvement surface.

---

## Definition of Done

`/geniro:implement` run is complete when:

- [ ] State.md frontmatter `phase:` is a terminal state `done` / `ship-committed-only` / `self-review-only` / `debug-handoff` / `aborted`.
- [ ] Spec source resolved — either a spec.md / plan.md / DESIGN_DOC frontmatter file was loaded, OR inline-task mode wrote a `## Inline Plan` to state.md.
- [ ] Phase 2 ended on green tests (or accepted-failures noted in state.md `## Accepted Failures`).
- [ ] On a spec-driven run, each section 9 `verify:` command ran once after the suite went green; any failure was surfaced through the Phase 2 escalation digest (not silently skipped).
- [ ] Phase 3 reviewer loop ran (round 1 — all dims; round N+1 — failing dims only); exited clean OR escalated.
- [ ] Ship sub-step executed per the user's modifier or AUQ pick: commit-only OR push OR push+PR OR push+draft-PR OR self-review-only.
- [ ] Ship report emitted to chat BEFORE the terminal `phase:` transition — Evidence Block with what shipped, commit SHA / branch / PR URL quoted from tool output, test Verdict, review-round found/fixed summary, deferred items (Commit + Push + PR §"Step 5").
- [ ] Transient working files cleaned from the task-dir before the terminal `phase:` write (§Cleanup) — leftovers in a finished task-dir resurface as recurring migration warnings on every plugin update.
- [ ] Trailing bookkeeping writes (memory index, terminal state, tracker) that failed were surfaced and retried once; if still failing, the stale record was called out in chat so it never silently contradicts the open PR (Commit + Push + PR §"Step 6").
- [ ] `non-resumable-actions[]` frontmatter updated for every external side-effect (`git push`, `gh pr create`).
- [ ] Staged set matched this run's CHANGED_FILES — production files modified outside that set were confirmed via AUQ, not silently folded in; after ship, `git status` shows no unexpected leftover/duplicate copies of the shipped work.
- [ ] Learning emit fired when triggers were met (`convention` or `decision`); promotion suggestion surfaced for `convention` emits.
- [ ] Project-snapshot update fired if Phase 2 added new modules — `_CODEBASE_MAP.md` appended via `update-semantic`.
- [ ] Stop-hook evidence scan satisfied — Ship report's PASS/FAIL claims attach Evidence Blocks.
