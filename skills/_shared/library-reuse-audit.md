# Library reuse audit (build-vs-buy)

Canonical procedure for "before hand-writing code, check whether a maintained EXTERNAL library already solves it." Defined ONCE here; referenced by `/geniro:plan` (approach design), `/geniro:implement` (candidate research + adoption gate), `/geniro:review` (reinvented-wheel finding), and `/geniro:refactor` (detection-only). This is the external-registry counterpart to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/existing-abstraction-audit.md`, which covers in-repo reuse.

The two are a funnel, never a parallel duplicate: Steps 1-4 fire only after an in-repo `NO-ANALOGUE` result, so a hand-written candidate is checked against the repo first, then the ecosystem.

## Contents

- Modes
- When to run / when to skip
- Step 0 — Language / stdlib capability check
- Step 1 — Detect the ecosystem
- Step 2 — Research candidates
- Step 3 — Filter funnel
- Step 4 — Evaluation rubric
- MODE: plan — fold into approaches
- MODE: implement — confirmation gate, then install
- MODE: review — finding shape
- Safety: package hallucination / slopsquatting
- Dedup boundary
- Anti-rationalization

## Modes

The caller passes one mode:

- **MODE: plan** — a no-spawn textual consideration during approach design: check the language/stdlib (Step 0) → surface "adopt an external library vs hand-write" as a trade-off in the relevant approach(es) and the spec's Approach / Steps prose, without researching or naming unverified packages. No candidate research, no registry calls, no gate. The user approving the approach IS the planning-time confirmation; candidate research and the binding install confirmation live in `/geniro:implement`.
- **MODE: implement** — full flow: check the language/stdlib → detect ecosystem → research candidates → filter → confirmation gate → on adopt, hand the dependency to Phase 2 for install and integration.
- **MODE: review** — detection only: flag hand-written code a maintained external library covers, as an advisory finding the user decides. No candidate research and no registry calls — the reviewer-agent carries no `WebSearch`/`WebFetch` grant, so `/geniro:review` reports the smell and `/geniro:implement` does the candidate research.

## When to run / when to skip

- **plan / implement** — run on each feature component (plan) or `NO-ANALOGUE` component the codebase-explorer reports (implement), when the effort tier is Small / Medium / Big. Skip Trivial: a one-liner never justifies a new dependency, and the supply-chain surface a dependency adds outweighs the saved lines. Skip Steps 1-4 silently when the project has no package manifest (Step 1 finds no ecosystem) — there is nothing to buy from; Step 0 needs no manifest and always runs.
- **review** — run when the diff hand-writes non-trivial functionality in a domain libraries commonly own: date/time math, crypto / auth / password hashing / tokens, parsing or serialization of untrusted input, retry-with-backoff, validation, HTTP clients, compression. Skip trivial snippets and code that is the project's own differentiating logic.

## Step 0 — Language / stdlib capability check

Runs in MODE: plan and MODE: implement only — MODE: review skips this step entirely. Before treating the need as a build-vs-buy question, check whether the language's standard library, a built-in capability, or a dependency-free pattern already covers it.

Resolve it in order, strongest first: the toolchain's own documentation command and the installed language distribution's bundled docs or type definitions — reachable via `Bash`/`Read` — before the official online documentation, skipped rather than guessed where no web reach exists. Availability is version-dependent; a recalled answer risks the same hallucination Safety guards against for packages.

When the stdlib, the capability, or the pattern covers the need, there is nothing to buy — end the audit here; Steps 1-4 do not run, and the MODE: implement confirmation gate never fires since no candidate exists to confirm. Fail open on an inconclusive check: proceed to Step 1 rather than blocking.

## Step 1 — Detect the ecosystem (language-agnostic)

Read the ecosystem from the project snapshot (`_project.md` / CLAUDE.md §Tech Stack) first; fall back to a `Glob` for manifest/lockfile presence. Detect by FILE presence, never by inference. A monorepo can carry several manifests — scope to the manifest nearest the code under audit.

| Ecosystem | Manifest / lockfile | Registry | Inspect command (read-only) | Adopt command |
|---|---|---|---|---|
| Node | `package.json` (+ `package-lock.json` / `yarn.lock` / `pnpm-lock.yaml` / `bun.lockb`) | npm | `npm view <pkg>` | `npm install <pkg>` (or `yarn`/`pnpm`/`bun add`) |
| Python | `pyproject.toml` / `requirements.txt` (+ `uv.lock` / `poetry.lock`) | PyPI | `pip index versions <pkg>` | `pip install <pkg>` (or `uv`/`poetry add`) |
| Rust | `Cargo.toml` (+ `Cargo.lock`) | crates.io | `cargo search <pkg>` | `cargo add <pkg>` |
| Go | `go.mod` (+ `go.sum`) | pkg.go.dev | `go list -m -versions <mod>` | `go get <mod>` |
| Ruby | `Gemfile` (+ `Gemfile.lock`) | RubyGems | `gem info -r <gem>` | `bundle add <gem>` |
| Java | `pom.xml` / `build.gradle*` | Maven Central | registry search | add to the manifest |

Never hardcode `npm`. The registry, the inspect command, and the adopt command all key off the detected ecosystem. A project with no row matched skips this audit.

## Step 2 — Research candidates (MODE: implement)

Spawn ONE web-research agent (`subagent_type: general-purpose`, OMIT `model=` — it inherits the orchestrator tier; it needs `WebSearch` + `WebFetch`, which the read-only codebase agents lack). Orchestrate the spawn at the top level — subagents cannot spawn sub-agents.

Prompt it to, for the one hand-written problem under audit:
- Search the detected registry and the web for several candidate libraries that solve it — return several ranked candidates, never just the first hit.
- For each candidate, gather the Step 4 signals and the canonical registry + repository URLs.
- Return a ranked shortlist of 2-3 with the signals and links. Research only — it never edits files or installs anything.

Fail open: if the spawn errors or the web is unreachable, write a one-line note, skip the suggestion, and let the run hand-write the component. A library suggestion is an optimization, never a blocker.

## Step 3 — Filter funnel

Run the shortlist through a fail-fast funnel before ranking:

**Stage 0 — Authenticity (do this FIRST; it is a security gate).** Confirm each candidate name resolves to a real entry on its registry via the Step 1 inspect command. Drop any name that does not resolve — the model proposing the name (including this orchestrator) is itself a known source of invented package names (see Safety). Flag any name one edit away from a far-more-popular package, or freshly-registered with near-zero downloads.

**Stage 1 — Hard disqualifiers (binary drop).** Remove a candidate with: an open HIGH/CRITICAL advisory and no fix; a license incompatible with the project (e.g. AGPL/GPL in a proprietary or SaaS codebase); abandonment (no release AND no commit in >18 months); or no usable docs. These are vetoes, not weights.

**Stage 2 — Rank survivors.** Order by, roughly, security posture and adoption (hardest to fake) > maintenance recency and cadence > fit, docs, and first-class language support > transitive-dependency footprint and size.

**Stage 3 — Keep the top 1-3** for the MODE: implement confirmation gate.

## Step 4 — Evaluation rubric

Gather these per candidate. Present them as evidence so the user decides with the facts in front of them.

| Signal | Why it matters | Red flag |
|---|---|---|
| Last release + last commit | Stale = unpatched issues | No release AND no commit in >12 months |
| Downloads + dependents | Battle-testing; dependents resist gaming better than stars | Very low relative to ecosystem peers |
| Open advisories (CVEs) | Direct security risk | Any open, unfixed HIGH/CRITICAL |
| License | Legal / distribution risk | GPL/AGPL in proprietary or SaaS code; missing license |
| Maintainer count / bus factor | One maintainer = fragile | Single dormant maintainer (weight it, don't auto-reject) |
| Transitive dependencies | Each is added attack + breakage surface | Bloated graph of low-quality transitives |
| Docs + types | Integration cost + correctness | No usage docs; missing typings where the ecosystem expects them |

Free, cross-ecosystem data sources: **deps.dev** (one call returns the dependency graph + OpenSSF Scorecard + advisories + license + dependents; covers npm/PyPI/crates/Maven/Go/NuGet), **OSV.dev** (advisories), the registry APIs (existence + timestamps), and **Socket** (typosquat + malware, npm/PyPI). Prefer registry-native and free-tier aggregators over any single vendor dashboard, which can change or sunset.

## MODE: plan — fold into approaches

Plan mode is a textual consideration, not a research pass — no spawn, no registry calls. For a component an approach would otherwise hand-write that looks like a solved problem an established library likely covers, present "adopt an external library vs hand-write" as part of the approach trade-offs — e.g. "Approach A: adopt an established CSV-parsing library; Approach B: hand-write it". A specific package may appear by name only when it is already in the project's manifest or the user named it; otherwise describe the capability generically — `/geniro:implement` does the candidate research (Step 2), the registry existence-verification (Step 3 Stage 0), and names the candidates. Carry the trade-off into the spec's Approach and Steps prose so `/geniro:implement` inherits it.

The user selecting the approach at the approach-approval gate is the planning-time confirmation; do NOT fire a separate adoption AskUserQuestion here, and never write an unverified package name into the spec. The binding install confirmation happens at `/geniro:implement`.

## MODE: implement — confirmation gate, then install

Adopting a dependency is a real decision the user owns — it adds supply-chain surface, a license obligation, and maintenance cost. It is never pre-authorized by the task invocation or the approved spec. Confirm before adopting ANY library.

When the spec names a library for this component (legitimate only when the name came from the project's manifest or the user named it during planning), existence-verify and health-check that named candidate (Step 3 Stage 0 + Step 4) before adoption — never adopt on the spec's word alone, since a library can be yanked or newly flagged between planning and implementation and the name itself must resolve on the registry. When the spec names none (the plan described the capability generically), run full discovery from Step 2.

Render the gate message-first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering and the visual language of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md`: a self-contained chat block FIRST (a one-sentence opener, a plain-English statement of what the code does and which library could replace it, and a candidate-comparison table whose rows carry the Step 4 signals and the registry + repository links as the evidence cite), THEN a lean `AskUserQuestion`.

