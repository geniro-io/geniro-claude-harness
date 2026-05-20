# Phase 1 Triage Reference (M6 §18)

Detailed contract for `/geniro:review` Phase 1 (Triage & Context Collect). Extracted из SKILL.md (D8 fix) to keep the orchestration shell ≤400 lines. SKILL.md retains а 2-3 line summary + а pointer here.

State.md `phase: triage` during this phase.

---

## 1. Input mode detection (3-mode routing)

The pre-step routes `$ARGUMENTS` к exactly one of OUTGOING / INCOMING / pr-ref-driven flow:

| Mode | Trigger | Routing |
|---|---|---|
| OUTGOING (default) | empty `$ARGUMENTS`, branch name, file paths, или diff range | Phase 1.5 mechanical pre-pass (M6 §7) |
| INCOMING | PR ref + computed `K > 0` unresolved threads (после AUQ pick) OR anchored NL signals («process review on #N», «respond to review #N», «incoming review #N») | `incoming-mode-reference.md` Phase I |
| PR ref + K=0 / K=unknown | `gh` fetch fail-open or no unresolved threads | OUTGOING (skips AUQ) |

**PR-ref resolution.** Parse `<owner>/<repo>/<number>` от `$ARGUMENTS`. For а full PR URL, parse the path segments directly; для bare PR number (`#1234` или `1234`), resolve `<owner>/<repo>` от the current repo via `gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"'`.

**Thread-state fetch.** MCP-preferred: `mcp__github__pull_request_read` with the resolved owner/repo/number; consume `reviewThreads[]` от the returned payload directly. Fallback when MCP is unavailable:

```bash
gh api graphql -F owner=<owner> -F repo=<repo> -F number=<N> -F cursor=null -f query='query($owner:String!,$repo:String!,$number:Int!,$cursor:String){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100,after:$cursor){pageInfo{hasNextPage endCursor} nodes{isResolved isOutdated path line}}}}}'
```

Paginate с `endCursor` until `hasNextPage == false` (loop the call, concatenate `nodes[]` across pages — typical PR completes в 1-3 calls, stays under rate-limit budget). Compute `K = count(nodes where isResolved == false && isOutdated == false)`. Outdated threads are excluded от K (referenced code rewritten; comment stale).

**Fail-open behavior.** If the fetch fails (no network, missing token scope, rate limit, pagination loop errored mid-stream): set K к `unknown`, default routing к OUTGOING, surface `PR review-thread fetch failed — defaulting to Outgoing without thread-state awareness` под `## Caveats` в the final report (mirrors Phase 1.5 / 4b / 4c fail-open).

**INCOMING AUQ.** When K > 0, fire `AskUserQuestion` (do NOT print options as plain text) с header `"Mode"`: `"PR #N has K unresolved threads. Pick mode:"` (substitute the computed K — do NOT render the literal `K`) с options `"Outgoing — author my own review"` / `"Incoming — process reviewer feedback"`.

There is **NO `--incoming` flag**. Explicit override into INCOMING is via the anchored natural-language signals above. Bare keywords без а PR-ref anchor route к OUTGOING.

---

## 2. Scope resolution

Follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md`. The base branch is whatever scope-anchor resolves (PR base, remote `origin/HEAD`, or local `main`/`master` fallback) — do NOT hardcode `main`. Report the resolved target on its own (e.g., "Reviewing working tree — 3 files" или "Reviewing branch diff against `origin/master` — 2 commits, 5 files"). NEVER invoke `gh pr list` к **invent а target** — PR mode triggers ONLY on explicit PR-ref forms.

Read-only `gh pr list` / `gh pr view` / `gh pr diff` calls that gather peer-PR context для an *already-named* target ARE allowed (consume а user-supplied PR ref rather than invent one).

**Harness Auto Mode.** `/geniro:review` has NO auto mode of its own. Follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/auto-mode-signals.md` §"Not а per-skill trigger" — do NOT promote «Auto Mode Active» reminder into transcript framing.

---

## 3. PR-ref input parsing

For а PR ref, strip leading `#` and resolve с:

- `gh pr diff <number-or-url>` к materialize the diff
- `gh pr view <number-or-url> --json baseRefName,headRefName,body,title,headRefOid,url,isDraft,author,labels` для base/head context, head SHA pin, PR URL, PR body+title (the PR body feeds PLAN CONTEXT below), plus the draft state, author user, и label set

The draft/author/labels feed the pr-metadata reviewer's Common-False-Positives detection (bot-author / draft / release-please-label PRs excluded от rubric-strict checks). Capture the original PR ref, `headRefOid`, и canonical `url` — all three persisted к the state file for Phase 6 Action gate's «Post Draft PR review» option и для `commit_id` pinning (prevents line-anchor drift if PR updates mid-review).

If `gh` is unavailable или the PR cannot be fetched, report the error и stop — do NOT fall back silently к unstaged changes; do NOT run `gh pr list` к "find а related PR".

---

## 4. Peer-PR scout (PR-ref input only)

Skip для files / diff range / branch. Mechanism:

- `gh pr list --state open --base <baseRefName> --json number,title,headRefName,author,updatedAt,files --limit 30`
- Compute file-path intersection between current PR's changed files и each sibling. `gh pr diff <N> --name-only` для file-name list (re-derived от parsing captured diff текст or separate call).
- Keep top-3 by overlap count (ties broken by `updatedAt` descending).
- For each kept sibling: `gh pr view <peer-N> --json title,headRefName,url` + `gh pr diff <peer-N> | head -300` (bounded к 300 lines).
- Build `PEER-PR CONTEXT:` block: one entry per sibling. Total cap ~3000 chars — drop lowest-overlap sibling first if exceeded.
- Pre-inline into architecture и design reviewer prompts ONLY. Not threaded into bugs/security/tests/optimizations/guidelines/conventions/pr-metadata (cross-reviewer convergence anti-pattern + conventions rubric mismatch).

Fail-open: if `gh pr list` fails или zero overlap, render slot as `none — gh unavailable (fail-open)` (error case) или `none — no overlapping open peer PRs` (legitimate empty result).

Read-only — never writes files, never mutates git state. Latency ~1-3s on healthy network.

---

## 5. Git workspace decision (PR-ref input only)

Skip для files / diff range / branch. Routes к exactly one of three branches per the cwd / target-worktree state:

```bash
TOPLEVEL=$(git rev-parse --show-toplevel)
PARENT=$(basename "$(dirname "$TOPLEVEL")")
TOP=$(basename "$TOPLEVEL")
TARGET="pr-<N>-review"
```

- **Already in `.claude/worktrees/<TARGET>`** (`PARENT == "worktrees"` AND `TOP == TARGET`): skip create AND enter; sanity-check `git rev-parse HEAD` vs `headRefOid`. Match → reuse silently. Mismatch → surface а warning, continue without erroring.
- **In а different `.claude/worktrees/<other>`** (`PARENT == "worktrees"` AND `TOP != TARGET`): AUQ (header `Worktree`) с options "Continue here in `<other>`" / "Exit then create `pr-<N>-review`" / "Abort". Do NOT silently create а nested worktree.
- **Outside any `.claude/worktrees/...`** (`PARENT != "worktrees"`):
  - If `git worktree list --porcelain` already lists `.claude/worktrees/pr-<N>-review`: skip create. `EnterWorktree(path: ".claude/worktrees/pr-<N>-review")`.
  - Otherwise: AUQ (header `Worktree`) с "Yes — create (Recommended)" / "No — review в current location". On Yes: `git fetch origin pull/<N>/head:pr-<N>-review` (universal refspec — works for fork и same-repo), `git worktree add .claude/worktrees/pr-<N>-review pr-<N>-review`, `EnterWorktree`. On No: continue в current cwd; user accepts that Phase 6 commits land on the current branch.

After settled, every subsequent Phase 1 action и downstream phases run от the new cwd. Cross-session writes auto-route к the main worktree's `.geniro/` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md`, so they survive worktree teardown.

Do NOT use `EnterWorktree(name: ...)` — that path auto-creates с `worktree-` prefix и defeats the convention detection.

---

## 6. Step 0 — Load custom instructions (L4)

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` с `SKILL_SLUG: review`, `LOAD_TIER: pipeline`, `MODE: initial-load`. The helper's §Procedure prescribes imperative `Read` directives on `global.md`, `<slug>.md`, и `code-style.md`; its §Echo contract requires one observable line per file. Both are mandatory.

---

## 7. Step 0.5 — Round-N counter

Round-N awareness so reviewers can focus on what prior rounds missed.

1. Resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A. Compute the state-file path `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` (M1 §T2 — see M6 §15.1).
2. Read the state file if present. If absent, set `prior-round-summary: none — first review` и `round: 1`.
3. If present AND state-file's `pr-ref:` matches the current run's `pr-ref` (both literal "none" counts as а match): set `round: <prior round + 1>` (defaulting prior к `1` when absent). Capture prior `prior-round-summary:` value into in-memory variable для threading into reviewer prompts as `PRIOR-ROUND FINDINGS:`. Also capture `pr-body:` value into `prior-pr-body` для the pr-metadata reviewer's drift check.
4. If `round >= 3` после increment, fire `AskUserQuestion` (header `"Round-N gate"`, question `"This is round N of review on the same target. Continue or escalate?"`) с options `"Continue review (Recommended)"` / `"Escalate to user — structured handoff"`. On Escalate: write а `## Handoff` к state file, persist `round:` и `prior-round-summary:`, exit cleanly без spawning reviewers (terminal `escalated`).
5. Persist `round:` и `prior-round-summary:` к the state file. Consumed by every Phase 2 reviewer prompt as the `PRIOR-ROUND FINDINGS:` slot.

---

## 8. Step 0.6 — PLAN CONTEXT load (M5-aware)

Per M6 §16.1 и `plan-context-reference.md`. If `$ARGUMENTS` contains `--plan <path>`, OR PR body contains `geniro-plan: <path>`, OR walk-up `.geniro/planning/*/spec.md` resolves, OR legacy filenames exist (`docs/spec.md`, `docs/plan.md`, `PLAN.md`, `SPEC.md`): load.

Schema-aware:
1. Read first 20 lines. If `geniro_kind: design-doc` + `geniro_schema_version: m5-v1` frontmatter present → structured-section parser (10 sections + frontmatter goal-state).
2. Else fall back к prose detection с ~3000-char cap (legacy mode).

PLAN CONTEXT body inlined в spec-compliance reviewer spawn prompt only (Phase 2). Other dimensions don't see it.

---

## 9. Step 0.7 — Risk-tier stratification

Size-only triage (>8 files / >400 LOC) misses high-stakes small diffs. Stratify by risk tier alongside size.

1. Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` § "Step 1: Check for Hard Escalation Signals" — single source of truth for the 9 canonical signals (new entity / new endpoint or route / auth or permissions changes / new module / 3+ modules coordinated / open-closed violation / new async or background work / new external integration или env vars / ambiguous intent).
2. Scan changed files + diff content for matches.
3. If ANY signal matches → `risk-tier: high`. Otherwise → `risk-tier: standard`.
4. Persist к state.md frontmatter.

**Downstream knobs (4 — one NEW per M6 §6.2):**
- Phase 4a severity threshold: standard ≥80; high ≥70.
- Phase 4b validator coverage: standard top-3 sample; high ALL HIGH.
- spec-compliance dimension default-on когда risk-tier:high (otherwise gated on PR ref).
- **NEW (M6 D6):** Phase 1.5 mechanical pre-pass secret scan strictness — risk-tier:high adds patterns: AWS access keys / GCP service-account JSON / Azure SAS tokens / SSH OPENSSH key markers. Standard tier scans only the 4 baseline patterns.

---

## 10. Step 0.8 — Memory layer load (M2)

| Helper | Inputs | Outputs |
|---|---|---|
| `load-custom-instructions` MODE: refresh | scope = `review` + `global` + `code-style` | concatenated rule body |
| `load-semantic` MODE: refresh | top-2: `_project.md` + `_CODEBASE_MAP.md` | inlined + fingerprint drift check |
| `query-learnings` | tags inferred от changed-file paths | top-K matching L2 entries (default K=5; filter superseded/deprecated) |
| `resolve-conflicts` | transitive | hard conflict → AUQ |

---

## 11. Mode AUQ (Standard vs TDD)

Fires only when `$ARGUMENTS` contains neither `--tdd` nor `--standard`. After triage, surface one `AskUserQuestion` (do NOT print options as plain text):

- **Header:** "Review mode"
- **Question:** "Run а Standard review (post all kept findings) или а TDD review (only post findings backed by an F→P-verified failing test)?"
- **Options:**
  - "Standard review (Recommended)" — current behavior; Phase 4c gate opt-in per-run; Phase 6 posts all kept findings.
  - "TDD review (auto-author failing tests for findings)" — Phase 4c gate's Recommended option flips to "Author tests…"; Phase 6 PR-comment posting filters к `[CONFIRMED-BY-TEST]` findings plus non-testable decision-types only.

If user declines (empty answer), default к Standard. `--tdd`/`--standard` flag (when present) always overrides this AUQ. Persist к `approvals[]` с category `tdd_mode_choice` (M3 §6 Block 5d).

See `${CLAUDE_SKILL_DIR}/tdd-mode-reference.md` для what TDD mode flips, edge cases, F→P contract scope, и rollback notes.

---

## 12. Size triage

After context settled, classify files когда diff has >8 files или >400 LOC:

- **Trivial**: Renames, formatting-only, import reordering, generated files, lock files → skip full review (mention в summary as "triaged out").
- **Substantive**: Logic changes, new code, API changes, security-sensitive → full review.

Done inline by orchestrator (read each diff hunk, classify) — no subagent.

The size threshold also controls Phase 2 Standard vs Batched mode (≤8 files AND ≤400 LOC → Standard, all reviewers see all files; >8 files OR >400 LOC → Batched, files split into ~5-file batches).
