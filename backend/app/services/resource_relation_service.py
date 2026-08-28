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
        # A task member may edit the collaborative body, including links and
        # references inserted from the editor. Metadata/assignment actions
        # still use ``can_edit`` at their own endpoints.
        return task is not None and todo_service.can_edit_content(db, task, user_id)
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
        # ``REFERENCES`` rows are the reverse-direction graph edges created
        # from a collaborative document.  They are not task provenance and
        # must not be shown as duplicate "来源" entries alongside the durable
        # ``CREATED_FROM`` relation created when a task originates in a note.
        ResourceRelation.relation_type == RelationType.CREATED_FROM,
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


ResourceReference = tuple[ResourceType, str, str | None]


def resource_references_in_document(content_json: Mapping[str, Any] | None) -> set[ResourceReference]:
    """Return resource identities represented by the collaborative document.

    The block id is carried down to inline marks so a backlink can still open
    the originating paragraph.  The parser deliberately reads only our
    identity attributes; visible text is not a relation and must never create
    a database edge by accident.
    """
    references: set[ResourceReference] = set()

    def string_value(value: Any) -> str | None:
        return value if isinstance(value, str) and value else None

    def visit(value: Any, inherited_block_id: str | None = None) -> None:
        if isinstance(value, Mapping):
            attrs = value.get("attrs")
            block_id = inherited_block_id
            if isinstance(attrs, Mapping):
                block_id = string_value(attrs.get("blockId")) or inherited_block_id
            node_type = value.get("type")
            if node_type == "taskReference" and isinstance(attrs, Mapping):
                task_id = string_value(attrs.get("taskId"))
                if task_id:
                    references.add((ResourceType.TASK, task_id, block_id))
            marks = value.get("marks")
            if isinstance(marks, list):
                for mark in marks:
                    if not isinstance(mark, Mapping):
                        continue
                    mark_attrs = mark.get("attrs")
                    if not isinstance(mark_attrs, Mapping):
                        continue
                    mark_type = mark.get("type")
                    if mark_type == "taskLink":
                        task_id = string_value(mark_attrs.get("taskId"))
                        if task_id:
                            references.add((ResourceType.TASK, task_id, block_id))
                    elif mark_type == "noteLink":
                        note_id = string_value(mark_attrs.get("noteId"))
                        if note_id:
                            references.add((ResourceType.PERSONAL_NOTE, note_id, block_id))
            # Do not recurse into attrs/marks: they are identity metadata, not
            # nested document nodes. Passing the current block id through the
            # content tree keeps inline references attached to their block.
            for key, child in value.items():
                if key in {"attrs", "marks"}:
                    continue
                visit(child, block_id)
        elif isinstance(value, list):
            for child in value:
                visit(child, inherited_block_id)

    visit(content_json)
    return references


def task_ids_in_document(content_json: Mapping[str, Any] | None) -> set[str]:
    return {
        resource_id
        for resource_type, resource_id, _block_id in resource_references_in_document(content_json)
        if resource_type == ResourceType.TASK
    }


def _find_reference_relation(
    relations: Iterable[ResourceRelation],
    target_type: ResourceType,
    target_id: str,
    block_id: str | None,
    used_relation_ids: set[str],
) -> ResourceRelation | None:
    exact: ResourceRelation | None = None
    fallback: ResourceRelation | None = None
    for relation in relations:
        if relation.id in used_relation_ids:
            continue
        if relation.target_type != target_type or relation.target_id != target_id:
            continue
        if relation.source_block_id == block_id:
            exact = relation
            break
        # Older relation rows may not have a block id while the document now
        # does (or vice versa). Reuse one existing edge rather than creating a
        # duplicate; the next exact projection will update its block id.
        if fallback is None and (block_id is None or relation.source_block_id is None):
            fallback = relation
    return exact or fallback


