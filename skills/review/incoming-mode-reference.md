# Incoming Mode Reference

Incoming mode is a `/geniro:review` variant that processes reviewer feedback ON an existing PR — instead of authoring a new review (Outgoing mode, the existing default behavior). The user is the PR author; the skill helps them respond to comments left by another reviewer.

This file is the single source of truth for Incoming-mode procedure. SKILL.md cites this file; the per-step body lives here so SKILL.md stays under the line cap.

## Contents

- Activation paths
- Phase I — Incoming Mode Steps
- Skipped phases
- Edge cases
- Anti-rationalization
- Definition of Done

---

## Activation paths

There is **NO `--incoming` flag**. Mode resolution follows the natural-language signal pattern — bare keywords are not enough; a request only routes to Incoming when an explicit handling phrase is paired with a PR-ref anchor (detailed below). The Phase 1 Step 0 mode-detection block in SKILL.md routes:

- PR ref alone (`#1234` / PR URL) WITH unresolved review threads → fire `AskUserQuestion` (`Outgoing` / `Incoming`).
- Anchored natural-language signals that explicitly request incoming-handling → route to Incoming directly (skip the AUQ): `process review on #N`, `respond to review #N`, `incoming review #N`.
- All other shapes (empty / branch / file paths / diff range / PR ref without unresolved threads) → Outgoing.

The natural-language signals are **anchored** — bare keywords are not enough. "respond to feedback" without a PR-ref anchor is ambiguous and routes to Outgoing.

## Phase I — Incoming Mode Steps (runs INSTEAD of SKILL.md Phase 5/6 when mode=INCOMING)

The first 4 phases (Phase 1 triage, Phase 2 reviewer spawns, Phase 3 relevance filter, Phase 4 judge pass) are SKIPPED in Incoming mode — the diff is already reviewed by another human, the deliverable is responses, not new findings. Phase 4.3 (adversarial F→P) machinery is reused only for Step I-3 below. Steps:

### Step I-1 — Fetch reviewer feedback

Pull all unresolved review threads + general PR comments from the PR.

- Use `mcp__github__pull_request_read` to fetch PR metadata and the full thread/comment list. Fall back to `gh api /repos/<owner>/<repo>/pulls/<N>/comments` + `gh api /repos/<owner>/<repo>/issues/<N>/comments` when the MCP tool is unavailable (gracefully degraded — Incoming mode requires GitHub access; if both paths fail, surface the error verbatim and stop, mirroring SKILL.md Phase 1 `gh`-unavailable handling).
- Filter to threads where `isResolved == false` AND `isOutdated == false` AND inline-anchored review comments. Skip resolved threads. Skip outdated threads — the referenced code was rewritten and the thread is stale; classifying against current HEAD would mismap path:line and produce a misleading [WRONG] / [ACTIONABLE] verdict. When MCP is available, both this Incoming-mode filter and the Outgoing-mode K-count exclusion at SKILL.md Phase 1 Step 0 consume the same `reviewThreads` field from `mcp__github__pull_request_read`'s payload. When the REST fallback fires here (MCP unreachable), `isResolved` is unavailable per-thread (REST returns flat comments without thread grouping); the filter degrades to inline-anchored only, and the cross-path symmetry holds only on the MCP path — surface a one-line `Incoming-mode REST fallback — resolved-thread filter degraded` under `## Caveats` to inform the user.
- Persist the fetched payload to `.geniro/state/review-feedback/<slug>-incoming.md` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Slug rules. Headers: `Branch:` / `Worktree:` / `Timestamp:` per the producer contract. Body sections: `## Comments` (one block per comment with `id` / `path` / `line` / `author` / `body` / `commit_id`).

### Step I-2 — Per-comment classification

For each fetched comment, classify into one of four buckets — the orchestrator does the classification (no agent spawn; the comment text is short enough for inline reasoning):

| Tag | Meaning |
|---|---|
| `[ACTIONABLE]` | Reviewer points to a real defect; clear fix path. Routes to `/geniro:implement` in Step I-4. |
| `[QUESTION]` | Reviewer asks for clarification ("why this?"); no code change needed unless the answer reveals a defect. |
| `[AMBIGUOUS]` | Reviewer's intent is unclear (vague feedback, multiple interpretations). Defaults to clarification request. |
| `[WRONG]` | Reviewer's claim is factually incorrect against the actual code. Triggers Step I-3 F→P verification. |

