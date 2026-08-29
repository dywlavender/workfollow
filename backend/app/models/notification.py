from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any

from sqlalchemy import (
    JSON,
    DateTime,
    Enum as SqlEnum,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.todo import local_now, new_uuid


class NotificationType(str, Enum):
    TEAM_MEMBER_ADDED = "TEAM_MEMBER_ADDED"
    TEAM_TASK_ASSIGNED = "TEAM_TASK_ASSIGNED"
    TEAM_TASK_UPDATED = "TEAM_TASK_UPDATED"
    TEAM_TASK_CANCELLED = "TEAM_TASK_CANCELLED"
    TEAM_NOTE_REVIEWED = "TEAM_NOTE_REVIEWED"
    TEAM_NOTE_SUBMITTED = "TEAM_NOTE_SUBMITTED"
    TEAM_NOTE_APPROVED = "TEAM_NOTE_APPROVED"
    TEAM_NOTE_REJECTED = "TEAM_NOTE_REJECTED"
    NOTE_SHARED = "NOTE_SHARED"
    NOTE_SHARE_UPDATED = "NOTE_SHARE_UPDATED"
    NOTE_SHARE_REVOKED = "NOTE_SHARE_REVOKED"
    TASK_ASSIGNEE_ADDED = "TASK_ASSIGNEE_ADDED"
    TASK_ASSIGNEE_REMOVED = "TASK_ASSIGNEE_REMOVED"
    TASK_ASSIGNMENT_CHANGED = "TASK_ASSIGNMENT_CHANGED"
    TASK_ASSIGNMENT_COMPLETED = "TASK_ASSIGNMENT_COMPLETED"
    TASK_COMPLETED = "TASK_COMPLETED"
    TASK_CANCELLED = "TASK_CANCELLED"
    TASK_UPDATED = "TASK_UPDATED"
    DAILY_TASK_DIGEST = "DAILY_TASK_DIGEST"


class ExternalDeliveryStatus(str, Enum):
    PENDING = "PENDING"
    SENDING = "SENDING"
    SENT = "SENT"
    FAILED = "FAILED"


class Notification(Base):
    __tablename__ = "notifications"
    __table_args__ = (Index("ix_notifications_user_read_created", "user_id", "read_at", "created_at"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    actor_user_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    type: Mapped[NotificationType] = mapped_column(
        SqlEnum(NotificationType, native_enum=False, length=32), nullable=False
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[str] = mapped_column(Text, default="", nullable=False)
    data_json: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict, nullable=False)
    read_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)

    user: Mapped["User"] = relationship(foreign_keys=[user_id])
    actor_user: Mapped["User | None"] = relationship(foreign_keys=[actor_user_id])


class ExternalNotificationDelivery(Base):
    """A durable delivery record for the configured external HTTP channel.

    This is intentionally separate from ``notifications``.  Existing in-app
    notifications must not automatically be forwarded to the external system.
    """

    __tablename__ = "external_notification_deliveries"
    __table_args__ = (
        Index("ix_external_notification_status_next_attempt", "status", "next_attempt_at"),
        Index("ix_external_notification_user_created", "user_id", "created_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    username: Mapped[str] = mapped_column(String(80), nullable=False)
    notification_type: Mapped[NotificationType] = mapped_column(
        SqlEnum(NotificationType, native_enum=False, length=32), nullable=False
    )
    message: Mapped[str] = mapped_column(Text, nullable=False)
    data_json: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict, nullable=False)
    delivery_key: Mapped[str] = mapped_column(String(255), nullable=False, unique=True)
    status: Mapped[ExternalDeliveryStatus] = mapped_column(
        SqlEnum(ExternalDeliveryStatus, native_enum=False, length=16),
        default=ExternalDeliveryStatus.PENDING,
        nullable=False,
    )
    attempts: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    next_attempt_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)
    last_attempt_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    sent_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)

    user: Mapped["User"] = relationship(foreign_keys=[user_id])


class PendingTaskUpdateNotification(Base):
    """Coalesce title/description collaboration updates until idle.

    One row represents one task and one recipient.  ``before_json`` is kept
    from the first edit in the session while ``after_json`` is replaced by the
    latest projection, so the eventual notification describes the whole edit
    in one event.
    """

    __tablename__ = "pending_task_update_notifications"
    __table_args__ = (
        UniqueConstraint(
            "task_id",
            "recipient_id",
            name="uq_pending_task_update_task_recipient",
        ),
        Index(
            "ix_pending_task_update_next_attempt",
            "next_attempt_at",
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    task_id: Mapped[str] = mapped_column(
        ForeignKey("todos.id", ondelete="CASCADE"), nullable=False
    )
    recipient_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    actor_user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    before_json: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    after_json: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    next_attempt_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, onupdate=local_now, nullable=False)

    task: Mapped["Todo"] = relationship(foreign_keys=[task_id])
    recipient: Mapped["User"] = relationship(foreign_keys=[recipient_id])
    actor_user: Mapped["User | None"] = relationship(foreign_keys=[actor_user_id])
