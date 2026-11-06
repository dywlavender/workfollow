import asyncio
from uuid import uuid4

from app.ai_runtime.server import Runtime


def test_scheduled_run_coexists_with_foreground_text_without_interrupting_it(tmp_path, monkeypatch):
    async def run():
        order = []
        runtime = Runtime(tmp_path, lambda _: None)
        started, finish, scheduled_started = asyncio.Event(), asyncio.Event(), asyncio.Event()

        async def dispatch(method, data):
            order.append(data["label"])
            if data["label"] == "foreground":
                started.set()
                await finish.wait()
            else:
                scheduled_started.set()
            return {"text": data["label"]}

        monkeypatch.setattr(runtime, "_dispatch", dispatch)
        foreground = asyncio.create_task(runtime.dispatch("text.generate", {"label": "foreground"}))
        await asyncio.wait_for(started.wait(), 1)
        scheduled = asyncio.create_task(runtime.dispatch("conversation.send", {
            "conversationID": str(uuid4()), "sessionDirectory": str(tmp_path / "sessions"),
            "label": "scheduled", "scheduledTask": {"id": str(uuid4())}, "progressChannel": "scheduled"}))
        await asyncio.wait_for(scheduled_started.wait(), 1)
        assert not foreground.done()
        assert order == ["foreground", "scheduled"]
        assert (await scheduled)["text"] == "scheduled"
        assert runtime.text_gate.locked()
        finish.set()
        assert (await foreground)["text"] == "foreground"
        assert runtime.background_text is None and not runtime.text_gate.locked()
        assert not runtime.conversation_tasks
        await runtime.close()

    asyncio.run(run())


def test_new_foreground_requests_do_not_interrupt_scheduled_conversation(tmp_path, monkeypatch):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        started, finish = asyncio.Event(), asyncio.Event()

        async def dispatch(method, data):
            if data.get("scheduledTask"):
                started.set()
                await finish.wait()
                return {"text": "定时执行完成"}
            return {"text": "主动提问的回复"}

        monkeypatch.setattr(runtime, "_dispatch", dispatch)
        options = {"conversationID": str(uuid4()), "sessionDirectory": str(tmp_path / "sessions")}
        scheduled = asyncio.create_task(runtime.dispatch("conversation.send", {
            **options, "scheduledTask": {"id": str(uuid4())}}))
        await asyncio.wait_for(started.wait(), 1)
        result = await runtime.dispatch("conversation.send", {
            **options, "conversationID": str(uuid4()), "message": "用户主动提问"})
        assert result["text"] == "主动提问的回复"
        assert (await runtime.dispatch("text.generate", {"prompt": "用户主动提问"}))["text"] == "主动提问的回复"
        assert not scheduled.done() and not scheduled.cancelling()
        assert list(runtime.conversation_tasks.values()) == [scheduled]
        finish.set()
        assert (await scheduled)["text"] == "定时执行完成"
        assert runtime.background_text is None and not runtime.text_gate.locked()
        assert not runtime.conversation_tasks
        await runtime.close()

    asyncio.run(run())


def test_scheduled_run_precedes_optional_daily_briefing(tmp_path, monkeypatch):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        started = asyncio.Event()

        async def dispatch(method, _):
            if method == "assistant.briefing":
                started.set()
                await asyncio.sleep(30)
            return {"text": "定时执行完成"}

        monkeypatch.setattr(runtime, "_dispatch", dispatch)
        briefing = asyncio.create_task(runtime.dispatch("assistant.briefing", {"facts": {}}))
        await started.wait()
        result = await runtime.dispatch("conversation.send", {
            "conversationID": str(uuid4()), "sessionDirectory": str(tmp_path / "sessions"),
            "scheduledTask": {"id": str(uuid4())}})
        assert briefing.cancelled()
        assert result["text"] == "定时执行完成"
        await runtime.close()

    asyncio.run(run())


def test_scheduled_run_keeps_its_metadata_and_scope_out_of_the_next_normal_chat(tmp_path, monkeypatch):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        options = []

        class Session:
            async def request(self, *_):
                return "虚构结果"

            async def close(self):
                pass

        async def session(data, **_):
            options.append(data)
            return Session()

        monkeypatch.setattr(runtime.pi, "session", session)
        task = {"id": str(uuid4()), "title": "虚构松竹周报", "scheduledFor": "2026-11-03T01:00:00Z"}
        await runtime.dispatch("conversation.send", {"conversationID": str(uuid4()),
            "sessionDirectory": str(tmp_path / "sessions"), "message": "生成虚构周报", "scheduledTask": task})
        await runtime.dispatch("conversation.send", {"conversationID": str(uuid4()),
            "sessionDirectory": str(tmp_path / "sessions"), "message": "正常讨论"})
        assert task["id"] in options[0]["systemPrompt"]
        assert task["scheduledFor"] in options[0]["systemPrompt"]
        assert task["id"] not in options[1]["systemPrompt"]
        assert options[0]["sessionFile"] != options[1]["sessionFile"]
        assert runtime.background_text is None
        await runtime.close()

    asyncio.run(run())
