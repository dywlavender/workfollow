"""Versioned JSON-lines RPC over the owning App's stdin/stdout pipes.

No listening port, daemon, web account or business database. EOF and SIGTERM
cancel work and close the model sessions, including Pi's child processes.
"""
from __future__ import annotations

import argparse
import asyncio
import json
from pathlib import Path
import signal
import sys
import time

from pydantic import ValidationError

from app.ai_runtime.pi_engine import PiEngine
from app.ai_runtime.conversation import converse
from app.ai_runtime.failures import EngineError, model_failure
from app.ai_runtime.prompts import minutes_prompt, summary_prompt, task_prompt
from app.ai_runtime.settings import AISettings
from app.ai_runtime.text_stream import TextStream
from app.ai_runtime.workflows import KnowledgeRequest, NoteRewriteRequest, knowledge_prompt, knowledge_result, note_prompt
from app.schemas.ai import AIChatRequest, AIGenerateRequest

PROTOCOL_VERSION = 1
MAX_MESSAGE_BYTES = 8 * 1024 * 1024


def normalized_options(data: dict) -> dict:
    options = data.get("options", {}).copy()
    options["length"] = {"简短": "brief", "默认": "normal", "详细": "detailed"}.get(options.get("length"), options.get("length", "normal"))
    options["style"] = {"平实": "plain", "温暖": "warm", "正式": "formal"}.get(options.get("style"), options.get("style", "plain"))
    return options


