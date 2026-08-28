from fastapi.testclient import TestClient
from sqlalchemy import select

from app.models.auth import User, UserStatus
from app.models.resource_relation import RelationType, ResourceRelation, ResourceType
from app.models.todo import Todo
from app.services.auth_service import password_hash
from tests.collaboration_helpers import enable_collaboration_bridge, project_body, project_metadata, project_note


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


def task_body_with_task_link(task_id: str) -> dict:
    return {
        "type": "doc",
        "content": [{
            "type": "paragraph",
            "attrs": {"blockId": "task-link-block"},
            "content": [{
                "type": "text",
                "text": "继续处理",
                "marks": [{"type": "taskLink", "attrs": {"taskId": task_id}}],
            }],
        }],
    }


def task_body_with_note_link(note_id: str) -> dict:
    return {
        "type": "doc",
        "content": [{
            "type": "paragraph",
            "attrs": {"blockId": "note-link-block"},
            "content": [{
                "type": "text",
                "text": "查看笔记",
                "marks": [{"type": "noteLink", "attrs": {"noteId": note_id}}],
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

    # The note body may also contain a collaborative REFERENCES edge to the
    # same task.  It is a graph backlink, not a second task provenance row.
    assert project_note(client, note["id"], content_json=task_link_document(task["id"])).status_code == 204
    assert len(client.get(f"/api/tasks/{task['id']}").json()["sources"]) == 1

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
    assert project_note(client, note["id"], content_json=task_link_document(task["id"])).status_code == 204

    cleared = {"type": "doc", "content": [{"type": "paragraph", "attrs": {"blockId": "block-origin"}}]}
    assert project_note(client, note["id"], content_json=cleared).status_code == 204
    relation = db.scalar(select(ResourceRelation).where(ResourceRelation.target_id == task["id"]))
    db.refresh(relation)
    assert relation.deleted_at is not None
    assert client.get(f"/api/tasks/{task['id']}").status_code == 200
    assert client.get(f"/api/tasks/{task['id']}").json()["sources"] == []


def test_task_body_projection_reconciles_outgoing_task_relation(client: TestClient, db) -> None:
    source = client.post("/api/tasks", json={"title": "来源任务"}).json()
    target = client.post("/api/tasks", json={"title": "关联任务"}).json()
    enable_collaboration_bridge(client)

    projected = project_body(client, source["id"], task_body_with_task_link(target["id"]))
    assert projected.status_code == 204, projected.text
    relation = db.scalar(select(ResourceRelation).where(
        ResourceRelation.source_type == ResourceType.TASK,
        ResourceRelation.source_id == source["id"],
        ResourceRelation.target_type == ResourceType.TASK,
        ResourceRelation.target_id == target["id"],
        ResourceRelation.relation_type == RelationType.REFERENCES,
        ResourceRelation.deleted_at.is_(None),
    ))
    assert relation is not None
    assert relation.source_block_id == "task-link-block"

    cleared = {"type": "doc", "content": [{"type": "paragraph", "attrs": {"blockId": "task-link-block"}}]}
    assert project_body(client, source["id"], cleared).status_code == 204
    db.refresh(relation)
    assert relation.deleted_at is not None


def test_task_body_projection_reconciles_outgoing_note_relation(client: TestClient, db) -> None:
    source = client.post("/api/tasks", json={"title": "来源任务"}).json()
    note = client.post("/api/notes", json={"title": "关联笔记"}).json()
    enable_collaboration_bridge(client)

    projected = project_body(client, source["id"], task_body_with_note_link(note["id"]))
    assert projected.status_code == 204, projected.text
    relation = db.scalar(select(ResourceRelation).where(
        ResourceRelation.source_type == ResourceType.TASK,
        ResourceRelation.source_id == source["id"],
        ResourceRelation.target_type == ResourceType.PERSONAL_NOTE,
        ResourceRelation.target_id == note["id"],
        ResourceRelation.relation_type == RelationType.REFERENCES,
        ResourceRelation.deleted_at.is_(None),
    ))
    assert relation is not None
    assert relation.source_block_id == "note-link-block"


def test_note_creation_and_copy_register_document_relations_immediately(client: TestClient, db) -> None:
    task = client.post("/api/tasks", json={"title": "创建时关联的任务"}).json()
    linked_content = task_body_with_task_link(task["id"])
    source = client.post("/api/notes", json={
        "title": "带关联的来源笔记",
        "contentJson": linked_content,
    })
    assert source.status_code == 201, source.text
    relation = db.scalar(select(ResourceRelation).where(
        ResourceRelation.source_type == ResourceType.PERSONAL_NOTE,
        ResourceRelation.source_id == source.json()["id"],
        ResourceRelation.target_type == ResourceType.TASK,
        ResourceRelation.target_id == task["id"],
        ResourceRelation.relation_type == RelationType.REFERENCES,
        ResourceRelation.deleted_at.is_(None),
    ))
    assert relation is not None

    copied = client.post(f"/api/notes/{source.json()['id']}/copy")
    assert copied.status_code == 201, copied.text
    copied_relation = db.scalar(select(ResourceRelation).where(
        ResourceRelation.source_type == ResourceType.PERSONAL_NOTE,
        ResourceRelation.source_id == copied.json()["id"],
        ResourceRelation.target_type == ResourceType.TASK,
        ResourceRelation.target_id == task["id"],
        ResourceRelation.relation_type == RelationType.REFERENCES,
        ResourceRelation.deleted_at.is_(None),
    ))
    assert copied_relation is not None


def test_task_creation_registers_embedded_document_relations_immediately(client: TestClient, db) -> None:
    target = client.post("/api/tasks", json={"title": "创建时被引用的任务"}).json()
    note = client.post("/api/notes", json={"title": "创建时被引用的笔记"}).json()
    content = {
        "type": "doc",
        "content": [{
            "type": "paragraph",
            "attrs": {"blockId": "created-task-block"},
            "content": [{
                "type": "text",
                "text": "同时引用任务和笔记",
                "marks": [
                    {"type": "taskLink", "attrs": {"taskId": target["id"]}},
                    {"type": "noteLink", "attrs": {"noteId": note["id"]}},
                ],
            }],
        }],
    }
    created = client.post("/api/tasks", json={"title": "正文带链接的任务", "contentJson": content})
    assert created.status_code == 201, created.text
    created_id = created.json()["id"]
    relations = list(db.scalars(select(ResourceRelation).where(
        ResourceRelation.source_type == ResourceType.TASK,
        ResourceRelation.source_id == created_id,
        ResourceRelation.relation_type == RelationType.REFERENCES,
        ResourceRelation.deleted_at.is_(None),
    )))
    assert {(item.target_type, item.target_id, item.source_block_id) for item in relations} == {
        (ResourceType.TASK, target["id"], "created-task-block"),
        (ResourceType.PERSONAL_NOTE, note["id"], "created-task-block"),
    }


def test_recurring_task_copy_registers_inherited_document_relations(client: TestClient, db) -> None:
    target = client.post("/api/tasks", json={"title": "重复任务引用目标"}).json()
    recurring = client.post("/api/tasks", json={
        "title": "带链接的重复任务",
        "contentJson": task_body_with_task_link(target["id"]),
        "dueAt": "2026-08-28T09:00:00",
        "recurrenceType": "DAILY",
    })
    assert recurring.status_code == 201, recurring.text

    completed = client.post(f"/api/tasks/{recurring.json()['id']}/complete")
    assert completed.status_code == 200, completed.text
    next_task = completed.json()["nextTodo"]
    assert next_task is not None
    relation = db.scalar(select(ResourceRelation).where(
        ResourceRelation.source_type == ResourceType.TASK,
        ResourceRelation.source_id == next_task["id"],
        ResourceRelation.target_type == ResourceType.TASK,
        ResourceRelation.target_id == target["id"],
        ResourceRelation.relation_type == RelationType.REFERENCES,
        ResourceRelation.deleted_at.is_(None),
    ))
    assert relation is not None
    assert relation.source_block_id == "task-link-block"


def test_note_body_reconciles_outgoing_note_relation_when_link_is_removed(client: TestClient, db) -> None:
    source = client.post("/api/notes", json={"title": "来源笔记"}).json()
    target = client.post("/api/notes", json={"title": "关联笔记"}).json()
    linked = {
        "type": "doc",
        "content": [{
            "type": "paragraph",
            "attrs": {"blockId": "note-link-block"},
            "content": [{
                "type": "text",
                "text": "查看关联笔记",
                "marks": [{"type": "noteLink", "attrs": {"noteId": target["id"]}}],
            }],
        }],
    }
    assert project_note(client, source["id"], content_json=linked).status_code == 204
    relation = db.scalar(select(ResourceRelation).where(
        ResourceRelation.source_type == ResourceType.PERSONAL_NOTE,
        ResourceRelation.source_id == source["id"],
        ResourceRelation.target_type == ResourceType.PERSONAL_NOTE,
        ResourceRelation.target_id == target["id"],
        ResourceRelation.relation_type == RelationType.REFERENCES,
        ResourceRelation.deleted_at.is_(None),
    ))
    assert relation is not None

    cleared = {"type": "doc", "content": [{"type": "paragraph", "attrs": {"blockId": "note-link-block"}}]}
    assert project_note(client, source["id"], content_json=cleared).status_code == 204
    db.refresh(relation)
    assert relation.deleted_at is not None


def test_deleted_note_retires_incoming_and_outgoing_relations(client: TestClient, db) -> None:
    source = client.post("/api/notes", json={"title": "将被删除的来源笔记"}).json()
    target = client.post("/api/notes", json={"title": "被引用的笔记"}).json()
    task = client.post("/api/tasks", json={
        "title": "来自待删除笔记的任务",
        "source": {"resourceType": "PERSONAL_NOTE", "resourceId": source["id"]},
    }).json()
    document = {
        "type": "doc",
        "content": [{
            "type": "paragraph",
            "attrs": {"blockId": "delete-source-block"},
            "content": [
                {"type": "text", "text": "任务", "marks": [{"type": "taskLink", "attrs": {"taskId": task["id"]}}]},
                {"type": "text", "text": "笔记", "marks": [{"type": "noteLink", "attrs": {"noteId": target["id"]}}]},
            ],
        }],
    }
    assert project_note(client, source["id"], content_json=document).status_code == 204

    active = list(db.scalars(select(ResourceRelation).where(
        ResourceRelation.source_id == source["id"],
        ResourceRelation.deleted_at.is_(None),
    )))
    assert len(active) == 3
    assert client.delete(f"/api/notes/{source['id']}").status_code == 204

    db.expire_all()
    retired = list(db.scalars(select(ResourceRelation).where(
        ResourceRelation.source_id == source["id"],
    )))
    assert retired
    assert all(item.deleted_at is not None for item in retired)
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
    assert project_note(client, note["id"], content_json=document).status_code == 204
    enable_collaboration_bridge(client)
    assert project_metadata(client, task, title="Task 中已更新").status_code == 204
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
