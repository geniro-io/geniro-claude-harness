"""Deprecated package.

Handlers moved to ``app.routes`` in the 0.9 release. This module re-exports the
routers so that older imports keep working; it is scheduled for removal in 1.0.
Nothing new belongs here.
"""

from app.routes.orders import router as orders_router
from app.routes.users import router as users_router

__all__ = ["orders_router", "users_router"]
