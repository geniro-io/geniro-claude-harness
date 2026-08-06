# /geniro:review Phase 6 §7 — the Post drill

Detailed contract for the Post drill: what happens after the Phase 6 Action gate's pick is
"Post Draft PR review". **Conditional — read this file only on that pick.** It is unreachable when
`pr-ref: none`, and every other Phase 6 path (report-only, hand off to `/geniro:implement`, abort)
completes without it.

Parent: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md`, whose §7 heading points here.
Section numbering is preserved — external files cite these anchors as `review-handoff.md §7.0`
through `§7.8`, and those citations resolve to the sub-sections below.

## Contents

- §7.0 — Unresolved-ambiguity guard (fail-closed, four invariants)
- §7.1 — Already-on-PR dedup (post-set filter)
- §7.2 — Granularity gate
- §7.3 — Per-finding gate
- §7.4 — Post via the GitHub reviews API
- §7.5 — PR-comment body content rules (hard)
- §7.6 — Persist `[POSTED-TO-PR]` markers
- §7.7 — Posting-failure semantics
- §7.8 — Post-posting overturn reconciliation

---

## 7. Action == Post drill (PR-ref input only)

When user picked "Post" in the Action gate:

1. If `## Authored Tests` is non-empty: fire Failing-tests gate FIRST (push lands before `gh api` POST).
2. Continue with §7.0-§7.8 below.

When Action != Post or Post option was omitted, skip §7.0-§7.8 and proceed to Failing-tests (when applicable) and cleanup.

### 7.0 Unresolved-ambiguity guard (fail-closed)

This re-read is a mandatory, explicit step that fires in the window between the Action gate's "Post" pick and the first `gh api POST /reviews` call — never earlier (an Action-gate-time read can go stale before POST) and never assumed-already-done. It is its own Bash read of the handoff; a Post drill that reaches §7.4 without a §7.0 read of state.md in that window has skipped the guard.

Before any of the Post-drill steps below fire, re-read state.md and verify FOUR invariants. If any fails, abort the Post drill — never post to GitHub with unresolved ambiguity, missing user picks, refuted findings baked in, or a provisional (un-finalized) report.

**Invariant A — no `open_questions[]` left `unresolved`.** The §2.5 Pre-gate runs first in Phase 6 and should leave zero entries with `status: unresolved` by the time Action gate fires.

**Invariant B — every PRODUCT-DECISION finding has `step0_status: resolved` (or `wontfix`).** The §3 Step 0 per-finding gate runs after §2.5 and flips each PRODUCT-DECISION finding's `step0_status: pending` → `resolved` once the user's AUQ pick lands. A finding still at `pending` here means §3 never fired for it — and §7.4 would route it to `comments[]` by `File:` sentinel alone, with either AUQ chip label (`"Open question"` from §2.5 or `"Open decision"` from §3) potentially leaking into the comment body as if it were a tag.

**Invariant C — every kept finding (CRITICAL / HIGH / MEDIUM) has `Validation: confirmed`, `clarified`, or `unverified`.** The Phase 4.2 per-finding verifier should filter `validation: refuted` findings before they reach the handoff. Any kept finding in `## Findings` carrying `Validation: refuted` indicates a producer-side filter failure; posting it to GitHub would surface a finding the verifier already judged incorrect. This guard re-checks at the external-effect boundary as defense-in-depth — refuted should never reach Post. `Validation: unverified` (orchestrator-assigned when the verifier failed to spawn, per finding-verification.md §4.5) is a legal value, not a violation — its disposition is per-finding: exclude the finding from the §7.1 post set (the same per-finding mechanism as `post-disposition: off-pr`) and surface a one-line warning that it was withheld because the verifier never ran. Missing `Validation:` on a CRITICAL / HIGH / MEDIUM finding (legacy handoff per §2 back-compat) is NOT a violation: treat as `confirmed` and proceed with the one-line warning. The guard rejects `refuted` and field-mismatch (values outside the four-value enum), not absence and not `unverified`.

