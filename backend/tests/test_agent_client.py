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
    finally:
        client.close()

    assert created["id"] == "created"
    assert all(request.headers["authorization"] == "Bearer wf_test" for request in requests)
    assert requests[0].url.params["limit"] == "5"
    assert requests[1].url.params["scope"] == "personal"
    assert b"agent-note.md" in requests[2].content


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
