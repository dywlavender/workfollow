import asyncio
import json

import httpx
import pytest
from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.messages import AIMessage, BaseMessage, HumanMessage
from langchain_core.outputs import ChatGeneration, ChatResult
from pydantic import Field

from app.core.config import Settings
from app.schemas.ai import AIChatRequest, AIGenerateRequest
from app.services.ai_service import AIServiceError, TextAIService


class RecordingModel(BaseChatModel):
    responses: list[str] = Field(default_factory=list)
    seen: list[list[BaseMessage]] = Field(default_factory=list)
    finish_reason: str = "stop"

    @property
    def _llm_type(self) -> str:
        return "recording-test-model"

    def _generate(self, messages, stop=None, run_manager=None, **kwargs):
        self.seen.append(messages)
        text = self.responses.pop(0)
        return ChatResult(generations=[ChatGeneration(message=AIMessage(
            content=text, response_metadata={"finish_reason": self.finish_reason},
        ))])


class ExtractingModel(RecordingModel):
    def _generate(self, messages, stop=None, run_manager=None, **kwargs):
        self.seen.append(messages)
        data = json.loads(messages[-1].content)
        tasks = []
        for title, quote in [("提交方案", "明天提交方案。"), ("核对合同", "下周一核对合同。")]:
            if quote in data["content"]:
                tasks.append({"title": title, "quote": quote})
        return ChatResult(generations=[ChatGeneration(message=AIMessage(content=json.dumps({"tasks": tasks}, ensure_ascii=False)))])


def ai_settings(**overrides) -> Settings:
    return Settings(_env_file=None, ai_enabled=True, ai_api_key="test-only-key", ai_model="compatible-model",
                    ai_context_window=4096, ai_max_output_tokens=512, ai_context_margin=512, **overrides)


def test_long_note_extraction_keeps_tail_evidence_and_deduplicates():
    model = ExtractingModel()
    service = TextAIService(ai_settings(), model=model)
    content = "明天提交方案。\n" + "背景说明，没有新的行动。\n" * 80 + "明天提交方案。\n下周一核对合同。"
    result = asyncio.run(service.generate(AIGenerateRequest(
        action="extract_tasks", content=content, referenceDate="2026-10-28",
    )))
    assert [task.title for task in result.tasks] == ["提交方案", "核对合同"]
    assert result.usage.chunks == 1
    assert result.usage.model_calls == len(model.seen)
    assert all(task.quote in content for task in result.tasks)
    assert "2026-10-28" in model.seen[0][-1].content


def test_extract_requires_quote_but_breakdown_can_suggest_steps():
    model = RecordingModel(responses=['{"tasks":[{"title":"执行建议","quote":"不存在的原文"}]}'])
    service = TextAIService(ai_settings(), model=model)
    with pytest.raises(AIServiceError, match="原文依据"):
        asyncio.run(service.generate(AIGenerateRequest(action="extract_tasks", content="今天只是讨论。")))

    model.responses = ['{"tasks":[{"title":"列出验收清单"}]}']
    result = asyncio.run(service.generate(AIGenerateRequest(action="breakdown_task", content="完成项目验收")))
    assert result.tasks[0].title == "列出验收清单"


def test_invalid_date_and_truncated_output_are_not_adopted():
    model = RecordingModel(responses=['{"tasks":[{"title":"验收","date":"明天"}]}'])
    service = TextAIService(ai_settings(), model=model)
    with pytest.raises(AIServiceError, match="日期无效"):
        asyncio.run(service.generate(AIGenerateRequest(action="breakdown_task", content="项目验收")))
    model.responses = ["只有前半段"]
    model.finish_reason = "length"
    with pytest.raises(AIServiceError, match="长度上限"):
        asyncio.run(service.generate(AIGenerateRequest(action="improve_summary", content="完整摘要")))


def test_long_summary_is_combined_instead_of_losing_the_last_chunk():
    class SummaryModel(RecordingModel):
        def _generate(self, messages, stop=None, run_manager=None, **kwargs):
            self.seen.append(messages)
            text = json.loads(messages[-1].content)["content"]
            facts = [fact for fact in ["第一部分成果", "最后部分成果"] if fact in text]
            return ChatResult(generations=[ChatGeneration(message=AIMessage(content="；".join(facts) or "背景事项"))])

    model = SummaryModel()
    service = TextAIService(ai_settings(), model=model)
    content = "第一部分成果。\n" + "A" * 6000 + "\n最后部分成果。"
    result = asyncio.run(service.generate(AIGenerateRequest(action="improve_summary", content=content, referenceDate="2026-10-28")))
    assert result.usage.chunks == 1
    assert result.usage.model_calls == 1
    assert "最后部分成果" in result.text
    merge = json.loads(model.seen[-1][-1].content)["content"]
    assert "第一部分成果" in merge and "最后部分成果" in merge


def test_langchain_compacts_history_and_returns_reusable_context_without_mutating_input():
    model = RecordingModel(responses=["交付日期是11月2日；任务尚未完成。", "继续按11月2日安排交付。"])
    service = TextAIService(ai_settings(), model=model)
    messages = [{"role": "user" if i % 2 == 0 else "assistant", "content": f"历史讨论{i}：交付日期11月2日，任务尚未完成。" * 10} for i in range(100)]
    messages.append({"role": "user", "content": "继续整理下一步"})
    original = json.dumps(messages, ensure_ascii=False)
    result = asyncio.run(service.chat(AIChatRequest(messages=messages)))
    assert result.usage.compacted
    assert result.usage.model_calls == 2
    assert len(result.messages) < len(messages)
    assert "11月2日" in result.messages[0].content
    assert result.messages[-1].role == "assistant"
    assert result.messages[-2].content == "继续整理下一步"
    assert json.dumps(messages, ensure_ascii=False) == original


def test_large_single_message_is_sent_to_the_agent_without_preflight_rejection():
    model = RecordingModel(responses=["完整返回"])
    service = TextAIService(ai_settings(), model=model)
    content = "长" * 3000
    asyncio.run(service.chat(AIChatRequest(messages=[{"role": "user", "content": content}])))
    assert model.seen[0][-1].content == content


def test_real_langchain_adapter_uses_compatible_chat_endpoint(monkeypatch):
    from langchain_openai import ChatOpenAI

    async def run():
        captured = []

        def handler(request: httpx.Request):
            captured.append(request)
            return httpx.Response(200, json={
                "id": "test-completion", "object": "chat.completion", "created": 1, "model": "compatible-model",
                "choices": [{"index": 0, "message": {"role": "assistant", "content": "优化后的摘要"}, "finish_reason": "stop"}],
                "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15},
            })

        settings = ai_settings(ai_base_url="https://compatible.example/v1")
        service = TextAIService(settings, http_transport=httpx.MockTransport(handler))
        try:
            result = await service.generate(AIGenerateRequest(action="improve_summary", content="本期摘要"))
        finally:
            await service.close()
        assert result.text == "优化后的摘要"
        assert captured[0].url.path == "/v1/chat/completions"
        assert captured[0].headers["authorization"] == "Bearer test-only-key"
        body = json.loads(captured[0].content)
        assert body["model"] == "compatible-model"
        assert body["messages"][-1]["role"] == "user"

    asyncio.run(run())
