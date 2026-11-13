## Do-not-flag list (endorsed patterns)

Verified healthy by prior audit — re-flagging these is a false positive. The bracketed tag names the dimension(s) an entry binds: Phase 2 pastes the `[universal]` entries plus those tagged with the spawning reviewer's own dimension (§Reviewer spawn template).

- **[universal]** **Resolving `§N` section anchors** — content anchors are the endorsed cross-reference form; only dangling or inverted ones are defects.
- **[D4, D6]** **Caps inside anti-rationalization right-hand cells** accompanied by reasoning.
- **[D7]** **Justified magic numbers with adjacent WHY** (convergence ≥2/≥3, ≤50-file scan cap, 4096 PIPE_BUF) — keep numeric. A **single-homed** value only: D7's multi-homed, prose-count and ordinal checks stay in force.
- **[D4]** **Author-facing tier/layer codes (T1/L4/m6-v2) and decision-type tags** in architecture docs (`CLAUDE.md` §Memory Layers, `state-tier-spec.md`) and skill-body declarative prose — the plain-English rule binds user-facing strings, so only leakage into them is a defect.
- **[D6]** **Size guidelines treated as guidelines** — a SKILL.md a few hundred words past the whole-file guideline is advisory.
- **[D3]** **Deleted-skill names inside README.md's "Skills deleted" table and MIGRATION.md** — documentation of the deletion.
- **[D6]** **Rich SKILL.md `description:` fields** — the description is the sole signal for skill selection, so its trigger keywords are load-bearing. Flag only length past the limit (D1 checks it) or body drift (D2 §Description-vs-body drift), never verbosity.
- **[D8, D9]** **The deliberately-unwired Cursor hook** (update-check) — its absence from `cursor/hooks.json` is documented, as that event maps to no Cursor slot; only a WIRED guard that fails open under the shim is a defect.
- **[D2, D3]** **`cursor/agents/*.md` divergence from `agents/*.md`** in dropped fields (`tools`, `maxTurns`, forced `model: inherit`, added `readonly`) — the generator's contract; `tests/cursor/build-agents-fresh.sh` catches real drift.
- **[D4]** **`agents/<name>-reference.md` companions** — body-overflow targets with no agent frontmatter by design; also the `maxTurns` exemption in D1's frontmatter check.
- **[D9]** **A first load site prescribing `MODE: refresh`** — `load-custom-instructions.md` §When to invoke allows it at a consumer's Phase 1 entry (`refactor` and `implement` do); D9 flags a *missing* refresh site only.
- **[D2, D9]** **`MODE:` values outside the loader's set** — the slot is shared by `spec-challenge.md`, `library-reuse-audit.md` and `task-chain-context.md`, each with its own values; `MODE: plan` is a defect only when the helper invoked is the instruction loader.
- **[D9]** **An optional instruction block absent from a project** — `## Data Sources`, `## Verification Surface` and `## Memory Backend` are opt-in; the check asks whether the plugin has an execution site, not whether a project authored one.
- **[universal]** **A reason attached to a rule the model would otherwise rationalize around** — payload. Where the reason itself looks spent, that is D6's over-constraint bar.
- **[D6]** **The argument a rule ships with** — provenance, evidence grading, a refuted theory, how the rule arrived. An audit leaves the argument alone; `rule-writing.md` binds the author.
