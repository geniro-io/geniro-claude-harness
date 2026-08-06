# Per-finding AskUserQuestion rendering

Canonical shape for every `AskUserQuestion` call that surfaces a code-review finding (or a set of findings) to the user. The user must understand the finding fully at the moment of decision — what the code does, what the concern is, why it matters, and what each option means — without having seen the reviewer agents' output. The finding body is rendered to a chat message first (§ Message-first rendering); the `AskUserQuestion` itself stays lean. A bare `label` + 1-line `description`, or a finding body crammed into the truncating `preview` side-box, is not enough.

This file is the single source of truth for the core contract. Skills cite specific sections; do NOT inline-paste the body schema. The concrete finding-gate shapes — the single-finding AUQ shape, the challenge option, the mandatory pre-fire scrub, the visual map, and the source-field maps — live in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md`; Read that file when a gate is about to fire on a concrete finding or investigation result. A run that reaches no finding gate never loads it.

## Contents

- When this applies — which AUQ calls fall under this contract
- Message-first rendering — render the finding to chat first, then a lean question
- Cap-extension for >4 options — chained calls, never dropped options
- Multi-select pick loop — multiple findings per call
- Finding-gate shapes — when to Read the companion reference
- Recommended-label policy — when `(Recommended)` may and must not be applied
- Why this exists — the rationale for surfacing the finding body

## When this applies

Any AUQ call that asks the user to act on one or more findings. Both the per-finding "resolve this PRODUCT-DECISION" gate and the multi-select "pick which findings to act on" loop fall under this contract.

## Message-first rendering

Every gate under this contract follows a two-step shape — **render the finding to chat first, then fire a lean question** — mirroring the Gate presentation contract `/geniro:plan` uses for its approval gates.

1. **Render the finding to a chat message FIRST.** Before the `AskUserQuestion` fires, write a self-contained explanation to chat. It has full width and persists in scrollback:

   ```
   <progress tracker — only when ≥2 decisions are queued: ✔ Decision 1 — <short tag> · ● Decision 2 of 4 — <short tag> · ○ Decision 3 · ○ Decision 4>

   ### 🧭 Decision needed: <plain-English one-line title>

   **In one sentence:** <what this decision settles>

   <lead sentence(s), conversational: what the code does now and what the concern is — name the function / file / behavior in words; expand any shorthand the reviewer used>

   **Why it matters:** <concrete impact: what breaks or degrades, who is affected, under what condition> (evidence: `path:lines`)

   <the visual — shape per the visual map in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md`; when code itself is the clearest visual, a 2-5 line evidence snippet>

   **Options:**
   - **<Option A>** — <consequence>
   - **<Option B>** — <consequence>
   ```

   The tracker, opener, digest, per-unit visual, and heading icons are defined canonically in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Visual rendering language; this template is their finding-gate instantiation.

2. **Then fire a LEAN `AskUserQuestion`.** The `question` restates the plain-English title and points at the chat explanation; each option is a short selector with a one-line `description`. Leave `preview` empty or use it for a one-line recap — never as the rendering surface.

**Separate-message rule.** The chat block must be a SEPARATE, already-emitted assistant message that exists before the `AskUserQuestion` fires. Emitting the text and the AUQ tool call in the same assistant turn does not satisfy the contract: same-turn text may not display in some clients, and the question must be answerable from what the user has already seen. A question that says "the message above" / "rendered above" / "summarized above" while no such message exists obtains an approval the user could not have been informed of — a gate failure, not a UX nit.

**Turn-completion rule.** The inverse failure is forbidden too: once the chat block is emitted, the `AskUserQuestion` is the immediate next action. Canonical, with the guard's hard-block recovery, in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard.

**Self-containment rule.** The chat block and the AUQ must be understandable to a fresh user who never saw the reviewer agents' output. Expand reviewer shorthand into plain English: a reviewer phrase like "relies on the implicit entity-default @Filter at the 3 call sites" must be spelled out — which code paths, what the default does, why the reliance is in question — never echoed verbatim into the question. No term may appear in the `question` or any option that was not explained in the chat block first.

Why this shape: the `preview` side-box cannot carry a finding body — the reason is canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions. The body lives in the chat message; the lean question captures only the decision.