Options:
- **Keep hand-written** — the default. Do NOT mark adoption `(Recommended)`: the model proposed the library, so the conservative path is pre-selected per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Recommended-label policy. Users systematically ratify a Recommended option, so auto-recommending a dependency adoption removes the choice.
- **Adopt `<library>`** (one option per surviving candidate) — replace the hand-written code with the library at Phase 2.
- **Explain further** — a reading aid that renders a deeper walkthrough; writes no decision.

Persist the pick to state.md `approvals[]` with `category: library_adoption`, `picked: <choice>`, `at: <ISO-8601 UTC>` via `atomic_state_write`, so a compaction-resume re-applies it without re-asking. When the user declines (keeps hand-written, or picks a non-recommended path), emit `user_rejected_suggestion` to past learnings via `emit_rejection_if_signal()` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-rejection.md`.

Skip the gate silently when no candidate survives Step 3 — ask nothing when there is nothing to adopt.

On an Adopt pick, hand the dependency to Phase 2 as a TodoWrite item: add it through the package manager (the Step 1 adopt command, run via Bash), NOT by editing a lockfile — lockfile writes are blocked by the file-protection hook, and a package manager regenerates the lockfile correctly. Pass `--ignore-scripts` (or the ecosystem equivalent) when the package declares install scripts, then integrate the library in place of the hand-written component. An adopted library reshapes the Phase 2 todo list — install plus wire-up replaces implement-from-scratch.

## MODE: review — finding shape

Emit a finding in the reviewer-agent output format (`${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output Format). Tag it `[PRODUCT-DECISION]` — adopting a library is the user's call, so the finding surfaces for them to decide regardless of severity (the decision-type axis, not severity, carries it to the user). Severity per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md`: MEDIUM is typical; HIGH only when the hand-written code carries real correctness or security risk a battle-tested library would remove (hand-rolled crypto, auth, timezone math, HTML sanitization — the "never roll your own" domains); never CRITICAL (the architecture dimension signals design risk, not immediate breakage; a runtime defect in the hand-rolled code is owned by the bugs / security dimension). Carry an `Options:` block (adopt a library / keep hand-written / extract an in-repo helper). Cite the hand-written `file:line` and name the library category that covers it; the heavy candidate research happens in `/geniro:implement`, so the review finding points the direction rather than enumerating vetted packages.

