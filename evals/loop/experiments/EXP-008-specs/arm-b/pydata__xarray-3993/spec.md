---
tier: T1.5
producer: plan
schema-version: 1
branch: detached-HEAD-8cc34cb
timestamp: 2026-08-10T07:20:49Z
geniro_kind: design-doc
geniro_schema_version: m5-v2
task_slug: integrate-coord-arg-consistency
topic: "Rename DataArray.integrate's `dim` argument to `coord` with a deprecation cycle so it matches Dataset.integrate and both `differentiate` methods."
mode: DESIGN_DOC
effort_tier: small
lifecycle: draft
budget:
  max_files_to_edit: 5
  max_lines_changed: 120
  time_budget: "2h"
checkpoints:
  - step_anchor: step-3
    name: "DataArray.integrate accepts coord= and warns on dim="
  - step_anchor: step-7
    name: "Test suite green + doctests pass"
forbidden_actions:
  - "do NOT remove the `dim` keyword outright — the change must stay source-compatible for callers using `integrate(dim=...)` in this release"
  - "do NOT add a `dim` alias to `Dataset.integrate` or to either `differentiate` — those already expose `coord` and never accepted `dim`"
  - "do NOT change the numerical behaviour of `Dataset._integrate_one` — this task is an API-surface rename only"
approval_required_for: []
tools_required: ["python", "pytest"]
---

<!-- geniro:design-doc -->

# Make `DataArray.integrate` take `coord`, deprecating `dim`

## 1. Objective

Rename the first parameter of `DataArray.integrate` from `dim` to `coord`, keeping `dim` accepted as a deprecated keyword alias that emits a `FutureWarning`.

## 2. Scope — Included

- `xarray/core/dataarray.py:3483-3532` — `DataArray.integrate` signature, argument reconciliation, docstring, and the delegating call into `Dataset.integrate`.
- `xarray/core/dataset.py:5966-5988` — `Dataset.integrate` docstring only: align the `coord` parameter type line and the `See also` block with the `DataArray` wording. No signature or behaviour change.
- `xarray/tests/test_dataset.py:6554-6604` — extend `test_integrate` with keyword-form and deprecation coverage.
- `xarray/tests/test_units.py:3684` — the one in-repo call site still passing `dim=` to `DataArray.integrate` (inside `TestDataArray`, class opens at `xarray/tests/test_units.py:2236`).
- `doc/whats-new.rst:20-45` — a `Deprecations` section under the unreleased `v0.17.0` block.

## 3. Scope — Excluded

- `Dataset.integrate`'s signature and body (`xarray/core/dataset.py:5966`, `xarray/core/dataset.py:6018-6023`, `xarray/core/dataset.py:6025-6070`) — it already takes `coord`; the loop, the 1-D coordinate check, and the datetime handling are untouched.
- `DataArray.differentiate` (`xarray/core/dataarray.py:3424-3426`) and `Dataset.differentiate` (`xarray/core/dataset.py:5907`) — both already take `coord`.
- Removal of the `dim` alias. That is the follow-up half of the deprecation cycle and belongs to a later release, not this change.
- Positional call sites, which keep working unchanged: `doc/computation.rst:413`, `xarray/tests/test_sparse.py:353`, and every `da.integrate("x")` in `xarray/tests/test_dataset.py`.
- `doc/api.rst:371` — the entry is method-level, so a parameter rename does not touch it.

## 4. Assumptions

- `xarray/core/dataarray.py:3` already does `import warnings`, so emitting the deprecation needs no new import.
- `DataArray.integrate` currently declares `dim` as a **required** parameter with no default (`xarray/core/dataarray.py:3484`), so today `da.integrate()` raises `TypeError`; giving `coord` a `None` default converts that to the `ValueError` this spec specifies.
- `DataArray.integrate` has exactly one implementation-side call site, the delegation at `xarray/core/dataarray.py:3531`; a repo-wide grep for `integrate` finds no other production caller passing `dim=`, and exactly one test caller (`xarray/tests/test_units.py:3684`).
- `Dataset.integrate` normalises a non-`list`/`tuple` argument into a 1-tuple (`xarray/core/dataset.py:6018-6019`), so forwarding a sequence such as `("y", "x")` through the renamed parameter keeps the multi-coordinate path working (`xarray/tests/test_dataset.py:6600`).
- The pytest configuration at `setup.cfg:138-147` sets no `error` entry in `filterwarnings`, so a `FutureWarning` from an un-updated call site degrades to a warning rather than a test failure.
- CI runs doctests over the package (`.github/workflows/ci-additional.yaml:160`, `python -m pytest --doctest-modules xarray --ignore xarray/tests`), so the `>>> da.integrate("x")` example at `xarray/core/dataarray.py:3526` must keep producing byte-identical output — it is positional, so it does.

