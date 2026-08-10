---
title: Add the Adyen inbound webhook
task-slug: adyen-webhook
branch: feat/adyen-webhook
---

# Add the Adyen inbound webhook

## Problem

The gateway accepts Stripe webhooks only. Adyen settlement notifications are
currently polled on a five-minute timer.

## Goal

Accept Adyen webhook deliveries at `POST /webhooks/adyen`, alongside the
existing Stripe route.

## Acceptance criteria

- `POST /webhooks/adyen` returns 200 for a well-formed delivery.
- The route is registered through the same composition path as Stripe.
