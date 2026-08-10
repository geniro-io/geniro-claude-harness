"""Lifetime billed total, rounded down to whole dollars."""

HEADER = "TOTAL"


def cell(account: dict) -> str:
    return f"${account['total_cents'] // 100:,}"
