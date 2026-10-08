# Model tiering — canonical rule

Single source of truth for the model a spawned subagent runs on, from any skill in this plugin, on any host.

## Contents

- Cost classes — session by default; the light class and its roles; fallbacks; the batch rule; user overrides
- Runtime resolution — how each host spells the classes
- `--subagent-model` — user-elected run-wide override
- Hard rules
- Anti-rationalization

## Cost classes

Every spawn runs at one class. A site states its class in the sentence that describes the spawn and never names a model, so one skill file reads the same on every host; a site that states none is **session**. In a literal `Agent(...)` block, drop `model=` and put the class in a trailing comment (`# cost class: light (mid) — model-tiering.md §Cost classes`).

- **session** — the default. Pass no model: the subagent runs on the model the user chose for the session. It covers anything that decides what the orchestrator acts on — what the code does, whether a finding is real, which approach to take, what a diff should contain. The user chose the session model knowing its cost, and a decision's quality scales with the model that makes it. The Agent tool's `model=` enum is `sonnet|opus|haiku|fable`, so `model="inherit"` fails input validation ("Invalid tool parameters"); session is expressed by OMITTING the argument, and the host then resolves the orchestrator's model.
- **light** — a spawn that meets all four: (1) it applies a decision already made, or gathers evidence the orchestrator re-checks; (2) its output can be checked without redoing the work; (3) a wrong result costs one re-spawn; (4) its size is known before spawning. Except on Cursor, where the host's selector decides (§Runtime resolution), a light class never runs above the session: when the session model is at or below the class's family, spawn as session and omit the model.
  - **light (smallest)** — a mechanical, fixed-shape check. The host's smallest current model family.
  - **light (mid)** — any other light work. The host's mid current model family. When unsure, use light (mid).

Always use the newest model of the family and never write a version number. §Runtime resolution spells each class per host.

Agent frontmatter never pins a model: every `agents/*.md` declares `model: inherit`, so one agent can be session at one site and light at another.

**Roles that are light** — the sites that name a light class. The list describes them; a site that names none is session.

- light (smallest): the `/geniro:review`, `/geniro:refactor` and `/geniro:onboard` "where is X" locator lookups, the test runner, the scoped learnings read in `/geniro:review`, the setup checklist verifier, the git-history extractor.
- light (mid): applying a decided code slice, applying approved instruction fixes, the UI description, the library web search, the memory sweep and the other scoped learnings reads, ad-hoc research during implementation, grill fact lookups, the internet researcher, the transcript analysts, the `/geniro:audit-instructions` verifiers.

**Fallbacks.**

- A writer (a code delegate, an approved-fix agent) that started and failed is never re-spawned: it may already have written edits, so its caller inspects the tree and takes its own error path. A writer whose model the host refused or does not offer never started, so it steps up like the read-only spawns the bullets below cover.
- **Zero output**, or a model the host does not offer or refuses: step up one class (smallest → mid → session); a session spawn retries once.
- **Malformed or otherwise unusable output**: re-spawn once as session. A light spawn jumps straight to session; a session spawn retries once.
- **Still failing at session** is no model problem: it goes to the caller's own error path (a fix loop, an escalation gate, a verifier's unverified disposition), not to a bigger model.
- Red tests and a refuted finding are results, not failures.

`${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` §Empty-result fallback runs the step-up.

**One class per role or prompt template in a parallel batch.** A shared `subagent_type` (general-purpose, Codex `default`) does not by itself make two spawns the same role, so different roles in one batch may use different classes. Model is part of the prompt-cache key, so batch siblings that share a cached prefix share a class.

