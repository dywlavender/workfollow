#!/usr/bin/env python3
"""Exercise a shipped AI backend with an empty HOME and locally installed Node and Pi.

The Pi extension and compatible HTTP server below are synthetic: no paid model
is called and no personal configuration, recording or task data is opened.
"""
import argparse
import asyncio
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile
import threading
import uuid


async def check(app, node=None, pi=None):
    root = app / "Contents/Resources/AIBackend"
    if platform.machine() != "arm64":
        raise RuntimeError("请在 Apple 芯片 Mac 上运行安装包测试。")
    arch = "arm64"
    manifest = json.loads((root / "runtime.json").read_text())
    assert manifest["architectures"] == [arch]
    assert manifest["node"] == "external"
    assert manifest["pi"] == "external"
    assert not (root / "pi").exists()
    assert not (root / "runtime/x86_64").exists()
    assert not any((root / "runtime").glob("*/node"))
    python = root / "runtime" / arch / "python/bin/python3"
    assert subprocess.check_output(["/usr/bin/lipo", "-archs", str(python)], text=True).split() == [arch]
    with tempfile.TemporaryDirectory(prefix="workfollow-ai-isolated-") as folder:
        temporary = Path(folder)
        extension = temporary / "synthetic-stream.mjs"
        extension.write_text("""import {realpathSync} from 'node:fs';
        export default function(pi) {
          pi.registerCommand('wf-meeting-stream', {description:'Package test only',handler:async(args,ctx)=>{
            const input=JSON.parse(args);
            if(input.op==='start') {
              if(ctx.model?.provider==='fixture') {
                const auth=await ctx.modelRegistry.getApiKeyAndHeaders(ctx.model);
                if(!auth.ok || auth.apiKey!=='package-test-pi-key')throw new Error('Synthetic credential mismatch');
              }
              ctx.ui.notify('WF_MEETING_STREAM_EVENT '+JSON.stringify({kind:'diagnostic',message:String(process.pid),node:process.execPath,pi:realpathSync(process.argv[1]),provider:ctx.model?.provider,directory:process.env.PI_CODING_AGENT_DIR}),'info');
            }
            if(input.op==='append')ctx.ui.notify('WF_MEETING_STREAM_EVENT '+JSON.stringify({kind:'preview',itemID:'one',text:'草稿'}),'info');
            if(input.op==='stop')ctx.ui.notify('WF_MEETING_STREAM_EVENT '+JSON.stringify({kind:'final',itemID:'one',text:'最后一句'}),'info');
            ctx.ui.notify('WF_MEETING_STREAM_ACK '+JSON.stringify({id:input.id,op:input.op}),'info');
          }});
        }""")
        environment = {"HOME": folder, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TMPDIR": folder,
                       "LANG": "en_US.UTF-8", "PI_CODING_AGENT_DIR": str(temporary / "pi-config")}
        if node:
            environment["WORKFOLLOW_NODE_PATH"] = str(node.resolve())

        async def launch(env):
            return await asyncio.create_subprocess_exec(str(python), "-I", "-B",
                str(root / "backend/ai_entry.py"), "--root", str(root),
                stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE, env=env, cwd=folder)

        process = await launch(environment)
        events = []

        async def request(method, params=None, expected_error=None):
            request_id = str(uuid.uuid4())
            params = {"piExecutable": str(pi.resolve()), **(params or {})} if pi else (params or {})
            process.stdin.write((json.dumps({"id": request_id, "method": method, "params": params}) + "\n").encode())
            await process.stdin.drain()
            while True:
                line = await asyncio.wait_for(process.stdout.readline(), 30)
                if not line:
                    raise RuntimeError("Bundled backend exited before responding")
                response = json.loads(line)
                if "event" in response:
                    events.append(response)
                if response.get("id") == request_id:
                    if "error" in response:
                        if expected_error:
                            assert response["error"]["code"] == expected_error
                            return response["error"]
                        raise RuntimeError(response["error"]["message"])
                    assert expected_error is None, "Expected the backend to report an error"
                    return response["result"]

        http = None
        try:
            assert json.loads(await asyncio.wait_for(process.stdout.readline(), 10)) == {"ready": 1}
            health = await request("health")
            assert health["protocol"] == 1
            assert {"knowledge", "note_rewrite"}.issubset(health["capabilities"])
            assert isinstance((await request("models"))["models"], list)
            stream = await request("stream.open", {"channel": "first", "streamExtension": str(extension)})
            await request("stream.command", {"streamID": stream["streamID"], "op": "append", "audio": "AA==", "sequence": 0})
            await request("stream.command", {"streamID": stream["streamID"], "op": "stop"})
            assert [item["event"]["kind"] for item in events if item["event"]["kind"] != "diagnostic"] == ["preview", "final"]
            assert events[-1]["event"]["text"] == "最后一句"
            node_path = Path(next(item["event"]["node"] for item in events if item["event"]["kind"] == "diagnostic"))
            assert not node_path.resolve().is_relative_to(app.resolve()), "Pi used a bundled Node"
            pi_path = Path(next(item["event"]["pi"] for item in events if item["event"]["kind"] == "diagnostic"))
            assert not pi_path.resolve().is_relative_to(app.resolve()), "Pi came from the App"

            requests = []

            class Handler(BaseHTTPRequestHandler):
                def do_POST(self):
                    payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                    requests.append((self.path, payload))
                    source = json.dumps(payload, ensure_ascii=False)
                    if "知识问答合成验证" in source:
                        text = json.dumps({"paragraphs": [{"text": "周五验收。", "citations": [
                            {"source": "S1", "quote": "周五验收。"}]}], "insufficient": False}, ensure_ascii=False)
                    elif "笔记改写合成验证" in source:
                        text = "整理后的合成笔记正文。"
                    elif "待办提取合成验证" in source:
                        text = json.dumps({"tasks": [{"title": "核对成本", "date": None, "due": "2026-10-30",
                            "priority": "none", "quote": "周五前核对成本。"}]}, ensure_ascii=False)
                    else:
                        text = "已验证摘要"
                    if payload.get("stream") and self.path.startswith("/openai/"):
                        self.send_response(200); self.send_header("Content-Type", "text/event-stream")
                        self.send_header("Connection", "close"); self.end_headers()
                        for delta, finish in [({"role": "assistant", "content": text}, None), ({}, "stop")]:
                            value = {"id": "fixture", "object": "chat.completion.chunk", "created": 1, "model": "fixture-model",
                                     "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
                            self.wfile.write(("data: " + json.dumps(value) + "\n\n").encode())
                        self.wfile.write(b"data: [DONE]\n\n"); self.wfile.flush(); self.close_connection = True
                        return
                    if self.path.startswith("/responses/"):
                        value = {"id": "resp_synthetic", "object": "response", "created_at": 1, "model": "fixture-model",
                            "status": "completed", "error": None, "incomplete_details": None,
                            "output": [{"type": "message", "id": "msg_synthetic", "role": "assistant", "status": "completed",
                                        "content": [{"type": "output_text", "text": text, "annotations": []}]}],
                            "usage": {"input_tokens": 10, "output_tokens": 1, "total_tokens": 11,
                                      "input_tokens_details": {"cached_tokens": 0}, "output_tokens_details": {"reasoning_tokens": 0}}}
                    else:
                        value = {"id": "synthetic", "object": "chat.completion", "created": 1,
                            "model": "fixture-model", "choices": [{"index": 0, "finish_reason": "stop",
                            "message": {"role": "assistant", "content": text}}]}
                    if payload.get("stream") and self.path.startswith("/responses/"):
                        self.send_response(200); self.send_header("Content-Type", "text/event-stream")
                        self.send_header("Connection", "close"); self.end_headers()
                        sequence = 0
                        def event(kind, **values):
                            nonlocal sequence
                            data = {"type": kind, "sequence_number": sequence, **values}; sequence += 1
                            self.wfile.write(("event: " + kind + "\ndata: " + json.dumps(data) + "\n\n").encode())
                        item = value["output"][0]
                        event("response.created", response={**value, "status": "in_progress", "output": []})
                        event("response.output_item.added", output_index=0, item={**item, "status": "in_progress", "content": []})
                        event("response.content_part.added", output_index=0, item_id=item["id"], content_index=0,
                            part={"type": "output_text", "text": "", "annotations": []})
                        event("response.output_text.delta", output_index=0, item_id=item["id"], content_index=0, delta=text)
                        event("response.output_text.done", output_index=0, item_id=item["id"], content_index=0, text=text)
                        event("response.content_part.done", output_index=0, item_id=item["id"], content_index=0, part=item["content"][0])
                        event("response.output_item.done", output_index=0, item=item)
                        event("response.completed", response=value)
                        self.wfile.flush(); self.close_connection = True
                        return
                    body = json.dumps(value).encode()
                    self.send_response(200); self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

                def log_message(self, *args):
                    pass

            http = HTTPServer(("127.0.0.1", 0), Handler)
            threading.Thread(target=lambda: http.serve_forever(poll_interval=0.05), daemon=True).start()

            async def workflows(engine, options):
                answer = await request("knowledge.ask", {**options, "engine": engine,
                    "question": "知识问答合成验证：海鸥何时验收？",
                    "sources": [{"id": "S1", "title": "海鸥项目", "content": "定稿发言：周五验收。"}]})
                assert answer["sourceIDs"] == ["S1"]
                assert answer["paragraphs"][0]["citations"][0] == {"source": "S1", "quote": "周五验收。"}
                channel = str(uuid.uuid4())
                note = await request("note.rewrite", {**options, "engine": engine, "action": "polish",
                    "title": "笔记改写合成验证", "content": "这是一条用于验证的合成笔记。",
                    "jobID": str(uuid.uuid4()), "progressChannel": channel})
                assert note["text"] == "整理后的合成笔记正文。"
                progress = [item["event"] for item in events if item["channel"] == channel]
                assert progress[-1] == {"kind": "text", "text": "整理后的合成笔记正文。"}
                tasks = await request("text.tasks", {**options, "engine": engine, "action": "extract_tasks",
                    "title": "待办提取合成验证", "content": "周五前核对成本。测试报告已完成。追加采购仅为建议。",
                    "referenceDate": "2026-10-29", "timeZone": "Asia/Shanghai"})
                row = json.loads(tasks["text"])["tasks"][0]
                assert row["title"] == "核对成本" and row["quote"] == "周五前核对成本。"
                assert row["due"] == "2026-10-30" and row["date"] is None

            routes = {"openai_chat": "/openai/v1", "openai_responses": "/responses/v1", }
            for protocol, route in routes.items():
                configuration = {"ai_enabled": True, "ai_protocol": protocol,
                    "ai_base_url": f"http://127.0.0.1:{http.server_port}" + route,
                    "ai_model": "fixture-model", "ai_api_key": "test-only-key"}
                assert (await request("model.test", {"configuration": configuration}))["success"] is True
                result = await request("text.summary", {"engine": "langchain", "content": "只使用这条合成事实。",
                    "options": {"length": "简短", "style": "正式"}, "configuration": configuration})
                assert result["text"] == "已验证摘要"
                await workflows("langchain", {"configuration": configuration})
            assert requests[0][0] == "/openai/v1/chat/completions"
            error = await request("models", {"piExecutable": str(temporary / "missing/pi")}, expected_error="pi_unavailable")
            assert "AI 配置说明" in error["message"]

            pi_directory = temporary / "pi-config"
            pi_directory.mkdir(exist_ok=True)
            pi_models = {"providers": {"fixture": {"api": "openai-completions",
                "baseUrl": f"http://127.0.0.1:{http.server_port}/openai/v1", "apiKey": "package-test-pi-key",
                "models": [{"id": "fixture-model"}]}}}
            pi_file = pi_directory / "models.json"
            pi_file.write_text(json.dumps(pi_models))
            before = pi_file.read_bytes()
            catalog = await request("models")
            assert any(item["provider"] == "fixture" and item["id"] == "fixture-model" for item in catalog["models"])
            generated = await request("text.generate", {"model": "fixture/fixture-model", "prompt": "请回复测试文字。"})
            assert generated["text"] == "已验证摘要"
            await workflows("pi", {"model": "fixture/fixture-model"})
            configured = await request("stream.open", {"channel": "configured", "model": "fixture/fixture-model", "streamExtension": str(extension)})
            diagnostic = events[-1]["event"]
            assert diagnostic["provider"] == "fixture"
            assert Path(diagnostic["directory"]) == pi_directory
            await request("stream.command", {"streamID": configured["streamID"], "op": "stop"})
            assert pi_file.read_bytes() == before

            # Leave a session open. EOF must close the Pi process using local Node.
            await request("stream.open", {"channel": "shutdown", "streamExtension": str(extension)})
            pid = int(events[-1]["event"]["message"])
            process.stdin.close()
            await asyncio.wait_for(process.wait(), 5)
            assert process.returncode == 0
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                pass
            else:
                raise AssertionError("Pi session survived backend EOF")

            # A Mac without Node must still support direct text-model calls.
            process = await launch({**environment, "WORKFOLLOW_NODE_PATH": str(temporary / "not-installed/node")})
            assert json.loads(await asyncio.wait_for(process.stdout.readline(), 10)) == {"ready": 1}
            assert (await request("health"))["protocol"] == 1
            error = await request("models", expected_error="node_unavailable")
            assert "AI 配置说明" in error["message"]
            result = await request("text.summary", {"engine": "langchain", "content": "无 Node 的合成事实。",
                "configuration": configuration})
            assert result["text"] == "已验证摘要"
            process.stdin.close()
            await asyncio.wait_for(process.wait(), 5)
            assert process.returncode == 0
            print("通过：包内后端启动、本机 Node/Pi、配置读取、两类引擎的资料问答与引用校验、笔记改写、两种 OpenAI 协议、转写末句和退出清理；缺少 Node 时直接调用仍可用。")
        finally:
            if process.returncode is None:
                process.terminate()
                await process.wait()
            if http:
                http.shutdown(); http.server_close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--node", type=Path, help="可选：指定本机 Node；默认验证 Finder 启动时的自动发现")
    parser.add_argument("--pi", type=Path, help="可选：指定本机 Pi 程序")
    args = parser.parse_args()
    asyncio.run(check(args.app.resolve(), args.node, args.pi))


if __name__ == "__main__":
    main()
