import asyncio
import json

import pytest

from app.ai_runtime.pi_engine import PiSession
from app.ai_runtime.server import Runtime
from app.ai_runtime.text_stream import TextStream


@pytest.mark.parametrize("method,extra", [("text.tasks", {"action": "extract_tasks"}), ("note.rewrite", {"action": "polish"})])
def test_full_original_uses_one_agent_prompt_without_application_chunks_or_token_caps(tmp_path, monkeypatch, method, extra):
    async def run():
        events, calls = [], []
        runtime = Runtime(tmp_path, events.append)
        source = "保留本段所有细节。\n" * 1000 + "末尾：下周核对合同。"
        async def generate(options, prompt, **kwargs):
            calls.append((options, prompt))
            kwargs["on_event"]({"kind": "text", "text": '{"tasks":[{"title":"核对合同"' if method == "text.tasks" else "正在生成正文", "force": True})
            return '{"tasks":[]}' if method == "text.tasks" else "完整正文"
        monkeypatch.setattr(runtime.pi, "generate", generate)
        await runtime.dispatch(method, {**extra, "title": "虚构笔记", "content": source,
                                        "instruction": "只保留合同相关", "progressChannel": "preview"})
        assert len(calls) == 1
        assert "textBudget" not in calls[0][0] and source in json.loads(calls[0][1].split("输入 JSON：", 1)[1])["content"]
        assert "只保留合同相关" in calls[0][1]
        assert events[0]["event"]["text"] in ("核对合同", "正在生成正文")
        await runtime.close()
    asyncio.run(run())


def test_agent_end_does_not_finish_before_pi_compaction_and_retry_settle():
    async def run():
        class Process:
            stdout = asyncio.StreamReader()
        updates = []
        session = PiSession(updates.append); session.mode = "text"; session.process = Process()
        session.pending = asyncio.get_running_loop().create_future()
        reader = asyncio.create_task(session.read_events())
        def feed(event): session.process.stdout.feed_data((json.dumps(event) + "\n").encode())
        feed({"type": "message_end", "message": {"role": "assistant", "stopReason": "error", "errorMessage": "context length", "content": []}})
        feed({"type": "agent_end"})
        await asyncio.sleep(0.01)
        assert not session.pending.done()
        feed({"type": "auto_compaction_start"})
        feed({"type": "auto_compaction_end"})
        feed({"type": "message_start", "message": {"role": "assistant"}})
        feed({"type": "message_update", "assistantMessageEvent": {"type": "thinking_delta", "delta": "private reasoning"}})
        feed({"type": "message_update", "assistantMessageEvent": {"type": "text_delta", "delta": "完整结果"}})
        feed({"type": "message_end", "message": {"role": "assistant", "stopReason": "stop", "content": [{"type": "text", "text": "完整结果"}]}})
        feed({"type": "agent_settled"}); session.process.stdout.feed_eof()
        await reader
        assert await session.pending == "完整结果"
        assert any(update.get("message") == "正在整理对话上下文…" for update in updates)
        assert "private reasoning" not in json.dumps(updates)
    asyncio.run(run())


def test_preview_projects_partial_json_without_exposing_json_or_citations():
    events = []
    stream = TextStream("knowledge.ask", "answer", events.append)
    stream({"kind": "text", "text": '{"paragraphs":[{"text":"周五验收","citations":[{"source":"S1"', "force": True})
    assert events[-1]["event"] == {"kind": "text", "text": "周五验收"}


def test_active_stream_and_agent_compaction_are_not_cut_off_by_original_wait_timeout(tmp_path):
    async def run():
        script = tmp_path / "pi-stream"
        script.write_text('''#!/usr/bin/python3
import json,sys,time
sys.stdin.readline()
def send(event): print(json.dumps(event),flush=True)
send({'type':'auto_compaction_start'})
time.sleep(1.1)
send({'type':'auto_compaction_end'})
send({'type':'message_start','message':{'role':'assistant'}})
for i in range(6):
 send({'type':'message_update','assistantMessageEvent':{'type':'text_delta','delta':'正文'}})
 time.sleep(0.2)
send({'type':'message_end','message':{'role':'assistant','stopReason':'stop','content':[{'type':'text','text':'完整正文'}]}})
send({'type':'agent_end'})
send({'type':'agent_settled'})
''')
        script.chmod(0o755)
        runtime = Runtime(tmp_path, lambda _: None)
        result = await runtime.dispatch("text.generate", {"piExecutable": str(script), "prompt": "虚构输入", "timeoutSeconds": 1})
        assert result["text"] == "完整正文"
        await runtime.close()
    asyncio.run(run())
