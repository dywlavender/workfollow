from fastapi.testclient import TestClient
from sqlalchemy import select

from app.models.auth import User, UserStatus
from app.models.note import Attachment
from app.models.todo import TodoAssignment
from app.services.auth_service import password_hash


def add_security_user(db, user_id: str, username: str) -> User:
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


def login_security_user(app, username: str) -> TestClient:
    client = TestClient(app)
    response = client.post(
        "/api/auth/login", json={"identifier": username, "password": "member-password"}
    )
    assert response.status_code == 200
    return client


def test_personal_resources_are_isolated_between_users(client: TestClient, db) -> None:
    other = add_security_user(db, "80000000-0000-0000-0000-000000000001", "isolated")
    todo = client.post("/api/tasks", json={"title": "仅属于 tester"}).json()
    note = client.post("/api/notes", json={"title": "仅属于 tester"}).json()
    attachment = Attachment(
        id="80000000-0000-0000-0000-000000000010",
        owner_id="20000000-0000-0000-0000-000000000001",
        note_id=note["id"],
        original_name="private.txt",
        storage_name="private.txt",
        mime_type="text/plain",
        size=1,
        file_path="data/files/private-not-created.txt",
    )
    db.add(attachment)
    db.commit()

    other_client = login_security_user(client.app, other.username)
    assert other_client.get(f"/api/tasks/{todo['id']}").status_code == 404
    assert other_client.put(f"/api/tasks/{todo['id']}", json={"title": "越权"}).status_code == 405
    assert other_client.delete(f"/api/tasks/{todo['id']}").status_code == 404
    assert other_client.get(f"/api/notes/{note['id']}").status_code == 404
    assert other_client.post(f"/api/notes/{note['id']}/copy").status_code == 404
    assert other_client.put(f"/api/notes/{note['id']}/favorite", json={"isFavorite": True}).status_code == 404
    assert other_client.delete(f"/api/notes/{note['id']}").status_code == 404
    assert other_client.get(f"/api/attachments/{attachment.id}").json()["detail"] == "Attachment not found"
    assert other_client.get("/api/notes").json() == []


def test_non_member_cannot_cross_team_read_or_update_tasks(client: TestClient, db) -> None:
    other = add_security_user(db, "80000000-0000-0000-0000-000000000002", "outsider2")
    worker = add_security_user(db, "80000000-0000-0000-0000-000000000012", "worker2")
    first = client.post("/api/teams", json={"name": "第一团队"}).json()
    assert client.post(f"/api/teams/{first['id']}/members", json={"identifier": worker.username}).status_code == 201
    task = client.post("/api/tasks", json={"title": "第一团队任务", "assigneeIds": [worker.id]}).json()
    outsider = login_security_user(client.app, other.username)
    assert outsider.get(f"/api/teams/{first['id']}/tasks").status_code == 404
    assert outsider.get(f"/api/tasks/{task['id']}").status_code == 404
    assert outsider.put(f"/api/tasks/{task['id']}", json={"title": "越权"}).status_code == 405


def test_team_a_member_cannot_resolve_team_b_task_id(client: TestClient, db) -> None:
    member = add_security_user(db, "80000000-0000-0000-0000-000000000003", "teamaonly")
    owner_b = add_security_user(db, "80000000-0000-0000-0000-000000000004", "teambowner")
    worker_b = add_security_user(db, "80000000-0000-0000-0000-000000000005", "teambworker")
    owner_b.can_create_team = True
    db.commit()
    team_a = client.post("/api/teams", json={"name": "Team A"}).json()
    assert client.post(
        f"/api/teams/{team_a['id']}/members", json={"identifier": member.username, "role": "MEMBER"}
    ).status_code == 201
    owner_b_client = login_security_user(client.app, owner_b.username)
    team_b = owner_b_client.post("/api/teams", json={"name": "Team B"}).json()
    assert owner_b_client.post(
        f"/api/teams/{team_b['id']}/members", json={"identifier": worker_b.username, "role": "MEMBER"}
    ).status_code == 201
    task_b = owner_b_client.post("/api/tasks", json={"title": "Team B secret", "assigneeIds": [worker_b.id]}).json()
    member_client = login_security_user(client.app, member.username)
    assert member_client.get(f"/api/tasks/{task_b['id']}").status_code == 404
    assert member_client.put(f"/api/tasks/{task_b['id']}/my-status", json={"status": "DONE"}).status_code == 404


def test_task_attachment_access_is_revoked_when_assignee_leaves_team(client: TestClient, db) -> None:
    member = add_security_user(
        db, "80000000-0000-0000-0000-000000000006", "filemember"
    )
    observer = add_security_user(
        db, "80000000-0000-0000-0000-000000000007", "fileobserver"
    )
    team_id = client.post("/api/teams", json={"name": "附件权限团队"}).json()["id"]
    for user in (member, observer):
        assert client.post(
            f"/api/teams/{team_id}/members",
            json={"identifier": user.username, "role": "MEMBER"},
        ).status_code == 201
    task = client.post(
        "/api/tasks", json={"title": "带附件的任务", "assigneeIds": [member.id]}
    ).json()
    uploaded = client.post(
        "/api/attachments/task",
        data={"taskId": task["id"]},
        files={"file": ("proof.txt", b"task attachment", "text/plain")},
    )
    assert uploaded.status_code == 201, uploaded.text
    attachment_id = uploaded.json()["id"]

    member_client = login_security_user(client.app, member.username)
    observer_client = login_security_user(client.app, observer.username)
    assert member_client.get(f"/api/attachments/{attachment_id}").content == b"task attachment"
    assert member_client.delete(f"/api/attachments/{attachment_id}").status_code == 403
    assert observer_client.get(f"/api/attachments/{attachment_id}").status_code == 404

    assert client.delete(f"/api/teams/{team_id}/members/{member.id}").status_code == 204
    assert member_client.get(f"/api/tasks/{task['id']}").status_code == 404
    assert member_client.get(f"/api/attachments/{attachment_id}").status_code == 404
    assignment = db.scalar(select(TodoAssignment).where(
        TodoAssignment.task_id == task["id"], TodoAssignment.user_id == member.id
    ))
    db.refresh(assignment)
    assert assignment.active is False
    assert assignment.removed_at is not None

    # Creator cleanup also proves the grant and task metadata are removed together.
    assert client.delete(f"/api/attachments/{attachment_id}").status_code == 204
