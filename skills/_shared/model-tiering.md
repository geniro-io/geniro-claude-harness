# Model Tiering — Canonical Rule

Single source of truth for picking a `model=` when spawning subagents from any skill in this plugin.

## The rule

**Plugin-defined subagents inherit orchestrator tier by default.** Frontmatter declares `model: inherit`; spawn sites **OMIT the `model=` argument**. Rationale: the user explicitly chose their orchestrator tier (Opus / Sonnet / Haiku) at session start; subagents should symmetrically match that choice rather than hardcoding a cheaper tier. The user owns the cost / quality trade-off at session level — plugin paternalism («I'll force Sonnet for cost containment») is the documented anti-pattern.

The Agent tool's `model=` argument enum is `sonnet|opus|haiku`; passing `model="inherit"` at the call site fails input validation with "Invalid tool parameters". Propagate `inherit` by **OMITTING the runtime arg** — Claude Code's Agent tool resolver picks up the orchestrator's tier when `model=` is unset.

**Hardcoded tier is allowed in two narrow categories:**

1. **User-authored custom reviewers** (`.geniro/instructions/review-extra/<slug>.md` with an explicit `model:` field). That's the user's own opt-in — their declaration overrides inherit. Absent declaration in custom-reviewer frontmatter = inherit (NOT a hidden default to Sonnet).

2. **Plugin-defined mechanical-only spawn sites** where the tier IS the safety property:
   - `skills/implement/implement-reference.md` doc-patcher → `model="haiku"` — mechanical rewrite-file-with-known-output transform; haiku is sufficient and the speed floor matters.
   - `skills/setup/SKILL.md` verification subagent → `model="sonnet"` — runs under a tightly constrained tool budget (`[Read, Bash, Glob, Grep]` — no Write/Edit); the hardcoded floor is the safety contract, not the model preference.

   Both sites carry an inline comment justifying the exemption. Any new hardcode requires the same justification.

## Tier table — fallback for runtimes without an orchestrator

When a plugin subagent is invoked in a context without an interactive orchestrator parent (cloud-runner harness, batch evaluation, headless CI), the calling layer SHOULD pick a tier per the table below. This is **fallback**, not preference — interactive runs always inherit.

| Task nature | Fallback model |
|---|---|
| Mechanical edit, template-based doc patching, rubric-based review (guidelines), CLI orchestration, structured PASS/FAIL classification, dedup checks, observation extraction | `haiku` |
| Code reasoning, implementation, bugs/security/architecture/tests/optimizations/conventions/design review, spec compliance, simplify pass, refactor with zero-behavior guarantee, parallel research with narrow focus | `sonnet` |
| Architecture design, multi-file planning, deep hypothesis-driven debugging, threat modeling, novel-domain greenfield work | `opus` |

## Escalation signals (orchestrator-side advisory)

Even on small file counts, the orchestrator SHOULD surface a one-line advisory to the user when ANY of these hold (e.g., «Spec touches auth boundary + async work — consider running on Opus tier if not already (current: <tier>)»):

- New entity / migration / schema change
- Auth, permissions, or role boundary changes
- 3+ modules coordinated (cross-boundary work)
- Ambiguous spec or no clear acceptance criteria
- Novel problem domain (no similar code in the repo to copy)
- Long-horizon autonomy (multi-step plan, no human checkpoints)
- New external integration, async work, or queue/background job
- Open-closed violation (changing public signatures, shared middleware, routing)

Signals do NOT drive automatic tier override — they're a soft suggestion. The user retains authority over tier selection via `/model`.

## Runtime escalation (Sonnet → Opus on failure)

Still applicable to the adversarial-tester per-finding retry path and other reasoning-grade carve-outs that internally escalate. NOT applicable to inherit-default subagents (their tier IS the orchestrator's tier; «escalation» would mean changing the orchestrator mid-session, which is the user's call).

When a `sonnet` subagent returns wrong output, fails its checklist, or fails tests:

1. Re-dispatch ONCE with: more context (paste the failure) + `model="opus"`.
2. If the opus retry also fails, escalate to the user — do not loop.
3. Never bump twice in a row. Never escalate `haiku` → `opus` directly (go `haiku` → `sonnet` first).

## Hard rules

- **Architect-flavored work (multi-file design, planning, threat modeling) runs orchestrator-side**, not in a subagent. The orchestrator's own model handles this reasoning inline. (When the orchestrator is on Opus 4.7, architecture work happens on Opus; when on Sonnet, on Sonnet. The user picks.)

## maxTurns convention

All plugin-defined agents declare `maxTurns:` explicitly in frontmatter — **never omit**. Two-runtime rationale:

- **Interactive Claude Code** ignores the value (per [anthropics/claude-code#41143](https://github.com/anthropics/claude-code/issues/41143) closed «not planned»). Treats `maxTurns` as advisory documentation.
- **Agent SDK / claude-code-action / cloud-runners** default to **10 turns** when unset (per [claude-code-action#1177](https://github.com/anthropics/claude-code-action/issues/1177)). Any plugin agent running under the SDK without an explicit cap hits «Reached maximum number of turns (10)» on the first reasoning workload.

Setting explicitly protects cross-runtime portability — the value is documentation in interactive mode and a hard cap in headless mode.

**Pick the value per workload-counting formula:**

```
floor    = sum(Reads + Greps + Bash invocations + reasoning turns + emit step)
slack    = 50-60% (retry / refinement iterations)
maxTurns = ceil(floor × 1.5) + optional safety bump
```

Document the formula in each agent's `## maxTurns rationale` section. Pure mechanical agents (test-runner) get tight caps; reasoning agents (reviewer, adversarial-tester) get generous caps. Values above ~150 signal «I gave up bounding» — re-examine the agent's scope before going higher.

## How skills reference this

Add this one-liner near the top of any delegating skill:

> **Subagent model selection:** Follow `skills/_shared/model-tiering.md`. Plugin subagent spawns OMIT `model=`; the two narrow hardcode carve-outs are documented inline at their spawn sites.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll pass `model='sonnet'` explicitly at the reviewer-agent spawn site to ensure cost containment — the user might not realize Opus is expensive." | Forbidden. Plugin subagents inherit orchestrator tier per the Rule. User chose Opus at session start with full knowledge of cost; over-riding back to sonnet is paternalistic and produces tier-mismatch UX. If the user wants cheaper review, they switch orchestrator tier — that's the canonical knob, not skill-internal hardcoding. |
| "Opus is overkill for the `guidelines` dimension (rubric-based pattern match) — I'll force haiku at the spawn site." | Forbidden. Inherit symmetry holds for all dimensions. User-Opus → guidelines on Opus (slight overspend, accepted by user when they chose Opus); user-Sonnet → guidelines on Sonnet; user-Haiku → guidelines on Haiku (matches the rubric model). Inheriting is correct in all three cases; hardcoding breaks symmetry asymmetrically. |
| "Custom reviewer's `.geniro/instructions/review-extra/<slug>.md` doesn't declare `model:` — I'll default to sonnet at the spawn site." | When `model:` is OMITTED in the custom reviewer's frontmatter, treat it as «inherit», not «sonnet». Custom reviewers follow the same default as built-ins. The user opts INTO a hardcoded tier only by explicitly writing `model: haiku` / `model: opus` in their custom-reviewer frontmatter — that's their declaration, honor it. |
| "Plugin subagent spawning fails because the Agent tool doesn't accept `model='inherit'`." | Correct — the tool doesn't. The fix is to OMIT `model=` entirely, not to fall back to a hardcoded value. Tool resolver picks up orchestrator tier when arg is unset. Hardcoding a fallback (e.g., `model='sonnet'`) defeats the inherit contract. |
| "User is on Haiku; subagents on Haiku will produce low-quality output for reasoning dimensions." | User chose Haiku — they accepted the trade-off. Plugin paternalism («I know better, bump to Sonnet») is documented anti-pattern across all tools (Cline, Cursor, Aider all let the user choose). If a reviewer-agent on Haiku misses bugs, surface this in Phase 6 hand-off summary («findings count: 2 — note: orchestrator tier is Haiku; consider /model switch to Sonnet for deeper review»), not by silent override. |
| "Omit `maxTurns` — Claude Code interactive ignores it anyway." | Agent SDK default is 10 turns when unset. If the plugin agent ever runs outside interactive Claude Code (cloud-runner, claude-code-action, batch eval), omitting causes `Reached maximum number of turns (10)` immediately. Set explicitly for cross-runtime portability. |
| "Bump `maxTurns` to 200 for safety — won't hurt anything." | Above ~150 reads as «the agent owner gave up bounding scope» rather than «the workload genuinely needs this». If a workload genuinely needs 200 turns, the agent's procedure has a bug or scope creep — fix the procedure, don't paper over with bigger budget. Keep caps in the 30-100 range; if tempted past 150, audit the workflow first. |
| "Tighten `maxTurns` to ~25 to bound cost — agent will self-monitor and stop." | Self-monitoring is unreliable — the bug-41143 reporter's agent kept calling tools past their declared cap. Mechanical caps are needed precisely because self-monitoring can drift. Set the cap at floor + 50% slack, not at floor — last-second tool calls (emit findings, write output) need turns budget. Tight caps trigger silent truncation, partial output, corrupted downstream handoffs. |
