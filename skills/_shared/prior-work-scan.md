# Prior-work scan — check for an existing PR or ticket before investing

Single source of truth for the pre-investment "does this already exist" probe. `/geniro:debug` cites this file for the open-PR check it previously specified inline (`${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §8 stays debug's phase-anchor and mode gate; the probe mechanics live here). Any skill about to invest real effort — forming a hypothesis, designing an approach, selecting a refactor scope — against an already-named target cites this file the same way, rather than growing its own copy. Do not inline-paste the procedure.

## Contents

- §1 When it runs
- §2 The two probes — open pull requests, open tickets
- §3 Bounds
- §4 On a hit
- §5 Unreachable handling
- §6 Anti-rationalization

---

## 1. When it runs

The scan fires once a caller has an **already-named target** — a symptom plus suspect files, a feature or refactor scope, a bug description — and is about to spend the expensive step on it: forming hypotheses, generating approaches, or committing to a scope. It runs before that step, never after, so a hit can still change what the caller does next.

This is a context probe, not target discovery. It sits inside the carve-out `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` §Forbidden discovery moves draws around `gh pr list`: read-only calls that gather context for an **already-named** target are not the forbidden target-invention move. A caller with no named target — nothing to check the probe against — never reaches this helper; supplying one is the caller's job, not this helper's.

Phase position is caller-specific but lands at the same relative point in each: after the target is named, before the phase that reasons expensively about it. `/geniro:debug` Scientific Mode places it between Observe & repro and Hypothesize, and `/geniro:refactor` between scope discovery and tier classification — both have a file set by then. A planning caller places it between research synthesis and approach generation, where no file set exists yet and keywords are all there is; §4 treats that as the normal case, not a degraded one.

## 2. The two probes

Both probes are read-only. Neither ever opens, comments on, edits, or creates a PR or ticket.

### Open pull requests

Checks whether an open PR already touches the target, so the caller doesn't duplicate work already in flight.

- **Queried:** the repo's own forge, through whatever tooling the repo already uses to talk to it (`gh` for a GitHub remote; the equivalent CLI for another forge). One call carries the whole candidate set including changed-files, so no per-PR round trip is needed — e.g. `gh pr list --state open --json number,title,headRefName,author,updatedAt,url,files --limit 30`, optionally pre-narrowed with `--search` on the target's top keywords.
- **Relevance:** `file_overlap` — how many of the target's suspect/touched files the PR's `files` field also lists — plus `keyword_match` — the PR title contains a distinctive target token, the error string, or the PR surfaced through the `--search` pre-narrow (a server-side title+body match). Sum to `total_score`.

### Open tickets

A bounded keyword search for OTHER open tracker tickets describing the same bug or feature — nobody has named this ticket yet, which is what makes it a search rather than a fetch. Two things it is easy to conflate this with: the linked-ticket fetch, where a ticket the user or spec already names is read directly by its own ID rather than searched for; and the related-task chain (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/task-chain-context.md`), which walks the ALREADY-KNOWN parent and siblings of a named ticket at a hard depth-1 cost bound (§8 there rejects widening it, and §9's first row makes the same refusal explicit for a reason worth respecting here too). This probe is a separate, independently-bounded search: it runs even when no ticket is named at all, and it finds candidates by keyword rather than by walking a chain.

- **Queried:** whatever tracker the project has configured, driven by `.geniro/workflow/<kind>.md` exactly as `${CLAUDE_PLUGIN_ROOT}/skills/_shared/task-chain-context.md` §3 already does for the chain — read its `## Searching for issues` section for the project's search tool, query shape, and how an open issue is expressed, rather than hardcoding a tracker API. No workflow file for any kind, or one whose `## Searching for issues` section is still an unfilled placeholder → the project declares no search capability, and the ticket probe reports nothing to query. That is the normal-absence case of §5, not an unreachable source.
- **Relevance:** keyword overlap between the target's distinctive terms (symptom, error string, feature name) and each candidate's title. A generic word matching alone is not overlap — the terms have to distinguish the target from an unrelated ticket.

## 3. Bounds

Each bound exists to keep the scan a priming check, not a research phase — the goal it serves is named next to it.

- **One call per probe.** The PR probe's single `gh pr list --json ...` call already carries the whole candidate set; the ticket probe issues one query against the configured tracker. A second round-trip per candidate is exactly the cost `${CLAUDE_PLUGIN_ROOT}/skills/_shared/task-chain-context.md` §8 refuses for the related-task chain, for the same reason — depth-1 keeps the fetch to a fixed, small number of calls regardless of how many candidates exist.
- **Result cap: top-5 per probe**, ties broken by recency. A candidate list beyond a handful stops being something the caller can read before deciding whether to act on it — the cap is what keeps a hit reviewable rather than another wall of text.
- **Content-read cap.** When §4's hit gate picks "read the candidate's content first," bound that read too: a PR diff to roughly its changed lines (~150 lines) — enough to judge whether it resolves the target, not the surrounding discussion or commit history; a ticket to its main description, not its comment thread — a ticket has no line-count analogue to a diff, so the description body is the natural stopping point. Reading past either turns the priming check into its own research phase, exactly what this section exists to prevent.
- **Drop rule: zero-signal candidates are dropped, not just deprioritized.** A PR with no file overlap and no keyword match, or a ticket with no keyword overlap, existing in the raw result set is not evidence of prior work. Surfacing it anyway would turn every scan into noise the caller reads past, which is how a real hit two runs later gets ignored along with it.

## 4. On a hit

Generalizes the strong-match gate `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §8 already runs for the PR probe so every caller can use the same shape — including the three that reach this section with keywords only, no file set yet.

- **Strong match** scales to what the caller supplied. Ticket probe: always keyword-only, since no ticket carries a file list — keyword overlap on terms that actually distinguish the target, not a generic word. PR probe: `file_overlap >= 1` AND `keyword_match >= 1` when the caller has a file set (debug's `suspect_files`, the only caller with one at this point); the same distinguishing-term bar as the ticket probe when the caller has keywords only (plan, implement, refactor call before any files are chosen — the normal case there, not a degraded one). Fire the gate per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md`: name the candidate and why it matched, then offer caller-appropriate options — read the candidate's content first (PR diff, ticket description; bounded per §3); use it as a starting point (a hypothesis, an approach seed, a scope input); or ignore it and continue. Persist the pick to the caller's own state file `approvals[]`, under a category naming the probe (debug's existing `existing_fix_pr` category is the model), so a resumed run does not re-ask.
- **Weak match** — overlap without a keyword, or a keyword without overlap. Surface as plain-text priming context, no gate: name the candidates and what overlapped, and let the caller's next step read it before committing.
- **Zero matches.** Stay silent. A clean run must not pay a notification cost — nothing to surface means nothing said.

## 5. Unreachable handling

Inherit `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md` §6 fail-open for what happens when a probe's source can't be reached — no forge remote, an unauthenticated or missing CLI, no `.geniro/workflow/<kind>.md` configured, or the tracker's MCP tool unregistered or timing out. None of these hard-block; the caller's other work continues either way.

The one thing to state here: an unreachable probe names the source it couldn't check and leaves the question open — it does NOT get folded into "no prior work found." A probe that ran and found nothing (§4's zero-matches) and a probe that never ran are different answers to different questions, and reporting the second as the first tells the caller a check happened when it didn't — the exact gap a teammate's in-flight PR or an already-filed ticket falls straight through.

## 6. Anti-rationalization

| Reasoning | Why it is wrong |
|---|---|
| "The related-task chain already walked this ticket's neighbors — skip the ticket probe." | The chain walks a NAMED ticket's already-known parent and siblings at a fixed depth; this probe searches by keyword for tickets nobody has named, and runs even when no ticket exists yet. They answer different questions. |
| "The PR search timed out — I'll just say no existing PR was found and move on." | An unreachable probe is not a clean result (§5). Name the source that couldn't be checked and leave the question open; reporting it as "found nothing" is a claim the probe never actually verified. |
| "No target is named yet, but a quick `gh pr list` would help me find one to work on." | This is target-invention, the exact move `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` forbids. The probe checks an already-named target; it does not supply one. |
| "This is a small fix — running the scan isn't worth it." | The scan is already bounded to one call per probe (§3); its cost doesn't grow with the target's size. A small fix duplicating a teammate's in-flight PR is exactly as wasteful as a large one. |
| "One candidate has a matching keyword — close enough, fire the gate." | The strong/weak split exists so the gate fires only when it's worth the caller's attention. Gating on every partial match trains the user to dismiss the gate, which buries the strong match that actually mattered. |
