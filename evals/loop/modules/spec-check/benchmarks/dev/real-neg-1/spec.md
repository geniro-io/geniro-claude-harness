---
tier: T1.5
producer: plan
schema-version: 1
branch: fix-mro-marks
timestamp: 2026-08-10T00:00:00Z
geniro_kind: design-doc
geniro_schema_version: m5-v2
task_slug: mro-aware-class-marks
topic: Collect pytest marks from every class in a test class's MRO instead of the first one that defines pytestmark
mode: DESIGN_DOC
effort_tier: small
lifecycle: draft
budget:
  max_files_to_edit: 6
  max_lines_changed: 200
  time_budget: null
checkpoints:
  - step_anchor: step-2
    name: "Mark storage and collection split; existing mark suite green"
  - step_anchor: step-5
    name: "Regression tests for multiple inheritance green"
forbidden_actions:
  - "do NOT change the public signature of pytest.mark / MarkDecorator — the fix stays inside mark collection"
  - "do NOT make mark collection walk the MRO for non-class objects (functions, modules); their marks are single-attribute by definition"
  - "do NOT deduplicate marks by hashing — Mark.kwargs is a Mapping and a Mark carrying dict kwargs is not hashable"
approval_required_for: []
tools_required: ["python", "pip", "tox", "pre-commit"]
---

<!-- geniro:design-doc -->

# MRO-aware mark collection for test classes

## 1. Objective

Collect a test class's pytest marks from every class in its MRO, so a class inheriting from two separately-marked base classes carries both sets of marks.

## 2. Scope — Included

- `src/_pytest/mark/structures.py` — `get_unpacked_marks` (`src/_pytest/mark/structures.py:358`) and `store_mark` (`src/_pytest/mark/structures.py:383`).
- `testing/test_mark.py` — new regression tests in `TestFunctional` (`testing/test_mark.py:471`).
- `changelog/` — one `<issue>.bugfix.rst` newsfragment, per the naming rule in `changelog/README.rst:14`.
- `doc/en/reference/reference.rst:1024` and `doc/en/example/markers.rst:304` — one sentence each stating that class marks are unioned across base classes.
- `AUTHORS` — contributor line, per the repo's PR checklist.

## 3. Scope — Excluded

- Marks on functions and modules. `Function.__init__` calls the same collector on a function object (`src/_pytest/python.py:1717`) and `Module` calls it on a module object (`src/_pytest/python.py:314`); neither is a class, so both keep today's single-attribute semantics.
- `_get_legacy_hook_marks` (`src/_pytest/config/__init__.py:354`), which reads `pytestmark` off a hook *routine*, never a class.
- Mark *precedence* when two base classes apply the same mark name with different arguments — `get_closest_marker` semantics (`src/_pytest/nodes.py:392`) are left exactly as they are; see §5.
- `MarkDecorator` / `Mark` public API, marker expression evaluation (`src/_pytest/mark/expression.py`), and `--strict-markers` handling.
- The parametrize path — `normalize_mark_list` stays as-is and its parametrize caller (`src/_pytest/python.py:1150`) is untouched.

## 4. Assumptions

