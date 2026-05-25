# Phase 1 Triage Reference

Detailed contract for `/geniro:review` Phase 1 (Triage & Context Collect). Extracted from SKILL.md (design fix) to keep the orchestration shell ≤400 lines. SKILL.md retains a 2-3 line summary + a pointer here.

State.md `phase: triage` during this phase.

---

## 1. Input mode detection (3-mode routing)

The pre-step routes `$ARGUMENTS` to exactly one of OUTGOING / INCOMING / pr-ref-driven flow:

| Mode | Trigger | Routing |
|---|---|---|
| OUTGOING (default) | empty `$ARGUMENTS`, branch name, file paths, or diff range | Phase 1.5 mechanical pre-pass |
| INCOMING | PR ref + computed `K > 0` unresolved threads (after AUQ pick) OR anchored NL signals («process review on #N», «respond to review #N», «incoming review #N») | `incoming-mode-reference.md` Phase I |
| PR ref + K=0 / K=unknown | `gh` fetch fail-open or no unresolved threads | OUTGOING (skips AUQ) |

**PR-ref resolution.** Parse `<owner>/<repo>/<number>` from `$ARGUMENTS`. For a full PR URL, parse the path segments directly; for bare PR number (`#1234` or `1234`), resolve `<owner>/<repo>` from the current repo via `gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"'`.

**Thread-state fetch.** MCP-preferred: `mcp__github__pull_request_read` with the resolved owner/repo/number; consume `reviewThreads[]` from the returned payload directly. Fallback when MCP is unavailable:

```bash
gh api graphql -F owner=<owner> -F repo=<repo> -F number=<N> -F cursor=null -f query='query($owner:String!,$repo:String!,$number:Int!,$cursor:String){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100,after:$cursor){pageInfo{hasNextPage endCursor} nodes{isResolved isOutdated path line}}}}}'
```

Paginate with `endCursor` until `hasNextPage == false` (loop the call, concatenate `nodes[]` across pages — typical PR completes in 1-3 calls, stays under rate-limit budget). Compute `K = count(nodes where isResolved == false && isOutdated == false)`. Outdated threads are excluded from K (referenced code rewritten; comment stale).

**Fail-open behavior.** If the fetch fails (no network, missing token scope, rate limit, pagination loop errored mid-stream): set K to `unknown`, default routing to OUTGOING, surface `PR review-thread fetch failed — defaulting to Outgoing without thread-state awareness` under `## Caveats` in the final report (mirrors Phase 1.5 / 4b / 4c fail-open).

**INCOMING AUQ.** When K > 0, fire `AskUserQuestion` (do NOT print options as plain text) with header `"Mode"`: `"PR #N has K unresolved threads. Pick mode:"` (substitute the computed K — do NOT render the literal `K`) with options `"Outgoing — author my own review"` / `"Incoming — process reviewer feedback"`.

There is **NO `--incoming` flag**. Explicit override into INCOMING is via the anchored natural-language signals above. Bare keywords without a PR-ref anchor route to OUTGOING.

---

## 2. Scope resolution

Follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md`. The base branch is whatever scope-anchor resolves (PR base, remote `origin/HEAD`, or local `main`/`master` fallback) — do NOT hardcode `main`. Report the resolved target on its own (e.g., "Reviewing working tree — 3 files" or "Reviewing branch diff against `origin/master` — 2 commits, 5 files"). NEVER invoke `gh pr list` to **invent a target** — PR mode triggers ONLY on explicit PR-ref forms.

Read-only `gh pr list` / `gh pr view` / `gh pr diff` calls that gather peer-PR context for an *already-named* target ARE allowed (consume a user-supplied PR ref rather than invent one).

**Harness Auto Mode.** `/geniro:review` has NO auto mode of its own. Do NOT promote "Auto Mode Active" reminder into transcript framing — review has no auto mode.

---

## 3. PR-ref input parsing

For a PR ref, strip leading `#` and resolve with:

- `gh pr diff <number-or-url>` to materialize the diff
- `gh pr view <number-or-url> --json baseRefName,headRefName,body,title,headRefOid,url,isDraft,author,labels` for base/head context, head SHA pin, PR URL, PR body+title (the PR body feeds PLAN CONTEXT below), plus the draft state, author user, and label set

The draft/author/labels feed the pr-metadata reviewer's Common-False-Positives detection (bot-author / draft / release-please-label PRs excluded from rubric-strict checks). Capture the original PR ref, `headRefOid`, and canonical `url` — all three persisted to the state file for Phase 6 Action gate's «Post Draft PR review» option and for `commit_id` pinning (prevents line-anchor drift if PR updates mid-review).

If `gh` is unavailable or the PR cannot be fetched, report the error and stop — do NOT fall back silently to unstaged changes; do NOT run `gh pr list` to "find a related PR".

---

## 3.5. Workflow integrations (issue-tracker fetch)

Mirrors `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md:22` plumbing pattern — read `.geniro/workflow/*.md` integrations, apply argument-detection regex, attempt MCP fetch when backend available. Read-only from /review's perspective; status/comment updates remain in /implement Ship per `${CLAUDE_PLUGIN_ROOT}/skills/setup/workflow-templates/linear.md` § AI-Disclosure Prefix.

Skipped when `.geniro/workflow/` directory is absent OR empty (workflow not configured by /setup). Other inputs (files / diff range / branch / PR ref) ALL eligible — tracker IDs surface in `$ARGUMENTS` independently of PR-ref-driven flow.

### 3.5.1 Detection

1. `ls.geniro/workflow/*.md 2>/dev/null` — if zero matches, skip entirely.
2. For each workflow file, read it and extract the `## Argument Detection` regex patterns (Linear's: `https://linear\.app/.+/issue/([A-Z]+-\d+)` URL form, `\b[A-Z]{2,}-\d+\b` bare-ID form).
3. Apply patterns against (a) `$ARGUMENTS`, (b) `pr.title`, (c) `pr.body` — in that order. First match wins. Multiple matches in one source are deduplicated to the first.
4. Persist the matched tracker ID to state.md frontmatter:
- Linear: `linear-task-ref: <ENG-123|null>` (defaults to `null` when no match).

### 3.5.2 MCP fetch

When a tracker ID is detected AND the corresponding MCP server is registered (heuristic: any tool prefixed `mcp__linear__*` appears in the orchestrator's tool list at runtime — exact tool names depend on the installed MCP server):

1. Fetch the issue: title, description, acceptance criteria (parse `## Acceptance criteria` / numbered AC list from description body), labels, priority, parent issue ID, assignee.
2. **Sub-task fetch (parent epic linkage):** if the fetched issue has a non-null `parent` field, fetch the parent issue AND list its children. Persist:
- `linear-parent-ref: <ENG-100|null>` to state.md frontmatter (the parent issue ID).
- Build `linear-sibling-task-ids:` slot (in-memory only — not state.md frontmatter): list of sibling sub-task IDs from the parent's children. Consumed by peer-PR scout's Linear-relatedness bonus.
3. Build `LINEAR CONTEXT:` block — schema:
```
LINEAR CONTEXT:
ID: <ENG-123>
Title: <verbatim>
Description: <first ~800 chars, trimmed at sentence boundary if longer>
Acceptance Criteria:
- <AC1>
- <AC2>
…
Labels: <comma-separated>
Priority: <Urgent|High|Medium|Low|None>
Parent: <ENG-100|none>
Sibling sub-tasks (from parent): <ENG-101, ENG-102, …|none>
```
Total cap ~2000 chars — trim Description first, then AC list (keep first 5 ACs), then Labels.

### 3.5.3 Inline routing

`LINEAR CONTEXT:` block is pre-inlined into Phase 2 spawn prompts for **3 reviewers only**:

- **spec-compliance** — Acceptance Criteria become the rubric (in addition to PLAN CONTEXT section 9). Each AC must be reflected by a test reference or boundary assertion in the diff.
- **pr-metadata** — Title/body alignment with issue title; issue ID prefix presence enhanced from regex-only to verified-existence check.
- **architecture** — Parent epic + sibling sub-task IDs enable cross-PR coordination signals (see expanded peer-PR scout).

Other dims (bugs / security / tests / optimizations / guidelines / conventions / design) do NOT see LINEAR CONTEXT — they review the code under per-file rubrics where tracker context is noise.

### 3.5.4 Fail-open behavior

| Failure mode | Slot value | Caveat surfaced |
|---|---|---|
| Workflow directory absent | | none — silent (workflow not configured) |
| Tracker ID detected but MCP server unregistered | `LINEAR CONTEXT: none — MCP unavailable (degraded to regex-only ID detection)` | `## Caveats` one-liner |
| MCP fetch error (network / scope / rate limit) | `LINEAR CONTEXT: none — MCP fetch failed (fail-open)` | `## Caveats` one-liner with error reason |
| Sub-task list fetch fails (parent fetch ok) | `Sibling sub-tasks: none — child fetch failed` (partial block) | `## Caveats` one-liner |
| Parent issue absent from fetched issue (top-level epic) | `Parent: none` (legitimate, no caveat) | none |

Read-only — never writes to Linear; never mutates git state. Latency ~1-3s per fetch on healthy network (1-2 fetches: main issue + optional parent).

---

## 4. Peer-PR scout (PR-ref input only)

Skip for files / diff range / branch. Mechanism:

- `gh pr list --state open --base <baseRefName> --json number,title,headRefName,author,updatedAt,files --limit 30`
- Compute file-path intersection between current PR's changed files and each sibling. `gh pr diff <N> --name-only` for file-name list (re-derived from parsing captured diff text or separate call).
- **Score each candidate sibling** (extended beyond pure file-overlap):
- `file_overlap`: integer count of intersecting changed files.
- `linear_bonus`: +2 if sibling's PR title OR body contains a Linear ID matching `linear-parent-ref` OR appearing in `linear-sibling-task-ids:` from (parent epic OR sibling sub-task linkage). Bonus is additive: PR can earn +2 for parent-match AND +2 for sibling-sub-task-match (total +4).
- `total_score = file_overlap + linear_bonus`.
- Keep **top-10** by `total_score` (ties broken by `updatedAt` descending). Drop candidates with `total_score == 0` (no file overlap AND no Linear linkage — irrelevant). When is skipped (no workflow), `linear_bonus` is always 0 and this reduces to pure file-overlap top-10.
- For each kept sibling: `gh pr view <peer-N> --json title,headRefName,url` + `gh pr diff <peer-N> | head -200` (bounded to **200 lines** per sibling — tightened from 300 to compensate for higher count).
- Build `PEER-PR CONTEXT:` block: one entry per sibling, annotated with `(file_overlap=N, linear_bonus=±N)` so reviewers can weigh signal strength. Total cap ~**5000 chars** — drop lowest-`total_score` sibling first if exceeded.
- Pre-inline into **6 reviewer prompts**: architecture, design, **bugs, conventions, optimizations, spec-compliance** (expanded from architecture + design only). Skipped for tests + security + guidelines + pr-metadata (orthogonal or target-PR-specific).

Fail-open: if `gh pr list` fails or zero overlap-and-bonus surviving, render slot as `none — gh unavailable (fail-open)` (error case) or `none — no relevant open peer PRs` (legitimate empty result).

Read-only — never writes files, never mutates git state. Latency ~1-3s base + ~200ms per kept sibling (vs ~300ms in pre-expansion 3-sibling cap).

---

## 5. Git workspace decision (PR-ref input only)

Skip for files / diff range / branch. Routes to exactly one of three branches per the cwd / target-worktree state:

```bash
TOPLEVEL=$(git rev-parse --show-toplevel)
PARENT=$(basename "$(dirname "$TOPLEVEL")")
TOP=$(basename "$TOPLEVEL")
TARGET="pr-<N>-review"
```

- **Already in `.claude/worktrees/<TARGET>`** (`PARENT == "worktrees"` AND `TOP == TARGET`): skip create AND enter; sanity-check `git rev-parse HEAD` vs `headRefOid`. Match → reuse silently. Mismatch → surface a warning, continue without erroring.
- **In a different `.claude/worktrees/<other>`** (`PARENT == "worktrees"` AND `TOP != TARGET`): AUQ (header `Worktree`) with options "Continue here in `<other>`" / "Exit then create `pr-<N>-review`" / "Abort". Do NOT silently create a nested worktree.
- **Outside any `.claude/worktrees/...`** (`PARENT != "worktrees"`):
- If `git worktree list --porcelain` already lists `.claude/worktrees/pr-<N>-review`: skip create. `EnterWorktree(path: ".claude/worktrees/pr-<N>-review")`.
- Otherwise: AUQ (header `Worktree`) with "Yes — create (Recommended)" / "No — review in current location". On Yes: `git fetch origin pull/<N>/head:pr-<N>-review` (universal refspec — works for fork and same-repo), `git worktree add.claude/worktrees/pr-<N>-review pr-<N>-review`, `EnterWorktree`. On No: continue in current cwd; user accepts that Phase 6 commits land on the current branch.

After settled, every subsequent Phase 1 action and downstream phases run from the new cwd. Cross-session writes auto-route to the main worktree's `.geniro/` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md`, so they survive worktree teardown.

Do NOT use `EnterWorktree(name:...)` — that path auto-creates with `worktree-` prefix and defeats the convention detection.

---

## 6. Step 0 — Load custom instructions (L4)

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: review`, `LOAD_TIER: pipeline`, `MODE: initial-load`. The helper's §Procedure prescribes imperative `Read` directives on `global.md`, `review.md`, and `code-style.md` (3 files, pipeline tier); the §Echo contract requires one observable line per file. Both are mandatory.

---

## 7. Step 0.5 — Round-N counter

Round-N awareness so reviewers can focus on what prior rounds missed.

1. Resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A. Compute the state-file path `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md`.
2. Read the state file if present. If absent, set `prior-round-summary: none — first review` and `round: 1`.
3. If present AND state-file's `pr-ref:` matches the current run's `pr-ref` (both literal "none" counts as a match): set `round: <prior round + 1>` (defaulting prior to `1` when absent). Capture prior `prior-round-summary:` value into in-memory variable for threading into reviewer prompts as `PRIOR-ROUND FINDINGS:`. Also capture `pr-body:` value into `prior-pr-body` for the pr-metadata reviewer's drift check.
4. If `round >= 3` after increment, fire `AskUserQuestion` (header `"Round-N gate"`, question `"This is round N of review on the same target. Continue or escalate?"`) with options `"Continue review (Recommended)"` / `"Escalate to user — structured handoff"`. On Escalate: write a `## Handoff` to state file, persist `round:` and `prior-round-summary:`, exit cleanly without spawning reviewers (terminal `escalated`).
5. Persist `round:` and `prior-round-summary:` to the state file. Consumed by every Phase 2 reviewer prompt as the `PRIOR-ROUND FINDINGS:` slot.

---

## 8. Step 0.6 — PLAN CONTEXT load (schema-aware)

Per `plan-context-reference.md`. If `$ARGUMENTS` contains `--plan <path>`, OR PR body contains `geniro-plan: <path>`, OR walk-up `.geniro/planning/*/spec.md` resolves, OR project files exist (`docs/spec.md`, `docs/plan.md`, `PLAN.md`, `SPEC.md`): load.

Schema-aware:
1. Read first 20 lines. If `geniro_kind: design-doc` + `geniro_schema_version: m5-v1` frontmatter present → structured-section parser (10 sections + frontmatter goal-state).
2. Else fall back to prose detection with ~3000-char cap.

PLAN CONTEXT body inlined in spec-compliance reviewer spawn prompt only (Phase 2). Other dimensions don't see it.

---

## 9. Step 0.7 — Risk-tier stratification

Size-only triage (>8 files / >400 LOC) misses high-stakes small diffs. Stratify by risk tier alongside size.

1. Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` § "Step 1: Check for Hard Escalation Signals" — single source of truth for the 9 canonical signals (new entity / new endpoint or route / auth or permissions changes / new module / 3+ modules coordinated / open-closed violation / new async or background work / new external integration or env vars / ambiguous intent).
2. Scan changed files + diff content for matches.
3. If ANY signal matches → `risk-tier: high`. Otherwise → `risk-tier: standard`.
4. Persist to state.md frontmatter.

**Downstream knobs (4 — one NEW ):**
- Phase 4a severity threshold: standard ≥80; high ≥70.
- Phase 4b validator coverage: standard top-3 sample; high ALL HIGH.
- spec-compliance dimension default-on when risk-tier:high (otherwise gated on PR ref).
- **NEW:** Phase 1.5 mechanical pre-pass secret scan strictness — risk-tier:high adds patterns: AWS access keys / GCP service-account JSON / Azure SAS tokens / SSH OPENSSH key markers. Standard tier scans only the 4 baseline patterns.

---

## 10. Step 0.8 — Memory layer load

| Helper | Inputs | Outputs |
|---|---|---|
| `load-custom-instructions` MODE: refresh | scope = `review` + `global` + `code-style` (3 files) | concatenated rule body |
| `load-semantic` MODE: refresh | top-2: `_project.md` + `_CODEBASE_MAP.md` | inlined + fingerprint drift check |
| `query-learnings` | tags inferred from changed-file paths | top-K matching L2 entries (default K=5; filter superseded/deprecated) |
| `resolve-conflicts` | transitive | hard conflict → AUQ |

---

## 11. Mode AUQ (Standard vs TDD)

Fires only when `$ARGUMENTS` contains neither `--tdd` nor `--standard`. After triage, surface one `AskUserQuestion` (do NOT print options as plain text):

- **Header:** "Review mode"
- **Question:** "Run a Standard review (post all kept findings) or a TDD review (only post findings backed by an F→P-verified failing test)?"
- **Options:**
- "Standard review (Recommended)" — current behavior; Phase 4c gate opt-in per-run; Phase 6 posts all kept findings.
- "TDD review (auto-author failing tests for findings)" — Phase 4c gate's Recommended option flips to "Author tests…"; Phase 6 PR-comment posting filters to `[CONFIRMED-BY-TEST]` findings plus non-testable decision-types only.

If user declines (empty answer), default to Standard. `--tdd`/`--standard` flag (when present) always overrides this AUQ. Persist to `approvals[]` with category `tdd_mode_choice`.

See `${CLAUDE_SKILL_DIR}/tdd-mode-reference.md` for what TDD mode flips, edge cases, F→P contract scope, and rollback notes.

---

## 12. Size triage

After context settled, classify files when diff has >8 files or >400 LOC:

- **Trivial**: Renames, formatting-only, import reordering, generated files, lock files → skip full review (mention in summary as "triaged out").
- **Substantive**: Logic changes, new code, API changes, security-sensitive → full review.

Done inline by orchestrator (read each diff hunk, classify) — no subagent.

The size threshold also controls Phase 2 Standard vs Batched mode (≤8 files AND ≤400 LOC → Standard, all reviewers see all files; >8 files OR >400 LOC → Batched, files split into ~5-file batches).
