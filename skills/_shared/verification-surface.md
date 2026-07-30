# Verification Surface — what each project check covers, and what it does not

This file is the single source of truth for the optional `## Verification Surface` block in the instructions layer. Skills cite this file; do NOT inline-paste the entry shape.

A project runs several verification layers and they do not cover the same ground. A type check says nothing about behavior. A unit suite says nothing about the wiring between units. An integration suite may not touch the migration path at all, and some ground — a payment flow against a live sandbox, a visual regression — no automated layer covers.

Absent that mapping, a green suite reads as "verified" for claims no check ever touched. That is the unscoped-claim failure `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` §Forbidden phrases names: a claim wider than its Evidence Block outruns its own proof, and a reader cannot see which command ran. The block exists so a run can tell which check demonstrates a given criterion, and can word the result at the width that check actually earned.

## Contents

- Entry shape
- Where it lives
- How it is consumed
- What it is not
- Anti-rationalization

## Entry shape

One bullet per check. Three parts, all required:

```markdown
## Verification Surface

- `pnpm typecheck` — covers: type contracts across every package. Does not cover: runtime behavior, so a green run says nothing about whether a function returns the right value.
- `pnpm test:unit` — covers: logic inside a module, mocked at every boundary. Does not cover: the wiring between modules, or anything the mocks stand in for.
- `pnpm test:integration` — covers: HTTP contract of the public API against a real database. Does not cover: the migration path (migrations run before the suite starts), background jobs, or the payment provider.
- MANUAL — the payment flow against the provider sandbox. No automated layer covers it; a change touching `src/billing/**` is not verified by any command in this list.
```

The **does-not-cover** half is the load-bearing one. It is what a claim may not be widened to include, and it is the part a reader cannot derive from the command name. A bullet carrying only a command and a covers clause is half an entry: it tells a run what to execute and leaves it free to overstate the result.

A `MANUAL` entry is a first-class row rather than an omission. Ground no command covers is exactly the ground a run will silently claim; naming it is what makes the gap visible.

## Where it lives

Valid in `global.md` and any per-skill scope under `.geniro/instructions/`, alongside `## Rules`, `## Constraints`, `## Additional Steps` and `## Data Sources`. Authored by `/geniro:instructions` (the block-type detection table maps a request like "the unit suite doesn't cover X" here) and loaded by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`.

A per-skill file's entries narrow the global ones for that skill rather than replacing them. Where the two disagree about the same command, the per-skill entry wins — it was written closer to the work.

## How it is consumed

Two points, both about the same thing: not overstating a result.

1. **Choosing the check.** Where a run has to demonstrate a criterion — a spec's `verify:` line, a fix's acceptance, a claim in a ship report — the entry whose covers clause contains that ground is the one to run. When no entry covers it, that is the answer: nothing here verifies it, and the run says so rather than substituting the nearest green command.
2. **Wording the result.** The claim is stated at the width of the check that produced it, and the does-not-cover clause is the boundary. "The integration suite passes, which covers the API contract but not the migration path" is the shape. "Tests pass" is not, when this block says what tests do not reach.

Absent block, or a criterion no entry mentions: behavior is unchanged from having no declaration at all. This is a declaration a project opts into, never an inferred one — a guess about what a suite covers is worse than no mapping, because it reads as authoritative.

## What it is not

- **Not `## Constraints`.** A constraint is a gate the work must not cross. This is a description of what the existing checks observe.
- **Not `## Data Sources`.** Those are read-only sources for cross-checking a FACT about the world. This is about what the project's own checks prove.
- **Not a command registry.** The project's canonical test command already lives where the project documents its commands. This block adds coverage boundaries to commands, and exists only for the boundaries.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "The block lists no entry for this area, so there is nothing to check and the change is verified." | An absent entry means nothing here is known to cover that ground — the opposite of verified. Say which check ran and what it covers, and name the area as uncovered. An unlisted area silently absorbed into a green result is the exact failure this block exists to prevent. |
| "I'll fill in the covers / does-not-cover clauses myself from reading the test files." | The block is a declaration the project makes, not an inference a run produces. A guessed boundary reads as authoritative to every later consumer and is wrong in the direction that matters — a suite almost always covers less than its name suggests. Ask, or leave the entry out. |
| "A MANUAL entry has no command, so it is not really an entry — drop it." | It is the most load-bearing row in the block. Ground no command covers is the ground a run is most likely to claim by accident, and deleting the row does not make the gap smaller, only invisible. |
| "The does-not-cover clause is obvious from the command name, so it is filler." | It is the half a reader cannot derive. `test:integration` does not say whether migrations run inside it, whether the payment provider is stubbed, or whether background jobs fire — and each of those is a claim someone will make on the strength of a green run. |
