from fastapi import FastAPI

from .repo import get

app = FastAPI()


@app.get("/items/{sku}")
def read_item(sku: str):
    return get(sku)