## Safety: package hallucination / slopsquatting

The existence check in Step 3 Stage 0 is mandatory, not optional polish. Language models — including the orchestrator running this audit — invent plausible package names that do not exist, and the same fake names recur predictably across runs, so attackers pre-register them with malware ("slopsquatting"). Never adopt a package an AI assistant suggested without verifying it independently: never present an unverified name as adoptable or write it into a spec; gate on registry maturity (publish age plus downloads) to catch a freshly-registered squat; flag near-name look-alikes of popular packages; and never auto-install — the confirmation gate is the human checkpoint an existence miss cannot bypass.

## Dedup boundary

| | existing-abstraction-audit.md | this audit's Step 0 | this audit's Steps 1-4 | repo-tooling-first.md |
|---|---|---|---|---|
| Scope | in-repo reuse | language / stdlib reuse | external-registry reuse | repo-tooling reuse |
| Looks at | `utils/ lib/ shared/` via the project's code search | the installed toolchain's own docs first, official docs second — version-pinned to the project's toolchain | npm / PyPI / crates / Maven / Go / RubyGems | the repo's own scaffolders, generators, and CLIs |
| Fires | any reuse smell | before Steps 1-4, on any hand-write candidate (MODE: plan/implement only) | only after Step 0 finds no coverage and an in-repo `NO-ANALOGUE` result | before hand-writing an artifact a scaffolder already generates |
| Outcome | reuse-as-is / extend-existing / no-analogue | covered (audit ends here) / not covered (continue to Step 1) | adopt-library / keep-hand-written | generate-through-tooling / hand-written fallback |

