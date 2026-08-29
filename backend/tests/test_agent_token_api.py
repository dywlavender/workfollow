from fastapi.testclient import TestClient


def test_agent_token_lifecycle_and_bearer_access(client: TestClient, unauthed_client: TestClient) -> None:
    initial = client.get("/api/auth/agent-token")
    assert initial.status_code == 200
    assert initial.json() == {"enabled": False, "createdAt": None, "lastUsedAt": None}

    generated = client.post("/api/auth/agent-token")
    assert generated.status_code == 200
    first_token = generated.json()["token"]
    assert first_token.startswith("wf_")
    assert generated.json()["enabled"] is True

    bearer = {"Authorization": f"Bearer {first_token}"}
    me = unauthed_client.get("/api/auth/me", headers=bearer)
    assert me.status_code == 200
    assert me.json()["username"] == "tester"
    assert unauthed_client.get("/api/notes", headers=bearer).status_code == 200

    captured = unauthed_client.post(
        "/api/notes/capture", headers=bearer, json={"title": "Agent 速记", "text": "MCP 已连接"}
    )
    assert captured.status_code == 201
    note_id = captured.json()["id"]
    assert unauthed_client.get(f"/api/notes/{note_id}", headers=bearer).json()["plainText"] == "MCP 已连接"
    searched = unauthed_client.get(
        "/api/search", headers=bearer, params={"q": "MCP", "scope": "personal"}
    )
    assert searched.status_code == 200
    assert searched.json()["total"] == 1

    imported = unauthed_client.post(
        "/api/notes/import-markdown",
        headers=bearer,
        data={"title": "Agent Markdown"},
        files={"file": ("agent.md", b"# Heading\n\nBody", "text/markdown")},
    )
    assert imported.status_code == 201
    assert imported.json()["title"] == "Agent Markdown"

    reset = client.post("/api/auth/agent-token")
    assert reset.status_code == 200
    second_token = reset.json()["token"]
    assert second_token != first_token
    assert unauthed_client.get("/api/notes", headers=bearer).status_code == 401
    assert unauthed_client.get(
        "/api/notes", headers={"Authorization": f"Bearer {second_token}"}
    ).status_code == 200

    disabled = client.delete("/api/auth/agent-token")
    assert disabled.status_code == 200
    assert disabled.json()["enabled"] is False
    assert unauthed_client.get(
        "/api/notes", headers={"Authorization": f"Bearer {second_token}"}
    ).status_code == 401


def test_invalid_authorization_does_not_fall_back_to_cookie(client: TestClient) -> None:
    response = client.get("/api/auth/me", headers={"Authorization": "Bearer invalid"})
    assert response.status_code == 401
