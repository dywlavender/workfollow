from pydantic import BaseModel, Field, SecretStr, model_validator
from typing import Literal
from urllib.parse import urlsplit


class AISettings(BaseModel):
    ai_enabled: bool = False
    ai_base_url: str = "https://api.openai.com/v1"
    ai_api_key: SecretStr = SecretStr("")
    ai_model: str = ""
    ai_protocol: Literal["openai_chat", "openai_responses"] = "openai_chat"
    ai_context_window: int = Field(default=32768, ge=2048)
    ai_max_output_tokens: int = Field(default=2048, ge=128)
    ai_context_margin: int = Field(default=1024, ge=256)
    ai_timeout_seconds: float = Field(default=90, gt=0, le=600)
    ai_max_chunks: int = Field(default=32, ge=1, le=128)
    ai_summary_trigger_ratio: float = Field(default=0.7, gt=0, lt=1)
    ai_summary_keep_ratio: float = Field(default=0.2, gt=0, lt=1)

    @property
    def requires_api_key(self) -> bool:
        return not (self.ai_protocol in ("openai_chat", "openai_responses") and
                    urlsplit(self.ai_base_url).hostname in ("localhost", "127.0.0.1", "::1"))

    @model_validator(mode="after")
    def validate_ai_budget(self) -> "AISettings":
        if self.ai_context_window - self.ai_max_output_tokens - self.ai_context_margin < 1024:
            raise ValueError("AI 上下文窗口必须为输入、输出和预留空间提供足够预算")
        if self.ai_summary_keep_ratio >= self.ai_summary_trigger_ratio:
            raise ValueError("AI 历史保留比例必须小于压缩触发比例")
        return self
