---
tier: T1.5
producer: plan
schema-version: 1
branch: fix-regexp-csv-comma-mangling
timestamp: 2026-08-10T07:10:43Z
geniro_kind: design-doc
geniro_schema_version: m5-v2
task_slug: regexp-csv-comma-mangling
topic: "Let a regular expression containing a comma survive pylint's comma-separated regex options"
mode: DESIGN_DOC
effort_tier: small
lifecycle: draft
budget:
  max_files_to_edit: 12
  max_lines_changed: 400
  time_budget: "1d"
checkpoints:
  - step_anchor: step-4
    name: "Quote-aware splitter unit-tested in isolation"
  - step_anchor: step-10
    name: "Config, self and functional suites green"
forbidden_actions:
  - "do NOT change `_splitstrip` itself — `load-plugins` parsing depends on its current semantics"
  - "do NOT implement splitting by tracking regex bracket/brace nesting depth — that is a second regex parser to maintain and it silently reinterprets existing configs"
  - "do NOT hand-edit doc/user_guide/configuration/all-options.rst — it is generated at doc build"
approval_required_for:
  - step-1
tools_required: ["python3", "pytest", "pre-commit", "git"]
---

<!-- geniro:design-doc -->

# Comma-safe parsing for pylint's comma-separated regular-expression options

## 1. Objective

Give pylint's comma-separated regular-expression options RFC-4180 double-quote semantics so that a regex containing a comma can be expressed without being split mid-pattern.

## 2. Scope — Included

- `pylint/utils/utils.py:212-253` — add a quote-aware CSV splitter beside `_splitstrip`, and route `_check_csv` through it.
- `pylint/utils/__init__.py:12-35` — re-export the new helper alongside `_check_csv` and `_splitstrip`.
- `pylint/config/utils.py:134-142` — `_parse_rich_type_value` re-quotes list elements that contain a comma or a double quote, so a TOML array of regexes survives its flattening to a string.
- Behavior of the five options that route through the shared splitter: `good-names-rgxs` (`pylint/checkers/base/name_checker/checker.py:209-215`), `bad-names-rgxs` (`pylint/checkers/base/name_checker/checker.py:229-235`), `ignore-patterns` (`pylint/lint/base_options.py:53-62`), `exclude-too-few-public-methods` (`pylint/checkers/design_analysis.py:392-399`), `ignore-paths` (`pylint/lint/base_options.py:63-73`).
- Tests: `tests/utils/unittest_utils.py`, `tests/config/test_config.py`, a new fixture under `tests/config/functional/toml/`.
- Docs: a "Comma-separated options" section in `doc/user_guide/configuration/index.rst:18-26`, and a towncrier fragment under `doc/whatsnew/fragments/`.

## 3. Scope — Excluded

- **The option help strings** at `pylint/checkers/base/name_checker/checker.py:213`, `pylint/lint/base_options.py:58`, and the other three sites. Editing them regenerates `doc/user_guide/configuration/all-options.rst` (written by `doc/exts/pylint_options.py:157`), which is a tracked file — a large mechanical diff for a rule better stated once in the user guide. Revisit only if reviewers ask for per-option discoverability.
- **`_splitstrip` itself** (`pylint/utils/utils.py:212`). It also parses `load-plugins` (`pylint/config/utils.py:170`, `pylint/config/config_initialization.py:61`), where a module path never contains a comma and quoting buys nothing. Leaving it untouched bounds the blast radius to config values that flow through `_check_csv`.
- **Wrapping `_regexp_paths_csv_transfomer`'s inline `re.compile` in the friendly error path.** `pylint/config/argument.py:126-132` compiles directly instead of delegating to `_regex_transformer` (`pylint/config/argument.py:105-111`), so a bad `ignore-paths` regex still surfaces a raw `re.error` traceback rather than an `argparse.ArgumentTypeError`. Real defect, orthogonal cause, separate change.
- **The double compilation at `pylint/checkers/base/name_checker/checker.py:293-298`**, which re-runs `re.compile` over values the transformer already compiled. Harmless (`re.compile` on a `Pattern` returns it unchanged) and unrelated to splitting.

