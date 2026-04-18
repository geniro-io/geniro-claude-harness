# Model Tiering — Canonical Rule

Single source of truth for picking a `model=` when spawning subagents from any skill in this plugin.

## The rule

**Every `Agent(...)` spawn MUST specify `model=` explicitly.** Never rely on the agent's frontmatter default or the orchestrator's `inherit` — both let the caller's expensive model leak into mechanical subagents (see Claude Code issue #26179, #29768).

## Tier table

| Task nature | Model |
|---|---|
| Mechanical edit, template-based doc patching, rubric-based review (guidelines, design), CLI orchestration, structured PASS/FAIL classification, dedup checks, observation extraction | `haiku` |
| Code reasoning, implementation, bugs/security/architecture/tests review, spec compliance, simplify pass, refactor with zero-behavior guarantee, parallel research with narrow focus | `sonnet` |
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
- **Read-only / classifier agents stay on `haiku`** regardless of caller: `knowledge-agent`, `doc-agent`, `knowledge-retrieval-agent`.
- **Reviewer agents never use `opus`.** Stay on `sonnet` for reasoning dimensions (bugs, security, architecture, tests) or `haiku` for rubric dimensions (guidelines, design). Synthesis of review findings may use the orchestrator's model.

## How skills reference this

Add this one-liner near the top of any delegating skill:

> **Subagent model selection:** Follow `skills/_shared/model-tiering.md`. Skill-specific overrides documented inline at each spawn site.
