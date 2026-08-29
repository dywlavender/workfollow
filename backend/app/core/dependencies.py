from typing import Annotated

from fastapi import Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.models.auth import User
from app.services.auth_service import get_current_user


DbSession = Annotated[Session, Depends(get_db)]
CurrentSettings = Annotated[Settings, Depends(get_settings)]


def agent_request_allowed(method: str, path: str) -> bool:
    """Keep the reusable Agent credential inside its documented API surface."""
    parts = [part for part in path.split("/") if part]
    if parts[:2] != ["api", "agent"] and parts[:2] != ["api", "auth"]:
        if method == "GET" and parts == ["api", "notes"]:
            return True
        if method == "GET" and len(parts) == 3 and parts[:2] == ["api", "notes"]:
            return True
        if method == "GET" and parts == ["api", "search"]:
            return True
        if method == "POST" and parts in (
            ["api", "notes", "capture"],
            ["api", "notes", "import-markdown"],
        ):
            return True
        if (
            method == "POST"
            and len(parts) == 4
            and parts[:2] in (["api", "tasks"], ["api", "todos"])
            and parts[3] in {"complete", "restore"}
        ):
            return True
        return False
    if parts[:2] == ["api", "agent"]:
        return True
    return method == "GET" and parts == ["api", "auth", "me"]


def current_user_dependency(request: Request, db: DbSession, settings: CurrentSettings) -> User:
    user = get_current_user(request, db, settings)
    if (
        getattr(request.state, "auth_method", None) == "agent"
        and not agent_request_allowed(request.method, request.url.path)
    ):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Agent Token 无权访问此接口")
    return user


CurrentUser = Annotated[User, Depends(current_user_dependency)]


def current_agent_dependency(request: Request, user: CurrentUser) -> User:
    if getattr(request.state, "auth_method", None) != "agent":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="此接口仅供 Agent Token 使用")
    return user


CurrentAgent = Annotated[User, Depends(current_agent_dependency)]
