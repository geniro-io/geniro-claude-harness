# Architecture review criteria


Assess structure: coupling, layering violations, API contracts, duplication, wrong abstraction.

## Common false positives

1. **Pragmatic design** — Sometimes coupling is acceptable for simplicity
- Framework integration often requires tight coupling
- Small projects don't need full SOLID adherence
- Check project size and constraints

2. **Intentional repetition** — Code reuse isn't always beneficial
- Duplicating code for different contexts is sometimes correct
- Premature abstraction creates worse problems
- Only flag if obvious shared logic exists

3. **Framework patterns** — Many frameworks violate SOLID on purpose
- Rails/Django models do multiple things by design
- Framework code patterns don't apply to app code
- Check if pattern is framework-recommended

4. **Configuration-driven behavior** — Behavior controlled externally
- Configuration injection addresses tight coupling
- Check if values come from proper config sources
- Don't flag if using DI framework

5. **Learning code** — New developers might use older patterns
- Code reviews should mentor, not just criticize
- Consistency matters, but growth is important
- Consider context and codebase age

6. **Intentional simplification** — Simple code beats perfect design
- Don't flag over-engineering fears
- Some coupling is acceptable for simplicity
- Only flag if causing real problems


## Severity guidelines

Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1.

- **CRITICAL** — Never emitted by this dimension. Architecture findings cannot block deploy on their own — they signal design risk, not immediate breakage. A semantic mutation that silently drops data from user-visible surfaces (per §1.5 Caller-Blast Check) is a runtime defect owned by the bugs dimension, not an architecture CRITICAL.
- **HIGH** — Caller-blast >= 10 surviving callers, or a public-API / module-export / shared-type change at any count, when a contract changes (per §1.5 Caller-Blast Check thresholds in this file); circular dependency introduced where none existed; new tight coupling between modules that prior architecture explicitly decoupled (cite the decoupling source); new shared mutable state across boundaries; N+1 pattern in a request-handling path; a type-design gap (per §1.7) where an escape hatch or public mutable field lets a cross-module caller construct an illegal state a downstream consumer assumes cannot exist; hand-rolled crypto / auth / parsing a battle-tested library would secure (per §7.5 reinvented-wheel).
- **MEDIUM** — Caller-blast 4-9 callers on a contract change; coupling increase with documented future remediation cost (e.g., the dimension flagged a similar coupling in a prior PR surfaced via the inline `PEER-PR CONTEXT:` slot); module-boundary violation that requires a sibling module to know an implementation detail; a type-design gap (per §1.7) contained to one module and guarded by convention at each use site today; reinvented-wheel / build-vs-buy where a maintained library already solves the hand-written code (per §7.5, typical tier); function-level complexity / deep nesting (per §4.5) on a critical path where the cognitive load raises real defect risk.
- **LOW** — Stylistic structural suggestions ("this would be cleaner as a class"); coupling concerns without measured blast radius; "consider splitting this module" without a defect or growth-pressure citation; excessive function-level nesting / cognitive load (per §4.5) on a non-critical path; documentation or PR-description nits about an architectural area.
