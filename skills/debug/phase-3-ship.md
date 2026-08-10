# Debug Phase 3 — ship

Phase file for `/geniro:debug`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md`.

state.md `phase: ship`. Findings handoff to downstream skill OR user-handles — proposals + tests authored locally (no-ship boundary per § Your role, § ACI per-phase).

**Refresh custom instructions on entry.** Re-fire `load-custom-instructions(SKILL_SLUG: debug, LOAD_TIER: pipeline, MODE: refresh)` once (pipeline tier's load set owned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`), before §3.0 below. The Debug Findings summary and the escalation gate are both authored here, so the code-style and process rules have to be the ones on disk now — Phase 2's load can be several fix-loop rounds old.

## Contents

- §3.0 Pre-gate — resolve open questions · §3.1 Present findings · §3.2 Escalation AUQ
- §3.3 Emit learnings · §3.4 Cleanup · §3.5 Atomic non-resumable updates
- Definition of done — Scientific Mode

### 3.0 Pre-gate — resolve open questions

Fires FIRST in Phase 3 — before the findings summary, before the escalation AUQ — whenever state.md frontmatter `open_questions[]` carries any entry with `status: unresolved`. Open questions surface ambiguity that downstream consumers (typically /geniro:implement) need resolved before applying a fix; resolving them here means the escalation AUQ chooses between a known-shape target rather than between paths that still gate on ambiguity.

**Procedure.** Run the canonical resolve-open-questions procedure in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §2.5 — read and filter the unresolved set, render each entry message-first before its own lean `AskUserQuestion` (Always-WAIT), write the resolution back in place via `atomic_state_write`, mirror it into the body `## Resolved Questions`, chain a second call rather than batching when one entry's options exceed the AUQ cap, and re-read the frontmatter afterwards to confirm every entry sits in `{resolved, wontfix}` before §3.1 runs. Its Wontfix path binds here unchanged. The entry fields and the `resolution` sub-fields are `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2.

Debug's instantiation of that procedure:

- **Render source.** A debug entry carries `source` + `related_hypotheses` rather than `related_findings`, so the conversational lead states what the investigation hit and why the question stayed open. Preserve `id`, `source`, `question`, `related_hypotheses` across the resolution write.
- **Resolution values.** `resolution.asked_in_phase: phase-3-pre-gate`, `resolution.resolved_by: debug`.
- **Options** are synthesized from the entry's context:
  - Stall categories (Phase 1 stall gate) → re-render the stall categories surfaced in Phase 1 (the set persisted in this entry's `question:` field) plus the "Abandon" option; do not introduce categories that were not originally surfaced.
  - Multi-path fix deferred → render the original path options.
  - Cannot-verify deferred → render "Provide the missing data" / "Mark as accepted limitation" / "Escalate to /geniro:investigate".

**No-skip rule.** This gate cannot be deferred to /geniro:implement or to the user's manual patch path. /geniro:debug is the producer that surfaced the ambiguity, and a handoff that carries an unresolved question makes the consumer act on a question the user never answered. The exception: when §3.2 fires and the user picks "Cannot verify — request specific data from user", that response itself IS a resolution path — emit a new `open_questions[]` entry with `source: phase-3-cannot-verify`, `status: unresolved`, then re-enter this gate when the data arrives.

Skipped silently when `open_questions[]` has zero `unresolved` entries.

### 3.1 Present findings (chat + persist handoff)

Present a human-readable findings summary before the escalation question fires — the user chooses the escalation target based on it, so do not jump straight to the question. Output the markdown block directly in chat AND write the same content (with full frontmatter wrapping it) to `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md` via `atomic_state_write`. Resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A so the handoff survives worktree teardown. The summary speaks the gate visual language (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Visual rendering language) — no progress tracker (this is the single terminal gate), an `**In one sentence:**` opener, light icons on the field labels, and the cause → effect flow visual; the escalation `AskUserQuestion` itself stays lean — the render does not alter its option set. The icon prefixes on the field labels are presentation only — consumers match labels by their text, never by the icon, and the two parsed labels (`**Reproduction test:**`, `**Test file:**`) stay undecorated.

**Findings template body:**

```markdown
## Debug Findings

**In one sentence:** [what was wrong and what fixing it takes — one plain sentence]

**Source branch:** [from `git branch --show-current`]

**Source worktree:** [from `git rev-parse --show-toplevel`]

**Why escalating to <target>:** [one sentence — which target, plus the fix's blast radius: how many files it touches and whether it changes interfaces, architecture, or auth/permissions; user makes the final routing choice in the escalation question (§3.2)]

**🔍 Root cause:** [one sentence, plain language — why the bug happens]

[cause → effect flow per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md` § Finding-type visual map, "Debug root cause" row: `<root cause at path:line> ──▸ <intermediate> ──▸ <observed failure>`]

