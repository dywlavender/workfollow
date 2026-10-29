"""Stable, user-facing model failures shared by Pi and direct calls."""
import math


class EngineError(Exception):
    def __init__(self, message: str, code: str = "engine_failed", retry_after: float | None = None):
        super().__init__(message)
        self.code = code
        self.retry_after = retry_after


def model_failure(message: str = "", *, status: int | None = None,
                  retry_after: str | float | None = None, reason: str = "") -> EngineError:
    # Only fixed descriptions leave the backend. Provider bodies can contain
    # credentials or unrelated links, so they are used for classification only.
    text = str(message).lower()
    if "unauthorized client" in text or "client not allowed" in text:
        return EngineError("模型服务拒绝当前客户端，请使用允许通用 API 的服务或联系服务方开通权限。", "client_unauthorized")
    if any(word in text for word in ("insufficient_quota", "quota exceeded", "insufficient balance", "余额不足", "额度不足")):
        return EngineError("模型服务额度不足，请检查服务余额或更换模型。", "quota_exceeded")
    if status == 429 or any(word in text for word in ("rate limit", "rate_limit", "too many requests", "限流")):
        try:
            seconds = float(retry_after) if retry_after is not None else 30.0
            if not math.isfinite(seconds) or seconds < 1: seconds = 30.0
        except (TypeError, ValueError):
            seconds = 30.0
        seconds = min(seconds, 600)
        return EngineError(f"模型服务触发速率限制，请在 {math.ceil(seconds)} 秒后重试或更换模型。", "rate_limited", seconds)
    if status in (401, 403) or any(word in text for word in ("invalid api key", "unauthorized", "authentication")):
        return EngineError("模型服务认证失败，请检查 API Key 和模型权限。", "authentication_failed")
    if reason == "length" or any(word in text for word in ("max_tokens", "max_output_tokens", "output limit")):
        return EngineError("模型输出达到长度上限，未采用不完整结果；请缩小内容范围或提高输出预算。", "output_limit")
    if any(word in text for word in ("context length", "context_length", "context window", "上下文")):
        return EngineError("内容超过模型上下文，请缩小范围或选择更大上下文的模型。", "context_limit")
    if reason == "timeout" or status in (408, 504) or "timed out" in text or "timeout" in text:
        return EngineError("模型请求超时，原文与已处理段落保留，请稍后重试。", "timeout")
    if status == 404:
        return EngineError("模型或接口不存在，请检查协议、模型名称和 API 地址。", "model_not_found")
    if reason == "connection":
        return EngineError("无法连接模型服务，请检查服务地址和网络。", "connection_failed")
    if reason == "aborted":
        return EngineError("模型已中止生成，原有内容保留，请重试。", "generation_aborted")
    return EngineError("模型服务调用失败，原有内容保留，请稍后重试或检查模型设置。")
