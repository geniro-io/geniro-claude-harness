# Audit dimensions reference

Per-dimension checklists for `/audit-plugin`. Each dimension defines its file scope, what to look for, how to check it, and how to map findings to severity tiers. The orchestrator pastes ONE dimension section into each reviewer's prompt — reviewers never read this file themselves.

## Contents

- Reviewer spawn template
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
{{paste §Severity tiers + §Finding output contract from dimensions-reference.md}}

### Do-not-flag list
{{paste §Do-not-flag list}}

### Your file scope
{{inventory subset for this dimension, from Phase 0}}

### Mechanical pre-pass context
{{battery summary; for D3 additionally: the candidate lists; for D7 additionally: the seed-grep output}}

### Procedure
1. Load your markdown scope in FULL via `scripts/dump-md.sh <scope paths>` and survey from that — grep hits miss reworded coverage; grep only to pinpoint an exact known string. Read non-markdown files directly.
2. Verify each candidate finding by Reading the exact cited lines — your `evidence` column must be a verbatim quote.
3. Return ONLY the findings table per the output contract (≤25 rows) plus a 2-3 sentence per-dimension verdict ("healthy / debt concentrated in X").
Do NOT fix anything. Do NOT review outside your dimension. Report only.
""", description="Audit: D<N> <name>")
```

Dimension-specific notes:
- **D4 (rules compliance):** instruct the reviewer to load the three `.claude/rules/*.md` files first as its rubric source (`scripts/dump-md.sh .claude/rules` — they're too long to paste).
- **D5:** two spawns — D5a scope `skills/ agents/ .claude/skills/`, D5b scope `hooks/ lib/ tests/`.
- **Sharding:** if a dimension's markdown scope exceeds ~15K lines (full-audit D4/D6 typically do), split into shard A (`skills/*/SKILL.md` + `agents/`) and shard B (the remainder of the dimension's scope — everything NOT in shard A, so no file falls between two positive globs), same prompt, both in the batch.

## Severity tiers (shared output classification)

Dimensions are review lenses; tiers classify the output. Every finding gets exactly one tier.

| Tier | Name | Admits |
|---|---|---|
| T0 | Safety | Hook bypass holes, secret-leak paths, data-loss vectors, fail-open where fail-closed is required |
| T1 | Correctness | Logic bugs, gates that can never fire, producer/consumer schema mismatch, shell bugs with behavioral impact, untested live data-mutating code |
| T2 | Rule violations | Breaches of `.claude/rules/*` hard exclusions or hard structural rules (description >1024, reference-graph inversion, non-English, dangling refs) |
| T3 | Staleness & drift | Dead references, doc-vs-reality drift, stale conditionals, orphaned files |
| T4 | Maintainability | Duplicated single-source content, unexplained or multi-homed constants, over-complication, anti-rationalization dead weight, latent-but-unreachable defects, test-coverage-map gaps |
| T5 | Cosmetic | Title-Case headers, terminology mixes, caps-without-reasoning, provenance citations |

## Finding output contract (shared reviewer schema)

Every reviewer returns a Markdown table with EXACTLY these columns, one row per finding, capped at 25 rows (rank by impact; note "N further low-impact items omitted" if capped):

| Column | Content |
|---|---|
| `id` | `D<dim>-<n>` (e.g. `D3-4`; sub-reviewers keep their label — `D5a-2`, `D4-shardB-1`) |
| `tier` | T0-T5 per the table above |
| `file:line` | Real location — verified by the reviewer with Read before reporting. Use `file:start-end` for ranges. |
| `issue` | One sentence, plain English |
| `evidence` | Verbatim quote (≤2 lines) from the cited location — the orchestrator re-verifies this quote exists |
| `fix` | Concrete suggested change, one sentence |
| `effort` | S / M / L |

A finding without a verifiable `file:line` + verbatim `evidence` is inadmissible — drop it rather than guessing a location.

---

## D1 — Mechanical hygiene (deterministic, no LLM)

**Scope:** whole repo. **Method:** Bash only — the orchestrator runs this battery directly in Phase 1; no reviewer spawn.

| Check | Command / procedure | Tier on failure |
|---|---|---|
| Test suites | `bash tests/run-all.sh` | T1 |
| Authoring lint | `bash tests/authoring/lint-skills.sh` (hard fails → findings; warnings → advisory findings) | T2 / T4 |
| ShellCheck | Preflight `command -v shellcheck` (absent → "skipped: tool unavailable", never a finding). Then `find lib hooks tests evals cursor scripts -name '*.sh' -exec shellcheck -S error {} +` (errors → T1); re-run `-S warning` (advisory → T4). Keep this path set in lockstep with `.github/workflows/ci.yml` — a path linted here but not in CI (or the reverse) is itself a finding. `find`, not `tests/**/*.sh` — `**` needs globstar and silently misses top-level files without it | T1 / T4 |
| Deleted-skill refs | `grep -rnE 'geniro:(brainstorm|decompose|follow-up|deep-simplify|features|learnings|cleanup|vendor)' skills/ agents/ hooks/ lib/ cursor/ scripts/` — matches are CANDIDATES for D3 adjudication (CLAUDE.md's deleted-skills table is a legitimate mention) | feed D3 |
| hooks.json wiring | Every script referenced in `hooks/hooks.json` exists in `hooks/`; every `hooks/*.sh` + `hooks/*.js` is either registered or documented as library/manual | T1 |
| Frontmatter fields | Every `skills/*/SKILL.md` has `name`, `description`, `context`, `model`, `allowed-tools`, `argument-hint`; description ≤1024 chars | T2 |
| File-size guidelines | `wc -w`: SKILL.md past ~3,000 words puts later sections outside the compaction re-attach budget, ~5,000 is the whole-file guideline; `agents/*.md` past ~2,500. All advisory — `tests/authoring/lint-skills.sh` warns only when a SKILL.md grows past its recorded size in `tests/authoring/skill-size-baseline.txt`, and then names the heading its compaction boundary falls at, so a silent run means every size is one a maintainer already accepted. Flag WHAT sits below the boundary, never the number itself | T4 |
| TOC presence | Any `skills/**/*-reference.md` or `_shared/*.md` >100 lines without a "Contents"/"Sections" block in its first 30 lines | T4 |
| Orphan candidates | For each `skills/_shared/*.md`, `lib/*.sh`, `agents/*.md`: grep the repo for its basename; zero inbound references → CANDIDATE for D3 adjudication | feed D3 |

Record full battery output to the state checkpoint. Machine findings are pre-verified (no Phase 3 re-read needed); candidate lists feed the relevant reviewer prompts.

## D2 — Cross-file consistency

**Scope:** `CLAUDE.md`, `README.md`, `HOOKS.md`, `ARCHITECTURE.md`, `CONTRIBUTING.md`, `MIGRATION.md`, `skills/`, `agents/`, `hooks/` (check 1 compares doc claims against actual script matchers), `lib/` (check 4 compares helper contracts against the scripts). **Method:** LLM reviewer, grep-grounded.

Checks:
1. **Docs-vs-reality drift.** CLAUDE.md skills table, README, HOOKS.md, ARCHITECTURE.md, and CONTRIBUTING.md claims vs actual skill/hook/helper behavior: listed skills exist, described flags/phases/paths match the SKILL.md body, hook descriptions match the script's actual matchers and bypass IDs, design rationale cited from ARCHITECTURE.md still matches the code that cites it.
2. **Description-vs-body drift.** Each SKILL.md frontmatter `description:` vs what the body actually does (flags, phases, outputs).
3. **Schema lockstep.** For every state-file / handoff field a producer writes (per `skills/_shared/state-tier-spec.md`), confirm consumers read the same field name and shape; flag fields written-but-never-read or read-but-never-written.
4. **Helper contract drift.** For each `_shared/*.md` helper and `lib/*.sh` script: do callers pass the slots / flags / MODE values the contract defines? Do cited exit codes match the script?
5. **Single-source violations.** Pseudo-code blocks, slot tables, or schema definitions duplicated across ≥2 files (the rule: one source, others cite it).
6. **Spawn-site consistency.** Every plugin-agent spawn follows the `spawn-agent.md` ladder and the OMIT-`model=` rule for carve-out agents; flag sites that contradict the skill's own tiering table.
7. **Terminology consistency** within each file (one term per concept, per `.claude/rules/skill-prose.md` §Terminology consistency).

Tier mapping: schema mismatch with behavioral impact → T1; doc drift / duplication → T3 / T4; terminology → T5.

## D3 — Stale rules & dead references

**Scope:** `skills/`, `agents/`, `.claude/rules/`, `.claude/skills/`, `cursor/`, `scripts/`, top-level docs. **Method:** LLM reviewer seeded with D1 candidate lists.

Checks:
1. **Deleted-skill references** outside the documented replacement tables (adjudicate D1 candidates).
2. **Dangling section anchors.** `§Some Header` / "see §N" cross-references whose target header no longer exists in the cited file.
3. **Dropped phase/step names.** References to phases or steps that were renamed or removed (grep the referenced skill for the phase name).
4. **Stale conditionals.** "when X ships" / "once Y lands" where X/Y already exists; "reserved for future" hooks that are now live.
5. **Orphans.** Adjudicate D1 orphan candidates: a `_shared` helper, lib script, or agent with zero inbound references is dead weight (or its callers reference it by a wrong name — which is a T1 instead).
6. **Stale rule files.** `.claude/rules/*` migration-audit sections describing work already completed; rules citing files that moved.
7. **MIGRATION.md / HOOKS.md entries** describing behavior the current code no longer has.

Tier mapping: wrong-name reference breaking a runtime lookup → T1; everything else → T3.

## D4 — Authoring-rules compliance

**Scope:** `skills/**/*.md`, `agents/*.md` (shipped files — the rules bind these; `.claude/skills/` is exempt from shipping rules but check it for the prose rules). **Method:** LLM reviewer; instruct it to read all three `.claude/rules/*.md` files first and apply them as the rubric.

Checks (the rules files are the source of truth — these are pointers, not restatements):
1. **Hard exclusions** (`skill-authoring.md`): plugin-author-internal references, authoring-process narration, informational noise, out-of-scope content, non-English.
2. **Prose rules** (`skill-prose.md`): caps-MUST/NEVER/ALWAYS outside anti-rationalization tables; menu-of-options paragraphs; restatement summaries; mixed point-of-view; load-bearing invariants placed past the compaction re-attach boundary (§Rule placement); fresh-user test on every user-facing string (step titles, AUQ text, narration templates).
3. **Structure rules** (`skill-structure.md`): section ordering; frontmatter description format (third person, "Use when", no XML); anti-rationalization tables ≤15 rows with reasoning in the right cell; reference-graph depth ≤1 hop and no upward links from `_shared/` into skill bodies for runtime instructions; no line-number cross-refs.

Tier mapping: hard exclusions / hard structure breaches → T2; prose-guideline breaches → T5 (or T4 when they carry recurring token cost, e.g. restatement blocks).

## D5 — Logic & syntax correctness

**Scope split:** 5a (markdown logic) covers `skills/`, `agents/`, `.claude/skills/`; 5b (shell logic) covers `hooks/`, `lib/`, `tests/`, `cursor/hooks/`, `scripts/`. Spawn as two reviewers. **Method:** LLM reviewers; every claim must survive a re-read of the cited code.

5a checks (markdown):
1. **Contradictions.** Phase A states X, phase B assumes not-X; an invariant the steps violate; a budget table disagreeing with the step that enforces it.
2. **Unfireable gates.** Conditions comparing against fields no schema carries; gates whose trigger can never occur; AUQ flows with no path to one of their documented outcomes.
3. **Tool-surface mismatches.** Body instructs using a tool absent from `allowed-tools`; AskUserQuestion specs exceeding 4 options; spawn prompts using slots never filled.
4. **State-machine holes.** `phase:`/`status:` enum values written but never read (or read but never written); terminal states unhandled by resume logic.
5. **Broken procedures.** Steps referencing outputs of steps that don't produce them; counters that reset on compaction while the skill claims compaction-safety.

5b checks (shell):
1. **Quoting & word-splitting** on user-controlled or file-derived values; unquoted globs.
2. **Regex correctness** in guard hooks — false negatives (bypassable patterns, line-by-line matching of multi-line constructs) and false positives (legit commands blocked).
3. **Exit-code semantics** — hooks must exit 2 to block / 0 to allow per their contract; helpers' documented rc values match reality.
4. **Trap/lock hygiene** — locks released on SIGINT/SIGTERM; mktemp cleaned; partial writes impossible (atomic mv).
5. **Portability** — BSD/GNU divergence (`grep -P`, `stat -c`, `sed -i`, `tac`); `#!/usr/bin/env bash`.
6. **Input validation** — env-var overrides sanitized; malformed JSON stdin handled (fail-open vs fail-closed chosen deliberately and matching the hook's safety role).

Tier mapping: bypassable guard / data-loss path → T0; behavioral bug → T1; latent-but-unreachable → T4.

## D6 — Over-complication & instruction bloat

**Scope:** `skills/`, `agents/`, `.claude/skills/`. The project-local skills ship to nobody, but they load on every plugin-editing session and sit outside every other bloat check, which is where the densest over-specification in the repo accumulates. **Method:** LLM reviewer. The goal is REMOVAL/COMPRESSION candidates — every finding proposes one concrete action: delete, shorten, merge, move to a sibling reference file, or convert a deterministic constraint to a hook/script. Apply the per-line test to every candidate: "would removing this make Claude err?" If not, it is weight without payload. Target signal density, not raw size — see `.claude/rules/skill-prose.md` §Token budget awareness for the why: what degrades rule-following is the number of plausible-but-inapplicable rules the model has to adjudicate between, not the volume of text, so a near-duplicate or a drifted restatement costs far more than its word count (restatements — check 1 — and cross-file duplicates — check 8 — actively harm, not merely bloat). Where a rule is load-bearing for one kind of task only, prefer scoping it to that work over deleting it.

Checks:
1. **Restatements.** Same rationale stated ≥2× within one file; "in other words" summaries; rule text duplicating an anti-rationalization row.
2. **Hedges** without a condition ("may or may not", "depending on the situation").
3. **Collapsible steps.** Adjacent steps that always run together with no decision between them; sub-step trees deeper than the decision structure warrants.
4. **Dead anti-rationalization rows.** Rows defending against a failure mode the current design makes impossible (e.g., the step it polices was removed).
5. **Example & option overload.** >3 examples per concept or near-identical examples teaching one pattern; option lists offering >2 choices with no stated default → collapse to one default + one escape hatch.
6. **Model-known instruction.** Text re-explaining standard tool behavior or general competence the model already has ("read before editing", "write clean code") — delete, or convert a hard constraint to a hook. This is the per-line test's most common failure.
7. **Over-specified procedure.** Instructions narrating what the model would do anyway — trivial substeps, platform-specific command mechanics, shell idioms, workaround recipes for environment quirks the model can resolve on its own. Assume a capable model: state the goal and the bound ("poll until ready or ~30s"), not the mechanics of achieving it (per `.claude/rules/skill-prose.md` §Assume a capable model). Also: Definition-of-Done lists restating every body step instead of exit gates.
8. **Cross-file duplicated rules.** The SAME rule (prose, not a constant — D7 owns constants) stated in ≥2 files. Keep one canonical home; others cite it with `§`. A duplicate that has DRIFTED reads as a contradiction.
9. **Appended-patch contradiction.** A later note / "NOTE:" / exception / caveat that patches or narrows an earlier rule in the same file instead of being folded into it — the later text silently overrides the earlier (recency wins) or forces reconciliation. Rewrite the original to be correct on its own; delete the patch.
10. **Token-budget pressure.** SKILL.md detail that belongs in a sibling reference file (multi-paragraph explanations of one step, inline pseudo-code duplicated from a reference, or a large fully-unique block — a long template, full schema table, big example set) — propose a MOVE, not a cut. Redundancy is not a precondition. A MOVE only pays when the destination is conditionally loaded, so name the runs that will not read it: a reference every run of the skill loads is part of that skill's always-on budget, and a move into an `agents/*.md` body is never a saving, since an agent body is injected whole as the subagent's system prompt.

11. **Dead instructions (liveness).** Checks 1-10 ask whether text is redundant. This one asks whether it is REACHABLE AT ALL — the dead-code question, and the highest-value removal in the dimension, because a rule that can never apply still costs adjudication on every run. Five shapes:
    - **Orphaned policeman** — an instruction, gate, or anti-rationalization row governing a step, phase, or sub-command that no longer exists (a phase split or a deletion is the usual cause).
    - **Unreachable branch** — a condition on a flag, mode, or option the skill no longer ships, or a gate whose trigger cannot occur.
    - **Write-only / read-only field** — a state or frontmatter field written by no producer, or read by no consumer.
    - **Defunct defense** — a rule defending against a failure mode the current design makes structurally impossible.
    - **Superseded remnant** — text left behind by a refactor that replaced its mechanism, still describing the old one.

    **Liveness is a claim — prove it before reporting.** Name the step / flag / gate / field / failure mode, then grep the repo for it. Zero hits outside the instruction itself → report the deletion, with the grep as the evidence. Any real hit → not dead; if it is merely wordy it belongs to checks 1-10 instead. A "this looks obsolete" with no grep behind it is inadmissible, exactly like an unverified `file:line`.

Tier mapping: T4 by default; pure-style items → T5; a duplicated rule that has drifted into a contradiction → T1. Every removal carries regression risk — propose, never auto-cut; state what behavior would change if the deletion is wrong.

**This dimension is expected to subtract.** The repo grows by default and nothing else removes, so a D6 pass returning only additive or purely-stylistic findings has under-delivered. Report a liveness sweep that genuinely found nothing dead as its own result — that is a real finding about the repo's health, not an empty return.

## D7 — Magic numbers & duplicated constants

**Scope:** `skills/`, `agents/`, `.claude/skills/`, `hooks/`, `lib/`. **Method:** LLM reviewer seeded with a number-density grep.

Seed grep (orchestrator runs, pastes matches into the prompt): `grep -rhoE '(≤|>=|<=|≥|max |cap |within )[0-9]+|[0-9]+ (retries|rounds|lines|files|questions|attempts|seconds|chars|tokens)' skills/ agents/ .claude/skills/ | sort | uniq -c | sort -rn | head -80` — `-h`, not `-n`: a `file:line:` prefix makes every line unique, so `uniq -c` would count nothing and the multi-homed-constant signal vanishes; the reviewer greps locations for the candidates it pursues. Plus `grep -rnE '[0-9]{3,}' hooks/ lib/ --include='*.sh' | grep -v ':[[:space:]]*#'` (POSIX class, not `\s` — BSD grep treats `\s` as a literal `s`).

Checks:
1. **Unexplained thresholds.** A numeric limit with no adjacent rationale and no citation to a canonical source. The fix is an inline WHY or a citation — keep the number itself.
2. **Multi-homed constants.** The same threshold stated in ≥2 files (drift risk even while values agree). Fix: pick one home, others cite it.
3. **Contradicting constants.** The same concept with DIFFERENT values in different files (this is a T1, not T4).
4. **Shell literals.** Hardcoded sizes/timeouts in hooks/lib without a comment or env-override; duplicated literals that must move in lockstep.
5. **Stale numbers in prose.** Counts that drift with the repo ("the 11 skills", "43 helpers", "6 sub-checks") — verify each against reality; prefer rewording to avoid hardcoded counts where the list lives elsewhere.

Tier mapping: contradicting constants → T1; multi-homed / unexplained → T4; stale prose counts → T3.

## D8 — Safety & test coverage

**Scope:** `hooks/hooks.json`, `hooks/`, `lib/`, `tests/`, `settings.json`, `cursor/hooks.json`, `cursor/hooks/`, plus `skills/` for check 6 only (destructive-op grep). **Method:** LLM reviewer.

Checks:
1. **Matcher coverage.** Every guard hook's `hooks.json` matcher covers ALL tools that can perform the guarded action (Edit/Write/MultiEdit/NotebookEdit; Bash variants). A guard that misses one tool is bypassable — T0.
2. **Sanitization coverage.** Every field that reaches a persisted artifact passes through `redact-secrets`; new fields added to emit paths are walked by the sanitize loop.
3. **Fail-open vs fail-closed.** For each guard: what happens when `jq` is missing, stdin is malformed, or safety.json is unparseable? Safety-critical guards should fail closed; convenience hooks may fail open — flag mismatches with the hook's role.
4. **Bypass-list integrity.** Every documented `allow_patterns` ID is actually checked by its hook; every hook bypass branch has a documented ID (CLAUDE.md + HOOKS.md).
5. **Test coverage map.** For each hook and each data-mutating lib helper: does a `tests/**` suite exercise it (both block and allow paths for guards)? Untested hard-block guards and untested live data-mutators → T1.
6. **Destructive-op surface.** Any `rm -rf`, `git push`, `--force` usage in skills/hooks/lib outside the documented guarded paths.

Tier mapping: bypassable guard / unsanitized secret path → T0; untested live mutator / wrong fail direction → T1; map gaps → T4.

---

## Do-not-flag list (endorsed patterns)

Verified healthy by prior audit — re-flagging these is a false positive:

- **Resolving `§N` section anchors** — content anchors are the endorsed cross-reference form; only dangling/inverted ones are defects.
- **Caps inside anti-rationalization right-hand cells** when accompanied by reasoning.
- **Justified magic numbers with adjacent WHY** (convergence ≥2/≥3, ≤5-question cap, ≤50-file scan cap, 4096 PIPE_BUF, retry counts with backoff rationale) — keep numeric.
- **Author-facing tier/layer codes (T1/L4/m6-v2) in architecture docs** (`CLAUDE.md` §State Files / §Memory Layers, `state-tier-spec.md`) — the plain-English rule binds user-facing strings, not author-facing architecture sections.
- **Decision-type tags and memory codes in skill-body declarative prose** — only their leakage into user-facing strings is a defect.
- **Line caps treated as guidelines** — a 510-line SKILL.md is advisory, not a defect demanding cuts.
- **Deleted-skill names inside CLAUDE.md's replacement table and MIGRATION.md** — documentation of the deletion, not a stale reference.
- **Rich SKILL.md `description:` fields carrying trigger keywords + what/when** — the description is the sole signal Claude uses to select a skill, so its keywords are load-bearing; trimming them to save tokens degrades selection (a compaction pass's most common own-goal). Flag a description only for exceeding the 1024-char limit (D1) or for body drift (D2 check 2), never for verbosity.
- **The three deliberately-unwired Cursor hooks** (gate-render, evidence-stop, update-check) — their absence from `cursor/hooks.json` is documented: those events do not map cleanly to a Cursor slot. Only a WIRED guard that fails open under the shim is a defect.
- **`cursor/agents/*.md` divergence from `agents/*.md` in dropped fields** (`tools`, `maxTurns`, forced `model: inherit`, added `readonly`) — that is the generator's contract, not drift. Real drift is caught by `tests/cursor/build-agents-fresh.sh`; flag only what that test cannot see.
- **`agents/<name>-reference.md` companions** — body-overflow targets prescribed by `.claude/rules/skill-structure.md`; they carry no agent frontmatter by design and are skipped by the Cursor generator.
