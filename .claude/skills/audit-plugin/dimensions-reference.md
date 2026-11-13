# Audit dimensions reference

Per-dimension checklists for `/audit-plugin`. Each dimension defines its file scope, what to look for, how to check it, and how to map findings to severity tiers. The orchestrator pastes ONE dimension section into each reviewer's prompt — reviewers never read this file themselves.

## Contents

- Reviewer spawn template
- Run setup
- Fix-round execution
- Mechanize what recurs
- Deletion gate
- Severity tiers (shared output classification)
- Finding output contract (shared reviewer schema)
- D1 — Mechanical hygiene (deterministic, no LLM)
- D2 — Cross-file consistency
- D3 — Stale rules & dead references
- D4 — Authoring-rules compliance
- D5 — Logic & syntax correctness
- D6 — Over-complication & instruction bloat
- D7 — Magic numbers & duplicated constants
- D8 — Safety & test coverage
- D9 — Wiring completeness (declared vs. wired)
- Do-not-flag list (endorsed patterns)

---

## Reviewer spawn template

Pasted by the orchestrator at Phase 2. Every slot is filled before the spawn — a reviewer that has to discover its own rubric will invent one.

```
Agent(subagent_type="general-purpose", prompt="""
## Task: Plugin audit — dimension D<N> (<name>)

You are one reviewer in a multi-dimension audit of this Claude Code plugin repo.
Review ONLY your dimension; other dimensions are covered by parallel reviewers.

### Your rubric
{{paste the full D<N> section from dimensions-reference.md}}

### Severity tiers and output contract
{{paste §Severity tiers from dimensions-reference.md + §Finding output contract from skills/_shared/audit-pipeline.md}}

### Do-not-flag list
{{paste every §Do-not-flag list entry tagged `[universal]`, plus every entry tagged with this reviewer's own dimension ID — each entry's tag is the bracketed prefix on its bullet. A reviewer never sees another dimension's single- or multi-dimension entries; only the universal ones and its own}}

### Your file scope
{{inventory subset for this dimension, from Phase 0}}

### Mechanical pre-pass context
{{battery summary; for D3 additionally: the candidate lists; for D7 additionally: the seed-grep output}}

### Procedure
1. Load your markdown scope in FULL via `scripts/dump-md.sh <scope paths>` and survey from that — grep hits miss reworded coverage; grep only to pinpoint an exact known string. Read non-markdown files directly.
2. Verify each candidate finding by Reading the exact cited lines — your `evidence` column must be a verbatim quote.
3. Return ONLY the findings table per the output contract plus a 2-3 sentence per-dimension verdict ("healthy / debt concentrated in X").
Do NOT fix anything. Do NOT review outside your dimension. Report only.
""", description="Audit: D<N> <name>")
```

