from __future__ import annotations

import re
from copy import deepcopy
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from markdown_it import MarkdownIt
from markdown_it.token import Token


class MarkdownImportError(ValueError):
    """Raised when a Markdown document cannot be converted to the note schema."""


_FRONT_MATTER_RE = re.compile(r"\A---\s*\n(?P<body>.*?)(?:\n|\r\n)(?:---|\.\.\.)\s*(?:\n|\Z)", re.DOTALL)
_TITLE_RE = re.compile(r"^\s*title\s*:\s*(?P<value>.+?)\s*$", re.IGNORECASE)
_H1_RE = re.compile(r"^\s{0,3}#\s+(?P<title>.+?)\s*#*\s*$")
_TASK_RE = re.compile(r"^\s*\[(?P<checked>[ xX])\]\s+")
_DANGEROUS_SCHEME_RE = re.compile(r"^(?:javascript|vbscript|data):", re.IGNORECASE)


def _token_attr(token: Token, name: str, default: Any = None) -> Any:
    attrs = token.attrs or {}
    if isinstance(attrs, dict):
        return attrs.get(name, default)
    for key, value in attrs:
        if key == name:
            return value
    return default


def _safe_url(value: str | None, *, image: bool = False) -> str | None:
    if not value:
        return None
    value = value.strip()
    if _DANGEROUS_SCHEME_RE.match(value):
        return None
    parsed = urlparse(value)
    if image:
        return value if parsed.scheme.lower() in {"http", "https"} else None
    if parsed.scheme.lower() in {"http", "https", "mailto", "tel"} or not parsed.scheme:
        return value
    return None


def _text_node(text: str, marks: list[dict[str, Any]] | None = None) -> dict[str, Any] | None:
    if not text:
        return None
    node: dict[str, Any] = {"type": "text", "text": text}
    if marks:
        node["marks"] = deepcopy(marks)
    return node


def _mark(type_name: str, attrs: dict[str, Any] | None = None) -> dict[str, Any]:
    value: dict[str, Any] = {"type": type_name}
    if attrs:
        value["attrs"] = attrs
    return value


def _parse_inline(tokens: list[Token] | None, *, allow_images: bool = True) -> list[dict[str, Any]]:
    if not tokens:
        return []
    content: list[dict[str, Any]] = []
    marks: list[dict[str, Any]] = []
    mark_stack: list[dict[str, Any] | None] = []

    def add_text(value: str, active_marks: list[dict[str, Any]] | None = None) -> None:
        node = _text_node(value, active_marks if active_marks is not None else marks)
        if node:
            if content and content[-1].get("type") == "text" and content[-1].get("marks", []) == node.get("marks", []):
                content[-1]["text"] = f"{content[-1].get('text', '')}{value}"
            else:
                content.append(node)

    for token in tokens:
        token_type = token.type
        if token_type in {"text", "entity"}:
            add_text(token.content)
        elif token_type == "softbreak":
            add_text(" ")
        elif token_type == "hardbreak":
            content.append({"type": "hardBreak"})
        elif token_type in {"em_open", "strong_open", "s_open", "del_open"}:
            type_name = {
                "em_open": "italic",
                "strong_open": "bold",
                "s_open": "strike",
                "del_open": "strike",
            }[token_type]
            next_mark = _mark(type_name)
            mark_stack.append(next_mark)
            marks.append(next_mark)
        elif token_type in {"em_close", "strong_close", "s_close", "del_close"}:
            type_name = {
                "em_close": "italic",
                "strong_close": "bold",
                "s_close": "strike",
                "del_close": "strike",
            }[token_type]
            for index in range(len(marks) - 1, -1, -1):
                if marks[index].get("type") == type_name:
                    marks.pop(index)
                    break
            if mark_stack:
                mark_stack.pop()
        elif token_type == "code_inline":
            add_text(token.content, [*marks, _mark("code")])
        elif token_type == "link_open":
            href = _safe_url(_token_attr(token, "href"))
            link_mark = _mark("link", {"href": href}) if href else None
            mark_stack.append(link_mark)
            if link_mark:
                marks.append(link_mark)
        elif token_type == "link_close":
            for index in range(len(marks) - 1, -1, -1):
                if marks[index].get("type") == "link":
                    marks.pop(index)
                    break
            if mark_stack:
                mark_stack.pop()
        elif token_type == "image":
            src = _safe_url(_token_attr(token, "src"), image=True)
            alt = _token_attr(token, "alt") or "".join(child.content for child in (token.children or []) if child.type == "text")
            if src and allow_images:
                attrs: dict[str, Any] = {"src": src, "alt": alt or None, "title": _token_attr(token, "title") or None}
                content.append({"type": "image", "attrs": attrs})
            else:
                add_text(f"![{alt}]({src})" if src and alt else f"[图片：{alt}]" if alt else "[图片]")
        elif token_type in {"html_inline", "html_block"}:
            # Raw HTML is intentionally ignored. Markdown imports must never
            # turn user-provided HTML into executable editor content.
            continue
        elif token.content:
            add_text(token.content)
    return content