## 5. Risks

- **Warning category mismatch (medium).** A consumer test may assert a specific category. `FutureWarning` is the category xarray uses for user-facing deprecations — `xarray/core/utils.py:45-48` (`alias_warning`), `xarray/core/dataset.py:5630-5636` (`roll_coords`), `xarray/core/computation.py:1063-1080` (`meta`/`output_sizes`). `DeprecationWarning` is suppressed by default outside `__main__` and would hide the notice from exactly the users who need it. Mitigation: use `FutureWarning` with `stacklevel=2`, matching those three precedents.
- **Silent behaviour change for `da.integrate()` with no argument (low).** `TypeError` becomes `ValueError`. Mitigation: raise explicitly with a message naming `coord`, rather than letting `None` fall through into `Dataset.integrate` and surface as the misleading `"Coordinate None does not exist."` from `xarray/core/dataset.py:6028-6029`.
- **Both arguments supplied (low).** `da.integrate(coord="x", dim="y")` is ambiguous. Mitigation: raise `ValueError` before any work, rather than silently preferring one.
- **Stale in-repo call site (low).** `xarray/tests/test_units.py:3684` would start emitting the new warning on every parametrisation. Mitigation: Step 6 updates it and Step 7's grep proves no other survives.

## 6. Steps

- [ ] 1. Change the `DataArray.integrate` signature at `xarray/core/dataarray.py:3483-3485` to `coord` first (default `None`), `datetime_unit` second, and a keyword-only deprecated `dim` last — preserving the existing positional order so `da.integrate("x", "D")` still resolves the same way. <!-- step-1 -->
- [ ] 2. Insert the argument-reconciliation block at the top of the body, immediately before the delegation at `xarray/core/dataarray.py:3531`: both supplied → `ValueError`; only `dim` → `warnings.warn(..., FutureWarning, stacklevel=2)` then `coord = dim`; neither → `ValueError` naming `coord`. <!-- step-2 -->
- [ ] 3. Update the delegation at `xarray/core/dataarray.py:3531` to `self._to_temp_dataset().integrate(coord, datetime_unit)`. <!-- step-3 -->
- [ ] 4. Rewrite the `DataArray.integrate` docstring to say `coord` throughout — the `.. note::` at `xarray/core/dataarray.py:3488-3490` and the parameter entry at `xarray/core/dataarray.py:3494-3495` — mirroring the `differentiate` wording at `xarray/core/dataarray.py:3436-3437`, and leave the doctest at `xarray/core/dataarray.py:3511-3529` byte-identical. <!-- step-4 -->
- [ ] 5. Align the `Dataset.integrate` docstring: change `coord: str, or sequence of str` at `xarray/core/dataset.py:5975` to the `hashable, or sequence of hashable` form used by `DataArray`, and add `DataArray.differentiate` alongside the existing `DataArray.integrate` entry in the `See also` block at `xarray/core/dataset.py:5985-5988`. Docs only — no signature change. <!-- step-5 -->
- [ ] 6. Change `method("integrate", dim="x")` to `method("integrate", coord="x")` at `xarray/tests/test_units.py:3684`, matching the `Dataset` counterpart already written that way at `xarray/tests/test_units.py:5186`. <!-- step-6 -->
- [ ] 7. Extend `test_integrate` in `xarray/tests/test_dataset.py:6554-6604`: assert `da.integrate(coord="x")` equals `da.integrate("x")`, assert `pytest.warns(FutureWarning)` around `da.integrate(dim="x")` with the result still equal to `expected_x`, and assert `ValueError` for both-supplied and neither-supplied. Place these after the existing `da.integrate("x2d")` check at `xarray/tests/test_dataset.py:6603-6604`. <!-- step-7 -->
- [ ] 8. Add a `Deprecations` section to the unreleased `v0.17.0` block in `doc/whats-new.rst` between `Breaking changes` (`doc/whats-new.rst:23`) and `New Features` (`doc/whats-new.rst:46`), following the heading style of the `v0.16.2` one at `doc/whats-new.rst:133`, and reference `:issue:`3993``. <!-- step-8 -->

The reconciliation contract Step 2 encodes, stated exactly once:

```python
def integrate(
    self,
    coord: Union[Hashable, Sequence[Hashable]] = None,
    datetime_unit: str = None,
    *,
    dim: Union[Hashable, Sequence[Hashable]] = None,
) -> "DataArray":
    # (coord, dim) -> outcome
    #   (given, None)  -> use coord
    #   (None,  given) -> FutureWarning, coord = dim
    #   (given, given) -> ValueError, ambiguous
    #   (None,  None)  -> ValueError, coord is required
```

## 7. Tools Required

