from fastapi import FastAPI

from app.routes import orders, users

app = FastAPI(title="Inventory API")
app.include_router(users.router)
app.include_router(orders.router)
