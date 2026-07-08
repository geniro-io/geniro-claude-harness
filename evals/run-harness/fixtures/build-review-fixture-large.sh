#!/usr/bin/env bash
# Build a throwaway git repo with a LARGE planted-issue diff for /review Batched-mode
# spawn assertions (see README "Review spawn assertions (Batched mode)").
#
# The diff is 12 files (>8 — the file-count threshold alone triggers Batched payload
# mode); ~450 total changed lines (~40 per file), spread over four
# subsystem directories (src/core, src/queue, src/web, migrations) so file-grouping
# has real structure. Planted findable issues, mirroring build-review-fixture.sh:
#   - a CLEAR security bug (SQL built by string concatenation in src/web/handlers.js
#     listJobs, replacing the parameterized base query) -> CRITICAL/HIGH;
#   - a dropped null-check (src/queue/worker.js runOnce no longer guards the
#     queue.claim(...) null return before reading job.kind) -> likely bug finding;
#   - a dead export (src/core/errors.js formatLegacyId — exported, never referenced).
# Every other change is a benign refactor. Content is deterministic (no timestamps,
# no randomness beyond the mktemp dir name).
#
# Prints the repo path on the LAST stdout line. The base branch is `main`; the planted
# changes live on `fixture/planted-01`, so review the range `main..HEAD`.
set -euo pipefail

REPO="$(mktemp -d "${TMPDIR:-/tmp}/geniro-review-fixture-large-XXXXXX")"
cd "$REPO"
git init -q -b main
git config user.email eval@geniro.local
git config user.name geniro-eval
mkdir -p src/core src/queue src/web migrations

# ---------------------------------------------------------------- base: main

cat > src/core/config.js <<'EOF'
// Loads service configuration from environment variables.
// Invalid numeric values silently fall back to the defaults below.
const defaults = {
  dbUrl: 'postgres://localhost:5432/app',
  queueName: 'jobs',
  maxRetries: 3,
  pollIntervalMs: 500,
  concurrency: 4,
  logLevel: 'info',
};

function loadConfig(env) {
  return {
    dbUrl: env.DB_URL || defaults.dbUrl,
    queueName: env.QUEUE_NAME || defaults.queueName,
    maxRetries: parsePositiveInt(env.MAX_RETRIES, defaults.maxRetries),
    pollIntervalMs: parsePositiveInt(env.POLL_INTERVAL_MS, defaults.pollIntervalMs),
    concurrency: parsePositiveInt(env.CONCURRENCY, defaults.concurrency),
    logLevel: env.LOG_LEVEL || defaults.logLevel,
  };
}

function parsePositiveInt(raw, fallback) {
  const n = parseInt(raw, 10);
  return Number.isInteger(n) && n > 0 ? n : fallback;
}

function validateConfig(config) {
  if (!config.dbUrl) {
    throw new Error('dbUrl is required');
  }
  return config;
}

module.exports = { loadConfig, validateConfig, defaults };
EOF

cat > src/core/logger.js <<'EOF'
// Leveled JSON-lines logger for the service processes.
const LEVELS = ['debug', 'info', 'warn', 'error'];

function createLogger(level) {
  const threshold = LEVELS.indexOf(level);

  function enabled(entryLevel) {
    return LEVELS.indexOf(entryLevel) >= threshold;
  }

  function write(entryLevel, message, fields) {
    const line = { level: entryLevel, message, ...fields };
    process.stdout.write(JSON.stringify(line) + '\n');
  }

  return {
    debug: (message, fields) => enabled('debug') && write('debug', message, fields),
    info: (message, fields) => enabled('info') && write('info', message, fields),
    warn: (message, fields) => enabled('warn') && write('warn', message, fields),
    error: (message, fields) => enabled('error') && write('error', message, fields),
  };
}

module.exports = { createLogger, LEVELS };
EOF

cat > src/core/errors.js <<'EOF'
// Typed error hierarchy shared across the service.
class AppError extends Error {
  constructor(message, code) {
    super(message);
    this.name = 'AppError';
    this.code = code;
  }
}

class NotFoundError extends AppError {
  constructor(resource, id) {
    super(resource + ' ' + id + ' not found', 'NOT_FOUND');
    this.name = 'NotFoundError';
  }
}

class ConflictError extends AppError {
  constructor(resource, id) {
    super(resource + ' ' + id + ' already exists', 'CONFLICT');
    this.name = 'ConflictError';
  }
}

