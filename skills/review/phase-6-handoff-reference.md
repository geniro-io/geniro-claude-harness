# Phase 6 Action-Gate Hand-off Reference (M6 §18)

Detailed contract for `/geniro:review` Phase 6 (Action Gate Hand-off). Extracted из SKILL.md (D8 fix). SKILL.md retains а 2-3 line summary + а pointer here.

State.md `phase: action-gate` during this phase.

---

## 1. Reporter behavior — no fix loop (M6 H-2)

М6 confirms: /review does NOT apply fixes. Phase 6 hand-off message NEVER includes «I'll fix these now» language. The /implement option routes к /implement skill (manual or via Phase 6 hand-off line).

`--simplify` flag does NOT change this. The flag biases Phase 2 reviewer attention (М6 §8.3) но the output is still а finding list для consumption by other skills.

**Skip Phase 6 entirely когда:**
- `/geniro:review` is called as а sub-phase within `/geniro:implement` (parent owns its own fix loop).
- Zero actionable findings remain (CRITICAL + HIGH + MEDIUM all zero after Phase 4b).

---

## 2. Gate chain — fire each as а separate AUQ

Phase 6 surfaces up к 3 sequential top-level gates. Each one decides а different thing AND MUST be its own `AskUserQuestion` call — never collapse them into а single summary question, never paraphrase the question text, never merge options across gates.

**Firing order:**