**User overrides win over the class:** `--subagent-model` (pins session spawns, caps light ones; beats a custom reviewer's `model:`) and a custom reviewer's own `model:`. Host-level settings apply as the host defines them: `CLAUDE_CODE_SUBAGENT_MODEL` overrides every spawn argument, Codex's subagent default applies where a spawn omits the model, and Cursor's session model propagates.

## Runtime resolution — how each host spells the classes

`skills/` is shared by every runtime, and Claude Code's model names are on no other host's roster. A site names a class; this table spells it. Never substitute a model id of your own choosing.

| Class | Claude Code | Cursor | Codex |
|---|---|---|---|
| session | omit `model=` | omit the model argument | omit `model` |
| light (smallest) | `haiku` | `auto` | the newest `…-luna` in the spawn tool's model list |
| light (mid) | `sonnet` | `auto` | the newest `…-sol` in the spawn tool's model list, with `reasoning_effort: "medium"` |

**Claude Code.** The `haiku` and `sonnet` aliases resolve to the newest model of each family that the installed Claude Code knows. Where `haiku` resolves to a model with a smaller context window than the session's, the spawn comes back empty.

**Cursor.** `auto` is Cursor's own selector (first entry in `cursor-agent --list-models`, and its default): a server-side classifier picks per task, so it means "the host decides", not "always cheaper". A pinned Cursor model id is the wrong spelling — the roster turns over constantly, and an unavailable or team-blocked id falls back silently to something else. A subagent `model:` declared in frontmatter takes effect only on some plans (without Max Mode, Cursor forces subagents onto the Composer family), with nothing in the transcript to say which happened; the reliable lever to tell a Cursor user about is the SESSION model, which propagates to every subagent.

**Codex.** A spawn naming a Claude model fails outright. The spawn tool lists the models it allows; pick the newest model of the family from that list. Codex's tool wants an explicit instruction before it sets a model, and the class declared at the site is that instruction. If the run still omits the model, the work runs at session, which is safe: unless `[agents] default_subagent_model` / `default_subagent_reasoning_effort` are set, a subagent inherits the session's model and reasoning effort. A user-elected model (`--subagent-model`, or a custom reviewer's `model:`) has no Codex spelling: announce once that it is not applied and name `[agents] default_subagent_model` (§`--subagent-model`, Codex route), rather than dropping it silently.

## `--subagent-model` — user-elected run-wide override

A run-scoped flag on `/geniro:implement` and `/geniro:review` (values `sonnet` / `opus` / `haiku` / `fable`) naming the model the user wants this run's spawns to reason at. Announce it once at run start (name the model) so it stays visible for the rest of the session.

**It pins session spawns and caps light ones.** A session spawn takes the value verbatim — reasoning depth is what the flag buys. A light spawn treats it as a cap: a *stronger* value never raises it, because `--subagent-model opus` asks for deeper judgment and putting Opus on a test re-run answers a question nobody asked; a *cheaper* value lowers it, because "spend less everywhere" is exactly what that election says. Where the named model cannot be placed against the class's own — `fable` has no settled position among the light models — leave that spawn at its class and say so once.

The flag is the user's own declaration for one run, the same shape as a custom reviewer's declared `model:` — not the plugin choosing a cheaper model on their behalf, which the anti-rationalization table below forbids.

**Expressible values only.** The value has to be one the Agent tool's `model=` argument can carry — the closed `sonnet|opus|haiku|fable` enum from §Cost classes. A value outside it has no spawn-site argument. A run given one does not drop it silently — it says so and names the routes that still work:

- **Claude Code:** `CLAUDE_CODE_SUBAGENT_MODEL`, a session-wide environment variable that overrides every subagent's model — it takes precedence over both frontmatter and the spawn argument, but must be set before the session starts, so a mid-run request can only be relayed to the user, not applied live. A non-Anthropic model id passes through this variable only behind a gateway or non-Anthropic provider; Anthropic documents routing to non-Claude models this way as unsupported.
- **Cursor:** the session model, which propagates to every subagent, is the reliable lever; as an explicit escape hatch, spawn via `cursor-agent -p --model <id> --output-format text` from Bash instead of the Task tool. The hatch bypasses the plugin's agent registry and the `Context loaded:` reporting contract, so the caller owns output parsing and failure handling.
- **Codex:** `[agents] default_subagent_model` in `~/.codex/config.toml`, a session-wide default that must be set before the session starts, so a mid-run request can only be relayed to the user. Its values are Codex model ids, so the flag's Claude names have no meaning there.

**`effort`** (`low` / `medium` / `high` / `xhigh` / `max`, a Claude Code agent-frontmatter field; Codex `reasoning_effort`) is a second cost lever independent of the model — the two compose rather than substitute. Both are part of the prompt-cache key, so uniformity matters within a parallel batch of one agent (§Cost classes), not across the run.

## Hard rules

- **Architect-flavored work (multi-file design, planning, threat modeling) runs orchestrator-side**, not in a subagent. That reasoning decides, so it runs on the session model.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll run this reviewer light — the user might not realize their session model is expensive." | Forbidden — this is the plugin picking a cheaper model on the user's behalf, unprompted. A reviewer decides whether a finding is real, so it is session however simple the diff looks: an easy dimension is still a decision, and light work applies one already made. The user chose their session model with full knowledge of its cost. If they want cheaper review, they switch the session model or pass `--subagent-model` on the run itself — an explicit election the plugin honors (§`--subagent-model`). What's forbidden is the plugin deciding for the user; what's permitted is the user deciding for themselves. |
| "This spawn writes files, so it applies a decision — make it light." | Writing files is not the test; whether the decision is already made is. A spawn still working out what the content should be — a reviewer's per-finding severity and confidence, a delegate that must first find its own file set — is deciding, and decisions are session. A role missing from §Cost classes' list needs all four light conditions argued. |
| "Custom reviewer's `.geniro/instructions/review-extra/<slug>.md` doesn't declare `model:` — I'll default it to a light model at the spawn site." | An omitted `model:` means session (`inherit`). Custom reviewers follow the same default as built-ins. The user opts INTO a model only by explicitly writing `model: haiku` / `model: opus` in the reviewer's frontmatter — that is their declaration, and it overrides the class. |
| "The Agent tool doesn't accept `model='inherit'`, so I'll hardcode a model at this spawn site." | At a session site the fix is to OMIT `model=` entirely: the resolver picks up the orchestrator's model when the argument is unset, and a hardcoded fallback defeats that. A light site names its class, never a model, and the orchestrator spells the class for this host from §Runtime resolution — a Claude model name at the site fails on Codex and Cursor. |
| "User is on a small model; subagents on it will produce low-quality output for reasoning dimensions." | The user chose it and accepted the trade-off. Plugin paternalism ("I know better, bump to something larger") defeats the user's choice. If a reviewer on a small model misses bugs, surface it in the Phase 6 handoff summary ("findings count: 2 — note: session model is small; consider switching to a larger one for deeper review"), not by silent override. |
| "The run carries `--subagent-model opus`, so the test-runner and the code delegate go to Opus too — the flag says every spawn." | The flag buys reasoning depth, and neither of those spawns reasons. It pins session spawns and *caps* light ones (§`--subagent-model`): stronger never raises them, cheaper does lower them. A `--subagent-model haiku` run does drag them down with it. |
