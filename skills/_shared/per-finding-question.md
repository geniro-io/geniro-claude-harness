# Per-Finding AskUserQuestion Rendering

Canonical shape for every `AskUserQuestion` call that surfaces a code-review finding (or a set of findings) to the user. The user must understand the finding fully at the moment of decision — what the code does, what the concern is, why it matters, and what each option means — without having seen the reviewer agents' output. The finding body is rendered to a chat message first (§ Message-first rendering); the `AskUserQuestion` itself stays lean. A bare `label` + 1-line `description`, or a finding body crammed into the truncating `preview` side-box, is not enough.

This file is the single source of truth. Skills cite specific sections; do NOT inline-paste the body schema.

## Contents

- When this applies — which AUQ calls fall under this contract
- Message-first rendering — render the finding to chat first, then a lean question
- Single-finding gate — one finding per call (shape + source-field map + cap-extension)
- Multi-select pick loop — multiple findings per call
- Investigation-driven fix gate — debug-flavored single-finding variant
- Where the body fields come from — in-memory vs handoff-artifact sources
- Recommended-label policy — when `(Recommended)` may and must not be applied
- Why this exists — the rationale for surfacing the finding body

## When this applies

Any AUQ call that asks the user to act on one or more findings. Both the per-finding "resolve this PRODUCT-DECISION" gate and the multi-select "pick which findings to act on" loop fall under this contract.

## Message-first rendering

Every gate under this contract follows a two-step shape — **render the finding to chat first, then fire a lean question** — mirroring the Gate presentation contract `/geniro:plan` uses for its approval gates.

1. **Render the finding to a chat message FIRST.** Before the `AskUserQuestion` fires, write a self-contained explanation to chat. It has full width and persists in scrollback:

   ```
   ### Decision needed: <plain-English one-line title>

   **What the code does now:** <plain English — name the function / file / behavior in words; expand any shorthand the reviewer used>
   **The concern:** <what is wrong, risky, or sub-optimal>
   **Why it matters:** <concrete impact: what breaks or degrades, who is affected, under what condition>
   **Evidence:** `path:lines` — <short behavior quote or snippet>
   **Options:**
   - **<Option A>** — <consequence>
   - **<Option B>** — <consequence>
   ```

2. **Then fire a LEAN `AskUserQuestion`.** The `question` restates the plain-English title and points at the chat explanation; each option is a short selector with a one-line `description`. Leave `preview` empty or use it for a one-line recap — never as the rendering surface.

**Self-containment rule.** The chat block and the AUQ must be understandable to a fresh user who never saw the reviewer agents' output. Expand reviewer shorthand into plain English: a reviewer phrase like "relies on the implicit entity-default @Filter at the 3 call sites" must be spelled out — which code paths, what the default does, why the reliance is in question — never echoed verbatim into the question. No term may appear in the `question` or any option that was not explained in the chat block first.

Why this shape: `AskUserQuestion` renders `preview` as a narrow monospace side-box that hard-truncates long content with no scroll, and is often absent entirely in an interactive session. A finding body placed there is unreadable or invisible — so the body lives in the chat message, which has full width, and the lean question captures only the decision.

## Single-finding gate (one finding per call)

Used by:
- `/geniro:review` Phase action-gate (PRODUCT-DECISION resolution; PR-comment Pick-one-by-one per-finding gate — calling-skill-set fixed menu: Post / Skip / Stop posting)
- `/geniro:implement` Phase 3 self-review fix-loop pre-step (PRODUCT-DECISION resolution)
- `/geniro:refactor` escalation

### Required AUQ shape

- **`header`**: short chip label set by the calling skill (e.g. `"Open decision"`, `"Escalate"`).
- **Chat render (first):** render the finding to chat per § Message-first rendering before firing the AUQ — the self-contained block carries What-the-code-does / The-concern / Why-it-matters / Evidence / Options, built from the finding's structured fields (see `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output Format) and expanded into plain English per the § Message-first rendering self-containment rule (never echoed verbatim when they carry reviewer shorthand).
- **`question`** (lean): the plain-English one-line title, then a pointer to the chat block:

 ```
 <plain-English one-line title> — `path:lines`

 Full explanation above. How do you want to resolve it?
 ```

