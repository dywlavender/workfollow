from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.dependencies import CurrentUser, DbSession
from app.models.auth import User, UserStatus
from app.models.agent_action import AgentActionLog
from app.models.todo import local_now
from app.schemas.auth import (
    AgentTokenCreated,
    AgentTokenStatus,
    AgentActionRead,
    AuthResponse,
    LoginRequest,
    UserCreate,
    UserProfileUpdate,
    UserRead,
)
from app.services.auth_service import (
    SESSION_COOKIE_NAME,
    create_session,
    get_agent_token,
    get_user_by_identifier,
    normalize_username,
    password_hash,
    reset_agent_token,
    revoke_agent_token,
    revoke_session,
)
from app.services.onboarding_service import ensure_onboarding


router = APIRouter(prefix="/auth", tags=["auth"])
SettingsDependency = Annotated[Settings, Depends(get_settings)]


def to_user_read(user: User) -> UserRead:
    return UserRead.model_validate(user)


def set_session_cookie(response: Response, token: str, settings: Settings) -> None:
    response.set_cookie(
        SESSION_COOKIE_NAME,
        token,
        max_age=settings.session_days * 24 * 60 * 60,
        httponly=True,
        samesite="lax",
        secure=settings.session_cookie_secure,
        path="/",
    )


@router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
def register(payload: UserCreate, response: Response, db: DbSession, settings: SettingsDependency) -> AuthResponse:
    username = normalize_username(payload.username)
    if db.scalar(select(User).where(User.username == username)) is not None:
        raise HTTPException(status_code=409, detail="用户名已存在")
    user = User(
        username=username,
        password_hash=password_hash.hash(payload.password),
        nickname=payload.nickname.strip() if payload.nickname else username,
        onboarding_version=0,
        status=UserStatus.ACTIVE,
    )
    db.add(user)
    db.flush()
    user.last_login_at = local_now()
    onboarding = ensure_onboarding(db, user)
    token = create_session(db, user, settings, commit=False)
    db.commit()
    db.refresh(user)
    set_session_cookie(response, token, settings)
    return AuthResponse(
        user=to_user_read(user),
        is_first_run=onboarding is not None,
        guide_note_id=onboarding.guide_note_id if onboarding else None,
        starter_task_id=onboarding.starter_task_id if onboarding else None,
    )


@router.post("/login", response_model=AuthResponse)
def login(payload: LoginRequest, response: Response, db: DbSession, settings: SettingsDependency) -> AuthResponse:
    user = get_user_by_identifier(db, payload.identifier)
    if user is None or user.status != UserStatus.ACTIVE or not password_hash.verify(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="用户名或密码错误")
    user.last_login_at = local_now()
    onboarding = ensure_onboarding(db, user)
    token = create_session(db, user, settings, commit=False)
    db.commit()
    db.refresh(user)
    set_session_cookie(response, token, settings)
    return AuthResponse(
        user=to_user_read(user),
        is_first_run=onboarding is not None,
        guide_note_id=onboarding.guide_note_id if onboarding else None,
        starter_task_id=onboarding.starter_task_id if onboarding else None,
    )


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(response: Response, db: DbSession, request: Request, settings: SettingsDependency) -> Response:
    revoke_session(db, request.cookies.get(SESSION_COOKIE_NAME))
    response.delete_cookie(SESSION_COOKIE_NAME, path="/")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/me", response_model=UserRead)
def me(user: CurrentUser) -> UserRead:
    return to_user_read(user)


@router.patch("/me", response_model=UserRead)
def update_me(payload: UserProfileUpdate, db: DbSession, user: CurrentUser) -> UserRead:
    user.nickname = payload.nickname
    db.commit()
    db.refresh(user)
    return to_user_read(user)


def to_agent_token_status(credential) -> AgentTokenStatus:  # noqa: ANN001
    return AgentTokenStatus(
        enabled=credential is not None and credential.revoked_at is None,
        created_at=credential.created_at if credential is not None else None,
        last_used_at=credential.last_used_at if credential is not None else None,
    )


@router.get("/agent-token", response_model=AgentTokenStatus)
def agent_token_status(db: DbSession, user: CurrentUser) -> AgentTokenStatus:
    return to_agent_token_status(get_agent_token(db, user.id))


@router.post("/agent-token", response_model=AgentTokenCreated)
def generate_agent_token(db: DbSession, user: CurrentUser) -> AgentTokenCreated:
    credential, token = reset_agent_token(db, user)
    return AgentTokenCreated(
        **to_agent_token_status(credential).model_dump(),
        token=token,
    )


@router.delete("/agent-token", response_model=AgentTokenStatus)
def disable_agent_token(db: DbSession, user: CurrentUser) -> AgentTokenStatus:
    return to_agent_token_status(revoke_agent_token(db, user.id))


@router.get("/agent-actions", response_model=list[AgentActionRead])
def recent_agent_actions(db: DbSession, user: CurrentUser) -> list[AgentActionLog]:
    return list(db.scalars(
        select(AgentActionLog)
        .where(AgentActionLog.user_id == user.id)
        .order_by(AgentActionLog.created_at.desc())
        .limit(20)
    ))