class Runtime:
    def __init__(self, root: Path, emit):
        self.root = root
        self.emit = emit
        self.pi = PiEngine(root)
        self.pending: dict[str, asyncio.Task] = {}
        self.text_gate = asyncio.Lock()
        self.cooldowns = {}

    async def dispatch(self, method: str, data: dict):
        text_methods = {"knowledge.ask", "note.rewrite", "text.tasks", "text.summary", "text.generate", "chat", "conversation.send", "meeting.minutes", "model.test"}
        if method not in text_methods or (method == "knowledge.ask" and not data.get("sources")):
            return await self._dispatch(method, data)
        key = self.model_key(data)
        remaining = self.cooldowns.get(key, 0) - time.monotonic()
        if remaining > 0:
            raise model_failure(status=429, retry_after=remaining)
        try:
            # A cancelled child can take a moment to exit. Briefly wait for
            # cleanup, then report busy without starting another model call.
            await asyncio.wait_for(self.text_gate.acquire(), 2)
        except TimeoutError:
            raise EngineError("另一个文字 AI 任务正在处理，请等待完成或先取消。", "busy") from None
        try:
            remaining = self.cooldowns.get(key, 0) - time.monotonic()
            if remaining > 0:
                raise model_failure(status=429, retry_after=remaining)
            async with asyncio.timeout(600):
                return await self._dispatch(method, data)
        except EngineError as exc:
            if exc.code == "rate_limited":
                self.cooldowns[key] = time.monotonic() + (exc.retry_after or 30)
            raise
        finally:
            self.text_gate.release()

    @staticmethod
    def model_key(data):
        config = data.get("configuration", {})
        return (data.get("engine", "pi"), data.get("model", ""), data.get("piExecutable", ""),
                data.get("profileID", ""), *(config.get(key) for key in
                ("ai_protocol", "ai_base_url", "ai_model", "ai_context_window", "ai_max_output_tokens", "ai_context_margin")))

    def text_stream(self, method, data):
        return TextStream(method, data.get("progressChannel"), self.emit)

    async def _dispatch(self, method: str, data: dict):
        if method == "health":
            return {"protocol": PROTOCOL_VERSION, "engines": ["pi", "langchain"],
                    "capabilities": ["tasks", "summary", "minutes", "transcription", "stream", "chat", "conversation", "knowledge", "note_rewrite", "streaming_text"]}
        if method == "models":
            return {"models": await self.pi.models(data)}
        if method == "conversation.send":
            return await converse(self.pi, data, self.text_stream(method, data))
        if method == "model.test":
            return await self.langchain(method, data)
        if method in ("knowledge.ask", "note.rewrite"):
            if data.get("engine", "pi") not in ("pi", "langchain"):
                raise EngineError("不支持的 AI 引擎。", "invalid_request")
            request = KnowledgeRequest.model_validate(data) if method == "knowledge.ask" else NoteRewriteRequest.model_validate(data)
            if isinstance(request, KnowledgeRequest) and not request.sources:
                return {"paragraphs": [], "insufficient": True, "sourceIDs": []}
            if data.get("engine") == "langchain":
                return await self.langchain(method, data)
            if isinstance(request, NoteRewriteRequest):
                if data.get("conversationID"):
                    return await converse(self.pi, data, self.text_stream(method, data), prompt=note_prompt(request), scene="note")
                return {"text": await self.pi.generate(data, note_prompt(request), on_event=self.text_stream(method, data))}
            text = await self.pi.generate(data, knowledge_prompt(request), on_event=self.text_stream(method, data))
            return knowledge_result(text, request)
        if method in ("text.tasks", "text.summary", "text.generate", "chat"):
            if method == "text.tasks" and not data.get("content", "").strip():
                data = {**data, "content": data.get("title", "")}
            if data.get("engine", "pi") not in ("pi", "langchain"):
                raise EngineError("不支持的 AI 引擎。", "invalid_request")
            if data.get("engine", "pi") == "langchain":
                return await self.langchain(method, data)
            if method == "chat":
                raise EngineError("带历史压缩的对话需要选择 LangChain 引擎。", "invalid_request")
            if method == "text.tasks":
                request = AIGenerateRequest.model_validate(data)
                prompt = task_prompt(request.model_dump(mode="json", by_alias=True))
            elif method == "text.summary":
                request = AIGenerateRequest.model_validate({**data, "action": "improve_summary", "options": normalized_options(data)})
                prompt = summary_prompt(request.model_dump(mode="json", by_alias=True))
            else:
                prompt = data["prompt"]
                if not isinstance(prompt, str) or not prompt.strip():
                    raise EngineError("输入不能为空。", "invalid_request")
            return {"text": await self.pi.generate(data, prompt, on_event=self.text_stream(method, data))}
        if method == "meeting.minutes":
            if not data.get("lines"):
                return {"text": data.get("minutes", "")}
            if data.get("engine") == "langchain":
                return await self.langchain(method, data)
            extension = ""
            prompt = minutes_prompt(data)
            model_id = data.get("model", "").split("/")[-1]
            if "-asr-" in model_id or model_id.startswith(("fun-asr", "paraformer")):
                raise EngineError("纪要模型需要支持文字生成，请选择文字模型。", "invalid_request")
            if "-omni-" in model_id and model_id.endswith("-realtime"):
                extension = self.audio_extension(data)
                prompt = "/wf-meeting-minutes " + json.dumps({"version": 1, "prompt": prompt}, ensure_ascii=False)
            return {"text": await self.pi.generate(data, prompt, extension, on_event=self.text_stream(method, data))}
        if method == "meeting.prepare":
            if data.get("model", "").split("/")[-1] == "qwen-audio-3.1-asr-flash" and not data.get("audioExtension"):
                await self.pi.generate(data, "/wf-meeting-check", self.audio_extension(data))
            return {}
        if method == "meeting.transcribe":
            payload = {key: data[key] for key in ("audio", "offset", "duration", "knownSpeakers")}
            payload.update(version=2, format="pcm16", sampleRate=16000, channels=1)
            text = await self.pi.generate(data, "/wf-meeting-audio " + json.dumps(payload), self.audio_extension(data))
            return {"text": text}
        if method == "stream.open":
            channel = data["channel"]
            stream_id = await self.pi.open_stream(data, lambda event: self.emit({"channel": channel, "event": event}))
            return {"streamID": stream_id}
        if method == "stream.command":
            await self.pi.stream_command(data)
            return {}
        raise EngineError("不支持的 AI 操作。", "invalid_request")

    def audio_extension(self, data: dict) -> str:
        return data.get("audioExtension", "").strip() or str(self.root / "resources" / "wf-meeting-audio.mjs")

    async def langchain(self, method: str, data: dict):
        # Lazy import keeps Pi-only startup quick. The same service is also used
        # by the old web API, without importing its Settings, DB or auth layer.
        from app.services.ai_service import AIServiceError, TextAIService
        settings = AISettings.model_validate(data.get("configuration", {}))
        service = TextAIService(settings)
        service.on_text = self.text_stream(method, data).text if data.get("progressChannel") else None
        try:
            async with asyncio.timeout(600):
                if method == "model.test":
                    await service.test_connection()
                    return {"success": True}
                elif method == "knowledge.ask":
                    return await service.answer_knowledge(KnowledgeRequest.model_validate(data))
                elif method == "note.rewrite":
                    result = await service.rewrite_note(NoteRewriteRequest.model_validate(data))
                elif method == "meeting.minutes":
                    result = await service.write_minutes(data["lines"])
                elif method == "chat":
                    result = await service.chat(AIChatRequest.model_validate(data))
                elif method == "text.generate":
                    result = await service.chat(AIChatRequest(messages=[{"role": "user", "content": data["prompt"]}]))
                else:
                    params = {**data, "action": "improve_summary"} if method == "text.summary" else data
                    request = AIGenerateRequest.model_validate({**params, "options": normalized_options(params)})
                    result = await service.generate(request)
        except AIServiceError as exc:
            raise EngineError(str(exc), exc.code, exc.retry_after) from exc
        finally:
            await service.close()
        value = result.model_dump(mode="json", by_alias=True)
        if method == "text.tasks":
            value["text"] = json.dumps({"tasks": value["tasks"]}, ensure_ascii=False)
        return value

    async def handle(self, message: dict):
        request_id = message["id"]
        try:
            result = await self.dispatch(message["method"], message.get("params", {}))
            self.emit({"id": request_id, "result": result})
        except asyncio.CancelledError:
            self.emit({"id": request_id, "error": {"code": "cancelled", "message": "操作已取消。"}})
        except TimeoutError:
            self.emit({"id": request_id, "error": {"code": "timeout", "message": "AI 请求超时，已有内容保留。"}})
        except EngineError as exc:
            error = {"code": exc.code, "message": str(exc)}
            if exc.retry_after is not None:
                error["retryAfterSeconds"] = exc.retry_after
            self.emit({"id": request_id, "error": error})
        except (ValidationError, KeyError, TypeError, ValueError):
            self.emit({"id": request_id, "error": {"code": "invalid_request", "message": "AI 请求参数不正确。"}})
        except Exception:
            self.emit({"id": request_id, "error": {"code": "engine_failed", "message": "AI 服务调用失败，请检查模型配置。"}})
        finally:
            self.pending.pop(request_id, None)

    def accept(self, message: dict):
        if message.get("method") == "cancel":
            task = self.pending.get(message.get("params", {}).get("requestID"))
            if task:
                task.cancel()
            return
        request_id = message.get("id")
        if not isinstance(request_id, str) or request_id in self.pending:
            return
        self.pending[request_id] = asyncio.create_task(self.handle(message))

    async def close(self):
        tasks = list(self.pending.values())
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        await self.pi.close()
        self.cooldowns.clear()


async def serve(root: Path):
    def emit(message):
        sys.stdout.write(json.dumps(message, ensure_ascii=False, separators=(",", ":")) + "\n")
        sys.stdout.flush()

    runtime = Runtime(root, emit)
    loop = asyncio.get_running_loop()
    reader = asyncio.StreamReader(limit=MAX_MESSAGE_BYTES)
    transport, _ = await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin.buffer)
    current = asyncio.current_task()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, current.cancel)
    emit({"ready": PROTOCOL_VERSION})
    try:
        while line := await reader.readline():
            try:
                message = json.loads(line)
                if isinstance(message, dict):
                    runtime.accept(message)
            except (ValueError, UnicodeError):
                continue
    except (asyncio.CancelledError, ValueError):
        pass
    finally:
        transport.close()
        await runtime.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    asyncio.run(serve(args.root))
