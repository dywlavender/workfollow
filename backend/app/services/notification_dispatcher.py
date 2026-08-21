from __future__ import annotations

import logging
from collections.abc import Iterable
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.models.notification import Notification, NotificationType
from app.services import external_notification_service, notification_service


logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class NotificationDispatchResult:
    in_app_count: int = 0
    external_count: int = 0

    @property
    def changed(self) -> bool:
        return bool(self.in_app_count or self.external_count)


def recipient_ids(participant_ids: Iterable[str], actor_user_id: str | None = None) -> list[str]:
    """Return affected users once, excluding the user who performed the action."""
    return sorted({
        user_id
        for user_id in participant_ids
        if user_id and user_id != actor_user_id
    })


def _has_in_app_event(db: Session, user_id: str, notification_type: NotificationType, event_key: str) -> bool:
    rows = db.scalars(
        select(Notification.data_json)
        .where(
            Notification.user_id == user_id,
            Notification.type == notification_type,
        )
        .order_by(Notification.created_at.desc())
        .limit(100)
    ).all()
    return any(isinstance(data, dict) and data.get("eventKey") == event_key for data in rows)


def dispatch_event(
    db: Session,
    *,
    event: str,
    participant_ids: Iterable[str],
    actor_user_id: str | None,
    in_app_type: NotificationType | None,
    external_type: NotificationType | None,
    title: str,
    body: str,
    external_message: str | None = None,
    data_json: dict[str, object] | None = None,
    event_key: str | None = None,
    settings: Settings | None = None,
    commit: bool = True,
) -> NotificationDispatchResult:
    """Fan out one event to the in-app and external channels consistently."""
    recipients = recipient_ids(participant_ids, actor_user_id)
    in_app_count = 0
    external_count = 0
    message = external_message or body

    for user_id in recipients:
        if in_app_type is not None:
            already_exists = event_key is not None and _has_in_app_event(
                db, user_id, in_app_type, event_key
            )
            if not already_exists:
                notification_service.add_notification(
                    db,
                    user_id,
                    in_app_type,
                    title,
                    body,
                    actor_user_id=actor_user_id,
                    data_json=data_json,
                )
                in_app_count += 1

        if external_type is not None:
            delivery_key = f"{event_key}:{user_id}" if event_key else None
            delivery = external_notification_service.add_external_notification(
                db,
                user_id,
                external_type,
                message,
                delivery_key=delivery_key,
                data_json=data_json,
                settings=settings,
            )
            external_count += delivery is not None

    result = NotificationDispatchResult(
        in_app_count=in_app_count,
        external_count=external_count,
    )
    if result.changed and commit:
        db.commit()
    logger.info(
        "统一通知分发 event=%s actor=%s recipients=%s in_app=%s external=%s",
        event,
        actor_user_id or "-",
        len(recipients),
        result.in_app_count,
        result.external_count,
    )
    return result
