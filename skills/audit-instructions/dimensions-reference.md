# Instruction-audit dimensions reference

Per-dimension rubrics for `/geniro:audit-instructions`. Each dimension defines its scope, what to look for, and how findings map to severity tiers. The orchestrator pastes ONE dimension section into each reviewer's prompt — reviewers never read this file themselves.

## Contents

- Surface inventory (canonical)
- Run setup
- Reviewer spawn template
- Fix-round execution
- Severity tiers (shared output classification)
- Finding output contract (shared reviewer schema)
- D1 — Mechanical pre-pass (deterministic, no reviewer)
- D2 — Accuracy vs repo reality
- D3 — Cross-tool consistency
- D4 — Bloat & over-constraint
- D5 — Structure & scoping
- D6 — Coverage & safety
- Do-not-flag list (endorsed patterns)

---

## Surface inventory (canonical)

One row per tool. Phase 0 enumerates the path column with Glob to build the run's inventory; a surface absent from the repo drops out of scope, and its absence feeds D6's coverage check when the tool shows other signs of use. The loading notes are D5's rubric input: what a file costs depends on when its tool loads it.

| Tool | Paths | Format & loading notes |
|---|---|---|
| Claude Code | `CLAUDE.md` (root and nested per-directory), `CLAUDE.local.md`, `.claude/rules/*.md`, `.claude/skills/**/SKILL.md`, `.claude/agents/*.md`, `.claude/commands/*.md` | Root `CLAUDE.md` and `CLAUDE.local.md` load whole every session (always-on); nested `CLAUDE.md` loads when working in its directory; `.claude/rules/*.md` scope via `paths:` frontmatter (no `paths:` = always-on); skills route via frontmatter `description`; commands load on explicit invocation |
| Cross-tool standard | `AGENTS.md` (root and nested) | Read whole by Codex, Cursor, Copilot, and most newer agents; commonly symlinked to or generated from `CLAUDE.md` — endorsed, see §Do-not-flag list |
| Cursor | `.cursor/rules/*.mdc`; legacy `.cursorrules` | `.mdc` frontmatter: `description` / `globs` / `alwaysApply`. `alwaysApply: true` = every session; `globs` = attached when a matching file is in context; `description` alone = model-requested. `.cursorrules` is the deprecated single-file form |
| GitHub Copilot | `.github/copilot-instructions.md`, `.github/instructions/*.instructions.md` | `copilot-instructions.md` attaches to every request (always-on); `.instructions.md` scopes via `applyTo` frontmatter glob |
| Windsurf | `.windsurf/rules/*.md`; legacy `.windsurfrules` | Legacy single-file form deprecated |
| Cline | `.clinerules` (file or directory) | Loaded whole |
| Gemini CLI | `GEMINI.md` | Loaded whole |
| Aider | `CONVENTIONS.md` | Loaded whole when configured |
| JetBrains Junie | `.junie/guidelines.md` | Loaded whole |
| Zed | `.rules` | Loaded whole |
| Amazon Q | `.amazonq/rules/*.md` | Loaded whole |
| Geniro | `.geniro/instructions/*.md` | In scope for every dimension; per-file structural lint alone is owned by `/geniro:instructions validate` — route structural findings there instead of duplicating that lint |

**Scope boundaries.**
- User-global files (`~/.claude/CLAUDE.md`, per-user Cursor or Copilot settings) live outside the repo and are out of scope.
- `CLAUDE.local.md` and other personal-overlay files are in scope for accuracy and safety, but a personal preference differing from the team files is the overlay's design, not drift.

**Activity signals.** Alongside the surfaces, record per tool whether the repo shows the tool in active use — its config or state directories (`.cursor/`, `.windsurf/`, `.claude/`), CI jobs invoking it, its lockfiles or settings committed. D6's "tool in use, no instructions" check consumes this; a coverage claim without an activity signal is speculation.

## Run setup

Read at Phase 0 alongside the rubric sections.

**Inventory** — record in the state checkpoint: per tool, the surfaces found (with `wc -w` per file), the activity signal (present/absent), and whether the surface is always-on or scoped per the loading notes above.

