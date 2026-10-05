# PR body

Single source for the description a skill writes when it opens a pull request. The caller maps its run records to these sections, so a reviewer who never saw the chat meets the same sections in the same order on every PR.

## Sections, in order

1. **Why + ticket (first line).** One or two sentences of motivation in product words, then the ticket reference. Previews (Slack, email) show the first characters, so the body never opens with a code fence or a heading.
2. **Summary.** Prose first. Add ONE visual from the menu below only when it clarifies the change beyond the prose. Mermaid renders on GitHub but not in every tracker or preview; prefer a text tree when the body is read elsewhere.
3. **Evidence.** Built only from what the run recorded:
   - the tests added, by name, each with the behavior it pins. Say a test failed before and passes now only when the run's records show it failing against the base code (a reproduction test authored before the fix); a test written against this run's own new code carries no before/after claim;
   - the acceptance results, each naming the criterion it covers when a ticket is linked;
   - the before/after screenshots when the run captured them. The `gh` CLI cannot upload images, so list their repo-relative paths as still to be attached, never as attached; the caller's closing report asks the user to attach them. With no UI change, say "no visual change";
   - for a debug handoff, the re-run result of the original bug scenario, or "not run — <reason>".
4. **Merge danger.** Name ONLY what cannot be undone or is hard to reverse, and what it affects: data migrations, destructive operations, backward-incompatible public API or contract changes, removed config or flags. When nothing qualifies, write "No irreversible changes identified." and add nothing else to the section — "safe", "low-risk", or "easy to roll back" would lower a reviewer's defect detection (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-brief.md` §Content contract).
5. **Known limitations.** Every accepted failure, accepted finding, unreviewed file, accepted assumption (decision, owner, working assumption), and visual issue shipped with a note. Omit the section when none exist.
6. **Review detail, collapsed.** A `<details>` block with the result per review dimension as counts ("bugs: 0 found", "tests: 1 found, 1 fixed, 0 deferred"), each dimension that did not run with its reason, and the pruned-tests record verbatim. Where the records hold no count, write "not recorded", never a reconstruction.

Every claim sits at the width its evidence supports (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`). Screen every number and behavioral claim against the run's recorded spec divergences (the spec claims the run disproved) before posting: a stale figure reads as authoritative in a public body, most of all under a sentence asserting that everything quoted was measured. Use the measured value or drop the claim. Fill or omit every section; an empty heading is what the PR-metadata review flags.

## Project template wins

Before composing, look for the repo's own template in GitHub's locations: the repo root, `docs/`, or `.github/`, as `pull_request_template.md` in any letter case or a `PULL_REQUEST_TEMPLATE/` directory. A single-file template is the default; use a directory's files only when no single file exists, picking the one matching the change, or asking. When one applies, keep its headings and order, put each section above under the closest heading, and give whatever has no home a short trailing heading. A heading with nothing to report gets a one-line "None" or "Not applicable", never an empty body; tick a checkbox only when the run's records show it is true. The first-line rule and Merge danger's wording still apply inside the template's headings.

A workflow file's `## PR description` section (`.geniro/workflow/*.md`, e.g. the Linear ticket line) is honored for whatever it prescribes, and the order above (or the project template's) stands where it is silent. A section left as an unfilled placeholder is ignored.

## Summary visual menu

Pick the smallest view that carries the point, beside the sentence it supports, keeping only the calls, files, states, and boundaries the reader needs.

| Show | Use when | Tiny example |
|---|---|---|
| Pseudocode | logic or an algorithm changed | `on(save)` / `if unchanged → return cached` / `write; return fresh` |
| Call tree | runtime control flow changed | `submitForm` → `createSession` → `persistPrompt`, `launchAgent` |
| Component tree | UI structure or state ownership changed | `<SessionPage>` → `<Toolbar>` → `<RunButton>` (`ui/run-button.tsx`) |
| Shallow file tree | responsibilities moved or a module was split | `src/` → `commands/  # parses actions`, `sessions/  # owns state` |
| Mermaid | components or data flow interact across boundaries | a `sequenceDiagram` of User, UI, Daemon |
| Diff-sketch | the surrounding shape exists and only a piece changed | the same tree with `+` / `-` lines on the nodes that changed |
