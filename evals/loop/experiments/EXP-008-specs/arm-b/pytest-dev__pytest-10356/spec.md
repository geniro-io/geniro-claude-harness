---
tier: T1.5
producer: plan
schema-version: 1
branch: mro-class-marks
timestamp: 2026-08-10T07:22:51Z
geniro_kind: design-doc
geniro_schema_version: m5-v2
task_slug: pytest-mro-class-marks
topic: Class-level pytest marks are resolved by plain attribute lookup, so a test class inheriting from two marked base classes silently keeps only one base's marks.
mode: DESIGN_DOC
effort_tier: small
lifecycle: draft
budget:
  max_files_to_edit: 5
  max_lines_changed: 140
  time_budget: "4h"
checkpoints:
  - step_anchor: step-4
    name: "Marker resolution merged over the MRO"
  - step_anchor: step-8
    name: "Marker test suites green"
forbidden_actions:
  - "do NOT change the public shape of pytest.mark / MarkDecorator / Mark — the fix is confined to how stored marks are READ back off an object"
  - "do NOT make Mark hashable or add __hash__ to it — kwargs is a plain dict and hashing it raises TypeError at runtime"
  - "do NOT collect marks for a class by calling getattr(cls, 'pytestmark') as well as walking the MRO — the two overlap and double-count"
approval_required_for: []
tools_required: ["python", "pip", "pytest", "tox", "pre-commit"]
---

<!-- geniro:design-doc -->

# Consider the MRO when collecting class-level pytest marks

## 1. Objective

Collect a test class's marks from every class in its MRO so that a class inheriting from several marked base classes carries all of their marks, not just the first base's.

## 2. Scope — Included

- `src/_pytest/mark/structures.py:358-363` — `get_unpacked_marks` gains a class-aware branch that merges each MRO entry's own `pytestmark` instead of relying on plain attribute lookup.
- `src/_pytest/mark/structures.py:383-391` — `store_mark` stops copying inherited marks into the decorated class's own `pytestmark` list, so the MRO merge is the single place inheritance is resolved.
- `testing/test_mark.py` `TestFunctional` (`testing/test_mark.py:471`) — new cases for multiple inheritance and for the diamond (no duplicate marks).
- `changelog/` — one newsfragment, per `changelog/README.rst:13-24`.
- `doc/en/example/markers.rst:303-312` — one sentence stating that class marks accumulate across base classes.

## 3. Scope — Excluded

- Module-level and function-level `pytestmark` resolution. `Module`/`Package` nodes (`src/_pytest/python.py:524`, `src/_pytest/python.py:661`) hand a module object to `get_unpacked_marks`, and `Function.__init__` (`src/_pytest/python.py:1717`) hands a function object; neither is a `type`, so both keep today's `getattr` path unchanged.
- `Node.own_markers` ordering and the `iter_markers` / `get_closest_marker` traversal (`src/_pytest/nodes.py:371-383`). Only the contents of a `Class` node's `own_markers` change; how nodes are walked does not.
- `Node.add_marker` (`src/_pytest/nodes.py:339-361`) — runtime marker addition never touches `pytestmark`.
- `_get_legacy_hook_marks` (`src/_pytest/config/__init__.py:354`) — it reads `pytestmark` off hook *methods* (functions, not classes), so the class branch does not reach it.
- Making `Mark` hashable or introducing value-equality deduplication of marks.
- An `AUTHORS` entry — contributor-specific, not part of the behavior change.

## 4. Assumptions

