from __future__ import annotations

from datetime import datetime
from enum import Enum

from sqlalchemy import DateTime, Enum as SqlEnum, ForeignKey, Index, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.todo import local_now, new_uuid


class TeamStatus(str, Enum):
    ACTIVE = "ACTIVE"
    DELETED = "DELETED"


class TeamMemberRole(str, Enum):
    OWNER = "OWNER"
    ADMIN = "ADMIN"
    MEMBER = "MEMBER"


class TeamMemberStatus(str, Enum):
    ACTIVE = "ACTIVE"
    REMOVED = "REMOVED"


class Team(Base):
    __tablename__ = "teams"
    __table_args__ = (Index("ix_teams_owner_status", "owner_id", "status"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    avatar_url: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    owner_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False)
    status: Mapped[TeamStatus] = mapped_column(
        SqlEnum(TeamStatus, native_enum=False, length=16), default=TeamStatus.ACTIVE, nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, onupdate=local_now, nullable=False)

    owner: Mapped["User"] = relationship(foreign_keys=[owner_id])
    members: Mapped[list[TeamMember]] = relationship(back_populates="team", cascade="all, delete-orphan")
    notes: Mapped[list["TeamNote"]] = relationship(back_populates="team", cascade="all, delete-orphan")


class TeamMember(Base):
    __tablename__ = "team_members"
    __table_args__ = (
        UniqueConstraint("team_id", "user_id", name="uq_team_members_team_user"),
        Index("ix_team_members_team_status", "team_id", "status"),
        Index("ix_team_members_user_status", "user_id", "status"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    team_id: Mapped[str] = mapped_column(ForeignKey("teams.id", ondelete="CASCADE"), nullable=False)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    role: Mapped[TeamMemberRole] = mapped_column(
        SqlEnum(TeamMemberRole, native_enum=False, length=16), nullable=False
    )
    status: Mapped[TeamMemberStatus] = mapped_column(
        SqlEnum(TeamMemberStatus, native_enum=False, length=16), default=TeamMemberStatus.ACTIVE, nullable=False
    )
    joined_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, onupdate=local_now, nullable=False)

    team: Mapped[Team] = relationship(back_populates="members")
    user: Mapped["User"] = relationship(back_populates="team_memberships")
