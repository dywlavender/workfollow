from datetime import datetime

from fastapi import HTTPException

from app.api.routes import agent as agent_routes
from app.main import _agent_resource


def _bearer(client, unauthed_client):  # noqa: ANN001, ANN202
    token = client.post("/api/auth/agent-token").json()["token"]
    return unauthed_client, {"Authorization": f"Bearer {token}"}


def test_agent_note_read_append_and_conflict(client, unauthed_client, monkeypatch) -> None:  # noqa: ANN001
    note = client.post("/api/notes/capture", json={"title": "记录", "text": "原文"}).json()
    api, headers = _bearer(client, unauthed_client)
    calls: list[dict] = []

    def fake_document_request(_settings, **kwargs):  # noqa: ANN001, ANN202
        calls.append(kwargs)
        if kwargs.get("operation", "read") == "read":
            return {
                "version": "version-1",
                "title": "记录",
                "contentJson": {"type": "doc", "content": [{"type": "paragraph"}]},
            }
        if kwargs["expected_version"] != "version-1":
            raise HTTPException(status_code=409, detail="文档已被其他编辑者修改，请重新读取后再提交")
        return {"version": "version-2", "title": "记录", "contentJson": kwargs["content_json"]}

    monkeypatch.setattr(agent_routes, "document_request", fake_document_request)
    read = api.get(f"/api/agent/notes/{note['id']}", headers=headers)
    assert read.status_code == 200
    assert read.json()["version"] == "version-1"

    appended = api.post(
        f"/api/agent/notes/{note['id']}/append",
        headers=headers,
        json={"markdown": "新增段落", "expectedVersion": "version-1"},
    )
    assert appended.status_code == 200
    assert calls[-1]["operation"] == "append-body"

    conflict = api.post(
        f"/api/agent/notes/{note['id']}/append",
        headers=headers,
        json={"markdown": "冲突内容", "expectedVersion": "stale"},
    )
    assert conflict.status_code == 409


def test_agent_task_create_read_and_metadata_update(client, unauthed_client, monkeypatch) -> None:  # noqa: ANN001
    api, headers = _bearer(client, unauthed_client)
    calls: list[dict] = []

    def fake_document_request(_settings, **kwargs):  # noqa: ANN001, ANN202
        calls.append(kwargs)
        if kwargs["document_name"].startswith("task-meta:"):
            metadata = {"title": kwargs["seed"]["title"], **(kwargs.get("metadata") or {})}
            return {"version": "meta-2", "metadata": metadata}
        return {
            "version": "body-1",
            "contentJson": kwargs["seed"].get("contentJson") or {"type": "doc", "content": []},
        }

    monkeypatch.setattr(agent_routes, "document_request", fake_document_request)
    created = api.post(
        "/api/agent/tasks",
        headers=headers,
        json={"title": "Agent 任务", "priority": "HIGH", "tags": ["MCP"]},
    )
    assert created.status_code == 201, created.text
    task_id = created.json()["id"]
    assert created.json()["bodyVersion"] == "body-1"
    assert created.json()["metadataVersion"] == "meta-2"

    updated = api.patch(
        f"/api/agent/tasks/{task_id}/metadata",
        headers=headers,
        json={"expectedVersion": "meta-2", "title": "更新后的任务", "tags": ["Agent"]},
    )
    assert updated.status_code == 200
    assert calls[-1]["operation"] == "update-metadata"
    assert calls[-1]["metadata"] == {"title": "更新后的任务", "tags": ["Agent"]}

    listed = api.get("/api/agent/tasks", headers=headers)
    assert listed.status_code == 200
    summary = next(item for item in listed.json() if item["id"] == task_id)
    assert summary["title"] == "Agent 任务"
    assert summary["myStatus"] == "TODO"
    assert "description" not in summary
    assert "assignments" not in summary
    assert "creator" not in summary


def test_agent_task_list_filters_due_date_and_completion(client, unauthed_client) -> None:  # noqa: ANN001
    api, headers = _bearer(client, unauthed_client)
    due_today = datetime(2026, 8, 29, 15, 0)
    open_task = client.post("/api/tasks", json={
        "title": "今天未完成",
        "dueAt": due_today.isoformat(),
    }).json()
    completed_task = client.post("/api/tasks", json={
        "title": "今天已完成",
        "dueAt": due_today.isoformat(),
    }).json()
    client.post(f"/api/tasks/{completed_task['id']}/complete")
    client.post("/api/tasks", json={
        "title": "明天未完成",
        "dueAt": "2026-08-30T15:00:00",
    })

    response = api.get(
        "/api/agent/tasks?dueOn=2026-08-29&completed=false",
        headers=headers,
    )
    assert response.status_code == 200, response.text
    assert [item["id"] for item in response.json()] == [open_task["id"]]


def test_agent_routes_reject_browser_session(client) -> None:  # noqa: ANN001
    assert client.get("/api/agent/tasks").status_code == 401


def test_agent_token_cannot_escape_documented_api_surface(client, unauthed_client) -> None:  # noqa: ANN001
    api, headers = _bearer(client, unauthed_client)
    note = client.post("/api/notes/capture", json={"title": "保留", "text": "正文"}).json()

    assert api.delete(f"/api/notes/{note['id']}", headers=headers).status_code == 403
    assert api.get("/api/auth/agent-actions", headers=headers).status_code == 403
    assert api.get("/api/admin/users", headers=headers).status_code == 403


def test_agent_audit_resource_parsing() -> None:
    assert _agent_resource("/api/agent/tasks") == ("TASK", None)
    assert _agent_resource("/api/agent/notes/note-1/append") == ("NOTE", "note-1")
    assert _agent_resource("/api/notes/capture") == ("NOTE", None)
    assert _agent_resource("/api/tasks/task-1/complete") == ("TASK", "task-1")
