from fastapi import APIRouter, Query

from app.core.dependencies import CurrentUser, DbSession
from app.models.team import TeamMemberRole
from app.schemas.audit import AuditLogRead
from app.services import audit_service, team_service


router = APIRouter(tags=["audit"])


@router.get("/teams/{team_id}/audit-logs", response_model=list[AuditLogRead])
def get_team_audit_logs(
    team_id: str,
    db: DbSession,
    user: CurrentUser,
    limit: int = Query(default=100, ge=1, le=200),
) -> list[AuditLogRead]:
    team_service.require_role(db, team_id, user.id, TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
    return audit_service.list_team_audit_logs(db, team_id, limit)
