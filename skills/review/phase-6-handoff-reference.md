# Phase 6 Action-Gate Hand-off Reference

Detailed contract for `/geniro:review` Phase 6 (Action Gate Hand-off). Extracted from SKILL.md (design fix). SKILL.md retains a 2-3 line summary + a pointer here.

State.md `phase: action-gate` during this phase.

---

## 1. Reporter behavior — no fix loop

This skill confirms: /review does NOT apply fixes. Phase 6 hand-off message NEVER includes «I'll fix these now» language. The /implement option routes to /implement skill (manual or via Phase 6 hand-off line).

`--simplify` flag does NOT change this. The flag biases Phase 2 reviewer attention but the output is still a finding list for consumption by other skills.

**Skip Phase 6 entirely when:**
- Zero actionable findings remain (CRITICAL + HIGH + MEDIUM all zero after Phase 4b).

---

## 2. Gate chain — fire each as a separate AUQ

Phase 6 surfaces up to 3 sequential top-level gates. Each one decides a different thing AND MUST be its own `AskUserQuestion` call — never collapse them into a single summary question, never paraphrase the question text, never merge options across gates.

**Firing order:**

1. **Step 0 — Open-decision (per finding):** fires once per `decision: PRODUCT-DECISION` finding kept by Phase 4 judge. Skipped when zero PRODUCT-DECISION findings remain.
2. **Action (Always-WAIT):** fires once whenever this phase fires — the consolidated top-level decision. User picks ONE next step: /implement / Post Draft PR / Continue rounds / Skip.
3. **Failing tests:** fires once when the state file's `## Authored Tests` section is non-empty — picks the commit policy for AI-authored tests. Firing order relative to Action gate conditional:
- **Action == Post AND `## Authored Tests` non-empty:** Failing-tests fires BEFORE the Post drill (GitHub reviews API rejects comments whose `path` is absent from `commit_id`'s tree).
- **Action != Post OR `## Authored Tests` empty:** Failing-tests fires AFTER Action gate's path completes.

Sequential: do not fire gate N+1 until gate N's answer is collected.

---

## 3. Step 0 — Open-decision gate (per-finding, Always-WAIT)

Before recommending which skill to run, surface every `decision: PRODUCT-DECISION` finding kept by Phase 4 judge to the user — they pick the resolution path; orchestrator NEVER picks on their behalf. The orchestrator must not auto-resolve multi-path findings even when the reviewer's `recommendation:` field appears obvious.

**For each kept finding with `decision: PRODUCT-DECISION` (read from state file):**

1. Read the finding's `Options:` sub-list AND body sub-fields (`evidence:`, `why-matters:`, `suggested-fix:`).
2. Fire `AskUserQuestion` per the canonical shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Single-finding gate. Set `header: "Open decision"`. Render the `question` text with finding's severity / `path:lines` / short-title / decision-type / `why-matters` line per spec's Source-field map; render each option's `label`+`description` from finding's `options:` sub-list bullets; render each option's `preview` with finding body (Evidence / Suggested-fix / Confidence / Origin). Do NOT collapse rendering to label + 1-line description.
3. Update finding line in the state file: replace `recommendation:` field with user's chosen option text. Preserve `options:`, `evidence:`, `why-matters:`, `suggested-fix:`. The state file is the handoff to the next skill, so the chosen path AND the body travel with the finding.

When more than 4 PRODUCT-DECISION findings exist OR a single finding's `Options:` carries `(more-options-exist: chain-follow-up)`: chain `AskUserQuestion` calls per cap-extension pattern.

Always-WAIT in every mode. If empty answer returns, fall back to plain text and re-ask — never default to the reviewer's synthesis.

Skip entirely when zero PRODUCT-DECISION findings remain after Phase 4 judge.

---

## 4. Action gate (Always-WAIT)

The consolidated top-level decision. Use `AskUserQuestion` (do NOT print options as plain text) with header "Action". Mark the severity-recommended escalation option with " (Recommended)" in its label.

**Severity-driven recommendation:**
- Any CRITICAL OR ≥2 HIGH findings → `/geniro:implement` is "(Recommended)"
- 0 CRITICAL AND ≤1 HIGH findings → "Skip — keep findings on disk" is "(Recommended)"

**Question:** "How should I proceed with the N findings?"

**Options (≤4 per AUQ cap):**

- **/implement findings (Recommended when CRITICAL/HIGH count >0)** — exit /review, suggest the next command `/geniro:implement.geniro/state/handoff/from-review-<branch>.md`. Pre-load findings from the state file.
- **Post Draft PR review** — present ONLY when state file's `pr-ref:` is non-`none` AND at least one finding remains unposted (no `[POSTED-TO-PR]` tag from prior run). On selection, drill into granularity sub-question (Step 2 below) before any `gh api` call. Posting is an external write to a public surface — the skill never posts without explicit approval; picking this option IS the approval.
- **Continue rounds (re-review)** — when round ≥3 fires Round-N escalation gate; otherwise loops back to Phase 1 increment round counter.
- **Skip — keep findings on disk** — terminal exit; user can resume later.

When `pr-ref: none` OR zero unposted findings, "Post" is omitted. The Action gate is mutually exclusive — user chooses ONE path.

**Persist user pick to `approvals[]`** with category `action_gate`.

Do NOT auto-invoke /implement — surface the suggestion only. The user runs the slash command themselves; the state file path is the handoff channel.

---

## 5. Round-N escalation gate

When round ≥3 AND user picks «Continue rounds», fire a secondary AUQ:

- **Continue (round 4)** — re-enter Phase 1 with round counter incremented; risk of infinite loop if user picks repeatedly (capped at round 5 hard ceiling — round 6 attempts auto-trigger «Escalate to user»).
- **Escalate to user — structured handoff** — terminal `escalated` state; writes a structured «next steps» summary to chat AND to state.md `## Open Questions`.
- **Abort** — terminal `aborted` state; `## Termination reason: repeated-failure: round-limit-3`.

Persist user pick to `approvals[]` with category `round_n_escalation`.

---

## 6. Failing-tests gate

Fires when `## Authored Tests` section is non-empty. Firing order conditional per gate chain.

- **Header:** "Failing tests"
- **Question:** "How should the N failing tests authored by Phase 4c be handled? They are AI-authored — review before merging. If you just chose to post findings as a Draft PR review, the comment bodies reference these test files by path — pushing them to the PR's branch is what makes those references resolve for PR reviewers."

**Options:**
- "Commit failing tests on current branch" — orchestrator stages only the test files listed in `## Authored Tests` (never `git add -A` / `git add.`), composes a commit message following the repo's commit style (check `git log -5 --oneline` first), and commits via HEREDOC. **Recommended in Standard mode and in TDD mode without a PR ref** — except when user selected "Post" in Action gate, in which case commit+push is Recommended.
- "Commit + push to current branch's upstream" — same as commit-only, then `git push`. **Recommended in TDD mode when a PR ref is present, and also Recommended in any mode when user selected "Post"** — load-bearing, not cosmetic.
- "Leave uncommitted" — tests stay on disk for user to review and stage manually.

Never use `--no-verify`, `--amend`, or destructive flags. If a pre-commit hook fails, surface the failure and stop — do not retry or bypass.

Persist user pick to `approvals[]` with category `failing_tests_commit_policy`.

---

## 7. Action == Post drill (PR-ref input only)

When user picked "Post" in the Action gate:

1. If `## Authored Tests` is non-empty: fire Failing-tests gate FIRST (push lands before `gh api` POST).
2. Continue with Steps 1.5-6 below.

When Action != Post or Post option was omitted, skip Steps 1.5-6 and proceed to Failing-tests (when applicable) and cleanup.

### 7.1 Step 1.5 — Resolved-thread dedup (input-side filter)

Before showing eligible findings to the user, exclude findings whose `path:lines` overlaps an entry in the state file's `resolved-threads-snapshot:`. Overlap rule: finding `<P>:A-B` overlaps a snapshot entry `<Q>:L` when `P == Q` AND `A <= L <= B`. Path equality is required.

For each matching finding, append `[ALREADY-RESOLVED-ON-PR]` to its tag list and add `reason: already-resolved-on-pr` annotation when moving to `## Filtered`. The Step 2 granularity AUQ and Step 3 per-finding gate count only non-excluded findings.

When Step 1.5 empties the post set, fall back to Skip semantics — do not call `gh api` POST; surface `All eligible findings overlap already-resolved threads — nothing drafted on PR` once in chat.

### 7.2 Step 2 — Granularity gate

Chain a follow-up `AskUserQuestion` with header "Post mode":

- **Question:** "Send all kept findings in a single batched review, or pick which ones to post?"
- **Options:**
- "Send all (Recommended)" — single batched review event minimizes per-finding AUQ calls and dodges secondary rate limits with a single POST.
- "Pick one-by-one" — chained `multiSelect` prompts; you choose which findings to include.

### 7.3 Step 3 — Per-finding gate

Fires only on "Pick one-by-one". Iterate over the eligible-findings list (filtered by Steps 1.5 + 3.5 when applicable). For each finding, fire ONE `AskUserQuestion` per canonical Single-finding gate shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md`. Calling-skill-set fixed menu: finding's own `Options:` is ignored; calling-skill menu is the three options below.

- **`header`:** `"Post finding?"`
- **`question`** (multi-line markdown, per Source-field map):
```
**<SEVERITY>** `path:lines` — <short title> — decision: <type>

**Why this matters:** <1-sentence impact from reviewer-agent's Why-this-matters: field>

Post this finding to the PR as an inline comment, or skip?
```
- **`options[]`** (three fixed options):
- "Post this finding" — adds finding to post set; iteration continues.
- "Skip this finding" — omits; iteration continues.
- "Stop posting (skip remaining)" — exit loop entirely; all unseen findings treated as Skip.
- **`preview`**: finding's full body block (Evidence / Suggested-fix / Confidence / Origin).

After loop completes (or user picked "Stop posting"), aggregated post set is the union of "Post" picks. If empty, treat as Skip and proceed without firing `gh api` POST.

### 7.4 Step 3.5 — TDD-mode post-set filter

When state-file `mode:` is `tdd`, filter the post set so findings with `decision: TESTABLE` lacking a `[CONFIRMED-BY-TEST]` tag are excluded (remain visible in local report; not posted to PR).

**Retained for posting in TDD mode:**
- (a) any finding tagged `[CONFIRMED-BY-TEST]`, regardless of decision-type.
- (b) any finding with `decision: PRODUCT-DECISION` or `INTENT-CHECK` (no executable behavior to gate on).
- (c) findings with `decision: FIX-NOW` AND which match the "Runtime-behavior classification" rule's NON-runtime branch (typo-class — no runtime behavior to test against — per Phase 4c).

When the filter empties the post set, fall back to Skip semantics; surface "TDD mode: no F→P-confirmed findings — nothing drafted on PR" once in chat. In Standard mode, this step is a no-op.

### 7.5 Step 4 — Post via the GitHub reviews API

Parse `<owner>/<repo>/<number>` from the state-file Summary's `pr-url`. Pass snapshotted `pr-head-sha` as `commit_id` — but see head-SHA freshness rule. ONE `gh api` call posts the entire review.

**Head-SHA freshness — re-fetch when authored tests were just pushed.** When Failing-tests gate fired BEFORE this step AND user picked "Commit + push", the local push advanced the PR's head past `pr-head-sha`. Re-fetch:

```bash
gh pr view <pr-ref> --json headRefOid --jq.headRefOid
```

Use the returned value as `commit_id`. Also overwrite state file's `pr-head-sha:` with the re-fetched value. Without this re-fetch, API rejects comments whose `path` is not present in `commit_id`'s tree with `Validation Failed: path could not be resolved`.

**Split the post set:**
- Findings with `File: <path>` → inline `comments[]` array.
- Findings with `File: PR-METADATA` → top-level review `body` under `## PR Metadata` section.
- Findings with `File: SPEC-COMPLIANCE` → top-level review `body` under `## Spec Compliance` section.

```bash
jq -nc \
--arg sha "<pr-head-sha-or-re-fetched-sha>" \
--arg body "<concatenated-body: summary header + ## PR Metadata + ## Spec Compliance sections>" \
--argjson comments '<comments-json — inline-anchored findings only>' \
'{commit_id: $sha, body: $body, comments: $comments}' \
| gh api --method POST "/repos/<owner>/<repo>/pulls/<number>/reviews" --input -
```

Omit `event` entirely from the jq payload — the review is created in PENDING state (visible only to the reviewer on github.com's "Finish your review" panel; no notifications fire until human submits). Never set `event` to `APPROVE`, `REQUEST_CHANGES`, or `COMMENT`. `event: "PENDING"` is INVALID; omission is the correct mechanism.

Each comment object:

```json
{
"path": "<file path relative to repo root>",
"line": <last line>,
"side": "RIGHT",
"start_line": <first line, ONLY when range spans multiple lines; OMIT for single-line>,
"start_side": "RIGHT",
"body": "**<SEVERITY>** — <description>\n\n**Recommendation:** <recommendation>"
}
```

**Persist non-resumable-action.** Append to state file's `non-resumable-actions[]`

```yaml
non-resumable-actions:
- action: pr-review-comment-batch
completed-at: <ISO-8601>
pr-ref: <owner>/<repo>#<num>
finding-count: <N>
comment-ids: [<id1>, <id2>,...]
```

### 7.6 PR-comment body content rules (hard)

GitHub PR comments are public, audience-expanding output. The comment body MUST contain ONLY: severity badge, finding's plain-language description, recommendation, and (for `[CONFIRMED-BY-TEST]` findings) the appended `**Failing test:** \`<test-path>\`` line.

**MUST NOT** add to the body or top-level review body:
- Plugin branding (`Geniro`, `/geniro:` prefix, "Generated by …" footers).
- Decision-type tags (`[FIX-NOW]`, `[TESTABLE]`, `[PRODUCT-DECISION]`, `[INTENT-CHECK]`).
- Pipeline phase names (`Phase 4c`, `judge pass`, `relevance filter`, `test-confirmation gate`).
- Confidence numerics (no `*Confidence: NN%*`).
- State-file paths or schema references.
- User-decision artifacts (`user picked X`, `approved by user`).
- Internal tags (`[CONFIRMED-BY-TEST]`, `[CHALLENGED-BY-TEST]`, `[POSTED-TO-PR]`, `[NEW]`, `[PRE-EXISTING]`, `[ALIGNS-WITH-PLAN]`, `TRUNCATED`).

The reviewer-agent's `description:` and `recommendation:` fields go into the body verbatim — if they legitimately mention any of these strings about the code under review, they stand as-is. The rule constrains orchestrator body-composition, not reviewer findings about the code.

### 7.7 Step 5 — Persist `[POSTED-TO-PR]` markers

Parse POST response to extract review's `id` field. Second call to derive per-comment URLs:

```bash
gh api "/repos/<owner>/<repo>/pulls/<number>/reviews/<review-id>/comments"
```

Match each returned comment back to its source finding by `(path, line)`. For each matched comment, append `[POSTED-TO-PR]` to the finding's tag list and add `posted-to-pr: <html_url>` to the line in the state file. The idempotency contract: the next `/geniro:review` run against the same PR reads these markers and excludes already-posted findings.

If the GET fails (rate limit, transient error), persist `[POSTED-TO-PR]` markers without `posted-to-pr:` URLs — the dedupe contract holds (marker IS the key).

After markers persisted, surface ONE chat-surface line:

```
Drafted N findings as a pending review on <pr-url>. Open the PR and click "Finish your review" → Submit when ready — pending reviews are private to you and fire no notifications until submit.
```

### 7.8 Step 6 — Posting-failure semantics

If the `gh api` call fails (non-zero exit, HTTP error, missing scopes, secondary rate limit): surface the error verbatim to the user and stop — do not retry, do not fall back, do not bypass with `--no-verify`-style flags, do not silently downgrade to top-level `gh pr comment`. No partial state is written: leave per-finding `[POSTED-TO-PR]` tags off entirely so user can re-run cleanly after fixing the underlying issue. Mirrors fail-closed semantics.

Append to state file `## Errors`:

```yaml
- phase: persist
stage: pr-review-comment-post
error: <verbatim gh stderr>
consequence: post-aborted-no-state-mutation
```

---

## 8. Empty-answer handling (universal)

If `AskUserQuestion` returns an empty answer at any prompt in Phase 6, fall back to plain text and re-ask once — never promote empty to a default Yes. After one re-ask, if still empty, treat as Skip and proceed without posting.

---

## 9. Terminal state mapping

Per
| User pick | Terminal state | `## Termination reason` body |
|---|---|---|
| /implement findings | `done` | (omitted) |
| Post Draft PR review (successful POST) | `done` | (omitted) |
| Post Draft PR review (POST failed) | `aborted` | `tool-unavailable: gh-api-post` |
| Continue rounds → Round-N → Abort | `aborted` | `repeated-failure: round-limit-3` |
| Continue rounds → Round-N → Escalate | `escalated` | (omitted; surfaced in `## Open Questions`) |
| Skip — keep findings on disk | `done` | `modifier-exit: skip-action` |

the SessionStart hook surfaces `## Termination reason` on resume so model and user see context, not bare «aborted».