## 4. Assumptions

- `_regexp_csv_transfomer` splits before it compiles: it calls `_csv_transformer(value)` and compiles each resulting fragment (`pylint/config/argument.py:114-119`). That ordering is the crash in the report — `(foo{1,3})` becomes `(foo{1` and `3})`, and the first fails to compile.
- The split has no escape mechanism today. `_csv_transformer` (`pylint/config/argument.py:51-53`) delegates to `_check_csv` (`pylint/utils/utils.py:250-253`), which for a string delegates to `_splitstrip` (`pylint/utils/utils.py:212-232`) — a bare `string.split(",")` with strip-and-drop-empties, no quoting, no escaping.
- Type transformers only ever receive a string from real config paths: the `_TYPE_TRANSFORMERS` docstring states they are called for command line, configuration files, and a string default value, and that non-string defaults are assumed already correct (`pylint/config/argument.py:152-158`). The list/tuple branch of `_check_csv` (`pylint/utils/utils.py:251-252`) is a defensive passthrough guarding the re-validation crash covered by `tests/test_self.py:1122-1134`, and must survive.
- An ini/`pylintrc` value keeps its quotes. `configparser.ConfigParser` is constructed with only `inline_comment_prefixes` (`pylint/config/config_file_parser.py:37`) and no quote stripping, so `bad-names-rgxs = "(foo{1,3})"` in a pylintrc reaches the transformer as the 12-character string including both `"` characters. Double quotes are therefore free to carry meaning at this layer.
- A TOML array is flattened before the transformer sees it: `_parse_rich_type_value` joins list and tuple values with `","` (`pylint/config/utils.py:136-137`) and the joined string is what `parse_toml_file` appends to the argv it builds (`pylint/config/config_file_parser.py:77-86`). So `bad-name-rgxs = ["(foo{1,3})"]` is today indistinguishable from the plain comma string, and fixing only the splitter leaves the array form broken.
- `csv.reader` cannot be fed the raw option value. Verified against this checkout's interpreter: `csv.reader(["a,\nb,\nc,"])` raises `_csv.Error: new-line character seen in unquoted field`, and that exact multi-line shape is one of `_splitstrip`'s own documented inputs (`pylint/utils/utils.py:220`), produced by any continuation-line list in a pylintrc. The reader must be fed `value.splitlines()`.
- `csv.reader(value.splitlines(), skipinitialspace=True)`, flattened with per-field `.strip()` and empties dropped, reproduces `_splitstrip` exactly on all three of its docstring examples (`pylint/utils/utils.py:216-221`) and additionally yields `['(foo{1,3})', 'bar']` for `"(foo{1,3})",bar`. Verified by running both against this checkout.
- Backslashes stay literal under the default csv dialect (`escapechar=None`), and a `"` that is not at the start of a field is kept verbatim — so `\d{1,3}` and `a"b` pass through unchanged. Verified against this checkout.
- Exactly one committed fixture in the repo passes a quoted value to an option that routes through `_check_csv`: `tests/functional/e/.#emacs_file_lock_redefined_conf.rc:2` sets `ignore-patterns=""`. Today that compiles to a pattern matching two literal quote characters; under quote-aware splitting it becomes an empty list. Both produce "nothing is ignored", which is what the fixture's `.txt` expectation asserts, so the observable result is unchanged.
- `tests/config/test_config.py:134-146` (`test_csv_regex_error`) asserts that `--bad-names-rgx=(foo{1,3})` — argparse resolves the abbreviation to `--bad-names-rgxs` — exits with `Error in provided regular expression: (foo{1 …`. Unquoted input still splits under this design, so that assertion stays true; it would not survive a splitter that inferred grouping from regex syntax.
- pytest turns warnings into errors (`pyproject.toml:99`, `filterwarnings = "error"`), so any `DeprecationWarning` raised by the new parsing path fails the suite rather than passing silently.
- Changelog fragments are pre-commit validated: `script/check_newsfragments.py:23-45` restricts the extension to a fixed set including `bugfix`, and requires the body to end in a sentence followed by a blank line and a `Closes #<issue>`-style reference.

