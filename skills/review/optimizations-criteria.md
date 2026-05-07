# Optimizations Review Criteria

Concrete, measurable performance wins on the changed lines: skip ORM hydration on read-only paths, project columns, parallelize independent awaits, batch per-row writes, hygiene React re-renders, and ship the frontend bundle leanly.

## Scope Boundary — Defers to `architecture-criteria.md` §6

This dimension owns *micro-level* optimization wins observable on the diff. The following six concerns are **not** owned here — they are systemic performance issues handled by `architecture-criteria.md` §6 (Performance & Scalability). Defer to that section; do not duplicate findings:

1. **N+1 query patterns** — queries inside loops without batching → architecture §6
2. **ORM eager-loading** — `include` / `prefetch_related` / `joinedload` design → architecture §6
3. **Caching / memoization at the architecture level** — missing layers, not micro-memo → architecture §6
4. **Missing pagination on unbounded queries** → architecture §6
5. **Sync I/O in async context** — `readFileSync` etc. on hot paths → architecture §6
6. **Inefficient algorithms (O(n²) where O(n) possible)** → architecture §6

If a finding fits one of those six, emit it under architecture's `category: "performance"` instead. Optimizations stays focused on the six categories below.

## What to Check

### 1. ORM Hydration Skip
- Read-only paths (JSON-serialize-only endpoints, list views, exports) that hydrate full ORM Documents/Entities when plain objects suffice
- Findings should target the *call site*, not the ORM — flag a missing skip-hydration call only when the result is never mutated, never `.save()`d, and never relies on getters/virtuals/methods
- Mongoose: missing `.lean()` on read-only `find()`/`findOne()`
- TypeORM: missing `getRawMany()`/`getRawOne()` on report-style queries
- Sequelize: missing `{ raw: true }` on read-only `findAll()`
- MikroORM: missing `disableIdentityMap: true` on detached-read paths
- Doctrine: missing `HYDRATE_ARRAY` / `HYDRATE_SCALAR` on report queries
- SQLAlchemy: missing drop-to-Core / `with_entities` on read-only aggregations
- Django: missing `.values()` / `.values_list()` on hot list endpoints
- ActiveRecord: missing `.pluck(:col)` where loop only reads one column
- Prisma / Drizzle: hydration not applicable — they return POJOs by default; don't invent a missing skip-hydration call

**How to detect:**
```bash
# Mongoose: read-only findX without .lean()
grep -nE "\.find(One|ById)?\(|\.findOneAnd" file.ts | grep -v "\.lean(\|\.save(\|\.populate("
# TypeORM repository reads
grep -nE "\.find\(|\.findOne\(|createQueryBuilder" file.ts | grep -v "getRaw\|\.save("
# Sequelize findAll without raw
grep -nE "\.findAll\(|\.findOne\(" file.ts | grep -v "raw:\s*true\|\.save("
# Django serializer paths missing .values()
grep -nE "\.objects\.(all|filter)\(" file.py | grep -v "\.values\|\.only\|\.defer"
# Detect mutate-then-save (negative signal — DO NOT flag)
grep -nB3 "\.save(" file.ts | grep -E "\.lean\(|raw:\s*true"
```

**Red flags:**
- `findAll().then(rows => res.json(rows))` with no projection or `.lean()` — pure read, hydration is pure cost
- Loop that reads one field per row from a hydrated entity collection
- Aggregation/report endpoints returning JSON of full ORM entities

### 2. Column Projection
- Endpoint or query fetches every column when caller uses ≤3 fields
- Fan-out pages (admin tables, autocomplete results, exports) that need only id + label but `SELECT *`
- Joins that pull all columns of the joined table while only one is read
- Findings strongest on hot paths and wide tables (BLOB/TEXT columns dragged through every read)

**How to detect:**
```bash
# Mongoose without .select()
grep -nE "\.find\(|\.findOne\(" file.ts | grep -v "\.select("
# TypeORM querybuilder without explicit select
grep -nE "createQueryBuilder\(" file.ts | grep -v "\.select(\["
# Sequelize without attributes
grep -nE "\.findAll\(\{" file.ts | grep -v "attributes:"
# Prisma without select/omit
grep -nE "\.findMany\(|\.findUnique\(|\.findFirst\(" file.ts | grep -v "select:\|omit:"
# SQL: SELECT *
grep -nE "SELECT\s+\*" file.{ts,py,sql}
# Django: full hydration where a few fields read
grep -nE "\.objects\.(all|filter)\(" file.py | grep -v "\.values\|\.only"
```

