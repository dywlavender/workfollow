from copy import deepcopy
from typing import Any

from fastapi import HTTPException
from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.note import NoteTemplate
from app.models.todo import local_now
from app.schemas.note import NoteTemplateCreate, NoteTemplateUpdate


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
    added = False
    for template_id, name, sort_order, content in BUILTIN_TEMPLATES:
        if template_id not in existing:
            db.add(
                NoteTemplate(
                    id=template_id,
                    name=name,
                    content_json=deepcopy(content),
                    is_builtin=True,
                    owner_id=None,
                    sort_order=sort_order,
                    description=None,
                )
            )
            added = True
    if added:
        db.commit()


def list_accessible_templates(db: Session, user_id: str) -> list[NoteTemplate]:
    return list(
        db.scalars(
            select(NoteTemplate)
            .where(
                NoteTemplate.deleted_at.is_(None),
                or_(NoteTemplate.is_builtin.is_(True), NoteTemplate.owner_id == user_id),
            )
            .order_by(
                NoteTemplate.is_builtin.desc(),
                NoteTemplate.sort_order,
                NoteTemplate.created_at,
                NoteTemplate.name,
            )
        )
    )


def get_accessible_template_or_404(db: Session, template_id: str, user_id: str) -> NoteTemplate:
    template = db.scalar(
        select(NoteTemplate).where(
            NoteTemplate.id == template_id,
            NoteTemplate.deleted_at.is_(None),
            or_(NoteTemplate.is_builtin.is_(True), NoteTemplate.owner_id == user_id),
        )
    )
    if template is None:
        raise HTTPException(status_code=404, detail="NoteTemplate not found")
    return template


def _get_owned_template_or_404(db: Session, template_id: str, user_id: str) -> NoteTemplate:
    template = db.scalar(
        select(NoteTemplate).where(
            NoteTemplate.id == template_id,
            NoteTemplate.deleted_at.is_(None),
        )
    )
    if template is None or (not template.is_builtin and template.owner_id != user_id):
        raise HTTPException(status_code=404, detail="NoteTemplate not found")
    if template.is_builtin:
        raise HTTPException(status_code=403, detail="系统模板不可修改")
    return template


def _ensure_name_available(db: Session, owner_id: str, name: str, exclude_id: str | None = None) -> None:
    statement = select(NoteTemplate.id).where(
        NoteTemplate.owner_id == owner_id,
        NoteTemplate.name == name,
        NoteTemplate.deleted_at.is_(None),
    )
    if exclude_id is not None:
        statement = statement.where(NoteTemplate.id != exclude_id)
    if db.scalar(statement.limit(1)) is not None:
        raise HTTPException(status_code=409, detail="模板名称已存在")


def create_template(db: Session, payload: NoteTemplateCreate, owner_id: str) -> NoteTemplate:
    _ensure_name_available(db, owner_id, payload.name)
    template = NoteTemplate(
        owner_id=owner_id,
        name=payload.name,
        description=payload.description,
        content_json=deepcopy(payload.content_json),
        is_builtin=False,
        sort_order=payload.sort_order,
    )
    db.add(template)
    try:
        db.commit()
    except IntegrityError as cause:
        db.rollback()
        raise HTTPException(status_code=409, detail="模板名称已存在") from cause
    db.refresh(template)
    return template


def update_template(db: Session, template_id: str, payload: NoteTemplateUpdate, owner_id: str) -> NoteTemplate:
    template = _get_owned_template_or_404(db, template_id, owner_id)
    changes = payload.model_dump(exclude_unset=True)
    if "name" in changes:
        _ensure_name_available(db, owner_id, changes["name"], exclude_id=template.id)
    if "content_json" in changes:
        changes["content_json"] = deepcopy(changes["content_json"])
    for field, value in changes.items():
        setattr(template, field, value)
    template.updated_at = local_now()
    try:
        db.commit()
    except IntegrityError as cause:
        db.rollback()
        raise HTTPException(status_code=409, detail="模板名称已存在") from cause
    db.refresh(template)
    return template


def delete_template(db: Session, template_id: str, owner_id: str) -> None:
    template = _get_owned_template_or_404(db, template_id, owner_id)
    template.deleted_at = local_now()
    template.updated_at = local_now()
    db.commit()
