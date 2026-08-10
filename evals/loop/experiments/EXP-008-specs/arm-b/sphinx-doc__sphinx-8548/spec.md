---
tier: T1.5
producer: plan
schema-version: 1
branch: HEAD (detached at dd1615c)
timestamp: 2026-08-10T07:26:24Z
geniro_kind: design-doc
geniro_schema_version: m5-v2
task_slug: autodoc-inherited-attributes
topic: "autodoc :inherited-members: does not pick up data members (attributes) documented in a base class"
mode: DESIGN_DOC
effort_tier: small
lifecycle: draft
budget:
  max_files_to_edit: 8
  max_lines_changed: 300
  time_budget: null
checkpoints:
  - step_anchor: step-3
    name: "Library code complete — enumeration, filtering, and rendering all base-class aware"
  - step_anchor: step-8
    name: "Full test suite green"
forbidden_actions:
  - "do NOT change the public signature of sphinx.ext.autodoc.importer.get_class_members() or the ClassAttribute / ObjectMember constructors — third-party documenters call them"
  - "do NOT widen sphinx.ext.autosummary in this change; its parallel bug is tracked separately"
  - "do NOT edit existing assertions in tests/test_ext_autodoc.py to make new output fit — a changed expectation is a regression until proven otherwise"
approval_required_for: []
tools_required: ["python (CPython 3.5-3.9)", "pip", "pytest", "flake8"]
---

<!-- geniro:design-doc -->

# Base-class-aware attribute documentation for autodoc

## 1. Objective

Make `:inherited-members:` document data members (class attributes and instance attributes) that are defined and documented in a base class, with the base class's own attribute comment as their content.

## 2. Scope — Included

- `sphinx/ext/autodoc/importer.py` — `get_class_members()` (`importer.py:254-318`): member enumeration gains an MRO-walking pass over each base class's own module analyzer.
- `sphinx/ext/autodoc/__init__.py` — `Documenter.filter_members.is_filtered_inherited_member()` (`__init__.py:669-680`): recognise an attribute documented in a base class's `__init__` as *defined* in that class.
- `sphinx/ext/autodoc/__init__.py` — `AttributeDocumenter.get_doc()` (`__init__.py:2361-2373`): fall back to the MRO attribute-comment lookup that already exists at `__init__.py:2163-2181`.
- Test fixtures under `tests/roots/test-ext-autodoc/target/` — one new same-module fixture, one new cross-module fixture, one addition to `target/inheritance.py`.
- `tests/test_ext_autodoc.py` — new test functions.
- `CHANGES` — one line under `Bugs fixed` for release 3.4.0 (`CHANGES:53-58`).

## 3. Scope — Excluded

- `sphinx/ext/autosummary` — `generate.py:274-275` and `__init__.py:693` key attribute docs the same way and carry the same latent bug. Fixing them changes stub generation and the autosummary test corpus; out of scope here.
- `sphinx.ext.autodoc.importer.get_object_members()` (`importer.py:180-241`) — reached only through `Documenter.get_object_members()`, which is deprecated and warns (`__init__.py:632-634`, `CHANGES:19`). Leave it as-is; no behavior parity is owed to a deprecated path.
- `DataDocumenter` / module-level data (`__init__.py:1839-1915`). Modules have no MRO; the reported defect is class-scoped.
- `autodoc_inherit_docstrings` semantics. This change inherits attribute *comments*, which that config has never governed (it governs `__doc__` lookup inside `sphinx.util.inspect.getdoc`, `sphinx/util/inspect.py:891-917`).
- Any change to `ObjectMember`'s field set (`__init__.py:261-284`).

## 4. Assumptions

