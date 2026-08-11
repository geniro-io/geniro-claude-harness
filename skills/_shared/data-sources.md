# Data sources — cross-check load-bearing facts against project-declared sources

Single source of truth for the data-source verification primitive. Skills cite this file; do NOT inline-paste the procedure.

Applied by any skill phase that establishes a load-bearing fact, to cross-check it against project-declared data sources. The principle: confirm every load-bearing fact against the maximum set of known sources — never assume. A fact today often comes from one source (a single tracker fetch, or code-only). This primitive widens that to every source the user has declared as confirmable, marks a fact no source can confirm as explicitly unconfirmed, and surfaces conflicts. Read-only, fail-open, bounded to load-bearing facts.

## Contents

- §1 What it consumes — the `## Data Sources` block
- §2 The `## Data Sources` block schema
- §3 Procedure — DISCOVER → SCREEN → VERIFY
- §4 Read-only screening rule (the safety gate)
- §5 Per-fact outcome
- §6 Fail-open
- §7 Plain-English echo
- §8 Anti-rationalization
- §9 Pre-running a source into a verifier's evidence

---

## 1. What it consumes

The enabling primitive is a `## Data Sources` block authored by the user in custom instructions — `.geniro/instructions/global.md` and the per-skill `.geniro/instructions/<skill>.md`. The L4 loader (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`) reads the block and surfaces its entries to the orchestrator. This helper consumes those surfaced entries.

A declared source is the user's standing statement: "this is a place you may read to confirm facts." Built-in sources (the code itself, git history, open pull requests, the linked tracker) always apply on top of the declared ones — declared sources widen the set, they never replace the built-ins. This list is a floor: a consuming skill may declare its own additional domain built-ins on top of it.

When no `## Data Sources` block is present, there are no declared sources. Verification then falls back to the built-in sources only and never blocks — the absence is normal, not an error.

## 2. The `## Data Sources` block schema

Human-authorable. Each entry is a label + a `(confirms: <what kind of fact>)` hint + ONE source — a read-only shell command (backticked), an MCP tool name, or an action name.

```markdown
## Data Sources
<!-- Read-only sources to cross-check facts against. Never assume — if a source here can confirm a fact, use it. Commands are read-only — a source that can mutate is not a fact-check. -->
- **prod-db** (confirms: task / feature status) — `psql "$DATABASE_URL_RO" -c "SELECT ..."`
- **deploy-state** (confirms: did it ship?) — MCP tool `mcp__deploys__get_release_state`
- **logs** (confirms: production behavior) — action `query-logs`
```

- **Label** — a short name the echo can use ("your production database", "the deploy state").
- **`(confirms: ...)` hint** — what kind of fact this source can settle. Drives source selection in §3: pick a declared source when its hint matches the fact under test.
- **The source** — exactly one of: a backticked read-only shell command, an MCP tool name (`mcp__...`), or an action name (registered under `.geniro/actions/`).

## 3. Procedure — DISCOVER → SCREEN → VERIFY

### DISCOVER

Read the `## Data Sources` entries surfaced by the L4 loader. Parse each into `{label, confirms-hint, source}`. Absent or empty block → no declared sources; continue with the built-in sources (code / git / open PRs / tracker) only.

### SCREEN (safety — before any source runs)

Every declared source passes the read-only screen in §4 before it runs. A source that fails the screen is SKIPPED with a one-line caveat — never run, never blocking. The user authoring the source in their own instructions is the authorization to run it read-only (no extra confirmation gate) — but the read-only screen is non-negotiable, because a declared shell command can point at production.

### VERIFY (per load-bearing fact)

Bound the input to LOAD-BEARING facts — the facts a downstream decision, verdict, or report depends on — NOT every sentence. This matches the always-on-verification doctrine: always-on is not unbounded; cost scales to the fact set, not to prose.

For each load-bearing fact:

1. Pick the applicable sources — declared sources whose `confirms:` hint matches the fact (plus orchestrator judgment) PLUS the built-in sources (code / git / open PRs / tracker).
2. Run each applicable, screen-passing source read-only.
3. **Max-source rule** — do not stop at the first confirming source. Consult EVERY applicable source. Stopping early defeats the whole point: a second source is exactly where a conflict shows up. No recursion beyond the declared/applicable sources.
4. Compare results and assign a per-fact outcome (§5) — the outcome governs how the fact is presented downstream.

## 4. Read-only screening rule

This is the canonical home for the read-only doctrine that governs anything the plugin auto-runs from a declared source. The spec `verify:` acceptance command and the `/geniro:implement` side-effect screen apply the same doctrine, but it is defined HERE rather than imported from a skill's files. The screen is a high-signal mutation-verb check on the source, not a sandbox.

| Source kind | Run when | Skip with caveat when |
|---|---|---|
| Shell command (backticked) | SELECT-shaped / read-only query, health probe, read-only CLI (`get` / `list` / `describe` / `cat` / `grep`) | It carries any mutating verb — `INSERT` / `UPDATE` / `DELETE` / `DROP` / `ALTER` / `TRUNCATE` / `CREATE`; `git push` / `gh pr` / `git commit`; `deploy` / `release` / `publish`; `rm`; `>` / `>>` redirection; `tee`; in-place `sed -i`. Also skip when the command hides its real action so the verb check can't see it: command substitution (`$(...)` / backticks), a query read from an opaque source (`psql -f <file>` / `psql -c "$(...)"`), or a wrapped CLI whose verb you cannot screen (`<tool> sync` / `<tool> apply` / `<tool> deploy` — e.g. deploy CLIs `helm install` / `helm upgrade` / `kubectl apply` / `terraform apply` / `serverless deploy` / `vercel --prod` / `netlify deploy` / `fly deploy`). An un-screenable command is mutating-by-default, exactly as a non-SELECT-shaped SQL source is. |
| MCP tool | The tool is a read tool — `get` / `query` / `list` / `read` / `search` semantics | It mutates (create / update / delete / send / deploy). |
| Action | A low- or medium-risk action whose body is read-only | A high-risk action OR one whose body mutates external state. Read its `risk_class` and body before running. |

A skipped source emits the §7 caveat and the fact falls back to whatever sources DID pass — it never blocks.

## 5. Per-fact outcome

| Outcome | When | What the consumer does |
|---|---|---|
| **confirmed** | ≥1 applicable source agrees and NO source conflicts. | Use the fact normally; echo notes the agreeing-source count. |
| **conflicting** | Two applicable sources disagree on the fact. | Surface a plain-English notice; gate to the user where a decision hinges on it. Never silently pick one. |
| **unconfirmed** | Two distinct situations collapse to this outcome. **(a) No applicable source** — no declared hint matched the fact and no built-in source covers it either. **(b) An applicable source failed to return** — a source whose hint matched was selected and run, but produced nothing usable. | (a) Mark "unconfirmed" in the narrative/report — no caveat, this is the normal absence case. (b) Mark "unconfirmed", name the matched source by its label in the narrative, and route the fact to the consumer's missing-data gate where the consuming skill has one. Neither situation licenses presenting the fetched/assumed value as established fact — assuming it is the exact failure this primitive prevents. |

## 6. Fail-open

Fail-open bounds THIS HELPER — a source erroring, timing out, or unreachable never hard-blocks the helper's own fact resolution; the fact resolves from whatever sources DID return, with a caveat naming what failed. Routing an unconfirmed fact to the consumer's own missing-data gate (§5(b)) can still pause the run there — that pause is the consuming skill's own contract, not a hard block by this helper.

| Situation | Behavior |
|---|---|
| A declared source whose hint matched the fact produced no usable result (errored, timed out, or was otherwise unreachable) | Do not classify why. An MCP tool from a server that's connected but unauthorized is indistinguishable from one that was never registered, and common CLIs exit 0 while logged out — the user knows which it is, the run does not. Mark the fact unconfirmed (§5) and name the source by its label. |
| A source fails the read-only screen (§4) | Skipped with caveat; never run; continue. |
| No `## Data Sources` block at all | Built-in sources only; no caveat needed; never blocks. |

## 7. Plain-English echo

User-facing lines describe what was checked and what was learned — never internal identifiers (no "ran the prod-db data-source entry", no schema/field names). Use the source label, not its raw command.

Examples (verbatim):

```
Checked the related tickets against your production database — statuses match.
Your production database and the deploy state disagree on whether ENG-302 shipped — flagging this before I rely on it.
Couldn't confirm ENG-302's status from any declared source — treating it as unconfirmed.
Couldn't reach the deploy state, so ENG-302's status is unconfirmed — if it needs you to sign in, say so and I'll retry.
Skipped one declared source because its command would modify data, not just read it — only read-only sources are run.
```

## 8. Anti-rationalization

| Reasoning | Why it is wrong |
|---|---|
| "One source already says the status is X — skip the rest to save time." | The max-source rule is the point. A second source is exactly where a conflict surfaces; stopping at the first confirming source means a contradiction goes unseen. Consult every applicable source. |
| "The command looks safe — just run it without screening." | "Looks safe" is how a `DELETE` slips through. Every shell-command source passes the read-only screen (§4) before it runs; the screen is non-negotiable because a declared command can point at production. |
| "No source could confirm this fact, so I'll just use the value I fetched." | No-source-could-check is the unconfirmed outcome, not a confirm. Mark it "unconfirmed" and never present it as established fact — assuming the fetched value is the exact "never assume" failure this primitive exists to prevent. |
| "Two sources disagree — I'll pick the one that matches what I expected." | Silently resolving a conflict hides it. Surface the conflict in plain English and gate to the user where a decision depends on it; the user resolves it, not the orchestrator's expectation. |
| "Verifying every fact against every source is too expensive — sample a few." | The fact set is already bounded to load-bearing facts — the facts a downstream decision depends on — not every sentence. Within that bounded set, max-source consultation is the contract. Sampling reintroduces the miss. |
| "There's no `## Data Sources` block, so I'll error out — the user should declare sources." | Absence is the normal case. Fall back to the built-in sources (code / git / open PRs / tracker) and continue; declared sources widen the set, they are never required. |
| "The source errored — that's the same as no source applying, so mark it unconfirmed with no caveat." | A source whose hint matched the fact is a different situation from nothing applying at all (§5, §6): the user often has something to fix. Name the source by its label so the caveat is actionable; folding it into the plain "nothing applied" case erases the one signal the user could act on. |

## 9. Pre-running a source into a verifier's evidence

Some claims a consuming skill's own verifier evaluates assert state the cited code slice cannot settle. Before that verifier spawns, the orchestrator applies this helper: when a declared `## Data Sources` entry's `confirms:` hint matches the claim's domain, pre-run that source through the §4 read-only screen and inline the result into the SAME verifier's evidence, alongside the cited code slice — additional evidence to an EXISTING verifier, never a verifier per source, so spawn count never multiplies with the number of matching sources. Fail-open follows §6, including its split between a source that failed the read-only screen and one that matched but could not be reached — that distinction carries into the verifier's evidence, so the verifier sees which source was expected to settle the claim. Neither kind blocks the spawn. A claim with no matching declared source verifies against the cited code alone, unchanged.
