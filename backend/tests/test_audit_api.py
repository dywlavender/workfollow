from fastapi.testclient import TestClient

from app.models.auth import User, UserStatus
from app.services.auth_service import password_hash


def add_audit_user(db, user_id: str, username: str) -> User:
    user = User(
        id=user_id,
        username=username,
        password_hash=password_hash.hash("member-password"),
        nickname=username.title(),
        status=UserStatus.ACTIVE,
    )
    db.add(user)
    db.commit()
    return user


def login_audit_user(app, username: str) -> TestClient:
    client = TestClient(app)
    response = client.post(
        "/api/auth/login", json={"identifier": username, "password": "member-password"}
    )
    assert response.status_code == 200
    return client


def test_audit_is_written_for_team_actions_and_admin_only(client: TestClient, db) -> None:
    member = add_audit_user(db, "70000000-0000-0000-0000-000000000001", "auditee")
    created = client.post("/api/teams", json={"name": "审计团队"})
    assert created.status_code == 201
    team_id = created.json()["id"]
    assert client.post(
        f"/api/teams/{team_id}/members", json={"identifier": member.username, "role": "MEMBER"}
    ).status_code == 201
    task = client.post(
        "/api/tasks", json={"title": "被审计任务", "assigneeIds": [member.id]}
    )
    assert task.status_code == 201
    note = client.post(
        f"/api/teams/{team_id}/notes", json={"title": "被审计笔记", "plainText": "内容"}
    )
    assert note.status_code == 201

    logs = client.get(f"/api/teams/{team_id}/audit-logs")
    assert logs.status_code == 200
    actions = {item["action"] for item in logs.json()}
    assert {"TEAM_CREATED", "TEAM_MEMBER_ADDED", "TASK_ASSIGNED", "TEAM_NOTE_CREATED"} <= actions
    assert all(item["teamId"] == team_id for item in logs.json())

    member_client = login_audit_user(client.app, member.username)
    assert member_client.get(f"/api/teams/{team_id}/audit-logs").status_code == 403
    assert member_client.delete(f"/api/teams/{team_id}").status_code == 403
