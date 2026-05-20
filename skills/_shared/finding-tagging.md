# Finding Tagging

Authoritative tag definitions for reviewer-agent / architect-agent output and orchestrator routing. The `[ROOT-CAUSE] / [SYMPTOM] / [UNKNOWN] / [SYMPTOM-ACK]` tags form a finding-classification system parallel to the existing `[CONFIRMED-BY-TEST] / [CHALLENGED-BY-TEST] / [NEW] / [PRE-EXISTING] / [PRODUCT-DECISION]` tag families: same persistence channel (`<task-dir>/review-feedback.md` and `.geniro/state/<skill>/state-<slug>.md`), same audit-trail discipline, different classification axis (cause vs effect, instead of newness or evidence-strength). Tags persist across skill phases and are the trigger predicate for `${CLAUDE_PLUGIN_ROOT}/skills/_shared/root-cause-gate.md`.

This file is the single source of truth. Skills cite this file; do NOT inline-paste tag definitions or routing rules.

## Tag definitions

| Tag | Meaning | Required evidence to assign |
|---|---|---|
| `[ROOT-CAUSE]` | Finding/design addresses the underlying cause of the defect or design gap. The fix changes the layer where causation originates, not the layer where the symptom is observed. | One of: (a) code-trace from observed symptom back to the assigned `path:lines` showing the defect originates there; (b) reproduction test (F→P verified) demonstrating the change at `path:lines` is necessary AND sufficient to fix the symptom; (c) hypothesis-confirmation artifact per `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md` § Evidence Standard (kinds 2-5). |
| `[SYMPTOM]` | Finding/design patches a downstream effect of the defect; the underlying cause is unconfirmed or sits in a different layer. The fix would make the visible defect disappear without addressing causation, so the same root cause may re-emerge through a different surface. | Default classification when the structural signal points to symptom: e.g., reviewer flags a null-check at the call-site when the upstream producer is the one returning null without justification; architect proposes a UI-layer guard for an invariant that the data layer should enforce. |
| `[UNKNOWN]` | Not classified — the agent cannot determine cause-vs-symptom without more investigation than the review/design pass affords. | Used when (a) the change is structural / refactor / docs and the cause/symptom axis is not meaningfully applicable, OR (b) the agent's confidence in a `[ROOT-CAUSE]` or `[SYMPTOM]` assignment is below 60%. UNKNOWN is the explicit escape hatch — NEVER omit the tag entirely. |
| `[SYMPTOM-ACK]` | User acknowledged via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/root-cause-gate.md` "Mixed — annotate and proceed" option that this is intentionally a symptom patch with documented tech debt. | Set ONLY at gate result-handling — never by the reviewer/architect at first emission. The original `[SYMPTOM]` tag is overwritten by `[SYMPTOM-ACK]` when the user picks the Mixed option. |

The `[ROOT-CAUSE] ⇄ [SYMPTOM-ACK]` transition is also possible at gate result-handling: `[SYMPTOM] → [ROOT-CAUSE]` when the user picks "Confirmed root cause (proceed)"; `[SYMPTOM] → [SYMPTOM-ACK]` for "Mixed — annotate and proceed"; `[SYMPTOM]` is consumed (skill exits) when the user picks "Symptom — escalate to /geniro:debug".

## How agents emit tags

**`agents/reviewer-agent.md` Output Format adds a mandatory `Cause:` sub-field per finding** — one of `[ROOT-CAUSE]`, `[SYMPTOM]`, or `[UNKNOWN]` (the agent never emits `[SYMPTOM-ACK]` — that tag is gate-result-only). The field sits alongside the existing `Decision Type:` / `Origin:` / `Confidence:` fields in the per-finding output block, immediately after `Decision Type:`. The reviewer applies the tag based on the structural signal:
- Surface where the defect is observed → `[SYMPTOM]`.
- Layer where causation originates → `[ROOT-CAUSE]`.
- Cannot tell within the dimension's review budget → `[UNKNOWN]`.

When the reviewer cites cross-dimension evidence (e.g., the bugs reviewer notices the architecture reviewer would have more context), it still emits its best-effort tag — the orchestrator's judge pass (`/geniro:review` Phase 4) reconciles cross-dimension overlap.

**`agents/architect-agent.md` adds a mandatory "Root-cause classification" output section per design unit** — one of `ROOT-CAUSE`, `SYMPTOM-PATCH`, or `MIXED` (architect-flavored 3-tag set; `MIXED` indicates one design unit contains both root-cause and symptom-patch components, OR confidence in a clean ROOT-CAUSE / SYMPTOM-PATCH split is below 60%). The section sits after the design unit's "Approach" / "Trade-offs" blocks. The architect applies the classification based on the same structural signal as the reviewer, scaled to design units rather than finding lines:
- Design unit changes the originating layer → `ROOT-CAUSE`.
- Design unit changes only the surface where the defect manifests → `SYMPTOM-PATCH`.
- Design unit straddles both, OR confidence is below 60%, OR the cause/symptom axis is not meaningfully applicable (pure refactor, doc-only, structural) → `MIXED` (fires the gate; the user picks per-unit). `MIXED` is the architect's escape hatch for genuine ambiguity — architect MUST commit to a design call and MUST NOT punt to `UNKNOWN` (that tag is reviewer-only; see below).

`UNKNOWN` is **reviewer-only** — a post-implementation escape hatch when the reviewer cannot classify cause-vs-symptom within its review budget. The architect operates pre-implementation and must commit to a design read; punting to `UNKNOWN` would force the gate to ask the user to make a classification call the architect itself refused to make.

Both agents tag every finding/design unit. Omission is never acceptable — see § Anti-rationalization.

## How orchestrators route by tag

The orchestrator (`/geniro:implement` Phase 3 self-review / `/geniro:review` Phase 4 filter / `/geniro:refactor` Phase 3 verify) reads the `Cause:` field (reviewer findings) from the persisted artifact and routes:

- **`[ROOT-CAUSE]` / `ROOT-CAUSE`** → proceeds in the upstream skill's normal flow. The finding/design enters the fix-loop pool / implementation pool unchanged.
- **`[SYMPTOM]` / `SYMPTOM-PATCH`** that survives the upstream filter step (Phase 4 relevance-filter for `/geniro:review`; Phase 3 self-review filter for `/geniro:implement`; Phase 3 verify for `/geniro:refactor`) → fires `${CLAUDE_PLUGIN_ROOT}/skills/_shared/root-cause-gate.md` once per finding. The gate's result handling re-tags to `[ROOT-CAUSE]` / `[SYMPTOM-ACK]` or halts the skill for `/geniro:debug` escalation.
- **`MIXED`** (architect only) → fires the same gate per design unit; the user picks per-unit, just as `[SYMPTOM]` findings fire per-finding.
- **`[UNKNOWN]`** (reviewer only — architect emits the 3-tag set ROOT-CAUSE / SYMPTOM-PATCH / MIXED and does NOT have UNKNOWN as an option) → orchestrator requires the reviewer to escalate to `/geniro:debug` BEFORE the gate fires. Surfacing `[UNKNOWN]` to the gate would force the user to make a cause/symptom call the agent itself couldn't make — which is the same anti-pattern as auto-classifying ambiguous findings (see § Anti-rationalization). The escalation path matches the gate's "Symptom — escalate to /geniro:debug" branch: surface the hand-off message, halt the upstream skill, the user re-invokes after `/geniro:debug` confirms the cause and emits the (now classified) finding.
- **`[SYMPTOM-ACK]`** → already user-acknowledged; orchestrator proceeds AND appends the entry to the Ship summary's `## Acknowledged tech debt` section (the gate's Result handling already wrote it; this is the read-back for ship-time rendering).

