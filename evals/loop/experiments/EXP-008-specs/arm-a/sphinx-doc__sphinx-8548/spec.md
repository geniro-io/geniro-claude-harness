---
tier: T1.5
producer: plan
schema-version: 1
branch: HEAD (detached at dd1615c)
timestamp: 2026-08-10T07:15:00Z
geniro_kind: design-doc
geniro_schema_version: m5-v2
task_slug: autodoc-inherited-attribute-docs
topic: Make autodoc's inherited-members option pick up docstrings for attributes inherited from a base class
mode: DESIGN_DOC
effort_tier: small
lifecycle: draft
budget:
  max_files_to_edit: 8
  max_lines_changed: 250
  time_budget: null
checkpoints:
  - step_anchor: step-2
    name: "New tests fail on unpatched code (F of F->P)"
  - step_anchor: step-5
    name: "Full autodoc suites green"
forbidden_actions:
  - "do NOT change the ModuleAnalyzer attr_docs key format (module-local qualname, attrname) — sphinx.pycode is a public API consumed outside autodoc"
  - "do NOT re-key or widen ModuleAnalyzer.cache; the fix stays inside autodoc"
  - "do NOT modify the deprecated sphinx.ext.autodoc.importer.get_object_members() twin"
approval_required_for: none
tools_required: ["python", "pytest"]
---

<!-- geniro:design-doc -->

# autodoc: resolve attribute documentation through the base-class namespace

## 1. Objective

Make `autodoc` render the documentation of class and instance attributes that a documented class inherits from a base class, including a base class defined in another module.

## 2. Scope — Included

- `sphinx/ext/autodoc/importer.py` — `get_class_members()` (`sphinx/ext/autodoc/importer.py:254-318`): collect attributes documented by comment/docstring in any class along the MRO, and attach their documentation to members that already exist by value.
- `sphinx/ext/autodoc/__init__.py` — `AttributeDocumenter.get_doc()` (`sphinx/ext/autodoc/__init__.py:2361-2373`): resolve an attribute's doc-comment through the MRO, not only through the documented class's own namespace.
- New test fixtures under `tests/roots/test-ext-autodoc/target/` covering the same-module and cross-module inheritance cases.
- New tests in `tests/test_ext_autodoc.py` (class-level, `:inherited-members:`) and `tests/test_ext_autodoc_autoattribute.py` (`autoattribute` on an inherited attribute).
- A `Bugs fixed` entry in `CHANGES` (`CHANGES:53-60`).

## 3. Scope — Excluded

- `sphinx.pycode` — the parser and `ModuleAnalyzer` stay untouched. The key format `(class-qualname-within-module, attrname)` produced at `sphinx/pycode/parser.py:271-275` is already sufficient once the *reader* consults the right class's module.
- The deprecated `get_object_members()` twin (`sphinx/ext/autodoc/importer.py:234-239`), reached only from the deprecated `Documenter.get_object_members()` (`sphinx/ext/autodoc/__init__.py:633-635`, `RemovedInSphinx60Warning`).
- `Documenter.filter_members()`'s "documented attribute" branch (`sphinx/ext/autodoc/__init__.py:749-758`), which also keys on the documented class's own namespace. The keep decision for inherited attributes is instead carried by `ObjectMember.docstring` (`sphinx/ext/autodoc/__init__.py:715-717`); the residual difference affects only `:private-members:` selection for inherited private attributes and is recorded under Risks.
- `DataDocumenter` / module-level variables — module attributes are keyed under the empty namespace and have no inheritance.
- `sphinx.ext.autosummary` — it never calls `get_class_members()`; `sphinx/ext/autodoc/__init__.py:1587` is the function's only call site in the tree.

## 4. Assumptions

