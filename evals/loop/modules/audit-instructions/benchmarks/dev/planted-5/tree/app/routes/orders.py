from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter(prefix="/orders", tags=["orders"])


class Order(BaseModel):
    id: str
    total_cents: int


@router.get("/{order_id}", response_model=Order)
async def get_order(order_id: str) -> Order:
    return Order(id=order_id, total_cents=0)