## Anti-rationalization

| Reasoning | Why it's wrong |
|---|---|
| "I know this package exists — skip the registry check." | The model is itself the hallucination source; about 1 in 20 frontier suggestions is a name that does not exist and may be a registered malware squat. The inspect command takes a second and is the security floor. |
| "The library is obviously better — mark Adopt as Recommended." | Adopting a dependency is the user's decision; it adds supply-chain, license, and maintenance surface. Keep-hand-written stays the default — users ratify Recommended options, so auto-recommending an adoption removes the choice. |
| "Search npm for the package." | Only when the project IS a Node project. Detect the ecosystem first; a Python / Rust / Go repo needs PyPI / crates / pkg.go.dev. An npm-only step is a bug. |
| "Auto-install the adopted library to save a step." | Never auto-install. Install runs at Phase 2 through the package manager after the user confirms; the lockfile-write hook blocks editor writes, and an unconfirmed install is exactly the slopsquatting delivery vector. |
| "The spec already names this library — adopt it without re-checking." | A spec-named library (from the manifest or the user) still goes stale — yanked or newly flagged between planning and implementation — and the name itself must resolve on the registry. Re-verify existence and health at the gate, then confirm. |
| "Web is down — block the run until research succeeds." | Fail open. A library suggestion is an optimization; a registry timeout must never stop the work. Note it and hand-write the component. |
| "Suggest a library for this 3-line helper." | A trivial, stable snippet does not justify a dependency's transitive and supply-chain cost. Skip Trivial scope and one-off snippets. |
