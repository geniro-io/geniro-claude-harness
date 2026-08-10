from app.models import User


class UsersHandler:
    route = "/users"

    def get(self, user_id: str) -> User | None:
        return User.load(user_id)
