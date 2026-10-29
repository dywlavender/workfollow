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
def provider(protocol, *, status=200, truncated=False):
    requests = []

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            requests.append((self.path, dict(self.headers), request))
            if status != 200:
                response = {"type": "error", "error": {"type": "authentication_error", "code": status,
                    "status": "UNAUTHENTICATED", "message": "hidden-test-credential"}}
            elif protocol == "openai_chat":
                response = {"id": "synthetic", "object": "chat.completion", "created": 1, "model": "fixture-model",
                    "choices": [{"index": 0, "finish_reason": "length" if truncated else "stop", "message": {"role": "assistant", "content": "OK"}}]}
            elif protocol == "openai_responses":
                response = {"id": "resp_synthetic", "object": "response", "created_at": 1, "model": "fixture-model",
                    "status": "incomplete" if truncated else "completed", "error": None,
                    "incomplete_details": {"reason": "max_output_tokens"} if truncated else None,
                    "output": [{"type": "message", "id": "msg_synthetic", "role": "assistant", "status": "completed",
                                "content": [{"type": "output_text", "text": "OK", "annotations": []}]}],
                    "usage": {"input_tokens": 10, "output_tokens": 1, "total_tokens": 11,
                              "input_tokens_details": {"cached_tokens": 0}, "output_tokens_details": {"reasoning_tokens": 0}}}
            body = json.dumps(response).encode()
            self.send_response(status); self.send_header("Content-Type", "application/json")
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
        assert chat["text"] == "OK" and chat["usage"]["compacted"] is True
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