**🧪 Reproduction:** [exact steps that trigger the bug]

**Confirmed hypothesis:** [which numbered hypothesis from `## Hypotheses` was confirmed, and the test result that confirmed it]

**Rejected hypotheses:** [brief — which hypotheses were ruled out and why]

**🛠 Proposed fix:**
- Files: [path(s) that need to change]
- Change: [unified diff or before/after snippet]
- Rationale: [one sentence tying the change to the root cause]

**✅ Evidence the fix works:** [default: "failing test went green under in-test monkey-patch; production source untouched"; or "<n> production files edited as escape hatch and reverted; bug stopped reproducing"]

**Reproduction test:** [<path>, <F→P status — example: "verified red on current code; verified green under throwaway patch"> — OR — "escape hatch: <alternative guard with rationale>"]

**⚠️ Special handling:** [codegen, migrations, schema changes, env/config updates, no correct test seam — regression not locked down (§2.4) — or "none"]

**⚠️ Stall-flagged?** [omit if stall gate did NOT fire; if it did: "Yes — cause not fully isolated; <component> identified as missing. Receiving skill should treat this as a starting point, not a closed investigation."]

**⚠️ Accepted limitations?** [omit unless fix-fail path "Accept as documented limitation" was taken; if so: "<description of limitation>; user accepted on <ISO timestamp>"]
```

**Populate `authored_tests[]` frontmatter (REQUIRED).** Alongside the body template above, write the `authored_tests[]` frontmatter array per the schema in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §2 and the canonical contract in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §Producer-specific extensions — that section owns the split between path B's empty array and the §2.4 hard-to-mock case's `escape-hatch` entry; follow it rather than re-deriving the split here. Each F→P test authored in §2.4 gets one entry: `{id: t<N>, path: <repo-root-relative>, intent: <one-line guarantee>, mode: scientific, f_to_p_status: <enum>, related_hypotheses: [<H-IDs>]}`. Never omit the array itself, even when it is empty. The body `**Reproduction test:**` line stays as human-readable mirror; the frontmatter is the machine-readable source for /geniro:implement's Phase 1 authored-test extraction (which invokes `${CLAUDE_PLUGIN_ROOT}/skills/_shared/debug-handoff.md` to verify presence in the consumer's worktree and surface relocation suggestions if MISSING).

The receiving skill pre-loads findings from `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md` — the state file is the handoff channel, not a chat paste. Do NOT re-derive, reword, or inline the summary into the escalation command; the file path IS the contract.

### 3.2 Escalation AUQ

Only after the summary above is visible AND persisted, `AskUserQuestion` with header "Escalate" and these options:

- **Run `/geniro:implement`** — the receiving skill pre-loads findings from the handoff file written above (`from-debug-<branch>.md`) and resolves that path itself, so the label stays free of internal path placeholders. How large the fix is rides in the handoff's **Why escalating** line, not in the option set. state.md transitions to `phase: done` (terminal).
- **Cannot verify — request specific data from user** — pick this when one or more hypotheses are unverified because a probe you actually ran failed to reach the artifact (§1.5 — an assumed limit is not a reason to route). Trigger a follow-up `AskUserQuestion` with concrete options for the missing data. When data arrives, return to the §3.0 Pre-gate, do NOT escalate yet — state.md stays `phase: ship` (non-terminal) until a later pick resolves to one of the other two terminals.
- **Leave it to me** — user will apply the patch manually using the state file as reference. state.md transitions to `phase: ship-summary-only` (terminal).

Do NOT auto-invoke the next skill — surface the suggestion only. The state file IS the handoff channel.

### 3.3 Emit learnings

At Phase 3 exit, fire the `diagnosis` emit below. Sequence the emit before the phase is declared done — a diagnosis emit left trailing after the handoff is persisted and the answer is delivered is the documented drop vector that kept L2 sparse (confirmed root causes recorded nothing). The visibility + ordering rules bind here: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §"Caller contract". The other two `emit-learning` types fire earlier in their own phases — listed here together so the full debug emit surface is visible in one place:

- **`emit-learning`** — called by /geniro:debug at three distinct points:
- **`diagnosis`** (primary emit type, fires at Phase 3 exit on confirmed root cause) — every confirmed root cause emits one entry with summary, tags (inferred from affected-files + hypothesis category), scope (project-relative path glob), and required `ext.{symptom, root_cause, fix}` per typed-extension table. Default trust `verified`. Canonical `emit_learning` call shape (single JSON object on stdin — a YAML payload exits 64) in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §9. After a successful emit, echo `Recorded learning: <summary>` to the user — the helper writes silently, so the echo is the only in-session signal the diagnosis was captured.
- **`discarded_hypothesis`** — fires per-rejection during Phase 1; payload schema, cap, and emit logic in §1.5.
- **`retry_failure_sequence`** — fires at Phase 2 exit when `fix_attempts >= 2`; payload schema and emit logic in §2.5.

### 3.4 Cleanup

After Phase 3 completes (escalated, accepted, or user-handles):

- **Scientific-method mode only:** `rm -rf .geniro/state/debug/<slug>/` for the current branch's slug only, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Cleanup contract — the whole slug dir, so any experiment artifact written under it (§2.3 permits scratch there) goes with `state.md`; nothing under `.geniro/state/debug/<slug>/` is read after the run, and the migration sweep does not scan `.geniro/state/`, so a leftover there would have no backstop. Its useful content is already saved (root cause, repro, hypotheses-tested-and-rejected, accepted limitations) via L2 emit + the persisted handoff at `.geniro/state/handoff/`. Do NOT delete sibling slugs from concurrent debug sessions on other branches.
- **Scientific-method mode only:** Remove debug scripts, scratch reproductions, the feedback-loop scratch signal, and ad-hoc curl/query files created during investigation. Grep the run's debug-log prefix (§1.5, e.g. `[DBG-a4f2]`) across the worktree and confirm zero hits before declaring cleanup done. The reproduction test (authored at project's normal test path) STAYS on disk — it ships with the fix as the regression guard.
- **Scientific-method mode only:** `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md` must remain on disk as the escalation handoff channel, so do not delete it. Stays until next debug run overwrites it (single file per branch).
- Kill any background processes started during investigation (dev servers, watchers, profilers).
- **Adversarial mode:** `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md` may remain as audit trail; authored test files stay on disk (unlike scientific-method experiments which get reverted).

Cleanup is best-effort — if a command fails silently, that's fine.

### 3.5 Atomic non-resumable updates

After each side-effect that cannot be replayed safely (none in baseline — debug performs no `git push` / `gh pr create`), append a structured entry to state.md frontmatter `non-resumable-actions[]` via `atomic_state_write`.

The empty baseline is intentional: debug ships proposals, not commits. If a future user-customization introduces side-effects (e.g. a `.geniro/actions/post-finding-to-slack.md` invocation), THAT action becomes a non-resumable entry — not the standard ship flow.

---

## Definition of done

These are the load-bearing exit gates and safety invariants for the mode that ran — the checks that, if skipped, make the investigation unsound or the no-ship boundary unsafe. Per-phase mechanics (context loading, hypothesis recording, feedback-loop construction) live in their phase sections; this is the final correctness/contract check, not a re-listing of every step.

### Scientific Mode

- [ ] Bug reproduced consistently with clear steps
- [ ] Root cause confirmed AND cited per Evidence Standard (not guessed), tagged `[ROOT-CAUSE]`
- [ ] Reproduction test authored at project's normal test path, F→P verified, survives Cleanup — OR escape hatch invoked with the user-recorded alternative regression guard in state.md "Reproduction Decision"
- [ ] Proposed fix written as a text patch, NOT applied to source (no-ship boundary held)
- [ ] When multiple valid fix paths exist, the multi-path fix gate fired (Always-WAIT) — user chose the path
- [ ] Findings handoff persisted to `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md` via `atomic_state_write` BEFORE the escalation question
- [ ] Escalation decision made via AskUserQuestion
- [ ] All experimental edits to non-test source reverted before handoff
- [ ] L2 emit fired with `diagnosis` type + `ext.{symptom, root_cause, fix}`
- [ ] Cleanup completed

Adversarial Mode's checklist lives in `${CLAUDE_PLUGIN_ROOT}/skills/debug/adversarial-mode.md`.
