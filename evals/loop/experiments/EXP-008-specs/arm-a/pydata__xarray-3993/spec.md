---
tier: T1.5
producer: plan
schema-version: 1
branch: main
timestamp: 2026-08-10T00:00:00Z
geniro_kind: design-doc
geniro_schema_version: m5-v2
task_slug: dataarray-integrate-coord-arg
topic: Rename DataArray.integrate's first argument from `dim` to `coord` behind a deprecation cycle so it matches Dataset.integrate and both `differentiate` methods.
mode: DESIGN_DOC
effort_tier: small
lifecycle: draft
budget:
  max_files_to_edit: 5
  max_lines_changed: 150
  time_budget: null
checkpoints:
  - step_anchor: step-2
    name: "Argument resolution implemented (coord/dim/both/neither)"
  - step_anchor: step-6
    name: "Deprecation tests green"
forbidden_actions:
  - "do NOT change `Dataset.integrate`'s public parameter name — it is already `coord` and is the target the DataArray side is being aligned to"
  - "do NOT remove the `dim` keyword outright in this change — it must keep working for one deprecation cycle"
  - "do NOT change the numerical behaviour of `Dataset._integrate_one` — this is an API-surface change only"
approval_required_for: []
tools_required: ["python", "pytest"]
---

<!-- geniro:design-doc -->

# Align `DataArray.integrate` on the `coord` argument name

## 1. Objective

Rename `DataArray.integrate`'s first parameter from `dim` to `coord`, keeping `dim` working as a deprecated keyword alias that emits a `FutureWarning`.

## 2. Scope — Included

- `xarray/core/dataarray.py` — the `integrate` signature, its argument-resolution logic, and its docstring (`xarray/core/dataarray.py:3483-3532`).
- `xarray/tests/test_dataset.py` — extend `test_integrate` (`xarray/tests/test_dataset.py:6555`) with coverage for `coord=`, the deprecated `dim=`, and the two error cases.
- `xarray/tests/test_units.py` — the one keyword call site that passes `dim=` to `DataArray.integrate` (`xarray/tests/test_units.py:3684`).
- `doc/whats-new.rst` — a deprecation entry in the unreleased `v0.17.0` section (`doc/whats-new.rst:20-24`).

## 3. Scope — Excluded

- `Dataset.integrate` (`xarray/core/dataset.py:5966`) and `Dataset._integrate_one` (`xarray/core/dataset.py:6025`) — the parameter is already named `coord` and the numerics are untouched.
- `DataArray.differentiate` (`xarray/core/dataarray.py:3424-3426`) and `Dataset.differentiate` (`xarray/core/dataset.py:5907`) — both already take `coord`; the issue names them as the reference, not as work.
- Actually removing the `dim` keyword. That is the follow-up release's change; this one only starts the cycle.
- `doc/computation.rst:408-413` and `doc/api.rst:178,371` — the docs call `a.integrate("x")` positionally and list the methods without argument names, so the rename leaves them correct as written.

## 4. Assumptions

