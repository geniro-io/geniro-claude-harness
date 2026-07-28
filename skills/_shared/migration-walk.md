# MIGRATION.md walk — locate, parse, detect, classify, verify

Canonical procedure for consuming the plugin's maintainer-authored `MIGRATION.md` breaking-change log: find the file, parse its entries, run each entry's `Auto-detect:` command, decide whether the entry applies to THIS install, and re-verify an entry after a fix has been applied to it.

Consumers: `/geniro:update` Phase 4 (per-entry interactive walk) and `/geniro:setup` §3.0 (re-run migration sweep). Each consumer owns its own **apply policy** — what happens to an entry once this procedure has classified it as applicable — and states that policy in its own skill body. Everything up to and including the classification lives here; cite this file rather than inlining a second copy, so the two consumers cannot drift apart on the shell-safety rules in §4.

## 1. Caller contract

| Slot | Meaning |
|---|---|
| `MIGRATION_FILE` | Absolute path to the `MIGRATION.md` this run walks. `/geniro:update` walks the copy it just installed; `/geniro:setup` walks the copy in the currently-loaded plugin root. |

The caller runs §2-§5 for every entry, hands each applicable entry to its own apply policy, and runs §6 for every entry a fix actually ran for.

This procedure emits no user-facing text of its own. Where a section below says a line is emitted, the caller emits it, on whichever surface it already uses — a chat report, a `## Phase log` line, an `## Open Questions` line. Four outcomes need reporting, and a caller that silently swallows any of them turns a failed migration into an apparent success:

| Outcome | Section |
|---|---|
| `MIGRATION_FILE` absent — nothing to walk | §2 |
| `MIGRATION_FILE` present but unparseable — walk skipped | §3 |
| Entry classified as not affected | §5 |
| Entry still affected after its fix ran | §6 |

## 2. Locate the file

Read `MIGRATION_FILE`. When it does not exist, there are no breaking changes to walk — the caller reports one notice line and skips the walk entirely. A fresh install has nothing to migrate.

## 3. Parse — walk every entry, never gate on the version heading

Collect **every** `### <name>` entry across **all** `## v<X.Y.Z>` sections, per the consumption contract in MIGRATION.md's preamble. The version heading groups entries into feature cohorts for readability; it is not a selection gate. The `## vX.Y.Z` axis tracks plugin features, not the package's semver, so a feature can already be live in this install even when its heading version sits outside the installed package's version range — gating on the heading would silently skip it. Each entry's read-only `Auto-detect:` command, not its heading, decides relevance.

The file follows this schema — each release is `## v<X.Y.Z>`, each change is `### <name>` with `Action required:`, `Auto-detect:`, `Auto-fix:`, and `Severity:` fields.

Process entries in file order (newest cohort first — entries are independent, so order does not affect which fire).

When the file is present but malformed (the heading structure cannot be parsed), skip the walk and have the caller report one warning line. A walk driven by a half-parsed structure runs some entries and silently drops the rest, which reads as "nothing to migrate" when the opposite is true.

## 4. Run the auto-detect — the `N/A` guard, bash, isolation

For each entry, in this order:

1. **No `Auto-detect:` field** → the entry carries no relevance signal. Treat it as not applicable (§5) and continue.
2. **Value begins with `N/A`** (matched case-insensitively) → an informational entry with no runnable detector. Skip execution and treat the entry as not applicable (§5). Never pass an `N/A — ...` value to `bash -c`: the prose carries `;`/`&&` that would execute its trailing fragments as commands.
3. **Otherwise** → run the value via `bash -c '<command>'` and capture its output. Run under bash regardless of the user's interactive shell: an unmatched glob stays literal under bash but aborts the command under zsh's default `nomatch`, which would halt the walk mid-way.

Run each entry's command in isolation so one failing detect cannot cascade into the rest.

Detect commands are read-only by contract (`grep` / `find` / `ls` / `printf`-class), so running one changes nothing on the install — the output is a report, not a mutation.

## 5. Classify — applicable or not

The captured output is the sole relevance signal:

| Result | Classification | What the caller does |
|---|---|---|
| Output empty | **Not affected** — this install is already current for that entry | Skip the entry and continue — no question, no fix. |
| Output non-empty | **Applicable** — this install is affected | Hand the entry and its captured output to the caller's apply policy. |
| `N/A` value, or no `Auto-detect:` field (§4 steps 1-2) | **Not affected** — no detector ran | Same as empty output. |

## 6. Verify after a fix

Re-run the entry's `Auto-detect:` — exactly as in §4 — after a fix has been applied to it. Only an empty result confirms resolution: an auto-fix can apply partially, and reporting "fixed" without the re-detect leaves the user on a half-migrated install.

Re-detect **only** the entries a fix actually ran for. Entries that were skipped, deferred, or printed as manual instructions are intentionally still affected, so re-detecting them reports a failure that never happened and logs the same entry twice.

An entry still affected after its fix is recorded by the caller (each consumer names the destination in its own apply policy) and the walk continues — one unresolved entry does not stop the remaining ones.

## 7. Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "This `Auto-detect:` value starts with `N/A` but the rest reads like a harmless note — running it costs nothing." | The value is prose, and `bash -c` executes prose. A `;`, `&&`, or backtick inside the sentence turns its trailing fragment into a command that runs on the user's machine. Match `N/A` case-insensitively at the start of the value and skip execution entirely. |
| "This install is several versions past most of these headings — range-filter the older cohorts away." | The heading tracks plugin features, not package semver (§3), so an entry under a heading outside the installed range can still be live here. Walk every entry and let its detect decide. |
| "One entry's detect exited non-zero, so the file is unusable — stop the walk." | A failing detect describes that one entry, not the file. Each command runs in isolation (§4); log the failure and continue with the remaining entries. |
| "The user's interactive shell is zsh, so run the detect the way their shell would." | An unmatched glob aborts under zsh's default `nomatch` and halts the walk mid-way. Every detect runs under `bash -c` for that reason, independent of the user's shell. |
| "The fix command exited 0 — that is the verification." | Exit 0 says the command ran, not that the condition is gone. Only an empty re-detect (§6) confirms the entry is resolved. |

## 8. Definition of Done

- [ ] Every `### <name>` entry across every `## v<X.Y.Z>` section was considered — no version-range filtering
- [ ] No `Auto-detect:` value beginning with `N/A` reached a shell
- [ ] Every runnable detect ran via `bash -c`, in isolation from the other entries
- [ ] Applicable / not-affected came from detect output alone, never from the entry's heading or wording
- [ ] Every entry a fix ran for was re-detected; entries that were skipped, deferred, or left to manual action were not