**Invariant D — `report_status: final`.** The §3.5 finalize step flips the report from `draft` to `final` after the §2.5 Pre-gate and §3 open-decision gate clear. A report still at `draft` here means finalize never ran — a decision gate is open, or the flip was lost — and posting a provisional report to a public surface is the failure this guard prevents. Missing `report_status` reads as `final` (back-compat per the state-tier-spec single-source rule), so the guard rejects an explicit `draft`, not absence.

This §7.0 check is the fail-closed second line of defense for ALL FOUR invariants: if a producer wrote a new `open_questions[]` entry mid-phase, if `atomic_state_write` raced with a parallel resolver, if §3 was conflated with §2.5 / skipped under orchestrator drift, if Phase 4.2's filter pass dropped a `refuted` entry from the filter list but left it in `## Findings`, or if §3.5 finalize was skipped under drift and left the report `draft`, the upstream gates' invariants might not hold. Verify defensively.

**Procedure:**

1. Read state.md frontmatter via `Bash: cat ... | head` and parse `open_questions[]`. Read the `## Findings` body section, parsing each finding's `Severity:`, `Decision Type:`, `step0_status:`, AND `Validation:` fields — every kept finding, including an unchanged repeat from a prior round, lives there.
2. Build four filter lists: (a) `open_questions[]` entries with `status: unresolved`; (b) findings with `Decision Type: PRODUCT-DECISION` AND `step0_status: pending`; (c) findings with `Severity: CRITICAL | HIGH | MEDIUM` AND (`Validation: refuted` OR `Validation:` set to a value outside the `confirmed | refuted | clarified | unverified` enum — `unverified` is legal and handled per-finding at §7.1, never a whole-phase abort); (d) frontmatter `report_status` explicitly set to `draft` (missing reads as `final` — not a violation).
3. If any of the four lists is non-empty:
   - Surface a one-line chat warning naming the count of each non-empty list (e.g., `"Can't post yet: 2 open questions still need your answer + 1 finding needs a decision from you + 1 finding the verifier couldn't confirm."`) and the first 1-2 affected items.
   - Append a `## Errors` entry to state.md via `atomic_state_write` with `phase: action-gate`, `error: post-drill-aborted-on-unresolved-ambiguity`, the unresolved question IDs, the pending finding IDs, AND the refuted/invalid finding IDs.
   - Re-fire the §2.5 Pre-gate for any unresolved `open_questions[]` entries (if list (a) non-empty).
   - Re-fire the §3 Step 0 per-finding gate for any `step0_status: pending` PRODUCT-DECISION findings (if list (b) non-empty).
   - For list (c) refuted/invalid findings: do NOT auto-resolve. Refuted findings must be moved to `## Filtered` (with `reason: verifier-refuted`) by re-running Phase 4.2's filter pass — surface a chat instruction: `"Re-run /geniro:review to re-fire Phase 4.2 per-finding verification, OR manually move the refuted finding(s) to ## Filtered."` Then abort Phase 6 entirely (terminal state `aborted`, `## Termination reason: producer-schema-violation: refuted-finding-in-handoff`) — the user re-runs /geniro:review rather than racing a manual edit against a pending Post.
   - For list (d) (report still `draft`): re-run the §3.5 finalize step — it re-verifies lists (a) + (b) and flips `report_status: final`. If (a) / (b) are non-empty, finalize loops to their owning gates first.
   - After resolution loops for lists (a) + (b) + (d) complete, loop back to step 1 of this section. Do NOT proceed to §7.1 until step 3 finds ALL FOUR filtered lists empty.
4. When step 3 finds all four filtered lists empty, proceed to §7.1.

**Definition of Done (§7.0 guard):** the §7.0 guard ran between the action pick and any POST — verifiable as a Bash read of the handoff (`cat`/`head` of state.md) issued AFTER the Action gate recorded the "Post" pick and BEFORE the §7.4 `gh api POST /reviews` call. No such read in that window means the guard did not run; do not POST.

