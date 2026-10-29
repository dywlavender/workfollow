import asyncio
import json
from uuid import uuid4

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


def test_app_skill_and_cli_are_enabled_only_for_standalone_chat(tmp_path, monkeypatch):
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
        assert env["WORKFOLLOW_CLI"] == str(cli) and env["WORKFOLLOW_APP"] == str(app)
        assert env["PATH"].split(":")[0] == str(cli.parent)
        for scene in ("selection", "note"):
            await runtime.dispatch("conversation.send", {**options, "scene": scene, "context": "选中的正文"})
            command, env, _ = calls[-1]
            assert "--no-tools" in command and "--skill" not in command
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
