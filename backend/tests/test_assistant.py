import asyncio
from uuid import uuid4

import pytest

from app.ai_runtime.assistant import memory_context
from app.ai_runtime.failures import EngineError
from app.ai_runtime.server import Runtime


def test_all_chat_surfaces_receive_current_memories_without_rebuilding_history(tmp_path, monkeypatch):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        cli, skill = tmp_path / "cli", tmp_path / "SKILL.md"
        cli.write_text("fixture"); skill.write_text("fixture")
        calls = []

        class Session:
            async def request(self, request, *_):
                calls[-1]["request"] = request
                return "虚构回复"

            async def close(self):
                pass

        async def session(options, **_):
            calls.append(options)
            return Session()

        monkeypatch.setattr(runtime.pi, "session", session)
        data = {"conversationID": str(uuid4()), "sessionDirectory": str(tmp_path / "sessions"),
                "workfollowCLI": str(cli), "workfollowSkill": str(skill), "message": "帮我规划",
                "memories": [{"id": str(uuid4()), "content": "虚构偏好：上午不安排会议"}]}
        for scene in ("chat", "note", "selection"):
            await runtime.dispatch("conversation.send", {**data, "scene": scene})
            assert "上午不安排会议" in calls[-1]["systemPrompt"]
            assert "memory" in calls[-1]["systemPrompt"]
            assert calls[-1]["request"]["type"] == "prompt"
            assert "history" not in calls[-1]["request"]
        await runtime.dispatch("conversation.send", {**data, "conversationID": str(uuid4()),
                                                     "memories": [{"content": "虚构偏好：下午不安排会议"}]})
        assert "下午不安排会议" in calls[-1]["systemPrompt"]
        assert "上午不安排会议" not in calls[-1]["systemPrompt"]
        await runtime.dispatch("conversation.send", {**data, "memories": []})
        assert "上午不安排会议" not in calls[-1]["systemPrompt"]
        assert "旧聊天中已修改或忘记" in calls[-1]["systemPrompt"]
        assert "[]" in calls[-1]["systemPrompt"]
        await runtime.close()

    asyncio.run(run())


def test_briefing_context_is_data_and_does_not_become_an_instruction(tmp_path, monkeypatch):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        requests = []

        class Session:
            async def request(self, request, *_):
                requests.append(request)
                return "已核对"

            async def close(self):
                pass

        async def session(*_, **__):
            return Session()

        monkeypatch.setattr(runtime.pi, "session", session)
        await runtime.dispatch("conversation.send", {
            "conversationID": str(uuid4()), "sessionDirectory": str(tmp_path / "sessions"),
            "message": "解释今日重点", "briefing": "虚构任务甲明天截止"})
        assert "生成时的快照，操作前读取最新业务记录" in requests[0]["message"]
        assert "虚构任务甲明天截止" in requests[0]["message"]
        await runtime.close()

    asyncio.run(run())


def test_daily_briefing_is_streamed_without_tools_or_a_persisted_pi_session(tmp_path, monkeypatch):
    async def run():
        events, calls = [], []
        runtime = Runtime(tmp_path, events.append)

        async def generate(options, prompt, on_event=None):
            command, _ = runtime.pi.command(options)
            calls.append((command, prompt))
            on_event({"kind": "text", "text": "虚构简报", "force": True})
            return "虚构简报"

        monkeypatch.setattr(runtime.pi, "generate", generate)
        result = await runtime.dispatch("assistant.briefing", {
            "facts": {"todayCount": 1, "tasks": [{"title": "虚构任务", "date": "2026-11-03 15:00"}]},
            "memories": [{"content": "会议提前十分钟提醒"}], "progressChannel": "briefing"})
        assert result["text"] == "虚构简报"
        command, prompt = calls[0]
        assert "--no-tools" in command and "--no-session" in command
        assert "--session" not in command
        assert "不自行创建、改期或完成任务" in prompt
        assert "会议提前十分钟提醒" in prompt
        assert "虚构任务" in prompt
        assert events[-1] == {"channel": "briefing", "event": {"kind": "text", "text": "虚构简报"}}
        await runtime.close()

    asyncio.run(run())


def test_explicit_user_request_cancels_background_briefing_and_releases_the_gate(tmp_path, monkeypatch):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        started = asyncio.Event()

        async def generate(options, prompt, on_event=None):
            if "今日工作简报" in prompt:
                started.set()
                await asyncio.sleep(30)
            return "用户的回复"

        monkeypatch.setattr(runtime.pi, "generate", generate)
        background = asyncio.create_task(runtime.dispatch("assistant.briefing", {"facts": {}}))
        await started.wait()
        reply = await runtime.dispatch("text.generate", {"prompt": "用户主动提问"})
        assert reply["text"] == "用户的回复"
        assert background.cancelled()
        assert runtime.background_text is None
        assert not runtime.text_gate.locked()
        await runtime.close()

    asyncio.run(run())


def test_briefing_cannot_interrupt_an_existing_user_request(tmp_path, monkeypatch):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        started, complete = asyncio.Event(), asyncio.Event()

        async def generate(*_, **__):
            started.set()
            await complete.wait()
            return "用户的回复"

        monkeypatch.setattr(runtime.pi, "generate", generate)
        foreground = asyncio.create_task(runtime.dispatch("text.generate", {"prompt": "处理我的问题"}))
        await started.wait()
        with pytest.raises(EngineError) as failure:
            await runtime.dispatch("assistant.briefing", {"facts": {}})
        assert failure.value.code == "busy"
        assert not foreground.done()
        complete.set()
        assert (await foreground)["text"] == "用户的回复"
        await runtime.close()

    asyncio.run(run())


@pytest.mark.parametrize("scheduled", [False, True])
def test_briefing_cannot_interrupt_an_active_conversation(tmp_path, monkeypatch, scheduled):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        started, finish = asyncio.Event(), asyncio.Event()
        calls = []
        async def dispatch(method, _):
            calls.append(method)
            started.set()
            await finish.wait()
            return {"text": "reply"}
        monkeypatch.setattr(runtime, "_dispatch", dispatch)
        options = {"conversationID": str(uuid4()), "sessionDirectory": str(tmp_path / "sessions"), "message": "question"}
        if scheduled:
            options["scheduledTask"] = {"id": str(uuid4())}
        conversation = asyncio.create_task(runtime.dispatch("conversation.send", options))
        await asyncio.wait_for(started.wait(), 1)
        with pytest.raises(EngineError) as failure:
            await runtime.dispatch("assistant.briefing", {})
        assert failure.value.code == "busy"
        assert not conversation.done() and not conversation.cancelling()
        assert calls == ["conversation.send"] and not runtime.text_gate.locked()
        finish.set()
        assert (await conversation)["text"] == "reply"
        await runtime.close()
    asyncio.run(run())


def test_memory_snapshot_rejects_non_text_content():
    with pytest.raises(EngineError):
        memory_context({"memories": [{"content": {"unexpected": "value"}}]})
