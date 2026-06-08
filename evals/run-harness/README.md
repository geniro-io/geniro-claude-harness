# evals/run-harness — Phase-0 gate driver

The blocking piece of the evals pipeline (`design/evals-pipeline-plan.md` §5, resolution
option A). It runs a **human-gated, multi-agent geniro skill** (`/geniro:plan`,
`/geniro:review`, …) **headlessly, on the maintainer's Claude subscription**, and
auto-answers every `AskUserQuestion` gate so an unattended ≥N-trial methodology becomes
reachable. Without it, each eval run is ~30+ hand-clicks.

## Status: Phase 0 PASSED (both exit criteria)

| Exit criterion | Evidence |
|---|---|
| **(1)** `/plan` runs end-to-end with no human; outputs land where the grader expects; isolated `.geniro` root | `subtype=success`, 3 gates auto-answered, `spec.md`+`state.md` in the **target** repo (`branch: main`, `worktree: <target>`), dev worktree clean. ~21 turns / ~$1.45. |
| **(2)** `/review` Phase-6 chain unattended with ≥1 PRODUCT-DECISION finding **and** ≥1 unresolved `open_question`; `approve-default-v1` selects a valid **per-finding** resolution path | 2 `open_questions` (`decision_type: PRODUCT-DECISION`) **resolved** via the `(Recommended)` option; handoff in the target; dev worktree clean. ~32 turns / ~$3.30. |

These two runs also jointly exercise **both halves** of `approve-default-v1`: `/plan` used
the first-position fallback (no marker rendered); `/review` used the explicit
`(Recommended)`-marker selection.

## How it bills (the hard constraint)

Runs bill against the **Claude Code subscription**, never the per-token API:

- The TypeScript Agent SDK `query()` has **no `apiKey` parameter** — it spawns the local
  `claude` CLI binary and inherits its auth. With no `ANTHROPIC_API_KEY` set and the CLI
  logged in (`claude` / OAuth / keychain), runs draw on the subscription. (Per Anthropic
  docs, from 2026-06-15 SDK + `claude -p` subscription usage draws a separate **monthly
  Agent SDK credit** — watch that ceiling for the token-heavy at-scale `/review` runs.)
- The driver **strips `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN`** from the child env and
  warns on `CLAUDE_CODE_USE_BEDROCK/VERTEX/FOUNDRY`, so a stray key can't silently switch
  to API billing.
