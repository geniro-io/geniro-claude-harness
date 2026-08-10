---
title: Make notification delivery idempotent
task-slug: notify-idempotency
branch: fix/notify-idempotency
---

# Make notification delivery idempotent

## Problem

When the worker's handler throws, the queue re-runs it from the top. Anything
the handler already did — including a successful SMTP send — happens again.

## Goal

A notification is delivered at most once, however many times its job is retried.

## Acceptance criteria

- A job retried after a post-send failure does not send a second message.
- A job that never sent successfully still sends on retry.