- `src/_pytest/mark/structures.py:391` (`obj.pytestmark = [*get_unpacked_marks(obj), mark]`) is the only place inside pytest that writes `pytestmark`; every other appearance in `src/` reads it. Verified: `pytestmark` occurs in `src/` only at `src/_pytest/mark/structures.py:360,391`, `src/_pytest/python.py` via `get_unpacked_marks`, `src/_pytest/config/__init__.py:354`, and `src/_pytest/terminal.py:1345-1351` (a keyword-name string check).
- `get_unpacked_marks` is reached with a class argument from exactly one site: the `PyobjMixin.obj` property at `src/_pytest/python.py:310-317`, guarded by `_ALLOW_MARKERS` (`src/_pytest/python.py:281` true for collectors, `src/_pytest/python.py:1687` false for `Function`). So a class's marks are unpacked once per collected `Class` node and memoized in `self._obj`.
- `Mark` is `@attr.s(frozen=True)` with `kwargs: Mapping[str, Any]` (`src/_pytest/mark/structures.py:193-201`); at runtime `kwargs` is a `dict`, so attrs' generated `__hash__` raises `TypeError` for any mark carrying keyword arguments. Any deduplication must therefore key on object identity, never on `set`/`dict` membership of `Mark` values.
- For single inheritance the observable mark order today is base-first — `store_mark` prepends the already-visible (inherited) marks before the newly applied one. `reversed(cls.__mro__)` reproduces that order exactly, so existing expectations such as `testing/test_mark.py:541-562` (`a`, `b`, `c` from `Base` → `Base2` → `Test1`) are preserved.
- Python's MRO lists each ancestor exactly once, so a diamond contributes a shared base's marks once by construction — no extra deduplication is needed for that shape.
- A class-level `pytestmark` may be a single `MarkDecorator` rather than a list (`testing/test_collection.py:889-899`), so the per-class read must keep the "wrap a non-list in a list" normalization.
- `List`, `Set`, and `Union` are already imported in `src/_pytest/mark/structures.py:9,16,21`; the change needs no new imports.

## 5. Risks

- **Medium — a subclass can no longer shadow its bases' marks.** Today `class Sub(Base): pytestmark = [...]` replaces whatever `Base` declared; after the change `Sub` carries both. This is the intended semantic, but it is a behavior change for any suite that relied on shadowing to *remove* an inherited mark (e.g. an inherited `skip`). Mitigation: land it as a user-visible changelog entry describing the merge, and state in `doc/en/example/markers.rst:303-312` that class marks accumulate.
- **Medium — a `pytestmark` supplied by a metaclass descriptor stops being seen.** The workaround circulating for this bug defines `pytestmark` as a metaclass property backed by `_pytestmark`; reading `cls.__dict__["pytestmark"]` finds nothing there, so such a class would collect zero marks instead of too few. Mitigation: the workaround exists only to compensate for this bug — say so in the changelog so affected users delete it. Do not add a `getattr` fallback (see §Considered Alternatives C).
- **Low-medium — third-party code reading `SomeClass.pytestmark` directly sees fewer marks.** With `store_mark` no longer copying inherited marks in, a decorated subclass's own list holds only its own marks. Mitigation: the merged view remains available through the supported entry point, `get_unpacked_marks(cls)`; the attribute was never documented as pre-merged.
- **Low — duplicate marks when user code copies a base's marks into a subclass** (`class Sub(Base): pytestmark = Base.pytestmark + [pytest.mark.x]`). Both classes' lists then hold the *same* `Mark` objects, and without a guard `parametrize` would be applied twice, multiplying the test count. Mitigation: identity-keyed deduplication inside the class branch (step 3).
- **Low — mark order across sibling bases.** `reversed(cls.__mro__)` puts the *last* base first, so for `class T(Foo, Bar)` with the same mark name on both, `get_closest_marker` resolves to `Foo`'s (nearest to the end of the merged list is `Foo`… concretely the merged order is `Bar`'s marks then `Foo`'s). Assert mark *presence* by set in the new tests rather than pinning sibling order, so the test does not freeze an arbitrary tie-break.

## 6. Steps

