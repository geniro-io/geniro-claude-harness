# Data sources — cross-check load-bearing facts against project-declared sources

Single source of truth for the data-source verification primitive. Skills cite this file; do NOT inline-paste the procedure.

Applied by `/geniro:plan` and `/geniro:implement` Phase 1 verification to cross-check load-bearing facts against project-declared data sources. The principle: confirm every load-bearing fact against the maximum set of known sources — never assume. A fact today often comes from one source (a single tracker fetch, or code-only). This primitive widens that to every source the user has declared as confirmable, marks a fact no source can confirm as explicitly unconfirmed, and surfaces conflicts. Read-only, fail-open, bounded to load-bearing facts.

## Contents

- §1 What it consumes — the `## Data Sources` block
- §2 The `## Data Sources` block schema
- §3 Procedure — DISCOVER → SCREEN → VERIFY → SURFACE
- §4 Read-only screening rule (the safety gate)
- §5 Per-fact outcome
- §6 Fail-open
- §7 Plain-English echo
- §8 Anti-rationalization

---

## 1. What it consumes

The enabling primitive is a `## Data Sources` block authored by the user in custom instructions — `.geniro/instructions/global.md` and the per-skill `.geniro/instructions/<skill>.md`. The L4 loader (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`) reads the block and surfaces its entries to the orchestrator. This helper consumes those surfaced entries.

A declared source is the user's standing statement: "this is a place you may read to confirm facts." Built-in sources (the code itself, git history, the linked tracker) always apply on top of the declared ones — declared sources widen the set, they never replace the built-ins.

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

## 3. Procedure — DISCOVER → SCREEN → VERIFY → SURFACE

### DISCOVER

Read the `## Data Sources` entries surfaced by the L4 loader. Parse each into `{label, confirms-hint, source}`. Absent or empty block → no declared sources; continue with the built-in sources (code / git / tracker) only.

### SCREEN (safety — before any source runs)

Every declared source passes the read-only screen in §4 before it runs. A source that fails the screen is SKIPPED with a one-line caveat — never run, never blocking. The user authoring the source in their own instructions is the authorization to run it read-only (no extra confirmation gate) — but the read-only screen is non-negotiable, because a declared shell command can point at production.

### VERIFY (per load-bearing fact)

Bound the input to LOAD-BEARING facts — the related-task chain statuses (parent epic + sibling sub-tasks + milestone states) and the spec's cited claims — NOT every sentence. This matches the always-on-verification doctrine: always-on is not unbounded; cost scales to the fact set, not to prose.

For each load-bearing fact:

1. Pick the applicable sources — declared sources whose `confirms:` hint matches the fact (plus orchestrator judgment) PLUS the built-in sources (code / git / tracker).
2. Run each applicable, screen-passing source read-only.
3. **Max-source rule** — do not stop at the first confirming source. Consult EVERY applicable source. Stopping early defeats the whole point: a second source is exactly where a conflict shows up. No recursion beyond the declared/applicable sources.
4. Compare results and assign a per-fact outcome (§5).

### SURFACE

- Conflicting fact → a plain-English notice; where a decision hinges on it, a gate to the user.
- Unconfirmed load-bearing fact → marked "unconfirmed" in the consumer's narrative/report. Never present an unconfirmed value as established fact.
- Confirmed fact → used as normal; the echo notes how many sources agreed.

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
| **unconfirmed** | No applicable source could check the fact (none had a matching hint, or all that did were skipped/errored). | Mark "unconfirmed" in the narrative/report — never present the fetched/assumed value as established fact, since assuming it is the exact failure this primitive prevents. |

## 6. Fail-open

A source erroring or timing out never hard-blocks. It emits a one-line caveat and the fact resolves from whatever sources DID return.

| Situation | Behavior |
|---|---|
| A declared source command errors / times out | One-line caveat; drop that source for this fact; continue with the rest. |
| An MCP tool is unregistered / unavailable | Treat as a source that couldn't run; caveat; continue. |
| A source fails the read-only screen (§4) | Skipped with caveat; never run; continue. |
| No source could confirm a load-bearing fact | Mark the fact "unconfirmed" (§5) — fail-open never means assume-true. |
| No `## Data Sources` block at all | Built-in sources only; no caveat needed; never blocks. |

## 7. Plain-English echo

User-facing lines describe what was checked and what was learned — never internal identifiers (no "ran the prod-db data-source entry", no schema/field names). Use the source label, not its raw command.

Examples (verbatim):

```
Checked the related tickets against your production database — statuses match.
Your production database and the deploy state disagree on whether ENG-302 shipped — flagging this before I rely on it.
Couldn't confirm ENG-302's status from any declared source — treating it as unconfirmed.
Skipped one declared source because its command would modify data, not just read it — only read-only sources are run.
```

## 8. Anti-rationalization

| Reasoning | Why it is wrong |
|---|---|
| "One source already says the status is X — skip the rest to save time." | The max-source rule is the point. A second source is exactly where a conflict surfaces; stopping at the first confirming source means a contradiction goes unseen. Consult every applicable source. |
| "The command looks safe — just run it without screening." | "Looks safe" is how a `DELETE` slips through. Every shell-command source passes the read-only screen (§4) before it runs; the screen is non-negotiable because a declared command can point at production. |
| "No source could confirm this fact, so I'll just use the value I fetched." | No-source-could-check is the unconfirmed outcome, not a confirm. Mark it "unconfirmed" and never present it as established fact — assuming the fetched value is the exact "never assume" failure this primitive exists to prevent. |
| "Two sources disagree — I'll pick the one that matches what I expected." | Silently resolving a conflict hides it. Surface the conflict in plain English and gate to the user where a decision depends on it; the user resolves it, not the orchestrator's expectation. |
| "Verifying every fact against every source is too expensive — sample a few." | The fact set is already bounded to load-bearing facts (chain statuses + the spec's cited claims), not every sentence. Within that bounded set, max-source consultation is the contract. Sampling reintroduces the miss. |
| "There's no `## Data Sources` block, so I'll error out — the user should declare sources." | Absence is the normal case. Fall back to the built-in sources (code / git / tracker) and continue; declared sources widen the set, they are never required. |
