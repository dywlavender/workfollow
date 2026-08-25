from datetime import datetime, timedelta
from urllib.parse import parse_qs, urlsplit

from fastapi.testclient import TestClient
from sqlalchemy import delete, select

from app.core.config import Settings
from app.models.auth import User, UserStatus
from app.models.notification import (
    ExternalDeliveryStatus,
    ExternalNotificationDelivery,
    Notification,
    NotificationType,
)
from app.models.todo import Todo, TodoAssignment, TodoAssignmentStatus, TodoStatus
from app.services import external_notification_service
from app.services.auth_service import password_hash
from app.services.external_notification_service import dispatch_pending, enqueue_daily_task_digests


def add_external_user(db, user_id: str, username: str) -> User:
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


def login_external_user(app, username: str) -> TestClient:
    client = TestClient(app)
    response = client.post(
        "/api/auth/login", json={"identifier": username, "password": "member-password"}
    )
    assert response.status_code == 200
    return client


def test_task_event_is_sent_to_external_get_endpoint(client, db, monkeypatch) -> None:
    target = add_external_user(db, "70000000-0000-0000-0000-000000000001", "external-target")
    team = client.post("/api/teams", json={"name": "外部通知团队"}).json()
    assert client.post(
        f"/api/teams/{team['id']}/members", json={"identifier": target.username, "role": "MEMBER"}
    ).status_code == 201

    settings = Settings(
        notification_http_url="http://notify.example.test/send",
        server_url="https://workfollow.example.test",
    )
    monkeypatch.setattr(external_notification_service, "get_settings", lambda: settings)

    captured: list[tuple[str, float]] = []

    class Response:
        status = 204

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

    def fake_urlopen(request, timeout):
        captured.append((request.full_url, timeout))
        return Response()

    monkeypatch.setattr(external_notification_service, "urlopen", fake_urlopen)

    task = client.post("/api/tasks", json={"title": "外部通知任务", "assigneeIds": [target.id]})
    assert task.status_code == 201

    deliveries = db.scalars(select(ExternalNotificationDelivery)).all()
    assert len(deliveries) == 1
    assert deliveries[0].username == target.username
    assert deliveries[0].status == ExternalDeliveryStatus.PENDING

    assert dispatch_pending(
        db,
        settings=settings,
        now=deliveries[0].next_attempt_at + timedelta(seconds=1),
    ) == 1
    assert len(captured) == 1
    query = parse_qs(urlsplit(captured[0][0]).query)
    assert query["userIds"] == [target.username]
    assert query["url"] == [
        f"https://workfollow.example.test/todos?view=all&todo={task.json()['id']}"
    ]
    assert query["msg"] == [
        "【任务分配】测试用户将任务“外部通知任务”分配给你；截止：未设置；团队：外部通知团队；"
        f"查看任务：https://workfollow.example.test/todos?view=all&todo={task.json()['id']}"
    ]
    assert captured[0][1] == settings.notification_http_timeout_seconds
    assert db.get(ExternalNotificationDelivery, deliveries[0].id).status == ExternalDeliveryStatus.SENT


def test_assignment_cancellation_notifies_before_and_after_participants(client, db, monkeypatch) -> None:
    first = add_external_user(db, "70000000-0000-0000-0000-000000000002", "external-first")
    second = add_external_user(db, "70000000-0000-0000-0000-000000000003", "external-second")
    team = client.post("/api/teams", json={"name": "分配变更通知"}).json()
    for target in (first, second):
        assert client.post(
            f"/api/teams/{team['id']}/members", json={"identifier": target.username, "role": "MEMBER"}
        ).status_code == 201
    settings = Settings(
        notification_http_url="http://notify.example.test/send",
        server_url="https://workfollow.example.test",
    )
    monkeypatch.setattr(external_notification_service, "get_settings", lambda: settings)

    task = client.post(
        "/api/tasks", json={"title": "调整成员任务", "assigneeIds": [first.id, second.id]}
    ).json()
    db.execute(delete(ExternalNotificationDelivery))
    db.commit()

    response = client.put(
        f"/api/tasks/{task['id']}/assignees", json={"assigneeIds": [second.id]}
    )
    assert response.status_code == 200
    deliveries = db.scalars(select(ExternalNotificationDelivery)).all()
    assert {item.username for item in deliveries} == {first.username, second.username}
    assert {item.notification_type for item in deliveries} == {
        NotificationType.TASK_ASSIGNEE_REMOVED,
        NotificationType.TASK_ASSIGNMENT_CHANGED,
    }
    messages = {item.username: item.message for item in deliveries}
    assert messages[first.username] == (
        "【任务分配取消】测试用户取消了你在“调整成员任务”中的分配；"
        "截止：未设置；团队：分配变更通知；"
        f"查看任务：https://workfollow.example.test/todos?view=all&todo={task['id']}"
    )
    assert messages[second.username] == (
        "【任务成员调整】测试用户调整了“调整成员任务”的分配成员（新增：无；移除：External-First）；"
        "截止：未设置；团队：分配变更通知；"
        f"查看任务：https://workfollow.example.test/todos?view=all&todo={task['id']}"
    )


