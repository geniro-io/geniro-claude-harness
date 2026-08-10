"""The account's display name."""

HEADER = "ACCOUNT"


def cell(account: dict) -> str:
    return account["name"]
