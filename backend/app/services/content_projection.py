from __future__ import annotations

from collections.abc import Mapping
from typing import Any


def _canonical(value: Any) -> Any:
    """Normalize editor-only JSON noise for projection no-op checks.

    Tiptap can add default ``null`` attributes and stable block ids while an
    editor is mounting. Those changes are useful inside Yjs, but they are not
    a user edit and must not trigger a task/note notification merely because a
    document was opened. Identity attributes such as taskId/noteId remain
    significant; only blockId is intentionally ignored here.
    """
    if isinstance(value, Mapping):
        result: dict[str, Any] = {}
        for key, child in value.items():
            if key == "attrs" and isinstance(child, Mapping):
                attrs = {
                    attr_key: _canonical(attr_value)
                    for attr_key, attr_value in child.items()
                    if attr_key != "blockId" and attr_value is not None
                }
                if attrs:
                    result[key] = attrs
                continue
            if key == "content" and isinstance(child, list):
                normalized_content = [_canonical(item) for item in child]
                if normalized_content:
                    result[key] = normalized_content
                continue
            result[key] = _canonical(child)
        return result
    if isinstance(value, list):
        return [_canonical(item) for item in value]
    return value


def content_json_semantically_equal(left: Mapping[str, Any] | None, right: Mapping[str, Any] | None) -> bool:
    return _canonical(left) == _canonical(right)
