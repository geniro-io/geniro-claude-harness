---
tier: T1.5
producer: plan
schema-version: 1
branch: fix-regexp-csv-comma-splitting
timestamp: 2026-08-10T07:25:23Z
geniro_kind: design-doc
geniro_schema_version: m5-v2
task_slug: pylint-regexp-csv-comma
topic: Comma-separated regex options must not split a comma that belongs to the regular expression itself
mode: DESIGN_DOC
effort_tier: small
lifecycle: draft
budget:
  max_files_to_edit: 6
  max_lines_changed: 200
  time_budget: "4h"
checkpoints:
  - step_anchor: step-1
    name: "Top-level comma splitter lands with its unit tests green"
  - step_anchor: step-5
    name: "Existing config test-suite green after the behavior change"
forbidden_actions:
  - "do NOT change the splitting rule used by the plain `csv` / `confidence` / `glob_paths_csv` option types — `_splitstrip` stays as it is"
  - "do NOT edit option `help` strings — `doc/user_guide/configuration/all-options.rst` is generated from them by `doc/exts/pylint_options.py:157`, so a help edit drags a regenerated doc file into the diff"
  - "do NOT introduce a compile-and-retry heuristic that re-joins fragments which fail `re.compile` — see §5 for why it is unsound"
approval_required_for:
  - step-5
tools_required: ["python3", "pip", "pytest", "pre-commit"]
---

<!-- geniro:design-doc -->

# Comma-separated regex options must not split a comma that belongs to the regular expression itself

## 1. Objective

Split the `regexp_csv` and `regexp_paths_csv` option values only at commas that sit at the top level of the value, so a comma inside a `{m,n}` quantifier, a `[...]` character class, or a `(...)` group stays part of its pattern.

## 2. Scope — Included

- `pylint/utils/utils.py:250-253` — add a `_check_regexp_csv` splitter beside the existing `_check_csv`.
- `pylint/utils/__init__.py:16,34` — re-export the new helper alongside `_check_csv` / `_splitstrip`.
- `pylint/config/argument.py:114-119` — `_regexp_csv_transfomer` splits with the new helper instead of `_csv_transformer`.
- `pylint/config/argument.py:122-133` — `_regexp_paths_csv_transfomer` splits with the new helper, and routes its `re.compile` through `_regex_transformer` (`pylint/config/argument.py:105-111`) so a bad `ignore-paths` pattern reports an `argparse` error instead of raising `re.error` out of the parser.
- Every option declared with `"type": "regexp_csv"` or `"type": "regexp_paths_csv"` inherits the fix: `ignore-patterns` and `ignore-paths` (`pylint/lint/base_options.py:53-67`), `good-names-rgxs` and `bad-names-rgxs` (`pylint/checkers/base/name_checker/checker.py:212,232`), `exclude-too-few-public-methods` (`pylint/checkers/design_analysis.py:395`).
- `tests/config/test_config.py:134-147` — `test_csv_regex_error` currently asserts the mangled behavior (`(foo{1`) and must be re-pointed at a genuinely invalid pattern.
- `tests/config/test_config.py` — new regression tests over the command-line route and the config-file route.
- `doc/whatsnew/fragments/<issue>.bugfix` — towncrier fragment, format enforced by `script/check_newsfragments.py`.
- `doc/user_guide/configuration/index.rst` — one hand-written paragraph stating the splitting rule and the `[,]` escape for a literal top-level comma.

## 3. Scope — Excluded

- The plain `csv`, `confidence`, and `glob_paths_csv` types (`pylint/config/argument.py:38-53,84-91`). Their values are msgids, names, and paths; a comma inside one of those is not a live complaint, and changing `_splitstrip` (`pylint/utils/utils.py:212-232`) would move `--disable`, `--enable`, and `--load-plugins` at the same time.
- `_parse_rich_type_value` (`pylint/config/utils.py:134-142`), which flattens a TOML array to a comma-joined string. Once the consumer splits at top level only, a TOML array such as `bad-names-rgxs = ["(foo{1,3})", "bar"]` round-trips correctly with no producer-side change, so quoting elements there would only add a second, competing mechanism.
- `--generate-toml-config` / `--generate-rcfile` output (`pylint/config/arguments_manager.py:236-395`). It writes real lists through `tomlkit`, not through the csv join, so it is unaffected.
- Option `help` strings and the generated `doc/user_guide/configuration/all-options.rst`.

## 4. Assumptions

