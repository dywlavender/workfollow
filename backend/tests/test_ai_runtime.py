import asyncio
import json
import os
from pathlib import Path
import signal
import sys
from functools import wraps

import pytest

from app.ai_runtime.pi_engine import PiEngine
from app.ai_runtime.prompts import minutes_prompt, summary_prompt, task_prompt
from app.ai_runtime.server import Runtime


def run_async(test):
    @wraps(test)
    def wrapped(*args, **kwargs):
        return asyncio.run(test(*args, **kwargs))
    return wrapped


@pytest.fixture
def pi_fixture(tmp_path):
    script = tmp_path / "pi-fixture"
    script.write_text('''#!/usr/bin/python3
import json, os, pathlib, sys, time
root = pathlib.Path(__file__).parent
(root / 'pid').write_text(str(os.getpid()))
dropped = False
seen = set()
for line in sys.stdin:
    value = json.loads(line)
    if value['type'] == 'get_available_models':
        print(json.dumps({'type':'response','id':value['id'],'command':'get_available_models','success':True,
            'data':{'models':[{'id':'voice','provider':'P'},{'id':'voice','provider':'P'},{'id':'text','provider':'P'}]}}), flush=True)
        continue
    prompt = value['message']
    if prompt.startswith('/wf-meeting-stream '):
        data = json.loads(prompt.split(' ',1)[1])
        if data['op'] == 'append':
            if not dropped:
                dropped = True
                continue
            if data['sequence'] not in seen:
                seen.add(data['sequence'])
                print(json.dumps({'message':'WF_MEETING_STREAM_EVENT '+json.dumps({'kind':'preview','itemID':'one','text':'草稿'})}), flush=True)
        if data['op'] == 'stop':
            print(json.dumps({'message':'WF_MEETING_STREAM_EVENT '+json.dumps({'kind':'final','itemID':'one','text':'最后一句'})}), flush=True)
        print(json.dumps({'message':'WF_MEETING_STREAM_ACK '+json.dumps({'id':data['id']})}), flush=True)
    elif prompt == 'WAIT':
        time.sleep(30)
    else:
        (root / 'prompt').write_text(prompt)
        print(json.dumps({'type':'message_end','message':{'role':'assistant','stopReason':'stop','content':[{'type':'text','text':'结果'}]}}), flush=True)
        print(json.dumps({'type':'agent_settled'}), flush=True)
''')
    script.chmod(0o755)
    return script


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def test_scenario_prompts_keep_facts_options_and_complete_source():
    summary = summary_prompt({"content": "已完成\n- 写周报\n尾部事实", "options": {"length": "简短", "style": "正式", "profession": "产品经理", "hint": "不用第一人称"}})
    for text in ("保留原文的日期范围", "不要新增或删除分组标题", "子任务推进不能描述成整个父任务已完成", "长度：简短", "语言风格：正式", "职业：产品经理", "尾部事实"):
        assert text in summary
    assert "本周成果" not in summary
    weekly = summary_prompt({"content": "事实", "options": {"weeklyStructure": True}})
    assert all(title in weekly for title in ("本周成果", "进展与调整", "本周复盘", "下周重点"))
    monthly = summary_prompt({"content": "10月任务事实", "options": {"weeklyStructure": True, "isWeeklyPeriod": False}})
    assert "本期成果、进展与调整、本期复盘、下一周期任务" in monthly
    task = task_prompt({"action": "extract_tasks", "content": "明天整理报价", "existingTitles": ["已存在"]})
    assert "quote 必须是输入中的连续原文" in task and "已存在" in task
    minutes = minutes_prompt({"lines": [{"speaker": "片段 1 · 暂定讲话人1", "text": "改成周五交付"}]})
    assert "后续发言推翻结论时修正" in minutes and "身份待确认" in minutes and "周五交付" in minutes


@run_async
async def test_runtime_uses_shared_model_catalog_and_central_prompt(pi_fixture, tmp_path):
    runtime = Runtime(tmp_path, lambda _: None)
    params = {"piExecutable": str(pi_fixture), "action": "extract_tasks", "content": "明天整理报价", "model": "P/text"}
    models = await runtime.dispatch("models", params)
    assert [row["id"] for row in models["models"]] == ["text", "voice"]
    result = await runtime.dispatch("text.tasks", params)
    assert result["text"] == "结果"
    assert "明天整理报价" in (tmp_path / "prompt").read_text()
    assert not alive(int((tmp_path / "pid").read_text()))
    result = await runtime.dispatch("text.summary", {"piExecutable": str(pi_fixture), "content": "摘要事实", "options": {"length": "简短", "style": "正式"}})
    assert result["text"] == "结果"
    assert "语言风格：正式" in (tmp_path / "prompt").read_text()
    await runtime.dispatch("text.tasks", {"piExecutable": str(pi_fixture), "action": "breakdown_task", "title": "发布新版", "content": ""})
    assert "发布新版" in (tmp_path / "prompt").read_text()


@run_async
async def test_cancelling_request_terminates_owned_pi_child(pi_fixture, tmp_path):
    messages = []
    runtime = Runtime(tmp_path, messages.append)
    runtime.accept({"id": "one", "method": "text.generate", "params": {"piExecutable": str(pi_fixture), "prompt": "WAIT"}})
    for _ in range(200):
        if (tmp_path / "pid").exists():
            break
        await asyncio.sleep(0.01)
    pid = int((tmp_path / "pid").read_text())
    assert alive(pid)
    task = runtime.pending["one"]
    runtime.accept({"method": "cancel", "params": {"requestID": "one"}})
    await task
    assert not alive(pid)
    assert messages[-1]["error"]["code"] == "cancelled"


