import asyncio
import json
from uuid import uuid4

import pytest

from app.ai_runtime.conversation import conversation_file
from app.ai_runtime.failures import EngineError
from app.ai_runtime.server import Runtime


def fixture_pi(tmp_path):
    script = tmp_path / "conversation-pi"
    script.write_text('''#!/usr/bin/python3
import json,pathlib,sys,time
args=sys.argv
file=pathlib.Path(args[args.index('--session')+1])
history=json.loads(file.read_text()) if file.exists() else []
for line in sys.stdin:
 request=json.loads(line)
 history.append(request['message'])
 file.write_text(json.dumps(history,ensure_ascii=False))
 if request['message']=='WAIT': time.sleep(30)
 text=' | '.join(history)
 print(json.dumps({'type':'message_update','assistantMessageEvent':{'type':'text_delta','delta':text}}),flush=True)
 print(json.dumps({'type':'message_end','message':{'role':'assistant','stopReason':'stop','content':[{'type':'text','text':text}]}}),flush=True)
 print(' {"type":"agent_settled"}',flush=True)
''')
    script.chmod(0o755)
    return script


def test_pi_resumes_conversation_and_keeps_sources_and_scenes_separate(tmp_path):
    async def run():
        events = []
        runtime = Runtime(tmp_path, events.append)
        conversation = str(uuid4())
        options = {"piExecutable": str(fixture_pi(tmp_path)), "conversationID": conversation,
                   "sessionDirectory": str(tmp_path / "sessions"), "progressChannel": "chat"}
        command, _ = runtime.pi.command({**options, "sessionFile": str(tmp_path / "a.jsonl")})
        assert "--session" in command and "--no-session" not in command
        assert "--no-tools" in command and "--no-context-files" in command
        await runtime.dispatch("conversation.send", {**options, "message": "虚构代号是蓝鲸42"})
        result = await runtime.dispatch("conversation.send", {**options, "message": "代号是什么？"})
        assert "蓝鲸42" in result["text"]
        assert events[-1]["event"]["kind"] == "text"
        selected = {**options, "scene": "selection", "context": "选中的虚构文字"}
        first = await runtime.dispatch("conversation.send", {**selected, "message": "请润色"})
        second = await runtime.dispatch("conversation.send", {**selected, "message": "再简短一点"})
        assert "选中的虚构文字" in first["text"] and "蓝鲸42" not in first["text"]
        history = json.loads((tmp_path / "sessions" / "selection" / (conversation + ".jsonl")).read_text())
        assert len(history) == 2 and history[1] == "再简短一点"
        assert "再简短一点" in second["text"]
        other = await runtime.dispatch("conversation.send", {**options, "conversationID": str(uuid4()), "message": "新的独立对话"})
        assert "蓝鲸42" not in other["text"]
        note = await runtime.dispatch("note.rewrite", {**options, "action": "polish", "title": "虚构笔记",
                                                       "content": "笔记事实", "instruction": "保留数字"})
        assert "笔记事实" in note["text"] and "蓝鲸42" not in note["text"]
        await runtime.close()
    asyncio.run(run())


def test_cancelled_conversation_releases_text_gate_and_can_continue(tmp_path):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        options = {"piExecutable": str(fixture_pi(tmp_path)), "conversationID": str(uuid4()),
                   "sessionDirectory": str(tmp_path / "sessions")}
        task = asyncio.create_task(runtime.dispatch("conversation.send", {**options, "message": "WAIT"}))
        for _ in range(200):
            if list((tmp_path / "sessions").glob("chat/*.jsonl")): break
            await asyncio.sleep(0.01)
        task.cancel()
        await asyncio.gather(task, return_exceptions=True)
        assert not runtime.text_gate.locked()
        result = await runtime.dispatch("conversation.send", {**options, "message": "继续"})
        assert result["text"].endswith("继续")
        await runtime.close()
    asyncio.run(run())


