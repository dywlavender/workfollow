import asyncio
import base64
import json
from uuid import uuid4

import httpx
import pytest
from langchain_core.messages import AIMessage, HumanMessage

from app.ai_runtime.attachments import attachment_content
from app.ai_runtime.server import Runtime
from app.ai_runtime.settings import AISettings
from app.ai_runtime.workflows import NoteRewriteRequest
from app.services.ai_service import TextAIService


def attachments(tmp_path):
    image = tmp_path / "虚构图片.png"
    image.write_bytes(base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aXs8AAAAASUVORK5CYII="))
    document = tmp_path / "项目资料.txt"
    document.write_text("虚构项目：周五提交演示稿。")
    return [{"name": image.name, "path": str(image), "mimeType": "image/png"},
            {"name": document.name, "path": str(document), "mimeType": "text/plain", "textPath": str(document)}]


def test_pi_receives_image_bytes_and_file_text_on_all_input_surfaces(tmp_path, monkeypatch):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        calls, models = [], []
        class Session:
            async def request(self, payload, mode, timeout):
                calls.append(payload)
                return "已读取虚构附件"
            async def close(self): pass
        async def session(options, *args, **kwargs):
            models.append(options.get("model"))
            return Session()
        monkeypatch.setattr(runtime.pi, "session", session)
        # Image support is assumed. No get_available_models or model switch.
        async def forbidden(*args, **kwargs): raise AssertionError("must not inspect model capabilities")
        monkeypatch.setattr(runtime.pi, "models", forbidden)
        files = attachments(tmp_path)
        options = {"conversationID": str(uuid4()), "sessionDirectory": str(tmp_path / "sessions"),
                   "model": "current/default", "attachments": files, "message": ""}
        await runtime.dispatch("conversation.send", options)
        await runtime.dispatch("conversation.send", {**options, "scene": "selection", "context": "原文"})
        await runtime.dispatch("note.rewrite", {**options, "scene": "note", "title": "虚构笔记", "content": "原文", "action": "polish"})
        await runtime.dispatch("text.tasks", {**options, "content": "原文", "action": "extract_tasks"})
        assert len(calls) == 4 and models == ["current/default"] * 4
        for payload in calls:
            assert payload["type"] == "prompt"
            assert payload["images"][0]["mimeType"] == "image/png"
            assert base64.b64decode(payload["images"][0]["data"]) == (tmp_path / "虚构图片.png").read_bytes()
            assert "虚构项目：周五提交演示稿。" in payload["message"]
        await runtime.close()
    asyncio.run(run())


def test_delete_conversation_removes_its_attachments_and_preserves_other_conversations(tmp_path):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        root = tmp_path / "sessions"
        own, other = uuid4(), uuid4()
        paths = [root / "attachments" / "chat" / str(own) / "image.png",
                 root / "attachments" / "chat" / str(other) / "image.png",
                 root / "attachments" / "note" / str(own) / "image.png"]
        for path in paths:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"fixture")
        await runtime.dispatch("conversation.delete", {"conversationID": str(own).upper(), "sessionDirectory": str(root)})
        assert not paths[0].exists()
        assert all(path.exists() for path in paths[1:])
        await runtime.close()
    asyncio.run(run())


def test_langchain_note_input_keeps_multimodal_blocks(tmp_path, monkeypatch):
    async def run():
        service = TextAIService(AISettings())
        service.input_images, service.attachment_context = attachment_content({"attachments": attachments(tmp_path)})
        async def conversation(rules, messages, usage):
            assert isinstance(messages[0], HumanMessage)
            text, image = messages[0].content
            assert text["type"] == "text" and "虚构项目" in text["text"]
            assert image["image_url"]["url"].startswith("data:image/png;base64,")
            return {"messages": [AIMessage(content="整理结果")]}
        monkeypatch.setattr(service, "_conversation", conversation)
        assert await service._invoke("整理笔记", {"content": "虚构原文"}, service._usage()) == "整理结果"
        await service.close()
    asyncio.run(run())


@pytest.mark.parametrize("protocol", ["openai_chat", "openai_responses"])
def test_existing_openai_adapters_send_image_contents(protocol, tmp_path):
    async def run():
        requests = []
        def respond(request):
            requests.append(json.loads(request.content))
            if protocol == "openai_chat":
                payload = {"id": "fixture", "object": "chat.completion", "created": 1, "model": "fixture",
                           "choices": [{"index": 0, "message": {"role": "assistant", "content": "图片内容"}, "finish_reason": "stop"}]}
            else:
                payload = {"id": "resp_fixture", "object": "response", "created_at": 1, "model": "fixture", "status": "completed",
                           "output": [{"id": "msg_fixture", "type": "message", "role": "assistant", "status": "completed",
                                       "content": [{"type": "output_text", "text": "图片内容", "annotations": []}]}]}
            return httpx.Response(200, json=payload)
        service = TextAIService(AISettings(ai_enabled=True, ai_protocol=protocol,
            ai_model="fixture", ai_api_key="test-only-key", ai_base_url="https://fixture.example/v1"),
            http_transport=httpx.MockTransport(respond))
        service.input_images, service.attachment_context = attachment_content({"attachments": attachments(tmp_path)})
        try:
            result = await service.rewrite_note(NoteRewriteRequest(action="organize", content="虚构原文"))
        finally:
            await service.close()
        assert result.text == "图片内容"
        body = requests[0]
        if protocol == "openai_chat":
            image = body["messages"][-1]["content"][-1]
            assert image["type"] == "image_url" and image["image_url"]["url"].startswith("data:image/png;base64,")
        else:
            image = body["input"][-1]["content"][-1]
            assert image["type"] == "input_image" and image["image_url"].startswith("data:image/png;base64,")
    asyncio.run(run())
