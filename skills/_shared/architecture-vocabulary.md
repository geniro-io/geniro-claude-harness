# Canonical: Architecture Vocabulary

Single source of truth for design vocabulary. Skills cite this file rather than redefining terms inline so that "deepen this module" means the same thing in every skill.

## Core terms

| Term | Definition | Concrete signal |
|---|---|---|
| **Module** | A unit of code with a public interface and an internal implementation. May be a file, package, class, or directory boundary — what matters is the seam, not the syntax. | "What does this module expose? What does it hide?" answerable in 1 sentence. |
| **Interface** | The surface a module exposes to callers. Function signatures, exported types, public methods, REST endpoints, CLI flags. Smaller is better. | Count exported symbols. Lower count + stable signatures = better interface. |
| **Implementation** | The code behind the interface. Callers never read this. | Internal helpers, private methods, hidden state. |
| **Depth** | The ratio of behavior-behind-the-interface to interface size. **Deep modules** hide a lot of behavior behind a small interface; **shallow modules** expose nearly all their internal complexity. | Deep: `cache.get(key)` does eviction, TTL, serialization, hit-stats — but the caller sees one method. Shallow: a util file with 12 exported helpers each used once. |
| **Seam** | A point in the code where two modules meet through an interface. The narrower the seam, the easier it is to change either side. | Imports + function calls between modules. A module imported by 30 callers has a wide seam. |
| **Adapter** | A module whose only job is to translate between two interfaces (or between an external service and an internal interface). Adapters absorb interface change so the rest of the code doesn't have to. | "DB adapter", "Stripe adapter", "Slack adapter". They have one job. |
| **Leverage** | How much of the codebase benefits from a single change. High-leverage code is depended on by many; low-leverage code is depended on by few. | Grep import count. A type used 200 places has high leverage; a helper used twice has low leverage. |
| **Locality** | How much of the change for a given task lives in one place. High locality = "to add a field, edit one file"; low locality = "to add a field, edit 7 files in 4 directories". | Trace a typical change. Count files touched. Few files = high locality. |

## Derived rules (apply when designing or evaluating modules)

1. **Prefer deep modules over shallow ones.** A module hiding a lot of behavior behind a small interface gives callers leverage without forcing them to learn the implementation.
2. **Narrow seams over wide seams.** When two modules must talk, expose the smallest possible interface. Wide seams couple modules; narrow seams let them evolve independently.
3. **High locality over low locality.** A typical change should touch as few places as possible. If adding a single feature edits N files in M directories, the seam is wrong — refactor the seam, not the feature.
4. **Use adapters at trust boundaries.** Anywhere external code (DB, third-party API, transport layer) meets internal code, put an adapter. The adapter absorbs upstream change.
5. **High-leverage code deserves more design.** Code many callers depend on warrants extra care: stable interface, deep implementation, comprehensive tests. Low-leverage code can stay simple.

## Anti-vocabulary (reject these framings)

- **"Add an abstraction"** — abstractions are not the goal; depth is. An abstraction without depth (e.g., a wrapper that adds nothing) is *worse* than no abstraction.
- **"Make it more flexible"** — flexibility without a concrete deepening or seam-narrowing rationale is YAGNI. Add complexity only when it absorbs change.
- **"Refactor for testability"** — if a module is hard to test, the seam is wrong, not the test framework. Fix the seam.

## How skills reference this

Each consumer cites this file rather than redefining vocabulary:

> Use the canonical terms in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/architecture-vocabulary.md` (depth, seam, adapter, leverage, locality). When proposing a refactor / deepening / module split, name the term explicitly.

### Per-skill use

| Skill / file | Where it cites this file |
|---|---|
| `/geniro:refactor` | Phase 1 Deepening Opportunities lens (`${CLAUDE_PLUGIN_ROOT}/skills/refactor/SKILL.md`) — vocabulary grounding before smell detection; the procedure body in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/refactor-patterns.md` reads it first too |
| `/geniro:review` (tests dim) | `${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md` — "narrow seams over wide seams" when a behavior is hard to test through the public interface |

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "These terms are obvious; skills don't need to cite them" | Without a single source, each skill drifts into its own vocabulary ("layer", "boundary", "facade"). Cross-skill handoffs (architect → reviewer, debug → implement) lose meaning. |
| "I'll add 'cohesion' and 'coupling' too" | Resist vocabulary bloat. Depth + seam + locality already cover what cohesion and coupling describe. Adding synonyms dilutes shared meaning. |
| "Another tool uses a different word for this — switch to match it" | Stay with these terms once defined. The point is consistency across these skills, not external alignment. Keep this file canonical and reference it. |