The four invariants are independent (different arrays, different gates, different producer phases), so the guard must check all four — checking only some leaves the remaining paths uncovered.

### 7.1 Already-on-PR dedup (post-set filter)

The post-drill's eligible-finding set is every unposted finding across `## Findings` (kept CRITICAL / HIGH / MEDIUM — including unchanged repeats from prior rounds — plus any LOW `PRODUCT-DECISION` admitted via §4.1 Path B; a `[USER-ELECTED]` promotion sitting in `## Findings` from a §4.6 include is an ordinary eligible unposted finding on a later Post — a promoted LOW carries no verification fields per the presence rules, which is not an exclusion reason) AND `## Deferred — sub-threshold` (awareness items — LOW plus any severity that failed every §4.1 admission signal) — once the user has chosen to post, severity no longer gates postability, and any exclusion is surfaced (`## Filtered` `reason:`, or `Validation: unverified` kept-in-place) like every other finding's. This step removes from the post set findings that already exist on the PR, so the user isn't asked to re-raise what's already there.

Safety invariant: every exclusion is surfaced — tagged and moved to `## Filtered` with a `reason:`, or (for verification exclusions) kept in `## Findings` with `Validation: unverified` as the recorded reason — never silently dropped. The user sees exactly what was withheld and why, so the post-set completeness guarantee (§7.2) holds.

Run THREE overlap checks against the snapshots the producer persisted to state.md frontmatter during triage — the field shapes and the `null` semantics are the snapshot-field contract in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §2.6. A `null` or absent snapshot means "nothing to dedup against" — skip that check rather than reading it as "no overlap".

1. **Resolved bot threads** (`resolved-threads-snapshot:`) — exclude findings whose `path:lines` overlaps a snapshot entry. Overlap rule: finding `<P>:A-B` overlaps a snapshot entry `<Q>:L` when `P == Q` AND `A <= L <= B`. Path equality is required. Tag `[ALREADY-RESOLVED-ON-PR]`, move to `## Filtered` with `reason: already-resolved-on-pr`.
2. **Unresolved bot comments** (`pr-bot-comments-snapshot:`) — these carry `path:line`, so apply the SAME range-overlap rule as check 1 (as precise). Catches a still-open CodeRabbit / other-bot finding the parallel reviewers re-discovered. Tag `[ALREADY-RAISED-ON-PR]`, move to `## Filtered` with `reason: already-raised-by-bot-reviewer`.
3. **Author / human formal reviews** (`pr-formal-reviews-snapshot:`) — these are free prose with NO line, so the range rule cannot apply. Use a CONSERVATIVE match: exclude ONLY when the finding's `path` basename AND a distinctive keyword from the finding's title BOTH appear in a formal-review body. Tag `[ALREADY-RAISED-ON-PR]`, move to `## Filtered` with `reason: likely-raised-in-author-review`. When the match is uncertain (path basename appears but no strong title-keyword hit), do NOT exclude — keep the finding in the post set, because a duplicate comment is a smaller harm than a silently withheld finding (§7.2 completeness wins ties).

Also exclude any finding carrying `post-disposition: off-pr` (set by the §3 open-decision gate when the user picked "Keep off the PR — I'll handle this"): append `[KEPT-OFF-PR]` to its tag list, move it to `## Filtered` with `reason: user-kept-off-pr`, and never place it in the inline `comments[]` or the body. This is the audience control for a decision residue the PR author cannot action — the decision is recorded for the reviewer, not posted to the PR.

Also exclude any finding carrying `post-disposition: no-action` (set by the §3 open-decision gate when the user resolved a judgment call with no code change, or set by the orchestrator when a finding it surfaced turns out to need no action): append `[NO-ACTION]` to its tag list, move it to `## Filtered` with `reason: no-action-needed`, and never place it in the inline `comments[]` or the body. A finding whose resolution is "leave the code as it is" gives the PR author nothing to do — posting it is noise on the review. Record the observation in the report so the trail survives, but keep it off the review the author reads.