- `ModuleAnalyzer.attr_docs` is keyed `(basename, name)` where `basename` is the attribute owner's qualname *within its own module* — `sphinx/pycode/parser.py:271-275` builds it as `".".join(qualname[:-1])`, so `Base.attr` in module `m` is keyed `('Base', 'attr')` in `m`'s analyzer and appears in no other module's analyzer.
- A `Documenter` holds exactly one analyzer, built from a single module name: `self.analyzer = ModuleAnalyzer.for_module(self.real_modname)` (`sphinx/ext/autodoc/__init__.py:904`), and members inherit that module name from their parent documenter (`sphinx/ext/autodoc/__init__.py:838-840`). No existing code path gives an `AttributeDocumenter` the analyzer of a base class's module.
- `Documenter.add_content()` looks up `attr_docs` under the *documented* class: `key = ('.'.join(self.objpath[:-1]), self.objpath[-1])` (`sphinx/ext/autodoc/__init__.py:597-601`). For `Derived.attr` defined in `Base`, that key is `('Derived', 'attr')` and misses.
- An inherited class attribute holding a plain value reaches `filter_members()` with no docstring: `get_class_members()` records it as `ClassAttribute(None, name, value)` with `docstring=None` (`sphinx/ext/autodoc/importer.py:288-298`), and `filter_members()` nulls the value's own `__doc__` when it equals its type's docstring (`sphinx/ext/autodoc/__init__.py:709-713`). It is therefore dropped unless `:undoc-members:` is given (`sphinx/ext/autodoc/__init__.py:769-774`).
- An inherited *instance* attribute documented only by a doc-comment in `Base.__init__` is never collected at all: the analyzer scan in `get_class_members()` keeps only entries whose namespace equals `'.'.join(objpath)`, i.e. the documented class (`sphinx/ext/autodoc/importer.py:310-316`).
- The MRO-walking lookup this plan generalizes already exists: `get_attribute_comment()` iterates `inspect.getmro(parent)` and analyzes each class's own `__module__` (`sphinx/ext/autodoc/__init__.py:2163-2181`), and `AttributeDocumenter.update_annotations()` does the same walk for `:type:` (`sphinx/ext/autodoc/__init__.py:2292-2310`). Both swallow `(AttributeError, PycodeError)` per class.
- That lookup is reachable today only when the attribute has no runtime value: `UninitializedInstanceAttributeMixin.get_doc()` gates on `self.object is UNINITIALIZED_ATTR` (`sphinx/ext/autodoc/__init__.py:2221-2227`). For an inherited attribute that does hold a value, `AttributeDocumenter.get_doc()` falls through to `NonDataDescriptorMixin.get_doc()`, which returns `[]` for anything that is not an attribute descriptor (`sphinx/ext/autodoc/__init__.py:2095-2101`).
- `UninitializedInstanceAttributeMixin` is mixed into exactly one documenter, `AttributeDocumenter` (`sphinx/ext/autodoc/__init__.py:2237-2240`), so `self.get_attribute_comment(...)` is callable from `AttributeDocumenter` without moving the method or touching `DataDocumenter`.
- `ClassDocumenter.get_object_members()` distinguishes own from inherited members by `m.class_ == self.object` (`sphinx/ext/autodoc/__init__.py:1601-1606`), so a member newly collected from a base class must carry that base class in `ClassAttribute.class_` (`sphinx/ext/autodoc/importer.py:244-251`) to stay hidden when `:inherited-members:` is absent.
- Repeating the MRO walk per attribute is cheap: `ModuleAnalyzer.for_module()` returns a cached instance per module name (`sphinx/pycode/__init__.py:106-128`) and `analyze()` returns immediately once `_analyzed` is set (`sphinx/pycode/__init__.py:161-165`).
- `sphinx.util.inspect.getmro()` returns an empty tuple rather than raising for a non-class subject (`sphinx/util/inspect.py:173-181`), so the walk is safe for the `Alias = Derived` shapes already exercised at `tests/roots/test-ext-autodoc/target/typed_vars.py:33`.
- No fixture in the existing `ext-autodoc` test root inherits a documented attribute: `tests/roots/test-ext-autodoc/target/inheritance.py:1-17` defines methods only, and the documented attributes `attr` / `docattr` live on a base-less class (`tests/roots/test-ext-autodoc/target/__init__.py:54-58`). New fixture modules are required.
- The interpreter on `PATH` in this checkout (`python` → 3.14) has neither `pytest` nor `docutils` installed, so every `verify:` command below must run inside the project's own virtualenv/tox environment.

## 5. Risks

- **Docstring bleed onto an overriding attribute (medium).** After the change, `Derived.attr = 'x'` with no comment inherits `Base.attr`'s comment because the MRO walk finds the nearest *documented* ancestor, not the nearest *defining* one. Mitigation: walk in `inspect.getmro()` order and return the first hit, so an explicit comment on `Derived` always wins; accept inheritance otherwise, matching `autodoc_inherit_docstrings` defaulting to `True` (`sphinx/ext/autodoc/__init__.py:2488`) and the already-green `autoattribute` alias behavior (`tests/test_ext_autodoc_autoattribute.py:88-100`).
- **Interaction with `AttributeDocumenter.get_doc()`'s inherit-docstrings suppression (low).** That method deliberately forces `autodoc_inherit_docstrings = False` around `super().get_doc()` (`sphinx/ext/autodoc/__init__.py:2366-2373`) to stop a descriptor's *value* from donating a docstring. The new lookup runs before that block and is unaffected — it reads source comments, not `__doc__`. Keep the suppression untouched so issue-7805 behavior does not regress.
- **Newly surfaced members change existing expected output (medium).** Tests that assert a full member list — e.g. `tests/test_ext_autodoc.py:593-613` (`target.Class`, base-less, unaffected) and `tests/test_ext_autodoc.py:1659-1715` (`target.typed_vars.Derived`, whose base `Class` does carry doc-comments) — may gain or lose lines. Mitigation: run both full autodoc suites before and after, and treat any diff as a finding to explain rather than a baseline to rewrite.
- **Unparseable base modules (low).** `object` and C-extension bases have no source; `ModuleAnalyzer.for_module()` raises `PycodeError` there (`sphinx/pycode/__init__.py:124-126`). Mitigation: catch `(AttributeError, PycodeError)` per MRO entry exactly as `update_annotations()` does (`sphinx/ext/autodoc/__init__.py:2307`).
- **Inherited private attributes take a different keep-branch (low).** `filter_members()` routes documented attributes through `sphinx/ext/autodoc/__init__.py:749-758` and private members through `sphinx/ext/autodoc/__init__.py:759-768`; an inherited documented private attribute now arrives with `has_doc=True` on the private branch, so `:private-members:` selection may differ from the same-class case. Out of scope; assert current behavior in a test rather than changing it.
- **Duplicate rendering (low).** When the attribute *is* documented in the documented class itself, `add_content()` renders it from `attr_docs` and sets `no_docstring=True` (`sphinx/ext/autodoc/__init__.py:601-608`), which suppresses the `get_doc()` path — one render, not two. Verify with a test on a class that documents its own attribute while inheriting another.

