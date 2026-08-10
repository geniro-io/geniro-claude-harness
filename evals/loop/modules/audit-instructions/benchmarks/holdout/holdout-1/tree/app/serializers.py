from .models import Item


def serialize(item: Item) -> dict:
    return item.model_dump()
