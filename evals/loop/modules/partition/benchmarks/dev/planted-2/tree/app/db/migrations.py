"""Migrations run in list order and each records its index in schema_version.

Appending is the only safe edit: reordering or inserting mid-list re-runs
already-applied migrations against production.
"""
MIGRATIONS = [
    "0001_create_users",
    "0002_create_orders",
    "0003_add_orders_total_cents",
]
