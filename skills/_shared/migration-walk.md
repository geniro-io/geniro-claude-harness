# MIGRATION.md walk — locate, parse, detect, classify, verify

Canonical procedure for consuming the plugin's maintainer-authored `MIGRATION.md` breaking-change log: find the file, parse its entries, run each entry's `Auto-detect:` command, decide whether the entry applies to THIS install, and re-verify an entry after a fix has been applied to it.

Consumers: `/geniro:update` Phase 4 (per-entry interactive walk) and `/geniro:setup` §3.0 (re-run migration sweep). Each consumer owns its own **apply policy** — what happens to an entry once this procedure has classified it as applicable — and states that policy in its own skill body. Everything up to and including the classification lives here; cite this file rather than inlining a second copy, so the two consumers cannot drift apart on the shell-safety rules in §4.

## Contents

- §1 Caller contract — invocation slots and what comes back
- §2 Locate the file
- §3 Parse — walk every entry, never gate on the version heading
- §4 Run the auto-detect — the `N/A` guard, bash, isolation
- §5 Classify — applicable or not
- §6 Verify after a fix
- §7 Anti-rationalization
- §8 Definition of Done

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

Run the helper, which walks every entry in file order (entries are independent, so order does not affect which fire):

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/migration-walk.sh"   # /geniro:update: "$PLUGIN_PATH/lib/migration-walk.sh"
migration_walk "$MIGRATION_FILE" "<project dir>"
```

It prints one `title<TAB>class<TAB>detail` row per entry. rc 66 means the file is present but malformed: skip the walk and have the caller report one warning line. A walk driven by a half-parsed structure runs some entries and silently drops the rest, which reads as "nothing to migrate" when the opposite is true.

## 4. Run the auto-detect — the `N/A` guard, bash, isolation

The helper owns the mechanics: an `Auto-detect:` value beginning with `N/A` (any case) is prose and never reaches a shell (its `;`/`&&` would execute trailing fragments as commands); every other value runs in its own `bash -c` child, regardless of the user's shell (an unmatched glob aborts under zsh's default `nomatch`), so one failing detect cannot cascade or touch the caller's shell. Detect commands are read-only by contract (`grep` / `find` / `ls` / `printf`-class), so the output is a report, not a mutation.

## 5. Classify — applicable or not

The detector output is the sole relevance signal:

| Helper class | What the caller does |
|---|---|
| `not-applicable` (empty output, or no `Auto-detect:` field) | Install already current — skip the entry, no question, no fix. |
| `informational` (`N/A` value) | Same as `not-applicable`; no detector ran. |
| `applies` (non-empty output; `detail` is the first line) | Hand the entry and its full detector output to the caller's apply policy. |
| `detector-error` | Report the detail line and continue — an unrunnable detector is not evidence the install is current. |

An applicable entry's `Auto-fix:` comes in one of two shapes, and the shape — not a prefix word — decides whether a shell may run it. A fenced `bash` block is a **command**. Anything else is a **description**: a `Manual-only —` or `Manual —` sentence, `N/A`, or plain prose such as "Remove the `"<id>"` string from `allow_patterns` …". Only a command ever reaches `bash -c`, because a description carries backticks and `;` that a shell would execute — the same hazard as an `N/A` detect (§4). What happens to a description is the consumer's apply policy.

## 6. Verify after a fix

Re-run `migration_walk` after a fix has been applied and read that entry's row (matched by title). Only a non-`applies` class confirms resolution: an auto-fix can apply partially, and reporting "fixed" without the re-detect leaves the user on a half-migrated install.

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