- `DataArray.integrate` currently declares `def integrate(self, dim: Union[Hashable, Sequence[Hashable]], datetime_unit: str = None)` with `dim` as a required first parameter — `xarray/core/dataarray.py:3483-3485`.
- `Dataset.integrate` currently declares `def integrate(self, coord, datetime_unit=None)` — `xarray/core/dataset.py:5966`. The two names are the only difference between the signatures; both accept a scalar or a sequence.
- `DataArray.integrate` forwards positionally — `ds = self._to_temp_dataset().integrate(dim, datetime_unit)` at `xarray/core/dataarray.py:3531` — so renaming the DataArray-side parameter requires no matching change on the Dataset side.
- `Dataset.integrate` wraps a non-list/tuple argument into a 1-tuple and loops `_integrate_one` per element (`xarray/core/dataset.py:6018-6023`), so the `Union[Hashable, Sequence[Hashable]]` annotation on the DataArray side is honoured downstream and must survive the rename.
- The name is resolved against coordinates, not dimensions: `_integrate_one` raises `ValueError(f"Coordinate {coord} does not exist.")` when the name is absent from both `self.variables` and `self.dims` (`xarray/core/dataset.py:6028-6029`), and rejects a non-1-D coordinate variable (`xarray/core/dataset.py:6032-6036`). The rename therefore aligns the parameter name with behaviour that is already coordinate-based.
- `import warnings` is already at module scope in `xarray/core/dataarray.py:3`, so emitting a `FutureWarning` needs no new import.
- The codebase's established deprecation vehicle is `warnings.warn(<message>, FutureWarning, stacklevel=2)` for a superseded keyword — see the `meta` / `output_sizes` deprecation in `xarray/core/computation.py:1063-1080` — with `xarray/core/utils.py:41-48` providing `alias_message` / `alias_warning` for whole-symbol aliases (function-level, not per-keyword, so not the right fit here).
- Every in-repo call site of `DataArray.integrate` except one passes the coordinate positionally: `xarray/tests/test_dataset.py:6575,6583,6589,6600,6604,6639,6655`, `xarray/tests/test_sparse.py:353`, `doc/computation.rst:413`, and the docstring example at `xarray/core/dataarray.py:3526`. The exception is `method("integrate", dim="x")` at `xarray/tests/test_units.py:3684`; its Dataset counterpart already uses `coord="x"` at `xarray/tests/test_units.py:5186`.
- The pytest config does not turn warnings into errors: `setup.cfg:141-143` sets `filterwarnings` to a single `ignore:` entry for a bottleneck `FutureWarning`. A new `FutureWarning` will therefore surface in test output but will not fail unrelated tests.
- `pytest.warns(FutureWarning)` is an established assertion style in this suite — `xarray/tests/test_dataarray.py:4078`, `xarray/tests/test_dataset.py:2396,5391`.
- Implicit-`Optional` annotations are already accepted by this repo's mypy configuration: the existing signature writes `datetime_unit: str = None` (`xarray/core/dataarray.py:3484`) and mypy runs through pre-commit (`.pre-commit-config.yaml:27-30`) with no `no_implicit_optional` override in `setup.cfg`'s mypy section (`setup.cfg:167` onward is per-module `ignore_missing_imports` only).
- The unreleased release section in `doc/whats-new.rst` is `v0.17.0 (unreleased)` at `doc/whats-new.rst:20-21`, with a `Breaking changes` subsection at `doc/whats-new.rst:23` and `New Features` at `doc/whats-new.rst:46`.
- Docstrings are executed as tests in CI via `python -m pytest --doctest-modules xarray --ignore xarray/tests` (`.github/workflows/ci-additional.yaml:160`), so the `>>> da.integrate("x")` example at `xarray/core/dataarray.py:3526` must keep producing the recorded output.

## 5. Risks

- **`coord` gains a default, so `da.integrate()` becomes syntactically legal** — medium. Making `coord` optional is what lets `dim=` still be passed alone; the cost is that Python no longer raises `TypeError` for a bare call. Mitigation: raise an explicit `TypeError` when neither `coord` nor `dim` is supplied (step 2), so the observable failure mode is unchanged in kind.
- **Callers passing both names** — low. `da.integrate("x", dim="y")` is ambiguous. Mitigation: raise `TypeError` naming both keywords rather than silently preferring one.
- **Downstream code using `dim=` starts emitting warnings** — low. That is the intended signal of a deprecation cycle, and `setup.cfg:141-143` shows this suite does not escalate warnings to errors.
- **Keyword-only placement of `dim`** — low. Declaring `dim` after `*` prevents a caller who passes two positional arguments (`da.integrate("x", "D")`) from accidentally binding `dim`; `datetime_unit` remains the second positional, matching every existing positional call site (`xarray/tests/test_dataset.py:6639`).
- **Test-id churn in `test_units.py`** — low. The `method` helper (`xarray/tests/test_units.py:277`) builds parametrize ids from the recorded kwargs, so switching `dim="x"` to `coord="x"` at `xarray/tests/test_units.py:3684` renames one test id. No selection logic in the repo pins that id.
- **Doctest drift** — low. The docstring rewrite touches prose and parameter names around a live doctest at `xarray/core/dataarray.py:3511-3529`; mitigation is the doctest `verify:` command in §9.

