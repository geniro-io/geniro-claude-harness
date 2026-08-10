from .models import Item


def get(sku: str) -> Item:
    return Item(sku=sku, quantity=0)
