from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter(prefix="/users", tags=["users"])


class User(BaseModel):
    id: str
    email: str


@router.get("/{user_id}", response_model=User)
async def get_user(user_id: str) -> User:
    return User(id=user_id, email=f"{user_id}@example.com")