def test_delete_chat_removes_only_its_session_without_requiring_pi(tmp_path):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        conversation = str(uuid4())
        directory = tmp_path / "sessions"
        paths = [directory / "chat" / (conversation + ".jsonl"),
                 directory / "selection" / (conversation + ".jsonl"),
                 directory / "chat" / (str(uuid4()) + ".jsonl")]
        for path in paths:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("虚构会话")
        result = await runtime.dispatch("conversation.delete", {
            "conversationID": conversation, "sessionDirectory": str(directory)})
        assert result == {"deleted": True}
        assert not paths[0].exists()
        assert all(path.read_text() == "虚构会话" for path in paths[1:])
        await runtime.close()
    asyncio.run(run())


def test_delete_running_chat_waits_for_pi_exit_before_removing_session(tmp_path):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        options = {"piExecutable": str(fixture_pi(tmp_path)), "conversationID": str(uuid4()),
                   "sessionDirectory": str(tmp_path / "sessions")}
        file = tmp_path / "sessions" / "chat" / (options["conversationID"] + ".jsonl")
        task = asyncio.create_task(runtime.dispatch("conversation.send", {**options, "message": "WAIT"}))
        for _ in range(200):
            if file.exists(): break
            await asyncio.sleep(0.01)
        assert file.exists()
        # The native stop request can arrive immediately before deletion.
        task.cancel()
        await runtime.dispatch("conversation.delete", options)
        assert task.done() and task.cancelled()
        assert not file.exists() and not runtime.conversation_tasks
        assert not runtime.text_gate.locked()
        await runtime.close()
    asyncio.run(run())


def test_same_skill_and_cli_are_enabled_for_all_conversation_surfaces(tmp_path, monkeypatch):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        app = tmp_path / "WorkFollow Example.app"
        cli = app / "Contents/MacOS/workfollowctl"
        skill = app / "Contents/Resources/Skills/workfollow-cli/SKILL.md"
        cli.parent.mkdir(parents=True); skill.parent.mkdir(parents=True)
        cli.write_text("#!/bin/sh\nexit 0\n"); cli.chmod(0o755)
        skill.write_text("---\nname: workfollow-cli\ndescription: Query and edit tasks and notes.\n---\nUse the CLI.")
        calls = []
        class Session:
            async def request(self, *args): return "已处理"
            async def close(self): pass
        async def session(options, **kwargs):
            command, env = runtime.pi.command(options)
            calls.append((command, env, options))
            return Session()
        monkeypatch.setattr(runtime.pi, "session", session)
        options = {"conversationID": str(uuid4()), "sessionDirectory": str(tmp_path / "sessions"),
                   "workfollowCLI": str(cli), "workfollowSkill": str(skill), "workfollowApp": str(app),
                   "localTime": "2026-10-29 09:00", "timeZone": "Asia/Shanghai", "message": "查询待办"}
        await runtime.dispatch("conversation.send", options)
        command, env, _ = calls[-1]
        assert command[command.index("--tools") + 1] == "read,bash" and "--no-tools" not in command
        assert command[command.index("--skill") + 1] == str(skill)
        assert "--no-skills" not in command
        assert env["WORKFOLLOW_CLI"] == str(cli) and env["WORKFOLLOW_APP"] == str(app)
        assert env["PATH"].split(":")[0] == str(cli.parent)
        for scene in ("selection", "note"):
            await runtime.dispatch("conversation.send", {**options, "scene": scene, "context": "选中的正文"})
            command, env, _ = calls[-1]
            assert command[command.index("--tools") + 1] == "read,bash"
            assert command[command.index("--skill") + 1] == str(skill)
            assert "--no-skills" not in command and "--no-tools" not in command
            assert env["WORKFOLLOW_CONVERSATION_ID"] == options["conversationID"]
        await runtime.close()
    asyncio.run(run())