**Mandatory Evidence Block per classification** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. The classification IS a claim about the codebase — and the standard's "every claim that requires evidence MUST attach this block" rule applies. For `[ACTIONABLE]` / `[WRONG]`, the evidence is a file:line citation with verified snippet (artifact kind 2) confirming the reviewer's claim is true / false. For `[QUESTION]` / `[AMBIGUOUS]`, evidence is the comment body itself (artifact kind 5 — user-provided artifact, the reviewer's text).

Write each comment's classification + Evidence Block back to the state file under `## Classification`.

### Step I-3 — F→P verification for [WRONG] claims

For every comment classified `[WRONG]`, reuse SKILL.md Phase 4.3 machinery to author a failing test that confirms the reviewer's claim is wrong (or, if the test fails, re-classifies the comment as `[ACTIONABLE]`).

- Spawn `adversarial-tester-agent` per the canonical contract — see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` for resolution + runtime degradation, and `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` for the six pre-inlined fields every spawn must satisfy.
- Hypothesis seeds: each `[WRONG]` comment becomes a seeded finding (`path:line — comment body — decision-type: TESTABLE — severity: HIGH`).
- The agent authors a failing test asserting the behavior the reviewer claims is broken. If the test passes on current code (`discarded-cannot-repro`), the reviewer's claim is verifiably wrong — keep `[WRONG]` classification. If the test fails (F→P verified by orchestrator independent re-run per SKILL.md Phase 4.3 Step 4), re-classify to `[ACTIONABLE]` and append `confirmed-by: <test path>` to the comment's state-file entry.
- Reuse SKILL.md Phase 4.3 Step 4 independent re-run + Step 6 fail-open semantics verbatim. Verification cache rules apply per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/verification-cache.md`.

### Step I-4 — Per-comment AUQ

Fire `AskUserQuestion` per comment per the canonical Single-finding-gate shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md`. Render the comment body, classification, file:line, and Evidence Block into the `question` payload. Use the same chained / multi-select / cap-extension pattern as SKILL.md Phase 6 Step 0 when more than 4 comments exist.

**Header:** `"Comment N of M"`. **Single-select** options:

- **`"Apply"`** — comment is actionable; dispatch to `/geniro:implement` with precise diff scope. Build the handoff: pre-load the comment body, file:line range, and any reviewer-cited expected behavior into the hand-off file `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` per the producer contract. Then surface the slash-command suggestion `Run /geniro:implement "<comment short title> [from review-feedback]"` in the chat output — do NOT auto-invoke; the user runs the slash command themselves.

- **`"Push back"`** — draft a `mcp__github__add_reply_to_pull_request_comment` reply explaining why the reviewer's claim is incorrect. Reply MUST cite codebase evidence (file:line snippet, test result from Step I-3, or a captured command output). **Forbidden phrases (verbatim from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` § Forbidden phrases):**
- `"you're absolutely right"`
- `"good catch"`
- `"great point"`
- `"nice"`

These four MUST NOT appear in any push-back draft — they capitulate to the reviewer's framing instead of correcting the record. The orchestrator scans the drafted reply for these tokens; if any appear, regenerate. The reply MUST attach an Evidence Block per the standard's schema (Command / Exit code / Tail), citing the artifact that proves the reviewer wrong (most commonly the F→P verification test from Step I-3, or a verified file:line snippet).

- **`"Ask clarification"`** — draft a clarifying-question reply via `mcp__github__add_reply_to_pull_request_comment`. The reply asks the reviewer for the missing detail (which file, which case, expected behavior). Render the draft to the user via the AUQ `preview` field for review before posting; on user confirmation, post via the MCP tool.

- **`"Defer"`** — annotate the state-file entry with `decision: defer` + a one-line rationale; no PR action taken. The user can re-invoke later to revisit deferred comments.

After the user picks, persist the choice to the state file under the comment's `## Classification` block as `decision: <Apply|Push back|Ask clarification|Defer>` plus the rendered reply body (for Push back / Ask clarification). Empty AUQ answer → fall back to plain-text re-ask once; treat second empty as Defer (mirrors SKILL.md Phase 6 universal empty-answer handling).

### Step I-5 — Resolve threads