@run_async
async def test_stream_retries_then_delivers_final_before_stop_response(pi_fixture, tmp_path):
    messages = []
    runtime = Runtime(tmp_path, messages.append)
    opened = await runtime.dispatch("stream.open", {"piExecutable": str(pi_fixture), "channel": "meeting-one"})
    stream_id = opened["streamID"]
    await runtime.dispatch("stream.command", {"streamID": stream_id, "op": "append", "sequence": 0, "audio": "AA==", "appendTimeout": 0.1})
    assert [m["event"]["kind"] for m in messages] == ["preview"]
    runtime.accept({"id": "stop", "method": "stream.command", "params": {"streamID": stream_id, "op": "stop"}})
    await runtime.pending["stop"]
    assert messages[-2]["event"]["text"] == "最后一句"
    assert messages[-1] == {"id": "stop", "result": {}}
    assert not runtime.pi.sessions
    assert not alive(int((tmp_path / "pid").read_text()))


@run_async
async def test_runtime_close_cancels_work_and_streams(pi_fixture, tmp_path):
    runtime = Runtime(tmp_path, lambda _: None)
    await runtime.dispatch("stream.open", {"piExecutable": str(pi_fixture), "channel": "one"})
    stream_pid = int((tmp_path / "pid").read_text())
    runtime.accept({"id": "waiting", "method": "text.generate", "params": {"piExecutable": str(pi_fixture), "prompt": "WAIT"}})
    await asyncio.sleep(0.1)
    request_pid = int((tmp_path / "pid").read_text())
    await runtime.close()
    assert not alive(stream_pid) and not alive(request_pid)


@run_async
async def test_stdio_protocol_eof_exits_without_web_backend(tmp_path):
    # Real entry point, but no model calls and no old web application imports.
    source = Path(__file__).resolve().parents[1]
    process = await asyncio.create_subprocess_exec(sys.executable, "-I", "-B", str(source / "ai_entry.py"), "--root", str(tmp_path),
        stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    assert json.loads(await process.stdout.readline()) == {"ready": 1}
    process.stdin.write(b'{"id":"check","method":"health"}\n')
    await process.stdin.drain()
    result = json.loads(await process.stdout.readline())
    assert result["result"]["engines"] == ["pi", "langchain"]
    process.stdin.close()
    await asyncio.wait_for(process.wait(), 5)
    assert process.returncode == 0


def test_legacy_pi_paths_use_local_node_and_local_pi(tmp_path, monkeypatch):
    from app.ai_runtime.node_runtime import NodeRuntime
    from app.ai_runtime import pi_engine
    node = tmp_path / "local-node/bin/node"
    node.parent.mkdir(parents=True)
    node.write_text("stub"); node.chmod(0o755)
    cli = tmp_path / "local-pi"
    cli.write_text("stub"); cli.chmod(0o755)
    monkeypatch.setattr(pi_engine, "resolve_node", lambda: NodeRuntime(node, "24.22.1"))
    monkeypatch.setattr(pi_engine, "resolve_pi", lambda override, selected_node: cli)
    command, env = PiEngine(tmp_path).command({"piExecutable": "/opt/homebrew/bin/pi", "model": "P/text"})
    assert env["PATH"].startswith(str(node.parent) + ":")
    assert command[0] == str(cli)
    assert "--no-tools" in command and "--no-context-files" in command
    assert command[-2:] == ["--model", "P/text"]


@run_async
async def test_fast_engine_exit_keeps_the_completed_result(tmp_path):
    script = tmp_path / "fast-pi"
    script.write_text('''#!/bin/zsh
read -r input
print -r -- '{"type":"message_end","message":{"role":"assistant","stopReason":"stop","content":[{"type":"text","text":"已完成结果"}]}}'
print -r -- '{"type":"agent_settled"}'
''')
    script.chmod(0o755)
    runtime = Runtime(tmp_path, lambda _: None)
    for _ in range(20):
        result = await runtime.dispatch("text.summary", {"piExecutable": str(script), "content": "事实"})
        assert result["text"] == "已完成结果"


@run_async
async def test_langchain_adapter_uses_compatible_api_and_closes_client(tmp_path, monkeypatch):
    import httpx
    from app.services import ai_service
    from app.ai_runtime import node_runtime
    monkeypatch.setattr(node_runtime, "node_candidates", lambda: [])
    original = ai_service.TextAIService
    requests, clients = [], []

    def response(request):
        requests.append(request)
        return httpx.Response(200, json={"id": "reply", "object": "chat.completion", "created": 1,
            "model": "compatible-model", "choices": [{"index": 0, "finish_reason": "stop",
            "message": {"role": "assistant", "content": "润色后的摘要"}}]})

    def factory(settings):
        service = original(settings, http_transport=httpx.MockTransport(response))
        clients.append(service)
        return service

    monkeypatch.setattr(ai_service, "TextAIService", factory)
    runtime = Runtime(tmp_path, lambda _: None)
    result = await runtime.dispatch("text.summary", {"engine": "langchain", "content": "原始事实",
        "options": {"length": "简短", "style": "正式"}, "configuration": {"ai_enabled": True,
        "ai_base_url": "https://compatible.example/v1", "ai_api_key": "test-only-key", "ai_model": "compatible-model"}})
    assert result["text"] == "润色后的摘要"
    assert str(requests[0].url) == "https://compatible.example/v1/chat/completions"
    assert json.loads(requests[0].content)["model"] == "compatible-model"
    assert all(service._http_async_client.is_closed and service._http_client.is_closed for service in clients)
