# Per-Finding AskUserQuestion Rendering

Canonical shape for every `AskUserQuestion` call that surfaces a code-review finding (or a set of findings) to the user. The user must see enough of the finding body at the moment of decision to actually exercise judgment — `label` + 1-line `description` is not enough.

This file is the single source of truth. Skills cite specific sections; do NOT inline-paste the body schema.

## When this applies

Any AUQ call that asks the user to act on one or more findings. Both the per-finding "resolve this PRODUCT-DECISION" gate and the multi-select "pick which findings to act on" loop fall under this contract.

## Single-finding gate (one finding per call)

Used by:
- `/geniro:review` Phase 6 Step 0 (PRODUCT-DECISION resolution)
- `/geniro:follow-up` Phase 5 Step 2 (PRODUCT-DECISION resolution)
- `/geniro:implement` Phase 6 Fix-Loop pre-step (PRODUCT-DECISION resolution)
- `/geniro:refactor` Phase 5 escalation (PRODUCT-DECISION → escalate)

### Required AUQ shape

- **`header`**: short chip label set by the calling skill (e.g. `"Open decision"`, `"Escalate"`).
- **`question`**: multi-line markdown — render every field below verbatim from the finding's structured fields (see `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output Format):

  ```
  **<SEVERITY>** `path:lines` — <short title> — decision: <type>

  **Why this matters:** <1-sentence impact>

  How do you want to resolve this?
  ```

- **`options[]`** — one per enumerated path (from the finding's `Options:` field for PRODUCT-DECISION resolution gates; from the calling skill's escalation menu for refactor-style escalation gates):
  - **`label`**: 1-5 words — the action name (e.g. `"Move to utils"`, `"Keep as-is"`, `"Run /geniro:implement"`).
  - **`description`**: 1-line trade-off. Preserves the existing `Options:` bullet's "— <one-line trade-off>" portion. For escalation gates where the calling skill overrides the finding's `Options:` with a fixed menu (e.g. `/refactor` Phase 5 escalation), the calling skill provides each option's `description` directly per its escalation menu's trade-off line — not derived from the finding's `Options:`.
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
- `/geniro:review` Phase 6 PR-comment Step 3 (Pick-one-by-one branch)

### Required AUQ shape

- **`multiSelect: true`**.
- **`question`**: a single sentence stating the picking task — set by the calling skill (e.g. `"Pick findings to author tests for"`, `"Pick findings to post as PR comments"`).
- **`options[]`** — one per eligible finding:
  - **`label`**: as currently specified by each call site (e.g. `<severity-badge> path:line — <short title>` for PR-comment Pick; `path:line — short title — decision: <type>` for Test-gate Pick) — call sites set their own label format; do NOT change existing label conventions.
  - **`description`**: 1-line per current call-site spec — call sites set their own.
  - **`preview`**: full finding body, formatted identically to the Single-finding gate's preview block above (Evidence / Suggested fix / Confidence / Origin).
- **Cap-extension:** when more than 4 eligible findings exist, batch across multiple chained AUQ calls (≤4 per call); preview body is per-finding (each option carries its own finding's body).

## Investigation-driven fix gate (debug-flavored)

Used by:
- `/geniro:debug` Step 5 (Multi-path fix gate when a confirmed root cause has 2-4 valid fix paths with real trade-offs)
- `/geniro:debug` Step 6 escape hatch (Repro infeasible — alternative regression-guard picker when the bug is non-deterministic)

Structurally identical to the Single-finding gate above, but the "finding" is constructed by the `/debug` investigation rather than read from a reviewer-agent `Options:` field — body fields come from `.geniro/debug/HYPOTHESES.md` instead of the reviewer-agent output.

### Required AUQ shape

- **`header`**: short chip label set by the calling skill (`"Fix path"` for Step 5, `"Repro infeasible"` for Step 6).
- **`question`**: multi-line markdown:

  ```
  **Confirmed root cause:** `path:lines` — <hypothesis title>

  **Observed failure:** <one-line summary of the failing-test signature or captured pre-fix output>

  How do you want to <resolve | regression-guard> this?
  ```

  Pull the root-cause `path:lines`, hypothesis title, and observed-failure summary from `.geniro/debug/HYPOTHESES.md` (the confirmed hypothesis's "Isolate" file:line + title + "Fix Evidence" pre-fix output).
- **`options[]`** — one per fix path (Step 5) or per alternative regression guard (Step 6):
  - **`label`**: 1-5 words — the path/guard name (e.g. `"COALESCE default"`, `"Add monitor/alert"`).
  - **`description`**: 1-line trade-off — provided by the calling skill per its constructed menu.
  - **`preview`**: investigation context, formatted as:

    ````
    ## Root cause

    `path:lines` — <hypothesis title>

    ## Evidence

    ```<lang>
    <2-5 lines from the failing-test output OR captured pre-fix snippet from HYPOTHESES.md "Fix Evidence">
    ```

    ## Reproduction status

    <"Hypothesis confirmed at Step 4; reproduction test pending Step 6" for Step 5; "Reproduction infeasible — <reason from Reproduction Decision>" for Step 6 escape hatch>

    ## Hypothesis

    Hypothesis <number> from `.geniro/debug/HYPOTHESES.md`
    ````

  Render the same `preview` body on every option for the same investigation — the body is per-investigation, not per-option.

### Source-field map

| AUQ field | `.geniro/debug/HYPOTHESES.md` field |
|-----------|--------------------------------------|
| `path:lines` in `question` | confirmed hypothesis's "Isolate" section (file:line of root cause) |
| `<hypothesis title>` in `question` | confirmed hypothesis's title |
| `<observed failure>` in `question` | first line of confirmed hypothesis's "Fix Evidence" → captured pre-fix output |
| `preview` Evidence codeblock | full captured pre-fix output (2-5 lines) from "Fix Evidence" |
| `preview` Reproduction status | "Hypothesis confirmed at Step 4; reproduction test pending Step 6" (Step 5 multi-path fix gate) OR "Reproduction infeasible — <reason from Reproduction Decision>" (Step 6 escape hatch) |
| `preview` Hypothesis number | hypothesis ID from `HYPOTHESES.md` |

## Where the body fields come from

For skills running findings end-to-end in one invocation (`/geniro:review`), the orchestrator has the full reviewer-agent output in-memory and pulls Evidence / Why-matters / Suggested-fix / Confidence / Origin directly.

For cross-skill consumers (`/geniro:follow-up` Phase 5 Step 2, `/geniro:implement` Phase 6 Fix-Loop pre-step), findings arrive via the `<task-dir>/review-feedback.md` artifact (or `<PRIMARY_ROOT>/.geniro/review-findings-state.md` for `/follow-up`). Those files MUST carry the body fields per finding (at minimum for PRODUCT-DECISION rows, which is the only place AUQ fires across the skill boundary) — see `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` Phase 5 per-finding line schema for the persisted shape.

For `/geniro:debug` Step 5 / Step 6 gates, body fields come from `.geniro/debug/HYPOTHESES.md` (the confirmed hypothesis's "Isolate" + "Fix Evidence" + "Reproduction Decision" sections) — debug operates within a single invocation, so the artifact and in-memory state are the same source.

## Why this exists

A title-only AUQ option creates the *ceremony* of approval without the *substrate* for judgment. Users either rubber-stamp the recommended option or escape to "Type something" / chat — both outcomes defeat the Always-WAIT contract. The fix is structural: surface the finding body at the moment of decision so the gate is informed.