function isAppError(err) {
  return err instanceof AppError;
}

function codeOf(err) {
  if (isAppError(err)) {
    return err.code;
  }
  return 'INTERNAL';
}

module.exports = { AppError, NotFoundError, ConflictError, isAppError, codeOf };
EOF

cat > src/core/db.js <<'EOF'
// Minimal stand-in data layer for the fixture.
// query(sql, params) runs a parameterized query and resolves with rows.

async function query(_sql, _params) {
  return [];
}

async function queryOne(sql, params) {
  const rows = await query(sql, params);
  if (rows.length === 0) {
    return null;
  }
  return rows[0];
}

async function readTransaction(fn) {
  await query('BEGIN READ ONLY', []);
  try {
    const result = await fn({ query });
    await query('COMMIT', []);
    return result;
  } catch (err) {
    await query('ROLLBACK', []);
    throw err;
  }
}

async function writeTransaction(fn) {
  await query('BEGIN', []);
  try {
    const result = await fn({ query });
    await query('COMMIT', []);
    return result;
  } catch (err) {
    await query('ROLLBACK', []);
    throw err;
  }
}

module.exports = { query, queryOne, readTransaction, writeTransaction };
EOF

cat > src/queue/queue.js <<'EOF'
// Job persistence: enqueue, claim, release, and depth accounting.
const db = require('../core/db');

async function enqueue(queueName, kind, payload) {
  const rows = await db.query(
    'INSERT INTO jobs (queue, kind, payload, state) VALUES ($1, $2, $3, $4) RETURNING id',
    [queueName, kind, JSON.stringify(payload), 'pending']
  );
  return rows[0];
}

async function claim(queueName) {
  const rows = await db.query(
    "UPDATE jobs SET state = 'running' WHERE id = (SELECT id FROM jobs WHERE queue = $1 AND state = 'pending' ORDER BY id LIMIT 1) RETURNING *",
    [queueName]
  );
  return rows[0] || null;
}

async function release(jobId) {
  await db.query(
    "UPDATE jobs SET state = 'pending' WHERE id = $1 AND state = 'running'",
    [jobId]
  );
}

async function depth(queueName) {
  const rows = await db.query(
    "SELECT count(*) AS n FROM jobs WHERE queue = $1 AND state = 'pending'",
    [queueName]
  );
  return rows.length ? Number(rows[0].n) : 0;
}

module.exports = { enqueue, claim, release, depth };
EOF

cat > src/queue/worker.js <<'EOF'
// Pulls one job off the queue and dispatches it to the registered handler.
const queue = require('./queue');
const { computeBackoffMs, shouldRetry } = require('./retry');

async function runOnce(queueName, handlers, logger, maxRetries) {
  const job = await queue.claim(queueName);
  if (!job) {
    return null;
  }
  const handler = handlers[job.kind];
  if (!handler) {
    logger.warn('no handler for job kind', { kind: job.kind });
    return null;
  }
  try {
    const payload = JSON.parse(job.payload);
    const result = await handler(payload);
    return { id: job.id, ok: true, result };
  } catch (err) {
    logger.error('job failed', { id: job.id, error: err.message });
    if (!shouldRetry(job.attempts, maxRetries)) {
      return { id: job.id, ok: false, exhausted: true };
    }
    return { id: job.id, ok: false, retryInMs: computeBackoffMs(job.attempts) };
  }
}

module.exports = { runOnce };
EOF

cat > src/queue/retry.js <<'EOF'
// Delay before the next attempt, in milliseconds.
function computeBackoffMs(attempts) {
  if (!attempts || attempts < 1) {
    return 1000;
  }
  if (attempts === 1) {
    return 2000;
  }
  if (attempts === 2) {
    return 4000;
  }
  if (attempts === 3) {
    return 8000;
  }
  if (attempts === 4) {
    return 16000;
  }
  if (attempts === 5) {
    return 32000;
  }
  return 60000;
}

function shouldRetry(attempts, maxRetries) {
  return (attempts || 0) < maxRetries;
}

module.exports = { computeBackoffMs, shouldRetry };
EOF

cat > src/web/router.js <<'EOF'
// Maps an incoming method + path onto a handler function.
const handlers = require('./handlers');

function route(method, path) {
  if (method === 'GET' && path === '/health') {
    return handlers.health;
  }
  if (method === 'HEAD' && path === '/health') {
    return handlers.health;
  }
  if (method === 'GET' && path.indexOf('/jobs') === 0) {
    return handlers.listJobs;
  }
  if (method === 'POST' && path === '/jobs') {
    return handlers.createJob;
  }
  return handlers.notFound;
}