def _paragraph_from_inline(token: Token | None, *, allow_images: bool = False) -> dict[str, Any]:
    content = _parse_inline(token.children if token else None, allow_images=allow_images)
    return {"type": "paragraph", "content": content} if content else {"type": "paragraph"}


def _paragraph_nodes_from_inline(token: Token | None) -> list[dict[str, Any]]:
    content = _parse_inline(token.children if token else None, allow_images=True)
    if not content:
        return [{"type": "paragraph"}]
    nodes: list[dict[str, Any]] = []
    paragraph_content: list[dict[str, Any]] = []
    for child in content:
        if child.get("type") == "image":
            if paragraph_content:
                nodes.append({"type": "paragraph", "content": paragraph_content})
                paragraph_content = []
            nodes.append(child)
        else:
            paragraph_content.append(child)
    if paragraph_content:
        nodes.append({"type": "paragraph", "content": paragraph_content})
    return nodes or [{"type": "paragraph"}]


def _ensure_block_content(nodes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return nodes or [{"type": "paragraph"}]


def _task_info(children: list[dict[str, Any]]) -> tuple[bool, bool]:
    if not children or children[0].get("type") != "paragraph":
        return False, False
    paragraph_content = children[0].get("content") or []
    if not paragraph_content or paragraph_content[0].get("type") != "text":
        return False, False
    first = paragraph_content[0]
    match = _TASK_RE.match(str(first.get("text") or ""))
    if not match:
        return False, False
    first["text"] = str(first.get("text") or "")[match.end():]
    if not first["text"]:
        paragraph_content.pop(0)
    return True, match.group("checked").lower() == "x"


def _table_cell(token: Token, *, header: bool) -> dict[str, Any]:
    node = _paragraph_from_inline(token, allow_images=False)
    return {"type": "tableHeader" if header else "tableCell", "content": [node]}


def _parse_blocks(tokens: list[Token], index: int = 0, closing: str | None = None) -> tuple[list[dict[str, Any]], int]:
    nodes: list[dict[str, Any]] = []
    while index < len(tokens):
        token = tokens[index]
        if closing and token.type == closing:
            return nodes, index + 1

        token_type = token.type
        if token_type == "paragraph_open":
            inline = tokens[index + 1] if index + 1 < len(tokens) and tokens[index + 1].type == "inline" else None
            nodes.extend(_paragraph_nodes_from_inline(inline))
            index += 3 if inline else 1
        elif token_type == "heading_open":
            inline = tokens[index + 1] if index + 1 < len(tokens) and tokens[index + 1].type == "inline" else None
            level = max(1, min(6, int(token.tag[1:]) if token.tag[1:].isdigit() else 1))
            node = _paragraph_from_inline(inline, allow_images=False)
            node["type"] = "heading"
            node["attrs"] = {"level": level}
            nodes.append(node)
            index += 3 if inline else 1
        elif token_type in {"blockquote_open", "bullet_list_open", "ordered_list_open", "list_item_open"}:
            child_closing = token_type.replace("_open", "_close")
            children, index = _parse_blocks(tokens, index + 1, child_closing)
            if token_type == "blockquote_open":
                nodes.append({"type": "blockquote", "content": _ensure_block_content(children)})
            elif token_type == "list_item_open":
                is_task, checked = _task_info(children)
                node: dict[str, Any] = {"type": "taskItem" if is_task else "listItem", "content": _ensure_block_content(children)}
                if is_task:
                    node["attrs"] = {"checked": checked}
                nodes.append(node)
            else:
                has_task = any(child.get("type") == "taskItem" for child in children)
                if has_task:
                    converted: list[dict[str, Any]] = []
                    for child in children:
                        if child.get("type") == "listItem":
                            child = {**child, "type": "taskItem", "attrs": {"checked": False}}
                        converted.append(child)
                    nodes.append({"type": "taskList", "content": converted})
                elif token_type == "ordered_list_open":
                    start = _token_attr(token, "start")
                    attrs = {"start": int(start) if str(start or "").isdigit() else 1}
                    nodes.append({"type": "orderedList", "attrs": attrs, "content": children})
                else:
                    nodes.append({"type": "bulletList", "content": children})
        elif token_type in {"code_block", "fence"}:
            language = None
            if token_type == "fence" and token.info:
                language = token.info.strip().split()[0] or None
            nodes.append({"type": "codeBlock", "attrs": {"language": language}, "content": [{"type": "text", "text": token.content.rstrip("\n")}] if token.content.rstrip("\n") else []})
            index += 1
        elif token_type == "hr":
            nodes.append({"type": "horizontalRule"})
            index += 1
        elif token_type == "table_open":
            children, index = _parse_blocks(tokens, index + 1, "table_close")
            nodes.append({"type": "table", "content": children})
        elif token_type == "tr_open":
            children, index = _parse_blocks(tokens, index + 1, "tr_close")
            nodes.append({"type": "tableRow", "content": children})
        elif token_type in {"th_open", "td_open"}:
            inline = tokens[index + 1] if index + 1 < len(tokens) and tokens[index + 1].type == "inline" else None
            nodes.append(_table_cell(inline, header=token_type == "th_open"))
            index += 3 if inline else 1
        elif token_type in {"thead_open", "tbody_open"}:
            children, index = _parse_blocks(tokens, index + 1, token_type.replace("_open", "_close"))
            nodes.extend(children)
        elif token_type == "inline":
            nodes.extend(_paragraph_nodes_from_inline(token))
            index += 1
        elif token_type.endswith("_close"):
            if closing:
                return nodes, index
            index += 1
        else:
            index += 1
    return nodes, index


def _strip_front_matter(markdown: str) -> tuple[str, str | None]:
    match = _FRONT_MATTER_RE.match(markdown)
    if not match:
        return markdown, None
    title = None
    for line in match.group("body").splitlines():
        title_match = _TITLE_RE.match(line)
        if title_match:
            title = title_match.group("value").strip().strip("'\"") or None
            break
    return markdown[match.end():], title


def _clean_heading_title(value: str) -> str:
    value = re.sub(r"!\[([^]]*)\]\([^)]*\)", r"\1", value)
    value = re.sub(r"\[([^]]+)\]\([^)]*\)", r"\1", value)
    value = re.sub(r"[*_~`]+", "", value)
    return re.sub(r"\s+", " ", value).strip().strip("#").strip()


def _first_h1_title(markdown: str) -> str | None:
    for line in markdown.splitlines():
        match = _H1_RE.match(line)
        if match:
            title = _clean_heading_title(match.group("title"))
            if title:
                return title
    return None


def _fallback_title(filename: str) -> str:
    stem = Path(filename).stem.strip()
    return stem or "未命名笔记"


def parse_markdown(markdown: str, filename: str) -> tuple[dict[str, Any], str]:
    body, front_matter_title = _strip_front_matter(markdown.lstrip("\ufeff"))
    try:
        parser = MarkdownIt("default", {"html": False, "linkify": False, "typographer": False})
        tokens = parser.parse(body)
        content, _ = _parse_blocks(tokens)
    except Exception as exc:  # pragma: no cover - parser internals vary by dependency version
        raise MarkdownImportError("Markdown 内容无法解析") from exc

    document = {"type": "doc", "content": _ensure_block_content(content)}
    title = front_matter_title or _first_h1_title(body) or _fallback_title(filename)
    title = title[:500].strip() or "未命名笔记"
    return document, title