- `get_unpacked_marks` obtains marks with a single `getattr(obj, "pytestmark", [])` (`src/_pytest/mark/structures.py:360`); Python attribute lookup stops at the first MRO entry that defines `pytestmark`, so for `class TestDings(Foo, Bar)` where only `Foo` and `Bar` are decorated, only `Foo`'s marks are returned. Reproduced against a faithful model of lines 358-391: `Foo.pytestmark == ['foo']`, `Bar.pytestmark == ['bar']`, collected on `TestDings` → `['foo']`.
- `store_mark` writes `obj.pytestmark = [*get_unpacked_marks(obj), mark]` (`src/_pytest/mark/structures.py:391`), so decorating a class copies its base classes' marks into the subclass's own `__dict__`. That copy-down is the only reason single-inheritance chains work today, and it means a plain MRO walk over each class's own `__dict__["pytestmark"]` would double-count unless `store_mark` stops copying: for the `Base(a) → Base2(b) → Test1(c)` chain in `testing/test_mark.py:541` the current attribute values are `['a']`, `['a','b']`, `['a','b','c']`, and a reverse-MRO concatenation of those yields `['a','a','b','a','b','c']`.
- `TestDings` in the reproducer has no `pytestmark` key in its own `__dict__` — nothing writes one, because it carries no decorator.
- `get_unpacked_marks` has exactly two call sites in the source tree, both in `src/_pytest/python.py` (imported at `src/_pytest/python.py:66`, called at `src/_pytest/python.py:314` and `src/_pytest/python.py:1717`), and no test imports it (`grep get_unpacked_marks testing/` returns nothing). Widening its signature with a keyword-only parameter therefore touches no other caller.
- `src/_pytest/python.py:314` is the site that puts *class* marks into the node tree: `PyobjMixin.obj` extends `own_markers` when `_ALLOW_MARKERS` is true (default `True` at `src/_pytest/python.py:281`, overridden to `False` only for `FunctionDefinition` at `src/_pytest/python.py:1687`). `Class` and `UnitTestCase` (`src/_pytest/unittest.py:60`) both reach it with `self.obj` bound to a class.
- `Mark` is `@attr.s(frozen=True, auto_attribs=True)` with `kwargs: Mapping[str, Any]` (`src/_pytest/mark/structures.py:194`), so attrs generates `__eq__` but a `Mark` holding dict kwargs raises on `hash()`. Any dedupe must compare with `==` against a list.
- `get_unpacked_marks` currently returns a lazy generator — it returns `normalize_mark_list(mark_list)` (`src/_pytest/mark/structures.py:363`), and `normalize_mark_list` is a `yield`-based generator (`src/_pytest/mark/structures.py:376-380`). Both consumers splat or `extend` it, so switching the return to a concrete `List[Mark]` is compatible.
- A class-level `pytestmark` may legally be a bare `MarkDecorator` rather than a list — documented at `doc/en/example/markers.rst:312` and handled by the `if not isinstance(mark_list, list)` normalization at `src/_pytest/mark/structures.py:361`. The new class branch must apply that same normalization per MRO entry.
- MRO traversal is already an accepted pattern in the collector: `Class._inject_setup_class_fixture`-adjacent code iterates `self.obj.__mro__` at `src/_pytest/python.py:437`.
- `TestFunctional.assert_markers` compares mark names as a `set` (`testing/test_mark.py:703-704`), so it cannot detect duplicated or reordered marks; a duplication regression needs a test that asserts the `own_markers` list directly.
- The four existing tests that pin current inheritance behaviour are `test_merging_markers_deep` (`testing/test_mark.py:472`), `test_mark_decorator_subclass_does_not_propagate_to_base` (`testing/test_mark.py:492`), `test_mark_should_not_pass_to_siebling_class` (`testing/test_mark.py:513`), and `test_mark_decorator_baseclasses_merged` (`testing/test_mark.py:541`). All four must stay green unmodified.

## 5. Risks

