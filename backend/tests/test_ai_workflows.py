import asyncio
import json

import pytest
from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.messages import AIMessage
from langchain_core.outputs import ChatGeneration, ChatResult
from pydantic import Field, ValidationError

from app.ai_runtime.pi_engine import EngineError
from app.ai_runtime.server import Runtime
from app.ai_runtime.settings import AISettings
from app.ai_runtime.workflows import KnowledgeRequest, NoteRewriteRequest, knowledge_result
from app.services.ai_service import TextAIService


def question(sources=1):
    return KnowledgeRequest(question="海鸥项目何时验收？", sources=[
        {"id": f"S{index + 1}", "title": "海鸥项目会议", "content": "会议时间：2026-10-29\n周五验收。"}
        for index in range(sources)])


def answer(source="S1", quote="周五验收。"):
    return json.dumps({"paragraphs": [{"text": "周五验收。", "citations": [{"source": source, "quote": quote}]}], "insufficient": False}, ensure_ascii=False)


class WorkflowModel(BaseChatModel):
    seen: list = Field(default_factory=list)

    @property
    def _llm_type(self):
        return "workflow-fixture"

    def _generate(self, messages, stop=None, run_manager=None, **kwargs):
        self.seen.append(messages)
        data = json.loads(messages[-1].content)
        if "sources" in data:
            text = answer()
        else:
            # Echo all source chunks so polishing can prove that it never
            # summarizes away the final part of a long note.
            text = data["content"]
        return ChatResult(generations=[ChatGeneration(message=AIMessage(content=text))])


def settings():
    return AISettings(ai_enabled=True, ai_model="fixture", ai_api_key="fixture",
                      ai_context_window=4096, ai_max_output_tokens=512, ai_context_margin=512)


def test_answer_contains_resolvable_source_and_exact_original_quote():
    result = knowledge_result("```json\n" + answer() + "\n```", question())
    assert result["sourceIDs"] == ["S1"]
    assert result["paragraphs"][0]["citations"][0]["quote"] == "周五验收。"


@pytest.mark.parametrize("text", [answer("S8"), answer(quote="周一验收。"),
    '{"paragraphs":[{"text":"周五","citations":[]}]}', '{"paragraphs":[],"insufficient":false}'])
def test_unverifiable_answers_are_rejected(text):
    with pytest.raises(EngineError, match="原文摘录无法核对"):
        knowledge_result(text, question())


def test_insufficient_answer_has_no_uncited_factual_output():
    result = knowledge_result('{"paragraphs":[],"insufficient":true}', question())
    assert result["insufficient"] is True and not result["paragraphs"]


def test_duplicate_source_ids_are_rejected():
    with pytest.raises(ValidationError):
        KnowledgeRequest(question="问题", sources=[question().sources[0]] * 2)


def test_pi_and_langchain_dispatch_use_same_workflow_and_validation(tmp_path, monkeypatch):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        prompts = []

        async def generate(data, prompt, **kwargs):
            prompts.append(prompt)
            return answer() if "sources" in data else "整理后的正文"

        monkeypatch.setattr(runtime.pi, "generate", generate)
        pi = await runtime.dispatch("knowledge.ask", question().model_dump())
        assert pi["sourceIDs"] == ["S1"]
        assert "任务实际状态" in prompts[-1] and "周五验收。" in prompts[-1]
        assert (await runtime.dispatch("note.rewrite", {"action": "polish", "content": "原文。"}))["text"] == "整理后的正文"
        assert "不改写成摘要" in prompts[-1]
        model = WorkflowModel()
        monkeypatch.setattr("app.services.ai_service.TextAIService", lambda config: TextAIService(config, model=model))
        direct = await runtime.dispatch("knowledge.ask", {**question().model_dump(), "engine": "langchain", "configuration": settings().model_dump(mode="json") | {"ai_api_key": "fixture"}})
        assert direct == pi
        await runtime.close()

    asyncio.run(run())


def test_no_sources_skips_both_engines(tmp_path, monkeypatch):
    async def run():
        runtime = Runtime(tmp_path, lambda _: None)
        async def unexpected(*args):
            pytest.fail("no sources must not call a model")
        monkeypatch.setattr(runtime.pi, "generate", unexpected)
        monkeypatch.setattr(runtime, "langchain", unexpected)
        for engine in ("pi", "langchain"):
            result = await runtime.dispatch("knowledge.ask", {"question": "没有依据", "sources": [], "engine": engine})
            assert result == {"paragraphs": [], "insufficient": True, "sourceIDs": []}
    asyncio.run(run())


def test_direct_knowledge_sends_all_selected_sources_without_application_trimming():
    model = WorkflowModel()
    service = TextAIService(settings(), model=model)
    request = question(8)
    request.sources = [source.model_copy(update={"content": source.content + "补充说明。" * 300}) for source in request.sources]
    result = asyncio.run(service.answer_knowledge(request))
    assert len(result["sourceIDs"]) == 8
    sent = json.loads(model.seen[-1][-1].content)["sources"]
    assert all(source["content"] in request.sources[int(source["id"][1:]) - 1].content for source in sent)


def test_long_note_polish_keeps_tail_and_all_parts_without_summary_merge():
    model = WorkflowModel()
    service = TextAIService(settings(), model=model)
    original = "第一项决定：周五验收。\n" + "保留每一项详细记录。\n" * 300 + "末尾决定：下周提交发票。"
    response = asyncio.run(service.rewrite_note(NoteRewriteRequest(action="polish", title="项目记录", content=original)))
    assert response.usage.chunks == 1
    assert response.text.startswith("第一项决定") and response.text.endswith("下周提交发票。")
    assert response.text.count("保留每一项详细记录。") == original.count("保留每一项详细记录。")
    assert len(model.seen) == response.usage.chunks