module.exports = { route };
EOF

cat > src/web/handlers.js <<'EOF'
// HTTP handlers for the jobs API.
const db = require('../core/db');
const queue = require('../queue/queue');

async function health(_req, res) {
  res.statusCode = 200;
  res.setHeader('content-type', 'application/json');
  res.end(JSON.stringify({ ok: true }));
}

async function listJobs(req, res) {
  const owner = req.query.owner;
  const rows = await db.query('SELECT * FROM jobs WHERE owner = $1 ORDER BY id', [owner]);
  res.statusCode = 200;
  res.setHeader('content-type', 'application/json');
  res.end(JSON.stringify(rows));
}

async function createJob(req, res) {
  const created = await queue.enqueue('jobs', req.body.kind, req.body.payload);
  res.statusCode = 201;
  res.setHeader('content-type', 'application/json');
  res.end(JSON.stringify(created));
}

async function notFound(_req, res) {
  res.statusCode = 404;
  res.setHeader('content-type', 'application/json');
  res.end(JSON.stringify({ error: 'not found' }));
}

module.exports = { health, listJobs, createJob, notFound };
EOF

cat > src/web/middleware.js <<'EOF'
// Handler wrappers: request logging, timing, and the error boundary.
function withLogging(logger, handler) {
  return async (req, res) => {
    logger.info('request', { method: req.method, path: req.path });
    await handler(req, res);
  };
}

function withTiming(logger, handler) {
  return async (req, res) => {
    const startedAt = Date.now();
    await handler(req, res);
    logger.info('request timing', { path: req.path, ms: Date.now() - startedAt });
  };
}

function withErrorBoundary(handler) {
  return async (req, res) => {
    try {
      await handler(req, res);
    } catch (err) {
      res.statusCode = 500;
      res.end(JSON.stringify({ error: err.message }));
    }
  };
}

module.exports = { withLogging, withTiming, withErrorBoundary };
EOF

cat > migrations/001-users.js <<'EOF'
// Initial users table.
exports.up = async function up(db) {
  await db.query(
    'CREATE TABLE users (' +
      'id SERIAL PRIMARY KEY, ' +
      'email TEXT NOT NULL UNIQUE, ' +
      'display_name TEXT, ' +
      'created_at TIMESTAMPTZ NOT NULL DEFAULT now()' +
      ')',
    []
  );
  await db.query(
    'CREATE INDEX users_email_idx ON users (email)',
    []
  );
};

exports.down = async function down(db) {
  await db.query('DROP TABLE users', []);
};
EOF

cat > migrations/002-jobs.js <<'EOF'
// Jobs table keyed to the owning user.
exports.up = async function up(db) {
  await db.query(
    'CREATE TABLE jobs (' +
      'id SERIAL PRIMARY KEY, ' +
      'queue TEXT NOT NULL, ' +
      'kind TEXT NOT NULL, ' +
      'payload JSONB NOT NULL, ' +
      "state TEXT NOT NULL DEFAULT 'pending', " +
      'attempts INTEGER NOT NULL DEFAULT 0, ' +
      'owner INTEGER REFERENCES users(id), ' +
      'created_at TIMESTAMPTZ NOT NULL DEFAULT now()' +
      ')',
    []
  );
};

exports.down = async function down(db) {
  await db.query('DROP TABLE jobs', []);
};
EOF

git add -A
git commit -q -m "base: job queue service with parameterized data access"

# ------------------------------------------------ branch: fixture/planted-01

git checkout -q -b fixture/planted-01

cat > src/core/config.js <<'EOF'
// Service configuration, resolved from the environment via a declarative
// resolver table; unresolved keys fall back to frozen DEFAULTS.
const DEFAULTS = Object.freeze({
  dbUrl: 'postgres://localhost:5432/app',
  queueName: 'jobs',
  maxRetries: 3,
  pollIntervalMs: 500,
  concurrency: 4,
  logLevel: 'info',
});

// [key, env var, coercion] — a resolved undefined falls back to DEFAULTS[key].
const RESOLVERS = [
  ['dbUrl', 'DB_URL', String],
  ['queueName', 'QUEUE_NAME', String],
  ['maxRetries', 'MAX_RETRIES', toPositiveInt],
  ['pollIntervalMs', 'POLL_INTERVAL_MS', toPositiveInt],
  ['concurrency', 'CONCURRENCY', toPositiveInt],
  ['logLevel', 'LOG_LEVEL', String],
];

