---
title: Per-tenant rate limit on the ledger CSV export
task-slug: export-rate-limit
branch: feat/export-limits
---

# Per-tenant rate limit on the ledger CSV export

## Problem

`POST /exports/ledger.csv` is unlimited. A single customer scripting the
endpoint can saturate the service for everyone, and each in-flight export holds
a database cursor open for the length of the response.

## Goal

Limit the ledger export to 5 requests per tenant per hour. A tenant over the
limit gets the service's standard failure response with HTTP 429. Tenants must
be limited independently of one another.

## Acceptance criteria

- A sixth export request from the same tenant inside one hour is rejected.
- A different tenant's requests are unaffected by the first tenant's usage.
- A rejected request does not reach the handler body.
