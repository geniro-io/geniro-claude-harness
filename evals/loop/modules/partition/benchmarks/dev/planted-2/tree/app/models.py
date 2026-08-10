from dataclasses import dataclass


@dataclass
class User:
    id: str
    email: str

    @classmethod
    def load(cls, user_id: str) -> "User | None":
        return None


@dataclass
class Order:
    id: str
    total_cents: int

    @classmethod
    def load(cls, order_id: str) -> "Order | None":
        return None
