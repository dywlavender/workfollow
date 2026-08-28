from datetime import date, datetime

from fastapi.testclient import TestClient
from sqlalchemy import func, inspect, select

from app.models.auth import SystemRole, User, UserStatus
from app.models.todo import Todo, TodoAssignment
from app.services.auth_service import password_hash
from tests.collaboration_helpers import enable_collaboration_bridge, project_body, project_metadata


def add_user(db, suffix: str, role: SystemRole = SystemRole.NORMAL) -> User:
    user = User(
        id=f"50000000-0000-0000-0000-{suffix:0>12}",
        username=f"unified-{suffix}",
        password_hash=password_hash.hash("member-password"),
        nickname=f"成员{suffix}",
        system_role=role,
        can_create_team=role == SystemRole.ROOT,
        status=UserStatus.ACTIVE,
    )
    db.add(user)
    db.commit()
    return user


def login_as(app, username: str) -> TestClient:
    result = TestClient(app)
    response = result.post("/api/auth/login", json={"identifier": username, "password": "member-password"})
    assert response.status_code == 200, response.text
    return result


def test_task_is_single_fact_source_with_multiple_assignments(client: TestClient, db, user_id: str) -> None:
    first = add_user(db, "1")
    second = add_user(db, "2")
    observer = add_user(db, "3")
    team_id = client.post("/api/teams", json={"name": "统一任务团队"}).json()["id"]
    for member in (first, second, observer):
        assert client.post(
            f"/api/teams/{team_id}/members",
            json={"identifier": member.username, "role": "MEMBER"},
        ).status_code == 201

    due_at = datetime.combine(date.today(), datetime.min.time()).replace(hour=18)
    created = client.post("/api/tasks", json={
        "title": "统一事实源任务",
        "dueAt": due_at.isoformat(),
        "assigneeIds": [first.id, second.id],
    })
    assert created.status_code == 201, created.text
    task = created.json()
    assert task["creatorId"] == user_id
    assert task["teamId"] == team_id
    assert task["totalAssignments"] == 2
    assert db.scalar(select(func.count(Todo.id)).where(Todo.title == "统一事实源任务")) == 1
    assert db.scalar(select(func.count(TodoAssignment.id)).where(TodoAssignment.task_id == task["id"])) == 2
    assert not inspect(db.get_bind()).has_table("team_tasks")

    first_client = login_as(client.app, first.username)
    second_client = login_as(client.app, second.username)
    observer_client = login_as(client.app, observer.username)
    assert [item["id"] for item in first_client.get("/api/tasks?view=today").json()] == [task["id"]]
    assert [item["id"] for item in first_client.get("/api/tasks?view=collaboration").json()] == [task["id"]]
    assert [item["id"] for item in first_client.get("/api/tasks?view=assigned-to-me").json()] == [task["id"]]
    assert [item["id"] for item in client.get("/api/tasks?view=collaboration").json()] == [task["id"]]
    assert observer_client.get(f"/api/tasks/{task['id']}").status_code == 404

    first_task = first_client.get(f"/api/tasks/{task['id']}")
    assert first_task.status_code == 200
    assert first_task.json()["permissions"]["editable"] is False
    assert first_task.json()["permissions"]["contentEditable"] is True

    enable_collaboration_bridge(first_client)
    assert project_metadata(first_client, task, actor_id=first.id, title="越权修改").status_code == 403
    document = {"type": "doc", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "执行说明"}]}]}
    content_update = project_body(first_client, task["id"], document, actor_id=first.id)
    assert content_update.status_code == 204, content_update.text
    refreshed = client.get(f"/api/tasks/{task['id']}").json()
    assert refreshed["contentJson"] == document
    assert refreshed["description"] == "执行说明"
    assert project_metadata(
        first_client, task, actor_id=first.id, dueAt=due_at.isoformat()
    ).status_code == 403
    assert first_client.put(
        f"/api/tasks/{task['id']}/assignees", json={"assigneeIds": [first.id]}
    ).status_code == 403
    assert first_client.delete(f"/api/tasks/{task['id']}").status_code == 403

    assert first_client.put(f"/api/tasks/{task['id']}/my-status", json={"status": "DONE"}).status_code == 200
    tracked = client.get("/api/tasks?view=assigned-by-me").json()[0]
    assert tracked["completedAssignments"] == 1
    assert tracked["totalAssignments"] == 2
    assert tracked["status"] == "TODO"
    assert second_client.put(f"/api/tasks/{task['id']}/my-status", json={"status": "DONE"}).status_code == 200
    assert client.get(f"/api/tasks/{task['id']}").json()["status"] == "DONE"


def test_assignment_is_limited_to_team_admins_and_current_members(client: TestClient, db, user_id: str) -> None:
    member = add_user(db, "11")
    external = add_user(db, "12")
    team_id = client.post("/api/teams", json={"name": "权限团队"}).json()["id"]
    assert client.post(
        f"/api/teams/{team_id}/members", json={"identifier": member.username, "role": "MEMBER"}
    ).status_code == 201

    outside = client.post("/api/tasks", json={"title": "非法外部成员", "assigneeIds": [external.id]})
    assert outside.status_code == 422

    member_client = login_as(client.app, member.username)
    legacy_admin_api = member_client.post(
        f"/api/teams/{team_id}/tasks",
        json={"title": "普通成员调用旧管理接口", "assigneeIds": [member.id]},
    )
    assert legacy_admin_api.status_code == 403
    forbidden = member_client.post(
        "/api/tasks", json={"title": "普通成员派给 OWNER", "assigneeIds": [user_id]}
    )
    assert forbidden.status_code == 403
    personal = member_client.post("/api/tasks", json={"title": "成员个人任务"})
    assert personal.status_code == 201
    assert personal.json()["teamId"] is None
    assert [item["userId"] for item in personal.json()["assignments"]] == [member.id]


def test_root_can_create_and_update_team_assignments_without_membership(client: TestClient, db) -> None:
    root = add_user(db, "21", role=SystemRole.ROOT)
    first = add_user(db, "22")
    second = add_user(db, "23")
    external = add_user(db, "24")
    team_id = client.post("/api/teams", json={"name": "系统管理员指派团队"}).json()["id"]
    for member in (first, second):
        assert client.post(
            f"/api/teams/{team_id}/members", json={"identifier": member.username, "role": "MEMBER"}
        ).status_code == 201

    root_client = login_as(client.app, root.username)
    created = root_client.post("/api/tasks", json={
        "title": "ROOT 创建的团队任务",
        "teamId": team_id,
        "assigneeIds": [first.id],
    })
    assert created.status_code == 201, created.text
    task = created.json()
    assert task["teamId"] == team_id
    assert [item["userId"] for item in task["assignments"]] == [first.id]
    assert task["permissions"]["assignable"] is True

    updated = root_client.put(
        f"/api/tasks/{task['id']}/assignees", json={"assigneeIds": [second.id]}
    )
    assert updated.status_code == 200, updated.text
    assert [item["userId"] for item in updated.json()["assignments"]] == [second.id]

    outside = root_client.post("/api/tasks", json={
        "title": "ROOT 不得指派团队外成员",
        "teamId": team_id,
        "assigneeIds": [external.id],
    })
    assert outside.status_code == 422

    inferred = root_client.post("/api/tasks", json={
        "title": "ROOT 必须指定团队",
        "assigneeIds": [first.id],
    })
    assert inferred.status_code == 422
