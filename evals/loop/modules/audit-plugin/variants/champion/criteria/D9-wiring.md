## D9 — Wiring completeness (declared vs. wired)

**Scope:** `skills/`, `agents/`, `hooks/hooks.json`, `.claude/rules/`, with `skills/_shared/` as the contract source. **Method:** LLM reviewer seeded with the D1 declaration inventory.

**Charter.** Find what is **declared but never wired** and what is **wired against a declaration that does not resolve**, across the kinds no other dimension owns: the instruction layer, load sites, phase structure, gates, template slots, claimed enforcement (D1's no-execution-site grep covers `_shared/` helpers, lib scripts and agents). Only the missing half is filed here: a declaration that *contradicts* rather than *dangles* goes to its owner at the owner's tier — a field written but never read → D2 §Schema lockstep; a gate that can never fire → D5a §Unfireable gates; a guard matcher missing a tool → D8 §Matcher coverage; a reference to something deleted → D3.

**Absence is the finding, so prove it.** Search every name the thing travels under — a block by heading *and* plain-English description, a gate by question text *and* the decision it makes, a phase by number *and* name — and name the searches in `evidence`; a bare "no hits" is inadmissible. **The commonest false positive is counting a mention as a wiring:** a skill that *authors* a block, a validator that *checks its shape* and a loader that *parses* it are all mentions — classify each hit author / validate / parse / execute; only the phase acting on the parsed value is the execution site.

Checks:

1. **Instruction-block consumption.** Every block the loader's §Producer contract parses (`## Rules`, `## Constraints`, `## Additional Steps`, `## Data Sources`, `## Verification Surface`, `## Memory Backend`) reaches an execution site; one that users author and the loader parses but no phase acts on silently does nothing while every visible step succeeds. An `## Additional Steps` subsection naming a boundary no consumer has is a no-op when the name is simply wrong. A bare heading grep misleads — helper files carry their own `## Constraints` and `## Rules` (`ui-preview-gate.md`, `update-semantic.md`) — so read the site.
2. **Load-site coverage.** Each loader call site names a `SKILL_SLUG` matching its skill directory (a mismatch loads as absent forever), a `LOAD_TIER` the loader defines, and a `MODE`; a pipeline skill with an initial load and no refresh site loses its rules at compaction. **`MODE:` is an overloaded slot name** — `spec-challenge.md`, `library-reuse-audit.md` and `task-chain-context.md` each define their own values; bind it to the helper actually invoked, not to the token.
3. **Phase structure.** Every phase in the overview has its `## PHASE N` heading and a pointer resolving to a body file that states the entry Read and echo; the Definition of Done has an exit gate for each phase that can ship something. Flag both directions — external files cite phases by number.
4. **Gate wiring.** Every user decision a skill declares (overview, Approval Points, Definition of Done, `approvals[]`) has an `AskUserQuestion` fire site in the body or its phase file; a gate with rich content cites the render contract rather than restating it.
5. **Template slots.** Every `{{slot}}` a template declares is filled at every site, and every filled slot exists — an unfilled one reaches the subagent as literal braces, read as missing context. An agent whose workflow prescribes an instruction load declares the load report in its output schema.
6. **Claimed enforcement with no mechanism.** Prose saying "mechanically enforced", "hard-blocked" or "the hook blocks this" names a hook that exists in `hooks/` and is registered in `hooks.json`; claim and hook both existing with differing details is D2's drift.

Tier mapping: an authorable declaration no site consumes, an unresolvable slug or tier, and an unfilled slot the spawn depends on → T1 (the feature does not work); a safety guard claimed in prose with no hook behind it → T0; a promised gate never built → T1 when it guards an external effect, T3 otherwise; missing refresh site, unfilled non-load-bearing slot → T4; phase-structure and Definition-of-Done gaps → T3.

**Report the searches, not just the gaps:** which declaration kinds you enumerated, how many sites each had, which apparent gaps you resolved as author/validate/parse mentions. "Wiring healthy" without that is indistinguishable from tracing nothing.

---

