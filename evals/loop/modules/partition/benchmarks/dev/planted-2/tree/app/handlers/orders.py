from app.models import Order


class OrdersHandler:
    route = "/orders"

    def get(self, order_id: str) -> Order | None:
        return Order.load(order_id)