- `analyzer.attr_docs` keys are `(qualname-of-the-owning-class, attrname)`: `VariableCommentPicker.add_variable_comment()` builds the key from `get_qualname_for()` (`sphinx/pycode/parser.py:242-251`, `271-275`), which returns the AST class-nesting context. A comment written in `Base.__init__` is therefore keyed `('Base', 'attr')` and can never match a subclass's namespace.
- For a class, the analyzer handed to `get_class_members()` is always the analyzer of the *defining* module: `ClassDocumenter.generate()` deliberately drops `real_modname` (`__init__.py:1672-1681`) and `Documenter.get_real_modname()` falls back to `self.object.__module__`. So a base class living in another module is unreachable from the passed-in analyzer by construction, and only a per-class `ModuleAnalyzer.for_module(cls.__module__)` lookup reaches it.
- `ClassAttribute.docstring` (`importer.py:244-251`) has exactly one consumer chain: `ClassDocumenter.get_object_members()` (`__init__.py:1595-1606`) → `ObjectMember.docstring` → the `has_doc` hack in `filter_members` (`__init__.py:715-719`). Nothing renders it, so populating it changes *keep* decisions only.
- A class documented under an alias never reaches `get_class_members()`: `ClassDocumenter.import_object()` sets `doc_as_attr` when `objpath[-1] != object.__name__` (`__init__.py:1412-1421`) and `document_members()` returns immediately in that case (`__init__.py:1667-1670`). Keying the new pass on `cls.__qualname__` instead of `'.'.join(objpath)` therefore cannot regress alias output.
- `inherited_members_option(None)` returns the string `'object'` (`__init__.py:119-124`). With a bare `:inherited-members:`, `is_filtered_inherited_member()` walks the MRO and returns `True` at `object` for any member it did not first find in some `cls.__dict__` or `cls.__annotations__` — which is exactly every instance attribute. This is the reason enumeration alone does not fix the defect.
- `getdoc(value, attrgetter, allow_inherited=False, ...)` returns `attrgetter(value, '__doc__', None)` (`sphinx/util/inspect.py:891-917`), i.e. the *type's* docstring for a plain value such as `0`. So an inherited attribute that survives filtering renders `int([x]) -> integer …` unless `get_doc()` returns the base-class comment first.
- The uninitialized-instance-attribute import path already handles inheritance: `UninitializedInstanceAttributeMixin.import_object()` → `is_uninitialized_instance_attribute()` → `get_attribute_comment()` walks `inspect.getmro(parent)` (`__init__.py:2163-2215`). Once a base-class instance attribute is enumerated as a member, `autoattribute` resolves it without a new import path.
- `ModuleAnalyzer.for_module()` caches both successes and `PycodeError` failures keyed by module name (`sphinx/pycode/__init__.py:110-128`), so per-MRO-class lookups are cheap after the first, including for `builtins`/C extensions that have no source.
- Test environment: CPython 3.5-3.9 (`setup.py:245`), `pip install -e .[test]`. The checked-out `sphinx/pycode/parser.py` uses `ast.Str`, removed in Python 3.12+, so the suite cannot be run on a newer interpreter.

## 5. Risks

- **Comment now beats the value's `__doc__` for inherited attributes** (medium). `AttributeDocumenter.get_doc()` consulting the MRO comment first changes output for any inherited attribute whose *value* has a meaningful docstring and whose *name* is commented somewhere in the MRO. Mitigation: the same-class case is untouched — `Documenter.add_content()` finds the key and sets `no_docstring=True` before `get_doc()` is ever called (`__init__.py:596-608`) — and precedence matches what a same-class comment already does. Cover the override case (base commented, subclass re-documented) with an assertion.
- **`:meta private:` inside an attribute comment starts taking effect** (low). Populating `ClassAttribute.docstring` feeds `extract_metadata(doc)` in `filter_members` (`__init__.py:721-729`) where previously `doc` was `None` for such members. No fixture uses metadata in an attribute comment (`tests/roots/test-ext-autodoc/target/private.py` carries it only in function docstrings), and the new behavior is the documented intent of `:meta private:`.
- **`:inherited-members: <Class>` semantics change for instance attributes** (medium). They are currently never emitted; after the change they are emitted and then subject to the cutoff class. Mitigation: assert the cutoff explicitly in a test, mirroring `test_autodoc_inherited_members_Base` (`tests/test_ext_autodoc.py:629-638`).
- **Per-class analyzer lookups in a hot loop** (low). `filter_members` runs once per member and would perform an MRO analyzer walk per member. Mitigation: rely on the `ModuleAnalyzer` cache and keep the walk inside the existing `for cls in self.object.__mro__` loop rather than adding a second one.
- **Fixture edits perturbing existing expectations** (low). `target/inheritance.py` feeds three tests that assert exact or partial *method* lists (`tests/test_ext_autodoc.py:617-638`) plus an attrgetter test (`tests/test_ext_autodoc.py:440-445`); those filter on `'method::'` or use `in`/`not in`, so adding an attribute to `Base` should not disturb them. Confirm by running the file, not by inspection.