**Resume paths render too.** The separate-message rule holds after a compaction, wakeup, or workflow-completion continuation. Treat a wakeup or self-prompt's embedded premises as claims, not facts — verify against the visible transcript/state, then author the render fresh if it is not there. The pre-compaction message is gone from the user's live view even when state.md records that the gate was reached.

## Cap-extension for >4 options

If a finding's `Options:` exceeds 4 OR carries `(more-options-exist: chain-follow-up)`, chain a follow-up `AskUserQuestion`: present at most 4 options per call, never drop or merge options across calls, and aggregate the selections from every call. The gate's schema applies identically to each chained call — the finding's chat block (§ Message-first rendering) is rendered once and referenced across the chained calls; `preview` stays empty or a one-line recap each time. Count appended reading-aid and verification options (**Explain further**, **Challenge this finding**) and any calling-skill disposition option (such as /geniro:review's **Keep off the PR**) toward the 4 — they occupy slots like any other. **Order so the first call carries the decision:** fill the first call with the finding's own resolution options (up to 4); the appended reading-aid, verification, and disposition options overflow into the follow-up call(s). The first question the user sees is the actual decision — the aids sit one step away and never crowd out a resolution path. This cap is about a SINGLE finding's options; it never licenses batching multiple findings into one call (the one-finding-per-call rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md` §Single-finding gate). This section is the canonical definition of the rule; consuming skills cite it rather than restating it.

## Multi-select pick loop (multiple findings per call)

Used by:
- `/geniro:review` Phase 4.3 Step 2 (Test-gate "Let me pick" branch)
- `/geniro:review` Phase 6 include-deferred gate, "Let me pick" branch (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §4.6)
- `/geniro:implement` Phase 3 minor-findings gate, "Let me pick" branch
- `/geniro:refactor` Phase 1 HIGH-risk step approval, the reject-specific-steps branch (the picked units are plan steps, not findings)

The multi-select shape is canonical wherever a gate selects a SUBSET of an already-rendered set — findings to feed a downstream agent, findings to carry into a handoff, steps to skip — rather than taking a discrete approval decision per item. The PR-comment per-finding gate uses the single-finding gate with a calling-skill-set fixed menu (Post / Skip / Stop posting) — see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md` §Single-finding gate.

### Required AUQ shape

- **`multiSelect: true`**.
- **`question`**: a single sentence stating the picking task — set by the calling skill (e.g. `"Pick findings to author tests for"`, `"Pick findings to post as PR comments"`).
- **`options[]`** — one per eligible item (a finding at every site except `/geniro:refactor`, where the items are HIGH-risk plan steps):
 - **`label`**: call sites set their own label format. When a label needs to convey decision-type (e.g. the Test-gate Pick, where decision-type is what matters when picking findings to author tests for), render it in plain English — "auto-fixable" (FIX-NOW), "testable" (TESTABLE), "needs your decision" (PRODUCT-DECISION), "confirm intent" (INTENT-CHECK) — rather than the raw `decision: <type>` tag, since the label is user-facing; keep the raw taxonomy tag in `description` or `preview` if a call site needs it. Severity drives sort order at the call site, not label content.
 - **`description`**: 1-line per current call-site spec — call sites set their own.
 - **`preview`**: leave empty or a one-line recap only. Per § Message-first rendering, render each eligible finding's self-contained block to chat before the pick loop so the user picks from explained findings, not side-box snippets.
- **Cap-extension:** when more than 4 eligible findings exist, batch across multiple chained AUQ calls (≤4 per call); each finding's self-contained block is rendered to chat per § Message-first rendering (`preview` stays empty or a one-line recap).

## Finding-gate shapes — when to Read the companion reference

Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md` at the moment a gate is about to fire on a concrete finding or investigation result — before composing the render and the question. It carries the required single-finding AUQ shape, the Challenge-finding option, the mandatory pre-fire scrub of internal shorthand, the finding-type visual map, and the source-field maps (reviewer output / handoff artifact / debug state). Deferring that Read is a cost measure only — the shapes bind in full whenever such a gate fires; the multi-select pick loop above renders from the same visual map, so a pick loop over findings Reads the reference too.

## Recommended-label policy

The `(Recommended)` suffix on an AskUserQuestion option is load-bearing — users systematically ratify the Recommended option (see § Why this exists below). That ratification is appropriate when the recommended option is the conservative / canonical / verification path; it becomes a failure surface when the orchestrator labels its own unverified hypothesis as Recommended.

### When `(Recommended)` MAY be applied

- The option represents a canonical gate's conservative default (e.g. `review-handoff.md` §4.6 Include-deferred gate "Leave them in the report" option — the deferred findings never passed verification, so the default must not steer toward acting on them; `within-skill-state-handoff.md` § Mismatch handling Case C "Stop — I'll switch" option — recovery from collision).
- The option represents a conservative verification path the orchestrator wants the user to take BEFORE acting (e.g. "Verify scenario X first" when the orchestrator is uncertain).
- The option directly matches a previously-loaded canonical default (CLAUDE.md gate / `.geniro/instructions/<skill>.md` rule).

### When `(Recommended)` must not be applied

- **Override-of-prior-finding rule.** When the orchestrator's AUQ option contradicts, downgrades, or proposes-to-ignore a prior `/geniro:review` CRITICAL or HIGH finding — read from `<task-dir>/state.md` or `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` — that option does not carry `(Recommended)`. The conservative path (verify the orchestrator's interpretation first; spawn skeptic to mirror-check; escalate to `/geniro:debug`) is the Recommended default instead. The orchestrator's interpretation of "this CRITICAL is stale / no-op / unused" is, by definition, an unverified claim until the skeptic mirror-check or an empirical re-run confirms it.
- **Orchestrator-authored-hypothesis rule.** When the orchestrator wrote BOTH the hypothesis AND the option set (i.e. the user did not propose the change in `$ARGUMENTS`; the orchestrator decided mid-pipeline that the change-shape should shift — e.g. "I'll downgrade this CRITICAL to a comment-only cleanup"), the orchestrator's preferred option does not carry `(Recommended)`. The Recommended default is whichever option keeps the original change shape intact, or "Stop and let me describe the change" if no original shape applies.
- **Defensive-removal rule.** When the AUQ asks the user to confirm a removal of a public-interface parameter, defensive branch (`if X return null` / early-return / try/catch / retry / fallback), or test, the removal option does not carry `(Recommended)`. The Recommended default is "Verify the guard's purpose first" (which routes to `/geniro:debug` adversarial mode — the adversarial-tester-agent authors an attempted-removal RED test verifying the guard's necessity) OR "Keep the guard for now".

### Pre-selection is the lever

Renaming `(Recommended)` to `(Suggested)` does NOT fix the anchoring problem: what steers the user is which option is pre-selected, not the word decorating it. The rule above is therefore stated in terms of WHICH option carries the pre-selection. When the override-of-prior-finding rule or the orchestrator-authored-hypothesis rule fires, the orchestrator surfaces the contradiction in the AUQ's `question` text — e.g.: `"I think the prior CRITICAL is stale because <reason>, but I haven't verified scenario <Y> directly. How should I proceed?"` — and the Recommended option, with the prior finding's full Evidence + Why-matters fields shown in the chat block (§ Message-first rendering), must be the verification path.

### Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'm 95% sure the CRITICAL is stale — Recommended save the user's time" | 95% confidence on an unverified hypothesis is exactly the failure mode this rule exists to counter. The verify-first option saves the user's CI cycle if you're wrong, and costs them ~60 seconds if you're right. |
| "The conservative option is obvious anyway — labeling doesn't matter" | Default-effect literature: users ratify the labeled-Recommended option at higher rates than the same option un-labeled, even when both options are visible. The label is the steering wheel; turn it correctly. |
| "I'll skip the prior-findings re-read since it's a small change" | The override-of-prior-finding rule fires on file/symbol overlap, not change size. A 2-line deletion that removes a parameter flagged by a prior CRITICAL is an override regardless of LOC. Re-read the artifact every time `$ARGUMENTS` touches a file with a prior finding. |
| "Just remove `(Recommended)` from my option entirely — that's enough" | Removing the label without re-pre-selecting the verification path leaves the user with no Recommended option at all, which (by default-effect) anchors on the first listed option instead. Always set the Recommended on a conservative path; never leave the AUQ rudderless. |

## Why this exists

A title-only AUQ option — or a finding body hidden in the `preview` field — creates the *ceremony* of approval without the *substrate* for judgment. Users either rubber-stamp the recommended option or escape to "Type something" / chat — both outcomes defeat the Always-WAIT contract. The fix is structural: render the finding to chat in self-contained plain English at the moment of decision (§ Message-first rendering) so the gate is informed and the question stands on its own.