def _sync_document_relations(
    db: Session,
    *,
    source_type: ResourceType,
    source_id: str,
    actor_id: str,
    references: Iterable[ResourceReference],
) -> None:
    retained = {
        (target_type, target_id, block_id)
        for target_type, target_id, block_id in references
        if target_type in (ResourceType.TASK, ResourceType.PERSONAL_NOTE, ResourceType.TEAM_NOTE)
        and not (target_type == source_type and target_id == source_id)
    }
    target_pairs = {(target_type, target_id) for target_type, target_id, _ in retained}
    active_relations = list(db.scalars(select(ResourceRelation).where(
        ResourceRelation.source_type == source_type,
        ResourceRelation.source_id == source_id,
        ResourceRelation.relation_type == RelationType.REFERENCES,
        ResourceRelation.deleted_at.is_(None),
    )))
    now = local_now()
    for relation in active_relations:
        # A block-aware relation is tied to an exact occurrence. For legacy
        # rows without a block id, retaining the target keeps a manually-
        # created relation alive during the one-time migration.
        exact_match = (relation.target_type, relation.target_id, relation.source_block_id) in retained
        target_match = (relation.target_type, relation.target_id) in target_pairs
        if not exact_match and not (relation.source_block_id is None and target_match):
            relation.deleted_at = now

    by_target = active_relations
    used_relation_ids: set[str] = set()
    for target_type, target_id, block_id in retained:
        if not can_view_resource(db, target_type, target_id, actor_id):
            # A document may contain an id copied from a resource the editor
            # can no longer access. Keep it in Yjs, but never expose a new
            # relation/backlink row for an inaccessible resource.
            continue
        relation = _find_reference_relation(
            by_target, target_type, target_id, block_id, used_relation_ids,
        )
        if relation is not None:
            used_relation_ids.add(relation.id)
            relation.deleted_at = None
            # Reusing a legacy/fallback row should also clear an obsolete
            # block id when the current document occurrence no longer has one;
            # otherwise a backlink can keep opening a paragraph that no longer
            # contains the reference.
            relation.source_block_id = block_id
            continue
        relation = ResourceRelation(
            source_type=source_type,
            source_id=source_id,
            source_block_id=block_id,
            target_type=target_type,
            target_id=target_id,
            relation_type=RelationType.REFERENCES,
            created_by_id=actor_id,
        )
        db.add(relation)
        by_target.append(relation)


def sync_personal_note_relations(
    db: Session,
    note_id: str,
    user_id: str,
    retained_task_ids: Iterable[str],
    references: Iterable[ResourceReference] | None = None,
) -> None:
    # Keep the old argument for callers that only have the task id set. The
    # projection path supplies block-aware references; either form remains
    # safe and idempotent.
    document_references = set(references or {
        (ResourceType.TASK, task_id, None) for task_id in retained_task_ids
    })
    retained_task_id_set = {
        target_id
        for target_type, target_id, _block_id in document_references
        if target_type == ResourceType.TASK
    }
    # CREATED_FROM is the durable backlink created together with a task from a
    # note. It is still tied to the note's source block, so removing that task
    # identity from the note must retire the source relation as well. Keep this
    # legacy relation type separate from the document-owned REFERENCES edges.
    source_relations = db.scalars(select(ResourceRelation).where(
        ResourceRelation.source_type == ResourceType.PERSONAL_NOTE,
        ResourceRelation.source_id == note_id,
        ResourceRelation.target_type == ResourceType.TASK,
        ResourceRelation.relation_type == RelationType.CREATED_FROM,
        ResourceRelation.created_by_id == user_id,
        ResourceRelation.deleted_at.is_(None),
    )).all()
    now = local_now()
    for relation in source_relations:
        if relation.target_id not in retained_task_id_set:
            relation.deleted_at = now
    _sync_document_relations(
        db,
        source_type=ResourceType.PERSONAL_NOTE,
        source_id=note_id,
        actor_id=user_id,
        references=document_references,
    )


def sync_team_note_relations(
    db: Session,
    note_id: str,
    user_id: str,
    references: Iterable[ResourceReference],
) -> None:
    _sync_document_relations(
        db,
        source_type=ResourceType.TEAM_NOTE,
        source_id=note_id,
        actor_id=user_id,
        references=references,
    )


def sync_task_relations(
    db: Session,
    task_id: str,
    user_id: str,
    references: Iterable[ResourceReference],
) -> None:
    _sync_document_relations(
        db,
        source_type=ResourceType.TASK,
        source_id=task_id,
        actor_id=user_id,
        references=references,
    )