def test_tool_events_keep_waiting_for_final_answer_and_hide_raw_tool_output():
    from app.ai_runtime.pi_engine import PiSession
    async def run():
        class Process:
            stdout = asyncio.StreamReader()
        updates = []
        session = PiSession(updates.append); session.mode = "text"; session.process = Process()
        session.pending = asyncio.get_running_loop().create_future()
        reader = asyncio.create_task(session.read_events())
        def feed(value): session.process.stdout.feed_data((json.dumps(value) + "\n").encode())
        feed({"type": "tool_execution_start", "toolName": "bash", "args": {"command": "raw-command"}})
        feed({"type": "tool_execution_end", "toolName": "bash", "result": {"content": [{"text": "raw-note-body"}]}})
        await asyncio.sleep(0.01)
        assert not session.pending.done()
        feed({"type": "message_end", "message": {"role": "assistant", "stopReason": "stop", "content": [{"type": "text", "text": "已创建测试待办"}]}})
        feed({"type": "agent_settled"}); session.process.stdout.feed_eof()
        await reader
        assert await session.pending == "已创建测试待办"
        assert any(update["kind"] == "status" for update in updates)
        assert "raw-note-body" not in json.dumps(updates) and "raw-command" not in json.dumps(updates)
    asyncio.run(run())


def test_presets_are_per_turn_and_note_chat_keeps_same_pi_session(tmp_path, monkeypatch):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        calls = []
        class Session:
            async def request(self, payload, *_):
                calls.append(payload)
                return "自然回复"
            async def close(self): pass
        sessions = []
        async def session(options, **kwargs):
            sessions.append(options)
            return Session()
        monkeypatch.setattr(runtime.pi, "session", session)
        options = {"conversationID": str(uuid4()), "sessionDirectory": str(tmp_path / "sessions"),
                   "scene": "note", "source": {"id": str(uuid4()), "kind": "note", "title": "虚构方案", "content": "周五提交报价。"}}
        await runtime.dispatch("conversation.send", {**options, "preset": "extract", "message": "提取待办"})
        await runtime.dispatch("conversation.send", {**options, "message": "你觉得这个方案有什么问题？"})
        assert "本轮快捷提问" in calls[0]["message"] and "周五提交报价。" in calls[0]["message"]
        assert "本轮快捷提问" not in calls[1]["message"] and "周五提交报价。" not in calls[1]["message"]
        assert "你觉得这个方案有什么问题" in calls[1]["message"]
        assert sessions[0]["sessionFile"] == sessions[1]["sessionFile"]
        assert "对话始终开放" in sessions[1]["systemPrompt"]
        assert "workfollow-tasks" in sessions[1]["systemPrompt"]
        await runtime.close()
    asyncio.run(run())


@pytest.mark.parametrize("second_scene", ["chat", "selection", "note"])
def test_independent_sessions_run_concurrently_and_cancel_only_the_selected_request(tmp_path, monkeypatch, second_scene):
    async def run():
        events = []
        runtime = Runtime(tmp_path, events.append)
        started = {name: asyncio.Event() for name in ("first", "second")}
        finish = asyncio.Event()
        closed, files = [], []

        class Session:
            def __init__(self, options, on_event):
                self.name = options["label"]
                self.on_event = on_event
                files.append(options["sessionFile"])

            async def request(self, *_):
                self.on_event({"kind": "text", "text": self.name, "force": True})
                started[self.name].set()
                await finish.wait()
                return self.name

            async def close(self):
                closed.append(self.name)

        async def session(options, on_event):
            return Session(options, on_event)

        monkeypatch.setattr(runtime.pi, "session", session)
        options = {"conversationID": str(uuid4()), "sessionDirectory": str(tmp_path / "sessions")}
        # Identical UUIDs in different scenes are different persisted sessions.
        second_options = {**options, "scene": second_scene}
        if second_scene == "chat":
            second_options["conversationID"] = str(uuid4())
        runtime.accept({"id": "first", "method": "conversation.send", "params": {
            **options, "label": "first", "message": "first", "progressChannel": "first"}})
        runtime.accept({"id": "second", "method": "conversation.send", "params": {
            **second_options, "label": "second", "message": "second", "progressChannel": "second"}})
        first, second = runtime.pending["first"], runtime.pending["second"]
        await asyncio.wait_for(asyncio.gather(*(event.wait() for event in started.values())), 1)
        assert len(runtime.conversation_tasks) == 2 and len(set(files)) == 2
        assert not runtime.text_gate.locked()
        assert {event["channel"] for event in events} == {"first", "second"}
        runtime.accept({"method": "cancel", "params": {"requestID": "first"}})
        await asyncio.wait_for(first, 1)
        assert closed == ["first"]
        assert not second.done() and not second.cancelling()
        assert list(runtime.conversation_tasks.values()) == [second]
        assert events[-1] == {"id": "first", "error": {"code": "cancelled", "message": "操作已取消。"}}
        finish.set()
        await asyncio.wait_for(second, 1)
        assert events[-1] == {"id": "second", "result": {"text": "second"}}
        assert closed == ["first", "second"]
        assert not runtime.conversation_tasks and not runtime.pending
        await runtime.close()
    asyncio.run(run())