def test_task_assignment_notification_contains_task_context(client, db, monkeypatch) -> None:
    target = add_external_user(db, "70000000-0000-0000-0000-000000000006", "external-context")
    team = client.post("/api/teams", json={"name": "任务上下文团队"}).json()
    assert client.post(
        f"/api/teams/{team['id']}/members", json={"identifier": target.username, "role": "MEMBER"}
    ).status_code == 201
    settings = Settings(
        notification_http_url="http://notify.example.test/send",
        server_url="https://workfollow.example.test",
    )
    monkeypatch.setattr(external_notification_service, "get_settings", lambda: settings)

    response = client.post(
        "/api/tasks",
        json={
            "title": "补充上下文任务",
            "description": "这是一段任务说明",
            "priority": "HIGH",
            "dueAt": "2026-08-30T18:00:00",
            "assigneeIds": [target.id],
        },
    )
    assert response.status_code == 201
    delivery = db.scalar(select(ExternalNotificationDelivery))
    assert delivery is not None
    assert "截止：2026-08-30 18:00" in delivery.message
    assert "优先级：高" in delivery.message
    assert "团队：任务上下文团队" in delivery.message
    assert delivery.data_json["eventType"] == "TASK_ASSIGNEE_ADDED"
    task_data = delivery.data_json["task"]
    assert task_data["dueAt"] == "2026-08-30T18:00:00"
    assert task_data["priority"] == "HIGH"
    assert task_data["descriptionExcerpt"] == "这是一段任务说明"
    assert task_data["url"] == (
        f"https://workfollow.example.test/todos?view=all&todo={delivery.data_json['taskId']}"
    )
    assert delivery.data_json["url"] == task_data["url"]


def test_task_detail_update_notifies_active_assignees(client, db, monkeypatch) -> None:
    first = add_external_user(db, "70000000-0000-0000-0000-000000000007", "external-update-first")
    second = add_external_user(db, "70000000-0000-0000-0000-000000000008", "external-update-second")
    team = client.post("/api/teams", json={"name": "任务更新通知"}).json()
    for target in (first, second):
        assert client.post(
            f"/api/teams/{team['id']}/members", json={"identifier": target.username, "role": "MEMBER"}
        ).status_code == 201
    settings = Settings(
        notification_http_url="http://notify.example.test/send",
        server_url="https://workfollow.example.test",
    )
    monkeypatch.setattr(external_notification_service, "get_settings", lambda: settings)

    task = client.post(
        "/api/tasks",
        json={
            "title": "待更新任务",
            "priority": "LOW",
            "dueAt": "2026-08-30T18:00:00",
            "assigneeIds": [first.id, second.id],
        },
    ).json()
    db.execute(delete(ExternalNotificationDelivery))
    db.commit()

    response = client.put(
        f"/api/tasks/{task['id']}",
        json={"title": "已更新任务", "priority": "HIGH", "dueAt": "2026-09-02T20:00:00"},
    )
    assert response.status_code == 200
    deliveries = db.scalars(select(ExternalNotificationDelivery)).all()
    assert {item.username for item in deliveries} == {first.username, second.username}
    assert {item.notification_type for item in deliveries} == {NotificationType.TASK_UPDATED}
    for delivery in deliveries:
        assert "【任务更新】测试用户更新了“已更新任务”" in delivery.message
        assert "截止时间改为2026-09-02 20:00" in delivery.message
        assert "优先级改为高" in delivery.message
        assert delivery.data_json["changedFields"] == ["title", "dueAt", "priority"]
        assert delivery.data_json["changes"]["dueAt"] == {
            "before": "2026-08-30T18:00:00",
            "after": "2026-09-02T20:00:00",
        }