**Red flags:**
- `SELECT *` in handwritten SQL on a hot path
- ORM call with no `select` / `attributes` / `fields` arg followed by usage that touches ≤3 columns
- Wide tables (10+ columns, including JSON/text blobs) read fully when caller serializes id + name

### 3. React Re-render Hygiene
- New object/array/function literal passed as prop on every parent render, breaking child `memo` / `PureComponent` equality
- Expensive child component (heavy render, deep tree, chart, virtualized list) without `React.memo`
- `useMemo` / `useCallback` missing where the wrapped expression is genuinely non-trivial *and* the consumer is render-frequent
- Long lists rendered without virtualization (>100 rows MEDIUM, >1000 rows HIGH)
- State updates in `useEffect` that cause render loops (state derived from props that re-derives every render)
- Only flag when there is a measurable render-cost path — render hygiene is not a license to wrap everything

**How to detect:**
```bash
# Inline object/array literals as JSX props
grep -nE "<[A-Z][A-Za-z]+\s.*=\{\{|=\{\[" file.tsx
# Inline arrow functions as props
grep -nE "<[A-Z][A-Za-z]+\s.*=\{\(.*\)\s*=>" file.tsx
# Memo coverage on heavy components
grep -nE "^export (default )?function [A-Z]|^const [A-Z]\w+ = " file.tsx | grep -v "memo("
# Long lists without virtualization
grep -nE "\.map\(.*=>\s*<[A-Z]" file.tsx | head
grep -lE "react-window|react-virtual|@tanstack/react-virtual" file.tsx
# useEffect with state setter and unstable dep
grep -nE "useEffect\(\(\)\s*=>\s*\{[^}]*set[A-Z]" file.tsx
```

**Red flags:**
- `<Child onClick={() => …}>` inside a frequently-re-rendering parent where `Child` is `memo`'d
- `<List items={data.map(d => …)} />` — the `.map` produces a fresh array every render
- A 5000-row table rendered as a flat `.map(row => <Row …/>)` with no virtualization
- `useEffect(() => setX(derive(props)), [props])` — derived state that should be `useMemo` or just inlined

### 4. Frontend Bundle / Asset Performance
- Routes loaded eagerly that could be split via dynamic `import()` / `React.lazy` / `loadable`
- Heavy third-party libs (charts, editors, PDF) imported at module top-level instead of lazy
- Images served as PNG/JPG without WebP/AVIF, no `srcset`, no width/height attrs (CLS)
- Below-fold `<img>` / `<iframe>` without `loading="lazy"`
- Fonts loaded synchronously without `font-display: swap`
- Tree-shaking-hostile imports (`import _ from 'lodash'` instead of `import debounce from 'lodash/debounce'`)

**How to detect:**
```bash
# Eager route imports
grep -nE "^import [A-Z][A-Za-z]+Page from" src/app/routes.tsx
grep -nE "React\.lazy\(|lazy\(" src/app/routes.tsx
# Heavy lib eager imports
grep -rnE "^import .* from ['\"](recharts|chart\.js|monaco|pdfjs|@codemirror)" src/
# Image elements missing modern attrs
grep -nE "<img\s" file.tsx | grep -v "loading=\|srcset=\|width=\|height="
# Lodash full import
grep -rnE "from ['\"]lodash['\"]" src/
# Missing dynamic import for charts/editors
grep -nE "import .*Chart|import .*Editor" file.tsx | grep -v "lazy\|dynamic"
```

**Red flags:**
- Top-level `import { BigChart } from 'recharts'` in a route that renders the chart only after a tab click
- All routes statically imported in `routes.tsx` → entire app in initial bundle
- Hero `<img src="hero.jpg">` with no `width`/`height` (causes layout shift) and no modern format

### 5. Async Parallelization
- Sequential `await`s on independent operations that could run via `Promise.all` (JS) / `asyncio.gather` (Python) / `errgroup` (Go) / `tokio::join!` (Rust)
- Fan-out fetch loops where each iteration awaits before kicking off the next, but iterations are independent
- Independence check is mandatory: if call B uses call A's result, serial is correct — verify before flagging
- Don't blindly recommend `Promise.all` for failure-coupled chains (e.g., if A fails, B must not run)