## 5. Risks

- **A plain-`csv` option whose value legitimately begins with a double quote changes meaning** — medium. Routing `_check_csv` (`pylint/utils/utils.py:250`) through the new splitter affects `csv`, `confidence`, `glob_paths_csv` and the message-id lists at `pylint/config/callback_actions.py:142` and `:359`, not only the regex types. Mitigation: the repo-wide survey found a single such fixture (`tests/functional/e/.#emacs_file_lock_redefined_conf.rc:2`) whose observable result is unchanged; add explicit unit cases for `""`, `a"b`, and an unterminated leading quote so the semantics are pinned rather than incidental. If review judges the blast radius unacceptable, the fallback is to leave `_check_csv` alone and call the new splitter only from `_regexp_csv_transfomer` and `_regexp_paths_csv_transfomer` (`pylint/config/argument.py:114-133`), accepting that plain `csv` and TOML arrays keep today's behavior.
- **Quoting inside `_parse_rich_type_value` leaks into non-csv options** — medium. That helper is type-blind: it is applied to every TOML value in `parse_toml_file` (`pylint/config/config_file_parser.py:80,84`), including scalars and dicts, and the same joined string is stored into `config_content` as well as argv. Mitigation: quote only elements that actually contain `,` or `"`, leaving every existing fixture (e.g. `tests/config/functional/toml/rich_types.toml:6-9`) byte-identical, and assert that with a result-json functional test.
- **A malformed quoted field parses to something surprising instead of erroring** — low. `csv.reader` treats an unterminated `"a,b` as a single field consuming the rest of the line rather than raising. Mitigation: that fragment then fails in `_regex_transformer` (`pylint/config/argument.py:105-111`) with the existing friendly message, so the user still gets a diagnostic naming the offending pattern; cover the shape with a unit case.
- **Users on the old syntax read the new rule as a break** — low. No previously-working configuration changes meaning unless it contained a leading double quote. Mitigation: file the changelog fragment under `bugfix`, not `breaking` (`script/check_newsfragments.py:23-36` lists both), and state the quoting rule in `doc/user_guide/configuration/index.rst:18-26`.
- **The fix does not reach the reported TOML snippet as literally written** — low. `bad-name-rgxs = "(foo{1,3})"` in a `.toml` has its quotes consumed by the TOML parser before `_parse_rich_type_value` runs, so the value still splits. Mitigation: the same file fixed as `bad-name-rgxs = ["(foo{1,3})"]` (array form, covered by Step 5) or `'"(foo{1,3})"'` works, and the identical snippet in a `pylintrc`/`setup.cfg` works unchanged; document both forms in the user-guide section.

## 6. Steps