def test_completion_notifies_assignment_and_whole_task(client, db, monkeypatch) -> None:
    target = add_external_user(db, "70000000-0000-0000-0000-000000000004", "external-completer")
    observer = add_external_user(db, "70000000-0000-0000-0000-000000000005", "external-observer")
    team = client.post("/api/teams", json={"name": "完成通知团队"}).json()
    for user in (target, observer):
        assert client.post(
            f"/api/teams/{team['id']}/members", json={"identifier": user.username, "role": "MEMBER"}
        ).status_code == 201
    settings = Settings(
        notification_http_url="http://notify.example.test/send",
        server_url="https://workfollow.example.test",
    )
    monkeypatch.setattr(external_notification_service, "get_settings", lambda: settings)

    task = client.post(
        "/api/tasks", json={"title": "完成通知任务", "assigneeIds": [target.id, observer.id]}
    ).json()
    db.execute(delete(ExternalNotificationDelivery))
    db.commit()
    target_client = login_external_user(client.app, target.username)
    observer_client = login_external_user(client.app, observer.username)

    assert target_client.post(f"/api/tasks/{task['id']}/complete").status_code == 200
    types = db.scalars(
        select(ExternalNotificationDelivery.notification_type).order_by(ExternalNotificationDelivery.created_at)
    ).all()
    assert types == [NotificationType.TASK_ASSIGNMENT_COMPLETED]
    assert db.scalars(
        select(ExternalNotificationDelivery.username)
    ).all() == [observer.username]
    page_notifications = db.scalars(
        select(Notification).where(Notification.type == NotificationType.TEAM_TASK_UPDATED)
    ).all()
    assert [item.user_id for item in page_notifications] == [observer.id]

    db.execute(delete(ExternalNotificationDelivery))
    db.commit()
    assert observer_client.post(f"/api/tasks/{task['id']}/complete").status_code == 200
    types = db.scalars(
        select(ExternalNotificationDelivery.notification_type).order_by(ExternalNotificationDelivery.created_at)
    ).all()
    assert types == [NotificationType.TASK_COMPLETED]
    assert db.scalars(
        select(ExternalNotificationDelivery.username)
    ).all() == [target.username]
    page_notifications = db.scalars(
        select(Notification).where(Notification.type == NotificationType.TEAM_TASK_UPDATED)
    ).all()
    assert {item.user_id for item in page_notifications} == {target.id, observer.id}
    assert sum(item.user_id == target.id for item in page_notifications) == 1


def test_daily_digest_is_one_per_user_and_contains_overdue_and_today(db) -> None:
    settings = Settings(
        notification_http_url="http://notify.example.test/send",
        server_url="https://workfollow.example.test",
    )
    user_id = "20000000-0000-0000-0000-000000000001"
    overdue = Todo(
        owner_id=user_id,
        creator_id=user_id,
        title="逾期任务",
        due_at=datetime(2026, 8, 20, 18),
    )
    today = Todo(
        owner_id=user_id,
        creator_id=user_id,
        title="今日任务",
        due_at=datetime(2026, 8, 21, 18),
    )
    completed = Todo(
        owner_id=user_id,
        creator_id=user_id,
        title="已完成任务",
        due_at=datetime(2026, 8, 21, 10),
    )
    completed_assignment = TodoAssignment(
        user_id=user_id,
        status=TodoAssignmentStatus.DONE,
    )
    completed.assignments.append(completed_assignment)
    overdue.assignments.append(TodoAssignment(user_id=user_id))
    today.assignments.append(TodoAssignment(user_id=user_id))
    db.add_all([overdue, today, completed])
    db.commit()

    now = datetime(2026, 8, 21, 8, 30)
    assert enqueue_daily_task_digests(db, settings=settings, now=now) == 1
    assert enqueue_daily_task_digests(db, settings=settings, now=now) == 0
    delivery = db.scalar(
        select(ExternalNotificationDelivery).where(
            ExternalNotificationDelivery.notification_type == NotificationType.DAILY_TASK_DIGEST
        )
    )
    assert delivery is not None
    assert "逾期 1 项：逾期任务" in delivery.message
    assert "今日 1 项：今日任务" in delivery.message
    assert delivery.message.endswith("查看今日待办：https://workfollow.example.test/todos?view=today")
    assert delivery.data_json["url"] == "https://workfollow.example.test/todos?view=today"
    assert delivery.data_json["overdueTasks"][0]["url"].endswith(
        f"todo={overdue.id}"
    )
    page_digest = db.scalar(
        select(Notification).where(
            Notification.user_id == user_id,
            Notification.type == NotificationType.DAILY_TASK_DIGEST,
        )
    )
    assert page_digest is not None
    assert page_digest.body == delivery.message