def test_same_session_is_busy_through_pi_cleanup_and_can_continue_afterwards(tmp_path, monkeypatch):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        started, closing, finish_cleanup = asyncio.Event(), asyncio.Event(), asyncio.Event()
        calls = []

        class Session:
            async def request(self, *_):
                started.set()
                await asyncio.Event().wait()

            async def close(self):
                closing.set()
                await finish_cleanup.wait()

        async def session(options, **_):
            calls.append(options)
            return Session()

        monkeypatch.setattr(runtime.pi, "session", session)
        options = {"conversationID": str(uuid4()), "sessionDirectory": str(tmp_path / "sessions"), "message": "first"}
        file = conversation_file(options).resolve()
        first = asyncio.create_task(runtime.dispatch("conversation.send", options))
        await asyncio.wait_for(started.wait(), 1)
        duplicate = {**options, "conversationID": options["conversationID"].upper(), "scheduledTask": {"id": str(uuid4())}}
        for cleaning in (False, True):
            if cleaning:
                first.cancel()
                await asyncio.wait_for(closing.wait(), 1)
            with pytest.raises(EngineError) as failure:
                await runtime.dispatch("conversation.send", duplicate)
            assert failure.value.code == "busy"
            assert runtime.conversation_tasks[file] is first
            assert len(calls) == 1
        finish_cleanup.set()
        with pytest.raises(asyncio.CancelledError):
            await asyncio.wait_for(first, 1)
        assert not runtime.conversation_tasks

        async def request(*_):
            return "继续"

        monkeypatch.setattr(Session, "request", request)
        assert (await runtime.dispatch("conversation.send", options))["text"] == "继续"
        assert len(calls) == 2 and not runtime.conversation_tasks
        await runtime.close()
    asyncio.run(run())


@pytest.mark.parametrize("cancel_deletion", [False, True])
def test_delete_reserves_session_until_request_cleanup_and_blocks_resurrection(tmp_path, monkeypatch, cancel_deletion):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        started, closing, finish_cleanup = asyncio.Event(), asyncio.Event(), asyncio.Event()
        options = {"conversationID": str(uuid4()), "sessionDirectory": str(tmp_path / "sessions"), "message": "WAIT"}
        file = conversation_file(options).resolve()
        attachments = file.parent.parent / "attachments" / "chat" / file.stem
        attachments.mkdir(parents=True)
        (attachments / "fixture.txt").write_text("资料")
        calls = []

        class Session:
            async def request(self, *_):
                file.write_text("会话")
                started.set()
                await asyncio.Event().wait()

            async def close(self):
                closing.set()
                await finish_cleanup.wait()
                # Pi may persist its final state while cancellation unwinds.
                file.write_text("清理时写回")

        async def session(*_, **__):
            calls.append("session")
            return Session()

        monkeypatch.setattr(runtime.pi, "session", session)
        request = asyncio.create_task(runtime.dispatch("conversation.send", options))
        await asyncio.wait_for(started.wait(), 1)
        deletion = asyncio.create_task(runtime.dispatch("conversation.delete", options))
        await asyncio.wait_for(closing.wait(), 1)
        assert not deletion.done() and file.exists() and attachments.exists()
        assert runtime.conversation_tasks[file] is request
        assert runtime.conversation_deletions[file] is deletion
        if cancel_deletion:
            deletion.cancel()
            await asyncio.sleep(0)
            assert not deletion.done()
            assert request.cancelling() == 1
        with pytest.raises(EngineError) as duplicate:
            await runtime.dispatch("conversation.delete", options)
        assert duplicate.value.code == "busy"
        with pytest.raises(EngineError) as resurrection:
            await runtime.dispatch("conversation.send", options)
        assert resurrection.value.code == "busy" and calls == ["session"]
        assert runtime.conversation_deletions[file] is deletion
        finish_cleanup.set()
        if cancel_deletion:
            with pytest.raises(asyncio.CancelledError):
                await asyncio.wait_for(deletion, 1)
        else:
            assert await asyncio.wait_for(deletion, 1) == {"deleted": True}
        assert request.cancelled()
        assert not file.exists() and not attachments.exists()
        assert not runtime.conversation_tasks and not runtime.conversation_deletions
        # A later explicit send can reuse the ID only after deletion finishes.
        async def request_done(*_):
            return "新会话"
        monkeypatch.setattr(Session, "request", request_done)
        assert (await runtime.dispatch("conversation.send", options))["text"] == "新会话"
        await runtime.close()
    asyncio.run(run())


