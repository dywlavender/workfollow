from __future__ import annotations

from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import select, update
from sqlalchemy.orm import Session, joinedload

from app.core.dependencies import CurrentUser, DbSession
from app.models.auth import SystemRole, User
from app.models.team import Team, TeamMember, TeamMemberRole, TeamMemberStatus, TeamStatus
from app.models.todo import Todo, TodoAssignment, local_now
from app.schemas.team import (
    TeamCreate,
    TeamMemberCreate,
    TeamMemberRead,
    TeamMemberRoleUpdate,
    TeamRead,
    TeamUpdate,
)
from app.schemas.auth import PasswordResetRead
from app.services import password_reset_service, team_service
from app.services import audit_service
from app.services.notification_service import notify_user
from app.services.system_permission_service import audit_metadata, can_create_team
from app.services.todo_service import recompute_task_status
from app.models.notification import NotificationType
from app.models.note_share import NoteShare, NoteShareStatus


router = APIRouter(prefix="/teams", tags=["teams"])


def _team_read(team: Team, role: TeamMemberRole | None = None) -> TeamRead:
    result = TeamRead.model_validate(team)
    result.role = role
    return result


def _member_read(member: TeamMember) -> TeamMemberRead:
    return TeamMemberRead.model_validate(member)


@router.post("", response_model=TeamRead, status_code=status.HTTP_201_CREATED)
def create_team(payload: TeamCreate, db: DbSession, user: CurrentUser) -> TeamRead:
    if not can_create_team(user):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="没有创建团队的权限")
    name = payload.name.strip()
    if not name:
        raise HTTPException(status_code=422, detail="团队名称不能为空")
    team = Team(name=name, description=payload.description.strip() if payload.description else None, owner_id=user.id)
    db.add(team)
    db.flush()
    db.add(
        TeamMember(
            team_id=team.id,
            user_id=user.id,
            role=TeamMemberRole.OWNER,
            status=TeamMemberStatus.ACTIVE,
        )
    )
    db.commit()
    db.refresh(team)
    audit_service.record_audit(
        db, actor_user_id=user.id, action="TEAM_CREATED", resource_type="TEAM", resource_id=team.id, team_id=team.id,
        metadata_json=audit_metadata(user),
    )
    return _team_read(team, TeamMemberRole.OWNER)


@router.get("", response_model=list[TeamRead])
def list_teams(db: DbSession, user: CurrentUser) -> list[TeamRead]:
    return [_team_read(team, role) for team, role in team_service.list_user_teams(db, user.id)]


@router.get("/{team_id}", response_model=TeamRead)
def get_team(team_id: str, db: DbSession, user: CurrentUser) -> TeamRead:
    member = team_service.require_team_access(db, team_id, user.id)
    return _team_read(team_service.get_team_or_404(db, team_id), member.role if member else None)


