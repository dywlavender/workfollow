import asyncio
from importlib import import_module

import pytest

from app.api.routes.ai import get_text_ai_service
from app.core.config import Settings, get_settings
from app.main import app
from app.services.ai_service import TextAIService
from test_ai_service import RecordingModel
from conftest import TestingSession


@pytest.fixture(autouse=True)
def isolated_ai_lifespan(monkeypatch, tmp_path, reset_database):
    """Keep these API tests independent of a developer's configured database."""
    settings = Settings(_env_file=None, ai_enabled=False,
                        uploads_dir=tmp_path / "data" / "uploads", files_dir=tmp_path / "data" / "files")
    main_module = import_module("app.main")
    monkeypatch.setattr(main_module, "SessionLocal", TestingSession)
    monkeypatch.setattr(main_module, "settings", settings)
    app.dependency_overrides[get_settings] = lambda: settings


def test_ai_requires_existing_login(unauthed_client):
    assert unauthed_client.get("/api/ai/config").status_code == 401
    response = unauthed_client.post("/api/ai/generate", json={"action": "improve_summary", "content": "摘要"})
    assert response.status_code == 401


def test_config_does_not_expose_provider_key(client):
    settings = Settings(_env_file=None, ai_enabled=True, ai_api_key="private-test-credential", ai_model="test-model")
    app.dependency_overrides[get_settings] = lambda: settings
    response = client.get("/api/ai/config")
    assert response.status_code == 200
    assert response.json()["configured"] is True
    assert "private-test-credential" not in response.text
    assert "apiKey" not in response.json()


def test_generate_returns_draft_and_keeps_normal_apis_working(client):
    model = RecordingModel(responses=['{"tasks":[{"title":"提交方案","date":"2026-10-29","quote":"明天提交方案。"}]}'])

    async def service():
        yield TextAIService(Settings(_env_file=None, ai_enabled=True, ai_model="test-model"), model=model)

    app.dependency_overrides[get_text_ai_service] = service
    before = client.get("/api/tasks").json()
    response = client.post("/api/ai/generate", json={
        "action": "extract_tasks", "content": "明天提交方案。", "referenceDate": "2026-10-28",
    })
    assert response.status_code == 200, response.text
    assert response.json()["tasks"][0]["date"] == "2026-10-29"
    assert response.json()["usage"]["modelCalls"] == 1
    assert client.get("/api/tasks").json() == before
    assert client.get("/api/health").status_code == 200


def test_disabled_ai_does_not_break_backend(client):
    settings = Settings(_env_file=None, ai_enabled=False)
    app.dependency_overrides[get_settings] = lambda: settings
    response = client.post("/api/ai/generate", json={"action": "improve_summary", "content": "摘要"})
    assert response.status_code == 503
    assert client.get("/api/health").status_code == 200


def test_invalid_ai_inputs_are_rejected(client):
    assert client.post("/api/ai/chat", json={"messages": [{"role": "assistant", "content": "结束"}]}).status_code == 422
    assert client.post("/api/ai/generate", json={"action": "extract_tasks", "content": "正文", "timeZone": "invalid-zone"}).status_code == 422


def test_total_request_deadline_is_enforced(client):
    class SlowService:
        settings = Settings(_env_file=None, ai_timeout_seconds=0.01)

        async def generate(self, request):
            await asyncio.sleep(1)

    app.dependency_overrides[get_text_ai_service] = lambda: SlowService()
    response = client.post("/api/ai/generate", json={"action": "improve_summary", "content": "摘要"})
    assert response.status_code == 504