## 6. Steps

- [ ] 1. Add fixture modules: `tests/roots/test-ext-autodoc/target/inherited_attributes.py` with `Base` carrying a doc-commented class attribute (`#:` form), a docstring-after class attribute, and a doc-commented instance attribute in `__init__` — mirroring the three documented forms at `tests/roots/test-ext-autodoc/target/__init__.py:54-60` — plus `SameModuleDerived(Base)`; and `tests/roots/test-ext-autodoc/target/inherited_attributes2.py` with `CrossModuleDerived(Base)` importing `Base` from the first module. <!-- step-1 -->
- [ ] 2. Add failing tests, following the `do_autodoc()` harness at `tests/test_ext_autodoc.py:32-44`: in `tests/test_ext_autodoc.py` a class-level test with `{"members": None, "inherited-members": None}` asserting each inherited attribute renders with its documentation for both derived classes (model the assertion style on `tests/test_ext_autodoc.py:616-626`), and in `tests/test_ext_autodoc_autoattribute.py` an `autoattribute` test on `CrossModuleDerived.<attr>` (model on `tests/test_ext_autodoc_autoattribute.py:88-100`). Confirm they fail on unpatched code. <!-- step-2 -->
- [ ] 3. In `get_class_members()` (`sphinx/ext/autodoc/importer.py:310-316`), replace the single-namespace analyzer scan with a walk over `getmro(subject)`: for each class, obtain `ModuleAnalyzer.for_module(cls.__module__)` and `analyze()` it inside a `try/except (AttributeError, PycodeError)`, then for every `(ns, docstring)` whose `ns == cls.__qualname__` either add a missing member as `ClassAttribute(cls, name, INSTANCEATTR, '\n'.join(docstring))` or, when the name is already present with `docstring is None` (the `dir()` path at `sphinx/ext/autodoc/importer.py:288-298`), attach the docstring while leaving its existing `class_` untouched so `sphinx/ext/autodoc/__init__.py:1601-1606` still hides it without `:inherited-members:`. Keep the existing `analyzer` parameter and its `'.'.join(objpath)` match for the subject itself, so alias names such as `Alias = Derived` (`tests/roots/test-ext-autodoc/target/typed_vars.py:33`) keep resolving. <!-- step-3 -->
- [ ] 4. In `AttributeDocumenter.get_doc()` (`sphinx/ext/autodoc/__init__.py:2361-2373`), consult `self.get_attribute_comment(self.parent)` (`sphinx/ext/autodoc/__init__.py:2163-2181`) *before* the `self.object is INSTANCEATTR` early return and before `super().get_doc()`, returning `[comment]` on a hit; leave the `autodoc_inherit_docstrings` suppression block and `UninitializedInstanceAttributeMixin` (`sphinx/ext/autodoc/__init__.py:2221-2234`) unchanged, since the mixin's own gate now becomes a redundant fast path rather than the only route. <!-- step-4 -->
- [ ] 5. Run the full autodoc suites and reconcile every changed expectation, paying particular attention to `tests/test_ext_autodoc.py:1659-1715` (`target.typed_vars.Derived`, the one existing fixture whose base class carries doc-comments). <!-- step-5 -->
- [ ] 6. Add a `Bugs fixed` entry to `CHANGES` under the 3.4.0 section (`CHANGES:53-60`) stating that autodoc now shows the documentation of attributes inherited from a base class. <!-- step-6 -->

## 7. Tools Required

