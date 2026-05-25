# Per-Finding AskUserQuestion Rendering

Canonical shape for every `AskUserQuestion` call that surfaces a code-review finding (or a set of findings) to the user. The user must see enough of the finding body at the moment of decision to actually exercise judgment — `label` + 1-line `description` is not enough.

This file is the single source of truth. Skills cite specific sections; do NOT inline-paste the body schema.

## When this applies

Any AUQ call that asks the user to act on one or more findings. Both the per-finding "resolve this PRODUCT-DECISION" gate and the multi-select "pick which findings to act on" loop fall under this contract.

## Single-finding gate (one finding per call)

Used by:
- `/geniro:review` Phase action-gate (PRODUCT-DECISION resolution; PR-comment Pick-one-by-one per-finding gate — calling-skill-set fixed menu: Post / Skip / Stop posting)
- `/geniro:implement` Phase 3 self-review fix-loop pre-step (PRODUCT-DECISION resolution)
- `/geniro:refactor` escalation

### Required AUQ shape

- **`header`**: short chip label set by the calling skill (e.g. `"Open decision"`, `"Escalate"`).
- **`question`**: multi-line markdown — render every field below verbatim from the finding's structured fields (see `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output Format):

 ```
 **<SEVERITY>** `path:lines` — <short title> — decision: <type>

 **Why this matters:** <1-sentence impact>

 How do you want to resolve this?
 ```

- **`options[]`** — one per enumerated path (from the finding's `Options:` field for PRODUCT-DECISION resolution gates; from the calling skill's escalation menu for refactor-style escalation gates — see /refactor .3 for the 4-fixed-option menu):
 - **`label`**: 1-5 words — the action name (e.g. `"Move to utils"`, `"Keep as-is"`, `"Run /geniro:implement"`).
 - **`description`**: 1-line trade-off. Preserves the existing `Options:` bullet's "— <one-line trade-off>" portion. For escalation gates where the calling skill overrides the finding's `Options:` with a fixed menu (e.g. `/refactor` escalation), the calling skill provides each option's `description` directly per its escalation menu's trade-off line — not derived from the finding's `Options:`.
 - **`preview`**: full finding body, formatted as:

 ````
 ## Evidence

 ```<lang>
 <2-5 lines from the finding's Evidence: field>
 ```

 ## Suggested fix

 <synthesis text from the finding's Suggested fix: field>

 ## Confidence

 NN%

 ## Origin

 [NEW] | [PRE-EXISTING]
 ````

 Render the same `preview` body on every option for the same finding — the body is per-finding, not per-option, but AUQ scopes preview to options so the user can re-read the body from any focused option without losing the option-pick context. When the calling skill's options are an escalation menu (not the finding's own `Options:`), the preview body is still the finding's body — the escalation labels merely tell the user what action will be taken on it.

### Source-field map

| AUQ field | Reviewer-agent finding field |
|-----------|------------------------------|
| `<SEVERITY>` in `question` | severity (`CRITICAL` / `HIGH` / `MEDIUM` / `LOW`) |
| `path:lines` in `question` | `File:` |
| `<short title>` in `question` | finding-title (heading after severity in reviewer output) |
| `<type>` in `question` | `Decision Type:` |
| `Why this matters` line | `Why this matters:` |
| `description` per option | `Options:` bullet's "— <one-line trade-off>" portion |
| `preview` Evidence block | `Evidence:` (entire codeblock) |
| `preview` Suggested fix | `Suggested fix:` (synthesis text for PRODUCT-DECISION) |
| `preview` Confidence | `Confidence:` |
| `preview` Origin | `Origin:` |

### Cap-extension for >4 options

If a finding's `Options:` exceeds 4 OR carries `(more-options-exist: chain-follow-up)`, chain a follow-up `AskUserQuestion` per the canonical cap-extension pattern (see `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` Phase 6 "Failing tests" block). The body schema above applies identically to each chained call — preview content is the SAME body each time.

## Multi-select pick loop (multiple findings per call)

Used by:
- `/geniro:review` Phase 4c Step 2 (Test-gate "Let me pick" branch)

> Historical note: `/geniro:review` Phase 6 PR-comment Step 3 previously used this multi-select shape. It now uses the Single-finding gate above with a calling-skill-set fixed menu (Post / Skip / Stop posting) — see that section's "Used by" list. The multi-select pattern remains canonical for the Test-gate Pick branch, which selects a subset of findings as input to a downstream agent rather than as discrete approval decisions per finding.

### Required AUQ shape