- `python` with the repo installed in development mode (`pip install -e .`).
- `pytest` for the unit suites and the `--doctest-modules` run.
- Optional: `pint` and `dask`, which gate `xarray/tests/test_units.py` and the `dask=True` parametrisations of `test_integrate`; without them those cases skip rather than fail.

## 8. Approval Points

none — the change is confined to one public method's parameter names plus its tests and release notes, so `/geniro:implement` may run start-to-finish.

## 9. Validation

Public seam: the `DataArray.integrate` and `Dataset.integrate` methods themselves — that is the surface the issue is about, and the surface every user calls. Prior art for the test shape is `xarray/tests/test_dataset.py::test_integrate` (`xarray/tests/test_dataset.py:6554`), which already exercises both classes side by side and is the natural home for the new assertions.

Criteria:

1. `da.integrate(coord="x")` returns the same result as `da.integrate("x")` for the 1-D, multi-coordinate (`("y", "x")`), and datetime paths.
   verify: `python -m pytest xarray/tests/test_dataset.py -k "integrate or trapz" -q`
2. `da.integrate(dim="x")` still computes the correct result and raises exactly one `FutureWarning`; `da.integrate(coord="x", dim="x")` and `da.integrate()` each raise `ValueError`. Covered by the Step 7 additions in the same run as criterion 1.
   verify: `python -m pytest xarray/tests/test_dataset.py::test_integrate -q`
3. The units suite, whose `DataArray` case now passes `coord=`, still passes (or skips cleanly when `pint` is absent).
   verify: `python -m pytest xarray/tests/test_units.py -k "integrate" -q`
4. Positional callers are untouched — the sparse suite calls `do("integrate", "x")` at `xarray/tests/test_sparse.py:353`.
   verify: `python -m pytest xarray/tests/test_sparse.py -k "integrate" -q`
5. The reworded docstrings still produce their documented output under the CI doctest run (`.github/workflows/ci-additional.yaml:160`).
   verify: `python -m pytest --doctest-modules xarray/core/dataarray.py xarray/core/dataset.py -q`
6. No in-repo call site still passes `dim=` to `integrate`.
   verify: `bash -c '! grep -rn "integrate(dim=\|\"integrate\", dim=" xarray doc asv_bench properties'`
7. Full core-object suites stay green, guarding against an accidental signature break in a neighbouring method.
   verify: `python -m pytest xarray/tests/test_dataarray.py xarray/tests/test_dataset.py -q`

## 10. Rollback-Recovery

Revert the single commit. No data migration, no schema, no persisted state is involved: every edit is a parameter name, a warning branch, a docstring, a test, or a release note. Because the old spelling `integrate(dim=...)` keeps working through the deprecation branch, a revert cannot strand a downstream caller written against either spelling. If only the warning proves problematic (for example, a downstream suite runs with `-W error`), the narrower recovery is to drop the `warnings.warn` call while keeping the `dim` → `coord` reconciliation, which preserves the new API without emitting anything.

## 11. Done Condition

`DataArray.integrate(coord=...)`, `Dataset.integrate(coord=...)`, `DataArray.differentiate(coord=...)`, and `Dataset.differentiate(coord=...)` all name the argument `coord`; `DataArray.integrate(dim=...)` still returns the correct result while raising a `FutureWarning`; and every `verify:` command in section 9 exits zero.

## Considered Alternatives

**A. Hard rename, no deprecation cycle.** Rename `dim` → `coord` and let `integrate(dim=...)` raise `TypeError`. Simplest diff and the cleanest end state. Rejected: `integrate` has shipped with `dim` since v0.11 (`doc/whats-new.rst:1691-1692`), the issue explicitly asks whether a cycle is needed, and a keyword-only alias costs about eight lines. The hard rename remains the correct *follow-up*, once the warning has shipped in a release.

**B. Add a symmetric `dim` alias to `Dataset.integrate` too.** Rejected: `Dataset.integrate` has always taken `coord` (`xarray/core/dataset.py:5966`). Adding a deprecated alias there would introduce a spelling that never existed, then deprecate it — widening the very inconsistency this task closes.

**C. Build a generic `_deprecate_kwarg` decorator.** The helpers in `xarray/core/utils.py:41-60` alias whole callables, not individual keywords, so a decorator would be new machinery. Rejected: one call site does not justify a new abstraction, and an inline branch reads more clearly at the point where the ambiguity has to be resolved. Revisit if a second keyword rename lands.

**D. Emit `DeprecationWarning` rather than `FutureWarning`.** Technically the more precise category for an API removal. Rejected: Python hides `DeprecationWarning` by default outside `__main__`, so end users — the audience for this notice — would never see it, and every comparable xarray deprecation uses `FutureWarning` (`xarray/core/utils.py:45-48`, `xarray/core/dataset.py:5630-5636`, `xarray/core/computation.py:1063-1080`).