Also exclude any finding carrying `Validation: unverified` (orchestrator-assigned at Phase 4.2 when the verifier failed to spawn — finding-verification.md §4.5): it stays in `## Findings` rather than moving to `## Filtered` — fail-open keeps it in the report — and the `Validation: unverified` field itself is the recorded reason for its absence from the post. Never place it in the inline `comments[]` or the body; surface the one-line warning ("N findings withheld from the post — the verifier never ran for them"), echoing the report's `## Caveats` note. Nothing lands on a public PR without an independent verification pass.

The §7.2 granularity AUQ and §7.3 per-finding gate count only non-excluded findings.

When §7.1 empties the post set, fall back to Skip semantics — do not call `gh api` POST; surface `All eligible findings were excluded (already on the PR, kept-off-PR, no action needed, or unverified) — nothing drafted on PR` once in chat.

Every kept finding posts, apart from these exclusions. The test-confirmation gate never filters the posted finding set — when it authored failing tests, each `[CONFIRMED-BY-TEST]` finding gains a `**Failing test:** \`<path>\`` line (per §7.5), but no finding is ever removed from the post set.

### 7.2 Granularity gate

**Non-skippable whenever the §7.1-filtered eligible set is non-empty.** Once the user picks "Post", severity does not gate postability — every eligible finding (CRITICAL / HIGH / MEDIUM / LOW / deferred) is in the post set unless it leaves via an accounted path: a user pick in this gate (or its §7.3 follow-up), a §7.1 dedup exclusion that wrote a `## Filtered` `reason:`, a §7.1 disposition exclusion (`post-disposition: off-pr` or `no-action`), or a §7.1 verification exclusion (`Validation: unverified` — the field itself is the recorded reason). There is no other path. The orchestrator never narrows the post set at §7.4 payload time on its own judgment — an unaccounted exclusion (a finding silently dropped with no user pick and no recorded reason) is the failure this gate prevents. The one skip is when §7.1 already emptied the set (handled above — Skip semantics).

Chain a follow-up `AskUserQuestion` with header "Post mode":

- **Question:** "Send all unposted findings (including LOW / deferred awareness items) in a single batched review, or pick which ones to post?"
- **Options:**
- "Send all (Recommended)" — single batched review event minimizes per-finding AUQ calls and dodges secondary rate limits with a single POST.
- "Pick one-by-one" — chained `multiSelect` prompts; you choose which findings to include.

**Definition of Done (§7.2 gate):** every finding in the §7.1-filtered eligible set either posts or left via one of the accounted paths listed above. Do not POST while any finding is unaccounted for.

### 7.3 Per-finding gate

Fires only on "Pick one-by-one". Iterate over the eligible-findings list (filtered by §7.1 when applicable — the test-confirmation gate applies no filter of its own). For each finding, fire ONE `AskUserQuestion` per canonical Single-finding gate shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md`. Calling-skill-set fixed menu: finding's own `Options:` is ignored; calling-skill menu is the three options below.

- **`header`:** `"Post finding?"`
- **Chat render (first):** render the finding to chat per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering — a self-contained block instantiating that template. The posting loop over ≥2 eligible findings is a decision queue, so each render opens with the tracker (`✔ Decision 1 — <short tag> · ● Decision 2 of N — <short tag> · ○ …`; the denominator is the eligible-finding count after the §7.1 filter). The user decides whether to post from an explained finding, not a side-box snippet.
- **`question`** (lean): the plain-English one-line title, then the ask:
```
<plain-English one-line title> — `path:lines`

