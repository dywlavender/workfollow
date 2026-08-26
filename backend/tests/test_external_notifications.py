from datetime import datetime, timedelta
from urllib.parse import parse_qs, urlsplit

from fastapi.testclient import TestClient
from sqlalchemy import delete, select

from app.core.config import Settings, get_settings
from app.models.auth import User, UserStatus
from app.models.notification import (
    ExternalDeliveryStatus,
    ExternalNotificationDelivery,
    Notification,
    NotificationType,
    PendingTaskUpdateNotification,
)
from app.models.todo import (
    Todo,
    TodoAssignment,
    TodoAssignmentStatus,
    TodoPriority,
    TodoStatus,
    RecurrenceType,
)
from app.services import external_notification_service, task_notification_service
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


def test_text_autosaves_are_coalesced_until_idle(db, user_id, monkeypatch) -> None:
    target = add_external_user(db, "70000000-0000-0000-0000-000000000009", "external-text-edit")
    todo = Todo(
        owner_id=user_id,
        creator_id=user_id,
        title="连续编辑任务",
        description="初始说明",
        status=TodoStatus.TODO,
        priority=TodoPriority.NONE,
        recurrence_type=RecurrenceType.NONE,
        list_name="收集箱",
        tags=[],
        attachment_ids=[],
        assignments=[TodoAssignment(user_id=target.id, status=TodoAssignmentStatus.TODO, active=True)],
    )
    db.add(todo)
    db.commit()
    db.refresh(todo)

    settings = Settings(
        notification_http_url="http://notify.example.test/send",
        server_url="https://workfollow.example.test",
        notification_task_edit_quiet_seconds=3,
    )
    monkeypatch.setattr(external_notification_service, "get_settings", lambda: settings)

    before = task_notification_service.task_change_snapshot(todo)
    todo.description = "第一次自动保存"
    task_notification_service.notify_task_updated(db, todo, user_id, before, commit=False)
    db.commit()
    before_second = task_notification_service.task_change_snapshot(todo)
    todo.description = "最终说明"
    task_notification_service.notify_task_updated(db, todo, user_id, before_second, commit=False)
    db.commit()

    assert db.scalars(select(Notification)).all() == []
    assert db.scalars(select(ExternalNotificationDelivery)).all() == []
    pending = db.scalar(select(PendingTaskUpdateNotification))
    assert pending is not None
    assert pending.before_json["description"] == "初始说明"
    assert pending.after_json["description"] == "最终说明"

    assert task_notification_service.dispatch_pending_task_update_notifications(
        db,
        settings=settings,
        now=pending.next_attempt_at + timedelta(seconds=1),
    ) == 1
    notifications = db.scalars(select(Notification)).all()
    deliveries = db.scalars(select(ExternalNotificationDelivery)).all()
    assert len(notifications) == 1
    assert len(deliveries) == 1
    assert notifications[0].data_json["changedFields"] == ["description"]
    assert notifications[0].data_json["changes"]["description"]["after"] == "最终说明"
    assert db.scalars(select(PendingTaskUpdateNotification)).all() == []


def test_member_content_edit_does_not_notify_but_admin_edit_does(client, db) -> None:
    member = add_external_user(db, "70000000-0000-0000-0000-000000000010", "task-member")
    team = client.post("/api/teams", json={"name": "成员编辑通知"}).json()
    assert client.post(
        f"/api/teams/{team['id']}/members",
        json={"identifier": member.username, "role": "MEMBER"},
    ).status_code == 201
    task = client.post(
        "/api/tasks",
        json={"title": "成员编辑任务", "assigneeIds": [member.id]},
    ).json()
    db.execute(delete(Notification))
    db.execute(delete(ExternalNotificationDelivery))
    db.commit()

    member_client = login_external_user(client.app, member.username)
    member_update = member_client.put(
        f"/api/tasks/{task['id']}",
        json={
            "contentJson": {
                "type": "doc",
                "content": [{"type": "paragraph", "content": [{"type": "text", "text": "成员说明"}]}],
            }
        },
    )
    assert member_update.status_code == 200, member_update.text
    assert db.scalars(select(Notification)).all() == []
    assert db.scalars(select(ExternalNotificationDelivery)).all() == []
    assert db.scalars(select(PendingTaskUpdateNotification)).all() == []

    admin_update = client.put(
        f"/api/tasks/{task['id']}",
        json={
            "contentJson": {
                "type": "doc",
                "content": [{"type": "paragraph", "content": [{"type": "text", "text": "管理员说明"}]}],
            }
        },
    )
    assert admin_update.status_code == 200, admin_update.text
    assert db.scalar(select(PendingTaskUpdateNotification)) is not None


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