## 6. Steps

- [ ] 1. Add a base-class pass to `get_class_members()` in `sphinx/ext/autodoc/importer.py:310-316`, after the existing `analyzer`-scoped block and before `return members`: for each `cls` in `getmro(subject)`, resolve `ModuleAnalyzer.for_module(safe_getattr(cls, '__module__'))`, `analyze()` it, and for every `(ns, name), docstring` in `analyzer.attr_docs` where `ns == safe_getattr(cls, '__qualname__')` — add `ClassAttribute(cls, name, INSTANCEATTR, '\n'.join(docstring))` when `name` is absent from `members`, otherwise fill in `members[name].docstring` when it is `None` (the `dir()` loop at `importer.py:288-298` leaves inherited members with `class_=None` and no docstring). Wrap each class in `try/except (AttributeError, PycodeError)`, mirroring the established walk at `__init__.py:2163-2181`; import `PycodeError` from `sphinx.errors` alongside the existing imports at `importer.py:16-20`. Leave `class_` untouched on members that already exist, so the non-inherited branch at `__init__.py:1604-1606` keeps excluding them. <!-- step-1 -->
- [ ] 2. Add a fourth condition to the MRO loop in `is_filtered_inherited_member()` (`sphinx/ext/autodoc/__init__.py:669-680`), after the `__annotations__` check: resolve `ModuleAnalyzer.for_module(cls.__module__)` and return `False` when `(cls.__qualname__, name)` is in its `attr_docs` — the member is defined in this class, so the walk must stop here instead of falling through to the `object` cutoff. Keep the cutoff test first within each iteration so `:inherited-members: Base` still filters Base's own attributes, and guard with `try/except (AttributeError, PycodeError)`. <!-- step-2 -->
- [ ] 3. Make `AttributeDocumenter.get_doc()` (`sphinx/ext/autodoc/__init__.py:2361-2373`) call `self.get_attribute_comment(self.parent)` first and return `[comment]` when it finds one, before the `INSTANCEATTR` early return and the `autodoc_inherit_docstrings` dance. The method is already in the MRO via `UninitializedInstanceAttributeMixin` (`__init__.py:2163-2181`, mixed in at `__init__.py:2237-2240`); reuse it rather than writing a second walk, and let the redundant `UNINITIALIZED_ATTR` branch at `__init__.py:2221-2227` stand. <!-- step-3 -->
- [ ] 4. Add fixture `tests/roots/test-ext-autodoc/target/instance_variable.py` with `Foo` (two doc-commented instance attributes in `__init__`), `Bar(Foo)` (re-documents one of Foo's attributes and adds a third), and `Baz(Bar)` (empty body) — covering inheritance, multi-level inheritance, and subclass-wins precedence in one module. Model the comment styles on `tests/roots/test-ext-autodoc/target/__init__.py:71-77`. <!-- step-4 -->
- [ ] 5. Add the cross-module fixture `tests/roots/test-ext-autodoc/target/inherited_attributes.py` containing `from target.instance_variable import Bar` and `class Derived(Bar): pass` — the `from target.<mod> import <name>` idiom is already used by `tests/roots/test-ext-autodoc/target/overload2.py:1`. Separately, give `Base` in `tests/roots/test-ext-autodoc/target/inheritance.py:1-11` a doc-commented *class-level* attribute so the existing `Derived` covers the class-attribute half of the defect. <!-- step-5 -->
- [ ] 6. Add test functions to `tests/test_ext_autodoc.py` next to the inherited-members block (`tests/test_ext_autodoc.py:616-638`): (a) `target.instance_variable.Bar` with `{"members": None, "inherited-members": None}` asserts all three attributes appear and that Bar's own comment wins for the re-documented one; (b) `target.instance_variable.Baz` asserts two-level inheritance; (c) `target.inherited_attributes.Derived` asserts the cross-module case; (d) `target.inheritance.Derived` asserts the inherited class attribute renders its base comment and not the value type's docstring; (e) a cutoff case passing `"inherited-members": "Foo"` asserts Foo's attributes are excluded while Bar's remain. Use `do_autodoc()` (`tests/test_ext_autodoc.py:33-45`) and assert on the exact line list where practical, as `test_autodoc_typed_inherited_instance_variables` does (`tests/test_ext_autodoc.py:1659-1718`). <!-- step-6 -->
- [ ] 7. Add one entry under `Bugs fixed` for release 3.4.0 in `CHANGES:53-58`, in the file's existing `* #<issue>: autodoc: …` form, stating that `:inherited-members:` did not document attributes defined in a base class. <!-- step-7 -->
- [ ] 8. Run the autodoc, autosummary and pycode suites, then the full suite, then `flake8` and `isort --check-only` over the two edited library files (`tox.ini:33-53`). Investigate every changed expectation rather than updating it. <!-- step-8 -->

## 7. Tools Required

- CPython 3.5-3.9 with the checkout installed in development mode (`pip install -e .[test]`) — the pinned parser uses `ast.Str`, so a 3.12+ interpreter cannot run this tree.
- `pytest`
- `flake8` and `isort` (configuration in `setup.cfg`, invocations in `tox.ini:33-53`)

## 8. Approval Points

none — the change is library-local with test coverage; `/geniro:implement` may run start to finish.

## 9. Validation

Two seams, both already exercised by the repository's own tests.

**Directive seam — `.. autoclass:: <target>` with `:members:` and `:inherited-members:`**, entered in tests through `do_autodoc(app, 'class', name, options)` (`tests/test_ext_autodoc.py:33-45`). This is the seam a real user hits, and the highest one that observes the defect. Prior art for exact-output assertions on inherited attributes: `test_autodoc_typed_inherited_instance_variables` (`tests/test_ext_autodoc.py:1659-1718`); prior art for the cutoff-class form: `test_autodoc_inherited_members_Base` (`tests/test_ext_autodoc.py:629-638`).

Criteria:

1. A doc-commented instance attribute defined in a base class appears as `.. py:attribute:: <Derived>.<attr>` with the base class's comment as its body, in the same module and across modules.
   verify: `python -m pytest tests/test_ext_autodoc.py -q -k "inherited"`
2. A doc-commented class-level attribute defined in a base class appears with the base's comment, not the docstring of the value's type.
   verify: `python -m pytest tests/test_ext_autodoc.py -q -k "inherited"`
3. A subclass that re-documents an inherited attribute wins over the base class's comment; two levels of inheritance resolve to the nearest documented class.
   verify: `python -m pytest tests/test_ext_autodoc.py -q -k "inherited"`
4. `:inherited-members: <Class>` still excludes members — now including attributes — belonging to that class and above.
   verify: `python -m pytest tests/test_ext_autodoc.py -q -k "inherited"`
5. Without `:inherited-members:`, a class documents only its own attributes; base-class attributes stay absent.
   verify: `python -m pytest tests/test_ext_autodoc.py tests/test_ext_autodoc_autoclass.py -q`

**Attribute seam — `.. autoattribute:: <Derived>.<attr>`**, entered through `do_autodoc(app, 'attribute', …)` (`tests/test_ext_autodoc_autoattribute.py`). Regression-only: a directly documented attribute, an uninitialized instance attribute, and a slots attribute keep their current output.
   verify: `python -m pytest tests/test_ext_autodoc_autoattribute.py tests/test_ext_autodoc_autodata.py tests/test_ext_autodoc_private_members.py tests/test_ext_autodoc_configs.py -q`

**Unit seam — `sphinx.ext.autodoc.importer.get_class_members(subject, objpath, safe_getattr, analyzer)`.** Optional, and worth writing only if a directive-level assertion turns out to be ambiguous about *which* class a member was attributed to; `ClassAttribute.class_` is observable there and nowhere else.

**Untouched neighbours** — autosummary and the pycode parser must not move:
   verify: `python -m pytest tests/test_ext_autosummary.py tests/test_pycode.py tests/test_pycode_parser.py -q`

**Whole suite and style:**
   verify: `python -X dev -m pytest tests -q`
   verify: `python -m flake8 sphinx/ext/autodoc/__init__.py sphinx/ext/autodoc/importer.py`

## 10. Rollback-Recovery

Pure source change in a library plus tests and fixtures — no migration, no persisted state, no feature flag. `git revert` of the single commit restores the previous behavior exactly. Partial rollback is also safe and meaningful: reverting step 3 alone restores the old rendering while leaving enumeration in place (inherited attributes then render their value type's docstring); reverting step 1 alone reverts the whole user-visible change, since steps 2 and 3 are inert without the members to act on.

## 11. Done Condition

`python -X dev -m pytest tests -q` is green with the new inherited-attribute tests included, and `.. autoclass::` with `:members:` + `:inherited-members:` emits every doc-commented base-class attribute — class-level and instance — carrying the base class's own comment.

## Considered Alternatives

**A. Widen the search key at every lookup site (rejected).** Replace `(namespace, attrname)` with a "try each MRO namespace" lookup in `Documenter.add_content()` (`__init__.py:596-608`), `filter_members` (`__init__.py:749`), and `get_class_members()`. This is the literal reading of the issue text, but `add_content` is shared with `ModuleDocumenter`, where there is no MRO, and the three sites would each need their own guard. The chosen design keeps the widened lookup in the two class-scoped places and reuses the MRO walk that already exists for attribute comments.

**B. Carry the defining class on `ObjectMember` (rejected).** Adding a `class_` field would let `is_filtered_inherited_member()` decide the cutoff by identity instead of re-consulting an analyzer. It is the cleaner data model, but `ObjectMember` is public API with a documented tuple compatibility contract (`__init__.py:261-284`), `filter_members` also receives plain tuples from the deprecated path (`__init__.py:626-652`), and the field would be dead weight for every non-attribute member. Revisit if a second consumer appears.

**C. Replace the `analyzer`-scoped block in `get_class_members()` rather than appending to it (rejected).** The MRO walk starting at `subject` subsumes it whenever `'.'.join(objpath) == subject.__qualname__` and `subject.__module__` resolves — true for every path autodoc actually takes. Keeping the existing block costs a few lines and removes the whole class of regression where a patched `__module__` makes `for_module()` resolve to the wrong source, so append rather than replace.

**D. Gate comment inheritance on `autodoc_inherit_docstrings` (rejected).** Superficially consistent, but that config governs `__doc__` resolution inside `getdoc()` (`sphinx/util/inspect.py:891-917`) and users who set it to `False` are suppressing inherited *method* docstrings. The MRO comment walk that already ships for uninitialized instance attributes (`__init__.py:2163-2181`) is ungated; matching it keeps one rule instead of two.