def test_delete_finds_session_registered_before_briefing_cleanup(tmp_path, monkeypatch):
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

        original_dispatch = runtime._dispatch
        monkeypatch.setattr(runtime, "_dispatch", dispatch)
        briefing = asyncio.create_task(runtime.dispatch("assistant.briefing", {}))
        await asyncio.wait_for(started.wait(), 1)
        options = {"conversationID": str(uuid4()), "sessionDirectory": str(tmp_path / "sessions"), "message": "send"}
        file = conversation_file(options).resolve()
        file.parent.mkdir(parents=True)
        file.write_text("existing")
        request = asyncio.create_task(runtime.dispatch("conversation.send", options))
        await asyncio.wait_for(closing.wait(), 1)
        assert runtime.conversation_tasks[file] is request
        assert calls == ["assistant.briefing"]
        with pytest.raises(EngineError) as duplicate:
            await runtime.dispatch("conversation.send", options)
        assert duplicate.value.code == "busy"
        # Restore actual delete handling; conversation work must never begin.
        monkeypatch.setattr(runtime, "_dispatch", original_dispatch)
        assert await asyncio.wait_for(runtime.dispatch("conversation.delete", options), 1) == {"deleted": True}
        assert request.cancelled() and not file.exists()
        assert calls == ["assistant.briefing"] and not runtime.conversation_tasks
        assert not briefing.done() and briefing.cancelling() == 1
        finish_cleanup.set()
        with pytest.raises(asyncio.CancelledError):
            await asyncio.wait_for(briefing, 1)
        assert not runtime.text_gate.locked()
        await runtime.close()
    asyncio.run(run())


def test_conversation_timeout_closes_pi_and_releases_session(tmp_path, monkeypatch):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        sessions = []
        original = runtime.pi.session
        async def session(*args, **kwargs):
            result = await original(*args, **kwargs)
            sessions.append(result)
            return result
        monkeypatch.setattr(runtime.pi, "session", session)
        options = {"piExecutable": str(fixture_pi(tmp_path)), "conversationID": str(uuid4()),
                   "sessionDirectory": str(tmp_path / "sessions"), "timeoutSeconds": 0.1}
        with pytest.raises(TimeoutError):
            await runtime.dispatch("conversation.send", {**options, "message": "WAIT"})
        assert sessions[0].process.returncode is not None and sessions[0].reader.done()
        assert not runtime.conversation_tasks
        assert (await runtime.dispatch("conversation.send", {**options, "message": "继续", "timeoutSeconds": 2}))["text"].endswith("继续")
        assert all(session.process.returncode is not None and session.reader.done() for session in sessions)
        await runtime.close()
    asyncio.run(run())


