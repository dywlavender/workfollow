from __future__ import annotations

from typing import Any

from fastapi.testclient import TestClient

from app.core.config import Settings, get_settings


COLLABORATION_TOKEN = "local-test-token"


def enable_collaboration_bridge(client: TestClient) -> None:
    existing = client.app.dependency_overrides.get(get_settings)
    base = existing() if existing else get_settings()
    settings = base.model_copy(update={"collaboration_internal_token": COLLABORATION_TOKEN})
    client.app.dependency_overrides[get_settings] = lambda: settings


def project_body(
    client: TestClient,
    task_id: str,
    content_json: dict[str, Any],
    *,
    actor_id: str | None = None,
    path_prefix: str = "/api/tasks",
):
    return client.put(
        f"{path_prefix}/{task_id}/collaboration-snapshot",
        json={"contentJson": content_json, "actorId": actor_id},
        headers={"X-WorkFollow-Collaboration-Token": COLLABORATION_TOKEN},
    )


def project_note(
    client: TestClient,
    note_id: str,
    *,
    content_json: dict[str, Any],
    title: str | None = None,
):
    enable_collaboration_bridge(client)
    if title is None:
        title = client.get(f"/api/notes/{note_id}").json()["title"]
    return client.put(
        f"/api/notes/{note_id}/collaboration-snapshot",
        json={"title": title, "contentJson": content_json},
        headers={"X-WorkFollow-Collaboration-Token": COLLABORATION_TOKEN},
    )


def project_metadata(
    client: TestClient,
    task: dict[str, Any],
    *,
    actor_id: str | None = None,
    path_prefix: str = "/api/tasks",
    **changes: Any,
):
    payload = {
        "title": task.get("title", ""),
        "dueAt": task.get("dueAt"),
        "dueEndAt": task.get("dueEndAt"),
        "priority": task.get("priority", "NONE"),
        "reminderAt": task.get("reminderAt"),
        "recurrenceType": task.get("recurrenceType", "NONE"),
        "recurrenceConfig": task.get("recurrenceConfig"),
        "listName": task.get("listName"),
        "tags": task.get("tags", []),
        **changes,
        "actorId": actor_id,
    }
    return client.put(
        f"{path_prefix}/{task['id']}/collaboration-metadata",
        json=payload,
        headers={"X-WorkFollow-Collaboration-Token": COLLABORATION_TOKEN},
    )