1. **Step 0 — Open-decision (per finding):** fires once per `decision: PRODUCT-DECISION` finding kept by Phase 4 judge. Skipped когда zero PRODUCT-DECISION findings remain.
2. **Action (Always-WAIT):** fires once whenever this phase fires — the consolidated top-level decision. User picks ONE next step: /implement / Post Draft PR / Continue rounds / Skip.
3. **Failing tests:** fires once когда the state file's `## Authored Tests` section is non-empty — picks the commit policy for AI-authored tests. Firing order relative к Action gate conditional:
   - **Action == Post AND `## Authored Tests` non-empty:** Failing-tests fires BEFORE the Post drill (GitHub reviews API rejects comments whose `path` is absent от `commit_id`'s tree).
   - **Action != Post OR `## Authored Tests` empty:** Failing-tests fires AFTER Action gate's path completes.

Sequential: do not fire gate N+1 until gate N's answer is collected.

---

## 3. Step 0 — Open-decision gate (per-finding, Always-WAIT)

Before recommending which skill к run, surface every `decision: PRODUCT-DECISION` finding kept by Phase 4 judge к the user — they pick the resolution path; orchestrator NEVER picks on their behalf. The orchestrator must not auto-resolve multi-path findings even когда the reviewer's `recommendation:` field appears obvious.

**For each kept finding с `decision: PRODUCT-DECISION` (read от state file):**

1. Read the finding's `Options:` sub-list AND body sub-fields (`evidence:`, `why-matters:`, `suggested-fix:`).
2. Fire `AskUserQuestion` per the canonical shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Single-finding gate. Set `header: "Open decision"`. Render the `question` text с finding's severity / `path:lines` / short-title / decision-type / `why-matters` line per spec's Source-field map; render each option's `label`+`description` от finding's `options:` sub-list bullets; render each option's `preview` с finding body (Evidence / Suggested-fix / Confidence / Origin). Do NOT collapse rendering к label + 1-line description.
3. Update finding line в the state file: replace `recommendation:` field с user's chosen option text. Preserve `options:`, `evidence:`, `why-matters:`, `suggested-fix:`. The state file is the handoff к the next skill, so the chosen path AND the body travel с the finding.

When more than 4 PRODUCT-DECISION findings exist OR а single finding's `Options:` carries `(more-options-exist: chain-follow-up)`: chain `AskUserQuestion` calls per cap-extension pattern.

Always-WAIT в every mode. If empty answer returns, fall back к plain text и re-ask — never default к the reviewer's synthesis.

Skip entirely когда zero PRODUCT-DECISION findings remain after Phase 4 judge.

---

## 4. Action gate (Always-WAIT)

The consolidated top-level decision. Use `AskUserQuestion` (do NOT print options as plain text) с header "Action". Mark the severity-recommended escalation option с " (Recommended)" в its label.

**Severity-driven recommendation:**
- Any CRITICAL OR ≥2 HIGH findings → `/geniro:implement` is "(Recommended)"
- 0 CRITICAL AND ≤1 HIGH findings → "Skip — keep findings on disk" is "(Recommended)"

**Question:** "How should I proceed с the N findings?"

**Options (≤4 per AUQ cap):**

- **/implement findings (Recommended когда CRITICAL/HIGH count >0)** — exit /review, suggest the next command `/geniro:implement .geniro/state/handoff/from-review-<branch>.md`. Pre-load findings от the state file.
- **Post Draft PR review** — present ONLY когда state file's `pr-ref:` is non-`none` AND at least one finding remains unposted (no `[POSTED-TO-PR]` tag от prior run). On selection, drill into granularity sub-question (Step 2 below) before any `gh api` call. Posting is an external write к а public surface — the skill never posts без explicit approval; picking this option IS the approval.
- **Continue rounds (re-review)** — when round ≥3 fires Round-N escalation gate (§5 below); otherwise loops back к Phase 1 increment round counter.
- **Skip — keep findings on disk** — terminal exit; user can resume later.

When `pr-ref: none` OR zero unposted findings, "Post" is omitted. The Action gate is mutually exclusive — user chooses ONE path.

**Persist user pick к `approvals[]`** с category `action_gate` (M3 §6 Block 5d compaction-safe — P-M1-1 resume-safe).

Do NOT auto-invoke /implement — surface the suggestion only. The user runs the slash command themselves; the state file path is the handoff channel.

---

## 5. Round-N escalation gate

When round ≥3 AND user picks «Continue rounds», fire а secondary AUQ:

- **Continue (round 4)** — re-enter Phase 1 с round counter incremented; risk of infinite loop if user picks repeatedly (capped at round 5 hard ceiling — round 6 attempts auto-trigger «Escalate к user»).
- **Escalate к user — structured handoff** — terminal `escalated` state; writes а structured «next steps» summary к chat AND к state.md `## Open Questions`.
- **Abort** — terminal `aborted` state; `## Termination reason: repeated-failure: round-limit-3`.

Persist user pick к `approvals[]` с category `round_n_escalation`.

---

## 6. Failing-tests gate

Fires when `## Authored Tests` section is non-empty. Firing order conditional per §2 gate chain.

- **Header:** "Failing tests"
- **Question:** "How should the N failing tests authored by Phase 4c be handled? They are AI-authored — review before merging. If you just chose к post findings as а Draft PR review, the comment bodies reference these test files by path — pushing them к the PR's branch is what makes those references resolve для PR reviewers."

**Options:**
- "Commit failing tests on current branch" — orchestrator stages only the test files listed в `## Authored Tests` (never `git add -A` / `git add .`), composes а commit message following the repo's commit style (check `git log -5 --oneline` first), и commits via HEREDOC. **Recommended в Standard mode и в TDD mode без а PR ref** — except когда user selected "Post" в Action gate, в which case commit+push is Recommended.
- "Commit + push к current branch's upstream" — same as commit-only, then `git push`. **Recommended в TDD mode когда а PR ref is present, и also Recommended в any mode когда user selected "Post"** — load-bearing, not cosmetic.
- "Leave uncommitted" — tests stay on disk для user к review и stage manually.

Never use `--no-verify`, `--amend`, или destructive flags. If а pre-commit hook fails, surface the failure и stop — do not retry или bypass.

Persist user pick к `approvals[]` с category `failing_tests_commit_policy`.

---

## 7. Action == Post drill (PR-ref input only)

When user picked "Post" в the Action gate:

1. If `## Authored Tests` is non-empty: fire Failing-tests gate FIRST (push lands before `gh api` POST).
2. Continue с Steps 1.5-6 below.

When Action != Post или Post option was omitted, skip Steps 1.5-6 и proceed к Failing-tests (когда applicable) и cleanup.

### 7.1 Step 1.5 — Resolved-thread dedup (input-side filter)

Before showing eligible findings к the user, exclude findings whose `path:lines` overlaps an entry в the state file's `resolved-threads-snapshot:`. Overlap rule: finding `<P>:A-B` overlaps а snapshot entry `<Q>:L` когда `P == Q` AND `A <= L <= B`. Path equality is required.

For each matching finding, append `[ALREADY-RESOLVED-ON-PR]` к its tag list и add `reason: already-resolved-on-pr` annotation when moving к `## Filtered`. The Step 2 granularity AUQ и Step 3 per-finding gate count only non-excluded findings.

When Step 1.5 empties the post set, fall back к Skip semantics — do not call `gh api` POST; surface `All eligible findings overlap already-resolved threads — nothing drafted on PR` once в chat.

### 7.2 Step 2 — Granularity gate

Chain а follow-up `AskUserQuestion` с header "Post mode":

- **Question:** "Send all kept findings в а single batched review, или pick which ones к post?"
- **Options:**
  - "Send all (Recommended)" — single batched review event minimizes per-finding AUQ calls и dodges secondary rate limits с а single POST.
  - "Pick one-by-one" — chained `multiSelect` prompts; you choose which findings к include.

### 7.3 Step 3 — Per-finding gate

Fires only on "Pick one-by-one". Iterate over the eligible-findings list (filtered by Steps 1.5 + 3.5 когда applicable). For each finding, fire ONE `AskUserQuestion` per canonical Single-finding gate shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md`. Calling-skill-set fixed menu: finding's own `Options:` is ignored; calling-skill menu is the three options below.

- **`header`:** `"Post finding?"`
- **`question`** (multi-line markdown, per Source-field map):
  ```
  **<SEVERITY>** `path:lines` — <short title> — decision: <type>

  **Why this matters:** <1-sentence impact от reviewer-agent's Why-this-matters: field>

  Post this finding к the PR as an inline comment, or skip?
  ```
- **`options[]`** (three fixed options):
  - "Post this finding" — adds finding к post set; iteration continues.
  - "Skip this finding" — omits; iteration continues.
  - "Stop posting (skip remaining)" — exit loop entirely; all unseen findings treated as Skip.
- **`preview`**: finding's full body block (Evidence / Suggested-fix / Confidence / Origin).

After loop completes (or user picked "Stop posting"), aggregated post set is the union of "Post" picks. If empty, treat as Skip и proceed без firing `gh api` POST.

### 7.4 Step 3.5 — TDD-mode post-set filter

When state-file `mode:` is `tdd`, filter the post set so findings с `decision: TESTABLE` lacking а `[CONFIRMED-BY-TEST]` tag are excluded (remain visible в local report; not posted к PR).

**Retained для posting в TDD mode:**
- (a) any finding tagged `[CONFIRMED-BY-TEST]`, regardless of decision-type.
- (b) any finding с `decision: PRODUCT-DECISION` или `INTENT-CHECK` (no executable behavior к gate on).
- (c) findings с `decision: FIX-NOW` AND which match the "Runtime-behavior classification" rule's NON-runtime branch (typo-class — no runtime behavior к test against — per Phase 4c §2.1).

When the filter empties the post set, fall back к Skip semantics; surface "TDD mode: no F→P-confirmed findings — nothing drafted on PR" once в chat. В Standard mode, this step is а no-op.

### 7.5 Step 4 — Post via the GitHub reviews API

Parse `<owner>/<repo>/<number>` от the state-file Summary's `pr-url`. Pass snapshotted `pr-head-sha` as `commit_id` — but see head-SHA freshness rule. ONE `gh api` call posts the entire review.

**Head-SHA freshness — re-fetch когда authored tests were just pushed.** When Failing-tests gate fired BEFORE this step AND user picked "Commit + push", the local push advanced the PR's head past `pr-head-sha`. Re-fetch:

```bash
gh pr view <pr-ref> --json headRefOid --jq .headRefOid
```

Use the returned value as `commit_id`. Also overwrite state file's `pr-head-sha:` с the re-fetched value. Without this re-fetch, API rejects comments whose `path` is not present в `commit_id`'s tree с `Validation Failed: path could not be resolved`.

**Split the post set:**
- Findings с `File: <path>` → inline `comments[]` array.
- Findings с `File: PR-METADATA` → top-level review `body` under `## PR Metadata` section.
- Findings с `File: SPEC-COMPLIANCE` → top-level review `body` under `## Spec Compliance` section.

```bash
jq -nc \
  --arg sha "<pr-head-sha-or-re-fetched-sha>" \
  --arg body "<concatenated-body: summary header + ## PR Metadata + ## Spec Compliance sections>" \
  --argjson comments '<comments-json — inline-anchored findings only>' \
  '{commit_id: $sha, body: $body, comments: $comments}' \
  | gh api --method POST "/repos/<owner>/<repo>/pulls/<number>/reviews" --input -
```

Omit `event` entirely от the jq payload — the review is created в PENDING state (visible only к the reviewer on github.com's "Finish your review" panel; no notifications fire until human submits). Never set `event` к `APPROVE`, `REQUEST_CHANGES`, или `COMMENT`. `event: "PENDING"` is INVALID; omission is the correct mechanism.

Each comment object:

```json
{
  "path": "<file path relative к repo root>",
  "line": <last line>,
  "side": "RIGHT",
  "start_line": <first line, ONLY when range spans multiple lines; OMIT для single-line>,
  "start_side": "RIGHT",
  "body": "**<SEVERITY>** — <description>\n\n**Recommendation:** <recommendation>"
}
```

**Persist non-resumable-action.** Append к state file's `non-resumable-actions[]` per M3 §8:

```yaml
non-resumable-actions:
  - action: pr-review-comment-batch
    completed-at: <ISO-8601>
    pr-ref: <owner>/<repo>#<num>
    finding-count: <N>
    comment-ids: [<id1>, <id2>, ...]
```

### 7.6 PR-comment body content rules (hard)

GitHub PR comments are public, audience-expanding output. The comment body MUST contain ONLY: severity badge, finding's plain-language description, recommendation, и (для `[CONFIRMED-BY-TEST]` findings) the appended `**Failing test:** \`<test-path>\`` line.

**MUST NOT** add к the body или top-level review body:
- Plugin branding (`Geniro`, `/geniro:` prefix, "Generated by …" footers).
- Decision-type tags (`[FIX-NOW]`, `[TESTABLE]`, `[PRODUCT-DECISION]`, `[INTENT-CHECK]`).
- Pipeline phase names (`Phase 4c`, `judge pass`, `relevance filter`, `test-confirmation gate`).
- Confidence numerics (no `*Confidence: NN%*`).
- State-file paths или schema references.
- User-decision artifacts (`user picked X`, `approved by user`).
- Internal tags (`[CONFIRMED-BY-TEST]`, `[CHALLENGED-BY-TEST]`, `[POSTED-TO-PR]`, `[NEW]`, `[PRE-EXISTING]`, `[ALIGNS-WITH-PLAN]`, `TRUNCATED`).

The reviewer-agent's `description:` и `recommendation:` fields go into the body verbatim — if they legitimately mention any of these strings about the code under review, they stand as-is. The rule constrains orchestrator body-composition, not reviewer findings about the code.

### 7.7 Step 5 — Persist `[POSTED-TO-PR]` markers

Parse POST response к extract review's `id` field. Second call к derive per-comment URLs:

```bash
gh api "/repos/<owner>/<repo>/pulls/<number>/reviews/<review-id>/comments"
```

Match each returned comment back к its source finding by `(path, line)`. For each matched comment, append `[POSTED-TO-PR]` к the finding's tag list и add `posted-to-pr: <html_url>` к the line в the state file. The idempotency contract: the next `/geniro:review` run against the same PR reads these markers и excludes already-posted findings.

If the GET fails (rate limit, transient error), persist `[POSTED-TO-PR]` markers без `posted-to-pr:` URLs — the dedupe contract holds (marker IS the key).

After markers persisted, surface ONE chat-surface line:

```
Drafted N findings as а pending review on <pr-url>. Open the PR и click "Finish your review" → Submit when ready — pending reviews are private к you и fire no notifications until submit.
```

### 7.8 Step 6 — Posting-failure semantics

If the `gh api` call fails (non-zero exit, HTTP error, missing scopes, secondary rate limit): surface the error verbatim к the user и stop — do not retry, do not fall back, do not bypass с `--no-verify`-style flags, do not silently downgrade к top-level `gh pr comment`. No partial state is written: leave per-finding `[POSTED-TO-PR]` tags off entirely so user can re-run cleanly after fixing the underlying issue. Mirrors М6 §11.3 fail-closed semantics.

Append к state file `## Errors`:

```yaml
- phase: persist
  stage: pr-review-comment-post
  error: <verbatim gh stderr>
  consequence: post-aborted-no-state-mutation
```

---

## 8. Empty-answer handling (universal)

If `AskUserQuestion` returns an empty answer at any prompt в Phase 6, fall back к plain text и re-ask once — never promote empty к а default Yes. After one re-ask, if still empty, treat as Skip и proceed без posting.

---

## 9. Terminal state mapping

Per M6 §2.1.1:

| User pick | Terminal state | `## Termination reason` body |
|---|---|---|
| /implement findings | `done` | (omitted) |
| Post Draft PR review (successful POST) | `done` | (omitted) |
| Post Draft PR review (POST failed) | `aborted` | `tool-unavailable: gh-api-post` |
| Continue rounds → Round-N → Abort | `aborted` | `repeated-failure: round-limit-3` |
| Continue rounds → Round-N → Escalate | `escalated` | (omitted; surfaced в `## Open Questions`) |
| Skip — keep findings on disk | `done` | `modifier-exit: skip-action` |

M3 SessionStart hook surfaces `## Termination reason` on resume so model и user see context, not bare «aborted».