- The driver also **strips `CLAUDECODE`** from the child env — that variable is an *interactive*
  nesting guard, and programmatic subprocess use is safe, so removing it lets the headless run
  nest inside a Claude Code session (mirrors skill-creator's `run_eval.py`). Without it the
  spawned `claude` refuses to start when the suite is driven from a Claude Code session.
- A fully no-SDK path is **not possible**: auto-*answering* `AskUserQuestion` (supplying the
  chosen label, not just allow/deny) requires the SDK `canUseTool` callback; the raw
  `claude -p` CLI and hooks can't inject the answer payload.

## Quickstart

```bash
# 1. Toolchain (one-time). Node >= 22, pnpm.
pnpm install            # or: pnpm add @anthropic-ai/claude-agent-sdk ; pnpm add -D tsx typescript @types/node
unset ANTHROPIC_API_KEY # ensure subscription auth (the driver also strips it defensively)
claude  # confirm you are logged in (subscription), then /exit

# 2. Unit tests for the auto-answer policy
node --import tsx --test src/auto-answer.test.ts
node ./node_modules/typescript/bin/tsc --noEmit   # typecheck

# 3. Drive /plan against a realistic target
PLAN_REPO=$(bash fixtures/build-plan-fixture.sh | tail -1)
node --import tsx src/driver.ts --skill geniro:plan --cwd "$PLAN_REPO" \
  --out runs/plan-1 --max-turns 300 \
  --prompt "add a multiply(a, b) helper to src/math.js alongside add and subtract, with a unit test"

# 4. Drive /review against the planted-bug fixture
REVIEW_REPO=$(bash fixtures/build-review-fixture.sh | tail -1)
node --import tsx src/driver.ts --skill geniro:review --cwd "$REVIEW_REPO" \
  --out runs/review-1 --max-turns 500 --prompt "main..HEAD --standard"
```

Each run writes `runs/<id>/`: `meta.json` (invocation + provenance), `transcript.jsonl`
(every SDK message), `gates.jsonl` (one record per AUQ: questions, options, chosen answer),
`result.json` (completion, `terminal_reason`, turns, `total_cost_usd`, token usage,
`permission_denials`, artifacts found under the target's `.geniro/`). The driver exits 0
only when the run completed (`subtype=success`).

### Driver flags

| Flag | Default | Meaning |
|---|---|---|
| `--skill <name>` | `geniro:plan` | skill command to run (`/<name> <prompt>`) |
| `--prompt <text>` | `""` | args to the skill (or the raw prompt with `--raw`) |
| `--cwd <dir>` | fresh temp git repo | the **target project** the skill operates on (host `chdir`s here) |
| `--plugin-root <path>` | the worktree | source repo to archive the plugin-under-test from |
| `--plugin-ref <ref>` | `HEAD` | git ref of the plugin under test (frozen via `git archive`) |
| `--plugin-raw` | off | load `--plugin-root` as-is instead of a clean archive copy (debug only) |
| `--claude-bin <path>` | resolved from `PATH` | the `claude` CLI for `pathToClaudeCodeExecutable` |
| `--max-turns <n>` | `300` | top-level turn cap; `result.terminal_reason=max_turns` flags truncation |
| `--out <dir>` | `runs/<runId>` | run-output directory |
| `--raw` | off | treat `--prompt` as the raw prompt (no `/<skill>` prefix) — for probes |

## The `approve-default-v1` auto-answer policy (`src/auto-answer.ts`)

Pick the `(Recommended)` / pre-selected option, **order-stable by the marker, not
positional**, falling back to the first listed option when none is marked; return the
chosen label **verbatim** (the SDK matches the answer to a presented label). For
`multiSelect`, take the marked options, else the empty set (the conservative do-nothing
path). Never synthesizes free text. Fails fast on an option-less question (an unanswerable
gate is a finding, not a silent default).

This mirrors geniro's `skills/_shared/per-finding-question.md` "Recommended-label policy"
(recommended option suffixed ` (Recommended)` **and** positioned first). Keying on the
marker keeps the policy correct under option re-ordering and lets it resolve `/review`'s
variable, dynamically-labelled per-finding PRODUCT-DECISION gates — not just `/plan`'s
fixed approve gate. Covered by `src/auto-answer.test.ts` (10 cases).

> Question quality is itself a graded signal — the auto-answer masks a skill that asks
> *worse* questions. `gates.jsonl` records every gate verbatim so question quality can be
> scored separately (plan §5).

## Operational findings (§5 risks, closed with evidence)

1. **`canUseTool` answers `AskUserQuestion` on subscription** — confirmed live (micro-smoke
   + both exit-criteria runs). Return `{behavior:"allow", updatedInput:{questions, answers}}`.
2. **Subscription auth headless** — works via the CLI binary; no `ANTHROPIC_API_KEY`.
   TypeScript `canUseTool` needs **no** streaming/keep-alive workaround (that's Python-only).
3. **Per-trial isolation requires `process.chdir(cwd)`.** The SDK `cwd` option moves only the
   Bash tool; Claude Code's workspace/git-root detection walks up from the **host process**
   cwd. Without `chdir`, relative `.geniro` writes + `git branch` detection resolve against
   the dir the driver was launched from, leaking state out of the trial. The driver now
   `chdir`s into the (isolated) target before `query()`.
4. **Load the plugin-under-test from a clean `git archive` copy, never the dev worktree.** A
   dev worktree is itself a geniro project (`.geniro/`, `evals/`) *and* a rich codebase; with
   an empty/under-specified target the model will `cd` into `CLAUDE_PLUGIN_ROOT` and
   plan/review against the **plugin source** instead of the target. `git archive <ref>` yields
   a pristine tree (no `.git`, `.geniro`, untracked `evals/`, or worktree linkage) and pins
   the prompts/scripts under test (plan §6 step 2).
5. **The target must be realistic, not empty.** An empty target gives the model nothing to
   work on, so it wanders looking for a codebase. The `fixtures/build-*.sh` scripts seed
   small self-contained repos.
6. **All `/plan` + `/review` gates fire from the main session** (recon-confirmed against
   `main`), so the SDK limitation *"`AskUserQuestion` is not available inside subagents
   spawned via the Agent tool"* does **not** block these skills. Audit this for any new gate.
7. **`gh` auth** is present for the real git/PR `/review` fixtures.
8. **Worktree nesting:** standard `/review` on a committed diff did not require `EnterWorktree`
   here; the cross-session handoff resolver already routes to the primary worktree.

## Known caveats / open items

- **Tool/MCP surface varies run-to-run** (observed `tools=30 mcp=0` vs `tools=78 mcp=31`
  under identical `settingSources:[]`). Pin the tool/MCP environment for reproducibility
  before the at-scale runs (feeds the plan's `instructions_digest` / environment-pinning).
- `total_cost_usd` is the SDK's **client-side estimate**; the committed ledger still derives
  cost from `tokens × price-map` for reproducibility (plan §9).
- These two runs are smokes, not the methodology. Suites (20–50 tasks), the cost/CI ingest,
  the ledger, and the seam check are Phases A–E.
- **Driving a whole suite** (multi-trial A/B → grade → swap-compare → aggregate → ingest) is
  Phase C's `evals/run-suite.sh`, which calls this driver per trial. Run it once per (skill,
  partition); see [`../README.md`](../README.md). This README documents the single-trial driver.

## Files

```
src/types.ts            AskUserQuestion input/answer shapes
src/auto-answer.ts      approve-default-v1 policy (pure, tested)
src/auto-answer.test.ts 10 policy tests (node:test)
src/driver.ts           the canUseTool query() driver
fixtures/build-plan-fixture.sh    realistic mathlib target for /plan
fixtures/build-review-fixture.sh  planted-bug git fixture for /review
runs/                   per-run outputs (gitignored)
```
