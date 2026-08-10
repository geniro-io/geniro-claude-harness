from pydantic import BaseModel


class Item(BaseModel):
    sku: str
    quantity: int