- **`options[]`** — one per enumerated path (from the finding's `Options:` field for PRODUCT-DECISION resolution gates; from the calling skill's escalation menu for refactor-style escalation gates — see `/geniro:refactor` Phase 3 escalation for the 4-fixed-option menu):
 - **`label`**: 1-5 words — the action name (e.g. `"Move to utils"`, `"Keep as-is"`, `"Run /geniro:implement"`).
 - **`description`**: 1-line trade-off. Preserves the existing `Options:` bullet's "— <one-line trade-off>" portion. For escalation gates where the calling skill overrides the finding's `Options:` with a fixed menu (e.g. `/geniro:refactor` escalation), the calling skill provides each option's `description` directly per its escalation menu's trade-off line — not derived from the finding's `Options:`.
 - **`preview`**: leave empty, or a one-line recap only. The finding body — Evidence, Suggested fix, Confidence, Origin — is rendered to chat per § Message-first rendering, which is the surface that holds it. Do NOT cram the body into the `preview` side-box: it truncates long content with no scroll and is often absent in an interactive session, so a body placed there is unreadable or invisible. When the calling skill's options are an escalation menu (not the finding's own `Options:`), the chat block still describes the finding's body — the escalation labels merely tell the user what action will be taken on it.

### Source-field map

The chat block (§ Message-first rendering) is the surface that carries the finding body; the AUQ stays lean. Fields are expanded into plain English, not echoed verbatim when they carry reviewer shorthand.

| Destination | Reviewer-agent finding field |
|-----------|------------------------------|
| chat `What the code does now` + `The concern` | synthesized in plain English from finding-title + `Evidence:` + `Why this matters:` |
| chat `Why it matters` | `Why this matters:` (expanded to name the concrete impact, not a verbatim one-liner) |
| chat `Evidence` line + `path:lines` | `File:` + `Evidence:` (2-5 lines) |
| chat `Options` / AUQ option `label` + `description` | `Options:` bullets (`label` ← action name; `description` ← "— <one-line trade-off>") |
| AUQ `question` title + `path:lines` | finding-title (plain English) + `File:` |
| chat recap of `Confidence` / `Origin` | `Confidence:` / `Origin:` |

### Cap-extension for >4 options

If a finding's `Options:` exceeds 4 OR carries `(more-options-exist: chain-follow-up)`, chain a follow-up `AskUserQuestion`: present at most 4 options per call, never drop or merge options across calls, and aggregate the selections from every call. The schema above applies identically to each chained call — the finding's chat block (§ Message-first rendering) is rendered once and referenced across the chained calls; `preview` stays empty or a one-line recap each time. This `§ Cap-extension` is the canonical definition of the rule; consuming skills cite it rather than restating it.

## Multi-select pick loop (multiple findings per call)

Used by:
- `/geniro:review` Phase 4.3 Step 2 (Test-gate "Let me pick" branch)

The multi-select shape is canonical for the Test-gate Pick branch, which selects a subset of findings as input to a downstream agent rather than as discrete approval decisions per finding. The PR-comment per-finding gate uses the Single-finding gate above with a calling-skill-set fixed menu (Post / Skip / Stop posting) — see that section's "Used by" list.

### Required AUQ shape

- **`multiSelect: true`**.
- **`question`**: a single sentence stating the picking task — set by the calling skill (e.g. `"Pick findings to author tests for"`, `"Pick findings to post as PR comments"`).
- **`options[]`** — one per eligible finding:
 - **`label`**: call sites set their own label format. When a label needs to convey decision-type (e.g. the Test-gate Pick, where decision-type is what matters when picking findings to author tests for), render it in plain English — "auto-fixable" (FIX-NOW), "testable" (TESTABLE), "needs your decision" (PRODUCT-DECISION), "confirm intent" (INTENT-CHECK) — rather than the raw `decision: <type>` tag, since the label is user-facing; keep the raw taxonomy tag in `description` or `preview` if a call site needs it. Severity drives sort order at the call site, not label content.
 - **`description`**: 1-line per current call-site spec — call sites set their own.
 - **`preview`**: leave empty or a one-line recap only. Per § Message-first rendering, render each eligible finding's self-contained block to chat before the pick loop so the user picks from explained findings, not side-box snippets.
- **Cap-extension:** when more than 4 eligible findings exist, batch across multiple chained AUQ calls (≤4 per call); each finding's self-contained block is rendered to chat per § Message-first rendering (`preview` stays empty or a one-line recap).

## Investigation-driven fix gate (debug-flavored)

