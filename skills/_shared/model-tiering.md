# Model tiering — canonical rule

Single source of truth for picking a `model=` when spawning subagents from any skill in this plugin.

## Contents

- The rule — inherit by default; OMIT `model=`; the four non-inherit categories
- Sizing a non-judgment spawn — `sonnet` is the ceiling, the orchestrator picks below it
- Runtime resolution — how each host spells these tiers
- `--subagent-model` — user-elected run-wide override
- Tier table — fallback for runtimes without an orchestrator
- Escalation signals (orchestrator-side advisory)
- Runtime escalation (Sonnet → Opus on failure)
- Hard rules
- Anti-rationalization

## The rule

**Judgment-grade subagents inherit orchestrator tier by default.** A judgment-grade spawn is one that *decides* something the orchestrator will act on — what the code does, whether a finding is real, which approach to take, what a diff should contain. Frontmatter declares `model: inherit` (except the carve-outs in categories 3-4 below, which declare or pin a concrete cheaper tier); spawn sites **OMIT the `model=` argument** unless a category below names them — the agent's frontmatter `model:` governs (inherit-agents resolve to the orchestrator tier; carve-out agents resolve to their declared tier). Rationale: the user explicitly chose their orchestrator tier (Opus / Sonnet / Haiku) at session start, and the quality of a *decision* scales with the tier that makes it. The user owns the cost / quality trade-off on judgment work — pinning a reviewer or a researcher cheaper is the documented paternalism anti-pattern.

The Agent tool's `model=` argument enum is `sonnet|opus|haiku|fable`; passing `model="inherit"` at the call site fails input validation with "Invalid tool parameters". Propagate `inherit` by **OMITTING the runtime arg** — Claude Code's Agent tool resolver picks up the orchestrator's tier when `model=` is unset.

**A tier other than inherit is set in four narrow categories.** Category 1 is the user's own declaration on a judgment agent. Categories 2-4 are *non-judgment* spawns, and §Sizing a non-judgment spawn below governs what tier they actually get.

1. **User-authored custom reviewers** (`.geniro/instructions/review-extra/<slug>.md` with an explicit `model:` field). That's the user's own opt-in — their declaration overrides inherit. Absent declaration in custom-reviewer frontmatter = inherit (NOT a hidden default to Sonnet).