- [ ] 1. Settle the escape syntax as RFC-4180 double quoting rather than a syntax-aware splitter, and record it in the fragment written at Step 9 — the deciding evidence is `tests/config/test_config.py:134-146`, which pins the current split-then-fail behavior for unquoted input. <!-- step-1 -->
- [ ] 2. Add a quote-aware splitter to `pylint/utils/utils.py` directly below `_splitstrip` (`pylint/utils/utils.py:212-232`): flatten `csv.reader(value.splitlines(), skipinitialspace=True)`, `.strip()` each field, drop empties. Import `csv` at `pylint/utils/utils.py:1-30`. Docstring mirrors `_splitstrip`'s three doctest examples plus one quoted-comma example. <!-- step-2 -->
- [ ] 3. Route the string branch of `_check_csv` through the new splitter (`pylint/utils/utils.py:250-253`), leaving the list/tuple passthrough at `pylint/utils/utils.py:251-252` untouched, and re-export the new name from `pylint/utils/__init__.py:12-27` and its `__all__` (`pylint/utils/__init__.py:29-35`). <!-- step-3 -->
- [ ] 4. Add splitter unit tests to `tests/utils/unittest_utils.py:7` (which imports `pylint.utils.utils` directly): the three `_splitstrip` doctest inputs (`pylint/utils/utils.py:216-221`), `"(foo{1,3})"`, `"(foo{1,3})",bar`, `""`, `a"b`, `\d{1,3}`, an unterminated `"a,b`, and a Windows-style path with backslashes. <!-- step-4 -->
- [ ] 5. Make `_parse_rich_type_value` re-quote list elements containing `,` or `"` before joining (`pylint/config/utils.py:136-137`), using `csv.writer` into a `StringIO` so the quoting dialect matches the reader added in Step 2 rather than being hand-rolled. Leave the `re.Pattern` and `dict` branches (`pylint/config/utils.py:138-141`) unchanged. <!-- step-5 -->
- [ ] 6. Add regression tests beside `test_csv_regex_error` in `tests/config/test_config.py:134`, driving the public CLI seam via the same `Run` helper imported at `tests/config/test_config.py:18`: a quoted comma-bearing `--bad-names-rgxs` exits cleanly, and `runner.linter.config.bad_names_rgxs` holds one pattern whose `.pattern` is the original regex. <!-- step-6 -->
- [ ] 7. Add an ini-seam test in `tests/config/test_config.py` using `run_using_a_configuration_file` (`tests/config/test_config.py:19`) with `bad-names-rgxs = "(foo{1,3})"` written verbatim — the form that reaches the transformer with its quotes intact per `pylint/config/config_file_parser.py:37`. <!-- step-7 -->
- [ ] 8. Add a TOML functional fixture plus `.result.json` under `tests/config/functional/toml/`, collected by the rglob at `tests/config/test_functional_config_loading.py:41-50`, covering the array form `bad-name-rgxs = ["(foo{1,3})", "bar"]` — the path Step 5 fixes. Mirror the shape of `tests/config/functional/toml/rich_types.toml` and its `.result.json`. <!-- step-8 -->
- [ ] 9. Add the towncrier fragment `doc/whatsnew/fragments/<issue-number>.bugfix` in the format enforced by `script/check_newsfragments.py:38-45` (sentence-terminated body, blank line, `Closes #<issue-number>`), taking the number from the tracking issue. <!-- step-9 -->
- [ ] 10. Add a short "Comma-separated options" section to `doc/user_guide/configuration/index.rst:18-26` stating the quoting rule and showing the pylintrc, TOML-array, and TOML-quoted-string forms; leave `doc/user_guide/configuration/all-options.rst` untouched since `doc/exts/pylint_options.py:157` regenerates it from the unchanged help strings. <!-- step-10 -->

## 7. Tools Required

- `python3` with the checkout installed in editable mode.
- `pytest` (`pyproject.toml:95-105` supplies the config; `filterwarnings = "error"` is active).
- `pre-commit`, for the newsfragment check wired to `script/check_newsfragments.py`.
- `git`.

## 8. Approval Points

- `step-1` — the escape syntax is the one user-visible decision in this change, and the alternative considered below (splitting on regex structure) contradicts an existing assertion at `tests/config/test_config.py:134-146`. Confirm the direction before code lands.

Steps 2-10 may run autonomously.

## 9. Validation

The public seams are `pylint.lint.Run` / the `pylint` CLI for end-to-end behavior (the seam `tests/config/test_config.py:18` already enters through) and `pylint.utils._check_csv` for the splitter unit. Prior art to mirror: `tests/config/test_config.py:118-146` for CLI-level regex-option assertions, `tests/config/functional/toml/rich_types.toml` + `.result.json` for a parsed-configuration assertion, `tests/utils/unittest_utils.py` for direct helper tests.

