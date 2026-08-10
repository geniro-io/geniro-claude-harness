# Model tiering — canonical rule

Single source of truth for picking a `model=` when spawning subagents from any skill in this plugin.

## Contents

- The rule — inherit by default; OMIT `model=`; the four hardcoded-tier categories
- Runtime resolution — how each host spells these tiers
- Tier table — fallback for runtimes without an orchestrator
- Escalation signals (orchestrator-side advisory)
- Runtime escalation (Sonnet → Opus on failure)
- Hard rules
- Anti-rationalization

## The rule

**Judgment-grade subagents inherit orchestrator tier by default.** A judgment-grade spawn is one that *decides* something the orchestrator will act on — what the code does, whether a finding is real, which approach to take, what a diff should contain. Frontmatter declares `model: inherit` (except the carve-outs in categories 3-4 below, which declare or pin a concrete cheaper tier); spawn sites **OMIT the `model=` argument** unless a category below names them — the agent's frontmatter `model:` governs (inherit-agents resolve to the orchestrator tier; carve-out agents resolve to their declared tier). Rationale: the user explicitly chose their orchestrator tier (Opus / Sonnet / Haiku) at session start, and the quality of a *decision* scales with the tier that makes it. The user owns the cost / quality trade-off on judgment work — pinning a reviewer or a researcher cheaper is the documented paternalism anti-pattern.

The Agent tool's `model=` argument enum is `sonnet|opus|haiku`; passing `model="inherit"` at the call site fails input validation with "Invalid tool parameters". Propagate `inherit` by **OMITTING the runtime arg** — Claude Code's Agent tool resolver picks up the orchestrator's tier when `model=` is unset.

**Hardcoded tier is allowed in four narrow categories:**

1. **User-authored custom reviewers** (`.geniro/instructions/review-extra/<slug>.md` with an explicit `model:` field). That's the user's own opt-in — their declaration overrides inherit. Absent declaration in custom-reviewer frontmatter = inherit (NOT a hidden default to Sonnet).

