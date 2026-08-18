from datetime import datetime
from typing import Any

from app.schemas.base import ApiModel


class AuditLogRead(ApiModel):
    id: str
    team_id: str | None
    actor_user_id: str | None
    action: str
    resource_type: str
    resource_id: str | None
    metadata_json: dict[str, Any]
    created_at: datetime