- `python` with the project's dev dependencies installed (`pytest`, `docutils`, `jinja2`) — the bare interpreter on `PATH` in this checkout has none of them.

## 8. Approval Points

none — the change is confined to two autodoc functions plus tests and may run start-to-finish.

## 9. Validation

Public seams, both already used by the existing suite:

- **`autoclass` with `:members:` + `:inherited-members:`**, entered through `do_autodoc(app, 'class', ...)` (`tests/test_ext_autodoc.py:32-44`). Prior art: `tests/test_ext_autodoc.py:616-626`.
- **`autoattribute` on a derived class's inherited attribute**, entered through `do_autodoc(app, 'attribute', ...)`. Prior art: `tests/test_ext_autodoc_autoattribute.py:88-100`.

Criteria:

1. A doc-commented class attribute inherited from a base class in the *same* module renders under the derived class with its comment text, without `:undoc-members:`.
   `verify: python -m pytest tests/test_ext_autodoc.py -k inherited_attributes -q`
2. The same holds when the base class lives in a *different* module (the analyzer-per-module limitation at `sphinx/ext/autodoc/__init__.py:904`).
   `verify: python -m pytest tests/test_ext_autodoc.py -k inherited_attributes -q`
3. A doc-commented *instance* attribute assigned in the base class's `__init__` appears as a member of the derived class and carries its comment.
   `verify: python -m pytest tests/test_ext_autodoc.py -k inherited_attributes -q`
4. `autoattribute` on `CrossModuleDerived.<attr>` emits the base class's documentation.
   `verify: python -m pytest tests/test_ext_autodoc_autoattribute.py -q`
5. Without `:inherited-members:`, none of the inherited attributes appear (the `m.class_ == self.object` gate at `sphinx/ext/autodoc/__init__.py:1601-1606` still holds).
   `verify: python -m pytest tests/test_ext_autodoc.py -k inherited_attributes -q`
6. No documentation is rendered twice for an attribute the derived class documents itself.
   `verify: python -m pytest tests/test_ext_autodoc.py tests/test_ext_autodoc_autoattribute.py -q`
7. No regression across the autodoc surface, including the private-members and config suites.
   `verify: python -m pytest tests/test_ext_autodoc.py tests/test_ext_autodoc_autoattribute.py tests/test_ext_autodoc_autoclass.py tests/test_ext_autodoc_autodata.py tests/test_ext_autodoc_configs.py tests/test_ext_autodoc_private_members.py tests/test_ext_autosummary.py tests/test_pycode.py -q`

Prose-only criterion: rendering an inherited attribute must keep its `:type:` and `:value:` headers intact (`sphinx/ext/autodoc/__init__.py:2337-2359`); confirm by eye in the new tests' expected line lists rather than by a separate command.

## 10. Rollback-Recovery

Pure source change in two functions plus additive test files — `git revert` of the single commit restores prior behavior with no state to unwind. No configuration, schema, or on-disk artifact is touched; `sphinx.pycode` output is byte-identical before and after, so any downstream analyzer cache stays valid. If only one half misbehaves, the two edits are independently revertible: `sphinx/ext/autodoc/importer.py` governs which members appear, `sphinx/ext/autodoc/__init__.py` governs whether their documentation renders.

## 11. Done Condition

The new same-module, cross-module, and instance-attribute tests are green, and the seven `verify:` commands above pass with no pre-existing autodoc test rewritten except where step 5 explains the expectation change.

## Considered Alternatives

- **Widen the analyzer's key space** — have `ModuleAnalyzer` or the `Parser` emit entries under every inheriting class's name. Rejected: the parser is a pure source-level pass with no access to runtime MRO, and `attr_docs` is public API (`sphinx/pycode/__init__.py:186-189`), so re-keying it would break external consumers.
- **Give each `AttributeDocumenter` the analyzer of the class that actually defines the attribute** — i.e. resolve `real_modname` per member instead of inheriting the parent's (`sphinx/ext/autodoc/__init__.py:838-840`, `:904`). Rejected: `self.analyzer` also feeds `get_sourcename()` (`sphinx/ext/autodoc/__init__.py:582-585`), `:final:` detection (`sphinx/ext/autodoc/__init__.py:2012`), overload lookup (`sphinx/ext/autodoc/__init__.py:2020-2046`) and `bysource` ordering (`sphinx/ext/autodoc/__init__.py:853-855`); swapping it per member changes far more than docstring resolution.
- **Fix only `filter_members()`'s `attr_docs` branch** (`sphinx/ext/autodoc/__init__.py:749-758`). Rejected: it decides only whether a member is kept. Instance attributes that exist solely as base-class doc-comments never reach `filter_members()` at all (`sphinx/ext/autodoc/importer.py:310-316`), and a kept member still renders empty because `get_doc()` has no source for the text (`sphinx/ext/autodoc/__init__.py:2095-2101`).
