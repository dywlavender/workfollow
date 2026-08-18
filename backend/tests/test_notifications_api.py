from fastapi.testclient import TestClient

from app.models.auth import User, UserStatus
from app.models.notification import NotificationType
from app.services.auth_service import password_hash
from app.services.notification_service import notify_user


def add_notification_user(db, user_id: str, username: str) -> User:
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


def login_notification_user(app, username: str) -> TestClient:
    client = TestClient(app)
    response = client.post(
        "/api/auth/login", json={"identifier": username, "password": "member-password"}
    )
    assert response.status_code == 200
    return client


def test_notifications_are_user_scoped_and_markable(client: TestClient, db) -> None:
    target = add_notification_user(db, "60000000-0000-0000-0000-000000000001", "notify")
    team = client.post("/api/teams", json={"name": "通知团队"}).json()
    assert client.post(
        f"/api/teams/{team['id']}/members", json={"identifier": target.username, "role": "MEMBER"}
    ).status_code == 201

    target_client = login_notification_user(client.app, target.username)
    notifications = target_client.get("/api/notifications", params={"unreadOnly": True})
    assert notifications.status_code == 200
    assert notifications.json()[0]["type"] == "TEAM_MEMBER_ADDED"
    notification_id = notifications.json()[0]["id"]
    assert target_client.post(f"/api/notifications/{notification_id}/read").status_code == 200
    assert target_client.get("/api/notifications", params={"unreadOnly": True}).json() == []
    assert target_client.post(f"/api/notifications/{notification_id}/read").status_code == 200

    # A user cannot mark another user's notification by guessing its id.
    assert client.post(f"/api/notifications/{notification_id}/read").status_code == 404


def test_task_assignment_and_note_share_emit_notifications(client: TestClient, db, user_id: str) -> None:
    target = add_notification_user(db, "60000000-0000-0000-0000-000000000002", "workmate")
    team = client.post("/api/teams", json={"name": "事件通知"}).json()
    team_id = team["id"]
    assert client.post(
        f"/api/teams/{team_id}/members", json={"identifier": target.username, "role": "MEMBER"}
    ).status_code == 201
    target_client = login_notification_user(client.app, target.username)
    target_client.post("/api/notifications/read-all")

    task = client.post(
        "/api/tasks", json={"title": "通知任务", "assigneeIds": [target.id]}
    )
    assert task.status_code == 201
    task_notifications = target_client.get("/api/notifications", params={"unreadOnly": True}).json()
    assert any(item["type"] == "TEAM_TASK_ASSIGNED" for item in task_notifications)

    note = client.post("/api/notes", json={"title": "可共享"}).json()
    shared = client.post(f"/api/notes/{note['id']}/shares", json={"identifier": target.username})
    assert shared.status_code == 201
    share_notifications = target_client.get("/api/notifications", params={"unreadOnly": True}).json()
    assert any(item["type"] == "NOTE_SHARED" for item in share_notifications)


def test_notifications_can_only_be_deleted_or_cleared_by_the_owner(client: TestClient, db, user_id: str) -> None:
    target = add_notification_user(db, "60000000-0000-0000-0000-000000000003", "delete-target")
    notify_user(db, target.id, NotificationType.NOTE_SHARED, "给目标用户", "只属于目标用户")
    notify_user(db, user_id, NotificationType.NOTE_SHARED, "给 tester", "不应被清空")
    target_client = login_notification_user(client.app, target.username)
    target_notification = target_client.get("/api/notifications").json()[0]

    assert client.delete(f"/api/notifications/{target_notification['id']}").status_code == 404
    assert target_client.delete(f"/api/notifications/{target_notification['id']}").status_code == 204
    assert target_client.get("/api/notifications").json() == []

    notify_user(db, target.id, NotificationType.NOTE_SHARED, "再次通知", "再次通知")
    notify_user(db, target.id, NotificationType.NOTE_SHARED, "第三通知", "第三通知")
    assert target_client.delete("/api/notifications").status_code == 204
    assert target_client.get("/api/notifications").json() == []
    assert client.get("/api/notifications").json()