**How to detect:**
```bash
# Adjacent awaits on independent calls
grep -nE "^\s*const \w+ = await " file.ts | head
# Fan-out await in loop
grep -nB1 -A1 "for .* of " file.ts | grep "await"
# Python: serialized awaits
grep -nE "^\s+\w+ = await " file.py
# Sequential fetches that share no input
grep -nE "await fetch\(" file.ts | head
```

**Red flags:**
- `const a = await getA(); const b = await getB(); const c = await getC();` where `b` and `c` don't reference `a`
- `for (const id of ids) { results.push(await fetch(`/x/${id}`)); }` — classic fan-out, should be `Promise.all(ids.map(...))` (with concurrency cap if `ids` is unbounded)
- Python `for x in xs: await client.get(x)` where calls are independent

### 6. Bulk Operations
- Per-row `INSERT` / `UPDATE` / `DELETE` inside a loop where the ORM/driver supports a bulk variant
- Mongoose: `for (...) await Doc.create(one)` instead of `Doc.insertMany(many)`
- TypeORM: per-row `.save()` instead of `repo.save(arr)` or `insert().values(arr)`
- Sequelize: `Model.create()` in loop instead of `Model.bulkCreate()`
- Prisma: per-row `.create()` instead of `createMany()` (or transactional batch where `createMany` lacks features)
- Django: per-row `.save()` instead of `bulk_create()` / `bulk_update()`
- ActiveRecord: per-row `.save` instead of `insert_all` / `upsert_all`
- Raw SQL: per-row `INSERT` instead of multi-row `VALUES (...), (...), (...)` or `COPY`
- Cache writes: per-key `set` instead of `mset` / pipeline

**How to detect:**
```bash
# Sequelize / TypeORM / Mongoose per-row create in loop
grep -nB2 -A1 "for\s*(.*of\|in\s" file.ts | grep -E "\.(create|save|insertOne|updateOne)\("
# Prisma per-row in loop
grep -nB2 -A1 "for\s*(.*of\|in\s" file.ts | grep "prisma\."
# Django per-row save in loop
grep -nB2 -A1 "for .* in " file.py | grep "\.save("
# Raw SQL: single-row INSERT in loop
grep -nB2 -A1 "for\|while" file.{ts,py} | grep -iE "INSERT INTO"
# Redis per-key writes
grep -nB2 -A1 "for\|while" file.ts | grep "\.set("
```

**Red flags:**
- 10k-row import loop calling `await Model.create(row)` per iteration — N round-trips, easily 100x slower than bulk
- Migration script per-row `UPDATE` instead of one `UPDATE ... WHERE id IN (...)`
- Cache warmup loop with per-key `client.set()` instead of `client.mset()` / pipeline

## Output Format

```json
{
  "type": "optimization",
  "severity": "high|medium|low",
  "title": "Brief optimization opportunity",
  "file": "path/to/file.ts",
  "line_start": 42,
  "line_end": 48,
  "description": "Detailed description of the opportunity",
  "category": "hydration|projection|react-render|bundle|async-parallel|bulk-ops",
  "code_snippet": "Relevant code lines",
  "evidence": "Why this is slower than necessary (round-trips, hydration cost, render count)",
  "impact": "Expected magnitude (e.g., N→1 round-trips, removes O(rows × columns) hydration)",
  "recommendation": "Concrete change (e.g., add .lean(), batch via insertMany, wrap with React.memo)",
  "confidence": 80
}
```

## Common False Positives

