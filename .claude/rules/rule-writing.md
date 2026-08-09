---
paths:
  - ".claude/rules/**/*.md"
  - "CLAUDE.md"
---

# Editing a rule file

A rule file is payload for a model that has to act on it, not a document arguing its own case. Write the rule; drop the case.

**Ships — the rule:**

- The instruction, in requirement form (`skill-prose.md` §"Explain WHY, don't shout MUST" on why prohibitions decay).
- The reason, only where the model would otherwise rationalize around the rule — anti-patterns, escape hatches, error semantics. That same section draws the line.
- Values a run has to match exactly: paths, thresholds, schemas, canonical labels.
- A bare link where a counterintuitive rule needs evidence to stop being re-litigated. The link, not a summary of it.

**Doesn't ship — the case for the rule:**

- Source lists, "per X verbatim" quote blocks, attribution paragraphs. Restate the rule in your own voice; a citation is not a rule.
- Evidence grading ("where this rests on measurement it says so; treat unlabelled as taste"). Grade while authoring, publish the result.
- Refutations of theories the rule is *not* founded on. The reader was never going to apply the wrong theory.
- How the rule got here — the prior version, the incident, the debate.
- Restatement of a neighbouring rule for emphasis.

**Bounds.** A compression pass cuts the case, never the rule. Removing a rule is a separate decision with its own evidence bar — `skill-prose.md` §Token budget awareness carries that bar, the reduction ceiling, and the path-scoping alternative to deletion.

**Before committing**, confirm every heading another file cites by `§` still exists — `grep -rn "<filename>" --include=*.md --include=*.sh .` finds the citing sites. A renamed or dropped heading breaks a live cross-reference in a skill, an agent prompt, or the lint.
