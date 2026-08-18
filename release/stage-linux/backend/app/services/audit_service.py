from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.audit import AuditLog


def record_audit(
    db: Session,
    *,
    actor_user_id: str | None,
    action: str,
    resource_type: str,
    resource_id: str | None = None,
    team_id: str | None = None,
    metadata_json: dict[str, object] | None = None,
) -> AuditLog:
    log = AuditLog(
        actor_user_id=actor_user_id,
        action=action,
        resource_type=resource_type,
        resource_id=resource_id,
        team_id=team_id,
        metadata_json=metadata_json or {},
    )
    db.add(log)
    db.commit()
    db.refresh(log)
    return log


def list_team_audit_logs(db: Session, team_id: str, limit: int = 100) -> list[AuditLog]:
    return list(
        db.scalars(
            select(AuditLog)
            .where(AuditLog.team_id == team_id)
            .order_by(AuditLog.created_at.desc())
            .limit(limit)
        )
    )
