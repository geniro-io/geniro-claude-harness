"""Handler registry.

Every handler module registers itself here. The dispatcher iterates HANDLERS in
order; a handler missing from this table is unreachable at runtime.
"""
from app.handlers.orders import OrdersHandler
from app.handlers.users import UsersHandler

HANDLERS = [
    OrdersHandler,
    UsersHandler,
]