Used by:
- `/geniro:debug` Phase 2 (Multi-path fix gate when a confirmed root cause has 2-4 valid fix paths with real trade-offs)
- `/geniro:debug` Phase 2 escape hatch (Repro infeasible — alternative regression-guard picker when the bug is non-deterministic)

Structurally identical to the Single-finding gate above, but the "finding" is constructed by the `/geniro:debug` investigation rather than read from a reviewer-agent `Options:` field — body fields come from `.geniro/state/debug/<slug>/state.md` instead of the reviewer-agent output.

### Required AUQ shape

- **`header`**: short chip label set by the calling skill (`"Fix path"` for the multi-path fix gate, `"Repro infeasible"` for the repro-infeasible escape hatch — both `/geniro:debug` Phase 2).
- **Chat render (first):** render the investigation context to chat per § Message-first rendering — `### Fix decision: <plain-English root-cause title>`, then **Root cause** (`path:lines` + plain English), **What's failing** (observed failure in plain English), **Reproduction status**, **Options** (each fix path + consequence). Pull fields from `.geniro/state/debug/<slug>/state.md`.
- **`question`** (lean): multi-line markdown:

 ```
 <plain-English root-cause title> — `path:lines`

 Full explanation above. How do you want to <resolve | regression-guard> it?
 ```

 Pull the root-cause `path:lines`, hypothesis title, and observed-failure summary from `.geniro/state/debug/<slug>/state.md` (the confirmed hypothesis's `## Root Cause` file:line + title + `## Hypotheses` Result field pre-fix output).
- **`options[]`** — one per fix path or per alternative regression guard:
 - **`label`**: 1-5 words — the path/guard name (e.g. `"COALESCE default"`, `"Add monitor/alert"`).
 - **`description`**: 1-line trade-off — provided by the calling skill per its constructed menu.
 - **`preview`**: leave empty or a one-line recap only — the investigation context lives in the chat block (§ Message-first rendering), not the truncating/often-absent side-box.

### Source-field map

| AUQ field | `.geniro/state/debug/<slug>/state.md` field |
|-----------|--------------------------------------|
| `path:lines` in `question` | confirmed hypothesis's `## Root Cause` section (file:line of root cause) |
| `<hypothesis title>` in `question` | confirmed hypothesis's title |
| `<observed failure>` in `question` | first line of confirmed hypothesis's `## Hypotheses` Result field → captured pre-fix output |
| chat `Evidence` codeblock | full captured pre-fix output (2-5 lines) from `## Hypotheses` Result field |
| chat `Reproduction status` | "Hypothesis confirmed at Phase 1 Isolate; reproduction test pending Phase 2" (multi-path fix gate) OR "Reproduction infeasible — <reason from `## Reproduction Test` Reproduction Decision>" (repro-infeasible escape hatch) |
| chat `Hypothesis` number | hypothesis ID from state.md `## Hypotheses` |

## Where the body fields come from

For skills running findings end-to-end in one invocation (`/geniro:review`), the orchestrator has the full reviewer-agent output in-memory and pulls Evidence / Why-matters / Suggested-fix / Confidence / Origin directly.

For cross-skill consumers (`/geniro:implement`'s Phase 1 handoff-resolution step "Persist review/debug handoffs"), findings arrive in the Phase 3 self-review context (recorded in `<task-dir>/state.md`) or via the `/geniro:review` handoff at `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md`. Those files MUST carry the body fields per finding (at minimum for PRODUCT-DECISION rows, which is the only place AUQ fires across the skill boundary) — see the per-finding body schema in `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-6-handoff-reference.md` for the persisted shape.

For `/geniro:debug` Phase 2 / gates, body fields come from `.geniro/state/debug/<slug>/state.md` (the confirmed hypothesis's `## Root Cause` + `## Hypotheses` Result + `## Reproduction Test` Reproduction Decision sections) — debug operates within a single invocation, so the artifact and in-memory state are the same source.

## Recommended-label policy

The `(Recommended)` suffix on an AskUserQuestion option is load-bearing — users systematically ratify the Recommended option (see § Why this exists below). That ratification is appropriate when the recommended option is the conservative / canonical / verification path; it becomes a failure surface when the orchestrator labels its own unverified hypothesis as Recommended.

### When `(Recommended)` MAY be applied

- The option represents a canonical gate's conservative default (e.g. `test-first-gate.md` § Required AUQ shape "Author failing test first" option — the F→P-correct path; `root-cause-gate.md` § Required AUQ shape "Symptom — escalate to /geniro:debug" option — escalation when classification is `[SYMPTOM]` with low confidence; `within-skill-state-handoff.md` § Mismatch handling Case C "Stop — I'll switch" option — recovery from collision).
- The option represents a conservative verification path the orchestrator wants the user to take BEFORE acting (e.g. "Verify scenario X first" when the orchestrator is uncertain).
- The option directly matches a previously-loaded canonical default (CLAUDE.md gate / `.geniro/instructions/<skill>.md` rule).

### When `(Recommended)` MUST NOT be applied

- **Override-of-prior-finding rule.** When the orchestrator's AUQ option contradicts, downgrades, or proposes-to-ignore a prior `/geniro:review` CRITICAL or HIGH finding — read from `<task-dir>/state.md` or `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` — that option MUST NOT carry `(Recommended)`. The conservative path (verify the orchestrator's interpretation first; spawn skeptic to mirror-check; escalate to `/geniro:debug`) is the Recommended default instead. The orchestrator's interpretation of "this CRITICAL is stale / no-op / unused" is, by definition, an unverified claim until the skeptic mirror-check or an empirical re-run confirms it.
- **Orchestrator-authored-hypothesis rule.** When the orchestrator wrote BOTH the hypothesis AND the option set (i.e. the user did not propose the change in `$ARGUMENTS`; the orchestrator decided mid-pipeline that the change-shape should shift — e.g. "I'll downgrade this CRITICAL to a comment-only cleanup"), the orchestrator's preferred option MUST NOT carry `(Recommended)`. The Recommended default is whichever option keeps the original change shape intact, or "Stop and let me describe the change" if no original shape applies.
- **Defensive-removal rule.** When the AUQ asks the user to confirm a removal of a public-interface parameter, defensive branch (`if X return null` / early-return / try/catch / retry / fallback), or test, the removal option MUST NOT carry `(Recommended)`. The Recommended default is "Verify the guard's purpose first" (which routes to `/geniro:debug` adversarial mode — the adversarial-tester-agent authors an attempted-removal RED test verifying the guard's necessity) OR "Keep the guard for now".

### Pre-selection is the lever

Renaming `(Recommended)` to `(Suggested)` does NOT fix the anchoring problem — default-effect research shows pre-selection is the lever, not the label text. The rule above is therefore stated in terms of WHICH option is pre-selected, not what label decorates it. When the override-of-prior-finding rule or the orchestrator-authored-hypothesis rule fires, the orchestrator MUST surface the contradiction in the AUQ's `question` text — e.g.: `"I think the prior CRITICAL is stale because <reason>, but I haven't verified scenario <Y> directly. How should I proceed?"` — and the Recommended option, with the prior finding's full Evidence + Why-matters fields shown in the chat block (§ Message-first rendering), must be the verification path.

### Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'm 95% sure the CRITICAL is stale — Recommended save the user's time" | 95% confidence on an unverified hypothesis is exactly the failure mode this rule exists to counter. The verify-first option saves the user's CI cycle if you're wrong, and costs them ~60 seconds if you're right. |
| "The conservative option is obvious anyway — labeling doesn't matter" | Default-effect literature: users ratify the labeled-Recommended option at higher rates than the same option un-labeled, even when both options are visible. The label is the steering wheel; turn it correctly. |
| "I'll skip the prior-findings re-read since it's a small change" | The override-of-prior-finding rule fires on file/symbol overlap, not change size. A 2-line deletion that removes a parameter flagged by a prior CRITICAL is an override regardless of LOC. Re-read the artifact every time `$ARGUMENTS` touches a file with a prior finding. |
| "Just remove `(Recommended)` from my option entirely — that's enough" | Removing the label without re-pre-selecting the verification path leaves the user with no Recommended option at all, which (by default-effect) anchors on the first listed option instead. Always set the Recommended on a conservative path; never leave the AUQ rudderless. |

## Why this exists

A title-only AUQ option — or a finding body hidden in the truncating `preview` side-box — creates the *ceremony* of approval without the *substrate* for judgment. Users either rubber-stamp the recommended option or escape to "Type something" / chat — both outcomes defeat the Always-WAIT contract. The fix is structural: render the finding to chat in self-contained plain English at the moment of decision (§ Message-first rendering) so the gate is informed and the question stands on its own.