def test_knowledge_review_and_result_notifications_use_external_get_contract(client, db, monkeypatch) -> None:
    applicant = add_external_user(
        db, "70000000-0000-0000-0000-000000000009", "knowledge-applicant"
    )
    team = client.post("/api/teams", json={"name": "知识审核外部通知"}).json()
    assert client.post(
        f"/api/teams/{team['id']}/members",
        json={"identifier": applicant.username, "role": "MEMBER"},
    ).status_code == 201

    settings = Settings(
        notification_http_url="http://notify.example.test/send",
        server_url="https://workfollow.example.test",
    )
    client.app.dependency_overrides[get_settings] = lambda: settings
    monkeypatch.setattr(external_notification_service, "get_settings", lambda: settings)

    applicant_client = login_external_user(client.app, applicant.username)

    def submit(title: str) -> dict[str, str]:
        note = applicant_client.post("/api/notes", json={"title": title}).json()
        response = applicant_client.post(
            f"/api/notes/{note['id']}/submissions",
            params={"teamId": team["id"]},
            json={"type": "CREATE"},
        )
        assert response.status_code == 201, response.text
        return response.json()

    pending = submit("待审核知识")
    review_delivery = db.scalar(select(ExternalNotificationDelivery).where(
        ExternalNotificationDelivery.notification_type == NotificationType.TEAM_NOTE_SUBMITTED,
        ExternalNotificationDelivery.username == "tester",
    ))
    assert review_delivery is not None
    review_url = f"https://workfollow.example.test/notes?view=review&submission={pending['id']}"
    assert review_delivery.data_json["url"] == review_url
    assert review_delivery.data_json["eventType"] == "TEAM_NOTE_SUBMITTED"
    assert review_delivery.message.endswith(f"查看审核：{review_url}")

    needs_revision = submit("需要修改的知识")
    response = client.post(
        f"/api/note-submissions/{needs_revision['id']}/request-revision",
        json={"reason": "请补充操作步骤"},
    )
    assert response.status_code == 200, response.text
    revision_delivery = db.scalar(select(ExternalNotificationDelivery).where(
        ExternalNotificationDelivery.notification_type == NotificationType.TEAM_NOTE_REVIEWED,
        ExternalNotificationDelivery.user_id == applicant.id,
    ))
    assert revision_delivery is not None
    revision_url = f"https://workfollow.example.test/notes?view=submissions&submission={needs_revision['id']}"
    assert revision_delivery.data_json["url"] == revision_url
    assert "请补充操作步骤" in revision_delivery.message
    assert revision_delivery.message.endswith(f"查看投稿：{revision_url}")

    rejected = submit("被拒绝的知识")
    response = client.post(
        f"/api/note-submissions/{rejected['id']}/reject",
        json={"reason": "内容重复"},
    )
    assert response.status_code == 200, response.text
    reject_delivery = db.scalar(select(ExternalNotificationDelivery).where(
        ExternalNotificationDelivery.notification_type == NotificationType.TEAM_NOTE_REJECTED,
        ExternalNotificationDelivery.user_id == applicant.id,
    ))
    assert reject_delivery is not None
    reject_url = f"https://workfollow.example.test/notes?view=submissions&submission={rejected['id']}"
    assert reject_delivery.data_json["url"] == reject_url
    assert reject_delivery.message.endswith(f"查看投稿：{reject_url}")

    approved = submit("通过的知识")
    response = client.post(f"/api/note-submissions/{approved['id']}/approve", json={})
    assert response.status_code == 200, response.text
    approved_delivery = db.scalar(select(ExternalNotificationDelivery).where(
        ExternalNotificationDelivery.notification_type == NotificationType.TEAM_NOTE_APPROVED,
        ExternalNotificationDelivery.user_id == applicant.id,
    ))
    assert approved_delivery is not None
    knowledge_id = response.json()["id"]
    knowledge_url = f"https://workfollow.example.test/notes?view=knowledge&knowledge={knowledge_id}"
    assert approved_delivery.data_json["url"] == knowledge_url
    assert approved_delivery.data_json["submissionUrl"] == (
        f"https://workfollow.example.test/notes?view=submissions&submission={approved['id']}"
    )
    assert approved_delivery.message.endswith(
        f"查看知识：{knowledge_url}；查看投稿结果：{approved_delivery.data_json['submissionUrl']}"
    )