**State checkpoint** — write `.geniro/state/audit-instructions/<slug>/state.md`, slug per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` §Slug rules. Write via `atomic_state_write` (source `${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh` — a direct `Write` to a `.geniro/state/` path trips the state-helper hook), with the full T1.5 YAML frontmatter starting on line 1: `tier: T1.5`, `producer: audit-instructions`, `schema-version: 1`, `branch`, `worktree`, `timestamp`, `phase`, `status`, `non-resumable-actions: []`. Plain-text header lines before the `---` fence fail `validate_state_file`. Each checkpoint records: phase completed, scope, dimensions selected, finding counts, reviewer findings-file paths.

## Reviewer spawn template

Pasted by the orchestrator at Phase 2. Every slot is filled before the spawn — a reviewer that has to discover its own rubric will invent one.

```
Agent(subagent_type="general-purpose", prompt="""
## Task: AI-instruction audit — dimension D<N> (<name>)

You are one reviewer in a multi-dimension audit of this repo's AI-assistant
instruction files. Review ONLY your dimension; other dimensions are covered
by parallel reviewers.

### Your rubric
{{the full D<N> section from dimensions-reference.md}}

### Severity tiers and output contract
{{§Severity tiers + §Finding output contract}}

### Do-not-flag list
{{§Do-not-flag list, plus any patterns the prior report's health summary endorsed}}

### Your file scope
{{the inventory subset for this dimension, from Phase 0}}

### Mechanical pre-pass context
{{battery summary; plus this dimension's candidate lists when Phase 1 produced them}}

### Procedure
1. Read every file in your scope in full — instruction files are short, and a
   skim misses the reworded half of a duplicated rule. Grep the wider repo only
   to check a specific claim (does this command exist, does this path resolve).
2. Verify each candidate finding by reading the exact cited lines — your
   `evidence` column must be a verbatim quote. Exception: a secret is cited by
   location and shape, never quoted.
3. Return only the findings table per the output contract (max 25 rows) plus a
   2-3 sentence verdict for your dimension ("healthy / debt concentrated in X").
Report only — do not edit any file, and do not review outside your dimension.
""", description="Instruction audit: D<N> <name>")
```

Dimension-specific paste notes:
- **D2 (accuracy):** paste the Phase 1 command and path candidate lists into the pre-pass context slot.
- **D3 (consistency):** paste the same-rule candidate list.
- **D5 (structure) and D6 (coverage & safety):** additionally paste §Surface inventory — the loading notes and activity signals are their rubric inputs; keep the facts single-sourced there rather than restated per dimension.
- **D6:** paste the secret-scan candidate locations (file:line + pattern name only — the values were never captured).
- **Sharding:** if a dimension's scope exceeds ~10K words, split the file list into two halves covering every file between them, same prompt, both spawns in the batch.

## Fix-round execution

Read at Phase 5 when a fix path is approved. The disjoint-scope grouping, the ownership assert, and the 1-round budget are in SKILL.md §Phase 5; this section is what happens after the agents are spawned.

**Three things reliably happen — plan for them rather than treating each as an exception.**

1. **An agent finds more instances of its defect class outside its own files.** It reports them; you ground-truth the claim with a grep before routing it to the owning agent. Never let it reach across its allowlist.
2. **An agent judges a finding's stated fix wrong and says so instead of complying.** Treat that as the mechanism working. Verify the correction yourself, then amend the report row — a fix instruction written from a grep hit can be wrong in ways only the editing agent sees.
3. **A correct fix in one file breaks a mirror or a cross-reference in another.** Editing `CLAUDE.md` leaves a generated `AGENTS.md` copy stale; renaming a section breaks another surface's pointer to it. After the round, re-check every mirror pair and every cross-surface reference into a changed file, and route each repair to whoever owns the referencing file. A symlink needs nothing; a generated copy needs regenerating — do that once at the end of the round, never per-agent, since it races every agent that edited the source.

**An agent that dies mid-run has usually already written its edits.** Ground-truth the working tree rather than assuming either outcome — a per-finding grep tells you what landed far faster than re-spawning.

**Verification, in order.** Re-run the Phase 1 battery over the touched files (an edited `.mdc` or `.instructions.md` must still parse — a fix that breaks frontmatter converts a stale rule into a silently disabled one); Read each changed location to confirm the finding is resolved; re-check mirror integrity.

## Severity tiers (shared output classification)

Dimensions are review lenses; tiers classify the output. Every finding gets exactly one tier.

| Tier | Name | Admits |
|---|---|---|
| T0 | Safety | A secret, token, or credential quoted inside an instruction file; an instruction directing agents to bypass safety — disable TLS verification, force-push, skip hooks or permission prompts, run untrusted scripts as a required step |
| T1 | Misleading instruction | A factually wrong instruction an agent would follow into wrong behavior — a documented command that doesn't exist, a load-bearing path that moved, a stack claim the lockfile contradicts; a parse-breaking format defect that silently disables a rule (malformed `.mdc` or `.instructions.md` frontmatter, a glob that matches nothing) |
| T2 | Cross-tool contradiction | Two surfaces giving opposite guidance; the same threshold with different values; mirror copies that drifted apart |
| T3 | Staleness | References to removed code, tools, or workflows that decay rather than actively mislead; a legacy-format file coexisting with its replacement |
| T4 | Bloat & maintainability | Restatements, model-known instruction, over-constraint, hand-maintained duplicates that still agree, oversized always-on files, scoping misuse, coverage gaps |
| T5 | Cosmetic | Heading style, tone and formatting inconsistencies |

The T1/T3 line is behavioral: T1 when an agent following the text does the wrong thing (runs a wrong command, edits a wrong path); T3 when the text merely wastes attention or gets ignored. When in doubt, ask what a fresh agent session would actually do with the sentence.

## Finding output contract (shared reviewer schema)

Every reviewer returns a Markdown table with EXACTLY these columns, one row per finding, capped at 25 rows (rank by impact; note "N further low-impact items omitted" if capped):

| Column | Content |
|---|---|
| `id` | `D<dim>-<n>` (e.g. `D2-4`; shards keep their label — `D4-shardA-1`) |
| `tier` | T0-T5 per the table above |
| `file:line` | Real location — verified by the reviewer with Read before reporting. Use `file:start-end` for ranges. |
| `issue` | One sentence, plain English |
| `evidence` | Verbatim quote (≤2 lines) from the cited location — the orchestrator re-verifies this quote exists. For a secret: the location and credential shape only ("line contains what appears to be a live AWS access key"), never the value — the finding table feeds a persisted report. |
| `fix` | Concrete suggested change, one sentence |
| `effort` | S / M / L |

A finding without a verifiable `file:line` + `evidence` is inadmissible — drop it rather than guessing a location.

---

## D1 — Mechanical pre-pass (deterministic, no reviewer)

**Scope:** every surface in the run's inventory. **Method:** the orchestrator runs this battery inline in Phase 1; no spawn.

| Check | Procedure | Output |
|---|---|---|
| Surface discovery | Enumerate the §Surface inventory globs; record found files, word counts, activity signals | The inventory; context for D5/D6 |
| Cited-path existence | Extract path-shaped tokens from every instruction file; test each against the repo | Nonexistent paths → CANDIDATES for D2 (an illustrative example path is not a defect; a load-bearing one is — that split needs reading) |
| Command extraction | Extract backtick commands; check each against the repo's manifests (package scripts, Makefile, task runners, CI workflows) | Unmatched commands → CANDIDATES for D2 (a command may be globally installed — adjudication, not auto-flag) |
| Frontmatter validity | Parse every `.mdc` (`description` / `globs` / `alwaysApply`) and `.instructions.md` (`applyTo`) frontmatter | Machine finding T1 when malformed or missing such that the rule never loads |
| Legacy formats | Detect `.cursorrules` / `.windsurfrules` | Machine finding: T3 when the replacement directory also exists (two sources of truth); T4 advisory when legacy-only (migration proposal) |
| Same-rule candidates | Grep for rule-shaped content (commands, thresholds, distinctive imperative phrases) appearing across ≥2 surfaces | CANDIDATES for D3 |
| Secret scan | Pattern battery for credential shapes (API keys, tokens, connection strings with passwords) over every surface; record file:line + pattern name only — the matched value is never captured into any output | CANDIDATES for D6 (adjudication separates live credentials from placeholders like `sk-your-key-here`) |

Machine findings are pre-verified and skip Phase 3 re-reads; candidates are not findings until a reviewer adjudicates and the orchestrator verifies.

## D2 — Accuracy vs repo reality

**Scope:** every surface. **Method:** reviewer seeded with D1's command and path candidates.

Instruction files are trusted ground truth for every future agent session — a wrong instruction doesn't fail once, it misleads every run until someone notices. That is why this dimension tiers high.

Checks:
1. **Dead commands.** Documented build/test/lint/deploy commands absent from the repo's manifests, scripts, and CI (adjudicate the D1 candidates; check whether the command is a global tool the repo's toolchain evidence supports before flagging).
2. **Moved or removed paths.** Cited files and directories that no longer exist. Distinguish load-bearing ("config lives in `src/config.ts`") from illustrative ("e.g. a file like `foo/bar.ts`").
3. **Stack and version claims.** Framework, language, and tool claims contradicted by lockfiles and manifests — "we use React 17" against a v19 lockfile entry; a described package manager the repo's lockfile format contradicts.
4. **Described workflow vs reality.** Documented processes (migrations, release steps, codegen) whose scripts or tools are gone or renamed; conventions stated as current that the codebase visibly abandoned.
5. **Cross-surface pointers.** An instruction file citing another instruction file or section that no longer exists.

Tier mapping: actively misleads an agent → T1; decayed but ignorable → T3.

## D3 — Cross-tool consistency

**Scope:** every surface, `.geniro/instructions/*.md` included. **Method:** reviewer seeded with D1's same-rule candidates.

Checks:
1. **Direct contradictions.** One surface says X, another says not-X — commit-message rules, formatting, test-first policy, tool choices → T2.
2. **Threshold divergence.** The same limit with different values across surfaces (line length, coverage floor, file-size cap) → T2.
3. **Mirror drift.** Where `AGENTS.md` (or another surface) is symlinked to or generated from `CLAUDE.md`: verify the symlink resolves or the generated copy matches its source. Drift → T2. The mirroring itself is endorsed — flag only the drift.
4. **Hand-maintained duplicates that agree.** The same rule copied across surfaces with no symlink or generation mechanism → T4, even while the copies match: agreement today is drift tomorrow. Propose one home (the richest surface, usually `CLAUDE.md` or `AGENTS.md`) with the others pointing at it, or a mirroring mechanism.
5. **Material guidance divergence.** The same topic covered non-contradictorily but differently enough that an agent on one tool would surprise a teammate on another → T4, judgment call. Tool-specific phrasing carrying the same rule is not a finding (§Do-not-flag list).

## D4 — Bloat & over-constraint

**Scope:** every surface. **Runs on every audit** — full, scoped, or `--quick`; on a scoped run it inherits the run's scope, and on `--quick` the orchestrator sweeps inline. **Method:** reviewer. The goal is REMOVAL/COMPRESSION candidates — every finding proposes one concrete action: delete, shorten, merge, or move to a scoped surface (D5 owns the move mechanics). Apply the per-line test to every candidate: "would removing this make an agent err?" If not, it is weight without payload. For prohibitions and edge-case text the test has to name the case — a guard's removal never fails the happy path, so ask what an agent does on the case the text exists for; when you cannot name that case, the text may genuinely be spent.

Checks:
1. **Restatements.** The same rationale stated twice in one file; "in other words" summaries; a rule restated in slightly different wording two sections later.
2. **Hedges without conditions.** "May or may not", "depending on the situation" — commit to the condition or cut the line.
3. **Model-known instruction.** Text re-explaining what any capable agent already does — "write clean code", "read a file before editing it", "git is used for version control". The most common failure of the per-line test.
4. **Over-specified mechanics.** Shell recipes, prescribed loop shapes, platform hand-holding where a goal plus a bound suffices. State what, not how, unless the how is a project contract (an exact path, schema, or canonical command).
5. **Guardrails written for weaker models.** Blanket prohibitions where a criterion would let the agent read the situation ("never write comments" vs "match the file's comment density"); shouted emphasis standing in for a reason. A project contract — exact path, threshold with a stated why, canonical option — is not this shape and stays.
6. **Dead instructions.** Text governing code, tools, flags, or workflows that no longer exist. Route by referent: a wrong factual claim belongs to D2, a drifted duplicate to D3 — only dead text with no such owner lands here.

Every removal proposal names what breaks if the removal is wrong. A shorten or merge proposal additionally carries a **preserved inventory** — the spans the rewrite must reproduce verbatim: commands, paths, thresholds, frontmatter fields, globs, and any string a tool parses. Those are contracts, not prose; a reword that drifts one of them silently disables it.

**There is a ceiling on the proposal.** Instruction files are constraint payload nearly end to end, and compliance degrades faster than readability as they shrink — a proposal taking most of a rule-dense file loses rule-following in ways no re-read can show. Prefer scoping (move the rule to a path-scoped surface) over deletion when the rule is load-bearing for one kind of work.

**Return the sweep, not a quota.** Zero findings is a valid outcome; a manufactured deletion is worse than none, because a deletion is the one finding whose wrongness the user cannot notice later. Name what you examined (which files, which checks, where you looked hardest), name the candidates you considered and rejected with the reason, and say plainly when the pass found nothing — the rejections go in the verdict, not the table, and they are what stops the next run re-litigating them.

Tier mapping: T4 by default; pure style → T5; a drifted restatement that now contradicts its sibling → route to D3 as T2.

## D5 — Structure & scoping

**Scope:** every surface. **Method:** reviewer; the orchestrator pastes §Surface inventory into the prompt — the loading notes there are this dimension's cost model. The core question: is each piece of content on the cheapest surface its tool offers, given when that surface loads?

Checks:
1. **Oversized always-on files.** A root `CLAUDE.md`, `copilot-instructions.md`, `AGENTS.md`, or `alwaysApply` rule whose cost is paid every session, carrying content only some sessions need. Size alone is not the finding — size times always-on loading is.
2. **Scoping misuse.** A rule applying to one directory or file type living in an always-on file when the tool supports scoping — `.claude/rules` `paths:`, `.mdc` `globs`, `.instructions.md` `applyTo`, a nested `CLAUDE.md` or `AGENTS.md`. Propose the move, naming source and destination.
3. **Monolith splitting.** One very large file where the tool supports a rules directory; propose the split by concern.
4. **Missing navigation.** A very long instruction file with no contents block near the top — tools that partially read see only the head.
5. **Wrong-surface content.** Session narration, changelogs, TODO lists, or design history inside instruction files — it costs attention on every load and belongs in docs or git history.

Tier mapping: T4. A move proposal names what loads less often afterward; a move to a surface every session loads anyway saves nothing.

## D6 — Coverage & safety

**Scope:** every surface, plus the repo's manifests and CI for the essentials check. **Method:** reviewer; the orchestrator pastes §Surface inventory (for the activity signals) and the D1 secret-scan candidate locations.

Checks:
1. **Secrets.** Adjudicate the D1 candidates and read every surface for credential-shaped content the patterns missed. A live credential → T0. Cite the location and shape only — the value never enters the findings table, the report, or chat. A clearly-marked placeholder is not a finding.
2. **Unsafe directives.** Instructions that direct agents to disable TLS verification, force-push, bypass hooks or permission prompts, run untrusted downloads, or suppress errors as a required step → T0, whether or not intentional — surface it and let the user decide.
3. **Missing essentials.** Build, test, and lint commands documented in no surface while the repo plainly has them (manifest scripts, Makefile targets, CI steps as evidence) → T4. The evidence is mandatory: name where the command exists and that no surface mentions it.
4. **Tool in use, no instructions.** A tool with an activity signal (config/state dirs, CI jobs, committed settings) but zero instruction surface → T4 proposal to add one — typically pointing the tool at an existing surface (`AGENTS.md`) rather than authoring a parallel one. No activity signal → no finding.
5. **Undocumented project invariants.** A non-obvious, recurring project rule visible in the repo (a custom codegen step, a non-standard layout, a generated directory that must not be hand-edited) documented nowhere → T4, judgment call, only with concrete evidence of the invariant.

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