## 6. Steps

- [ ] 1. Change the `DataArray.integrate` signature at `xarray/core/dataarray.py:3483-3485` to `coord: Union[Hashable, Sequence[Hashable]] = None, datetime_unit: str = None, *, dim: Union[Hashable, Sequence[Hashable]] = None`, keeping `datetime_unit` in second position so positional callers such as `xarray/tests/test_dataset.py:6639` are unaffected. <!-- step-1 -->
- [ ] 2. In the method body, immediately before the delegation at `xarray/core/dataarray.py:3531`, resolve the two names: raise `TypeError` when both `coord` and `dim` are given, raise `TypeError` when neither is, and when only `dim` is given emit `warnings.warn(...,  FutureWarning, stacklevel=2)` stating that `dim` is deprecated for `DataArray.integrate` and `coord` should be used, then assign it to `coord` — mirroring the keyword-deprecation shape at `xarray/core/computation.py:1063-1071`. <!-- step-2 -->
- [ ] 3. Forward the resolved name: `self._to_temp_dataset().integrate(coord, datetime_unit)` at `xarray/core/dataarray.py:3531`, leaving `Dataset.integrate` (`xarray/core/dataset.py:5966`) untouched. <!-- step-3 -->
- [ ] 4. Update the docstring at `xarray/core/dataarray.py:3486-3506`: the `.. note::` sentence that reads "i.e. dim must be one dimensional" (`xarray/core/dataarray.py:3489-3490`), the `Parameters` entry `dim : hashable, or sequence of hashable` (`xarray/core/dataarray.py:3494-3495`), and add a `dim` entry marked deprecated. Add `Dataset.integrate` to the `See also` block at `xarray/core/dataarray.py:3504-3506`, matching the reciprocal reference `Dataset.integrate` already carries at `xarray/core/dataset.py:5987`. Leave the doctest at `xarray/core/dataarray.py:3511-3529` byte-identical. <!-- step-4 -->
- [ ] 5. Switch the one keyword call site in the unit-registry suite from `method("integrate", dim="x")` to `method("integrate", coord="x")` at `xarray/tests/test_units.py:3684`, matching its Dataset counterpart at `xarray/tests/test_units.py:5186`. <!-- step-5 -->
- [ ] 6. Extend `test_integrate` in `xarray/tests/test_dataset.py:6555-6604` with four assertions on the `DataArray` seam: `da.integrate(coord="x")` equals the positional `da.integrate("x")` (`xarray/tests/test_dataset.py:6575`); `da.integrate(dim="x")` raises `FutureWarning` under `pytest.warns` (style precedent `xarray/tests/test_dataarray.py:4078`) and still returns the same result; `da.integrate("x", dim="x")` raises `TypeError`; `da.integrate()` raises `TypeError`. <!-- step-6 -->
- [ ] 7. Add a `Breaking changes` entry to the unreleased section of `doc/whats-new.rst:23-24` recording that `DataArray.integrate`'s first argument is now `coord` and that `dim` is deprecated, referencing `:issue:`3993`` and matching the entry style already used at `doc/whats-new.rst:42-43`. <!-- step-7 -->
- [ ] 8. Sweep the repo for any remaining `integrate(dim` or `integrate(\n ... dim=` usage outside the deprecation path — the known positional sites are `doc/computation.rst:413`, `xarray/tests/test_sparse.py:353`, and `xarray/core/dataarray.py:3526`, none of which need editing — and confirm `doc/api.rst:178,371` list the methods without argument names. <!-- step-8 -->

## 7. Tools Required

- `python` with the repo's dev environment (xarray importable in-place).
- `pytest` — the suite runner configured at `setup.cfg:138-140` (`testpaths = xarray/tests properties`).

## 8. Approval Points

none — the change is confined to one public method's argument names plus its tests and release notes, and `/geniro:implement` may run start to finish.

## 9. Validation

The public seams under test are `xarray.DataArray.integrate` and `xarray.Dataset.integrate` — the same seams `test_integrate` (`xarray/tests/test_dataset.py:6555`) and `test_trapz_datetime` (`xarray/tests/test_dataset.py:6607`) already enter through, so all new coverage extends that existing file rather than adding one.