2. **Plugin-defined mechanical-only spawn sites** whose workload is a fixed check-and-report:
   - `/geniro:setup`'s Phase 4 verification subagent → `model="sonnet"` — runs a fixed check list against the generated CLAUDE.md and emits PASS / DRIFT lines. No hypothesis generation and no judgment call: the orchestrator re-decides from those lines, so output quality does not scale with orchestrator tier. Same mechanical shape as the category-3 agents below, hardcoded at the spawn site because this spawn has no agent file to carry the tier in frontmatter.

   The site carries an inline comment justifying the exemption. Any new hardcode requires the same justification — and the justification names what actually constrains the spawn (a mechanical, re-decidable output), never a tool restriction the spawn call cannot express: the Agent tool takes no `tools=` argument, so a tier defended by a claimed tool budget is defended by nothing. A hardcoded tier is a speed/cost preference, not a hard requirement — apply the empty-result fallback in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` so the spawn degrades to inherit (then inline) when the target tier is unavailable in the runtime (e.g. a Haiku spawn from a 1M-context Opus/Sonnet session returns `0 tokens`, since Haiku has no 1M-context variant).

3. **Plugin-defined mechanical / recoverable-evidence agents** that declare a concrete cheaper tier in their OWN frontmatter (so every spawn site still OMITs `model=` and the frontmatter governs — the universal spawn-site rule is unchanged):
   - `${CLAUDE_PLUGIN_ROOT}/agents/test-runner-agent.md` → `model: sonnet` — runs the test command and parses stdout into a fixed `{ALL_GREEN|HAS_FAILURES|INFRA_ERROR}` verdict plus capped failure snippets. No hypothesis generation or judgment: the orchestrator re-decides from the verdict and re-greps the saved log, so output quality does not scale with orchestrator intelligence. Pure mechanics.
   - `${CLAUDE_PLUGIN_ROOT}/agents/knowledge-retrieval-agent.md` → `model: sonnet` — mechanical search-and-cite across the memory layers; its one relevance filter is a one-line, hard-capped, citation-recoverable gate, so a weaker model's failure mode is bounded padding (which the orchestrator filters via the citations), not missed knowledge.

   Both pin **`sonnet`, never `haiku`**: the fallback tier table below would place these mechanical workloads at haiku, but Haiku 4.5 has no 1M-context variant, so a haiku-frontmatter agent returns `0 tokens` when spawned from a 1M-context Opus/Sonnet session. Sonnet is the safe floor. These are deliberate cost optimizations on genuinely mechanical agents — distinct from the reviewer / finding-verifier / codebase-research / codebase-explorer / reflection / adversarial-tester agents, whose output quality scales with orchestrator intelligence and which therefore stay `inherit` (pinning those cheaper is the paternalism anti-pattern below).

4. **Execution spawns — `model="sonnet"`, hard-pinned.** A spawn is an execution spawn when the decision is already made and the deliverable is applying it: the orchestrator (or the user, at an approval gate) has settled *what* changes, and the subagent's job is to carry that into files it was handed by name. The tier that decided is the tier that mattered; running the transcription on a reasoning-grade model buys nothing.

   The current sites — each carries an inline comment naming this category:

   | Site | Applies |
   |---|---|
   | `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-2-implement.md` §Steps, the delegation rule | one already-decomposed todo slice, against a named disjoint file set |
   | `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` §Step 1: Spawn the UI description agent | a read-only spec→description transform, no file writes at all |
   | `.claude/skills/improve-template/SKILL.md` Phase 4 implementers and every fix agent *(plugin-repo maintenance skill — does not ship to consumer installs)* | user-approved findings into named template files |
   | `.claude/skills/audit-plugin/SKILL.md` Phase 5 fix agents *(plugin-repo maintenance skill — does not ship to consumer installs)* | user-approved findings into their assigned file allowlist |
   | `${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/SKILL.md` §Phase 5 fix path | user-approved instruction-file findings into their assigned file allowlist |

   **Hard pin, not a cap.** The tier is `sonnet` whatever the orchestrator runs — a Haiku session gets execution upgraded, which is the safe direction, and no spawn site evaluates a conditional. `haiku` is never the pin, for the 1M-context reason in category 3.

   **What this category does NOT cover.** The boundary is decide-vs-apply, not writes-files. An agent that writes files while still deciding their content stays `inherit`: the `adversarial-tester-agent` authors tests but its deliverable is 5-12 *hypotheses*; the create-skill author agent in `.claude/skills/improve-template/SKILL.md` Phase B composes a skill from an interview rather than transcribing one. Nor does it cover a spawn whose file set the subagent must still discover — a delegate that has to work out *which* files to touch is deciding, and the delegation rule already refuses that shape.

## Runtime resolution — how each host spells these tiers

`haiku` / `sonnet` / `opus` are Claude Code model ids, and `skills/` is shared by both runtimes (`ARCHITECTURE.md` §Dual-runtime port (Cursor)) — so a spawn site written above is read verbatim under Cursor, whose roster carries no `sonnet`. The tiers name INTENTS; each host spells them its own way:

| Intent | Claude Code | Cursor |
|---|---|---|
| Judgment-grade — the tier the user chose | OMIT `model=` | omit the model argument |
| Mechanical / execution (categories 2-4) | `model="sonnet"` | `model="auto"` |
| One-shot escalation after a failure (§Runtime escalation) | `model="opus"` | omit the model argument — inheriting the session tier IS the step up from `auto` |

`auto` is Cursor's own selector (first entry in `cursor-agent --list-models`, and its default): a server-side classifier picks per task. **Never substitute a pinned Cursor model id instead.** The roster turns over constantly, and an id that is unavailable or blocked by team policy falls back silently to something else — `auto` is the only stable way to say "this workload is mechanical, spend accordingly". It means "the host decides", not "always cheaper": a session already on a cheap model can see `auto` pick something dearer. That is still the right semantic, because the point is that the tier stops being the user's reasoning-grade choice.

Agent frontmatter needs no per-site handling — `scripts/build-cursor-agents.sh` applies this same table when it generates `cursor/agents/` from `agents/*.md`, and rejects a tier the table cannot express.

**Measured caveat — `cursor-agent` 2026.08.04, probed 2026-08-10.** `auto` is a real, accepted selector and does route down (a trivial ask on `--model auto` answered `> Auto routed to Cursor Grok 4.5`). But that CLI **ignored a subagent's declared model** and derived it from the parent: a `composer-2.5` parent spawned a subagent declaring `model: auto` as `composer-2.5-fast`. Under it this mapping is a no-op. Keep it — it is the documented field, it becomes correct the moment the field is honored, and it costs nothing — but credit it with no saving until a probe shows a subagent running off its own declaration. What DOES work there today, and is worth telling a Cursor user: subagents follow the parent, so setting the SESSION model to `auto` gets auto-routing everywhere, mechanical spawns included. The probe was the CLI only; the IDE was not tested.

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

Still applicable to the adversarial-tester per-finding retry path and other reasoning-grade carve-outs that internally escalate. NOT applicable to inherit-default subagents (their tier IS the orchestrator's tier; "escalation" would mean changing the orchestrator mid-session, which is the user's call).

When a `sonnet` subagent returns wrong output, fails its checklist, or fails tests:

1. Re-dispatch ONCE with: more context (paste the failure) + `model="opus"`.
2. If the opus retry also fails, escalate to the user — do not loop.
3. Never bump twice in a row. Never escalate `haiku` → `opus` directly (go `haiku` → `sonnet` first).

## Hard rules

- **Architect-flavored work (multi-file design, planning, threat modeling) runs orchestrator-side**, not in a subagent. The orchestrator's own model handles this reasoning inline. (When the orchestrator is on Opus, architecture work happens on Opus; when on Sonnet, on Sonnet. The user picks.)

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll pass `model='sonnet'` explicitly at the reviewer-agent spawn site to ensure cost containment — the user might not realize Opus is expensive." | Forbidden. A reviewer decides whether a finding is real, so it is judgment-grade and inherits per the Rule. User chose Opus at session start with full knowledge of cost; over-riding back to sonnet is paternalistic and produces tier-mismatch UX. If the user wants cheaper review, they switch orchestrator tier — that's the canonical knob. Category 4 is not a licence to widen this: it covers spawns that apply a decision already made, and a reviewer is never one. |
| "This spawn writes files, so it's an execution spawn — pin it sonnet." | Writing files is not the test; category 4's test is whether the decision is already made. An agent still working out *what* the content should be — the adversarial-tester's hypotheses, a delegate that must first find its own file set — is deciding, and decisions inherit. Check category 4's site table: if the spawn isn't in it, adding it needs the same decide-vs-apply argument the listed ones carry. |
| "Opus is overkill for the `conventions` dimension's style-rubric checks (rubric-based pattern match) — I'll force haiku at the spawn site." | Forbidden. Inherit symmetry holds for all dimensions. User-Opus → conventions on Opus (slight overspend, accepted by user when they chose Opus); user-Sonnet → conventions on Sonnet; user-Haiku → conventions on Haiku (matches the rubric model). Inheriting is correct in all three cases; hardcoding breaks symmetry asymmetrically. |
| "Custom reviewer's `.geniro/instructions/review-extra/<slug>.md` doesn't declare `model:` — I'll default to sonnet at the spawn site." | When `model:` is OMITTED in the custom reviewer's frontmatter, treat it as "inherit", not "sonnet". Custom reviewers follow the same default as built-ins. The user opts INTO a hardcoded tier only by explicitly writing `model: haiku` / `model: opus` in their custom-reviewer frontmatter — that's their declaration, honor it. |
| "Plugin subagent spawning fails because the Agent tool doesn't accept `model='inherit'`." | Correct — the tool doesn't. At an inherit spawn site the fix is to OMIT `model=` entirely, not to fall back to a hardcoded value: the resolver picks up orchestrator tier when the arg is unset, and hardcoding a fallback defeats the inherit contract. A category 1-4 site is different — its tier is declared, so it passes that tier verbatim. |
| "User is on Haiku; subagents on Haiku will produce low-quality output for reasoning dimensions." | User chose Haiku — they accepted the trade-off. Plugin paternalism ("I know better, bump to Sonnet") defeats the user's tier choice. If a reviewer-agent on Haiku misses bugs, surface this in the Phase 6 handoff summary ("findings count: 2 — note: orchestrator tier is Haiku; consider /model switch to Sonnet for deeper review"), not by silent override. |