- [ ] 1. Branch from the current checkout (detached at `3c15349`) and install the tree in editable mode with test extras so `python -m pytest testing/` runs. <!-- step-1 -->
- [ ] 2. In `src/_pytest/mark/structures.py:358-363`, split the body of `get_unpacked_marks` into a class branch (`isinstance(obj, type)`) and the existing non-class branch, keeping the non-list normalization from `src/_pytest/mark/structures.py:361-362` applied per source list so a bare `MarkDecorator` still works (`testing/test_collection.py:889-899`). <!-- step-2 -->
- [ ] 3. Give the class branch its MRO merge and identity-keyed deduplication, and add the `consider_mro` switch the writer needs (`src/_pytest/mark/structures.py:358-363`): <!-- step-3 -->

  ```python
  def get_unpacked_marks(obj: object, *, consider_mro: bool = True) -> List[Mark]:
      """Obtain the unpacked marks that are stored on an object.

      If obj is a class and consider_mro is true, return marks applied to
      all base classes in MRO order (bases first), deduplicated by identity.
      """
      if isinstance(obj, type):
          if not consider_mro:
              mark_lists = [obj.__dict__.get("pytestmark", [])]
          else:
              mark_lists = [
                  x.__dict__.get("pytestmark", []) for x in reversed(obj.__mro__)
              ]
          mark_list = []
          for item in mark_lists:
              if isinstance(item, list):
                  mark_list.extend(item)
              else:
                  mark_list.append(item)
          # Identity, not equality: Mark carries a dict in `kwargs` and is
          # therefore unhashable at runtime.
          seen: Set[int] = set()
          result: List[Mark] = []
          for mark in normalize_mark_list(mark_list):
              if id(mark) not in seen:
                  seen.add(id(mark))
                  result.append(mark)
          return result
      mark_list = getattr(obj, "pytestmark", [])
      if not isinstance(mark_list, list):
          mark_list = [mark_list]
      return list(normalize_mark_list(mark_list))
  ```

  Keep deduplication inside the class branch only — modules and functions have no inheritance channel that can produce the duplicate, and applying it there would change unrelated behavior.
- [ ] 4. Change `store_mark` to write only the decorated object's own marks: `obj.pytestmark = [*get_unpacked_marks(obj, consider_mro=False), mark]` (`src/_pytest/mark/structures.py:383-391`), and update the comment above it so it explains that inheritance is resolved on read, not on write. <!-- step-4 -->
- [ ] 5. Add `test_mark_decorator_multiple_baseclasses_merged` to `TestFunctional` next to the existing single-chain case (`testing/test_mark.py:541-562`): two independently marked bases (`@pytest.mark.a class Foo`, `@pytest.mark.b class Bar`), a `class TestDings(Foo, Bar)` holding the test, asserted with `self.assert_markers(items, test_dings=("a", "b"))` (`testing/test_mark.py:694-704`). <!-- step-5 -->
- [ ] 6. Add a diamond case in the same class: a marked common `Base`, two marked intermediate classes, one leaf test class — assert with `len([m for m in item.iter_markers() if m.name == "a"]) == 1` (a set comparison via `assert_markers` at `testing/test_mark.py:694-704` cannot see a duplicate), plus that all three names are present. <!-- step-6 -->
- [ ] 7. Add a regression case pinning that a mark still does not leak upward or sideways, mirroring `testing/test_mark.py:492-511` and `testing/test_mark.py:513-539` but with the marked class as one of two bases. <!-- step-7 -->
- [ ] 8. Run the marker-sensitive suites and reconcile any expectation that encoded the old shadowing: `testing/test_mark.py`, `testing/test_collection.py:871-899`, `testing/python/metafunc.py:968-982`, `testing/test_skipping.py`, `testing/test_unittest.py:439-450`. <!-- step-8 -->
- [ ] 9. Run the full `testing/` suite plus `pre-commit run --all-files` (flake8 + mypy are configured at `.pre-commit-config.yaml:33-63`; the new `Set[int]` local needs no import beyond `src/_pytest/mark/structures.py:16`). <!-- step-9 -->
- [ ] 10. Add `changelog/<issue>.bugfix.rst` in the past/present tense with a trailing period, per `changelog/README.rst:13-24`: marks from all base classes of a test class are now collected, using the MRO. <!-- step-10 -->
- [ ] 11. Add one sentence after `doc/en/example/markers.rst:303-312` stating that a class's marks accumulate across its base classes in MRO order. <!-- step-11 -->

## 7. Tools Required

