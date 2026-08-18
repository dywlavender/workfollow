from fastapi.testclient import TestClient
from sqlalchemy import select

from app.models.audit import AuditLog
from app.models.auth import SystemRole, User, UserStatus
from app.services.auth_service import password_hash


def add_user(db, user_id: str, username: str, *, role: SystemRole = SystemRole.NORMAL) -> User:
    user = User(
        id=user_id,
        username=username,
        password_hash=password_hash.hash("member-password"),
        nickname=username,
        system_role=role,
        can_create_team=role == SystemRole.ROOT,
        status=UserStatus.ACTIVE,
    )
    db.add(user)
    db.commit()
    return user


def login(app, username: str, password: str = "member-password") -> TestClient:
    result = TestClient(app)
    response = result.post("/api/auth/login", json={"identifier": username, "password": password})
    assert response.status_code == 200, response.text
    return result


def test_team_creation_requires_persisted_permission_and_root_keeps_null_team_role(client: TestClient, db) -> None:
    normal = add_user(db, "21000000-0000-0000-0000-000000000001", "ordinary")
    root = add_user(
        db,
        "21000000-0000-0000-0000-000000000002",
        "sysadmin",
        role=SystemRole.ROOT,
    )
    normal_client = login(client.app, normal.username)
    root_client = login(client.app, root.username)

    assert normal_client.post("/api/teams", json={"name": "不应创建"}).status_code == 403
    # A username that happens to look privileged is still NORMAL until the
    # persisted system_role field says otherwise.
    impostor = add_user(db, "21000000-0000-0000-0000-000000000003", "root")
    impostor_client = login(client.app, impostor.username)
    assert impostor_client.post("/api/teams", json={"name": "伪 root"}).status_code == 403

    created = client.post("/api/teams", json={"name": "普通用户团队"})
    assert created.status_code == 201
    team = created.json()
    assert team["role"] == "OWNER"

    root_teams = root_client.get("/api/teams")
    assert root_teams.status_code == 200
    root_team = next(item for item in root_teams.json() if item["id"] == team["id"])
    assert root_team["role"] is None
    assert root_client.get(f"/api/teams/{team['id']}/members").status_code == 200


def test_root_can_grant_and_revoke_only_team_creation_capability(client: TestClient, db) -> None:
    root = add_user(
        db,
        "21000000-0000-0000-0000-000000000010",
        "permission-root",
        role=SystemRole.ROOT,
    )
    target = add_user(db, "21000000-0000-0000-0000-000000000011", "grant-target")
    root_client = login(client.app, root.username)
    target_client = login(client.app, target.username)

    assert client.get("/api/admin/users").status_code == 403
    users = root_client.get("/api/admin/users")
    assert users.status_code == 200
    target_read = next(item for item in users.json() if item["id"] == target.id)
    assert target_read["systemRole"] == "NORMAL"
    assert target_read["canCreateTeam"] is False

    granted = root_client.patch(
        f"/api/admin/users/{target.id}/permissions", json={"canCreateTeam": True}
    )
    assert granted.status_code == 200, granted.text
    assert granted.json()["canCreateTeam"] is True
    created = target_client.post("/api/teams", json={"name": "获授权团队"})
    assert created.status_code == 201
    assert created.json()["role"] == "OWNER"

    revoked = root_client.patch(
        f"/api/admin/users/{target.id}/permissions", json={"canCreateTeam": False}
    )
    assert revoked.status_code == 200
    assert revoked.json()["canCreateTeam"] is False
    assert target_client.post("/api/teams", json={"name": "撤销后不应创建"}).status_code == 403


def test_root_can_reset_any_user_password_and_revoke_existing_sessions(client: TestClient, db) -> None:
    root = add_user(
        db,
        "21000000-0000-0000-0000-000000000020",
        "password-root",
        role=SystemRole.ROOT,
    )
    target = add_user(db, "21000000-0000-0000-0000-000000000021", "password-target")
    root_client = login(client.app, root.username)
    target_client = login(client.app, target.username)

    assert client.post(f"/api/admin/users/{target.id}/reset-password").status_code == 403
    reset = root_client.post(f"/api/admin/users/{target.id}/reset-password")
    assert reset.status_code == 200, reset.text
    assert reset.json() == {"userId": target.id, "initialPassword": "11111111"}
    assert target_client.get("/api/auth/me").status_code == 401
    assert TestClient(client.app).post(
        "/api/auth/login", json={"identifier": target.username, "password": "11111111"}
    ).status_code == 200
    assert TestClient(client.app).post(
        "/api/auth/login", json={"identifier": target.username, "password": "member-password"}
    ).status_code == 401

    audit = db.scalar(select(AuditLog).where(
        AuditLog.actor_user_id == root.id,
        AuditLog.action == "USER_PASSWORD_RESET",
        AuditLog.resource_id == target.id,
    ))
    assert audit is not None
    assert audit.metadata_json["source"] == "SYSTEM_ADMIN"
    assert "password" not in audit.metadata_json
