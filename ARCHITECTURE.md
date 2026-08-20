# Architecture Decisions

Consolidated reference of design decisions that govern how skills, hooks, helpers, and state files work in the Geniro plugin. Each section distills one milestone's key rulings; historical rationale and proposal tracking have been removed.

---

## State Files (M1)

Every state write uses `atomic_state_write` (tmp + fsync + rename + fsync-dir); enforced by PreToolUse hook.

**Four tiers:**

| Tier | Purpose | Path pattern |
|------|---------|-------------|
| T1 Task — ephemeral | Transient working artifacts; targeted `rm -f` at the owning run's terminal exit | `planning/<task-dir>/.{kr,ce,tr,research,spec-challenge}-out.md` (subagent OUTPUT_PATH reports), `planning/<task-dir>/.research-<facet>.md` (per-facet `/plan` research), `planning/<task-dir>/notes.md`, visual-verify artifacts |
| T1.5 Task — durable | Survives Phase Ship; design artifacts the user may want to keep | `planning/<task-dir>/{spec,state}.md`, `planning/<task-dir>/plan-*.md`, `planning/<task-dir>/milestone-*.md`, `state/<skill>/<slug>/state.md`, `state/setup/state.md` singleton |
| T2 Handoff | Inter-skill; carries structured `open_questions[]` for safety-gated consumer transitions | `state/handoff/from-<producer>-<branch>.md` |
| T3 Persistent | CRUD / append-only | `instructions/`, `actions/`, `workflow/`, `planning/_*.md`, `knowledge/learnings.jsonl` |

- T1 vs T1.5 split lets Ship cleanup keep design intent (spec, state log, milestones) while removing only transient subagent-report scratch files.
- Validation failure opens a hard AUQ with four options (delete-and-restart / open-in-editor / update-worktree-path / skip-emergency) — no silent partial reads. `update-worktree-path` offers only when the saved `worktree:` path is stale (exit code 8); canonical template in `skills/_shared/validate-state-file.md` §Recovery AUQ template.
- Concurrency by convention: T1/T1.5 use slug-scoped paths, T2 uses branch-scoped paths, T3 CRUD uses optimistic mtime check. No filesystem locks.
- `_`-prefixed files under `planning/` are persistent T3; validators enforce tier by frontmatter, not filename.
- T2 handoffs carry a structured `open_questions[]` frontmatter array per `skills/_shared/state-tier-spec.md` §T2 — each entry has `{id, source, question, related_findings/related_hypotheses, status: unresolved|resolved|wontfix, resolution}`. Consumer skills (e.g., `/implement` Phase 1 Step 12) gate Edit/Write transitions on the array being empty-of-unresolved; producer Pre-gates (`/review` Phase 6, `/debug` Phase 3) and Pre-Post-PR guards refuse to ship state with unresolved entries.
- A gate that fires and never gets answered — the turn ends mid-question, or is followed by a non-reply like a bare "continue" — is its own state, distinct from a declined answer and from a producer→consumer `open_questions[]` handoff: `approvals[]`'s provenance rule forbids synthesizing an entry for a question never answered, so without this the gate would leave no trace at all. Recorded as a `## Errors` entry (schema: `skills/_shared/state-tier-spec.md` §"`## Errors` — the unanswered-gate entry"), discharged only by re-firing the identical question and getting an actual answer to it — behavioral rule in `skills/_shared/gate-rendering.md` §Lean-question conventions.
- `/debug` handoffs (m7-v2+) additionally carry a producer-specific `authored_tests[]` array — each entry `{id, path, intent, mode, f_to_p_status, related_hypotheses, targeted_source, confidence}`. Consumed by `/implement` Phase 1 Step 12 via `skills/_shared/debug-handoff.md` Scan/Extract/Verify/Decide protocol: prefer frontmatter, fall back to body parse for m7-v1 legacy; resolve paths against the consumer's worktree; surface suggest-only relocation block when MISSING. The array is informational (not a gate) so authored tests survive cross-worktree consumption without losing producer intent.

---

## Memory Layers (M2)

Four-layer taxonomy: L1 Working / L2 Episodic / L3 Semantic / L4 Procedural.