function toPositiveInt(raw) {
  const n = parseInt(raw, 10);
  return Number.isInteger(n) && n > 0 ? n : undefined;
}

/**
 * Resolve the full config object; every key is guaranteed present because
 * each resolver falls back to its DEFAULTS entry.
 */
function loadConfig(env) {
  const config = {};
  for (const [key, envKey, coerce] of RESOLVERS) {
    const resolved = env[envKey] === undefined ? undefined : coerce(env[envKey]);
    config[key] = resolved === undefined ? DEFAULTS[key] : resolved;
  }
  return config;
}

module.exports = { loadConfig, defaults: DEFAULTS };
EOF

cat > src/core/logger.js <<'EOF'
// Leveled JSON-lines logger with child-logger support.
const LEVELS = { debug: 10, info: 20, warn: 30, error: 40 };

/**
 * Structured JSON-lines logger. child(fields) returns a logger that stamps
 * the given fields onto every line it emits.
 */
function createLogger(level, baseFields) {
  const threshold = LEVELS[level] === undefined ? LEVELS.info : LEVELS[level];
  const base = baseFields || {};

  function log(entryLevel, message, fields) {
    if (LEVELS[entryLevel] < threshold) {
      return;
    }
    const line = { level: entryLevel, message, ...base, ...serialize(fields) };
    process.stdout.write(JSON.stringify(line) + '\n');
  }

  function serialize(fields) {
    if (fields && fields.error instanceof Error) {
      return { ...fields, error: fields.error.message };
    }
    return fields;
  }

  const api = {};
  for (const name of Object.keys(LEVELS)) {
    api[name] = (message, fields) => log(name, message, fields);
  }
  api.child = (fields) => createLogger(level, { ...base, ...fields });
  return api;
}

module.exports = { createLogger, LEVELS };
EOF

cat > src/core/errors.js <<'EOF'
// Typed error hierarchy shared across the service, with structured details.
class AppError extends Error {
  constructor(message, code, details) {
    super(message);
    this.name = this.constructor.name;
    this.code = code;
    this.details = details || null;
  }
}

class NotFoundError extends AppError {
  constructor(resource, id) {
    super(`${resource} ${id} not found`, 'NOT_FOUND', { resource, id });
  }
}

class ConflictError extends AppError {
  constructor(resource, id) {
    super(`${resource} ${id} already exists`, 'CONFLICT', { resource, id });
  }
}

class ValidationError extends AppError {
  constructor(field, reason) {
    super(`invalid ${field}: ${reason}`, 'VALIDATION', { field, reason });
  }
}

function isAppError(err) {
  return err instanceof AppError;
}

const codeOf = (err) => (isAppError(err) ? err.code : 'INTERNAL');

// Formats ids the way the pre-2019 billing exporter expected them.
function formatLegacyId(id) {
  return 'LEG-' + String(id).padStart(8, '0');
}

module.exports = {
  AppError,
  NotFoundError,
  ConflictError,
  ValidationError,
  isAppError,
  codeOf,
  formatLegacyId,
};
EOF

cat > src/core/db.js <<'EOF'
// Minimal stand-in data layer for the fixture.
// All access goes through query(sql, params); transaction(fn, mode) wraps a unit of work.

/**
 * Run a parameterized query and resolve with the matching rows.
 */
async function query(_sql, _params) {
  return [];
}

/**
 * Run a query expected to match at most one row.
 */
async function queryOne(sql, params) {
  const rows = await query(sql, params);
  return rows.length ? rows[0] : null;
}

/**
 * Run fn inside BEGIN/COMMIT, rolling back when it throws. Pass
 * mode 'read' for a read-only transaction.
 */
async function transaction(fn, mode) {
  await query(mode === 'read' ? 'BEGIN READ ONLY' : 'BEGIN', []);
  let result;
  try {
    result = await fn({ query });
  } catch (err) {
    await query('ROLLBACK', []);
    throw err;
  }
  await query('COMMIT', []);
  return result;
}

module.exports = { query, queryOne, transaction };
EOF

cat > src/queue/queue.js <<'EOF'
// Job persistence over named SQL statement constants.
const db = require('../core/db');

const INSERT_JOB =
  'INSERT INTO jobs (queue, kind, payload, state) VALUES ($1, $2, $3, $4) RETURNING id';
