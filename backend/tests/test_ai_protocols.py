import asyncio
from contextlib import contextmanager
from functools import wraps
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from pathlib import Path
import threading

import pytest

from app.ai_runtime.protocols import endpoint
from app.ai_runtime.server import Runtime
from app.ai_runtime.settings import AISettings
from app.schemas.ai import AIChatRequest
from app.services.ai_service import AIServiceError, TextAIService


def run_async(test):
    @wraps(test)
    def wrapped(*args, **kwargs):
        return asyncio.run(test(*args, **kwargs))
    return wrapped


@contextmanager
def provider(protocol, *, status=200, truncated=False, text="OK", error_message="hidden-test-credential", retry_after=None):
    requests = []

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            requests.append((self.path, dict(self.headers), request))
            output = text(request) if callable(text) else text
            if status != 200:
                response = {"type": "error", "error": {"type": "authentication_error", "code": status,
                    "status": "UNAUTHENTICATED", "message": error_message}}
            elif protocol == "openai_chat":
                response = {"id": "synthetic", "object": "chat.completion", "created": 1, "model": "fixture-model",
                    "choices": [{"index": 0, "finish_reason": "length" if truncated else "stop", "message": {"role": "assistant", "content": output}}]}
            elif protocol == "openai_responses":
                response = {"id": "resp_synthetic", "object": "response", "created_at": 1, "model": "fixture-model",
                    "status": "incomplete" if truncated else "completed", "error": None,
                    "incomplete_details": {"reason": "max_output_tokens"} if truncated else None,
                    "output": [{"type": "message", "id": "msg_synthetic", "role": "assistant", "status": "completed",
                                "content": [{"type": "output_text", "text": output, "annotations": []}]}],
                    "usage": {"input_tokens": 10, "output_tokens": 1, "total_tokens": 11,
                              "input_tokens_details": {"cached_tokens": 0}, "output_tokens_details": {"reasoning_tokens": 0}}}
            if status == 200 and request.get("stream"):
                self.send_response(200); self.send_header("Content-Type", "text/event-stream")
                self.send_header("Connection", "close"); self.end_headers()
                def emit(value, name=None):
                    prefix = f"event: {name}\n" if name else ""
                    self.wfile.write((prefix + "data: " + json.dumps(value) + "\n\n").encode())
                    self.wfile.flush()
                pieces = [output[:len(output)//2], output[len(output)//2:]]
                if protocol == "openai_chat":
                    for piece in pieces:
                        emit({"id": "fixture", "object": "chat.completion.chunk", "created": 1, "model": "fixture-model",
                            "choices": [{"index": 0, "delta": {"role": "assistant", "content": piece}, "finish_reason": None}]})
                    emit({"id": "fixture", "object": "chat.completion.chunk", "created": 1, "model": "fixture-model",
                        "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]})
                    self.wfile.write(b"data: [DONE]\n\n")
                else:
                    sequence = 0
                    def event(kind, **values):
                        nonlocal sequence
                        emit({"type": kind, "sequence_number": sequence, **values}, kind); sequence += 1
                    item = response["output"][0]
                    event("response.created", response={**response, "status": "in_progress", "output": []})
                    event("response.output_item.added", output_index=0, item={**item, "status": "in_progress", "content": []})
                    part = {"type": "output_text", "text": "", "annotations": []}
                    event("response.content_part.added", output_index=0, item_id=item["id"], content_index=0, part=part)
                    for piece in pieces:
                        event("response.output_text.delta", output_index=0, item_id=item["id"], content_index=0, delta=piece)
                    event("response.output_text.done", output_index=0, item_id=item["id"], content_index=0, text=output)
                    event("response.content_part.done", output_index=0, item_id=item["id"], content_index=0, part=item["content"][0])
                    event("response.output_item.done", output_index=0, item=item)
                    event("response.completed", response=response)
                self.wfile.flush(); self.close_connection = True
                return
            body = json.dumps(response).encode()
            self.send_response(status); self.send_header("Content-Type", "application/json")
            if retry_after is not None:
                self.send_header("Retry-After", str(retry_after))
            self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = HTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=lambda: server.serve_forever(poll_interval=0.01), daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}", requests
    finally:
        server.shutdown(); server.server_close(); thread.join()


CASES = [
    ("openai_chat", "/gateway/v1/chat/completions", "/gateway/v1/chat/completions", "Authorization", "Bearer test-only-key"),
    ("openai_responses", "/gateway/v1/responses", "/gateway/v1/responses", "Authorization", "Bearer test-only-key"),
]


@pytest.mark.parametrize("protocol", ["openai_chat", "openai_responses"])
@run_async
async def test_full_note_streams_through_agent_without_application_splitting(protocol, tmp_path):
    def echo_source(body):
        messages = body.get("messages", body.get("input"))
        content = messages[-1]["content"]
        if isinstance(content, list):
            content = "".join(block["text"] for block in content)
        return json.loads(content)["content"]
    events = []
    runtime = Runtime(tmp_path, events.append)
    original = "\n".join(f"记录{index:02}：本项尚未批准采购，需保留单价和复核日期。" for index in range(24))
    with provider(protocol, text=echo_source) as (url, requests):
        config = {"ai_enabled": True, "ai_protocol": protocol, "ai_base_url": url + "/v1",
            "ai_model": "fixture-model", "ai_max_output_tokens": 256}
        params = {"engine": "langchain", "configuration": config, "action": "polish", "content": original,
            "progressChannel": "note-progress"}
        result = await runtime.dispatch("note.rewrite", params)
        assert all(result["text"].count(f"记录{index:02}") == 1 for index in range(24))
        assert len(requests) == result["usage"]["chunks"] == 1
        assert events and all(event["event"]["kind"] == "text" for event in events)
        assert any(event["event"]["text"] and event["event"]["text"] in original for event in events)
        assert all(event["channel"] == "note-progress" for event in events)
    await runtime.close()


@pytest.mark.parametrize("protocol", ["openai_chat", "openai_responses"])
@run_async
async def test_real_sdk_rate_limit_is_not_retried_and_error_reaches_native_rpc(protocol, tmp_path):
    events = []
    runtime = Runtime(tmp_path, events.append)
    with provider(protocol, status=429, error_message="token rate limit hidden-test-credential", retry_after=12) as (url, requests):
        params = {"engine": "langchain", "configuration": {"ai_enabled": True, "ai_protocol": protocol,
            "ai_base_url": url + "/v1", "ai_model": "fixture-model"}}
        await runtime.handle({"id": "one", "method": "model.test", "params": params})
        await runtime.handle({"id": "two", "method": "model.test", "params": params})
        assert len(requests) == 1
        assert all(event["error"]["code"] == "rate_limited" for event in events)
        assert all(0 < event["error"]["retryAfterSeconds"] <= 12 for event in events)
        assert "hidden-test-credential" not in json.dumps(events)
    await runtime.close()


@pytest.mark.parametrize("protocol", ["openai_chat", "openai_responses"])
@run_async
async def test_knowledge_and_note_workflows_use_both_openai_protocols(protocol, tmp_path):
    runtime = Runtime(tmp_path, lambda _: None)
    answer = json.dumps({"paragraphs": [{"text": "周五验收。", "citations": [{"source": "S1", "quote": "周五验收。"}]}], "insufficient": False}, ensure_ascii=False)
    with provider(protocol, text=answer) as (url, requests):
        configuration = {"ai_enabled": True, "ai_protocol": protocol, "ai_base_url": url + "/v1", "ai_model": "fixture-model"}
        result = await runtime.dispatch("knowledge.ask", {"engine": "langchain", "configuration": configuration,
            "question": "海鸥项目何时验收", "sources": [{"id": "S1", "title": "海鸥项目", "content": "周五验收。"}]})
        assert result["sourceIDs"] == ["S1"] and result["paragraphs"][0]["text"] == "周五验收。"
        assert "周五验收。" in json.dumps(requests[-1][2], ensure_ascii=False)
    with provider(protocol, text="润色后的正文。") as (url, requests):
        configuration["ai_base_url"] = url + "/v1"
        result = await runtime.dispatch("note.rewrite", {"engine": "langchain", "configuration": configuration,
            "action": "polish", "title": "海鸥项目", "content": "核对成本，再发送报价。"})
        assert result["text"] == "润色后的正文。"
        assert "核对成本，再发送报价。" in json.dumps(requests[-1][2], ensure_ascii=False)
    await runtime.close()


@pytest.mark.parametrize("protocol,url_suffix,path,header,expected_key", CASES)
@run_async
async def test_openai_protocols_use_real_sdk_serialization(protocol, url_suffix, path, header, expected_key, tmp_path):
    with provider(protocol) as (url, requests):
        configuration = {"ai_enabled": True, "ai_protocol": protocol, "ai_base_url": url + url_suffix,
            "ai_api_key": "test-only-key", "ai_model": "fixture-model"}
        runtime = Runtime(tmp_path, lambda _: None)
        response = await runtime.dispatch("model.test", {"configuration": configuration})
        assert response == {"success": True}
        request_path, headers, body = requests[0]
        assert request_path == path
        assert {key.lower(): value for key, value in headers.items()}[header.lower()] == expected_key
        if protocol == "openai_responses":
            assert body["store"] is False
            assert "input" in body and "messages" not in body
            assert "previous_response_id" not in body
        else:
            assert body["model"] == "fixture-model"
        # Reuse the same service address after the first request's SDK client
        # closed; also verify the normal system+source messages used by the App.
        generated = await runtime.dispatch("text.summary", {"engine": "langchain", "configuration": configuration,
            "content": "末尾事实：周五交付。"})
        assert generated["text"] == "OK"
        assert "末尾事实" in json.dumps(requests[-1][2], ensure_ascii=False)
        chat = await runtime.dispatch("chat", {"engine": "langchain", "configuration": {**configuration,
            "ai_context_window": 8192, "ai_max_output_tokens": 512}, "messages": [
                {"role": "user", "content": "earlier facts " + "a" * 2500},
                {"role": "assistant", "content": "earlier reply " + "b" * 2500},
                {"role": "user", "content": "最新问题：保留确认后的结论。"}]})
        assert chat["text"] == "OK" and chat["usage"]["compacted"] is False
        assert chat["messages"][-1] == {"role": "assistant", "content": "OK"}


@pytest.mark.parametrize("protocol,url_suffix,path,header,expected_key", CASES)
@run_async
async def test_provider_errors_never_echo_the_upstream_body(protocol, url_suffix, path, header, expected_key, tmp_path):
    with provider(protocol, status=401) as (url, _):
        settings = AISettings(ai_enabled=True, ai_protocol=protocol, ai_base_url=url + url_suffix,
            ai_api_key="test-only-key", ai_model="fixture-model")
        service = TextAIService(settings)
        try:
            with pytest.raises(AIServiceError) as failure:
                await service.test_connection()
            assert "hidden-test-credential" not in str(failure.value)
            assert "test-only-key" not in str(failure.value)
            assert "认证" in str(failure.value) or "配置" in str(failure.value)
        finally:
            await service.close()


@pytest.mark.parametrize("protocol,url_suffix,path,header,expected_key", CASES)
@run_async
async def test_truncated_output_is_rejected_for_every_protocol(protocol, url_suffix, path, header, expected_key):
    with provider(protocol, truncated=True) as (url, _):
        service = TextAIService(AISettings(ai_enabled=True, ai_protocol=protocol, ai_base_url=url + url_suffix,
            ai_api_key="test-only-key", ai_model="fixture-model"))
        try:
            with pytest.raises(AIServiceError):
                await service.test_connection()
        finally:
            await service.close()


@run_async
async def test_keyless_local_compatible_model_and_direct_meeting_minutes(tmp_path):
    with provider("openai_chat") as (url, requests):
        runtime = Runtime(tmp_path, lambda _: None)
        config = {"ai_enabled": True, "ai_base_url": url + "/v1", "ai_model": "local-model"}
        response = await runtime.dispatch("meeting.minutes", {"engine": "langchain", "configuration": config,
            "lines": [{"speaker": "片段 1 · 暂定讲话人1", "text": "周五提交方案", "offset": 0}]})
        assert response["text"] == "OK"
        sent = json.dumps(requests[0][2], ensure_ascii=False)
        assert "周五提交方案" in sent and "暂定讲话人1" in sent
        assert "会议纪要编辑器" in sent and "身份待确认" in sent


def test_api_bases_retain_gateway_paths():
    assert endpoint("openai_chat", "https://proxy.example/team/v1/chat/completions") == ("https://proxy.example/team/v1", None)
    assert endpoint("openai_responses", "https://proxy.example/team/v1/responses") == ("https://proxy.example/team/v1", None)
    with pytest.raises(ValueError):
        endpoint("openai_chat", "https://user:password@proxy.example/v1")
