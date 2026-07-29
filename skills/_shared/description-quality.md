# Description quality rules

The shared grading rubric for a user-authored `description:` field. `/geniro:instructions` applies it to `.geniro/instructions/review-extra/<slug>.md`; `/geniro:actions` applies it to `.geniro/actions/<slug>.md`. One home, so a severity change lands in both linters at once.

A `description:` is the routing surface: it is what the orchestrator matches a task against when deciding whether to load this reviewer or run this action. A description that reads well but describes the wrong thing produces a file that never fires — or fires on everything.

## The rules

| Rule | Severity |
|---|---|
| Describes intent rather than implementation | LOW |
| Mentions adjacent terms (e.g. for `sql-bindings`: "SQL", "ORM", "DAO") | LOW |
| Carries an explicit boundary clause ("Skip for …", "Not for …") | LOW |

All three are LOW: a description failing any of them still loads and still runs, so blocking on it would refuse a working file over a wording preference. They surface as suggestions in the linter's per-file output.

## What each rule catches

- **Intent over implementation.** "Flags raw string interpolation in `db.query()` calls" describes what the criteria happen to grep for today; "Reviews database access for injection-unsafe query construction" describes what it is *for*, and keeps matching after the criteria are rewritten.
- **Adjacent terms.** The match is semantic, so near-synonyms the user's task might use are what close the gap between a slug and a real request. A `sql-bindings` reviewer that never says "ORM" is invisible to a task phrased around the ORM layer.
- **Boundary clause.** Without one, the description reads as unbounded and the orchestrator loads the file on adjacent work it was never written for. Naming the excluded case is cheaper than the false fire.

## Length

The description cap belongs to whichever file defines the frontmatter it grades — `review-extra/<slug>.md` and an action file carry their own caps in their own field references. This rubric grades content, not length.