- A transformer registered in `_TYPE_TRANSFORMERS` (`pylint/config/argument.py:136-158`) is only ever called with a `str`: the docstring at `pylint/config/argument.py:152-158` states it runs for command line, configuration file, and string default values, and non-string defaults bypass it. The list/tuple pass-through in the new helper exists only for symmetry with `_check_csv` (`pylint/utils/utils.py:250-253`).
- Configuration values can reach the transformer containing newlines: `configparser` joins INI continuation lines with `\n`, and `_splitstrip` documents that case at `pylint/utils/utils.py:220-221`. The new splitter must accept them (this rules out feeding the raw value to `csv.reader`, which raises `_csv.Error: new-line character seen in unquoted field`).
- In a *valid* Python regular expression an unescaped `(` always opens a group and an unescaped `[` always opens a character class — `re.compile("(")` and `re.compile("[")` both raise `re.error`. So tracking those two constructs cannot change the meaning of any configuration that parses today.
- `{` is not subject to that guarantee: `re.compile("[a-z]{2")` succeeds and matches the literal text `{2`. The splitter therefore only treats `{` as a quantifier opener when the brace group actually has quantifier shape (`\{\d*(?:,\d*)?\}`), and treats every other `{` as an ordinary character.
- `bad-names-rgxs`, `good-names-rgxs` (`pylint/checkers/base/name_checker/checker.py:212,232`) and `exclude-too-few-public-methods` (`pylint/checkers/design_analysis.py:395`) default to `""` or `[]`, so the splitter is exercised with the empty string on nearly every run and must return an empty list for it.
- The checkout has no installed dependencies: `import astroid` fails in a bare interpreter here. The implementer installs the package plus test requirements before running anything (`pip install -e .` and `pip install -r requirements_test_min.txt`).
- The GitHub issue number for the towncrier fragment filename is taken from the tracked issue this change closes; the fragment body must end with `Closes #<number>` to satisfy `script/check_newsfragments.py`.

## 5. Risks

- **A currently-working configuration changes meaning — low.** The only inputs whose split changes are those containing a comma inside `(...)`, `[...]`, or a quantifier-shaped `{...}`. Inside `(` and `[` such a configuration cannot parse today (the assumption above); inside `{m,n}` it parses but silently produces two junk patterns (`x{1` and `2}`), which is the same defect the issue reports without the crash. Mitigation: the regression tests in step 6 pin both the changed and the unchanged behavior, and the full `tests/config` plus `tests/lint` suites run before ship.
- **A literal top-level comma still cannot be expressed — low.** `bad-names-rgxs = "^Doe, John$"` still splits into two patterns. Mitigation: the regex language supplies its own escape — `^Doe[,] John$` or `^Doe(,) John$` — and step 9 documents it. A second, quoting-based escape mechanism is deliberately not added; two escapes for one problem is what makes this option class confusing.
- **A compile-and-retry design would look attractive during implementation and is unsound — medium if adopted.** Splitting first and re-joining any fragment that fails `re.compile` appears to fix the reported case, but `re.compile("[a-z]{2")` succeeds, so `[a-z]{2,}` splits into two *compilable* patterns and the recovery never fires — a silently wrong result with no error. Mitigation: recorded as a `forbidden_actions` entry.
- **`_regexp_paths_csv_transfomer` error text changes — low.** Routing its compile through `_regex_transformer` reports the composite Windows/Posix pattern that the function builds (`pylint/config/argument.py:126-132`), not the pattern the user typed. That is still strictly better than the current raw `re.error` traceback. Mitigation: assert on the `re` message substring, not on the echoed pattern, in the step 6 test.
- **The fragment filename needs an issue number the plan does not carry — low.** Mitigation: step 8 names the constraint; `pre-commit run check-newsfragments` decides it.

## 6. Steps

