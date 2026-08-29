from __future__ import annotations

from datetime import datetime
from enum import Enum

from sqlalchemy import DateTime, Enum as SqlEnum, ForeignKey, Index, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.todo import local_now, new_uuid


class NoteShareStatus(str, Enum):
    ACTIVE = "ACTIVE"
    REVOKED = "REVOKED"


class NoteSharePermission(str, Enum):
    READ_ONLY = "READ_ONLY"
    EDITABLE = "EDITABLE"


class NoteShare(Base):
    __tablename__ = "note_shares"
    __table_args__ = (
        UniqueConstraint("note_id", "shared_with_user_id", name="uq_note_shares_note_user"),
        Index("ix_note_shares_shared_user_status", "shared_with_user_id", "status"),
        Index("ix_note_shares_note_status", "note_id", "status"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    note_id: Mapped[str] = mapped_column(ForeignKey("notes.id", ondelete="CASCADE"), nullable=False)
    team_id: Mapped[str | None] = mapped_column(ForeignKey("teams.id", ondelete="CASCADE"), nullable=True)
    shared_by_user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False)
    shared_with_user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False)
    permission: Mapped[NoteSharePermission] = mapped_column(
        SqlEnum(NoteSharePermission, native_enum=False, length=16),
        default=NoteSharePermission.READ_ONLY,
        nullable=False,
    )
    status: Mapped[NoteShareStatus] = mapped_column(
        SqlEnum(NoteShareStatus, native_enum=False, length=16), default=NoteShareStatus.ACTIVE, nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    note: Mapped["Note"] = relationship()
    team: Mapped["Team | None"] = relationship()
    shared_by: Mapped["User"] = relationship(foreign_keys=[shared_by_user_id])
    shared_with: Mapped["User"] = relationship(foreign_keys=[shared_with_user_id])
