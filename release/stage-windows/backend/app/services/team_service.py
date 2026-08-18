from __future__ import annotations

from fastapi import HTTPException, status
from sqlalchemy import and_, select
from sqlalchemy.orm import Session

from app.models.auth import User, UserStatus
from app.models.team import Team, TeamMember, TeamMemberRole, TeamMemberStatus, TeamStatus
from app.services.system_permission_service import user_is_root


def get_team_or_404(db: Session, team_id: str) -> Team:
    team = db.scalar(select(Team).where(Team.id == team_id, Team.status == TeamStatus.ACTIVE))
    if team is None:
        raise HTTPException(status_code=404, detail="Team not found")
    return team


def get_member(db: Session, team_id: str, user_id: str) -> TeamMember | None:
    return db.scalar(
        select(TeamMember).where(
            TeamMember.team_id == team_id,
            TeamMember.user_id == user_id,
            TeamMember.status == TeamMemberStatus.ACTIVE,
        )
    )


def require_member(db: Session, team_id: str, user_id: str) -> TeamMember:
    get_team_or_404(db, team_id)
    member = get_member(db, team_id, user_id)
    if member is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Team not found")
    return member


def require_team_access(db: Session, team_id: str, user_id: str) -> TeamMember | None:
    """Require a real membership or persisted ROOT access.

    ROOT is intentionally represented by ``None`` here. Callers must not turn
    that access into an OWNER-shaped membership or return it as a team role.
    """
    get_team_or_404(db, team_id)
    if user_is_root(db, user_id):
        return None
    member = get_member(db, team_id, user_id)
    if member is not None:
        return member
    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Team not found")


def require_role(db: Session, team_id: str, user_id: str, *roles: TeamMemberRole) -> TeamMember | None:
    get_team_or_404(db, team_id)
    if user_is_root(db, user_id):
        # A persisted ROOT is a system actor even if an old or accidental
        # membership row also exists for the account.
        return None  # type: ignore[return-value]
    member = get_member(db, team_id, user_id)
    if member is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Team not found")
    if member.role not in roles:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="没有执行该操作的权限")
    return member


def find_user(db: Session, identifier: str) -> User:
    normalized = identifier.strip().lower()
    user = db.scalar(
        select(User).where(
            User.username == normalized,
            User.status == UserStatus.ACTIVE,
        )
    )
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    return user


def list_user_teams(db: Session, user_id: str) -> list[tuple[Team, TeamMemberRole | None]]:
    if user_is_root(db, user_id):
        teams = db.scalars(
            select(Team).where(Team.status == TeamStatus.ACTIVE).order_by(Team.updated_at.desc())
        ).all()
        return [(team, None) for team in teams]
    rows = db.execute(
        select(Team, TeamMember.role)
        .join(TeamMember, TeamMember.team_id == Team.id)
        .where(
            TeamMember.user_id == user_id,
            TeamMember.status == TeamMemberStatus.ACTIVE,
            Team.status == TeamStatus.ACTIVE,
        )
        .order_by(Team.updated_at.desc())
    )
    return [(team, role) for team, role in rows]


def ensure_role_change_allowed(actor: TeamMember | None, target: TeamMember, new_role: TeamMemberRole) -> None:
    if actor is not None and actor.role != TeamMemberRole.OWNER:
        raise HTTPException(status_code=403, detail="只有团队所有者可以修改角色")
    if target.role == TeamMemberRole.OWNER or new_role == TeamMemberRole.OWNER:
        raise HTTPException(status_code=422, detail="团队所有者角色不能通过此接口转移")