Full explanation above. Post this finding to the PR as an inline comment, or skip?
```
- **`options[]`** (three fixed options):
- "Post this finding" — adds finding to post set; iteration continues.
- "Skip this finding" — omits; iteration continues.
- "Stop posting (skip remaining)" — exit loop entirely; all unseen findings treated as Skip.
- **`preview`**: leave empty or a one-line recap; the finding body lives in the chat block (§ Message-first rendering), not the side-box.

After loop completes (or user picked "Stop posting"), aggregated post set is the union of "Post" picks. If empty, treat as Skip and proceed without firing `gh api` POST.

### 7.4 Post via the GitHub reviews API

Parse `<owner>/<repo>/<number>` from the state-file Summary's `pr-url`. Pass snapshotted `pr-head-sha` as `commit_id` — but see head-SHA freshness rule. ONE `gh api` call posts the entire review.

**Head-SHA freshness — re-fetch when authored tests were just pushed.** When Failing-tests gate fired BEFORE this step AND user picked "Commit + push", the local push advanced the PR's head past `pr-head-sha`. Re-fetch:

```bash
gh pr view <pr-ref> --json headRefOid --jq '.headRefOid'
```

Use the returned value as `commit_id`. Also overwrite state file's `pr-head-sha:` with the re-fetched value. Without this re-fetch, API rejects comments whose `path` is not present in `commit_id`'s tree with `Validation Failed: path could not be resolved`.

**Split the post set.** Pick the side from the unified diff hunk the finding's line sits in: a line removed (`-`) in the hunk is LEFT (base side); an added (`+`) or context line of the new file is RIGHT; a line in no hunk routes to the body. Three file-finding routes, in order:
- (a) Findings with `File: <path>` whose line is present on the RIGHT (an added or context line of the new file, in the diff's `commit_id` tree) → inline `comments[]` array with `side:"RIGHT"`. Inline-anchor every such finding regardless of severity — a LOW finding on a changed line is still an inline comment, never a body bullet. Severity gates whether a finding is kept (Phase 4.1), not where a kept finding renders.
- (b) Findings with `File: <path>` on a DELETED line (present on the LEFT / base side of a diff hunk, removed by the PR) → inline `comments[]` with `side:"LEFT"` (and `start_side:"LEFT"` for a multi-line range). Using `RIGHT` here is exactly what triggers `path could not be resolved`, so a deleted-line finding sets LEFT — it does NOT fall to the body.
- (c) Findings with `File: <path>` whose line is in NEITHER side of any hunk (truly unchanged, outside the changed ranges, so the reviews API rejects the inline comment with `path could not be resolved`) → top-level review `body` under a `## Findings on unchanged lines` section, each rendered as `**<SEVERITY>** \`<path>:<line>\` — <description>` so the reader can still locate it. This is the ONLY sanctioned route for a real file-finding into the body — it exists because GitHub cannot anchor a comment to a line absent from both sides of the diff, not as a catch-all for findings the orchestrator would rather batch. A finding whose line is on the RIGHT or LEFT side of a hunk must never land here.
- Findings with `File: PR-METADATA` → top-level review `body` under `## PR Metadata` section.
- Findings with `File: SPEC-COMPLIANCE` → top-level review `body` under `## Spec Compliance` section.

```bash
jq -nc \
--arg sha "<pr-head-sha-or-re-fetched-sha>" \
--arg body "<concatenated-body: summary header + ## Findings on unchanged lines + ## PR Metadata + ## Spec Compliance sections>" \
--argjson comments '<comments-json — inline-anchored findings only>' \
'{commit_id: $sha, body: $body, comments: $comments}' \
| gh api --method POST "/repos/<owner>/<repo>/pulls/<number>/reviews" --input -
```