(Pre-M4 lane-bypass exceptions for `/geniro:implement` Fast Lane и `/geniro:follow-up` Trivial are removed — M4 has no Lane modes per architecture/M4-implement-redesign.md §3.1, и `/follow-up` was deleted per master plan §66.)

## Persistence schema

Tags persist in two artifact families, mirroring the existing `[CONFIRMED-BY-TEST]` persistence pattern (per `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` Phase 5 per-finding line schema):

**1. Reviewer findings — `<task-dir>/review-feedback.md` (`/implement` Phase 3 self-review intermediate) и `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` (M6 §15.1 — M1 §T2 canonical — `/review` writer; consumed by `/implement` Phase 1 step 8 «Persist T2 handoffs»). Legacy path `<PRIMARY_ROOT>/.geniro/state/review-findings-state.md` is read once on resume для backward-compat per SKILL.md §5.2 only.**

The per-finding line gains a `cause:` field (lowercase to match existing field convention — `decision:`, `recommendation:`, `confidence:`). The field is appended after `confidence:` for both severity-section rows (CRITICAL/HIGH/MEDIUM) and Intent-section rows. Exact line format:

```
- [NEW|PRE-EXISTING] [optional: CONFIRMED-BY-TEST|CHALLENGED-BY-TEST|POSTED-TO-PR] path:lines — <description> — decision: <FIX-NOW|TESTABLE|PRODUCT-DECISION|INTENT-CHECK> — recommendation: <action> — confidence: NN% — cause: <ROOT-CAUSE|SYMPTOM|UNKNOWN|SYMPTOM-ACK>
```

