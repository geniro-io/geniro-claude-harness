## Severity tiers (shared output classification)

Dimensions are review lenses; tiers classify the output. Every finding gets exactly one tier.

| Tier | Name | Admits |
|---|---|---|
| T0 | Safety | A secret, token, or credential quoted inside an instruction file; an instruction directing agents to bypass safety — disable TLS verification, force-push, skip hooks or permission prompts, run untrusted scripts as a required step |
| T1 | Misleading instruction | A factually wrong instruction an agent would follow into wrong behavior — a documented command that doesn't exist, a load-bearing path that moved, a stack claim the lockfile contradicts; a parse-breaking format defect that silently disables a rule (malformed `.mdc` or `.instructions.md` frontmatter, a glob that matches nothing) |
| T2 | Cross-tool contradiction | Two surfaces giving opposite guidance; the same threshold with different values; mirror copies that drifted apart |
| T3 | Staleness | References to removed code, tools, or workflows that decay rather than actively mislead; a legacy-format file coexisting with its replacement |
| T4 | Bloat & maintainability | Restatements, model-known instruction, over-constraint, hand-maintained duplicates that still agree, oversized always-on files, scoping misuse, coverage gaps |

**There is no cosmetic tier, and its absence is the rule.** Heading case, tone, phrasing that merely reads better — a run does not report these at all. Measured across repeated rounds of an audit pipeline of this shape, cosmetic edits survived at 6% against 86% for the mechanically decidable ones, so each sweep's rewrites were re-raised by the round after it. A cosmetic observation is not a small finding here; it is not a finding. Where such a class turns out to be mechanically decidable after all, it belongs in a linter, not in a tier.

The T1/T3 line is behavioral: T1 when an agent following the text does the wrong thing (runs a wrong command, edits a wrong path); T3 when the text merely wastes attention or gets ignored. When in doubt, ask what a fresh agent session would actually do with the sentence.