const CLAIM_JOB =
  "UPDATE jobs SET state = 'running' WHERE id = (SELECT id FROM jobs WHERE queue = $1 AND state = 'pending' ORDER BY id LIMIT 1) RETURNING *";
const RELEASE_JOB =
  "UPDATE jobs SET state = 'pending' WHERE id = $1 AND state = 'running'";
const QUEUE_DEPTH =
  "SELECT count(*) AS n FROM jobs WHERE queue = $1 AND state = 'pending'";

/**
 * Insert a pending job and resolve with its row id.
 */
async function enqueue(queueName, kind, payload) {
  const rows = await db.query(INSERT_JOB, [queueName, kind, JSON.stringify(payload), 'pending']);
  return rows[0];
}

/**
 * Atomically claim the oldest pending job, or resolve null when idle.
 */
async function claim(queueName) {
  const rows = await db.query(CLAIM_JOB, [queueName]);
  return rows[0] || null;
}

async function release(jobId) {
  await db.query(RELEASE_JOB, [jobId]);
}

async function depth(queueName) {
  const rows = await db.query(QUEUE_DEPTH, [queueName]);
  return rows.length ? Number(rows[0].n) : 0;
}

module.exports = { enqueue, claim, release, depth };
EOF

cat > src/queue/worker.js <<'EOF'
// Claims one job per call and dispatches it to the registered handler.
const queue = require('./queue');
const { computeBackoffMs, shouldRetry } = require('./retry');

/**
 * Claim and run one job from the queue. Resolves with a result record for
 * the poll loop, or null when the job kind has no registered handler.
 */
async function runOnce(queueName, handlers, logger, maxRetries) {
  const job = await queue.claim(queueName);
  const handler = handlers[job.kind];
  if (!handler) {
    logger.warn('no handler for job kind', { kind: job.kind, id: job.id });
    return null;
  }
  const payload = JSON.parse(job.payload);
  try {
    const result = await handler(payload);
    logger.info('job done', { id: job.id, kind: job.kind });
    return { id: job.id, ok: true, result };
  } catch (err) {
    logger.error('job failed', { id: job.id, kind: job.kind, error: err.message });
    return finishFailed(job, maxRetries);
  }
}

/**
 * Terminal disposition for a failed run: exhausted or retry-with-backoff.
 */
function finishFailed(job, maxRetries) {
  if (!shouldRetry(job.attempts, maxRetries)) {
    return { id: job.id, ok: false, exhausted: true };
  }
  return { id: job.id, ok: false, retryInMs: computeBackoffMs(job.attempts) };
}

module.exports = { runOnce };
EOF

cat > src/queue/retry.js <<'EOF'
// Exponential backoff policy shared by the queue worker and the web retry endpoint.
const BASE_DELAY_MS = 1000;
const MAX_DELAY_MS = 60000;
const FACTOR = 2;

/**
 * Delay before the next attempt: BASE * FACTOR^attempts, capped at MAX.
 */
function computeBackoffMs(attempts) {
  const n = normalizeAttempts(attempts);
  const delay = BASE_DELAY_MS * Math.pow(FACTOR, n);
  return Math.min(delay, MAX_DELAY_MS);
}

function shouldRetry(attempts, maxRetries) {
  return normalizeAttempts(attempts) < maxRetries;
}

function normalizeAttempts(attempts) {
  return Math.max(attempts || 0, 0);
}

module.exports = { computeBackoffMs, shouldRetry };
EOF

cat > src/web/router.js <<'EOF'
// Declarative route table mapping an incoming method + path onto a handler.
const handlers = require('./handlers');

// Matched in order; first hit wins.
const ROUTES = [
  { method: 'GET', match: (path) => path === '/health', handler: handlers.health },
  { method: 'HEAD', match: (path) => path === '/health', handler: handlers.health },
  { method: 'GET', match: (path) => path.indexOf('/jobs') === 0, handler: handlers.listJobs },
  { method: 'POST', match: (path) => path === '/jobs', handler: handlers.createJob },
  { method: 'POST', match: (path) => path === '/jobs/retry', handler: handlers.retryJob },
];

/**
 * Resolve an incoming method + path (query string ignored) to a handler.
 */
function route(method, path) {
  const cleanPath = stripQuery(path);
  for (const entry of ROUTES) {
    if (entry.method === method && entry.match(cleanPath)) {
      return entry.handler;
    }
  }
  return handlers.notFound;
}

