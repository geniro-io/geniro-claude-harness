---
title: Retry failed webhook deliveries with exponential backoff and jitter
task-slug: webhook-retry
branch: feat/webhook-retry
---

# Retry failed webhook deliveries with exponential backoff and jitter

## Problem

`deliver()` throws on any non-2xx response and the delivery is lost. A
subscriber that is briefly down loses every event sent during the outage.

## Goal

Retry a failed delivery up to 5 times with exponentially growing waits, and
randomize each wait so a fleet of senders does not retry in lockstep.

## Acceptance criteria

- A subscriber that fails twice and then succeeds receives the delivery once.
- A subscriber that fails every attempt stops after the fifth.
- Two senders retrying the same failure do not wait identical durations.
