## Severity tiers (shared output classification)

Dimensions are review lenses; tiers classify the output. Every finding gets exactly one tier.

| Tier | Name | Admits |
|---|---|---|
| T0 | Safety | Hook bypass holes, secret-leak paths, data-loss vectors, fail-open where fail-closed is required |
| T1 | Correctness | Logic bugs, gates that can never fire, producer/consumer schema mismatch, shell bugs with behavioral impact, untested live data-mutating code |
| T2 | Rule violations | Breaches of `.claude/rules/*` hard exclusions or hard structural rules (description length past `.claude/rules/skill-structure.md` §Frontmatter hygiene, reference-graph inversion, non-English, dangling refs) |
| T3 | Staleness & drift | Dead references, doc-vs-reality drift, stale conditionals, orphaned files |
| T4 | Maintainability | Duplicated single-source content, unexplained or multi-homed constants, anti-rationalization dead weight, latent-but-unreachable defects, test-coverage-map gaps |

**There is no cosmetic tier, and its absence is the rule.** Caps emphasis, provenance citations, heading case, terminology, phrasing that "reads better" — a run does not report these at all. They were a tier for seven rounds and produced the pipeline's largest finding class and its smallest effect: prose edits from this pipeline survived at 6% against 86% for code, so the round after each cosmetic sweep re-raised what the sweep had just rewritten. A cosmetic observation is not a small finding here; it is not a finding. Where one of these classes turns out to be decidable after all, it becomes a check per §Mechanize what recurs — `lint-prose-and-links.sh` already owns heading case that way.

