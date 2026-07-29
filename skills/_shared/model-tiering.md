# Model tiering — canonical rule

Single source of truth for picking a `model=` when spawning subagents from any skill in this plugin.

## Contents

- The rule — inherit by default; OMIT `model=`; the three hardcoded-tier categories
- Tier table — fallback for runtimes without an orchestrator
- Escalation signals (orchestrator-side advisory)
- Runtime escalation (Sonnet → Opus on failure)
- Hard rules
- How skills reference this
- Anti-rationalization

## The rule

**Plugin-defined subagents inherit orchestrator tier by default.** Frontmatter declares `model: inherit` (except the mechanical-agent carve-outs in category 3 below, which declare a concrete cheaper tier); spawn sites **OMIT the `model=` argument** in every case — the agent's frontmatter `model:` governs (inherit-agents resolve to the orchestrator tier; carve-out agents resolve to their declared tier). Rationale: the user explicitly chose their orchestrator tier (Opus / Sonnet / Haiku) at session start; subagents should symmetrically match that choice rather than hardcoding a cheaper tier. The user owns the cost / quality trade-off at session level — plugin paternalism ("I'll force Sonnet for cost containment") is the documented anti-pattern.

The Agent tool's `model=` argument enum is `sonnet|opus|haiku`; passing `model="inherit"` at the call site fails input validation with "Invalid tool parameters". Propagate `inherit` by **OMITTING the runtime arg** — Claude Code's Agent tool resolver picks up the orchestrator's tier when `model=` is unset.

**Hardcoded tier is allowed in three narrow categories:**

1. **User-authored custom reviewers** (`.geniro/instructions/review-extra/<slug>.md` with an explicit `model:` field). That's the user's own opt-in — their declaration overrides inherit. Absent declaration in custom-reviewer frontmatter = inherit (NOT a hidden default to Sonnet).

