from __future__ import annotations

from collections.abc import Iterable, Mapping
from typing import Any

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.note import Note
from app.models.resource_relation import RelationType, ResourceRelation, ResourceType
from app.models.team_note import TeamNote
from app.models.todo import Todo, local_now
from app.schemas.resource_relation import ResourceRelationCreate, TaskSourceCreate, TaskSourceRead
from app.services import note_permission_service, todo_service


def _personal_note(db: Session, resource_id: str) -> Note | None:
    return db.get(Note, resource_id)


def _team_note(db: Session, resource_id: str) -> TeamNote | None:
    return db.get(TeamNote, resource_id)


def can_view_resource(db: Session, resource_type: ResourceType, resource_id: str, user_id: str) -> bool:
    if resource_type == ResourceType.PERSONAL_NOTE:
        note = _personal_note(db, resource_id)
        return note is not None and note_permission_service.can_view_personal_note(db, note, user_id)
    if resource_type == ResourceType.TEAM_NOTE:
        note = _team_note(db, resource_id)
        return note is not None and note_permission_service.can_view_team_note(db, note, user_id)
    if resource_type == ResourceType.TASK:
        task = db.get(Todo, resource_id)
        return task is not None and todo_service.can_view(db, task, user_id)
    return False


def can_edit_resource(db: Session, resource_type: ResourceType, resource_id: str, user_id: str) -> bool:
    if resource_type == ResourceType.PERSONAL_NOTE:
        note = _personal_note(db, resource_id)
        return note is not None and note_permission_service.can_edit_personal_note(note, user_id)
    if resource_type == ResourceType.TEAM_NOTE:
        note = _team_note(db, resource_id)
        return note is not None and note_permission_service.can_edit_team_note(db, note, user_id)
    if resource_type == ResourceType.TASK:
        task = db.get(Todo, resource_id)
        return task is not None and todo_service.can_edit(db, task, user_id)
    return False


def require_resource_access(
    db: Session,
    resource_type: ResourceType,
    resource_id: str,
    user_id: str,
    *,
    edit: bool,
) -> None:
    allowed = (
        can_edit_resource(db, resource_type, resource_id, user_id)
        if edit else can_view_resource(db, resource_type, resource_id, user_id)
    )
    if not allowed:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Resource not found")


def create_relation(
    db: Session,
    payload: ResourceRelationCreate,
    user_id: str,
    *,
    source_may_be_read_only: bool = False,
    commit: bool = True,
) -> ResourceRelation:
    require_resource_access(
        db, payload.source_type, payload.source_id, user_id, edit=not source_may_be_read_only
    )
    require_resource_access(db, payload.target_type, payload.target_id, user_id, edit=False)
    existing = db.scalar(select(ResourceRelation).where(
        ResourceRelation.source_type == payload.source_type,
        ResourceRelation.source_id == payload.source_id,
        ResourceRelation.source_block_id == payload.source_block_id,
        ResourceRelation.target_type == payload.target_type,
        ResourceRelation.target_id == payload.target_id,
        ResourceRelation.relation_type == payload.relation_type,
        ResourceRelation.created_by_id == user_id,
    ).order_by(ResourceRelation.created_at.desc()))
    if existing is not None:
        existing.deleted_at = None
        existing.source_excerpt = payload.source_excerpt
        relation = existing
    else:
        relation = ResourceRelation(**payload.model_dump(), created_by_id=user_id)
        db.add(relation)
    db.flush()
    if commit:
        db.commit()
        db.refresh(relation)
    return relation


def create_task_source_relation(
    db: Session, task: Todo, source: TaskSourceCreate, user_id: str
) -> ResourceRelation:
    return create_relation(
        db,
        ResourceRelationCreate(
            source_type=source.resource_type,
            source_id=source.resource_id,
            source_block_id=source.block_id,
            target_type=ResourceType.TASK,
            target_id=task.id,
            relation_type=RelationType.CREATED_FROM,
            source_excerpt=source.excerpt,
        ),
        user_id,
        source_may_be_read_only=True,
        commit=False,
    )


def list_task_source_relations(db: Session, task_id: str) -> list[ResourceRelation]:
    return list(db.scalars(select(ResourceRelation).where(
        ResourceRelation.target_type == ResourceType.TASK,
        ResourceRelation.target_id == task_id,
        ResourceRelation.source_type.in_((ResourceType.PERSONAL_NOTE, ResourceType.TEAM_NOTE)),
        ResourceRelation.deleted_at.is_(None),
    ).order_by(ResourceRelation.created_at.asc())))


def task_sources_for_user(db: Session, task_id: str, user_id: str) -> list[TaskSourceRead]:
    result: list[TaskSourceRead] = []
    for relation in list_task_source_relations(db, task_id):
        accessible = can_view_resource(db, relation.source_type, relation.source_id, user_id)
        title: str | None = None
        if accessible:
            resource = (
                _personal_note(db, relation.source_id)
                if relation.source_type == ResourceType.PERSONAL_NOTE
                else _team_note(db, relation.source_id)
            )
            title = resource.title if resource is not None else None
        result.append(TaskSourceRead(
            relation_id=relation.id,
            resource_type=relation.source_type,
            resource_id=relation.source_id if accessible else None,
            block_id=relation.source_block_id if accessible else None,
            title=title,
            excerpt=relation.source_excerpt if accessible else None,
            accessible=accessible,
        ))
    return result


def task_ids_in_document(content_json: Mapping[str, Any] | None) -> set[str]:
    task_ids: set[str] = set()

    def visit(value: Any) -> None:
        if isinstance(value, Mapping):
            attrs = value.get("attrs")
            if value.get("type") == "taskReference" and isinstance(attrs, Mapping):
                task_id = attrs.get("taskId")
                if isinstance(task_id, str) and task_id:
                    task_ids.add(task_id)
            marks = value.get("marks")
            if isinstance(marks, list):
                for mark in marks:
                    if not isinstance(mark, Mapping) or mark.get("type") != "taskLink":
                        continue
                    mark_attrs = mark.get("attrs")
                    task_id = mark_attrs.get("taskId") if isinstance(mark_attrs, Mapping) else None
                    if isinstance(task_id, str) and task_id:
                        task_ids.add(task_id)
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(content_json)
    return task_ids


def sync_personal_note_relations(
    db: Session, note_id: str, user_id: str, retained_task_ids: Iterable[str]
) -> None:
    retained = set(retained_task_ids)
    relations = db.scalars(select(ResourceRelation).where(
        ResourceRelation.source_type == ResourceType.PERSONAL_NOTE,
        ResourceRelation.source_id == note_id,
        ResourceRelation.target_type == ResourceType.TASK,
        ResourceRelation.created_by_id == user_id,
        ResourceRelation.deleted_at.is_(None),
    )).all()
    now = local_now()
    for relation in relations:
        if relation.target_id not in retained:
            relation.deleted_at = now