Omit `event` entirely from the jq payload — the review is created in PENDING state (visible only to the reviewer on github.com's "Finish your review" panel; no notifications fire until human submits). Never set `event` to `APPROVE`, `REQUEST_CHANGES`, or `COMMENT`. `event: "PENDING"` is INVALID; omission is the correct mechanism. /geniro:review never submits (publishes) the review it creates — submitting is the user's own action on github.com. This bars the separate submit endpoint too: never call `gh api --method POST "/repos/<owner>/<repo>/pulls/<number>/reviews/<id>/events"` (with any `event`) to publish a pending review — the create-call `event` omission and this endpoint bar are two faces of one draft-only rule. The bar holds across rounds: a round-2+ re-review also stops at PENDING and re-fires the action gate before posting; it never publishes a prior or current round's review. Publishing fires notifications to the PR author and is irreversible visibility — the user's decision, not the reviewer's.

Each comment object:

```json
{
"path": "<file path relative to repo root>",
"line": <last line>,
"side": "<RIGHT for an added/context line; LEFT for a deleted line>",
"start_line": <first line, ONLY when range spans multiple lines; OMIT for single-line>,
"start_side": "<same side as \"side\"; include only with start_line>",
"body": "**<SEVERITY>** — <description>\n\n**Recommendation:** <recommendation>"
}
```

**Persist non-resumable-action.** Append to state file's `non-resumable-actions[]`

```yaml
non-resumable-actions:
- action: pr-review-comment-batch
completed-at: <live clock read — $(date -u +%Y-%m-%dT%H:%M:%SZ) interpolated in the same write call, never a model-supplied or rounded value; atomic-state-write.md §Timestamp sourcing>
pr-ref: <owner>/<repo>#<num>
finding-count: <N>
comment-ids: [<id1>, <id2>,...]
```

### 7.5 PR-comment body content rules (hard)

GitHub PR comments are public, audience-expanding output. Each comment body opens with the severity badge per the §7.4 comment-object template (`**MEDIUM** — <description>`) and carries only these four things: the severity badge, the finding's plain-language description, the recommendation, and (for `[CONFIRMED-BY-TEST]` findings) the appended `**Failing test:** \`<test-path>\`` line. The orchestrator's internal finding handle (`M1`, `M1b`, `L5`, …) is a chat/handoff cross-reference only — it never prefixes or appears in a comment title, because the PR author has no map for `M1b`.

**Never add** to the body or top-level review body:
- Plugin branding (`Geniro`, `/geniro:` prefix, "Generated by …" footers).
- Decision-type tags (`[FIX-NOW]`, `[TESTABLE]`, `[PRODUCT-DECISION]`, `[INTENT-CHECK]`).
- AUQ `header:` chip labels echoed as if they were tags (`[Open question]`, `[Open decision]`). These literals are reserved for the §2.5 Pre-gate and §3 Step 0 AUQs that gate downstream action; echoing them in a PR comment body re-projects unresolved ambiguity onto the PR author, which is the exact failure mode those gates exist to prevent. If a finding reads as an open question, it has not completed §3 — abort the post and re-fire the gate per §7.0, do not relabel it for the PR.
- Pipeline phase names (`Phase 4.3`, `judge pass`, `relevance filter`, `test-confirmation gate`).
- Confidence numerics (no `*Confidence: NN%*`).
- State-file paths or schema references.
- User-decision artifacts (`user picked X`, `approved by user`).
- Internal tags (`[CONFIRMED-BY-TEST]`, `[CHALLENGED-BY-TEST]`, `[POSTED-TO-PR]`, `[NEW]`, `[PRE-EXISTING]`, `[ALIGNS-WITH-PLAN]`, `[USER-ELECTED]`, `TRUNCATED`).
- Internal finding IDs / orchestrator labels (`M1`, `M1a`, `M1b`, `M2`, `M3`, `L1`…`L7`, `F1`…, and any `<letter><digit>` handle assigned to enumerate findings in the chat summary or handoff). They exist only to cross-reference findings off the PR; the comment body opens with the severity badge, never a finding handle.
- Internal knowledge-base references — incident IDs (`incident 4`), learning IDs (`learning B.1.5`), and the project's internal incident-report cross-references (a `B.x.y`-style token when it is introduced by the word `incident`/`learning` or appears as a bare parenthetical cross-reference, e.g. `(incident 4 / learning B.1.5)`). These index a private incident log / learnings store the PR author cannot open, so the bare ID reads as noise. The `incident`/`learning` keyword or the parenthetical cross-reference shape is what identifies the pattern — a bare `<letter>.<digit>.<digit>` that is a genuine code fact under review (a spec section ref, a test-case ID, a version) is NOT this pattern and stands. Cite the failure mode in plain language ("the documented backdated-migration-ordering failure") and drop the parenthetical ID — or substitute a shareable link if the reviewer briefing carries one.

The reviewer-agent's `description:` and `recommendation:` fields go into the body verbatim — if they legitimately mention any of these strings about the code under review, they stand as-is. The rule constrains orchestrator body-composition, not reviewer findings about the code. **One class is the exception inside the verbatim fields: internal knowledge-base references** (the `incident N` / `learning X.Y.Z` / `B.x.y` patterns in the bullet above). Unlike a code symbol named `M1`, an incident/learning ID is never a fact about the code under review — it indexes a private log the reader cannot open — so it is scrubbed even mid-sentence in a reviewer's `description:`/`recommendation:`: strip the parenthetical ID (or swap in a shareable link) and keep the surrounding plain-language description intact.

**Secret redaction — before assembly (hard).** Before composing the `comments[].body` and top-level `body` strings, pipe every free-form segment bound for the PR — each finding's description, recommendation, and Evidence excerpt, plus the summary and section prose — through `redact_secrets` (`source "${CLAUDE_PLUGIN_ROOT}/lib/redact-secrets.sh"`; API in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/redact-secrets.md`). A finding that quotes a leaked secret must describe the leak's location (`path:line`), never reproduce the secret — a PR comment reaches a wider audience than the code and survives after the code is fixed, so a quoted credential re-leaks on a public surface. Redaction runs inside the verbatim `description:`/`recommendation:` fields too: the `[REDACTED:…]` placeholder still locates the leak, and the secret's literal value is never information the PR author needs.

**Enforcement — scrub before POST (hard).** §7.5 is otherwise advisory — an orchestrator naturally echoes its own finding handle (`**M1b …`), skill branding (`## /geniro:review …`), or a `handoff`/state-path reference into the composed title and summary, so the rules leak under drift. Before the `gh api POST /reviews`, scan the assembled top-level `body` and every `comments[].body` against the never-add set above; on a hit in orchestrator-composed text (comment title, summary header, section prose) strip or rewrite it and re-scan until clean — never POST a body that still matches. Match only the orchestrator-prepended title/prefix and the summary/section framing — never the verbatim `description:`/`recommendation:` segment a finding carries (a reviewer that legitimately writes "the `L2` cache" or names a code symbol `M1` stands; the leak vector is a handle in the *title slot*, `**M1b — …`, not a token mid-sentence). The lone exception is the internal knowledge-base cross-reference class (`incident N` / `learning X.Y.Z`, and a `B.x.y` token in that incident/learning context per the bullet above): scrub it wherever it appears, INCLUDING mid-sentence inside a reviewer's verbatim `description:`/`recommendation:` — replace the parenthetical ID with nothing (or a shareable link) and preserve the rest of the sentence. This is the external-effect-boundary analog of the §7.0 guard.

### 7.6 Persist `[POSTED-TO-PR]` markers

Parse POST response to extract review's `id` field. Second call to derive per-comment URLs:

```bash
gh api "/repos/<owner>/<repo>/pulls/<number>/reviews/<review-id>/comments"
```

Match each returned comment back to its source finding by `(path, line)`, and tag EACH matched finding individually:

1. For each returned comment, find its source finding by `(path, line)` equality.
2. Append `[POSTED-TO-PR]` to THAT finding's tag list and add `posted-to-pr: <html_url>` to THAT finding's line in the state file.
3. Repeat per comment — one `[POSTED-TO-PR]` tag per posted finding.

Per-finding tagging matched by path+line is the only valid form. A single aggregate marker (one `[POSTED-TO-PR]` written at the section or review level, or a prose note like "posted 8 of 12") is invalid — it leaves the individual findings untagged, so the next round's unposted-set computation (§7.1 reads per-finding `[POSTED-TO-PR]` markers) cannot tell which findings already posted and re-raises them. The marker IS the per-finding idempotency key; an aggregate marker has no key the dedup reads.

**Definition of Done (§7.6):** every finding that posted in this run carries its own `[POSTED-TO-PR]` tag on its own line — verifiable as count of `[POSTED-TO-PR]` tags added == count of comments in the POST response. No aggregate or section-level marker stands in for per-finding tags.

If the GET fails (rate limit, transient error), persist the per-finding `[POSTED-TO-PR]` markers without `posted-to-pr:` URLs — the dedupe contract holds (the per-finding marker IS the key). Match findings to posted comments by the `(path, line)` you sent in the POST payload, since the per-comment URLs are what the GET would have supplied.

After markers persisted, surface ONE chat-surface line:

```
Drafted <P> of <K> findings (<K1> kept, <K2> minor) as a pending review on <pr-url>; <W> withheld (<withheld-reason breakdown — e.g. 2 already on the PR, 1 kept off the PR, 1 needs no action, 1 the verifier couldn't confirm; omit any zero-count reason>). Open the PR and click "Finish your review" → Submit when ready — pending reviews are private to you and fire no notifications until submit.
```

`<K>` counts every finding eligible for the post set (§7.1) — `<K1>` counts `## Findings` entries (kept CRITICAL / HIGH / MEDIUM, plus Path-B LOW `PRODUCT-DECISION`s and `[USER-ELECTED]` promotions) plus `<K2>` counts `## Deferred — sub-threshold` entries, so `<K1>` + `<K2>` always sums to `<K>` over the §7.1 eligible set (counting only kept findings would undercount posted deferred entries). Omit the parenthetical split when `<K2>` is zero. `<W>` spans the same eligible set, so the withheld-reason breakdown covers kept and minor exclusions alike.

### 7.7 Posting-failure semantics

If the `gh api` call fails (non-zero exit, HTTP error, missing scopes, secondary rate limit): surface the error verbatim to the user and stop — do not retry, do not fall back, do not bypass with `--no-verify`-style flags, do not silently downgrade to top-level `gh pr comment`. No partial state is written: leave per-finding `[POSTED-TO-PR]` tags off entirely so user can re-run cleanly after fixing the underlying issue. Mirrors fail-closed semantics.

Append to state file `## Errors`:

```yaml
- phase: action-gate
stage: pr-review-comment-post
error: <verbatim gh stderr>
consequence: post-aborted-no-state-mutation
```

### 7.8 Post-posting overturn reconciliation

Fires when an in-session re-check (a user challenge, later analysis) overturns or re-grades a finding carrying `[POSTED-TO-PR]`.

**State reconciliation — mandatory and immediate, never a conditional chat offer.** Via `atomic_state_write`, move the finding to `## Filtered` with `reason: overturned-after-post` (or, for a re-grade, annotate the new grade on its line). Preserve the original severity so the user can re-elevate, and keep the `posted-to-pr: <url>` reference on the line so the external comment stays traceable.

**PR-side write — gated.** Editing, replying to, or deleting the posted comment is an external effect: offer it through its own one-question gate. Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Recommended-label policy, the withdraw/downgrade option must NOT carry "(Recommended)" unless the overturn is itself verifier-confirmed. AFTER the PR-side write succeeds, append a `non-resumable-actions[]` entry (`action: pr-comment-amended`, `pr-ref`, `comment-id`, `kind: edit|reply|delete`, `completed-at` a live clock read interpolated in the same write call — full schema in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §`non-resumable-actions[]` action enum) — write after the side-effect succeeds, consistent with §7.4 and implement/SKILL.md.

| Rationalization | Why it is wrong |
|---|---|
| "I corrected the finding in chat — the user knows, the handoff can stay as-is." | The handoff is what downstream consumers and resumed sessions read; an overturned finding left marked `[POSTED-TO-PR]` + kept presents a refuted claim as live. Reconcile the state file in the same turn as the overturn. |
