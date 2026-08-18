from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.note import NoteTemplate


def paragraph(text: str = "") -> dict[str, Any]:
    node: dict[str, Any] = {"type": "paragraph"}
    if text:
        node["content"] = [{"type": "text", "text": text}]
    return node


def heading(text: str, level: int = 2) -> dict[str, Any]:
    return {"type": "heading", "attrs": {"level": level}, "content": [{"type": "text", "text": text}]}


BUILTIN_TEMPLATES: list[tuple[str, str, int, dict[str, Any]]] = [
    ("10000000-0000-0000-0000-000000000001", "空白笔记", 0, {"type": "doc", "content": [paragraph()]}),
    ("10000000-0000-0000-0000-000000000002", "需求分析", 10, {"type": "doc", "content": [heading("背景"), paragraph(), heading("目标"), paragraph(), heading("范围与约束"), paragraph(), heading("待确认问题"), paragraph()]}),
    ("10000000-0000-0000-0000-000000000003", "技术方案", 20, {"type": "doc", "content": [heading("问题定义"), paragraph(), heading("方案设计"), paragraph(), heading("数据与接口"), paragraph(), heading("风险与回滚"), paragraph()]}),
    ("10000000-0000-0000-0000-000000000004", "材料阅读", 30, {"type": "doc", "content": [heading("材料信息"), paragraph(), heading("核心观点"), paragraph(), heading("我的判断"), paragraph(), heading("后续行动"), paragraph()]}),
    ("10000000-0000-0000-0000-000000000005", "会议记录", 40, {"type": "doc", "content": [heading("会议信息"), paragraph(), heading("讨论结论"), paragraph(), heading("待办事项"), paragraph(), heading("待确认问题"), paragraph()]}),
    ("10000000-0000-0000-0000-000000000006", "问题分析", 50, {"type": "doc", "content": [heading("现象"), paragraph(), heading("影响"), paragraph(), heading("原因分析"), paragraph(), heading("解决方案"), paragraph(), heading("验证结果"), paragraph()]}),
]


def seed_builtin_templates(db: Session) -> None:
    existing = set(db.scalars(select(NoteTemplate.id)))
    for template_id, name, sort_order, content in BUILTIN_TEMPLATES:
        if template_id not in existing:
            db.add(NoteTemplate(id=template_id, name=name, content_json=content, is_builtin=True, sort_order=sort_order))
    db.commit()