- [ ] 1. Add `_check_regexp_csv(value: list[str] | tuple[str] | str) -> Sequence[str]` to `pylint/utils/utils.py` immediately after `_check_csv` (`pylint/utils/utils.py:250-253`): pass a list/tuple through unchanged, otherwise tokenize the string and split at depth-zero commas, stripping each fragment and dropping empty ones so it matches `_splitstrip` (`pylint/utils/utils.py:212-232`) on every value that has no nested comma. <!-- step-1 -->

  The tokenizer is the decision — one pass over a pattern that consumes each comma-bearing construct whole, so no comma inside one is ever seen as a separator:

  ```python
  _REGEXP_CSV_TOKENS = re.compile(
      r"""\\.                        # escaped character: never a delimiter
        | \[ (?: \\. | [^]\\] )* ]   # character class
        | \{ \d* (?: , \d* )? }      # {m,n} quantifier
        | [(),]                      # group open / close / candidate separator
        | .                          # anything else, including a non-quantifier '{'
      """,
      re.VERBOSE | re.DOTALL,
  )
  ```

  Iterate the tokens keeping a group depth (`(` increments, `)` decrements, floored at zero); a `,` token at depth zero ends the current fragment, every other token is appended to it. `re.DOTALL` keeps newlines as ordinary characters.

- [ ] 2. Import `_check_regexp_csv` in `pylint/utils/__init__.py:16` and add it to `__all__` at `pylint/utils/__init__.py:34`, keeping both lists alphabetical next to `_check_csv`. <!-- step-2 -->

- [ ] 3. Change `_regexp_csv_transfomer` (`pylint/config/argument.py:114-119`) to iterate `pylint_utils._check_regexp_csv(value)` instead of `_csv_transformer(value)`, leaving the per-pattern `_regex_transformer` call untouched so an invalid fragment still surfaces as `argparse.ArgumentTypeError` (`pylint/config/argument.py:105-111`). <!-- step-3 -->

- [ ] 4. Change `_regexp_paths_csv_transfomer` (`pylint/config/argument.py:122-133`) the same way, and replace its bare `re.compile(...)` at `pylint/config/argument.py:127` with a `_regex_transformer(...)` call on the composed Windows/Posix alternation so an invalid `ignore-paths` value reports an argparse error rather than propagating `re.error`. <!-- step-4 -->

- [ ] 5. Re-point `test_csv_regex_error` (`tests/config/test_config.py:134-147`): `--bad-names-rgx=(foo{1,3})` is now one valid pattern and no longer errors. Keep the test's intent — one invalid element among several — by passing a value such as `foo,[a` and asserting the `unterminated character set` message from `_regex_transformer`. Leave `test_regex_error` (`tests/config/test_config.py:118-132`) untouched; it uses the non-csv `--function-rgx` and is unaffected. <!-- step-5 -->

- [ ] 6. Add regression tests to `tests/config/test_config.py`, mirroring the `Run([...], exit=False)` shape already used at `tests/config/test_config.py:100-116` and the tmp-file config shape at `tests/config/test_config.py:42-59`: <!-- step-6 -->
  - command line, quantifier comma preserved — `--bad-names-rgxs=(foo{1,3})` yields exactly one compiled pattern whose `.pattern` is `(foo{1,3})`;
  - command line, ordinary splitting unchanged — `--bad-names-rgxs=foo,bar` yields two patterns;
  - command line, mixed — `--bad-names-rgxs=(foo{1,3}),bar[,]baz` yields two patterns, proving `[,]` is the escape for a literal comma;
  - `pyproject.toml` route via `run_using_a_configuration_file` (`pylint/testutils/configuration_test.py`), covering both the scalar form `bad-names-rgxs = "(foo{1,3})"` from the issue report and the array form `bad-names-rgxs = ["(foo{1,3})", "bar"]` that `_parse_rich_type_value` (`pylint/config/utils.py:136-137`) flattens with a comma;
  - `--ignore-paths` with a `{m,n}` quantifier stays one pattern, and an invalid `--ignore-paths` value exits through argparse instead of raising `re.error` (step 4).

- [ ] 7. Add direct unit coverage for the splitter itself in `tests/config/test_config.py` — a `pytest.mark.parametrize` over `pylint.utils._check_regexp_csv` pinning: `""` → `[]`; `"a, b, c   ,  4,,"` → `["a", "b", "c", "4"]` and `"a,\nb,\nc,"` → `["a", "b", "c"]` (the `_splitstrip` doctests at `pylint/utils/utils.py:216-221`, which the new splitter must keep matching); `"(foo{1,3})"` → one element; `"[a,b],c"` → two elements; `"foo{bar,baz"` → two elements (a non-quantifier brace does not suppress the split). <!-- step-7 -->

- [ ] 8. Add `doc/whatsnew/fragments/<issue>.bugfix` describing that comma-separated regex options no longer split a comma inside a quantifier, character class, or group, ending with `Closes #<issue>` per the format enforced in `script/check_newsfragments.py`. <!-- step-8 -->

