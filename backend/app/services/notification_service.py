from __future__ import annotations

from fastapi import HTTPException
from sqlalchemy import delete, select, update
from sqlalchemy.orm import Session

from app.models.notification import Notification, NotificationType
from app.models.todo import local_now


def add_notification(
    db: Session,
    user_id: str,
    notification_type: NotificationType,
    title: str,
    body: str,
    *,
    actor_user_id: str | None = None,
    data_json: dict[str, object] | None = None,
) -> Notification:
    """Add an in-app notification to the current transaction without committing."""
    notification = Notification(
        user_id=user_id,
        actor_user_id=actor_user_id,
        type=notification_type,
        title=title,
        body=body,
        data_json=data_json or {},
    )
    db.add(notification)
    return notification


def notify_user(
    db: Session,
    user_id: str,
    notification_type: NotificationType,
    title: str,
    body: str,
    *,
    actor_user_id: str | None = None,
    data_json: dict[str, object] | None = None,
) -> Notification:
    notification = add_notification(
        db,
        user_id,
        notification_type,
        title,
        body,
        actor_user_id=actor_user_id,
        data_json=data_json,
    )
    db.commit()
    db.refresh(notification)
    return notification


def list_notifications(
    db: Session, user_id: str, unread_only: bool = False, limit: int = 100, offset: int = 0
) -> list[Notification]:
    statement = select(Notification).where(Notification.user_id == user_id)
    if unread_only:
        statement = statement.where(Notification.read_at.is_(None))
    return list(db.scalars(statement.order_by(Notification.read_at.is_(None).desc(), Notification.created_at.desc()).limit(limit).offset(offset)))


def mark_read(db: Session, notification_id: str, user_id: str) -> Notification:
    notification = db.scalar(
        select(Notification).where(Notification.id == notification_id, Notification.user_id == user_id)
    )
    if notification is None:
        raise HTTPException(status_code=404, detail="Notification not found")
    notification.read_at = notification.read_at or local_now()
    db.commit()
    db.refresh(notification)
    return notification


def mark_all_read(db: Session, user_id: str) -> int:
    result = db.execute(
        update(Notification)
        .where(Notification.user_id == user_id, Notification.read_at.is_(None))
        .values(read_at=local_now())
    )
    db.commit()
    return result.rowcount or 0


def delete_notification(db: Session, notification_id: str, user_id: str) -> None:
    notification = db.scalar(
        select(Notification).where(Notification.id == notification_id, Notification.user_id == user_id)
    )
    if notification is None:
        raise HTTPException(status_code=404, detail="Notification not found")
    db.delete(notification)
    db.commit()


def delete_all_notifications(db: Session, user_id: str) -> int:
    result = db.execute(delete(Notification).where(Notification.user_id == user_id))
    db.commit()
    return result.rowcount or 0
