from __future__ import annotations

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import func, select

from app.core.dependencies import CurrentUser, DbSession
from app.models.auth import SystemRole, User
from app.schemas.auth import AdminUserPermissionsUpdate, AdminUserSystemRoleUpdate, PasswordResetRead, UserRead
from app.services import audit_service, password_reset_service
from app.services.system_permission_service import audit_metadata, require_root


router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/users", response_model=list[UserRead])
def list_users(db: DbSession, user: CurrentUser) -> list[UserRead]:
    require_root(user)
    users = db.scalars(
        select(User).order_by(User.created_at.asc(), User.username.asc())
    ).all()
    return [UserRead.model_validate(item) for item in users]


@router.patch("/users/{user_id}/permissions", response_model=UserRead)
def update_user_permissions(
    user_id: str,
    payload: AdminUserPermissionsUpdate,
    db: DbSession,
    user: CurrentUser,
) -> UserRead:
    require_root(user)
    target = db.get(User, user_id)
    if target is None:
        # Do not disclose non-existent accounts through the admin API.
        raise HTTPException(status_code=404, detail="User not found")
    if target.system_role == SystemRole.ROOT:
        # ROOT always has the capability by definition; it is not a grant that
        # can be accidentally revoked through the ordinary user-permissions UI.
        target.can_create_team = True
    else:
        target.can_create_team = payload.can_create_team
    db.commit()
    db.refresh(target)
    audit_service.record_audit(
        db,
        actor_user_id=user.id,
        action="USER_TEAM_CREATE_PERMISSION_CHANGED",
        resource_type="USER",
        resource_id=target.id,
        metadata_json=audit_metadata(
            user,
            {"userId": target.id, "canCreateTeam": target.can_create_team},
        ),
    )
    return UserRead.model_validate(target)


@router.patch("/users/{user_id}/system-role", response_model=UserRead)
def update_user_system_role(
    user_id: str,
    payload: AdminUserSystemRoleUpdate,
    db: DbSession,
    user: CurrentUser,
) -> UserRead:
    require_root(user)
    target = db.get(User, user_id)
    if target is None:
        raise HTTPException(status_code=404, detail="User not found")
    if target.id == user.id and payload.system_role != SystemRole.ROOT:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="不能撤销当前登录账户的系统管理员权限")
    if target.system_role == payload.system_role:
        return UserRead.model_validate(target)
    if target.system_role == SystemRole.ROOT and payload.system_role != SystemRole.ROOT:
        root_count = db.scalar(
            select(func.count(User.id)).where(User.system_role == SystemRole.ROOT)
        ) or 0
        if root_count <= 1:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="至少保留一个系统管理员")

    previous_role = target.system_role
    target.system_role = payload.system_role
    # ROOT has this capability by definition. Demoting a ROOT must not leave
    # an implicit elevated capability behind.
    target.can_create_team = payload.system_role == SystemRole.ROOT
    db.commit()
    db.refresh(target)
    audit_service.record_audit(
        db,
        actor_user_id=user.id,
        action="USER_SYSTEM_ROLE_CHANGED",
        resource_type="USER",
        resource_id=target.id,
        metadata_json=audit_metadata(
            user,
            {
                "userId": target.id,
                "previousSystemRole": previous_role.value,
                "systemRole": target.system_role.value,
            },
        ),
    )
    return UserRead.model_validate(target)


@router.post("/users/{user_id}/reset-password", response_model=PasswordResetRead)
def reset_user_password(user_id: str, db: DbSession, user: CurrentUser) -> PasswordResetRead:
    require_root(user)
    target = db.get(User, user_id)
    if target is None:
        raise HTTPException(status_code=404, detail="User not found")
    password_reset_service.reset_user_password(db, target)
    db.commit()
    audit_service.record_audit(
        db,
        actor_user_id=user.id,
        action="USER_PASSWORD_RESET",
        resource_type="USER",
        resource_id=target.id,
        metadata_json=audit_metadata(user, {"userId": target.id}),
    )
    return PasswordResetRead(
        user_id=target.id,
        initial_password=password_reset_service.INITIAL_PASSWORD,
    )