- **A class using the metaclass `pytestmark` property workaround loses all its marks. (medium.)** The workaround in the issue defines `pytestmark` as a metaclass property whose setter stores `_pytestmark`; under the new own-`__dict__` read the class's `__dict__` holds `_pytestmark` and never `pytestmark`, so the MRO walk finds nothing. Mitigation: the workaround exists solely to compensate for this bug and becomes unnecessary — say so explicitly in the changelog fragment (step 6) and add a regression test proving the plain, un-metaclassed form now works (step 4), so users have a one-line removal instruction.
- **`SomeClass.pytestmark` stops containing inherited marks. (medium.)** After step 2 the attribute written at `src/_pytest/mark/structures.py:391` holds only the marks applied to that class. Third-party code that reads `cls.pytestmark` directly to get the effective set changes behaviour. Mitigation: this is the semantically correct split (attribute = declared here, collection = effective set), the effective set stays available through the public `Item.iter_markers()` seam, and the changelog fragment names the change.
- **Same-name marks from sibling bases resolve in reverse-MRO order, not MRO order. (low.)** Walking `reversed(obj.__mro__)` puts the *least* derived base first, and `iter_markers_with_node` yields a node's `own_markers` in list order (`src/_pytest/nodes.py:379-382`), so `get_closest_marker` (`src/_pytest/nodes.py:392`) returns the base-most of two same-named class marks. Mitigation: none needed — that is already today's behaviour, since `store_mark`'s copy-down also puts base marks first; keep the ordering identical so `test_mark_closest` (`testing/test_mark.py:564`) and `test_mark_decorator_baseclasses_merged` (`testing/test_mark.py:541`) are unaffected.
- **Newly-collected marks change outcomes in unrelated suites. (low.)** A shared marked mixin that was previously shadowed now applies — most visibly for `skip`/`xfail` marks on `unittest` mixin bases collected via `UnitTestCase` (`src/_pytest/unittest.py:60`). Mitigation: step 8 runs `testing/test_unittest.py` and `testing/test_skipping.py` alongside the mark suite before shipping.
- **Duplicated marks if step 1 lands without step 2. (low.)** Per §4, reverse-MRO concatenation over today's copy-down attribute values yields `['a','a','b','a','b','c']`. Mitigation: the two steps are one commit and checkpoint `step-2` gates on the existing mark suite being green.

## 6. Steps

- [ ] 1. Give `get_unpacked_marks` (`src/_pytest/mark/structures.py:358`) a keyword-only `consider_mro: bool = True` and a class branch: when `isinstance(obj, type)`, build the mark list from `reversed(obj.__mro__)` reading each class's own `vars(klass).get("pytestmark", [])` (only `obj`'s own entry when `consider_mro` is false), applying the existing non-list normalization from `src/_pytest/mark/structures.py:361` to each entry; non-class objects keep the `getattr` path verbatim. Return `list(normalize_mark_list(...))` and update the annotation from `Iterable[Mark]` to `List[Mark]`. <!-- step-1 -->
- [ ] 2. Change `store_mark` to `obj.pytestmark = [*get_unpacked_marks(obj, consider_mro=False), mark]` (`src/_pytest/mark/structures.py:391`) so a class's attribute records only the marks declared on that class, and update its docstring (`src/_pytest/mark/structures.py:384-387`) to state that inherited marks are resolved at collection time. <!-- step-2 -->
- [ ] 3. Re-read the two consumers — `src/_pytest/python.py:314` and `src/_pytest/python.py:1717` — and confirm each still receives an iterable it only `extend`s; no edit expected, and none should be made to `normalize_mark_list` (`src/_pytest/mark/structures.py:366`). <!-- step-3 -->
- [ ] 4. Add `test_mark_decorator_baseclasses_merged_mro` to `TestFunctional` next to `testing/test_mark.py:541`: two bases marked `a` and `b` respectively, a test class inheriting from both, asserting via `assert_markers` (`testing/test_mark.py:694`) that the test gets both. Include a second case where the diamond shares a common marked base, to pin that the shared mark appears. <!-- step-4 -->
- [ ] 5. Add a duplication/ordering test that asserts the collected list rather than a set — `assert_markers` collapses to a set at `testing/test_mark.py:703` — over the `Base(a) → Base2(b) → Test1(c)` shape from `testing/test_mark.py:541`, asserting `[m.name for m in item.iter_markers()]` contains each of `a`, `b`, `c` exactly once. <!-- step-5 -->
- [ ] 6. Add `changelog/<issue>.bugfix.rst` following `changelog/README.rst:14-26` (past/present tense, ends with a period): marks on all base classes are now collected, and note that the metaclass `pytestmark` workaround can be removed (§5 risk 1). <!-- step-6 -->
- [ ] 7. Add one sentence to the `pytestmark` reference entry (`doc/en/reference/reference.rst:1028`) and to the class-level example (`doc/en/example/markers.rst:304`) stating that a class's marks are the union of marks declared on it and on every base class; add the contributor line to `AUTHORS` in alphabetical order. <!-- step-7 -->
- [ ] 8. Run the mark suite plus the collection/unittest/skipping suites named in §9, then `pre-commit run --all-files` for the mypy hook (`.pre-commit-config.yaml:60-63`) since step 1 changes a public annotation. <!-- step-8 -->

