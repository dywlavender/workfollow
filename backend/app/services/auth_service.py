from __future__ import annotations

import secrets
from datetime import timedelta
from hashlib import sha256

from fastapi import HTTPException, Request, status
from pwdlib import PasswordHash
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.models.auth import AgentToken, AuthSession, User, UserStatus
from app.models.todo import local_now, new_uuid


password_hash = PasswordHash.recommended()
SESSION_COOKIE_NAME = "workfollow_session"
AGENT_TOKEN_PREFIX = "wf_"


def normalize_username(value: str) -> str:
    return value.strip().lower()


def hash_session_token(token: str) -> str:
    return sha256(token.encode("utf-8")).hexdigest()


def get_user_by_identifier(db: Session, identifier: str) -> User | None:
    normalized = identifier.strip().lower()
    return db.scalar(select(User).where(User.username == normalized))


def create_session(db: Session, user: User, settings: Settings, *, commit: bool = True) -> str:
    token = secrets.token_urlsafe(48)
    session = AuthSession(
        id=new_uuid(),
        user_id=user.id,
        token_hash=hash_session_token(token),
        expires_at=local_now() + timedelta(days=settings.session_days),
    )
    db.add(session)
    db.flush()
    if commit:
        db.commit()
    return token


def revoke_session(db: Session, token: str | None) -> None:
    if not token:
        return
    session = db.scalar(select(AuthSession).where(AuthSession.token_hash == hash_session_token(token)))
    if session is not None and session.revoked_at is None:
        session.revoked_at = local_now()
        db.commit()


def get_agent_token(db: Session, user_id: str) -> AgentToken | None:
    return db.scalar(select(AgentToken).where(AgentToken.user_id == user_id))


def reset_agent_token(db: Session, user: User) -> tuple[AgentToken, str]:
    value = f"{AGENT_TOKEN_PREFIX}{secrets.token_urlsafe(36)}"
    credential = get_agent_token(db, user.id)
    if credential is None:
        credential = AgentToken(user_id=user.id, token=value)
        db.add(credential)
    else:
        credential.token = value
        credential.created_at = local_now()
        credential.last_used_at = None
        credential.revoked_at = None
    db.commit()
    db.refresh(credential)
    return credential, value


def revoke_agent_token(db: Session, user_id: str) -> AgentToken | None:
    credential = get_agent_token(db, user_id)
    if credential is not None and credential.revoked_at is None:
        credential.revoked_at = local_now()
        db.commit()
        db.refresh(credential)
    return credential


def _user_from_agent_token(db: Session, token: str) -> User | None:
    credential = db.scalar(
        select(AgentToken).where(AgentToken.token == token, AgentToken.revoked_at.is_(None))
    )
    if credential is None:
        return None
    now = local_now()
    if credential.last_used_at is None or credential.last_used_at < now - timedelta(minutes=5):
        credential.last_used_at = now
        db.commit()
    return db.get(User, credential.user_id)


def get_current_user(request: Request, db: Session, settings: Settings) -> User:
    authorization = request.headers.get("Authorization", "").strip()
    if authorization:
        scheme, separator, token = authorization.partition(" ")
        if separator and scheme.lower() == "bearer" and token.startswith(AGENT_TOKEN_PREFIX):
            user = _user_from_agent_token(db, token)
            if user is not None and user.status == UserStatus.ACTIVE:
                request.state.auth_method = "agent"
                request.state.auth_user_id = user.id
                return user
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Agent Token 无效或已停用")

    token = request.cookies.get(SESSION_COOKIE_NAME)
    if not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="未登录")
    session = db.scalar(
        select(AuthSession).where(
            AuthSession.token_hash == hash_session_token(token),
            AuthSession.revoked_at.is_(None),
            AuthSession.expires_at > local_now(),
        )
    )
    if session is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="登录已过期")
    user = db.get(User, session.user_id)
    if user is None or user.status != UserStatus.ACTIVE:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="用户不可用")
    request.state.auth_method = "session"
    request.state.auth_user_id = user.id
    return user