2. **Plugin-defined mechanical-only spawn sites** whose workload is a fixed check-and-report:
   - `/geniro:setup`'s Phase 4 verification subagent → `model="sonnet"` — runs a fixed check list against the generated CLAUDE.md and emits PASS / DRIFT lines. No hypothesis generation and no judgment call: the orchestrator re-decides from those lines, so output quality does not scale with orchestrator tier. Same mechanical shape as the category-3 agents below, set at the spawn site because this spawn has no agent file to carry the tier in frontmatter.

   The site carries an inline comment justifying the exemption. Any new non-inherit site requires the same justification — and the justification names what actually constrains the spawn (a mechanical, re-decidable output), never a tool restriction the spawn call cannot express: the Agent tool takes no `tools=` argument, so a tier defended by a claimed tool budget is defended by nothing. The tier is a speed/cost preference, not a hard requirement — apply the empty-result fallback in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` so the spawn degrades to inherit (then inline) when the target tier is unavailable in the runtime.

3. **Plugin-defined mechanical / recoverable-evidence agents** that declare a concrete cheaper tier in their OWN frontmatter (so every spawn site still OMITs `model=` and the frontmatter governs — the universal spawn-site rule is unchanged):
   - `${CLAUDE_PLUGIN_ROOT}/agents/test-runner-agent.md` → `model: sonnet` — runs the test command and parses stdout into a fixed `{ALL_GREEN|HAS_FAILURES|INFRA_ERROR}` verdict plus capped failure snippets. No hypothesis generation or judgment: the orchestrator re-decides from the verdict and re-greps the saved log, so output quality does not scale with orchestrator intelligence. Pure mechanics.
   - `${CLAUDE_PLUGIN_ROOT}/agents/knowledge-retrieval-agent.md` → `model: sonnet` — mechanical search-and-cite across the memory layers; its one relevance filter is a one-line, hard-capped, citation-recoverable gate, so a weaker model's failure mode is bounded padding (which the orchestrator filters via the citations), not missed knowledge.

   Both declare **`sonnet`, never `haiku`**, because frontmatter is a fixed value a spawn cannot re-evaluate and Haiku 4.5 has no 1M-context variant — a haiku-frontmatter agent returns `0 tokens` from a 1M-context session, with no orchestrator judgment in the loop to catch it. Sonnet is the safe declared value; §Sizing below is where a cheaper tier gets chosen, at the spawn site, where the workload is visible and the fallback is one retry away. These are cost optimizations on genuinely mechanical agents — distinct from the reviewer / finding-verifier / codebase-research / codebase-explorer / reflection agents, whose output quality scales with orchestrator intelligence and which therefore stay `inherit` (pinning those cheaper is the paternalism anti-pattern below).

4. **Execution spawns — `model="sonnet"` by default.** A spawn is an execution spawn when the decision is already made and the deliverable is applying it: the orchestrator (or the user, at an approval gate) has settled *what* changes, and the subagent's job is to carry that into files it was handed by name. The tier that decided is the tier that mattered; running the transcription on a reasoning-grade model buys nothing.

   The current sites — each carries an inline comment naming this category:

   | Site | Applies |
   |---|---|
   | `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-2-implement.md` §Steps, the delegation rule | one already-decomposed todo slice, against a named disjoint file set |
   | `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` §Step 1: Spawn the UI description agent | a read-only spec→description transform, no file writes at all |
   | `${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/SKILL.md` §Phase 5 fix path | user-approved instruction-file findings into their assigned file allowlist |

   This table lists only sites under `${CLAUDE_PLUGIN_ROOT}` — the shipped tree every consumer install carries. The plugin repo's own maintenance skills (`.claude/skills/`) apply the same category-4 logic at their own fix-agent spawns, but that tree never ships, so a shipped file names no path under it.

   **A ceiling, not a floor.** `sonnet` is what the site gets absent a reason to spend less, and never more — a session on a reasoning tier does not push that tier into transcription work. Below it, §Sizing applies: an execution spawn is the clearest case for it, since the orchestrator reads every delegate's diff against a named allowlist before accepting it.

   **What this category does NOT cover.** The boundary is decide-vs-apply, not the shape of the output. An agent whose deliverable is still a judgment call stays `inherit` even when that judgment lands in a rigid, pre-defined schema: `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` returns one fixed-shape block per finding — severity, confidence, decision-type — but the values inside that schema are the analysis itself, not a decision already made elsewhere and merely transcribed, so it stays `inherit` per its own frontmatter. Nor does it cover a spawn whose file set the subagent must still discover — a delegate that has to work out *which* files to touch is deciding, and the delegation rule already refuses that shape.

## Sizing a non-judgment spawn

Categories 2-4 name what the tier is *not* — not the user's reasoning-grade choice, because the reasoning already happened. `sonnet` is the ceiling for all of them. **Below that ceiling the orchestrator picks the tier from the workload actually in front of it**, and states the pick with a one-clause reason at the spawn site. Cursor already works this way and spells it `auto`, handing the choice to the host's selector; Claude Code has no such selector, so the orchestrator is the selector. A re-run of one test file, a rename across three call sites, a description of a two-screen flow — each is smaller than `sonnet` assumes, and matching the spend to it is the point of the ceiling.

Two conditions bound a down-pick, and every category 2-4 site already satisfies both: the output is **checkable without redoing the work** (a verdict the orchestrator re-decides from, a diff it reads against an allowlist, PASS/DRIFT lines it re-judges), and **recovery is one re-spawn**, never a wrong ship. Take the ceiling where either fails — and take it where the size is not knowable before the spawn, since guessing small is not the same as knowing it: the first test run of an unfamiliar suite is a ceiling case, its retry after a one-line fix is not.

`haiku` is inside the band and frequently unspawnable from a 1M-context session; `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` §Empty-result fallback recovers it and sets the session's floor.

**One tier per parallel batch.** Model is part of the prompt-cache key, so siblings spawned in one response share a prefix only while they share a tier. Size the batch as a unit — one tier for all of it, set by its largest member — rather than per-member.

**When a down-pick comes back wrong** — schema violated, verdict unusable, an edit outside the allowlist — re-spawn that one site once at the ceiling and hold the ceiling for that site for the rest of the run. That is the whole tier ladder here: a mechanical spawn still failing at its ceiling is not a tier problem, so it goes to the caller's own error path (a fix loop, an escalation gate), never up to a reasoning tier — §Runtime escalation is scoped to reasoning-grade carve-outs and does not reach these sites. A sized-down spawn re-judged in the orchestrator's own context rather than re-spawned has spent the saving twice.

**A run carrying `--subagent-model` turns this section off.** The user named a tier, so the plugin does not then size under it — the same override the rule forbids in the other direction. Sizing is the default behavior of a run that named nothing.

This section is the whole lever. It does not reach across the decide-vs-apply line: a judgment spawn whose task looks easy this run is still deciding, and still inherits.

## Runtime resolution — how each host spells these tiers

`haiku` / `sonnet` / `opus` are Claude Code model ids, and `skills/` is shared by both runtimes (`ARCHITECTURE.md` §Dual-runtime port (Cursor)) — so a spawn site written above is read verbatim under Cursor, whose roster carries no `sonnet`. The tiers name INTENTS; each host spells them its own way:

| Intent | Claude Code | Cursor |
|---|---|---|
| Judgment-grade — the tier the user chose | OMIT `model=` | omit the model argument |
| Mechanical / execution (categories 2-4) | `model="sonnet"`, or the cheaper tier §Sizing picked | `model="auto"` — the host's selector is Cursor's version of §Sizing |
| One-shot escalation after a failure (§Runtime escalation) | `model="opus"` | omit the model argument — inheriting the session tier IS the step up from `auto` |

`auto` is Cursor's own selector (first entry in `cursor-agent --list-models`, and its default): a server-side classifier picks per task. **Never substitute a pinned Cursor model id instead.** The roster turns over constantly, and an id that is unavailable or blocked by team policy falls back silently to something else — `auto` is the only stable way to say "this workload is mechanical, spend accordingly". It means "the host decides", not "always cheaper": a session already on a cheap model can see `auto` pick something dearer. That is still the right semantic, because the point is that the tier stops being the user's reasoning-grade choice. This rule binds the plugin's own category 2-4 spawn sites, which pick a tier on the user's behalf — it says nothing about the user naming a model for their own run, which `--subagent-model` (below) exists to do.

Agent frontmatter needs no per-site handling — `scripts/build-cursor-agents.sh` applies this same table when it generates `cursor/agents/` from `agents/*.md`, and rejects a tier the table cannot express.

**Cursor subagent model field — corrected 2026-08-17.** Cursor's subagent frontmatter documents a `model` field taking `inherit` (default) or a specific model ID (cursor.com/docs/subagents) — a real, supported capability, not a no-op. Whether a declared model actually takes effect depends on the plan: on request-based plans without Max Mode, Cursor forces subagents onto the Composer family to control cost regardless of what the field declares (Cursor staff, 2026-07-02; a user confirmed switching to Max Mode restored the declared model). The same silent substitution happens when a team admin blocks a model or it isn't on the plan — Cursor falls back to a compatible model with no warning either way. Treat a declared subagent `model:` as real but conditional: it takes effect on Max Mode (or an unrestricted plan) and is silently overridden otherwise, with nothing in the transcript distinguishing the two. What works unconditionally regardless of plan: setting the SESSION model propagates to every subagent, so that stays the reliable lever to tell a Cursor user about.

## `--subagent-model` — user-elected run-wide override

A run-scoped flag on `/geniro:implement` and `/geniro:review` (values `sonnet` / `opus` / `haiku` / `fable`) naming the tier the user wants this run's spawns to reason at, overriding agent frontmatter. Announce it once at run start (name the tier) so it stays visible for the rest of the session.

**It pins judgment spawns and caps the rest.** A judgment-grade spawn takes the value verbatim — reasoning depth is what the flag buys. A category 2-4 spawn treats it as a ceiling: a flag naming a *stronger* tier does not raise it, because `--subagent-model opus` is a request for deeper judgment and putting Opus on a test re-run answers a question nobody asked; a flag naming a *cheaper* tier does lower it, because "spend less everywhere" is exactly what that election says. Where you cannot place the named tier against a spawn's own — `fable` has no settled position in this ordering — leave that spawn at its own tier and say so once. Either way the resulting tier is final: a flagged run does not also size below it (§Sizing a non-judgment spawn).

This is not the paternalism the anti-rationalization table forbids below: that rule stops the *plugin* choosing a cheaper tier on the user's behalf, unprompted. `--subagent-model` is the user's own declaration for one run — the same shape as category 1's custom reviewer, which already overrides inherit by declaring `model:` in its own file. What the rule tracks is who decided, not which tier came out.

**Expressible values only.** The value has to be one the Agent tool's `model=` argument can actually carry — the closed `sonnet|opus|haiku|fable` enum from §The rule, the same set `inherit` can't join either, which is why inherit is propagated by omitting the argument rather than passing the word. A `--subagent-model` value outside those four hits the identical wall: no spawn-site argument expresses it. A run given such a value does not drop it silently — it says so and names the two routes that still work:

- **Claude Code:** `CLAUDE_CODE_SUBAGENT_MODEL`, a session-wide environment variable that overrides every subagent's model — it takes precedence over both frontmatter and the spawn argument, but must be set before the session starts, so a mid-run request can only be relayed to the user, not applied live. A non-Anthropic model id passes through this variable only behind a gateway or non-Anthropic provider; Anthropic documents routing to non-Claude models this way as unsupported.
- **Cursor:** the agent file's own `model:` frontmatter (subject to the plan gating in §Runtime resolution above), or — as an explicit escape hatch — spawning via `cursor-agent -p --model <id> --output-format text` from Bash instead of the Task tool. This bypasses the plugin's agent registry and the `Context loaded:` reporting contract, so the caller owns output parsing and failure handling; treat it as the escape hatch, not the default route.

**`effort`** (`low` / `medium` / `high` / `xhigh` / `max`), a Claude Code agent-frontmatter field, is a second cost lever independent of model choice — a tier and an effort level compose rather than substitute.

**Caching consequence.** Model and effort are part of the prompt-cache key; sibling subagents that share agent type, model, effort, tool set, and working directory share a cache prefix. What that requires is uniformity **within a parallel batch**, not across the run — a mixed per-dimension reviewer fan-out forfeits the sharing, while a singleton test-runner spawn on its own tier costs nothing. §Sizing carries the same rule.

## Tier table — fallback for runtimes without an orchestrator

When a plugin subagent is invoked in a context without an interactive orchestrator parent (cloud-runner harness, batch evaluation, headless CI), the calling layer SHOULD pick a tier per the table below, resolved for its host per §Runtime resolution. This is **fallback**, not preference — interactive runs always inherit.

| Task nature | Fallback model |
|---|---|
| Mechanical edit, template-based doc patching, rubric-based style review (the conventions dim's style-rubric checks), CLI orchestration, structured PASS/FAIL classification, dedup checks, observation extraction | `haiku` |
| Code reasoning, implementation, bugs/security/architecture/tests/optimizations/conventions/design review, spec compliance, refactor with zero-behavior guarantee, parallel research with narrow focus | `sonnet` |
| Architecture design, multi-file planning, deep hypothesis-driven debugging, threat modeling, novel-domain greenfield work | `opus` |

## Escalation signals (orchestrator-side advisory)

When a task's shape argues for a stronger tier, surface a one-line advisory and continue — e.g. "Spec touches auth boundary + async work — consider running on Opus tier if not already (current: <tier>)". Signals never drive an automatic tier override; the user retains authority via `/model`.

No skill wires per-signal detection for this. An advisory the user can act on only by abandoning the run and restarting on another tier does not earn a scan on every run, and the same risk surface already reaches them through the change-scope estimate and the reviewer dimensions. Read the signals as judgment cues when picking a tier up front: a schema or migration change, an auth or role boundary, 3+ coordinated modules, a new external integration, async / queue / background work, an ambiguous spec or absent acceptance criteria, a novel problem domain with no similar code in the repo to copy, long-horizon autonomy (multi-step plan, no human checkpoints), and an open-closed violation (changing public signatures, shared middleware, routing).

## Runtime escalation (Sonnet → Opus on failure)

Still applicable to the finding-verifier's high-stakes refutation retry path (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §5) and other reasoning-grade carve-outs that internally escalate. NOT applicable to inherit-default subagents (their tier IS the orchestrator's tier; "escalation" would mean changing the orchestrator mid-session, which is the user's call).

When a `sonnet` subagent returns wrong output, fails its checklist, or fails tests:

1. Re-dispatch ONCE with: more context (paste the failure) + `model="opus"`.
2. If the opus retry also fails, escalate to the user — do not loop.
3. Never bump twice in a row. Never escalate `haiku` → `opus` directly (go `haiku` → `sonnet` first).

## Hard rules

- **Architect-flavored work (multi-file design, planning, threat modeling) runs orchestrator-side**, not in a subagent. The orchestrator's own model handles this reasoning inline. (When the orchestrator is on Opus, architecture work happens on Opus; when on Sonnet, on Sonnet. The user picks.)

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll pass `model='sonnet'` explicitly at the reviewer-agent spawn site to ensure cost containment — the user might not realize Opus is expensive." | Forbidden — this is the plugin picking a cheaper tier on the user's behalf, unprompted. A reviewer decides whether a finding is real, so it is judgment-grade and inherits per the Rule. User chose Opus at session start with full knowledge of cost; overriding back to sonnet without being asked is paternalistic and produces tier-mismatch UX. If the user wants cheaper review, they switch orchestrator tier, or pass `--subagent-model sonnet` on the run itself — an explicit election the plugin honors (§`--subagent-model`), the same shape as a custom reviewer's own declared `model:`. What's forbidden is the plugin deciding for the user; what's permitted is the user deciding for themselves. Category 4 is not a licence to widen this either: it covers spawns that apply a decision already made, and a reviewer is never one. |
| "This spawn writes files, so it's an execution spawn — pin it sonnet." | Writing files is not the test; category 4's test is whether the decision is already made. An agent still working out *what* the content should be — reviewer-agent's per-finding severity and confidence, a delegate that must first find its own file set — is deciding, and decisions inherit. Check category 4's site table: if the spawn isn't in it, adding it needs the same decide-vs-apply argument the listed ones carry. |
| "Opus is overkill for the `conventions` dimension's style-rubric checks (rubric-based pattern match) — I'll force haiku at the spawn site." | Forbidden. Inherit symmetry holds for all dimensions. User-Opus → conventions on Opus (slight overspend, accepted by user when they chose Opus); user-Sonnet → conventions on Sonnet; user-Haiku → conventions on Haiku (matches the rubric model). Inheriting is correct in all three cases; hardcoding breaks symmetry asymmetrically. |
| "Custom reviewer's `.geniro/instructions/review-extra/<slug>.md` doesn't declare `model:` — I'll default to sonnet at the spawn site." | When `model:` is OMITTED in the custom reviewer's frontmatter, treat it as "inherit", not "sonnet". Custom reviewers follow the same default as built-ins. The user opts INTO a hardcoded tier only by explicitly writing `model: haiku` / `model: opus` in their custom-reviewer frontmatter — that's their declaration, honor it. |
| "Plugin subagent spawning fails because the Agent tool doesn't accept `model='inherit'`." | Correct — the tool doesn't. At an inherit spawn site the fix is to OMIT `model=` entirely, not to fall back to a hardcoded value: the resolver picks up orchestrator tier when the arg is unset, and hardcoding a fallback defeats the inherit contract. A category 1-4 site is different — its tier is declared, so it passes that tier verbatim. |
| "User is on Haiku; subagents on Haiku will produce low-quality output for reasoning dimensions." | User chose Haiku — they accepted the trade-off. Plugin paternalism ("I know better, bump to Sonnet") defeats the user's tier choice. If a reviewer-agent on Haiku misses bugs, surface this in the Phase 6 handoff summary ("findings count: 2 — note: orchestrator tier is Haiku; consider /model switch to Sonnet for deeper review"), not by silent override. |
| "This reviewer dimension is simple on this diff — I'll size it down the way §Sizing sizes a test re-run." | §Sizing lives entirely on the non-judgment side of the decide-vs-apply line. An easy-looking dimension is not a decision already made: the reviewer still decides whether a finding is real, and that is the tier the user bought. The band never crosses the line — a spawn is either in categories 2-4 or it inherits. |
| "The run carries `--subagent-model opus`, so the test-runner and the code-delegate go to Opus too — the flag says every spawn." | The flag buys reasoning depth, and neither of those spawns reasons. It pins judgment spawns and *caps* categories 2-4 (§`--subagent-model`): stronger never raises them, cheaper does lower them. A `--subagent-model haiku` run does drag them down with it. |
