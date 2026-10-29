"""Explicit input budgets, independent of a provider's model catalog."""

from bisect import bisect_right
from dataclasses import dataclass
import json

from langchain_core.messages import BaseMessage


def estimate_text_tokens(text: str) -> int:
    # An intentionally conservative UTF-8 estimate for compatible providers
    # whose tokenizer is unknown. This is an estimate, not billed token usage.
    return len(text.encode("utf-8"))


def estimate_message_tokens(messages: list[BaseMessage]) -> int:
    return 16 + sum(estimate_text_tokens(str(message.content)) + 8 for message in messages)


@dataclass(frozen=True)
class ContextBudget:
    context_window: int
    output_tokens: int
    margin: int

    @property
    def input_tokens(self) -> int:
        return self.context_window - self.output_tokens - self.margin


@dataclass(frozen=True)
class TextChunk:
    text: str
    start: int
    end: int


def split_source(text: str, token_limit: int, *, overlap_tokens: int = 128) -> list[TextChunk]:
    """Keep paragraph/sentence boundaries when possible; retain overlapping evidence."""
    if token_limit < 16:
        raise ValueError("可用于正文的上下文预算不足")
    cumulative = [0]
    for character in text:
        encoded = json.dumps(character, ensure_ascii=False)[1:-1]
        cumulative.append(cumulative[-1] + len(encoded.encode("utf-8")))
    chunks: list[TextChunk] = []
    start = 0
    while start < len(text):
        end = min(len(text), bisect_right(cumulative, cumulative[start] + token_limit) - 1)
        if end < len(text):
            lower = start + (end - start) // 2
            boundary = max(text.rfind(mark, lower, end) for mark in ("\n", "。", "！", "？", ". ", ";"))
            if boundary >= lower:
                end = boundary + 1
        chunks.append(TextChunk(text[start:end], start, end))
        if end == len(text):
            break
        overlap = min(overlap_tokens, token_limit // 8)
        start = max(start + 1, bisect_right(cumulative, cumulative[end] - overlap) - 1)
    return chunks