- [ ] 9. Add a short paragraph to `doc/user_guide/configuration/index.rst` (hand-written, unlike the generated `all-options.rst`) stating the rule for options taking a comma-separated list of regular expressions and showing `[,]` as the way to match a literal comma. <!-- step-9 -->

## 7. Tools Required

- `python3` with the package installed in editable mode (`pip install -e .`) — `astroid` is not importable in a bare checkout here.
- `pip install -r requirements_test_min.txt` for `pytest`.
- `pre-commit` for the news-fragment format check.

## 8. Approval Points

- `step-5` — re-pointing `test_csv_regex_error` rewrites an assertion that encodes today's behavior. Confirm the behavior change is intended before the existing test is edited rather than deleted.

## 9. Validation

Seams: the CLI entry point `pylint.testutils._run._Run` (used throughout `tests/config/test_config.py`), the configuration-file entry point `run_using_a_configuration_file` (`pylint/testutils/configuration_test.py`), and the helper's own import seam `pylint.utils._check_regexp_csv`. Prior art for the first two lives in `tests/config/test_config.py:42-147`.

Criteria:

1. A `{m,n}` quantifier survives on the command line and in a configuration file — `--bad-names-rgxs=(foo{1,3})` and `bad-names-rgxs = "(foo{1,3})"` in `pyproject.toml` both produce a single compiled pattern equal to the input.
   `verify: python -m pytest tests/config/test_config.py -q`
2. Ordinary comma separation is unchanged for values with no nested comma, including the multi-line INI form.
   `verify: python -m pytest tests/config/test_config.py -q -k regexp_csv`
3. Nothing else in configuration handling regresses — the config functional suite and the linter option tests stay green.
   `verify: python -m pytest tests/config tests/lint/unittest_lint.py -q`
4. The functional test that exercises `good-names-rgxs` / `bad-names-rgxs` end to end still passes (`tests/functional/n/name/name_good_bad_names_regex.rc:13-14`).
   `verify: python -m pytest tests/test_functional.py -q -k name_good_bad_names_regex`
5. The whole suite is green before ship.
   `verify: python -m pytest tests -q -x`
6. The news fragment matches the enforced format.
   `verify: pre-commit run check-newsfragments --all-files`
7. Manual check against the report: a `pyproject.toml` containing `[tool.pylint.basic]` with `bad-name-rgxs = "(foo{1,3})"` runs `pylint foo.py` to completion instead of erroring on `(foo{1`. Prose-only — it reproduces the issue text verbatim rather than a criterion a single command decides.

## 10. Rollback-Recovery

Pure code change, no migration and no persisted state. `git revert` of the single commit restores the previous splitting behavior; the only downstream artifacts are the news fragment and the doc paragraph, both plain files removed by the same revert. If the change ships and a user reports a configuration whose meaning shifted, the narrower fallback is to revert step 4 only (`_regexp_paths_csv_transfomer`), leaving the `regexp_csv` fix in place, since the two transformers are independent call sites of the same helper.

## 11. Done Condition

`python -m pytest tests -q` is green with the new regression tests included, and a `pyproject.toml` carrying `bad-name-rgxs = "(foo{1,3})"` lints a file to completion with that single pattern registered.

## Considered Alternatives

**A. Quote-aware splitting with the `csv` module.** Parse the value with `csv.reader(value.splitlines(), skipinitialspace=True)` so a pattern wrapped in double quotes keeps its commas. Rejected: it does not fix the configuration in the report — TOML consumes the outer quotes, so the transformer still receives a bare `(foo{1,3})` — and it forces every user of a `{m,n}` quantifier to learn a quoting convention for what reads as an ordinary regex. It also changes the meaning of any pattern that legitimately begins with `"`, and `csv.reader` raises on embedded newlines unless the value is pre-split by line, which the INI continuation form produces.

**B. Split, then re-join fragments that fail to compile.** Rejected on evidence: `re.compile("[a-z]{2")` succeeds because Python treats an unmatched `{` as a literal, so `[a-z]{2,}` splits into two compilable patterns and the recovery never triggers — the failure is silent rather than loud, which is worse than the current behavior.

**C. Quote list elements in `_parse_rich_type_value` (`pylint/config/utils.py:136-137`) so TOML arrays round-trip.** Rejected as unnecessary once splitting is top-level-aware: the flattened `"(foo{1,3}),bar"` already re-splits correctly. It would also touch every csv-typed option, not just the regex ones, for no additional coverage.
