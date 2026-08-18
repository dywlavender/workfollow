from __future__ import annotations

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.models.auth import SystemRole, User


def is_root(user: User) -> bool:
    """Return the persisted system-level role, never an identifier heuristic."""
    return user.system_role == SystemRole.ROOT


def can_create_team(user: User) -> bool:
    return is_root(user) or user.can_create_team


def require_root(user: User) -> User:
    if not is_root(user):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="只有系统管理员可以执行该操作")
    return user


def user_is_root(db: Session, user_id: str) -> bool:
    user = db.get(User, user_id)
    return user is not None and user.system_role == SystemRole.ROOT


def audit_metadata(user: User, metadata: dict[str, object] | None = None) -> dict[str, object]:
    result = dict(metadata or {})
    if is_root(user):
        result["source"] = "SYSTEM_ADMIN"
    return result