def test_runtime_close_waits_for_delete_and_does_not_cancel_request_cleanup_twice(tmp_path, monkeypatch):
    async def run():
        events = []
        runtime = Runtime(tmp_path, events.append)
        started, closing, finish_cleanup = asyncio.Event(), asyncio.Event(), asyncio.Event()
        options = {"conversationID": str(uuid4()), "sessionDirectory": str(tmp_path / "sessions"), "message": "WAIT"}
        file = conversation_file(options).resolve()
        class Session:
            async def request(self, *_):
                file.write_text("会话")
                started.set()
                await asyncio.Event().wait()
            async def close(self):
                closing.set()
                await finish_cleanup.wait()
                file.write_text("清理时写回")
        async def session(*_, **__):
            return Session()
        monkeypatch.setattr(runtime.pi, "session", session)
        runtime.accept({"id": "send", "method": "conversation.send", "params": options})
        request = runtime.pending["send"]
        await asyncio.wait_for(started.wait(), 1)
        runtime.accept({"id": "delete", "method": "conversation.delete", "params": options})
        deletion = runtime.pending["delete"]
        await asyncio.wait_for(closing.wait(), 1)
        runtime.accept({"method": "cancel", "params": {"requestID": "send"}})
        shutdown = asyncio.create_task(runtime.close())
        await asyncio.sleep(0)
        assert request.cancelling() == 1 and not request.done()
        assert not shutdown.done() and not deletion.done()
        assert runtime.conversation_deletions[file] is deletion and file.exists()
        finish_cleanup.set()
        await asyncio.wait_for(shutdown, 1)
        assert not file.exists()
        assert not runtime.pending and not runtime.conversation_tasks and not runtime.conversation_deletions
        assert {event["id"] for event in events if event.get("error", {}).get("code") == "cancelled"} == {"send", "delete"}
    asyncio.run(run())


def test_delete_running_session_leaves_other_pi_child_running(tmp_path, monkeypatch):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        sessions = {}
        original = runtime.pi.session
        async def session(options, **kwargs):
            result = await original(options, **kwargs)
            sessions[options["sessionFile"]] = result
            return result
        monkeypatch.setattr(runtime.pi, "session", session)
        options = {"piExecutable": str(fixture_pi(tmp_path)), "conversationID": str(uuid4()),
                   "sessionDirectory": str(tmp_path / "sessions"), "message": "WAIT"}
        other_options = {**options, "conversationID": str(uuid4())}
        first = asyncio.create_task(runtime.dispatch("conversation.send", options))
        second = asyncio.create_task(runtime.dispatch("conversation.send", other_options))
        files = [conversation_file(data) for data in (options, other_options)]
        for _ in range(200):
            if all(file.exists() for file in files):
                break
            await asyncio.sleep(0.01)
        assert all(file.exists() for file in files) and len(sessions) == 2
        assert not runtime.text_gate.locked()
        assert await runtime.dispatch("conversation.delete", options) == {"deleted": True}
        assert first.cancelled() and not second.done() and not second.cancelling()
        assert not files[0].exists() and files[1].exists()
        first_session, second_session = (sessions[str(file)] for file in files)
        assert first_session.process.returncode is not None and first_session.reader.done()
        assert second_session.process.returncode is None and not second_session.reader.done()
        second.cancel()
        with pytest.raises(asyncio.CancelledError):
            await second
        assert second_session.process.returncode is not None and second_session.reader.done()
        assert not runtime.conversation_tasks
        await runtime.close()
    asyncio.run(run())


def test_translate_preset_is_accepted_and_appends_instruction(tmp_path, monkeypatch):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        calls = []
        class Session:
            async def request(self, payload, *_):
                calls.append(payload)
                return "自然回复"
            async def close(self): pass
        async def session(options, **kwargs):
            return Session()
        monkeypatch.setattr(runtime.pi, "session", session)
        options = {"conversationID": str(uuid4()), "sessionDirectory": str(tmp_path / "sessions"),
                   "scene": "selection", "source": {"kind": "selection", "title": "选中文字", "content": "核对成本"}}
        await runtime.dispatch("conversation.send", {**options, "preset": "translate", "message": "请翻译选中内容"})
        from app.ai_runtime.conversation import PRESETS as _PRESETS
        assert _PRESETS["translate"] in calls[0]["message"]
        assert "本轮快捷提问" in calls[0]["message"]
        await runtime.close()
    asyncio.run(run())