- **`multiSelect: true`**.
- **`question`**: a single sentence stating the picking task — set by the calling skill (e.g. `"Pick findings to author tests for"`, `"Pick findings to post as PR comments"`).
- **`options[]`** — one per eligible finding:
 - **`label`**: as currently specified by each call site (e.g. `path:line — short title — decision: <type>` for the Test-gate Pick — decision-type is what matters when picking findings to AUTHOR TESTS FOR; severity drives sort order at the call site, not label content) — call sites set their own label format; do NOT change existing label conventions.
 - **`description`**: 1-line per current call-site spec — call sites set their own.
 - **`preview`**: full finding body, formatted identically to the Single-finding gate's preview block above (Evidence / Suggested fix / Confidence / Origin).
- **Cap-extension:** when more than 4 eligible findings exist, batch across multiple chained AUQ calls (≤4 per call); preview body is per-finding (each option carries its own finding's body).

## Investigation-driven fix gate (debug-flavored)

Used by:
- `/geniro:debug` Phase 2 (Multi-path fix gate when a confirmed root cause has 2-4 valid fix paths with real trade-offs)
- `/geniro:debug` Phase 2 escape hatch (Repro infeasible — alternative regression-guard picker when the bug is non-deterministic)

Structurally identical to the Single-finding gate above, but the "finding" is constructed by the `/debug` investigation rather than read from a reviewer-agent `Options:` field — body fields come from `.geniro/state/debug/<slug>/state.md` instead of the reviewer-agent output.

### Required AUQ shape

- **`header`**: short chip label set by the calling skill (`"Fix path"` for , `"Repro infeasible"` for ).
- **`question`**: multi-line markdown:

 ```
 **Confirmed root cause:** `path:lines` — <hypothesis title>

 **Observed failure:** <one-line summary of the failing-test signature or captured pre-fix output>

 How do you want to <resolve | regression-guard> this?
 ```

 Pull the root-cause `path:lines`, hypothesis title, and observed-failure summary from `.geniro/state/debug/<slug>/state.md` (the confirmed hypothesis's `## Root Cause` file:line + title + `## Hypotheses` Result field pre-fix output).
- **`options[]`** — one per fix path or per alternative regression guard:
 - **`label`**: 1-5 words — the path/guard name (e.g. `"COALESCE default"`, `"Add monitor/alert"`).
 - **`description`**: 1-line trade-off — provided by the calling skill per its constructed menu.
 - **`preview`**: investigation context, formatted as:

 ````
 ## Root cause

 `path:lines` — <hypothesis title>

 ## Evidence

 ```<lang>
 <2-5 lines from the failing-test output OR captured pre-fix snippet from state.md `## Hypotheses` Result field>
 ```

 ## Reproduction status

 <"Hypothesis confirmed at Phase 1 Isolate; reproduction test pending Phase 2 " for ; "Reproduction infeasible — <reason from `## Reproduction Test` Reproduction Decision>" for escape hatch>

 ## Hypothesis

 Hypothesis <number> from `.geniro/state/debug/<slug>/state.md` § Hypotheses
 ````

 Render the same `preview` body on every option for the same investigation — the body is per-investigation, not per-option.

### Source-field map

| AUQ field | `.geniro/state/debug/<slug>/state.md` field |
|-----------|--------------------------------------|
| `path:lines` in `question` | confirmed hypothesis's `## Root Cause` section (file:line of root cause) |
| `<hypothesis title>` in `question` | confirmed hypothesis's title |
| `<observed failure>` in `question` | first line of confirmed hypothesis's `## Hypotheses` Result field → captured pre-fix output |
| `preview` Evidence codeblock | full captured pre-fix output (2-5 lines) from `## Hypotheses` Result field |
| `preview` Reproduction status | "Hypothesis confirmed at Phase 1 Isolate; reproduction test pending Phase 2 " ( multi-path fix gate) OR "Reproduction infeasible — <reason from `## Reproduction Test` Reproduction Decision>" ( escape hatch) |
| `preview` Hypothesis number | hypothesis ID from state.md `## Hypotheses` |

## Where the body fields come from

For skills running findings end-to-end in one invocation (`/geniro:review`), the orchestrator has the full reviewer-agent output in-memory and pulls Evidence / Why-matters / Suggested-fix / Confidence / Origin directly.

For cross-skill consumers (`/geniro:implement` Phase 1 step 8 «Persist T2 handoffs»), findings arrive via the `<task-dir>/review-feedback.md` artifact (Phase 3 self-review intermediate) or `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md`. Those files MUST carry the body fields per finding (at minimum for PRODUCT-DECISION rows, which is the only place AUQ fires across the skill boundary) — see `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` Phase 5 per-finding line schema for the persisted shape.

For `/geniro:debug` Phase 2 / gates, body fields come from `.geniro/state/debug/<slug>/state.md` (the confirmed hypothesis's `## Root Cause` + `## Hypotheses` Result + `## Reproduction Test` Reproduction Decision sections) — debug operates within a single invocation, so the artifact and in-memory state are the same source.

## Recommended-label policy

The `(Recommended)` suffix on an AskUserQuestion option is load-bearing — users systematically ratify the Recommended option (see § Why this exists below). That ratification is appropriate when the recommended option is the conservative / canonical / verification path; it becomes a failure surface when the orchestrator labels its own unverified hypothesis as Recommended.

### When `(Recommended)` MAY be applied

- The option represents a canonical gate's conservative default (e.g. `test-first-gate.md` § Required AUQ shape "Author failing test first" option — the F→P-correct path; `root-cause-gate.md` § Required AUQ shape "[SYMPTOM] escalate" option — escalation when classification is `[SYMPTOM]` with low confidence; `within-skill-state-handoff.md` § Mismatch handling Case C "Stop — I'll switch" option — recovery from collision).
- The option represents a conservative verification path the orchestrator wants the user to take BEFORE acting (e.g. "Verify scenario X first" when the orchestrator is uncertain).
- The option directly matches a previously-loaded canonical default (CLAUDE.md gate / `.geniro/instructions/<skill>.md` rule).

### When `(Recommended)` MUST NOT be applied

- **Override-of-prior-finding rule.** When the orchestrator's AUQ option contradicts, downgrades, or proposes-to-ignore a prior `/review` CRITICAL or HIGH finding — read from `<task-dir>/planning/*/review-feedback.md` or `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` — that option MUST NOT carry `(Recommended)`. The conservative path (verify the orchestrator's interpretation first; spawn skeptic to mirror-check; escalate to `/geniro:debug`) is the Recommended default instead. The orchestrator's interpretation of "this CRITICAL is stale / no-op / unused" is, by definition, an unverified claim until the skeptic mirror-check or an empirical re-run confirms it.
- **Orchestrator-authored-hypothesis rule.** When the orchestrator wrote BOTH the hypothesis AND the option set (i.e. the user did not propose the change in `$ARGUMENTS`; the orchestrator decided mid-pipeline that the change-shape should shift — e.g. "I'll downgrade this CRITICAL to a comment-only cleanup"), the orchestrator's preferred option MUST NOT carry `(Recommended)`. The Recommended default is whichever option keeps the original change shape intact, or "Stop and let me describe the change" if no original shape applies.
- **Defensive-removal rule.** When the AUQ asks the user to confirm a removal of a public-interface parameter, defensive branch (`if X return null` / early-return / try/catch / retry / fallback), or test, the removal option MUST NOT carry `(Recommended)`. The Recommended default is "Verify the guard's purpose first" (which routes to `/geniro:debug` adversarial mode — .6 adversarial-tester-agent authors an attempted-removal RED test verifying the guard's necessity) OR "Keep the guard for now".

### Pre-selection is the lever

Renaming `(Recommended)` to `(Suggested)` does NOT fix the anchoring problem — default-effect research shows pre-selection is the lever, not the label text. The rule above is therefore stated in terms of WHICH option is pre-selected, not what label decorates it. When the override-of-prior-finding rule or the orchestrator-authored-hypothesis rule fires, the orchestrator MUST surface the contradiction in the AUQ's `question` text — e.g.: `"I think the prior CRITICAL is stale because <reason>, but I haven't verified scenario <Y> directly. How should I proceed?"` — and the Recommended option, with its preview body showing the prior finding's full Evidence + Why-matters fields, must be the verification path.

### Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'm 95% sure the CRITICAL is stale — Recommended save the user's time" | 95% confidence on an unverified hypothesis is exactly the failure mode this rule exists to counter. The verify-first option saves the user's CI cycle if you're wrong, and costs them ~60 seconds if you're right. |
| "The conservative option is obvious anyway — labeling doesn't matter" | Default-effect literature: users ratify the labeled-Recommended option at higher rates than the same option un-labeled, even when both options are visible. The label is the steering wheel; turn it correctly. |
| "I'll skip the `review-feedback.md` re-read since it's a small change" | The override-of-prior-finding rule fires on file/symbol overlap, not change size. A 2-line deletion that removes a parameter flagged by a prior CRITICAL is an override regardless of LOC. Re-read the artifact every time `$ARGUMENTS` touches a file with a prior finding. |
| "Just remove `(Recommended)` from my option entirely — that's enough" | Removing the label without re-pre-selecting the verification path leaves the user with no Recommended option at all, which (by default-effect) anchors on the first listed option instead. Always set the Recommended on a conservative path; never leave the AUQ rudderless. |

## Why this exists

A title-only AUQ option creates the *ceremony* of approval without the *substrate* for judgment. Users either rubber-stamp the recommended option or escape to "Type something" / chat — both outcomes defeat the Always-WAIT contract. The fix is structural: surface the finding body at the moment of decision so the gate is informed.
