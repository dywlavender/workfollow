import httpx

from app.agent_client import WorkFollowAgentClient


def test_agent_client_sends_bearer_and_maps_note_tools() -> None:
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.url.path.endswith("/search"):
            return httpx.Response(200, json={"items": [], "total": 0, "hasMore": False})
        if request.url.path.endswith("/notes/import-markdown"):
            return httpx.Response(201, json={"id": "created", "title": "Agent note"})
        return httpx.Response(200, json=[])

    client = WorkFollowAgentClient(
        base_url="http://test/api",
        token="wf_test",
        transport=httpx.MockTransport(handler),
    )
    try:
        client.list_notes(limit=5)
        client.search_notes("会议", limit=3)
        created = client.create_note("# 会议\n\n正文", title="Agent note")
        client.append_note("note-1", "追加", expected_version="note-v1")
        client.list_tasks(due_on="2026-08-29", completed=False)
        client.update_task_metadata(
            "task-1", expected_version="meta-v1", fields={"priority": "HIGH"},
        )
    finally:
        client.close()

    assert created["id"] == "created"
    assert all(request.headers["authorization"] == "Bearer wf_test" for request in requests)
    assert requests[0].url.params["limit"] == "5"
    assert requests[1].url.params["scope"] == "personal"
    assert b"agent-note.md" in requests[2].content
    assert requests[3].url.path.endswith("/agent/notes/note-1/append")
    assert b"note-v1" in requests[3].content
    assert requests[4].url.params["dueOn"] == "2026-08-29"
    assert requests[4].url.params["completed"] == "false"
    assert requests[5].method == "PATCH"
    assert b"meta-v1" in requests[5].content


def test_agent_client_surfaces_api_detail() -> None:
    transport = httpx.MockTransport(lambda _: httpx.Response(401, json={"detail": "Token 已停用"}))
    client = WorkFollowAgentClient(base_url="http://test/api", token="wf_test", transport=transport)
    try:
        try:
            client.list_notes()
        except RuntimeError as exc:
            assert str(exc) == "Token 已停用"
        else:
            raise AssertionError("应当抛出 API 错误")
    finally:
        client.close()


def test_agent_client_compacts_task_write_results() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        task = {
            "id": "task-1",
            "title": "联调",
            "status": "TODO",
            "priority": "NONE",
            "dueAt": "2026-08-30T15:00:00",
            "listName": "收集箱",
            "tags": [],
            "creator": {"id": "user-1", "nickname": "不应返回"},
            "assignments": [{"id": "assignment-1"}],
            "bodyVersion": "body-1",
            "metadataVersion": "meta-1",
        }
        if request.url.path.endswith("/complete"):
            return httpx.Response(200, json={"todo": {**task, "status": "DONE"}, "nextTodo": None})
        return httpx.Response(201, json=task)

    client = WorkFollowAgentClient(
        base_url="http://test/api",
        token="wf_test",
        transport=httpx.MockTransport(handler),
    )
    try:
        created = client.create_task("联调")
        completed = client.set_task_completed("task-1", completed=True)
    finally:
        client.close()

    assert created["bodyVersion"] == "body-1"
    assert completed["status"] == "DONE"
    assert "creator" not in created
    assert "assignments" not in completed
