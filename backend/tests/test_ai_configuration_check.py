import asyncio
from types import SimpleNamespace

from app.ai_runtime import diagnostics
from app.ai_runtime.failures import EngineError


def test_configuration_check_lists_prerequisites_models_and_skills_without_prompt(tmp_path, monkeypatch):
    executable = tmp_path / "version-fixture"
    executable.write_text("#!/bin/sh\nprintf 'fixture-version\\n'\n"); executable.chmod(0o755)
    monkeypatch.setattr(diagnostics, "resolve_node", lambda: SimpleNamespace(executable=executable))
    calls = []
    class Session:
        async def request(self, payload, mode, timeout):
            assert payload["type"] == "get_commands" and mode == "commands"
            calls.append("commands")
            return {"commands": [{"name": "skill:workfollow-cli", "source": "skill"},
                                  {"name": "skill:fictional-user-skill", "source": "skill"}]}
        async def close(self): calls.append("closed")
    class Pi:
        def command(self, data): return [str(executable)], {}
        async def models(self, data): return [{"id": "fixture", "provider": "example"}]
        async def session(self, data):
            assert data["appTools"] is True
            return Session()
    result = asyncio.run(diagnostics.configuration_check(Pi(), {"model": "example/fixture"}))
    assert len(result["checks"]) == 4 and all(check["ok"] for check in result["checks"])
    assert "fictional-user-skill" in result["checks"][-1]["message"]
    assert calls == ["commands", "closed"]


def test_configuration_check_reports_missing_pi_without_calling_model(tmp_path, monkeypatch):
    executable = tmp_path / "node"
    executable.write_text("#!/bin/sh\nprintf 'v24\\n'\n"); executable.chmod(0o755)
    monkeypatch.setattr(diagnostics, "resolve_node", lambda: SimpleNamespace(executable=executable))
    class Pi:
        def command(self, data): raise EngineError("未找到本机 Pi。", "pi_unavailable")
    result = asyncio.run(diagnostics.configuration_check(Pi(), {}))
    assert result["checks"][0]["ok"]
    assert result["checks"][1] == {"name": "Pi", "ok": False, "message": "未找到本机 Pi。"}