## 7. Tools Required

- `python` ≥3.7 with the repo installed in editable mode (`pip install -e .`) — `pytest` is not importable in a bare checkout and `src/_pytest/mark/__init__.py:9` needs `attr`.
- `pre-commit` for the mypy/flake8 hooks configured in `.pre-commit-config.yaml`.
- `tox` (optional) for `tox -e linting` and a multi-interpreter run; `tox.ini:5-19` lists the envs.

## 8. Approval Points

none — the change is contained to mark collection and its tests; `/geniro:implement` may run start to finish.

## 9. Validation

Public seam: `_pytest.nodes.Node.iter_markers()` / `get_closest_marker()` on collected items, reached through `Pytester.inline_genitems`. Prior art for exactly this shape: `test_mark_decorator_baseclasses_merged` (`testing/test_mark.py:541`) and `test_mark_should_not_pass_to_siebling_class` (`testing/test_mark.py:513`). No new seam is introduced — `get_unpacked_marks` stays internal and is exercised only through collection.

- A class inheriting from two independently marked base classes yields an item carrying both marks.
  `verify: python -m pytest testing/test_mark.py -q -k "baseclasses_merged or mro"`
- Existing inheritance semantics are unchanged: base marks still propagate down a single chain, marks still do not leak to sibling classes or back to a base, and nested classes still inherit.
  `verify: python -m pytest testing/test_mark.py -q`
- No mark is collected twice and class-mark order (base-most first) is preserved, so `get_closest_marker` still returns the class-level mark it returns today.
  `verify: python -m pytest testing/test_mark.py -q -k "closest or merging_markers"`
- Collection, `unittest` integration, and skip/xfail evaluation are unaffected by the newly-visible base-class marks (§5 risk 4).
  `verify: python -m pytest testing/python/collect.py testing/test_unittest.py testing/test_skipping.py -q`
- Full suite stays green.
  `verify: python -m pytest testing/ -q`
- Types and lint pass with the widened signature and `List[Mark]` return.
  `verify: pre-commit run --all-files`

Prose-only: rendered docs read correctly for the two edited passages — judgment call, no command settles it.

## 10. Rollback-Recovery

Single-commit revert. The change is confined to two functions in `src/_pytest/mark/structures.py` plus additive tests, docs, and a changelog fragment; there is no persisted state, no migration, and no configuration flag. `git revert <sha>` restores the `getattr`-only collector and the copy-down `store_mark` together — reverting only one of the two reintroduces the duplication described in §5 risk 5, so the revert must take the whole commit.

## 11. Done Condition

`python -m pytest testing/ -q` is green with the new multiple-inheritance tests included, the four pre-existing inheritance tests at `testing/test_mark.py:472/492/513/541` pass unmodified, and `pre-commit run --all-files` is clean.

## Considered Alternatives

- **Keep `store_mark` as-is; walk the MRO with `getattr` per class and deduplicate by equality.** Preserves `SomeClass.pytestmark` as the full effective set and keeps the metaclass-property workaround working (§5 risks 1-2 disappear). Rejected: deduplication cannot use a set (`Mark` with dict kwargs is unhashable, `src/_pytest/mark/structures.py:194`), and equality-based dedupe silently collapses marks a user applied deliberately twice — including two identical `parametrize` marks, which would change test generation. The chosen approach needs no dedupe at all because each class stores only its own marks.
- **Fix it in the collector instead — have `PyobjMixin.obj` (`src/_pytest/python.py:314`) walk `self.obj.__mro__` itself.** Rejected: it leaves `get_unpacked_marks` wrong for every other caller, and `store_mark` (`src/_pytest/mark/structures.py:391`) would keep copying base marks down, so the collector would have to dedupe — the same problem, moved one file over.
- **Document the behaviour as intended and close the issue.** Rejected: the collector already resolves xunit fixtures across the MRO (`src/_pytest/python.py:437`), so mark lookup stopping at the first base is an inconsistency inside pytest itself, not a deliberate rule.
