## Do-not-flag list (endorsed patterns)

Re-flagging these is the audit's own false-positive failure mode:

- **Deliberate cross-tool mirroring without drift** — `AGENTS.md` symlinked to or generated from `CLAUDE.md` (or the reverse). Flag drift between the copies; never the mirroring itself.
- **A short CLAUDE.md.** Brevity is healthy — an instruction file's job is signal density, not completeness. A coverage finding needs an activity signal AND a concrete missing fact, never "this file seems thin".
- **Rich trigger-keyword skill descriptions** in `.claude/skills/**/SKILL.md` frontmatter — the description is the routing surface the tool selects skills by; keyword density is load-bearing. Flag only genuine description-vs-body drift (D2's territory).
- **Single-homed justified thresholds.** A number stated once with an adjacent reason stays numeric. Only restated or contradicting values are findings (D3).
- **User-global files outside the repo** — `~/.claude/CLAUDE.md` and per-user tool settings are not repo surfaces; nothing about them is in scope.
- **Personal-overlay divergence.** `CLAUDE.local.md` (and equivalents) differing in preference from team files is the overlay working as designed; only factual wrongness or safety issues in them are findings.
- **Tool-specific phrasing of the same rule.** A Cursor rule worded for Cursor's loading model is not a contradiction of the CLAUDE.md wording when both carry the same rule.
- **Structural shape of `.geniro/instructions/*.md`** — owned by `/geniro:instructions validate`; route rather than flag.
- **A reason attached to a rule an agent would otherwise rationalize around.** An anti-pattern, an escape hatch, or error semantics carries its why so the constraint survives contact with an edge case the wording never anticipated. That is payload, not provenance — D4 check 9 hunts the case *for* a rule, never the reason *inside* one.
- **A link the rule requires following.** A URL an agent must fetch to do the work — a schema, an API reference, a runbook — is a data source, not a citation. Only a link supporting an argument is in check 9's range.