- The splitter reproduces `_splitstrip` on its documented inputs and keeps a quoted comma inside one field.
  `verify: python -m pytest tests/utils/unittest_utils.py -q`
- A quoted comma-bearing regex reaches the checker as one compiled pattern via the CLI and via a pylintrc.
  `verify: python -m pytest tests/config/test_config.py -q`
- The TOML array form round-trips through `_parse_rich_type_value` into the parsed configuration.
  `verify: python -m pytest tests/config/test_functional_config_loading.py -q`
- The pre-existing assertion that *unquoted* `(foo{1,3})` still errors with the friendly message is unbroken.
  `verify: python -m pytest tests/config/test_config.py -q -k "csv_regex_error or regex_error"`
- `ignore-paths` / `ignore-patterns` behavior at the CLI level is unchanged, including the already-validated-values regression at `tests/test_self.py:1122-1134`.
  `verify: python -m pytest tests/test_self.py -q -k "regex or ignore"`
- The one committed fixture that feeds a quoted value to a `_check_csv` option still produces its expected output.
  `verify: python -m pytest tests/test_functional.py -q -k "emacs_file_lock"`
- Nothing else in the suite depends on the old splitting.
  `verify: python -m pytest tests -q -x`
- The changelog fragment satisfies the format check.
  `verify: python script/check_newsfragments.py doc/whatsnew/fragments/*.bugfix`

Prose-only criterion: a reviewer confirms the user-guide section added at Step 10 shows all three working spellings, since no command can judge whether the documented forms are the ones users will reach for.

## 10. Rollback-Recovery

Additive and self-contained: revert the single commit. No migration, no persisted state, no feature flag. If the wide `_check_csv` routing turns out to be the problem rather than the splitter, the narrower recovery is to restore `_check_csv` (`pylint/utils/utils.py:250-253`) to its `_splitstrip` call and invoke the new splitter only from `_regexp_csv_transfomer` and `_regexp_paths_csv_transfomer` (`pylint/config/argument.py:114-133`) — that keeps Steps 2, 4, 6, 7 and drops Steps 5 and 8.

## 11. Done Condition

`bad-names-rgxs = "(foo{1,3})"` in a pylintrc and `bad-name-rgxs = ["(foo{1,3})"]` in a pyproject.toml each lint a file without error and register one compiled pattern, the full `tests/` suite is green including the unchanged `test_csv_regex_error` assertion at `tests/config/test_config.py:134-146`, and the changelog fragment passes `script/check_newsfragments.py`.

## Considered Alternatives

- **Split only on commas that sit outside `()`, `[]`, `{}` (regex-structure-aware).** Fixes the reported config with no user edit at all, which is the issue's first-choice ask. Rejected: it is a second, partial regex parser living next to Python's — it must model escapes, character classes, and `(?…)` groups to stay correct, it silently reinterprets any existing config that has a top-level comma inside a bracket, and it cannot express a top-level literal comma at all. It also contradicts `tests/config/test_config.py:134-146`, which asserts the unquoted case errors.
- **Treat `\,` as an escaped separator.** Cheap, and the surviving backslash is harmless because `\,` compiles to a literal comma in Python's `re`. Rejected as the primary mechanism: it puts a pylint-specific meaning on a sequence that already has a regex meaning, and it does not help the reported `{1,3}` case, where the comma is not something a user thinks of as needing escape. Nothing prevents adding it later on top of quoting.
- **Accept only TOML/ini list syntax for these options and stop splitting strings.** Cleanest possible model. Rejected as a breaking change: every documented example, the default value of `ignore-patterns` (`pylint/lint/base_options.py:59-60`), and the committed fixture at `tests/functional/n/name/name_good_bad_names_regex.rc:14` use the comma-string form.
