import asyncio
import json
from pathlib import Path
import subprocess
import shutil
from uuid import uuid4

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


@pytest.mark.parametrize("limited_method,next_method", [
    ("conversation.send", "conversation.send"),
    ("conversation.send", "text.generate"),
    ("text.generate", "conversation.send"),
])
def test_conversation_and_serial_text_share_model_cooldowns(tmp_path, monkeypatch, limited_method, next_method):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        calls = []
        now = [100.0]
        monkeypatch.setattr("app.ai_runtime.server.time.monotonic", lambda: now[0])

        async def dispatch(method, data):
            calls.append((method, data["model"]))
            if len(calls) == 1:
                raise model_failure("token rate limit", retry_after=10)
            return {"text": "恢复"}

        monkeypatch.setattr(runtime, "_dispatch", dispatch)
        options = {"model": "model-a", "conversationID": str(uuid4()),
                   "sessionDirectory": str(tmp_path / "sessions"), "message": "question", "prompt": "question"}
        with pytest.raises(EngineError) as first:
            await runtime.dispatch(limited_method, options)
        assert first.value.code == "rate_limited"
        assert not runtime.conversation_tasks and not runtime.text_gate.locked()
        next_options = {**options, "conversationID": str(uuid4())}
        with pytest.raises(EngineError) as cooldown:
            await runtime.dispatch(next_method, next_options)
        assert cooldown.value.code == "rate_limited" and cooldown.value.retry_after == 10
        assert calls == [(limited_method, "model-a")]
        assert not runtime.conversation_tasks and not runtime.text_gate.locked()
        assert (await runtime.dispatch(next_method, {**next_options, "model": "model-b"}))["text"] == "恢复"
        now[0] += 11
        assert (await runtime.dispatch(next_method, next_options))["text"] == "恢复"
        assert calls == [(limited_method, "model-a"), (next_method, "model-b"), (next_method, "model-a")]
        await runtime.close()
        assert not runtime.cooldowns
    asyncio.run(run())


def test_conversation_rechecks_cooldown_after_awaiting_briefing_cleanup(tmp_path, monkeypatch):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        started, closing, finish_cleanup = asyncio.Event(), asyncio.Event(), asyncio.Event()
        calls = []

        async def dispatch(method, _):
            calls.append(method)
            if method == "assistant.briefing":
                started.set()
                try:
                    await asyncio.Event().wait()
                finally:
                    closing.set()
                    await finish_cleanup.wait()
            return {"text": "reply"}

        monkeypatch.setattr(runtime, "_dispatch", dispatch)
        options = {"model": "model-a", "conversationID": str(uuid4()),
                   "sessionDirectory": str(tmp_path / "sessions"), "message": "question"}
        briefing = asyncio.create_task(runtime.dispatch("assistant.briefing", options))
        await asyncio.wait_for(started.wait(), 1)
        request = asyncio.create_task(runtime.dispatch("conversation.send", options))
        await asyncio.wait_for(closing.wait(), 1)
        runtime.cooldowns[runtime.model_key(options)] = asyncio.get_running_loop().time() + 10
        finish_cleanup.set()
        with pytest.raises(EngineError) as failure:
            await asyncio.wait_for(request, 1)
        assert failure.value.code == "rate_limited"
        assert calls == ["assistant.briefing"] and briefing.cancelled()
        assert not runtime.conversation_tasks and not runtime.text_gate.locked()
        await runtime.close()
    asyncio.run(run())
