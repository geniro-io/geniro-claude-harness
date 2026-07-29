# Finding tagging

Cause classification for `/geniro:debug` findings. `[ROOT-CAUSE]` / `[SYMPTOM]` / `[UNKNOWN]` answer one question — does the finding name where causation originates, or only where the defect surfaces? — which is a different axis from severity (how bad) and from decision type (who decides). The orchestrator assigns the tag when it isolates a confirmed hypothesis at Phase 1.6 and records it alongside the finding in state.md `## Root Cause`.

In `/geniro:debug` the tag doubles as a self-check on the investigation itself: debug is the root-cause flow by definition, so anything other than `[ROOT-CAUSE]` says the hypothesis loop has not closed, and Phase 1.6 routes each of the other two tags to its own recovery.

This file is the single source of truth. Skills cite this file; do NOT inline-paste tag definitions.

## Contents

- Tag definitions — `[ROOT-CAUSE]` / `[SYMPTOM]` / `[UNKNOWN]` and the evidence each needs
- Anti-rationalization

## Tag definitions

| Tag | Meaning | Required evidence to assign |
|---|---|---|
| `[ROOT-CAUSE]` | The finding names the underlying cause: the layer where causation originates, not the layer where the failure is observed. | One of: (a) code-trace from the observed failure back to the assigned `path:lines` showing the defect originates there; (b) reproduction test (F→P verified) demonstrating the change at `path:lines` is necessary AND sufficient to stop the failure; (c) hypothesis-confirmation artifact per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` § "What counts as an artifact" (kinds 2-5). |
| `[SYMPTOM]` | The finding names a downstream effect; causation is unconfirmed or sits in a different layer. A fix here makes the visible failure disappear without addressing causation, so the same cause re-emerges through a different surface. | Assign when the structural signal points at the surface — e.g. a null-check at the call site when the upstream producer is the one returning null without justification. From debug this is a failure mode: re-enter the hypothesis loop with a new hypothesis rather than shipping the surface patch. |
| `[UNKNOWN]` | Not classified — the evidence in hand does not settle cause-vs-symptom. | Assign when confidence in a `[ROOT-CAUSE]` or `[SYMPTOM]` call is below 60%. `[UNKNOWN]` is the explicit escape hatch — emit it rather than omitting the tag, which forces the consumer to treat the finding as unclassified anyway, with a worse audit trail. From debug it means the hypothesis loop did not converge; escalate via the stall gate instead of writing a conclusion the evidence does not support. |

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll skip the tag — the write-up already explains the cause" | Prose can read as confident regardless of what was proven; the tag is the one field that states whether the Evidence Standard was actually met. `[UNKNOWN]` is the escape hatch, NOT omission — an untagged finding is read as unclassified anyway, minus the audit trail. |
| "I'll call it `[ROOT-CAUSE]` for speed — the fix looks right and the user can correct it" | The handoff's whole fix proposal rests on that claim, and `/geniro:implement` applies it without re-deriving causation. Default to `[UNKNOWN]` below 60% confidence: the cost is one visible escalation, the benefit is not shipping a patch aimed at the wrong layer. |
| "Confidence in the finding is 75% — that's high enough for `[ROOT-CAUSE]`" | The 60% threshold is about the CAUSE classification (does this address causation or the surface?), not about the finding (does this issue exist?). Those are independent — a 95%-confidence failure can have a 40%-confidence cause call. Tag `[UNKNOWN]` and keep investigating. |
| "`[SYMPTOM]` and `[UNKNOWN]` both mean I'm not done — I'll use one tag" | They recover differently. `[SYMPTOM]` means causation sits in a layer you can name — re-enter the hypothesis loop targeting it. `[UNKNOWN]` means you cannot name it at all — that is the stall gate's trigger, and it surfaces to the user. Collapsing the tags collapses the recovery. |
