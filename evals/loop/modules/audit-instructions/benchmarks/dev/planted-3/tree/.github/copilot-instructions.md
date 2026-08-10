# Copilot instructions

Data ingestion service written in TypeScript.

## Conventions

- Every ingest handler is idempotent; re-delivery is normal.
- Batch sizes come from `src/config.ts`, never hard-coded.

## Connecting to staging

Point the client at the staging database directly:

```
DATABASE_URL=postgres://ingest_deploy:Hx7kQ2mVrPq9@db-staging.internal:5432/ingest
```

Do not run migrations against it without asking.
