# Model Tiering — Canonical Rule

Single source of truth for picking a `model=` when spawning subagents from any skill in this plugin.

## The rule

**Every `Agent(...)` spawn MUST be explicit about its tier.** Pick a hardcoded tier (`haiku` / `sonnet` / `opus`) for mechanical or bounded-scope subagents — relying on the agent's frontmatter default lets the caller's expensive model leak into work that doesn't need it (see Claude Code issue #26179, #29768). **Carve-out for reasoning-grade subagents that mirror orchestrator judgment**: the agent's frontmatter declares `model: inherit` and the spawn site **omits the `model=` argument** so the synthesis/verification tier matches the orchestrator's — the bug-leak concern doesn't apply when the inherited tier is the intended one. (The Agent tool's `model=` argument enum is `sonnet|opus|haiku`; passing `model="inherit"` at the call site fails input validation with "Invalid tool parameters". `inherit` is a frontmatter directive only — propagate it by omitting the runtime arg.) The carve-out covers three categories: (a) synthesis-of-review-findings work (e.g., `relevance-filter-agent` weighing repo-convention evidence to inform KEEP/FILTER decisions); (b) per-finding validation sub-agents that independently confirm CRITICAL/HIGH findings (decisions inherit the same severity-stakes as the orchestrator's KEEP call); (c) reasoning-grade test authoring (e.g., `adversarial-tester-agent`'s F→P-verified test generation across edge cases). The carve-out does NOT cover reviewer agents themselves, mechanical leaf agents, or rubric-based work.

## Tier table

| Task nature | Model |
|---|---|
| Mechanical edit, template-based doc patching, rubric-based review (guidelines), CLI orchestration, structured PASS/FAIL classification, dedup checks, observation extraction | `haiku` |
| Code reasoning, implementation, bugs/security/architecture/tests/optimizations/conventions/design review, spec compliance, simplify pass, refactor with zero-behavior guarantee, parallel research with narrow focus | `sonnet` |
| Architecture design, multi-file planning, deep hypothesis-driven debugging, threat modeling, novel-domain greenfield work | `opus` |

## Escalation signals (pick `opus` from the start)

Even on small file counts, pick `opus` when ANY of these hold:

- New entity / migration / schema change
- Auth, permissions, or role boundary changes
- 3+ modules coordinated (cross-boundary work)
- Ambiguous spec or no clear acceptance criteria
- Novel problem domain (no similar code in the repo to copy)
- Long-horizon autonomy (multi-step plan, no human checkpoints)
- New external integration, async work, or queue/background job
- Open-closed violation (changing public signatures, shared middleware, routing)

## Runtime escalation (Sonnet → Opus on failure)

When a `sonnet` subagent returns wrong output, fails its checklist, or fails tests:

1. Re-dispatch ONCE with: more context (paste the failure) + `model="opus"`.
2. If the opus retry also fails, escalate to the user — do not loop.
3. Never bump twice in a row. Never escalate `haiku` → `opus` directly (go `haiku` → `sonnet` first).

## Hard rules (override the table)

- **Architect work always uses `opus`.** Architectural decisions, new-feature planning, multi-file design, threat modeling. Encoded in `agents/architect-agent.md` frontmatter AND must be set explicitly (`model="opus"`) at every spawn site so the choice survives any future change to the agent default.
- **Read-only / classifier agents stay on `haiku`** regardless of caller: `knowledge-retrieval-agent`.
- **Reviewer agents never use `opus`.** Stay on `sonnet` for reasoning dimensions (bugs, security, architecture, tests, optimizations, conventions, design) or `haiku` for rubric dimensions (guidelines). Design weighs visual/UX reasoning beyond pure rubric matching (token conformance, WCAG checks, exemplar drift, responsive coverage) — `sonnet` is the accuracy-floor.
- **Reasoning-grade carve-out agents** declare `model: inherit` in their frontmatter; spawn sites **omit `model=`** so the tier mirrors the orchestrator's. Three covered categories: synthesis-of-review-findings (e.g., `relevance-filter-agent`); per-finding validators that independently confirm CRITICAL/HIGH findings; reasoning-grade test authors (e.g., `adversarial-tester-agent`). They are NOT reviewer agents and the "never use `opus`" rule does not apply. (Do NOT pass `model="inherit"` at the call site — the Agent tool's enum is `sonnet|opus|haiku` and rejects `inherit` as Invalid tool parameters.)

## How skills reference this

Add this one-liner near the top of any delegating skill:

> **Subagent model selection:** Follow `skills/_shared/model-tiering.md`. Skill-specific overrides documented inline at each spawn site.
