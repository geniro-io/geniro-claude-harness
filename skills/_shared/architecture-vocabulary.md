# Canonical: architecture vocabulary

Single source of truth for design vocabulary. Skills cite this file rather than redefining terms inline so that "deepen this module" means the same thing in every skill.

## Core terms

| Term | Definition | Concrete signal |
|---|---|---|
| **Module** | A unit of code with a public interface and an internal implementation. May be a file, package, class, or directory boundary — what matters is the seam, not the syntax. | "What does this module expose? What does it hide?" answerable in 1 sentence. |
| **Interface** | Everything a caller must know to use the module correctly: signatures, exported types, public methods, REST endpoints, CLI flags — and also invariants, ordering constraints, error modes, required configuration, and performance characteristics. Less to know is better. | Could a caller use it correctly from the signatures alone? Every fact they must learn beyond that is interface too, so three exports with a hidden call-order rule are a bigger interface than they look. |
| **Implementation** | The code behind the interface. Callers never read this. | Internal helpers, private methods, hidden state. |
| **Depth** | How much behavior a module hides behind how little its callers must know. **Deep modules** do a lot while callers learn little; **shallow modules** make callers learn nearly as much as the module does. Judge it by what callers must know, never by comparing line or symbol counts. | Deep: `cache.get(key)` does eviction, TTL, serialization, hit-stats — but the caller sees one method. Shallow: a util file of 12 thin helpers, each used once, where callers must learn every name and quirk to save a line apiece. |
| **Seam** | A place where behavior can be altered without editing in that place — the location where a module's interface lives. Where to put a seam is a design decision separate from what sits behind it. A seam is narrow when crossing it takes little knowledge, wide when it takes a lot. | Can you swap or intercept behavior here (a different implementation, a test double) without touching the calling code? If nothing varies across it, the seam is hypothetical (rule 7). |
| **Adapter** | A module whose only job is to translate between two interfaces (or between an external service and an internal interface). Adapters absorb interface change so the rest of the code doesn't have to. | "DB adapter", "Stripe adapter", "Slack adapter". They have one job. |
| **Leverage** | How much caller code a change at this point affects — what callers gain from depth, since one implementation pays back across every caller and test that goes through it. | Ask what a fix or improvement here would change for callers. A module that 200 call sites lean on for real behavior has high leverage; a type those sites merely pass along has little, however often it is imported. |
| **Locality** | How much of the change for a given task lives in one place. High locality = "to add a field, edit one file"; low locality = "to add a field, edit 7 files in 4 directories". | Trace a typical change. Count files touched. Few files = high locality. |

## Derived rules (apply when designing or evaluating modules)

1. **Prefer deep modules over shallow ones.** A module hiding a lot of behavior behind a small interface gives callers leverage without forcing them to learn the implementation.
2. **Narrow seams over wide seams.** When two modules must talk, make what a caller must know to cross the seam as small as it can be. Wide seams couple modules; narrow seams let them evolve independently.
3. **High locality over low locality.** A typical change should touch as few places as possible. If adding a single feature edits N files in M directories, the seam is wrong — refactor the seam, not the feature.
4. **Use adapters at trust boundaries.** Anywhere external code (DB, third-party API, transport layer) meets internal code, put an adapter. The adapter absorbs upstream change.
5. **High-leverage code deserves more design.** Code many callers depend on warrants extra care: stable interface, deep implementation, comprehensive tests. Low-leverage code can stay simple.
6. **Apply the deletion test to suspected shallow modules.** Imagine deleting the module. If the complexity just vanishes, it was a pass-through wrapper — remove it. If the complexity reappears across N callers, the module was earning its keep — deepen it instead.
7. **One adapter means a hypothetical seam; two mean a real one.** Don't introduce an interface / port unless at least two adapters are justified — typically production + test. A single-adapter seam is indirection without depth: the interface has exactly one meaning, so callers pay the extra hop and gain nothing.

## Anti-vocabulary (reject these framings)

- **"Add an abstraction"** — abstractions are not the goal; depth is. An abstraction without depth (e.g., a wrapper that adds nothing) is *worse* than no abstraction.
- **"Make it more flexible"** — flexibility without a concrete deepening or seam-narrowing rationale is YAGNI. Add complexity only when it absorbs change.
- **"Refactor for testability"** — if a module is hard to test, the seam is wrong, not the test framework. Fix the seam.
- **Counts and ratios as the measure** — implementation-lines over interface-lines, exported-symbol totals, import tallies. They reward padding the implementation or splitting one surface into many small exports. Ask what a caller must know and what a change would reach.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "These terms are obvious; skills don't need to cite them" | Without a single source, each skill drifts into its own vocabulary ("layer", "boundary", "facade"). Cross-skill handoffs (architect → reviewer, debug → implement) lose meaning. |
| "Another tool uses a different word for this — switch to match it" | Stay with these terms once defined. The point is consistency across these skills, not external alignment. Keep this file canonical and reference it. |