After the user has shipped the fix (for `[ACTIONABLE]` comments routed to `/geniro:implement`), or posted the push-back / clarification reply (Push back / Ask clarification paths), call `mcp__github__resolve_review_thread` for each resolved thread. The state-file entry is updated to `resolved: true` so the next Incoming-mode invocation against the same PR skips already-handled comments (idempotency contract, mirrors SKILL.md Phase 6 `[POSTED-TO-PR]` markers).

For `Defer` decisions, do NOT resolve the thread — leave it unresolved on the PR so the reviewer sees it remains pending.

For `Push back` decisions, the thread is NOT auto-resolved by the skill — resolution belongs to the reviewer (they decide whether the push-back is convincing). The skill posts the reply and stops; the user / reviewer drives resolution from there.

## Skipped phases

Incoming mode SKIPS:

- SKILL.md Phase 2 reviewer spawns (no new findings being authored)
- SKILL.md Phase 3 relevance filter (no findings to filter)
- SKILL.md Phase 4 judge pass (no findings to judge)
- SKILL.md Phase 4.2 per-finding verifier (no findings to verify)
- SKILL.md Phase 5 state file (Incoming uses `.geniro/state/review-feedback/<slug>-incoming.md` instead)
- SKILL.md Phase 6 (Action gate, Failing tests gate, PR-comment posting — all replaced by Step I-4 per-comment AUQ)

Phase 1 worktree pre-flight + custom-instructions load + PR fetch + Phase 4.3 machinery (reused only by Step I-3) are the only SKILL.md sections that survive the Incoming-mode branch.

## Edge cases

- **Zero unresolved threads on the PR.** Mode detection routes to Outgoing automatically (the Step 0 fork in SKILL.md handles this).
- **PR has thousands of comments.** Apply the Step 1 filter (`isResolved == false` + inline-anchored). If > 50 unresolved comments survive, surface a warning to the user and require explicit `proceed` before fetching.
- **Reviewer's comment references a file outside the diff.** Honor the comment — Incoming mode is about responding to feedback, not validating the reviewer's scope. Step I-2 classifies it normally; Step I-4 routes to the appropriate decision.
- **`mcp__github__*` tools unavailable.** Fall back to `gh api` per Step I-1. If both fail, the Incoming mode cannot run; surface the error and stop.
- **F→P verification fails to spawn the agent.** Apply Phase 4.3 Step 6 fail-open semantics: do NOT auto-classify `[WRONG]` comments as `[ACTIONABLE]`; surface the fail-open caveat and proceed with the user's manual classification override at Step I-4.

## Anti-rationalization

| Reasoning | Why it's wrong |
|---|---|
| "Just apply every reviewer comment — they're the reviewer, they're right" | The classification step exists because reviewers are sometimes wrong. Auto-applying every comment ships fixes for non-bugs and burns engineering time. The Step I-3 F→P verification is the gate against capitulation. |
| "Use 'good catch' in the push-back — be polite" | Forbidden by the Evidence Standard. "Good catch" + push-back is internally contradictory — either the catch is good (Apply) or the claim is wrong (Push back, no flattery). The forbidden phrases prevent capitulation-disguised-as-politeness. |
| "Skip the Evidence Block on push-back drafts — the reasoning is in the body" | Push-back without Evidence Block is reasoning-from-the-diff, the exact failure the standard exists to prevent. The block IS the artifact that converts "I think you're wrong" into "this test demonstrates you're wrong". |
| "Auto-resolve threads after posting any reply" | Resolution is the reviewer's call (for Push back) or follows the fix (for Apply). Auto-resolving on Push back ships a "thread closed" signal the reviewer hasn't agreed to — politically rude AND removes the audit trail. |

## Definition of Done

Incoming mode is complete when:

- [ ] Step I-1: PR threads fetched and persisted to `.geniro/state/review-feedback/<slug>-incoming.md` with required headers
- [ ] Step I-2: Every fetched comment has a classification + Evidence Block in the state file
- [ ] Step I-3: Every `[WRONG]` comment was F→P-verified or the fail-open caveat was surfaced
- [ ] Step I-4: Per-comment AUQ fired for every classified comment; user choice persisted; push-back drafts contain zero forbidden phrases and carry an Evidence Block
- [ ] Step I-5: `mcp__github__resolve_review_thread` called for every Apply / Ask clarification thread the user confirmed as resolved; Defer / Push back threads left unresolved