- `python` (3.7+, per the repo's `setup.cfg`) and `pip` for an editable install of the checkout.
- `pytest` — the suite runs itself; `python -m pytest testing/`.
- `pre-commit` for the configured flake8 + mypy hooks (`.pre-commit-config.yaml:33-63`).
- `tox` optionally, for the documentation build (`tox -e docs`) if the changelog preview is wanted.

## 8. Approval Points

none — the change is confined to pytest's own source and tests, and `/geniro:implement` may run start-to-finish.

## 9. Validation

Public seam: pytest's own collection API, entered exactly as the neighbouring cases in `testing/test_mark.py::TestFunctional` do — `pytester.inline_genitems(...)` to build items, then `item.iter_markers()` / `item.get_closest_marker(...)` to observe the resolved marks. Prior art for the assertion helper is `TestFunctional.assert_markers` (`testing/test_mark.py:694-704`); prior art for the shape of these cases is `test_mark_decorator_baseclasses_merged` (`testing/test_mark.py:541-562`).

Criteria:

- A test method on `class TestDings(Foo, Bar)`, where `Foo` and `Bar` are independently decorated, reports both marks — the issue's reproduction.
  `verify: python -m pytest testing/test_mark.py::TestFunctional -q`
- A diamond (`Base` marked, two marked children, one leaf) yields each mark exactly once — no `parametrize` doubling and no duplicated `skipif`.
  `verify: python -m pytest testing/test_mark.py::TestFunctional -q`
- Existing inheritance semantics hold: a subclass's mark does not propagate to its base or to a sibling subclass, and the single-inheritance chain still yields base-first order.
  `verify: python -m pytest testing/test_mark.py -q`
- Module-level and function-level `pytestmark`, including the single-`MarkDecorator` form and class-level `parametrize`, are unaffected.
  `verify: python -m pytest testing/test_collection.py testing/python/metafunc.py testing/test_skipping.py testing/test_unittest.py -q`
- No regression anywhere else in the suite.
  `verify: python -m pytest testing/ -q`
- Lint and types clean.
  `verify: pre-commit run --all-files`

Prose-only criterion: the changelog newsfragment reads as user-facing release-note prose (`changelog/README.rst:3-11`) — a judgment call no command settles.

## 10. Rollback-Recovery

Pure source change: no schema, no data, no persisted state, no feature flag. `git revert` of the single commit restores the previous resolution exactly, because both edited functions are self-contained and nothing serializes their output. Note the ordering constraint if reverting piecemeal: the `get_unpacked_marks` MRO merge (step 3) and the `store_mark` `consider_mro=False` write (step 4) must move together — keeping the merge while restoring the copying writer double-counts a base's marks in every subclass, and the identity deduplication would be the only thing masking it.

## 11. Done Condition

The issue's reproduction collects both `foo` and `bar` on `test_dings`, the new multiple-inheritance and diamond cases pass, the full `testing/` suite is green with no expectation loosened to accommodate the change, and a changelog newsfragment plus the one-sentence doc note are in the diff.

## Considered Alternatives

**A. Leave resolution as-is and document the metaclass workaround.** Rejected: it pushes a metaclass onto every user who inherits from more than one marked base, and the marks it recovers are still invisible to any tool reading `get_unpacked_marks`. It also does not explain itself at the call site — the bug reappears the moment someone writes a base class without the metaclass.

**B. Merge over the MRO at the node level, in `PyobjMixin.obj` (`src/_pytest/python.py:310-317`).** Rejected: `store_mark`'s copy-up would stay in place, so each subclass's own list would still contain its bases' marks and the node-level merge would double-count them; and the fix would not reach any other caller of `get_unpacked_marks`. `src/_pytest/mark/structures.py:358-363` is the single choke point where "what marks does this object carry" is answered.

**C. Keep `store_mark` copying inherited marks and rely on identity deduplication alone.** Rejected: correctness would then hinge on the same `Mark` instance being shared across class dictionaries — true today only because `store_mark` splices references. Any code path that rebuilds a mark (a plugin re-wrapping a `MarkDecorator`, a copy of the list) silently reintroduces duplicates. It also leaves each subclass's `pytestmark` a growing transcript of its ancestors, which is what makes the attribute misleading to read.

**D. Read each MRO entry with a `getattr` fallback when its metaclass supplies `pytestmark`.** Rejected: it recovers the metaclass-property workaround (§Risks) at the cost of a descriptor that may build fresh `Mark` objects on each access, which identity deduplication cannot collapse — turning a rare silent under-count into a rare silent over-count, including duplicated `parametrize`. The workaround exists only because of this bug; retiring it in the changelog is the cheaper contract.