- Positional calls are unchanged and numerics are identical: `da.integrate("x")`, `da.integrate(("y", "x"))`, and `da.integrate("time", datetime_unit="D")` return what they returned before, and `ds["var"].integrate("x")` still equals `ds.integrate("x")["var"]`.
  `verify: python -m pytest xarray/tests/test_dataset.py -k "integrate or trapz_datetime" -q`
- `coord=` is accepted, `dim=` warns, and the two ambiguous/empty calls raise `TypeError` — the four assertions added in step 6.
  `verify: python -m pytest xarray/tests/test_dataset.py::test_integrate -q`
- The unit-registry suite passes with the renamed keyword at `xarray/tests/test_units.py:3684`.
  `verify: python -m pytest xarray/tests/test_units.py -k integrate -q`
- The sparse-array wrapper path, which calls `integrate` positionally (`xarray/tests/test_sparse.py:353`), is unaffected.
  `verify: python -m pytest xarray/tests/test_sparse.py -k integrate -q`
- The rewritten docstring still executes, matching the CI doctest job (`.github/workflows/ci-additional.yaml:160`).
  `verify: python -m pytest --doctest-modules xarray/core/dataarray.py xarray/core/dataset.py -q`
- Type checking stays clean under the pre-commit mypy hook (`.pre-commit-config.yaml:27-30`).
  `verify: python -m mypy xarray/core/dataarray.py`
- Manual check that the deprecation is actually reachable and points at the caller: running `da.integrate(dim="x")` in a fresh interpreter under `-W error::FutureWarning` raises, and the reported source line is the caller's, not `dataarray.py` (this is what `stacklevel=2` buys and no in-repo assertion pins it).

## 10. Rollback-Recovery

Single-commit revert. The change touches no persisted data, no serialization format, and no on-disk schema; the only externally visible artifacts are the new `FutureWarning` and the release-note line, both of which disappear with the commit. If the deprecation proves disruptive before release, the narrower rollback is to delete the `warnings.warn` call added in step 2 while keeping `coord` as the documented name — `dim` continues to work silently, and the alignment with `Dataset.integrate` survives.

## 11. Done Condition

`da.integrate(coord="x")`, `da.integrate("x")`, and `ds.integrate(coord="x")` all work and agree; `da.integrate(dim="x")` returns the same result while emitting a `FutureWarning`; every `verify:` command in §9 passes; and `doc/whats-new.rst` records the deprecation in the unreleased section.

## Considered Alternatives

**A. Hard rename with no deprecation cycle** — change `dim` to `coord` at `xarray/core/dataarray.py:3484` and update the one keyword call site at `xarray/tests/test_units.py:3684`. Smallest diff, and every in-repo caller is positional so nothing internal breaks. Rejected: `dim` is a documented public keyword, and the issue explicitly leaves the deprecation-cycle question open rather than answering "no". Silently raising `TypeError` on third-party `da.integrate(dim=...)` is not worth the ~15 lines saved.

**B. Deprecated keyword-only alias (chosen)** — `coord` becomes the first parameter, `dim` survives as a keyword-only alias behind a `FutureWarning`. Keeps every positional caller working, makes the DataArray and Dataset signatures agree on the name today, and gives downstream code a release to migrate. Costs a small argument-resolution block and two error branches.

**C. Accept both names permanently** — add `coord` as an alias with no warning and no removal plan. Rejected: it leaves two spellings in the public API forever, which is the confusion the issue is about ("we should be strict to not confuse up the meanings in the documentation/API"), and it gives no signal that would ever let the duplication be cleaned up.

**D. Change `Dataset.integrate` to `dim` instead** — the other way to make the two agree. Rejected on the issue's own reasoning: integration is defined by coordinate spacing, a bare dimension carries no such information (`xarray/core/dataset.py:6031-6036` resolves the argument to a 1-D coordinate variable and integrates against its values), and `differentiate` already standardises on `coord` on both classes (`xarray/core/dataarray.py:3425`, `xarray/core/dataset.py:5907`).
