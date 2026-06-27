# Graphiti MCP — existing fork analysis + our build suggestion

Self-contained brief: why the upstream Graphiti MCP loses data, what the best
community fork fixes (and the bug it still has), and what we should build
instead. Deeper detail in `graphiti-gotchas.md`.

---

## 1. Why this is a problem — the upstream bug

Graphiti's MCP server ingests episodes through an **asynchronous queue**:
`add_memory`/`add_episode` enqueues the episode and **returns success to the MCP
client immediately**, while extraction + embedding + the Neo4j write run in a
**background worker**. The queue exists because `add_episode` is slow (several LLM
calls — extraction, dedup, embedding — seconds per episode) and writes must be
serialized per `group_id`.

The failure: if the background worker never runs or throws, the client already
saw success and **nothing persists — no error reaches the caller**. Concretely:

- **Issue #566** (`/messages` returns 202, `async_worker.start()` never called →
  queue jobs never execute). Opened **2025-06-08, still OPEN ~a year later**, no
  assignee/label/PR/visible maintainer response.
- A recurring family of MCP/ingestion issues: #325/#450 → #566 → #871 → #1062 /
  #1116 → #1469, spanning mid-2025 into 2026.
- Split by layer: **`graphiti-core` (the engine) is actively maintained**; the
  **OSS MCP server is a reference surface whose hardening lags** — Zep's
  commercial focus is the hosted product. The community routed around it with
  forks rather than an upstream fix.

Symptom seen in practice: the full flow runs, Neo4j and the LLM each work in
isolation, the call returns success — but the graph stays empty.

---

## 2. The best existing fork — `michabbb/graphiti-mcp-but-working`

The standout community fork (last commit 2026-06; small, single-maintainer, 9★).
Source: https://github.com/michabbb/graphiti-mcp-but-working

### What it fixes (genuinely)
- **Redis-backed durable queue** (BRPOPLPUSH `queue → processing` list): atomic
  move, `complete` = remove-after-success (at-least-once), and **crash recovery**
  on startup (`recover_all` moves stuck `processing` items back to the queue).
  This fixes the "process dies mid-flight loses everything" upstream failure.
- **`get_queue_status` + `list_group_ids`** — observability so silent drops
  become visible.
- Graceful shutdown (SIGTERM/SIGINT), token auth, health checks.

### Security review (read the actual code — good hygiene)
- Constant-time `secrets.compare_digest` for the nonce and the `clear_graph`
  password. No `eval`/`exec`/`shell`/`subprocess`. No string-built Cypher (writes
  go through `graphiti-core`, parameterized). Secrets never logged (nonce hashed
  to 12 chars). `clear_graph` disabled unless `CLEAR_GRAPH_PASSWORD` is set.
- **Refuses to boot** when bound to `0.0.0.0` with no auth and no `ALLOWED_HOSTS`
  (`main.py`) — can't accidentally run wide-open; DNS-rebinding protection via
  TrustedHost when `ALLOWED_HOSTS` is set. Per-request `contextvar` isolation.

### Caveats / its OWN remaining bug
- **Processing-error episodes are silently DROPPED.** In `queue/worker.py`, any
  exception during processing calls `fail(requeue=False)` → the item is `LREM`'d
  from the processing list with **no requeue, no dead-letter** ("Dropped" log). A
  *transient* error (embedder 401/429, LLM timeout, malformed JSON) loses that
  episode permanently. The **inline comment is wrong** — it claims the item
  "stays in processing list and will be recovered on next startup," but
  `requeue=False` actively removes it. (Crash recovery works; processing-error
  durability does not.)
- **Auth = a single static shared nonce in a query param** (`?nonce=`) — can leak
  into proxy/access logs; coarse-grained (server-wide, not per-tenant).
- **`X-Group-Id` is trusted from the client** with no entitlement check → **no
  hard multi-tenant isolation** on its own. Tenant isolation must be enforced
  upstream (your backend).
- **No tests** (0 test files) — a maturity gap for production dependence.

**Verdict:** the best "working + active" MCP fork; usable to unblock/diagnose.
But single-maintainer, with a real drop-on-error gap and no multi-tenant
isolation guarantee — not something to build a product hard-dependency on
unmodified.

---

## 3. Our suggestion — build a thin TS wrapper, not a Graphiti fork

### Hard constraint
`graphiti-core` (the engine: extraction, bi-temporal graph, dedup, hybrid-search
recipes — the reason we chose Graphiti) is **Python-only**. So:

- **Reimplementing Graphiti in TS → no.** Rebuilding the engine throws away the
  exact value we picked it for.
- **A TS *wrapper* (MCP + auth + queue + multi-tenancy) over the Python engine →
  reasonable** if our platform is TS. The engine stays a black-box Python
  container, reached via Graphiti's REST `graph_service` or a tiny Python shim.

Don't fork Graphiti to fix a ~10-line queue bug. Own the wrapper in our stack;
keep the engine untouched.

### A better/simpler queue than the fork's hand-rolled Redis list
Ranked by use case:

1. **No queue — synchronous write (plugin / low volume).** `await
   add_episode(...)` and return when done. No Redis, no worker, no silent drops —
   failures surface to the caller for retry. Simplest and bulletproof; the caller
   waits a few seconds. (This is the plugin path in `graphiti-integration-plan.md`.)
2. **A trusted off-the-shelf queue (Genera throughput).** Don't hand-roll
   BRPOPLPUSH — use **BullMQ** (TS/Node, Redis-backed, retries + backoff +
   dead-letter + dashboard). Less of our own code, real durability.
3. **Postgres outbox (never lose a user's memory).** On a write, synchronously
   insert a `pending_episodes` row (fast, durable), return immediately; a worker
   drains it into Graphiti with retries. The DB row is the source of truth, the
   graph is a derived projection — a failed ingest never loses the memory.

### Auth (fixes the fork's gaps)
Backend-issued **short-lived Bearer JWT** verified by the wrapper; derive
`group_id` from the verified token, **not** a client `X-Group-Id` header — this
gives real per-tenant isolation. (Don't try to reuse Claude Code's CLI/login
token: MCP auth is server-defined; the client does not hand its login token to
servers.)

### Target architecture
```
custom UI (Genera) → Genera backend ─REST─┐
                                          ▼
   agents / plugin ─MCP/Bearer──►  thin TS service (auth + group_id + queue)
                                          │  BullMQ or Postgres outbox
                                          ▼
                              Python Graphiti engine (black box)
                                          ▼
                                   Neo4j / FalkorDB
```

**Meta-rule:** the most reliable system is the least custom code — synchronous
where we can, a trusted off-the-shelf queue where we can't, and Graphiti-Python
as a black box we never edit.

---

## References
- Upstream bug #566: https://github.com/getzep/graphiti/issues/566
- Embedder fallback #1116: https://github.com/getzep/graphiti/issues/1116
- Fork: https://github.com/michabbb/graphiti-mcp-but-working
- Graphiti core (Python engine): https://github.com/getzep/graphiti
- BullMQ: https://github.com/taskforcesh/bullmq
- Deeper gotchas + fork ranking: `graphiti-gotchas.md`
- Integration plan: `graphiti-integration-plan.md`
