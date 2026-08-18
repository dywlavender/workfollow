from fastapi.testclient import TestClient
from sqlalchemy import select

from app.models.auth import User, UserStatus
from app.models.resource_relation import RelationType, ResourceRelation, ResourceType
from app.models.todo import Todo
from app.services.auth_service import password_hash


def add_user(db, user_id: str, username: str) -> User:
    user = User(
        id=user_id,
        username=username,
        password_hash=password_hash.hash("member-password"),
        nickname=username,
        status=UserStatus.ACTIVE,
    )
    db.add(user)
    db.commit()
    return user


def login(app, username: str) -> TestClient:
    client = TestClient(app)
    response = client.post(
        "/api/auth/login", json={"identifier": username, "password": "member-password"}
    )
    assert response.status_code == 200
    return client


def task_link_document(task_id: str) -> dict:
    return {
        "type": "doc",
        "content": [{
            "type": "paragraph",
            "attrs": {"blockId": "block-origin"},
            "content": [{
                "type": "text",
                "text": "完成接口联调",
                "marks": [{"type": "taskLink", "attrs": {"taskId": task_id}}],
            }],
        }],
    }


def test_create_task_source_is_transactional_and_backlink_is_permission_filtered(
    client: TestClient, db
) -> None:
    member = add_user(db, "91000000-0000-0000-0000-000000000001", "relation-member")
    team_id = client.post("/api/teams", json={"name": "关系权限团队"}).json()["id"]
    assert client.post(
        f"/api/teams/{team_id}/members",
        json={"identifier": member.username, "role": "MEMBER"},
    ).status_code == 201
    note = client.post("/api/notes", json={"title": "私密会议记录"}).json()

    created = client.post("/api/tasks", json={
        "title": "完成接口联调",
        "assigneeIds": [member.id],
        "source": {
            "resourceType": "PERSONAL_NOTE",
            "resourceId": note["id"],
            "blockId": "block-origin",
            "excerpt": "完成接口联调",
        },
    })
    assert created.status_code == 201, created.text
    task = created.json()
    assert task["sources"] == [{
        "relationId": task["sources"][0]["relationId"],
        "resourceType": "PERSONAL_NOTE",
        "resourceId": note["id"],
        "blockId": "block-origin",
        "title": "私密会议记录",
        "excerpt": "完成接口联调",
        "accessible": True,
    }]

    relation = db.scalar(select(ResourceRelation).where(ResourceRelation.target_id == task["id"]))
    assert relation is not None
    assert relation.relation_type == RelationType.CREATED_FROM

    member_client = login(client.app, member.username)
    member_task = member_client.get(f"/api/tasks/{task['id']}")
    assert member_task.status_code == 200
    assert member_task.json()["sources"] == [{
        "relationId": relation.id,
        "resourceType": "PERSONAL_NOTE",
        "resourceId": None,
        "blockId": None,
        "title": None,
        "excerpt": None,
        "accessible": False,
    }]
    assert member_client.get(f"/api/notes/{note['id']}").status_code == 404

    before = len(client.get("/api/tasks", params={"view": "all"}).json())
    invalid = client.post("/api/tasks", json={
        "title": "不应半成功",
        "source": {
            "resourceType": "PERSONAL_NOTE",
            "resourceId": "missing-note",
        },
    })
    assert invalid.status_code == 404
    assert len(client.get("/api/tasks", params={"view": "all"}).json()) == before


def test_reference_removal_soft_deletes_relation_but_keeps_task(client: TestClient, db) -> None:
    note = client.post("/api/notes", json={"title": "引用生命周期"}).json()
    task = client.post("/api/tasks", json={
        "title": "完成接口联调",
        "source": {
            "resourceType": "PERSONAL_NOTE",
            "resourceId": note["id"],
            "blockId": "block-origin",
            "excerpt": "完成接口联调",
        },
    }).json()
    assert client.put(
        f"/api/notes/{note['id']}", json={"contentJson": task_link_document(task["id"])}
    ).status_code == 200

    cleared = {"type": "doc", "content": [{"type": "paragraph", "attrs": {"blockId": "block-origin"}}]}
    assert client.put(f"/api/notes/{note['id']}", json={"contentJson": cleared}).status_code == 200
    relation = db.scalar(select(ResourceRelation).where(ResourceRelation.target_id == task["id"]))
    db.refresh(relation)
    assert relation.deleted_at is not None
    assert client.get(f"/api/tasks/{task['id']}").status_code == 200
    assert client.get(f"/api/tasks/{task['id']}").json()["sources"] == []


def test_link_existing_task_and_batch_brief_do_not_copy_or_leak_task_facts(
    client: TestClient, db
) -> None:
    note = client.post("/api/notes", json={"title": "已有任务引用"}).json()
    task = client.post("/api/tasks", json={"title": "事实来自 Task", "priority": "HIGH"}).json()
    relation = client.post("/api/resource-relations", json={
        "sourceType": "PERSONAL_NOTE",
        "sourceId": note["id"],
        "sourceBlockId": "block-reference",
        "targetType": "TASK",
        "targetId": task["id"],
        "relationType": "REFERENCES",
    })
    assert relation.status_code == 201, relation.text
    assert db.scalar(select(Todo).where(Todo.id == task["id"])).title == "事实来自 Task"
    assert len(db.scalars(select(Todo)).all()) == 1

    document = {
        "type": "doc",
        "content": [{"type": "taskReference", "attrs": {"taskId": task["id"]}}],
    }
    assert set(document["content"][0]["attrs"]) == {"taskId"}
    assert client.put(f"/api/notes/{note['id']}", json={"contentJson": document}).status_code == 200
    assert client.put(f"/api/tasks/{task['id']}", json={"title": "Task 中已更新"}).status_code == 200
    brief = client.get("/api/tasks/brief", params=[("ids", task["id"])]).json()[0]
    assert brief["title"] == "Task 中已更新"

    outsider = add_user(db, "91000000-0000-0000-0000-000000000002", "relation-outsider")
    outsider_client = login(client.app, outsider.username)
    hidden = outsider_client.get("/api/tasks/brief", params=[("ids", task["id"])]).json()[0]
    assert hidden == {
        "id": task["id"],
        "accessible": False,
        "deleted": False,
        "title": None,
        "status": None,
        "priority": None,
        "dueAt": None,
        "assignees": [],
        "permissions": {"completable": False},
    }

    assert client.delete(f"/api/tasks/{task['id']}").status_code == 204
    deleted = client.get("/api/tasks/brief", params=[("ids", task["id"])]).json()[0]
    assert deleted["deleted"] is True
    assert deleted["title"] is None


def test_linkable_search_prioritizes_unfinished_tasks(client: TestClient) -> None:
    completed = client.post("/api/tasks", json={"title": "已完成候选"}).json()
    assert client.post(f"/api/tasks/{completed['id']}/complete").status_code == 200
    pending = client.post("/api/tasks", json={"title": "未完成候选"}).json()

    linkable = client.get("/api/tasks", params={"view": "linkable"})
    assert linkable.status_code == 200
    titles = [item["title"] for item in linkable.json()]
    assert titles.index(pending["title"]) < titles.index(completed["title"])
