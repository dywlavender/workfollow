from datetime import datetime
from typing import Any

from app.models.notification import NotificationType
from app.schemas.base import ApiModel


class NotificationRead(ApiModel):
    id: str
    actor_user_id: str | None
    type: NotificationType
    title: str
    body: str
    data_json: dict[str, Any]
    read_at: datetime | None
    created_at: datetime


class NotificationReadResult(ApiModel):
    id: str
    read_at: datetime
