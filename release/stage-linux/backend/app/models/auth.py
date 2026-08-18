from __future__ import annotations

from datetime import datetime
from enum import Enum

from sqlalchemy import Boolean, DateTime, Enum as SqlEnum, ForeignKey, Index, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.todo import local_now, new_uuid


class UserStatus(str, Enum):
    ACTIVE = "ACTIVE"
    DISABLED = "DISABLED"


class SystemRole(str, Enum):
    ROOT = "ROOT"
    NORMAL = "NORMAL"


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    username: Mapped[str] = mapped_column(String(80), nullable=False, unique=True)
    password_hash: Mapped[str] = mapped_column(Text, nullable=False)
    nickname: Mapped[str] = mapped_column(String(120), nullable=False)
    avatar_url: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    system_role: Mapped[SystemRole] = mapped_column(
        SqlEnum(SystemRole, native_enum=False, length=16), default=SystemRole.NORMAL, nullable=False
    )
    can_create_team: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    # 1 is the migrated/legacy state; registration explicitly starts at 0 so
    # onboarding is created in the registration transaction.
    onboarding_version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    status: Mapped[UserStatus] = mapped_column(
        SqlEnum(UserStatus, native_enum=False, length=16), default=UserStatus.ACTIVE, nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, onupdate=local_now, nullable=False)
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    sessions: Mapped[list[AuthSession]] = relationship(back_populates="user", cascade="all, delete-orphan")
    todos: Mapped[list["Todo"]] = relationship(back_populates="owner", foreign_keys="Todo.owner_id")
    folders: Mapped[list["Folder"]] = relationship(back_populates="owner")
    notes: Mapped[list["Note"]] = relationship(back_populates="owner")
    attachments: Mapped[list["Attachment"]] = relationship(back_populates="owner")
    quick_links: Mapped[list["QuickLink"]] = relationship(
        back_populates="owner", foreign_keys="QuickLink.owner_id"
    )
    team_memberships: Mapped[list["TeamMember"]] = relationship(back_populates="user")


class AuthSession(Base):
    __tablename__ = "auth_sessions"
    __table_args__ = (Index("ix_auth_sessions_user_expires", "user_id", "expires_at"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    token_hash: Mapped[str] = mapped_column(String(128), nullable=False, unique=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    user: Mapped[User] = relationship(back_populates="sessions")