- **Writer intent** — not file location — determines the layer.
- **Cross-layer precedence** when layers disagree: L4 > L3 > L2. Within-layer, recency wins.
- CLAUDE.md is outside the memory model — the plugin never writes to it.
- L3 files live under `planning/_*.md`; `.fingerprint.json` hashes detect drift.
- Hard conflict (L4 rule contradicts L3 reality) halts the skill and opens an AUQ per `skills/_shared/resolve-conflicts.md`.
- **L4 base directory is overridable for clean fresh-clone / ephemeral environments.** Precedence: `GENIRO_INSTRUCTIONS_DIR` > `CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR` (the plugin's `instructions_dir` install option) > `<repo>/.geniro/instructions`. The external dir holds the instruction files flat (`<dir>/global.md`, …); an active external dir is **override, not merge** (it replaces the in-repo set). Read-side only — pipeline skills read from it, but `/geniro:instructions` CRUD stays in-repo because the atomic-write + `.geniro/`-deletion guards key on the literal `.geniro/` path. A configured-but-missing pointer fails open to the in-repo default. Resolver: `skills/_shared/load-custom-instructions.md` (inline) + `lib/repo-root.sh` (`_geniro_instructions_dir`).

---

## Fact verification (Data Sources)

- A new `## Data Sources` block in the L4 custom-instruction layer (`global.md` or a per-skill instruction file) lets the user declare read-only verification sources — a read-only shell command, an MCP tool, or an action — each with a `(confirms: <fact kind>)` hint.
- The canonical helper `skills/_shared/data-sources.md` discovers the declared sources, screens each for read-only safety, then cross-checks load-bearing facts against the **maximum applicable set** of declared plus built-in sources (rather than trusting a single fetch). The bounded fact set is the facts a downstream decision, verdict, or report depends on — load-bearing facts only, not every sentence, consistent with the always-on-verification doctrine. Any skill phase that establishes such a fact applies the helper; the bound is a property of the fact, so it holds as consumers are added without re-enumerating them here.
- Per-fact outcomes: **confirmed** (a source agrees), **conflicting** (sources disagree — surfaced to the user), **unconfirmed** (no source can confirm — marked, never presented as fact). The whole pass is read-only-screened and fail-open: an unavailable source degrades to skip-and-log, never a hard block.
- Consumers: `skills/_shared/task-chain-context.md` verifies the assembled chain facts, and `skills/_shared/spec-challenge.md` verifiers consult declared sources too — spec-challenge is no longer code-only.

## Verification Surface

- A companion `## Verification Surface` block in the same L4 layer lets the user map each project check to what it covers and what it does not (a type check says nothing about behavior, a unit suite says nothing about cross-module wiring), plus `MANUAL` rows for ground no automated layer touches.
- Canonical spec: `skills/_shared/verification-surface.md`. Authored by `/geniro:instructions` (the request-to-block-type detection table routes "the unit suite doesn't cover X" here) and loaded alongside `## Data Sources` by `skills/_shared/load-custom-instructions.md`; a per-skill entry narrows the global one for that skill and wins where the two disagree about the same command.

---

## Compaction Survival (M3)

SessionStart hook re-establishes context across `compact|resume|startup`. `clear` is explicitly excluded (respects user intent).

- Hook only emits pointers and directives in `additionalContext` — it does NOT load helpers itself. The model executes the refresh protocol on its next turn.
- Side-effects already completed (git push, PR comment, Slack notify) are surfaced as hard-imperative do-not-repeat warnings via `non-resumable-actions[]` in state frontmatter.
- Cold startup with no active T1.5 task suppresses the `systemMessage` one-liner.
- Hook is read-only on state.md; only writes to `learnings.jsonl` (auto-archive path).

---

## /implement (M4)

3 phases: Analyze → Implement → Self-review-and-Ship.

- Phase 1 fires Step 0 workspace AUQ (passive-detect of `CURRENT_BRANCH`, `IN_WORKTREE`, prior-task signals → 6-rule decision tree; auto-continue when "continuing-work" signals are present, AUQ only when ambiguous).
- Phase 1 spawns `knowledge-retrieval-agent` + `codebase-explorer-agent` in parallel (subagent delegation replaces the orchestrator-inline 17-file Phase-1 sweep that drove the 370K-token context bloat). The knowledge-retrieval spawn is gated on a mechanical store-check — it fires only when the memory store has anything to sweep (`.geniro/knowledge/` non-empty, a prior handoff / snapshot / plan artifact, or a declared `## Memory Backend`, which a directory check cannot see); the gate reads the store, never the orchestrator's own context, so the anti-shortcut rule is unchanged. The codebase-explorer spawn is unconditional.
- When a spec.md is provided, `/implement` consumes the spec frontmatter (including `workflow_refs[]` when `geniro_schema_version: m5-v2` / `m5-v3`). Inline-task fallback exists when `/plan` has not been run. Phase 1 now primes its `knowledge-retrieval-agent` + `codebase-explorer-agent` with related-task chain context (parent epic + sibling tasks + neighboring milestones) via `skills/_shared/task-chain-context.md` — fail-open.
- Phase 2 uses TodoWrite for sequential decomposition (one-in-progress invariant); `test-runner-agent` runs at phase end. Phase 2 fix loop max 3 retries; on failure → AUQ with `debug-handoff / accept-failures / abort`.
- Phase 3 spawns the reviewer-agent set in parallel, sized by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-grid-scaling.md` against Codebase-Explorer's four-level `change_scope` (any matched signal on its `Risk flags:` line forces the full always-fire set regardless of scope; a spec-driven `small` diff also adds `architecture`, the sole carrier of spec-compliance/docs-staleness checks); an inline, no-spawn edge-case test-authoring step runs alongside that same round, skipped only on `change_scope: trivial` or the `--no-adversarial` modifier. Every CRITICAL/HIGH finding gets a cold `finding-verifier-agent` verdict before the fix loop consumes it (`--deep` replaces this with signal-gated majority verification); max 3 review rounds, then escalation AUQ.
- Phase 3's fix loop partitions findings into actionable (severity ≥ MEDIUM, decision-gated, or a failing authored edge-case test) vs minor (LOW with none of those); minor findings never block loop exit or force rounds — survivors persist to state.md `## Deferred Findings` and surface in a pre-ship minor-findings gate (same ruling set as the test-quality gate: skip-when-clean, advisory, fail-open, no new agent; conservative default "leave in ship report", fix-now = inline pass + suite re-run, never a review round; `approvals[]` category `minor_findings_disposition`; feeds the ship report's Deferred line; ship modifiers / `launch_config.ship_mode` never skip it). Canonical contract: `skills/implement/implement-reference.md` §"Phase 3: Minor-findings gate".
- Phase 3 adds a test-quality gate (`skills/_shared/test-quality-gate.md`): after the fix loop, when the run authored or changed tests, it surfaces the fresh `tests`-reviewer audit of those tests — claimed-vs-asserted scope, spec-coverage traceability, redundancy among newly-authored tests, weak assertions (the three honesty checks added to `skills/_shared/review-criteria/tests-criteria.md`) — as a visible, skip-when-clean, advisory, fail-open decision before Ship. It spawns no new agent: the surfacing-and-decision layer the broad reviewer pipeline lacked, consuming the tests-dimension output. The failure class it catches is the test that passes but asserts less than it claims, or omits a spec-required behavior. `tdd-cycle.md` also names it at its REFACTOR exit, but nothing runs the cycle past RED today, so that reuse is dormant.
- Phase 1 Step 12 parses every T2 handoff (`from-review-<branch>.md`, `from-debug-<branch>.md`) for `open_questions[]`; refuses to leave Phase 1 while any entry has `status: unresolved` — gates Edit/Write transitions cold. For debug handoffs additionally invokes `skills/_shared/debug-handoff.md` Scan/Extract/Verify/Decide protocol: extracts `authored_tests[]` (m7-v2+) or falls back to body parse (m7-v1), verifies each path against the consumer's worktree, surfaces suggest-only relocation block when MISSING. Authored-tests are informational (not a gate); Phase 2 reads them to prime TodoWrite decomposition so every authored test surfaces as an acceptance gate in its relevant todo.
- Phase 1 Step 12.5 runs the same spec-challenge (`skills/_shared/spec-challenge.md` MODE: implement) before the first Edit/Write on spec-driven runs — verifies the spec's cited claims against current code and red-teams the locked approach; the alternatives stage is skipped because the approach is already approved. It verifies FACTS, never the approved DESIGN: the spec is never rewritten (rewriting an upstream producer's durable artifact would silently re-open a signed-off decision), and an AskUserQuestion fires only on a refuted claim or blocking risk — skip-when-clean.
- Transient cleanup fires before every terminal `phase:` write (`done`, `aborted`, `debug-handoff`, `self-review-only`, `ship-committed-only`): targeted `rm -f` removes only T1 scratch — including `/plan`'s `.research-*.md` per-facet outputs left in the task-dir — and preserves durable T1.5 artifacts (spec.md / state.md / plan-*.md / milestone-*.md). Leftovers from interrupted runs are swept by the `/geniro:update` migration walk.
- Subagents declare `model: inherit`; spawn sites OMIT `model=`. The orchestrator's session tier (Opus / Sonnet / Haiku) propagates to every judgment-grade spawn — except the `test-runner-agent` + `knowledge-retrieval-agent` mechanical carve-outs, which declare `model: sonnet` in frontmatter, and the Phase 2 bounded code-delegate, which passes `model="sonnet"` at the spawn site as an execution spawn. Those three are non-judgment, so `sonnet` is their ceiling and the orchestrator sizes below it per the workload — a fix-loop test re-spawn, a delegate slice that is a mechanical rename. `--subagent-model` (also accepted by `/geniro:review`) pins every judgment spawn in the run to a user-named tier and caps the non-judgment ones — `skills/_shared/model-tiering.md` §`--subagent-model`.
- Round 1's reviewer-agent spawns pass paths, never pre-inlined bodies, for both criteria files and changed files — the reviewer reads each path itself, matching `/geniro:review` Phase 2's own spawn shape.
- Every side-effect (commit, push, PR creation) writes to `non-resumable-actions[]` before executing.

**A review verdict binds to the file set it reviewed, not to the run.** Phase 3's fix-loop exit persists frontmatter `reviewed_file_set` — the CHANGED_FILES the final round's reviewers actually received (`skills/implement/implement-reference.md` §"Phase 3: Bounded fix loop"). Ship's commit step diffs live CHANGED_FILES against it before staging (same file, §"Commit + Push + PR" Step 2): a file edited after the round converged carries no review, however clean that round read, and the run either re-reviews the diverged files or ships with a disclosed `## Unreviewed Files` block folded into the Ship-mode AUQ — never the earlier clean result standing in for coverage it never had. Same shape as an approval a host dismisses on a post-approval push; the classical framing is CWE-367 — a check bound to a state that has since moved is worse than none, for the confidence it wrongly lends.

**Ship consent (separate from side-effect logging).** Logging a side-effect to `non-resumable-actions[]` records that it happened; it does not authorize it. Commit / push / PR-create are outward-facing actions that each require their own confirmation gate (`/implement` Ship-mode AUQ). An approval scoped to one decision does not satisfy a different one: a `/review` action-gate pick ("/implement findings") authorizes applying the fixes, never the downstream commit/push. A push to a feature branch that already has an open PR is outward-facing (CI re-runs, reviewers see new commits), so it is gated like a shared-branch push when the run was entered via a handoff.

**Handoffs carry work, not authority.** A `/review` → `/implement` (or `/debug` → `/implement`) handoff transfers findings and unresolved `open_questions[]` — restrictions and to-dos — never ship authorization. The consumer applies its own gates; it is not pre-authorized by the producer's action-gate pick. See `skills/_shared/reporter-boundary.md` §2.

**Shortcut-judgment does not suspend a skill's contract.** A continuation run ("I already explored this in the /review I just ran") may not skip a skill's mandated parallel spawns (Phase-1 knowledge-retrieval + codebase-explorer) or gates (Ship-mode AUQ) on a "pure ceremony / context already held" rationalization. The spawns and gates fire regardless of inherited context; a continuation that skips them inherits the upstream run's blind spots. Enforced by `skills/_shared/reporter-boundary.md` and each skill's own gates.

---

## Subagent model selection

