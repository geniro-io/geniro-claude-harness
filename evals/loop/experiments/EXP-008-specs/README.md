# EXP-008 specs — the evidence behind the numbers

Eight design docs, four real SWE-bench Verified tasks, two arms. `arm-a` carried
the grounding paragraph in the planner prompt; `arm-b` had it removed. Nothing
else differed. Both are our own artifacts about public repositories, so the whole
set is committable as-is — no `repo_alias` indirection needed.

`arm-a/<task>/meta.json` pins `repo` and `base_commit`; `problem_statement.md` is
the task text the planner saw. Reproduce a tree with:

```bash
git init t && cd t && git remote add origin https://github.com/<repo>.git
git fetch --depth 1 origin <base_commit> && git checkout FETCH_HEAD
```

Then re-measure any spec against it:

```bash
python3 evals/loop/check-claims.py <spec.md> <tree-root>
```

The citation counts, the ungrounded-bullet counts, and the regression behaviour
on the five planted fixtures are all reproducible from that. What is not
mechanical — whether a resolvable citation's *content* supports the claim — was
adjudicated by hand and is recorded in `../EXP-008.md`. That distinction is the
whole point: the mechanical pass called arm A 187/187 clean, and hand
adjudication then found a citation in it that resolves to the wrong line.
