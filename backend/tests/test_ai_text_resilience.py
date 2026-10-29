import asyncio
import json
from pathlib import Path
import subprocess
import shutil

import pytest

from app.ai_runtime.failures import EngineError, model_failure
from app.ai_runtime.pi_engine import PiSession
from app.ai_runtime.server import Runtime
from app.ai_runtime.workflows import NoteRewriteRequest


@pytest.mark.parametrize("message,status,reason,expected", [
    ("token rate limit exceeded", 429, "", "rate_limited"),
    ("unauthorized client detected", 401, "", "client_unauthorized"),
    ("invalid api key", 401, "", "authentication_failed"),
    ("insufficient_quota", 429, "", "quota_exceeded"),
    ("", None, "length", "output_limit"),
    ("request timed out", None, "", "timeout"),
])
def test_model_failures_are_actionable_without_forwarding_raw_details(message, status, reason, expected):
    failure = model_failure(message + " hidden-test-credential", status=status, reason=reason, retry_after="12")
    assert failure.code == expected
    assert "hidden-test-credential" not in str(failure)
    if expected == "rate_limited":
        assert failure.retry_after == 12


def test_text_gate_leaves_audio_independent_and_releases_on_cancel(tmp_path, monkeypatch):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        started = asyncio.Event()
        async def generate(*args, **kwargs):
            started.set()
            await asyncio.Event().wait()
        monkeypatch.setattr(runtime.pi, "generate", generate)
        async def command(data):
            return None
        monkeypatch.setattr(runtime.pi, "stream_command", command)
        first = asyncio.create_task(runtime.dispatch("text.generate", {"prompt": "WAIT"}))
        await started.wait()
        assert await runtime.dispatch("stream.command", {"op": "append"}) == {}
        with pytest.raises(EngineError) as busy:
            await runtime.dispatch("text.generate", {"prompt": "duplicate"})
        assert busy.value.code == "busy"
        first.cancel()
        with pytest.raises(asyncio.CancelledError):
            await first
        assert not runtime.text_gate.locked()
        await runtime.close()
    asyncio.run(run())


def test_rate_limit_cooldown_prevents_duplicate_provider_calls(tmp_path, monkeypatch):
    async def run():
        messages, calls = [], []
        runtime = Runtime(tmp_path, messages.append)
        async def generate(options, prompt, **kwargs):
            calls.append(options.get("model"))
            if len(calls) == 1:
                raise model_failure("token rate limit", retry_after=10)
            return "恢复"
        monkeypatch.setattr(runtime.pi, "generate", generate)
        params = {"prompt": "fictional", "model": "model-a"}
        await runtime.handle({"id": "first", "method": "text.generate", "params": params})
        await runtime.handle({"id": "second", "method": "text.generate", "params": params})
        assert len(calls) == 1
        assert all(message["error"]["code"] == "rate_limited" for message in messages)
        assert 0 < messages[-1]["error"]["retryAfterSeconds"] <= 10
        assert (await runtime.dispatch("text.generate", {**params, "model": "model-b"}))["text"] == "恢复"
        await runtime.close()
    asyncio.run(run())
