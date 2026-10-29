"""UI previews from the agent's normal text stream; final results stay validated."""
import time

from langchain_core.utils.json import parse_partial_json


class TextStream:
    def __init__(self, method, channel, emit):
        self.method, self.channel, self.emit = method, channel, emit
        self.last = 0

    def __call__(self, event):
        if not self.channel:
            return
        if event.get("kind") == "text":
            now = time.monotonic()
            text = event.get("text", "")
            if self.method in ("text.tasks", "knowledge.ask"):
                raw = text.strip()
                if raw.startswith("```") and "\n" in raw:
                    raw = raw.split("\n", 1)[1].removesuffix("```")
                try:
                    value = parse_partial_json(raw) or {}
                    rows = value.get("tasks" if self.method == "text.tasks" else "paragraphs", [])
                    text = "\n\n".join(row.get("title" if self.method == "text.tasks" else "text", "") for row in rows if isinstance(row, dict))
                except (ValueError, AttributeError, TypeError):
                    return
            if text and not event.get("force") and now - self.last < 0.05:
                return
            self.last = now if text else 0
            event = {"kind": "text", "text": text}
        self.emit({"channel": self.channel, "event": event})

    def text(self, text):
        self({"kind": "text", "text": text})
