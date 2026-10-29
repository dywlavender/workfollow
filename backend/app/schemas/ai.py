from datetime import date, datetime
from typing import Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import Field, field_validator

from app.schemas.base import ApiModel


class AIConfigurationRead(ApiModel):
    enabled: bool
    configured: bool
    base_url: str
    model: str
    protocol: str = "openai_chat"
    context_window: int
    max_output_tokens: int
    input_budget: int
    summary_trigger_ratio: float
    summary_keep_ratio: float


class AIOptions(ApiModel):
    length: Literal["brief", "normal", "detailed"] = "normal"
    style: Literal["plain", "warm", "formal"] = "plain"
    profession: str = Field(default="", max_length=200)
    hint: str = Field(default="", max_length=2000)
    weekly_structure: bool = False
    is_weekly_period: bool = True


class AIGenerateRequest(ApiModel):
    action: Literal["extract_tasks", "breakdown_task", "improve_summary"]
    title: str = Field(default="", max_length=500)
    content: str = Field(min_length=1, max_length=256000)
    existing_titles: list[str] = Field(default_factory=list, max_length=500)
    reference_date: date | None = None
    time_zone: str = "Asia/Shanghai"
    options: AIOptions = Field(default_factory=AIOptions)

    @field_validator("content")
    @classmethod
    def nonempty_content(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("正文不能为空")
        return value

    @field_validator("existing_titles")
    @classmethod
    def bounded_titles(cls, value: list[str]) -> list[str]:
        if any(len(title) > 500 for title in value):
            raise ValueError("任务标题不能超过 500 字")
        return value

    @field_validator("time_zone")
    @classmethod
    def valid_time_zone(cls, value: str) -> str:
        try:
            ZoneInfo(value)
        except (ZoneInfoNotFoundError, ValueError) as exc:
            raise ValueError("时区无效") from exc
        return value


class AITaskDraft(ApiModel):
    title: str = Field(min_length=1, max_length=500)
    date: str | None = None
    due: str | None = None
    priority: Literal["none", "low", "medium", "high"] = "none"
    quote: str = Field(default="", max_length=2000)

    @field_validator("title")
    @classmethod
    def nonempty_title(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("任务标题不能为空")
        return value

    @field_validator("date", "due")
    @classmethod
    def valid_date(cls, value: str | None) -> str | None:
        if value is None:
            return None
        if len(value) == 10 and date.fromisoformat(value).isoformat() == value:
            return value
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if "T" not in value or parsed.tzinfo is None:
            raise ValueError("日期需要 YYYY-MM-DD 或带时区的 ISO8601 时间")
        return value


class AITaskPayload(ApiModel):
    tasks: list[AITaskDraft] = Field(max_length=200)


class AIUsage(ApiModel):
    model: str
    context_window: int
    input_budget: int
    max_output_tokens: int
    estimated_input_tokens: int = 0
    model_calls: int = 0
    chunks: int = 1
    compacted: bool = False


class AIGenerateResponse(ApiModel):
    text: str | None = None
    tasks: list[AITaskDraft] = Field(default_factory=list)
    usage: AIUsage


class AIMessage(ApiModel):
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=128000)


class AIChatRequest(ApiModel):
    instructions: str = Field(default="请准确、简洁地帮助用户处理当前问题。", max_length=4000)
    messages: list[AIMessage] = Field(min_length=1, max_length=200)

    @field_validator("messages")
    @classmethod
    def ends_with_user(cls, value: list[AIMessage]) -> list[AIMessage]:
        if value[-1].role != "user":
            raise ValueError("最后一条消息必须是用户消息")
        return value


class AIChatResponse(ApiModel):
    text: str
    messages: list[AIMessage]
    usage: AIUsage