- The axis is decide-vs-apply. A spawn that decides something the orchestrator acts on — what the code does, whether a finding is real, which approach wins — inherits the user's tier. A spawn that applies a decision already made runs at most sonnet, and the orchestrator sizes below that ceiling from the workload in front of it (`skills/_shared/model-tiering.md` §Sizing a non-judgment spawn) — the lever Cursor spells `auto` and Claude Code has no selector for. Writing files is not the test; several inherit-tier agents write files while still deciding their content.
- Plugin-defined subagents declare `model: inherit` in frontmatter, except the two mechanical carve-outs `test-runner-agent` + `knowledge-retrieval-agent`, which pin `model: sonnet` (per `skills/_shared/model-tiering.md` §category 3 — purely mechanical work that does not need the orchestrator's reasoning tier).
- Spawn sites in skill SKILL.md files OMIT `model=` argument unless a carve-out names them — passing `model="inherit"` at the call site fails Agent-tool input validation (the enum is `sonnet|opus|haiku|fable`); the runtime resolver picks up the orchestrator's tier ONLY when `model=` is unset.
- User-authored custom reviewers (`.geniro/instructions/review-extra/*.md`) may declare an explicit `model:` field to opt OUT of inherit; absent declaration means inherit.
- `--subagent-model` — a run-scoped flag on `/geniro:implement` and `/geniro:review` naming one tier from that same enum — pins every judgment-grade spawn in the run and caps the non-judgment ones (stronger never raises them; cheaper does lower them), and is announced once at run start. A value outside the enum (e.g. a non-Anthropic model id) is not expressible at a spawn site; the run says so and names the two working routes (`CLAUDE_CODE_SUBAGENT_MODEL` in Claude Code, an agent file's own `model:` frontmatter or a `cursor-agent -p --model` escape hatch in Cursor) instead of applying it silently. Full contract: `skills/_shared/model-tiering.md` §`--subagent-model`.
- Cloud-runner / headless-CI fallback table preserved in `skills/_shared/model-tiering.md` §"Tier table — fallback for runtimes without an orchestrator" for environments where `model: inherit` resolution is unsupported.
- Sites that deliberately set a tier of their own (`sonnet` as the ceiling in each case):
  - `test-runner-agent` + `knowledge-retrieval-agent` → `model: sonnet` in frontmatter (mechanical carve-outs — running tests and fetching prior learnings is not reasoning work).
  - **Execution spawns → `model="sonnet"` at the spawn site** — the authoritative site list is `skills/_shared/model-tiering.md` §The rule, category 4 (do not re-enumerate it here; it drifts). Each site receives its change and its file set already settled — by the orchestrator's decomposition or by a user approval gate — so the tier that decided has already run. A ceiling, not a floor: never above sonnet whatever the session runs, and below it whenever the orchestrator can name why this workload is smaller.
  - `/geniro:setup` Phase 4 verification subagent → `model="sonnet"` — a fixed check-and-report workload: it runs a set check list against the generated CLAUDE.md and emits PASS / DRIFT lines the orchestrator re-decides from, so output quality does not scale with orchestrator tier (`skills/_shared/model-tiering.md` §The rule, category 2). Its read-only floor is stated in the spawn prompt itself; the Agent tool takes no per-spawn tool allowlist, so a tier defended by a claimed tool budget is defended by nothing.

---

## /plan (M5)

Renamed from /brainstorm; absorbs /decompose; produces canonical spec.md.

- Fixed 11-section spec.md schema — downstream consumers (`/implement`, `/review`) depend on this exact structure.
- Frontmatter gains optional `workflow_refs[]` (m5-v2 / m5-v3 schema) — tracker linkage (Linear / Jira / GitHub-Issues / Asana) persists from Phase 1 fetch through Phase 6 write. Per-entry shape: `{kind, issue_id, url, fetched_at, title?, suggested_branch?, status?, parent_ref?, siblings?, chain_fetched_at?}`; the m5-v3 enrichment extends `parent_ref` with `title?`/`status?`/`scope?` and adds `siblings[]?` + `chain_fetched_at?`. `m5-v3` is written only when chain enrichment is present. A further additive-optional block, `launch_config` (m5-v4), is described in the next bullet. Downstream readers accept `m5-v1` (treat field as absent), `m5-v2`, `m5-v3`, and `m5-v4`. Phase 1 assembles the related-task chain (parent epic + siblings + neighboring `milestone-N.md` files) via `skills/_shared/task-chain-context.md` and persists the tracker half into `workflow_refs[]`; the milestone half is derived from disk.
- Frontmatter also gains an optional `launch_config` block (m5-v4) — `/plan` can capture `/implement`'s launch settings (workspace / deep mode / branch-freshness / ship mode — plus, when the spec has a linked tracker ticket, whether to move that tracker task to In Progress at `/implement` kickoff) into the approved spec at Phase 8 so `/implement` runs without re-asking. SETUP-only by design: it never pre-authorizes the genuine safety gates (library adoption / runaway-scope escalation / ship to a shared branch), which still fire on a real event; the tracker-status pre-answer is a kickoff status transition inside `/implement`'s existing tracker-mutation authority, never a ticket creation. Additive-optional — absent = `/implement` asks interactively; the `tracker_status` key is a further additive-optional key WITHIN `m5-v4` (no version bump). Canonical contract `skills/_shared/launch-config-schema.md`.
- Phase 2 Visual Companion fires only on UI trigger (Phase 1 surfaced UI files OR topic carries UI noun) — calls `skills/_shared/ui-preview-gate.md` for a UI preview before any code is written; the approved text feeds Phase 5 sections 6 + 9. In artifact mode with a live page (`artifact_mode: true`, `artifact_status` not `unavailable`) the preview is a rendered HTML mockup published onto the plan page through the existing plan-artifact caller contract — three new rows in `skills/plan/loop-artifact-call-sites.md` (before-gate, per revision round, post-approval update), and the same max-3-round revision loop runs against the rendered page. The mockup never replaces the text: it ships with a compact digest covering the same six concerns (layout / components / interactions / responsive / accessibility / open questions), because sections 6 + 9 cite that text and a page URL is not citable substrate; the six headings become the mockup's required coverage rather than its output format. No extra opt-in — the artifact opt-in already covers publishing, and the unavailable/skip path falls back to the text form.
- Phase 4 §4.2 spawns independent codebase-grounded approach critics (`codebase-research-agent`) BEFORE the `Recommended` marker is set — the model that generated the approaches would otherwise rank them in the same context and re-confirm its own bias, so `Recommended` reflects feasibility evidence, not author confidence. Tier-scaled: Trivial/Small skipped, Medium 1 comparative critic, Big 1 per approach (parallel). An approach carrying a verified `blocking` risk is never `Recommended`; if every approach is blocked, Phase 3 re-enters with a tighter scope question. Advisory + fail-open — a failed critic spawn logs `## Errors` and ranking proceeds with a "stress-test unavailable" note. Verdicts carry into the Phase 4 chat message and `## Considered Alternatives`.
- Phase 5 section approval is grouped into 3 dependency-ordered cluster gates (Goal & scope: sections 1-3 / Approach & steps: sections 4-7 / Safety & done: sections 8-11) instead of one AUQ per section. Each cluster is authored as a unit and rendered to a full chat message in the Visual rendering language — progress tracker (`✔/●/○` over the approval journey), one-sentence opener, friendly per-section digests (lead sentence / Why with evidence cite / How it gets built / You'll see), a visual per section type, light heading icons — then gated by ONE lean AskUserQuestion per cluster (Approve all / Explain a section further / Revise specific sections → section-picker / Cancel; Explain is a reading aid that renders a deeper walkthrough, writes no approvals, and never counts toward the 3 revision rounds). The chat message is the rendering surface: the AUQ `preview` side-box is a narrow, truncating panel too small for digests, code, and diagrams — this is the message-first Gate presentation contract (`skills/plan/plan-loop.md` §"Gate presentation contract"). The visual language itself is canonical in `skills/_shared/gate-rendering.md` (shared with the finding gates of /review, /implement, /debug, /refactor); plan keeps its instantiation — the approval-journey stops and per-section cluster visuals — in plan-loop.md / plan-reference.md. Drops the questions the user answers at Phase 5 from ~11 (one per section) to 3 (one per cluster). Phase 3 / Phase 4 / Phase 8 follow the same contract — rich content renders to a chat message, then a lean AUQ captures only the decision; Phase 3 walks the design as a one-question-at-a-time grill — uncapped, bounded by a summarize-and-continue checkpoint, and every branch it closes without an answer is written into spec section 4 as a checkable predicate, which is what puts it in front of the Phase 7.5 verifiers.
- Cluster authoring is incremental in dependency order (author cluster N → render to chat → lean AUQ → on approve, author cluster N+1) — this preserves cross-section issue-catching while avoiding BOTH the over-gating of a per-section design (one low-content gate per section → click-through fatigue) AND the redundancy of re-asking each section after it was already rendered to chat (the lean per-cluster AUQ captures the whole cluster in one decision). Each section's pick still persists immediately to `approvals[]` under category `section_<id>` for compaction safety — granularity is unchanged (the per-cluster AUQ writes one entry per section it covers), only the AUQ delivery is grouped, so Phase 6.4 compaction re-author and the session-start restore hook need no change.
- Each user answer and approach pick is immediately persisted to `approvals[]` for compaction safety.
- Milestone-mode fires when task is classified Big: emits sibling `milestone-N.md` files alongside `spec.md`.
- Phase 7 mechanical validator runs 14 checks (adds `workflow_refs_consistency` and `launch_config_consistency`; retired the false-positive-prone `contradiction_heuristic` + `scope_creep_marker`, whose defect is caught by the Phase 8 human render / `/geniro:review` — `workflow_refs_consistency` warns when `.geniro/workflow/<kind>.md` missing; fails on structural field-presence violations; the shape check runs on m5-v2 OR m5-v3, skipped on m5-v1; on m5-v3 it also shape-checks the sibling/chain fields — `siblings[]`, `chain_fetched_at`, the enriched `parent_ref` — when present).
- Phase 7.5 runs a spec-challenge (`skills/_shared/spec-challenge.md` MODE: plan) between the mechanical validator and the Phase 8 human approval, on every run — re-verifies the spec's cited claims against live code and red-teams the chosen approach. The failure class it catches is the factually-wrong claim that reads as plausible prose, and it is the only gate in the loop that reads the spec's claims back against the code from a context that did not write them. `/implement` Phase 1 runs the same helper pre-edit and stays the backstop for a spec that went stale between planning and building. The pass generates no competing approaches: approach search is Phase 4's, with the user present. Cost is bounded by the spec's own cited-claim set (same-file claims cluster into shared verifier spawns per `finding-verification.md` §4's cap, never one verifier per sentence). `keep-with-modifications` folds fixes into the draft via the Phase 6 re-author loop and re-runs Phase 7; `re-plan` re-enters approach selection. Advisory + fail-open — it hardens the spec but never hard-blocks the human approval gate.
- No auto-commit — commit fires at Phase 8 (post-approve) only.

---

## /review (M6)

Reporter-only (never applies fixes, never mutates tracker status — that is `/plan` and `/implement` territory); absorbs /deep-simplify's reuse/quality/efficiency lens into the standard dimensions (architecture / conventions / optimizations).

- MANDATORY spawn list: 6 always-fire (bugs / security / architecture / tests / conventions / regressions) + 4 conditional (optimizations — skipped only on a docs/lockfile-only diff, a mechanical changed-file check recorded in the spawn declaration so §4.0 audits the skip / design / pr-metadata / spec-compliance) + N custom from `.geniro/instructions/review-extra/`. The always-fire 6 narrow under the Phase 1 §12 size boundary (>8 files OR >400 LOC) to `bugs` / `security` / `tests` / `conventions`, and expand to the full 6 at or over that boundary or whenever the Phase 1 §9-computed `risk-tier` reads high — `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-grid-scaling.md` is the canonical scaling table; it also covers `/implement` Phase 3's own grid, in a separate column keyed off `/implement`'s own `change_scope` signal rather than this boundary. Conditional dimensions are untouched by it. `conventions` reads all three of its criteria files — style rubrics + repo-modal patterns + authored-rule citations when the repo has rule files. The list is no longer permissive — Phase 2 step 2.2 declares `spawn_dims_declared[]` in state.md before the parallel batch, and Phase 4 §4.0 runs a post-spawn verification gate (declared-vs-actual diff) to catch silent skips. `/implement` Phase 3 carries the identical declare-then-verify pair over its own size-scaled dimension grid (`skills/implement/phase-3-ship.md` Step 1 "Declare the set before firing" / Step 2, checked once against Round 1's return only): a declared dimension missing from the return re-spawns once then reports `not-run` by name in the ship report, and a returned dimension absent from the declaration is dropped before its findings reach the fix loop — closing the same silent-substitution exposure in the one MANDATORY-spawn skill that didn't yet have it. The `regressions` dim (added in m6-v2) catches unintended deletes + behavior changes outside stated intent via 4 signals — deleted-symbol caller-blast, intent-vs-behavior over-reach (PLAN/PR/commit message as intent source), test-coverage delta, and parallel-path symmetry (a guard/filter/fix applied to one branch of a type/cadence split but not its parallel counterpart).
- Batched payload mode (>8 files or >400 LOC): the diff is organized into ~5-file groups as a reading order inside each reviewer's single spawn (highest-risk groups first and last) — never a spawn multiplier. Total reviewer spawns = declared dimension count in every mode; §4.0b verifies spawn instances == `spawn_dims_count`. Ruled 2026-07-08 after a 33-spawn dims×batches incident; concern-parallel-never-chunk-parallel is the industry-consensus shape (`skills/review/phase-1-triage-reference.md` §12).
- spec-compliance treats the spec as the **primary intent rubric but a fallible artifact**, not ground truth. Before flagging a diff omission as a defect, the reviewer grounds the divergence against live code (§Spec-premise validation in `skills/_shared/review-criteria/spec-compliance-criteria.md`): a divergence can mean the diff is wrong (standard code-omission finding at normal severity) OR the spec is wrong (the code correctly departed from a stale spec premise). Spec-defect divergences cap at MEDIUM and route to `[INTENT-CHECK]` — the user decides whether to fix the spec or the code — never a HIGH/CRITICAL omission against the implementation. This mirrors the spec-challenge doctrine (`skills/_shared/spec-challenge.md`) used pre-approval in `/plan` (Phase 7.5, every run), pre-edit in `/implement` (Step 12.5, every spec-driven run), and pre-handoff in `/resolve` (Phase 4, `MODE: plan`): re-verify the spec's facts against code, never rewrite the spec, skip-when-clean. `reviewer-agent` Step 1.5 carries the same fallibility caveat for every dimension that reads PLAN CONTEXT.
- Phase 4.1 admits findings via a gate that deliberately does NOT try to estimate correctness. KEEP rule: `severity >= HIGH`, OR `severity == MEDIUM AND Evidence-Block present + properly formatted`, OR Path B (`Decision Type == PRODUCT-DECISION`, any severity). No tier-dependence — `risk-tier` changes nothing at admission. Both correctness-estimating signals were dropped once their evidence was actually checked. Verbalized self-confidence is a weak predictor and systematically overconfident (arXiv 2405.02917 — but note its real scope: GPT-3.5/4, LLaMA2, PaLM 2 and vision-language models on object counting, visual queries, and regression; it supports the direction only, NOT the Claude-specific "+25% at the 90%+ band" figure this line used to assert, and NOT a code-review setting). Cross-dimension agreement is no better: agreement predicts correctness weakly, and agreement between *correlated* samplers actively misleads by reinforcing shared errors (arXiv 2607.08065) — which is this system's exact case, since `architecture-criteria.md` §1.6 and `regressions-criteria.md` §4 deliberately carry the same mirror-gap rubric, so their agreeing is construction, not corroboration. Greptile's published experience points the same way: prompt-side severity rating failed to separate signal from nits, and a learned post-hoc filter is what worked. Correctness is instead decided at Phase 4.2 by a verifier that re-reads the cited code, under a high-stakes refutation guard — a `refuted` verdict on a CRITICAL or HIGH takes two independent verdicts to demote — because over-refutation (dropping a real bug) is the documented failure mode of LLM defect filters. Sub-threshold findings persist to a `## Deferred — sub-threshold` body section (structured D-entries with `File:`/`Why deferred:`/`Suggested fix:` since m6-v3); excluded from the PR and the fix list by default, with two user-elected exits — the §7 post drill's "Send all" and the §4.6 include-deferred gate chained after the "/geniro:implement findings" pick (picked entries promote into `## Findings` tagged `[USER-ELECTED]`, severity as scored, `approvals[]` category `deferred_inclusion`). The Confidence field and `convergence_count` are reported but gate nothing per `skills/_shared/severity-calibration.md` §4 — confidence renders beside the finding, convergence feeds deep mode's escalation predicate and the Phase 5.3 recurring-pitfall signal. Canonical severity rubric with INCLUDES + EXCLUDES per tier (CRITICAL/HIGH/MEDIUM/LOW) lives in the same reference file §1, consumed by `reviewer-agent.md` + every criteria file in `skills/_shared/review-criteria/` (12 files across the 10 dims — the merged `conventions` dim reads three); documentation/PR-description/cosmetic suggestions are explicitly LOW (never MEDIUM). Decision-type is an orthogonal admission axis: a finding tagged `[PRODUCT-DECISION]` is kept and surfaced — and, on a Post, inline-commented to its line — regardless of severity via §4.1 Path B (a LOW PRODUCT-DECISION is the user's call, not the reviewer's, mirroring `/refactor`'s always-WAIT PRODUCT-DECISION escalation); severity stays as scored, never inflated.
- Phase 4.2 verifies every §4.1 survivor (CRITICAL / HIGH / MEDIUM) via fresh `finding-verifier-agent` spawns clustered by cited file — up to 3 same-file findings per spawn, one independent verdict per finding; solo and sentinel findings spawn singly (no tier-scaling, no severity-scaling — every survivor verified regardless of `risk-tier`). A MEDIUM survivor carries an Evidence-Block-grade citation by admission and Loop Invariant #6 mandates Evidence at every kept severity, so survivors normally arrive with a concrete file:line to re-read; a CRITICAL or HIGH admitted on severity alone may arrive thinly cited, and supplying the missing quote is this step's job. Each verifier receives isolated context (its cluster's finding bodies + shared cited-code slice + 1-hop caller grep) NOT the full reviewer bundle — independence from the originating reviewer's framing prevents anchoring per multi-judge research. Verifier emits `Validation: confirmed | refuted | clarified` + `Recommended-action` + `Verification-confidence` (1-5) + `Verification-evidence` (literal file:line quote). Refuted findings demote to `## Filtered`; clarified findings update `Decision Type:` to the verifier's `Recommended-action`. Phase 6 §7.0 fail-closed guard now re-checks all 4 invariants (`open_questions[].status`, PRODUCT-DECISION `step0_status:`, kept-finding `Validation:`, `report_status: final`) before any `gh api POST /reviews` — defense-in-depth at the external-effect boundary. When no verifier ran for a survivor — spawn failure after the registration-ladder retry, or a deliberate orchestrator skip — the orchestrator assigns `Validation: unverified` — the finding stays in the report (fail-open) but is excluded from the PR post set and surfaced under `## Caveats`.
- `/review` authors nothing — the Phase 4.3 test-confirmation gate, the `## Authored Tests` handoff section, and the Phase 6 failing-tests push gate are gone; `reporter-boundary.md` §1 no longer carries an authored-test carve-out for this skill. Edge-case test authoring lives entirely in `/implement` Phase 3 and `/debug` Adversarial Mode now.
- Phase 1 Step 0 smart workspace setup (passive-detect → AUQ only when ambiguous); mirrors `/implement` Step 0 contract but without the workflow-status-mutation question.
- Re-review gate (Phase 1 §7, round ≥2 fresh re-run): always asks scope (whole PR vs only changes since last review = `prior-reviewed-head..HEAD`) + depth (Standard/Deep), never auto-decided or inherited from the prior round. A fresh `/geniro:review` re-invocation re-asks depth + scope; only a true compaction-resume (in-flight `state.md`) re-applies the run's picks — the workspace location re-applies on both (anti-relocation).
- Finding-decision gates (open-decision gate, Pre-gate, PR-comment per-finding gate) follow the shared message-first contract (`skills/_shared/per-finding-question.md` §"Message-first rendering") and render in the same visual language as `/plan`'s approval gates (`skills/_shared/gate-rendering.md`): the finding renders to a self-contained chat block first — decision-queue tracker when ≥2 decisions are queued, one-sentence opener, conversational digest with evidence cite (expanding reviewer shorthand into plain English), a visual per finding type (§Finding-type visual map) — then a lean AskUserQuestion captures the decision. The `preview` side-box is never the rendering surface (it truncates with no scroll and is often absent in interactive sessions). Same contract used by `/implement`, `/refactor`, `/debug`; it also covers the consolidated gates — `/review`'s Action gate renders a wrap-up message first, `/implement`'s fix-loop finding resolution and test-failure escalation render-first, `/debug`'s open-question pre-gate renders each entry as a rich block, and `/refactor`'s HIGH-risk step approval renders a steps-flow + per-step risk table before its lean question.
- Phase 1.5 mechanical pre-pass: lint / schema / secret scan + custom-reviewer discovery (the `review-extra/<slug>.md` set is resolved here so Phase 2 has zero cognitive load for it).
- `guidelines` + `rules-compliance` are folded into `conventions` — one always-fire dimension reading all three criteria files (style rubrics + repo-modal patterns + authored-rule citations when the repo has rule files). This supersedes the v3 un-merge that kept `guidelines` separate: the recall trade-off is accepted for spawn-cost reduction, and the distinct defect classes stay separated as criteria files inside the one dim.
- Cross-reviewer convergence at >=3 reviewers auto-promotes to a `pitfall` L2 entry.
- T2 handoff emitted at `from-review-<branch>.md` with structured `open_questions[]` frontmatter (status: `unresolved | resolved | wontfix`). 3-gate safety chain prevents posting or implementing with unresolved questions: Phase 6 Pre-gate (producer-side) + Pre-Post-PR guard (defensive, before `gh api` POST) + Consumer-side `/implement` Phase 1 Step 12 (refuses to leave Phase 1 with unresolved entries).
- All reviewer-agents inherit orchestrator tier (OMIT `model=`); user-authored custom reviewers may opt out via frontmatter declaration.

---

## /resolve

Executor over PR feedback: decides which comments are worth doing, applies those fixes, and closes the threads. It emits no spec and no handoff — the landed change is the deliverable.

- 3 phases: Fetch & Triage → Decide → Fix & Close.
- Reads an open PR's unresolved review threads (human + bot) AND failing CI checks via the read side of `skills/_shared/pr-threads.md`, and calls that file's write side itself once its ship gate answers. Phase 1 syncs the local checkout to the PR head before any analysis, so verdicts read the code the comments describe and the fixes land on the PR branch.
- The verdict IS the filter: `fix` (real, reachable, behavior-preserving — applied without asking), `ask` (alters something a caller could depend on, or cannot be confidently placed — goes to the decision gate), `answer-only`, `decline` with a reason (`wrong-claim` / `over-engineering` / `out-of-scope` / `regression-risk` / `too-large`) and an evidence-backed push-back.
- Verification is signal-gated, not always-on: a fresh `finding-verifier-agent` re-checks every `decline` before its reply is drafted — a public push-back is the verdict whose error the orchestrator cannot see — and every contested `fix`. An uncontested fix verifies itself by landing and passing its test. Tier scales the vote count only (`skills/_shared/deep-mode.md`).
- Two gates: one multi-select over the `ask` items (message-first render carrying all three groups — applying, needs-your-call, declining), and one ship gate authorizing commit → push → replies → thread resolution as a single chain. An ambiguous item adds its own single-item gate with the Explain-further and Challenge-this-comment aids.
- A thread resolves only once its fix is in the pushed diff; a `decline` thread gets its reply and stays open. CI items produce a fix and a report line, never a reply.
- Review comments are untrusted content (`skills/_shared/untrusted-content-defense.md`) — the load-bearing case in this plugin, since this skill turns them into edits and into posts under the user's account.
- State.md uses the session-bound subdir layout `.geniro/state/resolve/<slug>/state.md`, swept at terminal exit like the other session-bound skills.

---

## Build-vs-buy library reuse (cross-skill)

`skills/_shared/library-reuse-audit.md` is the canonical external-library build-vs-buy procedure — the registry counterpart to the in-repo `existing-abstraction-audit.md`, firing only after an in-repo NO-ANALOGUE result. A Step 0 language/stdlib capability check runs first, needs no package manifest, and ends the audit there when the language already covers the need. Three modes: `plan` (a textual build-vs-buy consideration in approach prose — no web-research spawn at plan time; a package is named only when it is already in the project manifest or user-named, otherwise the spec describes the capability generically), `implement` (research candidates on the codebase-explorer's NO-ANALOGUE components at Phase 1 Step 8.5, then a message-first confirmation gate before any adoption — `approvals[]` category `library_adoption`), and `review` (the architecture dimension §7.5 flags reinvented-wheel code, tagged `[PRODUCT-DECISION]`, detection-only; `/geniro:refactor` Phase 1 consumes this same detection-only mode for its NO-ANALOGUE smells). Decisions: candidate discovery (`implement` mode only) uses a top-level `general-purpose` web-research spawn (OMIT `model=`); the check is tier-gated (skip Trivial); the review side EXTENDS architecture-criteria rather than adding a new always-fire dimension (matching the /deep-simplify reuse-lens-absorption precedent). Safety: every candidate `implement`-mode research surfaces is existence-verified against the real registry before it is shown — language models hallucinate roughly 1-in-20 package names persistently and registrably ("slopsquatting"), so the confirmation gate is a supply-chain control, not just UX; never auto-install (installs go through the package manager; lockfile writes stay hook-protected). Language-agnostic: the ecosystem is detected from lockfiles (npm / PyPI / crates / Go / Maven / RubyGems); an npm-only assumption is a bug.

---

## /debug (M7)

3 phases: Investigate → Propose → Ship (escalates to `/implement`).

- Phase 0 Step 0.2 fires a conditional workspace AUQ (Mode INSPECT-HERE, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-chooser.md` §4) whenever the working tree sits outside a worktree — offering to debug in place, cut an isolated worktree, or cut a new branch, both creation paths at `HEAD` rather than the default-branch tip since relocating would change the code under investigation. The worktree option is always offered; its description states the cost (a fresh worktree checkout leaves uncommitted work behind, and that work is often the bug's own context) so the user weighs it, while the recommendation still favors the worktree on a clean tree and the branch on a dirty one — a branch cut at `HEAD` in the current worktree carries uncommitted work forward. Branch-derived paths key from the recorded pick, not a later branch re-read.
- Phase 1 STALL gate: 5 inconclusive steps → diagnose-by-missing-component AUQ over an 8-category taxonomy (≤4 options per call, chained).
- Phase 2 fix-loop gate: max 2 fix attempts; on third → AUQ.
- Adversarial Mode (verify-changes) is a co-equal parallel workflow; authors RED-phase tests inline in the same context, no subagent spawn.
- Phase 3 auto-emits L2 `diagnosis` with `ext.{symptom, root_cause, fix}`.
- T2 handoff carries a structured `authored_tests[]` frontmatter array (m7-v2+) alongside `open_questions[]`. Each entry pins the path + intent + F→P status of every reproduction test the run produced, so `/implement` Phase 1 Step 12 can extract, verify, and surface relocation suggestions for tests that exist in the debug source worktree but not the consumer's worktree. The handoff body's `**Reproduction test:**` (scientific) / `**Test file:**` (adversarial) lines remain as human-readable mirrors. Schema-version `m7-v1` legacy handoffs fall back to body-string parsing via `skills/_shared/debug-handoff.md`.
- Reporter-only: NEVER ships code (no `git push` / `gh pr create`). The reproduction test is the only on-disk deliverable; the handoff file is the channel.

---

## Deep mode (cross-skill `--deep`)

Opt-in quality mode on `/review`, `/plan`, `/implement`, `/debug`. Canonical contract: `skills/_shared/deep-mode.md`; each consumer's `deep-mode-reference.md` declares which phases deepen.

- Two independent layers: **recall** — run a generative stage 3× in parallel, then union + dedup BEFORE any cross-pass agreement signal is computed (otherwise a producer agreeing with itself inflates the signal); **precision** — one verifier per candidate by default, escalating to 3 independent verifiers aggregated by majority vote only on a contested or high-stakes call, where a single hallucinated vote cannot flip a disposition. An unparseable vote abstains (counts toward neither side); below 2 parseable votes, quorum fails → one fresh single-pass verifier.
- Runs inside an internal `Workflow(...)` with raw-JSON returns (never `agent({schema})` — the StructuredOutput call drops on long agents). Raises quality, never speed: under the concurrency cap, 3× the agents fill the same waves at ~3-5× token cost — which is why it is opt-in and never the default.
- Activation: `--deep` flag, or a Standard/Deep chooser folded into each skill's existing early AskUserQuestion (in `/debug`, which has no early always-fire gate, the chooser stays standalone except on the path where Phase 0's conditional workspace gate fires — there it batches into that gate's question instead). Persisted to `deep-mode:` frontmatter + `approvals[]` for compaction survival.
- Standard single-pass is the floor: a workflow failure degrades to single-pass with a plain-English caveat, never a hard stop. Deep mode changes pass count and aggregation only — every gate, boundary, and no-ship contract binds unchanged inside the workflow.

### Flags & presets

Every flag and modifier `/plan`, `/implement`, and `/review` accept — `--deep`, `--artifact`, `--plan <path>`, `--no-adversarial`, `--subagent-model`, the workspace / ship / `freshness:` modifiers, and the spec `launch_config` block — is cataloged in `skills/_shared/flags-reference.md`. Two kinds: a flag pre-answers a question, or changes what the run does and asks nothing either way (`--no-adversarial`, `--plan <path>`, `--subagent-model`). Neither reaches a safety gate — a pre-set is not consent for one, so the gates listed there (new-dependency adoption, runaway-scope, handoff open-questions, spec-challenge-on-drift, shared-branch ship, merge/rebase conflict) fire on their own trigger regardless of any flag.

---

## /refactor (M8)

3 phases: Plan → Apply → Verify. Zero-behavior-change guarantee.

- Adopts canonical 4-tier effort-scaling (Trivial/Small/Medium/Big).
- Core smell-detection and per-step execution run orchestrator-inline; Phase-3 review (`reviewer-agent`), on-demand `codebase-research-agent`, and the conditional backend-learnings read (`knowledge-retrieval-agent`, `SCOPE: learnings-backend`, only under a declared `## Memory Backend` block) use dedicated subagents.
- Blocked-step protocol: max 3 retries per step → mark BLOCKED and continue; >=30% blocked → escalation AUQ.
- PRODUCT-DECISION findings escalate to `/implement` via AUQ (always-wait, fixed option set).
- NEVER ships code — diff is the deliverable.

---

## /onboard + /investigate (M9)

Discovery surface; two skills.

- `/onboard` ≤50-file scan cap by default; expansion requires explicit AUQ approval.
- `/investigate` formalizes 5-step JIT retrieval cadence: classify → scope → select agents → run parallel → orchestrator re-verify.
- Phase 2 Codebase Analyst spawn IS `codebase-research-agent` (general-purpose plugin agent for cross-skill codebase research; `model: inherit`); Git Historian and Internet Researcher remain `general-purpose` Agent() spawns because of their distinct tool surfaces (git read-verbs / WebSearch+WebFetch).
- L2 trust label: `verified` for code-grounded, `retrieved` for WebFetch/WebSearch sourced.
- Both use M1 session-bound T1.5 layout (`state/<skill>/<slug>/state.md`).

`codebase-research-agent` is the cross-skill codebase-research substrate — used ad-hoc by `/plan`, `/debug`, `/implement` Phase 2, `/review` Phase 1, `/refactor` Phase 1, `/onboard` Phase 1 for any "map a subsystem / trace a flow / locate a definition" query that would otherwise flood the orchestrator's context with file contents. Replaces the built-in `Explore` subagent (Haiku-pinned, exposed to [anthropics/claude-code#38928](https://github.com/anthropics/claude-code/issues/38928) MCP-overflow bug). Canonical guidance + invocation contract: `skills/_shared/context-isolation-checklist.md` § Codebase research.

---

## /setup (M10a)

Singleton bootstrap; one state file at `state/setup/state.md`.

- Re-run mode runs a MIGRATION.md sweep before generating content — auto-fix then re-detect.
- Generated CLAUDE.md is project-specific only (tech stack, commands, conventions, domain) — no plugin info.
- Verification subagent runs the check set in `skills/setup/verification-checks.md`; 3-retry loop → AUQ escalation. Its read-only floor (Read / read-only Bash / Glob / Grep, no Write or Edit) is stated in the spawn prompt — the Agent tool has no per-spawn tool allowlist to express it.
- Detect phase is observation-only; Write/Edit forbidden until Generate phase.

---

## /instructions (M10b)

Stateless CRUD over `.geniro/instructions/` (L4 procedural layer).

- No state file — every invocation is a single transaction.
- `validate`'s full lint rule set (structural, reference, and per-scope checks, plus `## Data Sources`, `## Verification Surface`, `## Memory Backend`, description-quality and `requires-context` rules) is canonical in `skills/instructions/mode-validate.md` §Step 2 — cite it rather than re-enumerating; the 300-line soft cap (env-overridable via `GENIRO_INSTRUCTIONS_MAX_LINES`) is one entry in that set.
- 13 scopes: `global`, `code-style`, `memory` (dedicated `memory.md`), `review-extra/<slug>`, and per-skill (implement, plan, review, debug, refactor, onboard, investigate, resolve, reflect).
- No subagent spawns — CRUD is too small for parallelism.

---

## /actions (M10c)

Stateless CRUD + runner over `.geniro/actions/`.

- `risk_class` (low/medium/high) is mandatory frontmatter. Run mode executes the action directly — invoking it is the authorization, so no confirmation fires; `risk_class` is metadata for the list view, delete warning, and lint.
- Tool-scope intersection in run mode: action's `allowed-tools` ∩ skill's `allowed-tools`.
- L2 `discovery` emit fires on successful runs where `external-send: true`.
- `risk_class` is manually author-picked (Q4 of the create interview) — no auto-elevation from tool surface. The lint's one enforced coupling: `external-send: true` requires `risk_class: medium` or `high`.

---

## /audit-instructions

Consumer-facing adaptation of the repo-local `/audit-plugin` pipeline: audits every AI-assistant instruction surface in the consumer repo (Claude Code files, `AGENTS.md`, Cursor, Copilot, Windsurf, Cline, Gemini, Aider, Junie, Zed, Amazon Q, `.geniro/instructions/`), then applies user-approved fixes.

- Same pipeline spine as the plugin audit: deterministic pre-pass → parallel dimension reviewers (accuracy / consistency / bloat / structure / coverage-safety, inherit tier) → orchestrator re-verification of every cited line → tiered report → action gate → `sonnet`-pinned fix agents with disjoint file allowlists, 1 fix round.
- The machinery both audits run identically — the reviewer finding schema and the fix-round discipline — is single-sourced in `skills/_shared/audit-pipeline.md`; each skill's reference keeps only its domain specifics beside the citation.
- The rubric is self-contained in `skills/audit-instructions/dimensions-reference.md`: the plugin repo's `.claude/rules/*.md` rubric files do not ship to consumers, so the principles are distilled into the shipped reference rather than cited.
- The dated report persists at `.geniro/state/audit-instructions/report-<date>.md` — outside the slug dir deliberately, so it survives the slug cleanup and seeds the next run's do-not-flag list (health-summary endorsements + still-open T0-T2 carry).
- Secrets invariant: a credential found in an instruction file is cited by location and shape only; the value never enters findings tables, the report, chat, or state files.
- `.geniro/instructions/*.md` are in scope for every dimension, but per-file structural lint routes to `/geniro:instructions validate` — single owner, no duplicated lint.
- State: `.geniro/state/audit-instructions/<slug>/state.md` per `within-skill-state-handoff.md` (enumerated producer); reviewer findings persist per spawn label so resume never re-spawns completed reviewers.

---

## /update (M10d)

Stateless update wrapper + integrity check + MIGRATION.md reader.

- MIGRATION.md walk is per-entry, one AUQ per step; "Fix it for me (Recommended)" as first option.
- User-content survival check: hash-check `.geniro/instructions/` and `.geniro/actions/` after update.
- Network errors use 4-retry exponential backoff (2s/4s/8s/16s); after 4 → abort.
- Restart-session warning always emitted after successful update.

---

## Self-Learning (P-X8)

Three additional L2 entry types + score-based query ranking.

- `discarded_hypothesis`: emitted by `/debug` Phase 1; sliding-window cap 5 per scope.
- `user_rejected_suggestion`: emitted by `emit-rejection.sh` after qualifying AUQ resolution.
- `retry_failure_sequence`: emitted when retries >=2 in `/implement`, `/debug`, `/refactor`.
- Score-based ranking: recency × trust × access-count × recurrence. A learning's `recurrence_count` (incremented on each dedup-key re-emit by `emit-learning.sh`; absent treated as 1) folds in as a log-dampened factor `1 + ln(max(n,1))`, so absent/1 has no effect. Stale-candidate entries auto-archived at SessionStart; criteria owned by `lib/archive-stale.sh` (spec: `skills/_shared/archive-stale.md` §Criteria) — read the numbers from there, not here.

---

## Idle-window overlap (cross-skill)

Long-running skills overlap a background research/critic spawn's wait with provably-independent work instead of blocking idle, per `skills/_shared/idle-overlap.md`. Wall-clock collapses from `agent + other` to `max(agent, other)`.

- Two shapes: **A** — spawn the agent(s) `run_in_background: true` and, during the wait, fire a user question whose answer does not depend on the agent's output (the user reasons while the agent computes); **B** — co-fire mutually-independent agents that feed the same gate in one response.
- Eligibility is strict: provably independent (dependency-DAG regime), never speculative; agent spawns only, never a fire-and-forget shell command. The contract's anchors: visible spawn + drain-before-dependent-step + reconcile-against-live-state at the drain + unconditional echo.
- Applied: `/plan` Phase 1 explore ↔ code-independent grill questions (Shape A); `/implement` Phase 1 knowledge-retrieval / codebase-explorer ↔ review/debug handoff open-questions (Shape A, handoff runs only — the common no-handoff run is unchanged). Shape B remains available wherever mutually-independent agents feed one gate.
- Forbidden past Edit/Write-gating gates, Always-WAIT safety gates, and reviewer/verifier batches whose output feeds the gate — those stay synchronous.

---

## On-demand improvement mining (/reflect)

Post-task project-rule mining is user-invoked, not ambient. `/geniro:reflect` spawns the read-only `reflection-agent` on demand over recent work — a diff, a finding set, session-transcript extracts, or (under `--this-session`) extracts from the session running now — and walks surviving candidates per `skills/_shared/improvement-routing.md` (§Candidate bar → §Routing table → §Presentation).

`/geniro:reflect` is the ONLY skill that proposes a project rule. No other skill drafts, routes, or offers a rule candidate, and none carries a recurrence-driven rule-capture offer: a rule prompt riding the tail of a plan, a debug session, a refactor, or an onboarding run interrupts the deliverable the user asked for, and the run that produced a lesson is the worst judge of whether it generalizes. Every other skill's durable output is its own learnings emit, which a later reflect pass mines. Adding a rule offer to another skill re-opens exactly this.

The fourth source splits collection from synthesis, and that split is the constraint any change here must keep. The running session exists only in the orchestrator's context, so no spawned analyst can read it and collection runs inline; synthesis stays in the isolated `reflection-agent` spawn, which is what keeps the agent's judgment free of the orchestrator's own account of the run. Inline collection is bounded to the user's verbatim corrections for the same reason — the orchestrator's summary of what it thinks it got wrong is self-assessment, not evidence.

---

## Optional MCP companions

Some skills unlock extra capability when a companion MCP server is present, and degrade gracefully when it is not — so a user installs only what they need.

| MCP | Used by | Enables | Install |
|-----|---------|---------|---------|
| **Playwright** (`mcp__plugin_playwright_playwright__*`) | `/geniro:implement` Phase 3 Ship sub-step, Pre-Ship Visual Verification | Screenshot loop at 375/768/1440, console and network sanity checks, keyboard-nav verification, smoke-test of the shipped change | Install the `playwright` marketplace plugin alongside this one. The `plugin_playwright_playwright__*` prefix is what Claude Code exposes when Playwright arrives from a sibling plugin. Absent it, the visual loop and smoke-test are skipped automatically. |

A companion MCP is never declared in this plugin's manifest — the user installs it as a sibling plugin. To see what is reachable in a given environment, look for the tool prefix in the agent's tool list at runtime.

The plugin agents also carry a broad `mcp__*` grant so a project-configured code-index or memory-backend MCP is reachable from a subagent without this plugin naming the server. That grant is read-only by contract: the inlined untrusted-content defense instructs agents to use MCP for read-only intelligence and never to call an egress or mutating MCP tool.

---

## Dual-runtime port (Cursor)

The repository ships as one plugin for two runtimes. `.claude-plugin/plugin.json` packages it for Claude Code, reading `skills/` and `agents/` directly. `.cursor-plugin/plugin.json` packages it for Cursor, pointing at `cursor/skills/`, `cursor/agents/`, and `cursor/hooks.json` — all generated ports under `cursor/`. Each runtime reads only its own manifest, so Claude Code's discovery (`agents/`, `hooks/hooks.json`) is untouched.

- **`cursor/skills/geniro-<slug>/` is generated, never hand-edited.** `scripts/build-cursor-skills.sh` derives it from `skills/<slug>/`, prefixing every name so Cursor registers `/geniro-<slug>` instead of a bare slug that can collide with a Cursor built-in skill or a reserved CLI command. Each generated directory carries the skill's siblings too — phase bodies, reference procedures, templates — so a host that cannot resolve `${CLAUDE_PLUGIN_ROOT}` still reaches the gates beside the SKILL.md it read; `skills/_shared/` and `agents/` stay at the root rather than being duplicated per skill. `tests/cursor/build-skills-fresh.sh` hard-fails CI on drift, same contract as the agents generator below.
- **Tool names are part of the dialect, not just skill names.** The same generator also rewrites the Claude Code tool names a SKILL.md body references (e.g. `AskUserQuestion` → `AskQuestion`) to the names Cursor's tool surface exposes. That reaches only the generated `cursor/skills/geniro-<slug>/SKILL.md` bodies — a Cursor run also reads `skills/**` phase bodies and `skills/_shared/*.md` helpers straight through the plugin root, and those are never generated, so the mapping still has to exist as a run-time resolution rule for the agent to apply itself: `skills/_shared/runtime-portability.md` §Tool substitutions.
- **`cursor/agents/*.md` are generated, never hand-edited.** `scripts/build-cursor-agents.sh` derives them from `agents/*.md`: it drops the Claude-only `tools` / `maxTurns` fields, translates the declared tier per `skills/_shared/model-tiering.md` §Runtime resolution (`inherit` stays `inherit`; a mechanical carve-out's concrete tier becomes Cursor's `auto` selector; anything the table cannot express fails the build), and sets `readonly` from the agent's write contract. An optional `GENIRO_CURSOR_SUBAGENT_MODEL` env var, read by the same script, substitutes a caller-named Cursor model id for `auto` on those mechanical/execution rows only — judgment-grade (`inherit`) agents are untouched, since that tier is the session model the user picks via `/model`, not a build-time setting. Editing an agent means editing `agents/*.md`, re-running the script, and committing both — `tests/cursor/build-agents-fresh.sh` regenerates into a temp dir and hard-fails CI on any drift, so a stale copy cannot merge.
- **`cursor/hooks.json` wires a subset of the hook scripts through `cursor/hooks/claude-hook-shim.sh`.** The shim is the single translation point between dialects: camelCase event names (`beforeShellExecution` / `preToolUse` / `sessionStart`) map onto the Claude Code events the scripts expect; Cursor's `{command, cwd}` shell payload and its alias keys are normalized into `{tool_name, tool_input}`; a script's `exit 2` block becomes `{"permission":"deny","agent_message":<stderr>}` + exit 0 so the guardrail reason reaches the Cursor agent instead of being dropped; and `hookSpecificOutput.additionalContext` is re-emitted as `additional_context`. One script set serves both runtimes with no fork; any other failure fails open, matching the scripts' own contract.
  - **Alias normalization is symmetric — path AND content.** Cursor renames both (`path` / `target_file`; `contents` / `code_edit` / `new_string` / `new_source`). Folding only the path key is a silent bypass: a content-reading guard such as the security pattern scan receives an empty field and exits 0 on a payload it would otherwise deny. Both folds are additive, so a MultiEdit payload still reaches a guard's own `edits[]` branch.
  - **The shim `cd`s into the payload's `cwd`.** Every guard resolves the project root and `.geniro/safety.json` by walking up from `$PWD` — none reads a `cwd` field. Building the field without moving into it leaves guards inspecting the wrong tree, which fails open.
  - **Degraded mode is loud.** When `jq` is absent the shim names the inactive guard through the event's message key rather than exiting silently, and forwards a hook's `systemMessage` on the shell and edit events too. Such a notice carries no `permission` key, so an informational message can never vote "allow" over another hook's deny.
- **One hook is deliberately unwired for Cursor** because the runtime has no compatible slot: the marketplace update check (Claude Code's `claude plugin` registry only). Its conventions apply as instructions per `skills/_shared/runtime-portability.md`. A new hook is added to `cursor/hooks.json` only when its event maps cleanly onto the shim's translation map.
- **Each runtime-portable SKILL.md file carries a runtime-portability preamble** that resolves the plugin root when `${CLAUDE_PLUGIN_ROOT}` is unset — restructuring a skill's top section keeps the preamble intact. The one exception is `/geniro:update`, which needs the `claude plugin` CLI and install registry: it carries no preamble and, invoked elsewhere, states that plainly and exits without side effects. `/geniro:reflect` carries a preamble and is portable in its `--this-session` shape, which reads no transcript file; only its past-session mining shapes (a search string, or an empty argument) are Claude-Code-only, because they depend on the on-disk transcript layout.
- **Both manifests carry the same version, bumped in lockstep by the release workflow** — a version skew between them would ship a Cursor install pinned to a different feature set than its Claude Code twin.

---

## Operational Rules

- Hook blocking requires `exit 2`, not `exit 1` — `exit 1` is fail-open.
- SKILL.md size is measured in words, not lines (`.claude/rules/skill-structure.md` §File-size limits): everything load-bearing belongs inside the first ~3,000 words, which is all Claude Code re-attaches after a compaction, and ~5,000 words is the whole-file guideline. Both are guidelines — past them, move detail to a sibling `*-reference.md` some runs genuinely skip, rather than trimming load-bearing content.
- Beyond ~150 total CLAUDE.md instructions, compliance degrades uniformly (context rot).
- Skills cannot call other skills — use shared reference files + subagent delegation.
- Subagents cannot spawn sub-tasks; all orchestration happens at the top-level skill.
- MCP auth (OAuth) is silently lost after compaction; scheduled tasks cannot access MCP.
- A pending direct user question is answered in the next assistant message, before status updates or operational gates (`skills/_shared/loop-invariants.md`).

## Lockstep file sets

Some contracts are described in more than one file by design — the schema in one place, the producer in another, the consumer in a third. Changing the shape, an enum value, the version rule, or the producer/consumer wiring means updating the whole set in the same change, or a later editor inherits an inconsistency with nothing to detect it. These lists are maintenance metadata for this repo, not runtime instruction: they live here rather than in the shipped helper.

**`launch_config`** — when its shape, an enum value, the version rule, or its producer/consumer wiring changes:

- `skills/_shared/launch-config-schema.md` — the canonical schema
- `skills/_shared/spec-template.md` — the frontmatter example carrying the block
- `skills/plan/validator-checks.md` — the shape-only enum check
- `skills/plan/loop-phase-8-user-approval.md` — the end-of-plan opt-in write (§8.3.5 capture, §8.4's launch-config enum assertion)
- `skills/plan/loop-phase-6-write-spec.md` — the `m5-v4` schema-version bump when the block is emitted
- `skills/plan/plan-auq-reference.md` — the opt-in question wording
- `skills/plan/plan-reference.md` — the `workflow_refs[]` / `launch_config` usage notes
- `skills/implement/phase-1-analyze.md` — the Step 0g read-and-apply path
- `skills/implement/implement-reference.md` — the `SPEC_LAUNCH_CONFIG` slot and the 0g field map
- `skills/review/SKILL.md` — the `m5-v4` acceptance in the `workflow_refs[]` frontmatter parse
- `skills/_shared/state-tier-spec.md` — the `geniro_schema_version` frontmatter row (spec.md's `m5-v4` bump documents the block)
- `skills/_shared/plan-context.md` — the plan→implement priming contract
- `skills/_shared/flags-reference.md` — the cross-skill launch-modifier rows
- `skills/_shared/workflow-refs-schema.md` — owns the rule that every reader accepting `m5-v1`..`m5-v3` must also accept `m5-v4`
- `skills/_shared/review-criteria/spec-compliance-criteria.md` — the PLAN CONTEXT section-tagged blob's `m5-v4` acceptance
- `lib/validate-plan-spec.sh` — hardcodes every `launch_config` enum value and the `tracker_status` key-presence guard
- this file — the cross-skill architecture overview
