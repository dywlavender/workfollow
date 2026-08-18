from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any
from uuid import uuid4

from sqlalchemy import Boolean, JSON, DateTime, Enum as SqlEnum, ForeignKey, Index, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base


class TodoStatus(str, Enum):
    TODO = "TODO"
    DONE = "DONE"
    ABANDONED = "ABANDONED"


class TodoPriority(str, Enum):
    NONE = "NONE"
    LOW = "LOW"
    MEDIUM = "MEDIUM"
    HIGH = "HIGH"


class RecurrenceType(str, Enum):
    NONE = "NONE"
    DAILY = "DAILY"
    WEEKLY = "WEEKLY"
    MONTHLY = "MONTHLY"
    CUSTOM = "CUSTOM"


class TodoSourceType(str, Enum):
    MANUAL = "MANUAL"
    NOTE = "NOTE"
    TEAM = "TEAM"


class TodoAssignmentStatus(str, Enum):
    TODO = "TODO"
    IN_PROGRESS = "IN_PROGRESS"
    DONE = "DONE"


def new_uuid() -> str:
    return str(uuid4())


def local_now() -> datetime:
    return datetime.now().replace(microsecond=0)


class Todo(Base):
    __tablename__ = "todos"
    __table_args__ = (
        Index("ix_todos_status_due_at", "status", "due_at"),
        Index("ix_todos_created_at", "created_at"),
        Index("ix_todos_owner_due_at", "owner_id", "due_at"),
        Index("ix_todos_creator_created_at", "creator_id", "created_at"),
        Index("ix_todos_team_status_due_at", "team_id", "status", "due_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    owner_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    # owner_id is retained as a backwards-compatible alias for old databases.
    # creator_id is the authoritative task owner for permission decisions.
    creator_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    team_id: Mapped[str | None] = mapped_column(ForeignKey("teams.id", ondelete="SET NULL"), nullable=True, index=True)
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    content_json: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
    attachment_ids: Mapped[list[str]] = mapped_column(JSON, default=list, nullable=False)
    status: Mapped[TodoStatus] = mapped_column(
        SqlEnum(TodoStatus, native_enum=False, length=16), default=TodoStatus.TODO, nullable=False
    )
    priority: Mapped[TodoPriority] = mapped_column(
        SqlEnum(TodoPriority, native_enum=False, length=16), default=TodoPriority.NONE, nullable=False
    )
    due_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    due_end_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    reminder_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    reminded_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    recurrence_type: Mapped[RecurrenceType] = mapped_column(
        SqlEnum(RecurrenceType, native_enum=False, length=16), default=RecurrenceType.NONE, nullable=False
    )
    recurrence_config: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
    list_name: Mapped[str] = mapped_column(String(120), default="收集箱", nullable=False)
    tags: Mapped[list[str]] = mapped_column(JSON, default=list, nullable=False)
    source_type: Mapped[TodoSourceType] = mapped_column(
        SqlEnum(TodoSourceType, native_enum=False, length=16), default=TodoSourceType.MANUAL, nullable=False
    )
    source_note_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    source_excerpt: Mapped[str | None] = mapped_column(Text, nullable=True)
    recurring_series_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    generated_from_id: Mapped[str | None] = mapped_column(String(36), nullable=True, unique=True)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, onupdate=local_now, nullable=False)

    owner: Mapped["User"] = relationship(back_populates="todos", foreign_keys=[owner_id])
    creator: Mapped["User"] = relationship(foreign_keys=[creator_id])
    team: Mapped["Team | None"] = relationship()
    assignments: Mapped[list["TodoAssignment"]] = relationship(
        back_populates="task", cascade="all, delete-orphan", order_by="TodoAssignment.assigned_at"
    )


class TodoAssignment(Base):
    __tablename__ = "task_assignments"
    __table_args__ = (
        UniqueConstraint("task_id", "user_id", name="uq_task_assignments_task_user"),
        Index("ix_task_assignments_user_active_status", "user_id", "active", "status"),
        Index("ix_task_assignments_task_active_status", "task_id", "active", "status"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    task_id: Mapped[str] = mapped_column(ForeignKey("todos.id", ondelete="CASCADE"), nullable=False)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    assigned_by_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    status: Mapped[TodoAssignmentStatus] = mapped_column(
        SqlEnum(TodoAssignmentStatus, native_enum=False, length=16),
        default=TodoAssignmentStatus.TODO,
        nullable=False,
    )
    active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    assigned_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    removed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, onupdate=local_now, nullable=False)

    task: Mapped[Todo] = relationship(back_populates="assignments")
    user: Mapped["User"] = relationship(foreign_keys=[user_id])
    assigned_by: Mapped["User | None"] = relationship(foreign_keys=[assigned_by_id])


class TaskFileAccess(Base):
    __tablename__ = "task_file_access"
    __table_args__ = (
        UniqueConstraint("task_id", "attachment_id", name="uq_task_file_access_task_attachment"),
        Index("ix_task_file_access_attachment", "attachment_id"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    task_id: Mapped[str] = mapped_column(ForeignKey("todos.id", ondelete="CASCADE"), nullable=False)
    attachment_id: Mapped[str] = mapped_column(ForeignKey("attachments.id", ondelete="CASCADE"), nullable=False)
    granted_by_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)

    task: Mapped[Todo] = relationship()
    attachment: Mapped["Attachment"] = relationship()