Dimension-specific notes:
- **D4 (rules compliance) and D6:** instruct the reviewer to load every `.claude/rules/*.md` file first as its rubric source (`scripts/dump-md.sh .claude/rules` — they're too long to paste). D4 also loads `.claude/authoring` (`scripts/dump-md.sh .claude/rules .claude/authoring`): the fresh-user test's exemptions and translation tables live there.
- **D5:** two spawns — D5a scope `skills/ agents/ .claude/skills/`, D5b scope `hooks/ lib/ tests/`.
- **D6:** paste the no-execution-site and over-constraint candidate lists from the D1 battery into the `### Mechanical pre-pass context` slot, as D3 and D7 already get theirs.
- **D8:** paste the dead-matcher candidates from the D1 activation-reachability check.
- **D9:** paste the D1 declaration inventory. Also paste `skills/_shared/load-custom-instructions.md` §Producer contract — the instruction-block-consumption check adjudicates against the block set that file defines, and a reviewer left to recall the set will check the three it remembers.
- **Sharding:** if a dimension's markdown scope exceeds ~15K lines (full-audit D4/D6 typically do), split it into two shards balanced by LINE COUNT, not by a fixed glob — a path-based split (e.g. always `skills/*/SKILL.md` + `agents/` vs. everything else) drifts as the repo grows unevenly and can leave one shard well over the split threshold while the other sits well under it, spending a spawn without delivering the reduction the split exists for. Sum each candidate file's line count from the Phase 0 inventory, sort files descending by size, then assign each file to whichever shard currently holds fewer lines (greedy bin-packing) until both shards land within ~10% of half the scope's total. Same prompt for both shards, both in the batch.
- **D6 sharding — cross-file checks stay whole.** D6 checks #2 (drifted duplicate rules) and #7 (mechanism-level subtraction) each compare content ACROSS files a line-balanced split can separate onto different shards — a reviewer holding only its own shard cannot see the other half of a duplicated rule or judge whether a mechanism's cost is covered elsewhere, and neither shard can report the resulting blind spot on its own. When D6 shards, spawn one additional reviewer scoped to the FULL D6 file set (unsharded) running checks #2 and #7 only; shard A and shard B each run the remaining checks (#1, #3-6) over their own half. This third spawn counts against the reviewer-spawn cap (§Budgets) like any other shard.

## Run setup

Read at Phase 0, alongside this file's rubric sections.

**Inventory** — record file counts + line totals in the state checkpoint:

- Shipped: `skills/**/*.md`, `agents/*.md`, `hooks/*` + `hooks/hooks.json`, `lib/*.sh`, `settings.json`, `scripts/*.sh`.
- Cursor port: `cursor/**` (generated `cursor/skills/*/SKILL.md`, `cursor/agents/*.md`, `cursor/hooks.json`, `cursor/hooks/claude-hook-shim.sh`, `cursor/README.md`) + `.cursor-plugin/plugin.json`. The shim is a guard-carrying surface — it translates every wired hook's block signal into Cursor's deny response, so it belongs in the safety scope, not only the consistency scope.
- Repo-local: `.claude/rules/*.md`, `.claude/skills/**/*.md`.
- Docs (drift targets): `CLAUDE.md`, `README.md`, `HOOKS.md`, `ARCHITECTURE.md`, `MIGRATION.md`, `CONTRIBUTING.md`.
- Tests: `tests/**` (coverage map input for D8). `design/` and `evals/` are out of scope unless `$ARGUMENTS` names them.

**State checkpoint** — write `.geniro/state/audit-plugin/<slug>/state.md` (producer `audit-plugin` — not in the handoff helper's enumerated producer set, but adopting its contract shape verbatim) via `atomic_state_write` (source `lib/atomic-state-write.sh` — a direct `Write` truncates and rewrites in place, so a crash mid-write leaves a torn file). Slug and the full slug-scoped T1.5 frontmatter per `skills/_shared/within-skill-state-handoff.md` §Slug rules and §Producer contract — the field set, the line-1 rule, and the `validate_state_file` consequences live there. Each checkpoint records: phase completed, scope, dimensions selected, finding counts. The first checkpoint creates the file; every later one advances `phase:` with `atomic_state_set_field` and appends its log line with `atomic_state_append_section` — re-rendering the whole file each phase is what lets an untouched field carry forward at a stale value.

## Fix-round execution

Read at Phase 5 when a fix path is approved — you already have this file open from Phase 2. The disjoint-scope grouping, the ownership assert, and the 1-round budget are in `phase-5-action-gate.md`. The shared discipline — the three things that reliably happen after fix agents spawn, dead-agent ground-truthing, and the verification order — is canonical in `skills/_shared/audit-pipeline.md` §Fix-round discipline. Plugin-repo specifics:

- **Word budget:** every fix-agent brief states it, and the round ends with `scripts/word-delta.sh <base>` at net ≤ 0 — compress until it does, or put the named growth to the user. A size row the round grew is accepted only after that.
- **Once-per-round integration steps:** regenerating `cursor/skills/` from edited `skills/**/SKILL.md` sources, `cursor/agents/` from edited `agents/*.md` sources, accepting a size baseline, and completing a deletion across the files that referenced the deleted thing.
- **Routing:** large structural items (multi-file refactors, reference-graph re-homing) are better routed to `/improve-template` with the finding rows as `$ARGUMENTS`; say so instead of attempting them inline.

## Mechanize what recurs

Read at Phase 0 with the rest of this file, and again at Phase 5 when fixes are assigned.

**A recurring class closes with a test of behavior, never a test of wording** (`.claude/rules/tests.md`). A class in executable code — `hooks/`, `lib/`, `scripts/` — ships with a test that runs that code on a crafted input and fails without the fix; a passing test keeps the class closed with no memory needed. A structural break a run actually hits (an unresolved path, frontmatter that does not load, a stale generated copy, a hook registration naming a missing script) extends the existing integrity check that covers it. A class only a grep for a phrase, a count, a heading or a word list could decide closes with the fix alone: such a lint pins wording and blocks the next correct edit. Propose the test in the finding's `fix` column, and Phase 5 builds it alongside the fix.

## Deletion gate

Read at Phase 5 alongside §Fix-round execution, and reachable from this file rather than SKILL.md on purpose: Phase 5 arrives late in a long run, which is exactly when a compaction has dropped SKILL.md's tail, and this file is re-read there anyway. The no-blanket-deletion invariant — a mechanic is never deleted on a blanket approval — lives in `phase-5-action-gate.md`'s Deletion path, Read fresh at Phase 5 entry, and is what sends you here.

Walk the mechanism-level D6 proposals one at a time. Per proposal, render the explanation as its own chat message and then fire a lean `AskUserQuestion`, per `skills/_shared/per-finding-question.md` §Message-first rendering, in the visual language of `skills/_shared/gate-rendering.md`.

The render carries the four things the finding had to establish, plus what the user is left with:

- **What it is and where it lives** — the mechanic named in plain terms, with its path.
- **The case it exists for, and how often that case arises** — the reason someone built it, not a guess at their intent.
- **What it costs per run** — the measured figure, naming the profile it came from.
- **What covers that ground afterwards** — the other mechanism that catches the same case, or a plain statement that nothing will and the run will not know.
- **Whether it stands alone** — or only holds together with another proposal in this set, which the user has to decide as one.
- **What a run looks like once it is gone** — the observable difference, so the decision is about behavior rather than about a file.

Options: "Keep it" / "Delete it" / "Shrink it instead" / "Explain further". Mark whichever of keep-or-delete the evidence actually supports as `(Recommended)`, per that helper's §Recommended-label policy — a gate that recommends deletion by default spends the user's attention to obtain a signature, which is the same net-negative shape the mechanism-level check exists to find. "Shrink it instead" is the honest middle when the cost is real but the ground is still needed; it converts the finding into a text-level one and it re-enters the fix path as an edit.

Record the ones the user keeps in the report's subtraction sweep as considered-and-kept, with the reason. That is what stops the next audit re-proposing them, and it is the half of the sweep that compounds.

## Severity tiers (shared output classification)

Dimensions are review lenses; tiers classify the output. Every finding gets exactly one tier.

| Tier | Name | Admits |
|---|---|---|
| T0 | Safety | Hook bypass holes, secret-leak paths, data-loss vectors, fail-open where fail-closed is required |
| T1 | Correctness | Logic bugs, gates that can never fire, producer/consumer schema mismatch, shell bugs with behavioral impact, untested live data-mutating code |
| T2 | Rule violations | Breaches of `.claude/rules/*` hard exclusions or hard structural rules (description length past `.claude/rules/skill-structure.md` §Frontmatter hygiene, reference-graph inversion, non-English, dangling refs) |
| T3 | Staleness & drift | Dead references, doc-vs-reality drift, stale conditionals, orphaned files |
| T4 | Maintainability | Duplicated single-source content, unexplained or multi-homed constants, anti-rationalization dead weight, latent-but-unreachable defects, test-coverage-map gaps |

**There is no cosmetic tier, and its absence is the rule.** Caps emphasis, provenance citations, heading case, terminology, phrasing that "reads better" — a run does not report these at all. They were a tier for seven rounds and produced the pipeline's largest finding class and its smallest effect: prose edits from this pipeline survived at 6% against 86% for code edits, so the round after each cosmetic sweep re-raised what the sweep had just rewritten. A cosmetic observation is not a small finding here; it is not a finding. Where one of these classes turns out to be decidable after all, it becomes a check per §Mechanize what recurs — `lint-prose-and-links.sh` already owns heading case that way.

## Finding output contract (shared reviewer schema)

The table schema, row cap, and inadmissibility rule are canonical in `skills/_shared/audit-pipeline.md` §Finding output contract — paste that section into reviewer prompts alongside §Severity tiers above.

---

## D1 — Mechanical hygiene (deterministic, no LLM)

**Scope:** whole repo. **Method:** Bash only — the orchestrator runs this battery directly in Phase 1; no reviewer spawn.

| Check | Command / procedure | Tier on failure |
|---|---|---|
| Test suites | `bash tests/run-all.sh`, run through the test-runner agent (structured pass/fail + failure snippets) | T1 |
| Integrity lint | `bash tests/authoring/lint-skills.sh` — frontmatter that would not load, dangling plugin-root and rootless references, unknown spawn names (hard fails → findings); the compaction-boundary notice feeds D6 | T2 |
| ShellCheck | Preflight `command -v shellcheck` (absent → "skipped: tool unavailable", never a finding). Then `git ls-files lib hooks tests evals cursor scripts \| grep '\.sh$' \| xargs shellcheck -S error` (errors → T1); re-run `-S warning` (advisory → T4). Keep this path set in lockstep with `.github/workflows/ci.yml` — a path linted here but not in CI (or the reverse) is itself a finding. `git ls-files`, not `find`: gitignored scratch scripts in the working tree never reach CI's fresh checkout, and machine findings skip Phase 3 verification, so their false errors would ship as T1s | T1 / T4 |
| Deleted-skill refs | `grep -rnE 'geniro:(brainstorm|decompose|follow-up|deep-simplify|features|learnings|cleanup|vendor)' skills/ agents/ hooks/ lib/ cursor/ scripts/` — matches are CANDIDATES for D3 adjudication (README.md's "Skills deleted" table is a legitimate mention) | feed D3 |
| hooks.json wiring | `bash tests/authoring/lint-hook-wiring.sh` — every `hooks/*.sh` + `hooks/*.js` wired or declared unwired, the Claude-minus-Cursor gap matching its declaration | T1 |
| Canonical homes | `bash tests/authoring/lint-canonical-homes.sh` — every "X is canonical in FILE §SECTION" declaration resolves to a real file and a real heading | T2 |
| Links | `bash tests/authoring/lint-prose-and-links.sh` — local markdown links resolve | T3 |
| Frontmatter fields | Every `skills/*/SKILL.md` has `name`, `description`, `context`, `model`, `allowed-tools`, `argument-hint`; description length per `.claude/rules/skill-structure.md` §Frontmatter hygiene. Every `agents/*.md` declares `maxTurns` per that file's §`maxTurns` on agent frontmatter — an unset cap defaults to 10 turns outside interactive Claude Code, which truncates a reasoning agent at its emit step; `agents/*-reference.md` companions are exempt, carrying no agent frontmatter by design | T2 |
| Activation reachability | Each `.claude/rules/*.md` `paths:` glob matches at least one tracked file, evaluated under **gitignore `**` semantics** (a trailing `dir/**/*.ext` matches files directly in `dir/`, no subdirectory required) — NOT `git ls-files <pathspec>`, whose pathspec `**` semantics require an intervening path segment and report a false zero-match on a subdirectory-free directory (measured on `agents/**/*.md`). Each `hooks.json` matcher names tools and events that exist in Claude Code's surface — a matcher that can never fire is a guard that silently never runs | T1 (zero-match `paths:` glob under gitignore semantics); dead matchers → CANDIDATES, feed D8 |
| File-size guidelines | Word counts per the repo's one rule (`awk '{w+=NF}'`, never `wc -w` — that one's answer changes with the locale): budgets per `.claude/rules/skill-structure.md` §File-size limits (front-load budget for SKILL.md, whole-file guideline, and the `agents/*.md` cap). All advisory — `tests/authoring/lint-skills.sh` names the heading each SKILL.md's compaction boundary falls at. Flag WHAT sits below the boundary, never the number itself | T4 |
| Orphan candidates | For each `skills/_shared/*.md`, `lib/*.sh`, `agents/*.md`: grep the repo for its basename; zero inbound references → CANDIDATE for D3 adjudication | feed D3 |
| No-execution-site candidates | Same basenames, but the shape a zero-reference test cannot see: referrers exist yet **none is an execution site** — every hit is another `_shared/` peer, and no `skills/*/SKILL.md`, phase file, or `agents/*.md` names it. A helper two peers cite but no skill ever runs is dead with a non-zero reference count. Also flag a helper whose referrers disagree about where it fires | feed D6 |
| Over-constraint candidates | The integrity lint names each SKILL.md whose compaction boundary drops sections, and the heading it falls at — paste those; they are candidates for D6's progressive-disclosure check. Plus `grep -c` per shipped file for blanket prohibitions in normal prose (`NEVER` / `ALWAYS` / `MUST` outside a table row) — density, not any single hit, is the signal for D6's over-constraint check | feed D6 |
| Declaration inventory | For D9: enumerate each declaration kind so the reviewer adjudicates a list instead of running its own search. Per skill, the loader call sites (`SKILL_SLUG` / `LOAD_TIER` / `MODE`) and their initial-load-vs-refresh split; the phases-overview entries against the `## PHASE` headings and the phase-body files those pointers name; the `AskUserQuestion` site count; the `{{slot}}` names each spawn template declares; and per instruction-block heading, the files naming it. Emit each as a location list, never a count — a count cannot be adjudicated, and every entry here needs classifying as author / validate / parse / execute before it is a gap | feed D9 |

Record full battery output to the state checkpoint. Machine findings are pre-verified (no Phase 3 re-read needed); candidate lists feed the relevant reviewer prompts.

## D2 — Cross-file consistency

**Scope:** `CLAUDE.md`, `README.md`, `HOOKS.md`, `ARCHITECTURE.md`, `CONTRIBUTING.md`, `MIGRATION.md`, `skills/`, `agents/`, `hooks/` (the docs-vs-reality-drift check below compares doc claims against actual script matchers), `lib/` (the helper-contract-drift check below compares helper contracts against the scripts). **Method:** LLM reviewer, grep-grounded.

Checks:
1. **Docs-vs-reality drift.** CLAUDE.md skill routing, README, HOOKS.md, ARCHITECTURE.md, and CONTRIBUTING.md claims vs actual skill/hook/helper behavior: listed skills exist, described flags/phases/paths match the SKILL.md body, hook descriptions match the script's actual matchers and bypass IDs, design rationale cited from ARCHITECTURE.md still matches the code that cites it.
2. **Description-vs-body drift.** Each SKILL.md frontmatter `description:` vs what the body actually does (flags, phases, outputs).
3. **Schema lockstep.** For every state-file / handoff field a producer writes (per `skills/_shared/state-tier-spec.md`), confirm consumers read the same field name and shape; flag fields written-but-never-read or read-but-never-written. Hit count carries no signal here — a written field always has hits, so classify each as a write, a read, or a schema declaration and report when none is a read (or none is a write). Name both remedies and say which is cheaper: an unwired producer is as often a missing feature as it is dead weight.
4. **Helper contract drift.** For each `_shared/*.md` helper and `lib/*.sh` script: do callers pass the slots / flags / MODE values the contract defines? Do cited exit codes match the script?
5. **Single-source violations.** Pseudo-code blocks, slot tables, or schema definitions duplicated across ≥2 files (the rule: one source, others cite it).
6. **Spawn-site consistency.** Every plugin-agent spawn follows the `spawn-agent.md` ladder, and its class follows `model-tiering.md` §Cost classes: deciding sites are `session` and OMIT `model=`, applying and mechanical sites are `light`. Flag a model passed at a `session` site, a `light` site running above its class, and any site contradicting the skill's own tiering table.
Tier mapping: schema mismatch with behavioral impact → T1; doc drift / duplication → T3 / T4.

## D3 — Stale rules & dead references

**Scope:** `skills/`, `agents/`, `.claude/rules/`, `.claude/skills/`, `cursor/`, `scripts/`, top-level docs. **Method:** LLM reviewer seeded with D1 candidate lists. Where a reference is dead, check git history for a rename before writing the fix — repointing to the survivor beats deleting the mention.

Checks:
1. **Deleted-skill references** outside the documented replacement tables (adjudicate D1 candidates).
2. **Dangling section anchors — the undecidable half only.** `lint-canonical-homes.sh` hard-fails a canonical declaration whose file or heading is gone. The rest are for a reader — above all the BARE anchor, whose binding is not mechanically recoverable — it may name a section in the citing file, in a file named a paragraph earlier, or in none. Adjudicate those; do not re-scan what the lints already decided.
3. **Dropped phase/step names.** References to phases or steps that were renamed or removed (grep the referenced skill for the phase name). Read each hit rather than counting it — a hit that only *documents the removal* is not evidence the name is still live.
4. **Stale conditionals.** "when X ships" / "once Y lands" where X/Y already exists; "reserved for future" hooks that are now live.
5. **Orphans.** Adjudicate D1 orphan candidates: a `_shared` helper, lib script, or agent with zero inbound references is dead weight (or its callers reference it by a wrong name — which is a T1 instead).
6. **Stale rule files.** `.claude/rules/*` migration-audit sections describing work already completed; rules citing files that moved.
7. **MIGRATION.md / HOOKS.md entries** describing behavior the current code no longer has.

Tier mapping: wrong-name reference breaking a runtime lookup → T1; everything else → T3.

## D4 — Authoring-rules compliance

**Scope:** `skills/**/*.md`, `agents/*.md` (shipped files — the rules bind these; `.claude/skills/` is exempt from shipping rules but check it for the prose rules), plus `.claude/rules/*.md` and `CLAUDE.md` for the rule-file-rules check below, the one rule that binds those two paths. **Method:** LLM reviewer; instruct it to read every `.claude/rules/*.md` file first and apply them as the rubric.

Checks (the rules files are the source of truth — these are pointers, not restatements):
1. **Hard exclusions** (`skill-authoring.md`): plugin-author-internal references, authoring-process narration, informational noise, out-of-scope content, non-English.
2. **Prose rules** (`skill-prose.md`) — the two with a consequence a reader can name, not the style set: **load-bearing invariants placed past the compaction re-attach boundary** (§Rule placement), which silently stop binding mid-session; and the **fresh-user test on every user-facing string** (step titles, AUQ text, narration templates), where the failure lands on the user's screen. Caps emphasis, menu-of-options phrasing, restatement summaries and point-of-view are style — out of scope per §Severity tiers.
3. **Structure rules** (`skill-structure.md`): section ordering; frontmatter description format (third person, "Use when", no XML); anti-rationalization tables within the row cap with reasoning in the right cell; reference-graph depth within its hop limit and no upward links from `_shared/` into skill bodies for runtime instructions; no line-number cross-refs. Also **reference class** (§Reference classes): prose carrying taste a verifier could evaluate one criterion at a time wants to be a rubric; prose stating a condition a command could decide wants to be an executable check or a failing test; prose describing a file's conventions wants to be that file, passed as an exemplar. Flag the mismatch, not every prose reference — prose is the default, just not the only option.

4. **Rule-file rules** (`rule-writing.md`, which scopes itself to `.claude/rules/**` and `CLAUDE.md`): those files carry the instruction, the reason only where the model would rationalize around it, and exact contract values. This row is the pointer for the two paths no shipping rule reaches.

Tier mapping: hard exclusions / hard structure breaches → T2; a misplaced load-bearing invariant or a user-facing string failing the fresh-user test → T4.

## D5 — Logic & syntax correctness

**Scope split:** 5a (markdown logic) covers `skills/`, `agents/`, `.claude/skills/`; 5b (shell logic) covers `hooks/`, `lib/`, `tests/`, `cursor/hooks/`, `scripts/`. Spawn as two reviewers. **Method:** LLM reviewers; every claim must survive a re-read of the cited code.

5a checks (markdown):
1. **Contradictions.** Phase A states X, phase B assumes not-X; an invariant the steps violate; a budget table disagreeing with the step that enforces it.
2. **Unfireable gates.** Conditions comparing against fields no schema carries; gates whose trigger can never occur; branches conditioned on a flag, mode, or option the skill no longer ships (check `argument-hint` and the modifier table, not only the body); gates an earlier gate always pre-empts; AUQ flows with no path to one of their documented outcomes.
3. **Tool-surface mismatches.** Body instructs using a tool absent from `allowed-tools`; AskUserQuestion specs exceeding the question tool's option cap; spawn prompts using slots never filled.
4. **State-machine holes.** `phase:`/`status:` enum values written but never read (or read but never written); terminal states unhandled by resume logic.
5. **Broken procedures.** Steps referencing outputs of steps that don't produce them; counters that reset on compaction while the skill claims compaction-safety.
6. **Turn-completion seams.** A step that emits content and then owes a tool call — a gate render followed by its question, a spawn batch followed by its collection, an echo attesting to a Read — where the wording lets the run come to rest between the two. The underlying model has a documented early-stopping failure mode on exactly this seam: it ends on a statement of intent and the promised call never happens, which reads as a completed step from every angle except the user's. Flag a step whose obligation spans a turn boundary with nothing closing it, and one that states intent as its own completion criterion. The canonical closure and its recovery are in `skills/_shared/gate-rendering.md` §Turn-completion guard and `skills/_shared/loop-invariants.md` — flag the site that lacks it, never the contract.

5b checks (shell):
1. **Quoting & word-splitting** on user-controlled or file-derived values; unquoted globs.
2. **Regex correctness** in guard hooks — false negatives (bypassable patterns, line-by-line matching of multi-line constructs) and false positives (legit commands blocked).
3. **Exit-code semantics** — hooks must exit 2 to block / 0 to allow per their contract; helpers' documented rc values match reality.
4. **Trap/lock hygiene** — locks released on SIGINT/SIGTERM; mktemp cleaned; partial writes impossible (atomic mv).
5. **Portability** — BSD/GNU divergence (`grep -P`, `stat -c`, `sed -i`, `tac`); `#!/usr/bin/env bash`.
6. **Input validation** — env-var overrides sanitized; malformed JSON stdin handled (fail-open vs fail-closed chosen deliberately and matching the hook's safety role).

Tier mapping: bypassable guard / data-loss path → T0; behavioral bug → T1; latent-but-unreachable → T4.

## D6 — Over-complication & instruction bloat

**Scope:** every instruction surface — `skills/` (bodies, references, `_shared/`), `agents/`, `.claude/skills/`, `.claude/rules/`, `CLAUDE.md`; the last three ship to nobody, so they accumulate and no other dimension sweeps them. **Runs on every audit** per SKILL.md's subtraction-sweep invariant, inheriting a scoped run's scope; the orchestrator sweeps `--quick` inline. **Method:** LLM reviewer. Load every `.claude/rules/*.md` file first (`scripts/dump-md.sh .claude/rules`): `skill-prose.md` is this dimension's yardstick (the name-the-case test, the reduction ceiling, rule placement, what added instructions buy) and is not restated here. Every finding proposes one concrete action — delete, shorten, merge, move to a sibling reference, or convert a constraint to a hook/script.

**Two tests per candidate.** Would removing it make Claude err (for guard text, name the case)? Would replacing the rule with a criterion, or the example with a better-designed interface, make Claude err — the larger win? A proposal past the reduction ceiling is out of range. **Redundancy alone is not a finding** (§Severity tiers): every check asks whether text can still *apply* or still *earns* its place.

Checks:
1. **Model-known instruction.** Text re-explaining standard tool behavior or general competence ("read before editing", "write clean code") — delete, or convert a hard constraint to a hook.
2. **Drifted duplicate rules.** One rule (prose; D7 owns constants) in ≥2 files whose statements have **diverged** into a contradiction — one canonical home, others cite it with `§`. Agreeing copies are out of scope.
3. **Appended-patch contradiction.** A later NOTE or exception narrowing an earlier rule in the same file instead of being folded in, so recency silently overrides — rewrite the original to be correct alone, delete the patch.
4. **Load-bearing content past the front-load boundary.** A rule checked every turn sitting where the first compaction silently drops it — propose a MOVE into the spine or a split, never a cut; start from `lint-skills.sh`'s compaction notices. A move into an `agents/*.md` body saves nothing (injected whole).
5. **Over-constraint.** Live, unique, correct text costing more than it buys because it was written for a weaker model — the largest removable instruction in a mature plugin. Shapes: a rule that should be a criterion (a fixed threshold or blanket ban where the right answer varies by context; project contracts — exact paths, schemas, option labels — stay fixed); a prohibition where a requirement carries the rule (propose the positive form; keep a prohibition at a data-loss or outward-effect boundary, restated at the point of use); an example that narrows (prefer a closed enum or a tool surface that cannot express the wrong call); a guardrail past its model (an older generation's failure mode, or now enforced by a hook, schema or test). Report the candidate, never the count: what it constrains, what the model does without it, what breaks if that is wrong.
6. **Dead instructions (liveness).** Text that can no longer apply — it governs a phase, step, sub-command or flag that no longer exists, or describes a replaced mechanism in its old terms. Name the referent, then grep it outside `design/` and `evals/` (they quote strings they do not use); hits that merely *document a removal* are not liveness. **An anti-rationalization row is not dead because its failure mode is absent from current code — that is what a working guardrail looks like**; retire one only when its step is gone or a mechanism now enforces it. **Route by referent, at the owner's tier:** schema or frontmatter field → D2 §Schema lockstep; phase or step name → D3 §Dropped phase/step names; gate or branch condition → D5a §Unfireable gates; replaced mechanism still documented → D3 §MIGRATION.md / HOOKS.md entries. Only ownerless text is reported here.

7. **Mechanism-level subtraction.** The checks above ask whether *text* earns its place. This one asks whether a whole **mechanic** does — a phase, step, gate, sub-pipeline, helper, agent spawn, reviewer dimension, state file, mode, modifier, checkpoint, or verification pass. A mechanic can be well-written, unique, correct, and still not worth running, and no text-level check can see that: every one of them starts from the assumption that the thing should exist and asks only whether it is stated well. Three dispositions, and a finding names which one it is:

    - **Low yield.** It runs and almost never changes an outcome — a check whose findings are always filtered, a gate the user answers the same way every time, a verification pass that has never overturned what it verifies.
    - **Net-negative.** It runs and makes the process worse: a gate that fires so often it is rubber-stamped (which spends the user's attention and buys a signature, not a decision), a check whose false-positive rate trains readers to skip its output, a step that forces a default the run then has to work around.
    - **Cost or latency.** Removing it measurably cuts what a run loads or how long it takes — an always-on load only one phase reads, a serialized round-trip, a spawn whose output another spawn already carries.

    **The bar here is evidentiary, not stylistic, and it is the highest in this dimension.** A text cut that misses costs a rationale someone can notice is gone. A mechanic deleted in error leaves nothing behind to notice — no failure at the time, and none in any run after, because the step that would have objected is the step that was removed. So a proposal carries four things, and one that cannot is not a deletion proposal:

    - **The case it exists for, and that case's base rate.** "I did not see it fire" is not evidence — an idle guard is a working guard, which this dimension already says about prohibitive text and which binds harder here. Evidence is: the case it catches, how often that case arises, and what the run does on that case once the mechanic is gone.
    - **A measured cost, never an asserted one.** A token claim cites `scripts/measure-run-load.sh --detail <profile>` with the profile's total and the mechanic's own contribution; a latency claim counts what actually serializes — spawns, round-trips, gates awaiting a human. "Feels heavy" is not a finding. And cheapness cuts the other way: a mechanic costing little per run is a good trade even at a low firing rate, so the case needs cost × frequency, never low frequency alone.
    - **What covers the ground afterwards.** Either name the other mechanism catching the same case, or say plainly that the ground becomes uncovered and the run will not know it. Both are acceptable answers; not knowing which one applies is not.
    - **Whether it stands alone.** Say if the proposal holds only together with another in the same set. Two mechanics each redundant *given the other* are not both redundant, and a round applying them together removes the ground both were covering — the one compound failure a per-item gate cannot catch on its own.

    Report it whichever way the evidence points; a proposal that cleared the bar is worth making, and one that did not belongs in the verdict as a rejected candidate, not in the table as a hedged row.

**Headings are a contract.** Grep the repo for the filename before proposing a rename or drop: a `<file>.md §<Heading>` citation breaks with no error.

Tier mapping: T4 by default; a duplicated rule drifted into a contradiction → T1; mechanism-level proposals by disposition — net-negative → T1 when the mechanic produces wrong outcomes rather than merely costly ones, else T4; low-yield and cost/latency → T4. The tier orders the report; the deletion is the user's call at its own gate — propose, never auto-cut, and state what changes if it is wrong. A shorten or merge proposal carries a **preserved inventory**, the spans the rewrite must reproduce verbatim — commands, tool names, trigger phrases, output formats, paths, numbers, exact error strings, any string a test greps for. On a criteria or rubric file the target shape is a charter (mission, common false positives, severity calibration), never the checklist's headings with their content dropped.

**Return the sweep, not a quota.** The sweep is mandatory; its result is not. Zero findings is a valid outcome; a manufactured one is worse than none, because a deletion is the one finding whose wrongness the user cannot notice later. So the deliverable is the sweep itself, reported whether or not it yielded anything — and a clean result belongs in the verdict sentence, not padded into a findings row:

- **Name what you examined**, at the granularity of the check: which files you read in full, which of this dimension's checks you applied, and where you looked hardest. A verdict that does not say what was swept is indistinguishable from a sweep that did not happen.
- **Name what you rejected and why.** A candidate you considered and left — because the answer is genuinely invariant across contexts, because the guardrail is still load-bearing, because the destination of a proposed MOVE is loaded by every run anyway — is a *result*, and it is the most useful thing you can hand the next round. It goes in the verdict, not the table. This is also what stops the next reviewer re-litigating it.
- **Say plainly when a subtraction pass found nothing.** "Swept `_shared/`, the meta-skills, and `.claude/rules/` in full against every check; the two candidates were X and Y, both rejected for <reason>" is a complete and successful D6 result.

## D7 — Magic numbers & duplicated constants

**Scope:** `skills/`, `agents/`, `.claude/skills/`, `hooks/`, `lib/`. **Method:** LLM reviewer seeded with a number-density grep.

Seed grep (orchestrator runs, pastes matches into the prompt): `grep -rhoE '(≤|>=|<=|≥|max |cap |within )[0-9]+|[0-9]+ (retries|rounds|lines|files|questions|attempts|seconds|chars|tokens)' skills/ agents/ .claude/skills/ | sort | uniq -c | sort -rn | head -80` — `-h`, not `-n`: a `file:line:` prefix makes every line unique, so `uniq -c` would count nothing and the multi-homed-constant signal vanishes; the reviewer greps locations for the candidates it pursues. Plus `grep -rnE '[0-9]{3,}' hooks/ lib/ --include='*.sh' | grep -v ':[[:space:]]*#'` (POSIX class, not `\s` — BSD grep treats `\s` as a literal `s`).

Checks:
**Two dispositions, and the split is the whole discipline of this dimension.** A number that lives in exactly one place and explains itself is doing its job — the fix is an inline WHY or a citation, and the number stays. A number that is *restated*, or that *counts something the repo changes*, or that *ordinals a list an edit can reorder*, cannot stay correct: it has no single home to be fixed in. The keep-the-number group and the remove-the-number group below split this way — do not blur the two: stripping a self-explaining single-homed threshold costs a rationale the model was relying on and buys nothing.

Keep-the-number checks:

1. **Unexplained thresholds.** A numeric limit with no adjacent rationale and no citation to a canonical source. The fix is an inline WHY or a citation — keep the number itself.
2. **Contradicting constants.** The same concept with DIFFERENT values in different files (this is a T1, not T4).
3. **Shell literals.** Hardcoded sizes/timeouts in hooks/lib without a comment or env-override; duplicated literals that must move in lockstep.

Remove-the-number checks — the drift-prone classes. For these, "add a WHY" is not an acceptable fix, because the defect is that the value exists in more than one place at all:

4. **Multi-homed constants.** The same threshold stated in ≥2 files, **even while the values agree** — agreement today is drift tomorrow. Fix: one home keeps the number, every other site cites it. A file that names another file as the owner and then restates the value anyway is this check's most common shape, and the restatement is what to delete.
5. **Prose counts of repo contents.** A count of things the repo contains — skills, agents, helpers, test suites, dimensions, reviewers, assertions, bypass IDs, load-set files. Measure each against reality, then **reword so the count is not stated**: the list lives elsewhere, so the sentence should point at it rather than tally it. "the seven per-skill scopes" becomes "the per-skill scopes"; "the same batch as the 7-10 built-ins" becomes "the same batch as the consumer's built-in dimensions". Re-stating the corrected number only resets the clock on the same defect.
6. **Drifting ordinals.** A hardcoded step, phase, check, sub-phase, or invariant NUMBER used as a cross-reference. Inserting or removing one item silently invalidates every reference past it, and a renumbering pass that misses one site produces a citation that resolves to the wrong step — worse than one that dangles, because nothing detects it. Fix: content anchors per `.claude/rules/skill-structure.md` §Cross-skill references ("the F→P invariant", not "step 4.3"). Two carve-outs stay numeric: a number that is part of a **contract** other files grep for (a schema version, a phase-enum value, an exit code), and a **contiguity requirement** a validator enforces (a check set that must run 1..N). Flag the reference, not the heading it points at.

Tier mapping: contradicting constants → T1; multi-homed / unexplained / drifting ordinals → T4; stale prose counts → T3.

## D8 — Safety & test coverage

**Scope:** `hooks/hooks.json`, `hooks/`, `lib/`, `tests/`, `settings.json`, `cursor/hooks.json`, `cursor/hooks/`, plus `skills/` for the destructive-op-surface check only. **Method:** LLM reviewer.

Checks:
1. **Matcher coverage.** Every guard hook's `hooks.json` matcher covers ALL tools that can perform the guarded action (Edit/Write/MultiEdit/NotebookEdit; Bash variants). A guard that misses one tool is bypassable — T0. The inverse is also a finding: a matcher naming a tool or event that does not exist can never fire, so the guard silently never runs — T1; D1 seeds these.
2. **Sanitization coverage.** Every field that reaches a persisted artifact passes through `redact-secrets`; new fields added to emit paths are walked by the sanitize loop.
3. **Fail-open vs fail-closed.** For each guard: what happens when `jq` is missing, stdin is malformed, or safety.json is unparseable? Safety-critical guards should fail closed; convenience hooks may fail open — flag mismatches with the hook's role.
4. **Bypass-list integrity.** Every documented `allow_patterns` ID is actually checked by its hook; every hook bypass branch has a documented ID (HOOKS.md).
5. **Test coverage map.** For each hook and each data-mutating lib helper: does a `tests/**` suite exercise it (both block and allow paths for guards)? Untested hard-block guards and untested live data-mutators → T1.
6. **Destructive-op surface.** Any `rm -rf`, `git push`, `--force` usage in skills/hooks/lib with no user gate before it.
7. **Guard earns its blocks.** A new or changed PreToolUse guard reads a declared target (a tool field, a literal command word) rather than reconstructing intent from command text — `HOOKS.md` §Removed guards records why command-string guards were deleted. A guard that infers targets is T1.

Tier mapping: bypassable guard / unsanitized secret path → T0; untested live mutator / wrong fail direction → T1; map gaps → T4.

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
