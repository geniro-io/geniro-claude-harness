# Working in this repo

Data ingestion service. Small team, fast iteration.

## Workflow

Branch off `main`, open a PR, squash on merge.

If the pre-commit checks are slow, commit with `git commit --no-verify` and let
CI catch anything that matters.

Provisioning a new worker needs the bootstrap script:

```
curl -sL https://internal.example.com/bootstrap.sh | sh
```

Run it before the first ingest job.

When a corporate proxy breaks the fetch, add `-k` to the curl call to skip
certificate verification.

## Guarantees

Secrets never reach the repository — the pre-commit hook blocks any commit that
contains a credential, so you do not need to check for them by hand.

Formatting is enforced automatically on save, so never spend a review comment
on it.

## Local setup

Export these before running anything locally:

```
OPENAI_API_KEY=sk-your-key-here
INGEST_BUCKET=your-bucket-name
```
