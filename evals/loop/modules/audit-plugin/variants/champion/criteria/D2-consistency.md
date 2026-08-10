## D2 — Cross-file consistency

**Scope:** `CLAUDE.md`, `README.md`, `HOOKS.md`, `ARCHITECTURE.md`, `CONTRIBUTING.md`, `MIGRATION.md`, `skills/`, `agents/`, `hooks/` (the docs-vs-reality-drift check below compares doc claims against actual script matchers), `lib/` (the helper-contract-drift check below compares helper contracts against the scripts). **Method:** LLM reviewer, grep-grounded.

Checks:
1. **Docs-vs-reality drift.** CLAUDE.md skills table, README, HOOKS.md, ARCHITECTURE.md, and CONTRIBUTING.md claims vs actual skill/hook/helper behavior: listed skills exist, described flags/phases/paths match the SKILL.md body, hook descriptions match the script's actual matchers and bypass IDs, design rationale cited from ARCHITECTURE.md still matches the code that cites it.
2. **Description-vs-body drift.** Each SKILL.md frontmatter `description:` vs what the body actually does (flags, phases, outputs).
3. **Schema lockstep.** For every state-file / handoff field a producer writes (per `skills/_shared/state-tier-spec.md`), confirm consumers read the same field name and shape; flag fields written-but-never-read or read-but-never-written. Hit count carries no signal here — a written field always has hits, so classify each as a write, a read, or a schema declaration and report when none is a read (or none is a write). Name both remedies and say which is cheaper: an unwired producer is as often a missing feature as it is dead weight.
4. **Helper contract drift.** For each `_shared/*.md` helper and `lib/*.sh` script: do callers pass the slots / flags / MODE values the contract defines? Do cited exit codes match the script?
5. **Single-source violations.** Pseudo-code blocks, slot tables, or schema definitions duplicated across ≥2 files (the rule: one source, others cite it).
6. **Spawn-site consistency.** Every plugin-agent spawn follows the `spawn-agent.md` ladder and the OMIT-`model=` rule for carve-out agents; flag sites that contradict the skill's own tiering table.
Tier mapping: schema mismatch with behavioral impact → T1; doc drift / duplication → T3 / T4.

