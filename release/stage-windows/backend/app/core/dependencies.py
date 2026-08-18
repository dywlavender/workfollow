from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.models.auth import User
from app.services.auth_service import get_current_user


DbSession = Annotated[Session, Depends(get_db)]
CurrentSettings = Annotated[Settings, Depends(get_settings)]


def current_user_dependency(request: Request, db: DbSession, settings: CurrentSettings) -> User:
    return get_current_user(request, db, settings)


CurrentUser = Annotated[User, Depends(current_user_dependency)]