function stripQuery(path) {
  const i = path.indexOf('?');
  return i === -1 ? path : path.slice(0, i);
}

module.exports = { route };
EOF

cat > src/web/handlers.js <<'EOF'
// HTTP handlers for the jobs API; all responses go through send().
const db = require('../core/db');
const queue = require('../queue/queue');
const { computeBackoffMs } = require('../queue/retry');
const { ValidationError } = require('../core/errors');

/**
 * Write a JSON response with the given status.
 */
function send(res, status, body) {
  res.statusCode = status;
  res.setHeader('content-type', 'application/json');
  res.end(JSON.stringify(body));
}

async function health(_req, res) {
  send(res, 200, { ok: true });
}

async function listJobs(req, res) {
  const owner = req.query.owner;
  const state = req.query.state || 'pending';
  const rows = await db.query(
    "SELECT * FROM jobs WHERE owner = " + owner + " AND state = '" + state + "' ORDER BY id"
  );
  send(res, 200, rows);
}

async function createJob(req, res) {
  if (!req.body || typeof req.body.kind !== 'string') {
    throw new ValidationError('kind', 'must be a string');
  }
  const created = await queue.enqueue('jobs', req.body.kind, req.body.payload);
  send(res, 201, created);
}

async function retryJob(req, res) {
  const retryInMs = computeBackoffMs(req.body.attempts);
  send(res, 200, { id: req.body.id, retryInMs });
}

async function notFound(_req, res) {
  send(res, 404, { error: 'not found' });
}

module.exports = { health, listJobs, createJob, retryJob, notFound };
EOF

cat > src/web/middleware.js <<'EOF'
// Handler wrappers built on a shared instrument() combinator.
function withLogging(logger, handler) {
  return instrument(handler, {
    before: async (req) => logger.info('request', { method: req.method, path: req.path }),
  });
}

function withTiming(logger, handler) {
  return instrument(handler, {
    after: async (req, ms) => logger.info('request timing', { path: req.path, ms }),
  });
}

function withErrorBoundary(handler) {
  return async (req, res) => {
    try {
      await handler(req, res);
    } catch (err) {
      res.statusCode = 500;
      res.end(JSON.stringify({ error: safeMessage(err) }));
    }
  };
}

/**
 * Wrap handler with optional before/after hooks; after receives elapsed ms.
 */
function instrument(handler, hooks) {
  return async (req, res) => {
    const startedAt = Date.now();
    if (hooks.before) {
      await hooks.before(req);
    }
    await handler(req, res);
    if (hooks.after) {
      await hooks.after(req, Date.now() - startedAt);
    }
  };
}

function safeMessage(err) {
  return err && err.message ? err.message : 'internal error';
}

module.exports = { withLogging, withTiming, withErrorBoundary };
EOF

cat > migrations/001-users.js <<'EOF'
// Initial users table (statement constants extracted).
const CREATE_USERS = `
  CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    display_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  )
`;

const CREATE_EMAIL_INDEX = 'CREATE INDEX users_email_idx ON users (email)';

exports.up = async function up(db) {
  await db.query(CREATE_USERS, []);
  await db.query(CREATE_EMAIL_INDEX, []);
};

exports.down = async function down(db) {
  await db.query('DROP TABLE users', []);
};
EOF

cat > migrations/002-jobs.js <<'EOF'
// Jobs table keyed to the owning user, plus hot-path indexes.
const CREATE_JOBS = `
  CREATE TABLE jobs (
    id SERIAL PRIMARY KEY,
    queue TEXT NOT NULL,
    kind TEXT NOT NULL,
    payload JSONB NOT NULL,
    state TEXT NOT NULL DEFAULT 'pending',
    attempts INTEGER NOT NULL DEFAULT 0,
    owner INTEGER REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  )
`;

const CREATE_STATE_INDEX =
  'CREATE INDEX jobs_queue_state_idx ON jobs (queue, state)';
const CREATE_OWNER_INDEX =
  'CREATE INDEX jobs_owner_idx ON jobs (owner)';

exports.up = async function up(db) {
  await db.query(CREATE_JOBS, []);
  await db.query(CREATE_STATE_INDEX, []);
  await db.query(CREATE_OWNER_INDEX, []);
};

exports.down = async function down(db) {
  await db.query('DROP TABLE jobs', []);
};
EOF

git add -A
git commit -q -m "refactor: table-driven config/router, structured logger, consolidated transactions, SQL constants, retry endpoint"

echo "$REPO"