When `cause: SYMPTOM` (or `cause: UNKNOWN` requiring debug escalation), the line is followed by indented sub-fields capturing the gate-rendering payload — same indent shape as the `decision: PRODUCT-DECISION` sub-fields in `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` Phase 5:

```
  symptom: <one-line description of the observed downstream effect>
  suspected-root-cause: <one-line description of where causation likely originates>
```

These sub-fields populate the gate's `<symptom>` and `<suspected root cause>` slots in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/root-cause-gate.md` § Required AUQ shape. Rows with `cause: ROOT-CAUSE` or `cause: SYMPTOM-ACK` do NOT need these sub-fields (gate does not fire / already resolved); rows with `cause: UNKNOWN` SHOULD include them as best-effort hypothesis seeds for the downstream `/geniro:debug` invocation.

**2. Architect design units — `<task-dir>/design.md` (`/implement` Phase 2 output):**

Each design unit's "Root-cause classification" section uses block format. Architect output uses unbracketed `Root-cause classification: ROOT-CAUSE` / `SYMPTOM-PATCH` / `MIXED` (3-tag set, UNKNOWN reserved for reviewer post-implementation escape hatch):

```
Root-cause classification: <ROOT-CAUSE|SYMPTOM-PATCH|MIXED>
Symptom: <one-line>                       # required when classification is SYMPTOM-PATCH or MIXED
Suspected root cause: <one-line>          # required when classification is SYMPTOM-PATCH or MIXED
```

The same gate-rendering rule applies: ROOT-CAUSE units skip the symptom/cause sub-fields; SYMPTOM-PATCH / MIXED units include them.

Older state files written before tagging was introduced will lack the `cause:` field entirely. Consumers MUST treat a missing `cause:` field as `cause: UNKNOWN` (the safe default — fires the upstream-debug escalation rather than auto-proceeding) and log a single-line caveat under `## Caveats` in the rendered report: `legacy state file — cause classification missing, treating as UNKNOWN`.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll skip the `Cause:` tag for trivial findings — the gate won't fire anyway" | Every finding requires a tag; `[UNKNOWN]` is the explicit escape hatch, NOT omission. A missing tag is parsed as a legacy / corrupt entry and forces the consumer to treat it as `[UNKNOWN]` with a caveat — same outcome as tagging it `[UNKNOWN]` directly, but with worse audit trail. Just emit the tag. |
| "I'll auto-classify ambiguous findings as `[ROOT-CAUSE]` for speed — the user can correct it" | Defaults to `[UNKNOWN]`. `[ROOT-CAUSE]` skips the gate entirely (orchestrator proceeds in the normal flow), so an auto-classified mistake silently ships a symptom patch with no user prompt. `[UNKNOWN]` triggers the conservative escalation path (require `/geniro:debug` to confirm) — the cost is one user-visible escalation, the benefit is no silent symptom-ship. The asymmetry favors `[UNKNOWN]` every time confidence is below 60%. |
| "The reviewer-agent's confidence is 75% — that's high enough for `[ROOT-CAUSE]`" | The 60% threshold is for the FINDING itself (does this issue exist?), not for the cause-vs-symptom classification (does this fix the cause or the symptom?). Those are independent dimensions. A 95%-confidence finding can have a 40%-confidence cause classification — emit the finding with `[UNKNOWN]` and let the gate route. |
| "I'll merge `[SYMPTOM]` and `[UNKNOWN]` into one tag — they both fire escalation" | They route differently. `[SYMPTOM]` fires the gate (3 user options including "Confirmed root cause" if the user already knows the cause); `[UNKNOWN]` requires `/geniro:debug` to run BEFORE the gate fires (the user shouldn't be asked to classify what the agent itself couldn't classify). Collapsing the tags collapses the routing. |
| "The agent classified `[SYMPTOM]` but I (orchestrator) think it's `[ROOT-CAUSE]` — I'll re-tag" | The orchestrator does NOT re-classify agent output. Re-classification is the user's call via the gate's "Confirmed root cause (proceed)" option, which records the override in the audit trail. Silent re-tagging by the orchestrator is the same anti-pattern as auto-dropping a MEDIUM (see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md` § Why this exists). |
| "The architect can't decide between ROOT-CAUSE and SYMPTOM-PATCH — I'll emit UNKNOWN" | Architect emits the 3-tag set ROOT-CAUSE / SYMPTOM-PATCH / MIXED only. `MIXED` is the escape hatch for genuine ambiguity (architect must commit to a design call; MIXED captures the genuine-straddle case AND the sub-60% confidence case, and routes through the gate). `UNKNOWN` is reviewer-only — a post-implementation escape hatch when the reviewer cannot classify within its review budget. Architect punting to UNKNOWN would force the user to make a classification call architect itself refused to make. |