1. **Detached entity mutation** — `.lean()` / `raw:true` / `HYDRATE_ARRAY` / `disableIdentityMap` returns objects that cannot be saved through the ORM. Flag mutate-then-save paths only when the path is read-only; do not flag pure-read paths that already use these mechanisms, and never recommend skipping hydration on a path that calls `.save()` afterward.
2. **defer/only/load_only N+1 footgun** — Django `.only()` and SQLAlchemy `load_only` trigger an extra `SELECT` when a deferred column is later accessed. Flag deferred-then-accessed patterns; do not flag use of these on truly write-once-read-rare columns where the deferred access path is cold.
3. **Perf claims without profile data** — "missing index" or "lean would speed this up" without execution-plan / profile evidence is speculative. Lower confidence when no measurement exists; prefer concrete mechanism citations (round-trip count, hydration cost) over hand-waved magnitudes.
4. **Premature memoization** — `useMemo` / `useCallback` on cheap computations is overhead, not optimization. Only flag when the wrapped expression is non-trivial AND the consumer is in a render-frequent context (loop, parent re-renders >5x/sec, large memo'd subtree).
5. **Prisma / Drizzle "missing lean"** — these ORMs return POJOs by default; only projection (`select`) applies. Don't flag a missing skip-hydration call where there's no hydration to skip — recommend `select` / `omit` instead, or stay silent.
6. **Single-use `Promise.all` adjacent awaits** — sometimes serial is intentional: the second call depends on the first's success or its side-effects, or the team wants explicit failure ordering. Verify independence (read the variables, follow the data flow) before flagging.

## Stack-Agnostic Patterns

The two axes apply across stacks:
- **Skip wrapper-object construction** (axis 1): Mongoose `.lean()`, MikroORM `disableIdentityMap`, TypeORM `getRawMany()`, Sequelize `raw:true`, Doctrine `HYDRATE_ARRAY`, Django `.values()`, Rails `.pluck()`, SQLAlchemy `with_entities`
- **Project columns/fields** (axis 2): Mongoose `.select()`, TypeORM `select`, Sequelize `attributes`, Prisma `select`, Drizzle column-shape, SQLAlchemy `load_only`, Django `.only()`, Rails `.select()`/`pluck`

Some ORMs only have axis 2 (Prisma, Drizzle) — they return POJOs by default; the reviewer should not invent a missing axis-1 mechanism for those.

Async parallelization, bulk operations, and bundle/asset patterns are similarly cross-stack: substitute `Promise.all` ↔ `asyncio.gather` ↔ `errgroup.Wait` ↔ `tokio::join!`; substitute `insertMany` ↔ `bulk_create` ↔ `insert_all` ↔ multi-row `INSERT VALUES`. React re-render hygiene is React-specific but the underlying principle (don't recompute when input unchanged) maps to Vue `computed`, Svelte `$:`, SolidJS `createMemo`.

## Review Checklist

- [ ] Read-only ORM paths use the stack's skip-hydration mechanism (`.lean()`, `raw:true`, `HYDRATE_ARRAY`, `.values()`, `.pluck()`)
- [ ] Hot-path queries project columns explicitly; no `SELECT *` on wide tables
- [ ] `.only()` / `load_only` not paired with later access of deferred columns
- [ ] React props don't pass new object/array/function literals to memo'd children every render
- [ ] Long lists (>100 rows) use virtualization
- [ ] Routes and heavy libs (charts, editors, PDF) loaded via dynamic import / `React.lazy`
- [ ] Images use modern formats (WebP/AVIF), `srcset`, explicit `width`/`height`, `loading="lazy"` below the fold
- [ ] Independent awaits batched via `Promise.all` / `asyncio.gather` (independence verified)
- [ ] Per-row INSERT/UPDATE in loops replaced with `insertMany` / `bulk_create` / multi-row `VALUES`
- [ ] Each finding cites a concrete mechanism (round-trip count, hydration cost, render count) — no hand-waved magnitudes

## Severity Guidelines

- **CRITICAL**: not emitted. Optimization findings are improvements, not correctness bugs — bugs and security own CRITICAL. Any genuinely critical perf regression (unbounded query, sync I/O on hot path) belongs in architecture §6.
- **HIGH**: per-row INSERT/UPDATE in a loop on a path that processes >100 items; long-list render >1000 rows without virtualization; eager-import of a heavy lib (>100KB minified) used only behind a tab/modal
- **MEDIUM**: missing `.lean()` / `raw:true` / projection on hot-path read; sequential awaits on independent calls; missing route code-splitting; missing `React.memo` on demonstrably expensive child; long-list render 100–1000 rows without virtualization; image without modern format / `loading="lazy"` on hero
- **LOW**: minor projection wins on cold paths; below-fold image without `loading="lazy"`; tree-shaking-hostile `import _ from 'lodash'` where only one helper is used