2. **Plugin-defined mechanical-only spawn sites** whose workload is a fixed check-and-report:
   - `/geniro:setup`'s Phase 4 verification subagent → `model="sonnet"` — runs a fixed check list against the generated CLAUDE.md and emits PASS / DRIFT lines. No hypothesis generation and no judgment call: the orchestrator re-decides from those lines, so output quality does not scale with orchestrator tier. Same mechanical shape as the category-3 agents below, hardcoded at the spawn site because this spawn has no agent file to carry the tier in frontmatter.

   The site carries an inline comment justifying the exemption. Any new hardcode requires the same justification — and the justification names what actually constrains the spawn (a mechanical, re-decidable output), never a tool restriction the spawn call cannot express: the Agent tool takes no `tools=` argument, so a tier defended by a claimed tool budget is defended by nothing. A hardcoded tier is a speed/cost preference, not a hard requirement — apply the empty-result fallback in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` so the spawn degrades to inherit (then inline) when the target tier is unavailable in the runtime (e.g. a Haiku spawn from a 1M-context Opus/Sonnet session returns `0 tokens`, since Haiku has no 1M-context variant).

3. **Plugin-defined mechanical / recoverable-evidence agents** that declare a concrete cheaper tier in their OWN frontmatter (so every spawn site still OMITs `model=` and the frontmatter governs — the universal spawn-site rule is unchanged):
   - `${CLAUDE_PLUGIN_ROOT}/agents/test-runner-agent.md` → `model: sonnet` — runs the test command and parses stdout into a fixed `{ALL_GREEN|HAS_FAILURES|INFRA_ERROR}` verdict plus capped failure snippets. No hypothesis generation or judgment: the orchestrator re-decides from the verdict and re-greps the saved log, so output quality does not scale with orchestrator intelligence. Pure mechanics.
   - `${CLAUDE_PLUGIN_ROOT}/agents/knowledge-retrieval-agent.md` → `model: sonnet` — mechanical search-and-cite across the memory layers; its one relevance filter is a one-line, hard-capped, citation-recoverable gate, so a weaker model's failure mode is bounded padding (which the orchestrator filters via the citations), not missed knowledge.

   Both pin **`sonnet`, never `haiku`**: the fallback tier table below would place these mechanical workloads at haiku, but Haiku 4.5 has no 1M-context variant, so a haiku-frontmatter agent returns `0 tokens` when spawned from a 1M-context Opus/Sonnet session. Sonnet is the safe floor. These are deliberate cost optimizations on genuinely mechanical agents — distinct from the reviewer / codebase-research / codebase-explorer / reflection / adversarial-tester agents, whose output quality scales with orchestrator intelligence and which therefore stay `inherit` (pinning those cheaper is the paternalism anti-pattern below).

## Tier table — fallback for runtimes without an orchestrator

When a plugin subagent is invoked in a context without an interactive orchestrator parent (cloud-runner harness, batch evaluation, headless CI), the calling layer SHOULD pick a tier per the table below. This is **fallback**, not preference — interactive runs always inherit.

| Task nature | Fallback model |
|---|---|
| Mechanical edit, template-based doc patching, rubric-based style review (the conventions dim's style-rubric checks), CLI orchestration, structured PASS/FAIL classification, dedup checks, observation extraction | `haiku` |
| Code reasoning, implementation, bugs/security/architecture/tests/optimizations/conventions/design review, spec compliance, refactor with zero-behavior guarantee, parallel research with narrow focus | `sonnet` |
| Architecture design, multi-file planning, deep hypothesis-driven debugging, threat modeling, novel-domain greenfield work | `opus` |

## Escalation signals (orchestrator-side advisory)

When a task's shape argues for a stronger tier, surface a one-line advisory and continue — e.g. "Spec touches auth boundary + async work — consider running on Opus tier if not already (current: <tier>)". Signals never drive an automatic tier override; the user retains authority via `/model`.

No skill wires per-signal detection for this. An advisory the user can act on only by abandoning the run and restarting on another tier does not earn a scan on every run, and the same risk surface already reaches them through the change-scope estimate and the reviewer dimensions. Read the signals as judgment cues when picking a tier up front: a schema or migration change, an auth or role boundary, 3+ coordinated modules, a new external integration, async / queue / background work, an ambiguous spec or absent acceptance criteria, a novel problem domain with no similar code in the repo to copy, long-horizon autonomy (multi-step plan, no human checkpoints), and an open-closed violation (changing public signatures, shared middleware, routing).

## Runtime escalation (Sonnet → Opus on failure)

Still applicable to the adversarial-tester per-finding retry path and other reasoning-grade carve-outs that internally escalate. NOT applicable to inherit-default subagents (their tier IS the orchestrator's tier; "escalation" would mean changing the orchestrator mid-session, which is the user's call).

When a `sonnet` subagent returns wrong output, fails its checklist, or fails tests:

1. Re-dispatch ONCE with: more context (paste the failure) + `model="opus"`.
2. If the opus retry also fails, escalate to the user — do not loop.
3. Never bump twice in a row. Never escalate `haiku` → `opus` directly (go `haiku` → `sonnet` first).

## Hard rules

- **Architect-flavored work (multi-file design, planning, threat modeling) runs orchestrator-side**, not in a subagent. The orchestrator's own model handles this reasoning inline. (When the orchestrator is on Opus, architecture work happens on Opus; when on Sonnet, on Sonnet. The user picks.)

## How skills reference this

Add this one-liner near the top of any delegating skill:

> **Subagent model selection:** Follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. Plugin subagent spawns OMIT `model=`; the narrow hardcode carve-outs are documented inline at their spawn sites.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll pass `model='sonnet'` explicitly at the reviewer-agent spawn site to ensure cost containment — the user might not realize Opus is expensive." | Forbidden. Plugin subagents inherit orchestrator tier per the Rule. User chose Opus at session start with full knowledge of cost; over-riding back to sonnet is paternalistic and produces tier-mismatch UX. If the user wants cheaper review, they switch orchestrator tier — that's the canonical knob, not skill-internal hardcoding. |
| "Opus is overkill for the `conventions` dimension's style-rubric checks (rubric-based pattern match) — I'll force haiku at the spawn site." | Forbidden. Inherit symmetry holds for all dimensions. User-Opus → conventions on Opus (slight overspend, accepted by user when they chose Opus); user-Sonnet → conventions on Sonnet; user-Haiku → conventions on Haiku (matches the rubric model). Inheriting is correct in all three cases; hardcoding breaks symmetry asymmetrically. |
| "Custom reviewer's `.geniro/instructions/review-extra/<slug>.md` doesn't declare `model:` — I'll default to sonnet at the spawn site." | When `model:` is OMITTED in the custom reviewer's frontmatter, treat it as "inherit", not "sonnet". Custom reviewers follow the same default as built-ins. The user opts INTO a hardcoded tier only by explicitly writing `model: haiku` / `model: opus` in their custom-reviewer frontmatter — that's their declaration, honor it. |
| "Plugin subagent spawning fails because the Agent tool doesn't accept `model='inherit'`." | Correct — the tool doesn't. The fix is to OMIT `model=` entirely, not to fall back to a hardcoded value. Tool resolver picks up orchestrator tier when arg is unset. Hardcoding a fallback (e.g., `model='sonnet'`) defeats the inherit contract. |
| "User is on Haiku; subagents on Haiku will produce low-quality output for reasoning dimensions." | User chose Haiku — they accepted the trade-off. Plugin paternalism ("I know better, bump to Sonnet") defeats the user's tier choice. If a reviewer-agent on Haiku misses bugs, surface this in the Phase 6 handoff summary ("findings count: 2 — note: orchestrator tier is Haiku; consider /model switch to Sonnet for deeper review"), not by silent override. |