@router.put("/{team_id}", response_model=TeamRead)
def update_team(team_id: str, payload: TeamUpdate, db: DbSession, user: CurrentUser) -> TeamRead:
    team_service.require_role(db, team_id, user.id, TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
    team = team_service.get_team_or_404(db, team_id)
    changes = payload.model_dump(exclude_unset=True)
    if "name" in changes:
        changes["name"] = (changes["name"] or "").strip()
        if not changes["name"]:
            raise HTTPException(status_code=422, detail="团队名称不能为空")
    if "description" in changes and changes["description"] is not None:
        changes["description"] = changes["description"].strip()
    for field, value in changes.items():
        setattr(team, field, value)
    db.commit()
    db.refresh(team)
    member = team_service.get_member(db, team_id, user.id)
    audit_service.record_audit(
        db, actor_user_id=user.id, action="TEAM_UPDATED", resource_type="TEAM", resource_id=team_id, team_id=team_id,
        metadata_json=audit_metadata(user, {"fields": list(changes)}),
    )
    return _team_read(team, member.role if member else None)


@router.delete("/{team_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_team(team_id: str, db: DbSession, user: CurrentUser) -> Response:
    team_service.require_role(db, team_id, user.id, TeamMemberRole.OWNER)
    team = team_service.get_team_or_404(db, team_id)
    team.status = TeamStatus.DELETED
    for member in team.members:
        if member.status == TeamMemberStatus.ACTIVE:
            member.status = TeamMemberStatus.REMOVED
    db.commit()
    audit_service.record_audit(
        db, actor_user_id=user.id, action="TEAM_DELETED", resource_type="TEAM", resource_id=team_id, team_id=team_id,
        metadata_json=audit_metadata(user),
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/{team_id}/members", response_model=list[TeamMemberRead])
def list_members(team_id: str, db: DbSession, user: CurrentUser) -> list[TeamMemberRead]:
    team_service.require_team_access(db, team_id, user.id)
    members = db.scalars(
        select(TeamMember)
        .options(joinedload(TeamMember.user))
        .where(TeamMember.team_id == team_id, TeamMember.status == TeamMemberStatus.ACTIVE)
        .order_by(TeamMember.role, TeamMember.joined_at)
    ).unique().all()
    return [_member_read(member) for member in members]


@router.post("/{team_id}/members/{user_id}/reset-password", response_model=PasswordResetRead)
def reset_team_member_password(
    team_id: str,
    user_id: str,
    db: DbSession,
    user: CurrentUser,
) -> PasswordResetRead:
    actor = team_service.require_role(db, team_id, user.id, TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
    target = db.scalar(
        select(TeamMember)
        .options(joinedload(TeamMember.user))
        .where(
            TeamMember.team_id == team_id,
            TeamMember.user_id == user_id,
            TeamMember.status == TeamMemberStatus.ACTIVE,
        )
    )
    if target is None:
        raise HTTPException(status_code=404, detail="Team member not found")

    is_system_root = user.system_role == SystemRole.ROOT
    if not is_system_root:
        if target.user.system_role == SystemRole.ROOT:
            raise HTTPException(status_code=403, detail="团队角色不能重置系统管理员密码")
        if actor is None:
            raise HTTPException(status_code=403, detail="没有重置密码的权限")
        if actor.role == TeamMemberRole.ADMIN and target.user_id != user.id and target.role != TeamMemberRole.MEMBER:
            raise HTTPException(status_code=403, detail="团队管理员只能重置自己或普通成员的密码")

    password_reset_service.reset_user_password(db, target.user)
    db.commit()
    audit_service.record_audit(
        db,
        actor_user_id=user.id,
        action="USER_PASSWORD_RESET",
        resource_type="USER",
        resource_id=target.user_id,
        team_id=team_id,
        metadata_json=audit_metadata(user, {"userId": target.user_id, "memberRole": target.role.value}),
    )
    return PasswordResetRead(
        user_id=target.user_id,
        initial_password=password_reset_service.INITIAL_PASSWORD,
    )


@router.post("/{team_id}/members", response_model=TeamMemberRead, status_code=status.HTTP_201_CREATED)
def add_member(team_id: str, payload: TeamMemberCreate, db: DbSession, user: CurrentUser) -> TeamMemberRead:
    actor = team_service.require_role(db, team_id, user.id, TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
    target_user = team_service.find_user(db, payload.identifier)
    if payload.role == TeamMemberRole.OWNER:
        raise HTTPException(status_code=422, detail="不能通过成员接口添加 OWNER")
    if actor is not None and actor.role == TeamMemberRole.ADMIN and payload.role != TeamMemberRole.MEMBER:
        raise HTTPException(status_code=403, detail="管理员只能添加 MEMBER")

    existing = db.scalar(
        select(TeamMember).where(TeamMember.team_id == team_id, TeamMember.user_id == target_user.id)
    )
    if existing is not None and existing.status == TeamMemberStatus.ACTIVE:
        raise HTTPException(status_code=409, detail="用户已经是团队成员")
    if existing is None:
        member = TeamMember(
            team_id=team_id,
            user_id=target_user.id,
            role=payload.role,
            status=TeamMemberStatus.ACTIVE,
        )
        db.add(member)
    else:
        member = existing
        member.role = payload.role
        member.status = TeamMemberStatus.ACTIVE
        member.joined_at = local_now()
    db.commit()
    db.refresh(member)
    db.refresh(target_user)
    notify_user(
        db,
        target_user.id,
        NotificationType.TEAM_MEMBER_ADDED,
        "你已加入团队",
        f"你已被加入团队“{team_service.get_team_or_404(db, team_id).name}”。",
        actor_user_id=user.id,
        data_json={"teamId": team_id},
    )
    audit_service.record_audit(
        db, actor_user_id=user.id, action="TEAM_MEMBER_ADDED", resource_type="TEAM_MEMBER", resource_id=member.id,
        team_id=team_id, metadata_json=audit_metadata(user, {"userId": target_user.id, "role": member.role.value}),
    )
    return _member_read(member)


@router.put("/{team_id}/members/{user_id}/role", response_model=TeamMemberRead)
def update_member_role(
    team_id: str,
    user_id: str,
    payload: TeamMemberRoleUpdate,
    db: DbSession,
    user: CurrentUser,
) -> TeamMemberRead:
    actor = team_service.require_role(db, team_id, user.id, TeamMemberRole.OWNER)
    target = db.scalar(
        select(TeamMember)
        .options(joinedload(TeamMember.user))
        .where(
            TeamMember.team_id == team_id,
            TeamMember.user_id == user_id,
            TeamMember.status == TeamMemberStatus.ACTIVE,
        )
    )
    if target is None:
        raise HTTPException(status_code=404, detail="Team member not found")
    team_service.ensure_role_change_allowed(actor, target, payload.role)
    target.role = payload.role
    db.commit()
    db.refresh(target)
    audit_service.record_audit(
        db, actor_user_id=user.id, action="TEAM_MEMBER_ROLE_CHANGED", resource_type="TEAM_MEMBER", resource_id=target.id,
        team_id=team_id, metadata_json=audit_metadata(user, {"userId": user_id, "role": target.role.value}),
    )
    return _member_read(target)


def _deactivate_member_access(db: Session, target: TeamMember) -> None:
    """Remove current team access while retaining membership and assignment history."""
    target.status = TeamMemberStatus.REMOVED
    # Keep assignment history, but remove it from current permissions and
    # progress as part of the same transaction as the membership change.
    affected_tasks = db.scalars(
        select(Todo)
        .join(TodoAssignment, TodoAssignment.task_id == Todo.id)
        .where(
            Todo.team_id == target.team_id,
            TodoAssignment.user_id == target.user_id,
            TodoAssignment.active.is_(True),
        )
    ).unique().all()
    removed_at = local_now()
    for task in affected_tasks:
        for assignment in task.assignments:
            if assignment.user_id == target.user_id and assignment.active:
                assignment.active = False
                assignment.removed_at = removed_at
        recompute_task_status(task)
    db.execute(
        update(NoteShare)
        .where(
            NoteShare.team_id == target.team_id,
            (NoteShare.shared_with_user_id == target.user_id) | (NoteShare.shared_by_user_id == target.user_id),
            NoteShare.status == NoteShareStatus.ACTIVE,
        )
        .values(status=NoteShareStatus.REVOKED, revoked_at=removed_at)
    )


@router.post("/{team_id}/leave", status_code=status.HTTP_204_NO_CONTENT)
def leave_team(team_id: str, db: DbSession, user: CurrentUser) -> Response:
    target = team_service.require_member(db, team_id, user.id)
    if target.role == TeamMemberRole.OWNER:
        raise HTTPException(status_code=422, detail="团队所有者不能直接退出，请先解散团队")
    _deactivate_member_access(db, target)
    db.commit()
    audit_service.record_audit(
        db, actor_user_id=user.id, action="TEAM_MEMBER_LEFT", resource_type="TEAM_MEMBER", resource_id=target.id,
        team_id=team_id, metadata_json=audit_metadata(user, {"userId": user.id}),
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("/{team_id}/members/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_member(team_id: str, user_id: str, db: DbSession, user: CurrentUser) -> Response:
    actor = team_service.require_role(db, team_id, user.id, TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
    target = db.scalar(
        select(TeamMember).where(
            TeamMember.team_id == team_id,
            TeamMember.user_id == user_id,
            TeamMember.status == TeamMemberStatus.ACTIVE,
        )
    )
    if target is None:
        raise HTTPException(status_code=404, detail="Team member not found")
    if target.role == TeamMemberRole.OWNER:
        raise HTTPException(status_code=422, detail="不能移除团队所有者")
    if actor is not None and actor.role == TeamMemberRole.ADMIN and target.role != TeamMemberRole.MEMBER:
        raise HTTPException(status_code=403, detail="管理员只能移除 MEMBER")
    _deactivate_member_access(db, target)
    db.commit()
    audit_service.record_audit(
        db, actor_user_id=user.id, action="TEAM_MEMBER_REMOVED", resource_type="TEAM_MEMBER", resource_id=target.id,
        team_id=team_id, metadata_json=audit_metadata(user, {"userId": user_id}),
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)
