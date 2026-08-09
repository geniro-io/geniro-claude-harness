# Optimizations review criteria
## Contents
## Scope boundary — defers to `architecture-criteria.md`
## What to check
### 1. ORM Hydration Skip
# Mongoose: read-only findX without.lean
# TypeORM repository reads
# Sequelize findAll without raw
# Django serializer paths missing.values
# Detect mutate-then-save (negative signal — DO NOT flag)
### 2. Column Projection
# Mongoose without.select
# TypeORM querybuilder without explicit select
# Sequelize without attributes
# Prisma without select/omit
# SQL: SELECT *
# Django: full hydration where a few fields read
### 3. React Re-render Hygiene
# Inline object/array literals as JSX props
# Inline arrow functions as props
# Memo coverage on heavy components
# Long lists without virtualization
# useEffect with state setter and unstable dep
### 4. Frontend Bundle / Asset Performance
# Eager route imports
# Heavy lib eager imports
# Image elements missing the lazy-loading attr (the red flag; check other attrs in separate passes — an OR-exclusion drops an img that has any one of them)
# Lodash full import
# Missing dynamic import for charts/editors
### 5. Async Parallelization
# Adjacent awaits on independent calls
# Fan-out await in loop
# Python: serialized awaits
# Sequential fetches that share no input
### 6. Bulk Operations
# Sequelize / TypeORM / Mongoose per-row create in loop
# Prisma per-row in loop
# Django per-row save in loop
# Raw SQL: single-row INSERT in loop
# Redis per-key writes
## Common false positives
## Stack-agnostic patterns
## Cross-PR hot-path work (peer-PR context)
## Review checklist
## Severity guidelines
