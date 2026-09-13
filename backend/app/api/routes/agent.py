"""Versioned Agent APIs backed by the same collaborative documents as the UI."""

from __future__ import annotations

from datetime import date
from typing import Any

from fastapi import APIRouter, HTTPException, Query, status

from app.api.routes.todos import todo_read
from app.core.dependencies import CurrentAgent, CurrentSettings, DbSession
from app.models.note import Note
from app.schemas.agent import (
    AgentNoteAppend,
    AgentNoteReplace,
    AgentTaskBodyUpdate,
    AgentTaskCreate,
    AgentTaskMetadataUpdate,
    AgentTaskSummary,
)
from app.services import (
    event_stream,
    note_permission_service,
    note_service,
    task_notification_service,
    todo_service,
)
from app.services.collaboration_agent_service import document_request
from app.services.markdown_import_service import MarkdownImportError, parse_markdown


router = APIRouter(prefix="/agent", tags=["agent"])


def _markdown_document(markdown: str, filename: str) -> dict[str, Any]:
    if not markdown:
        return {"type": "doc", "content": [{"type": "paragraph"}]}
    try:
        content_json, _ = parse_markdown(markdown, filename)
    except MarkdownImportError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return content_json


def _note_seed(note: Note) -> dict[str, Any]:
    return {"title": note.title, "contentJson": note.content_json}


def _task_body_seed(task) -> dict[str, Any]:  # noqa: ANN001
    return {"contentJson": task.content_json, "description": task.description}


def _task_metadata_seed(task) -> dict[str, Any]:  # noqa: ANN001
    return {
        "title": task.title,
        "priority": task.priority.value,
        "dueAt": task.due_at.isoformat() if task.due_at else None,
        "dueEndAt": task.due_end_at.isoformat() if task.due_end_at else None,
        "reminderAt": task.reminder_at.isoformat() if task.reminder_at else None,
        "recurrenceType": task.recurrence_type.value,
        "recurrenceConfig": task.recurrence_config,
        "tags": task.tags,
    }


@router.get("/notes/{note_id}")
def get_agent_note(
    note_id: str, db: DbSession, settings: CurrentSettings, user: CurrentAgent,
) -> dict[str, Any]:
    note = db.get(Note, note_id)
    if note is None or note.deleted_at is not None or not note_permission_service.can_view_personal_note(db, note, user.id):
        raise HTTPException(status_code=404, detail="Note not found")
    snapshot = document_request(
        settings, document_name=f"note:{note.id}", seed=_note_seed(note), actor_id=user.id,
    )
    return {
        **snapshot,
        "id": note.id,
        "folderId": note.folder_id,
        "plainText": note_service.content_to_plain_text(snapshot["contentJson"]),
        "createdAt": note.created_at,
        "updatedAt": note.updated_at,
    }


def _require_note_editor(db, note_id: str, user_id: str) -> Note:  # noqa: ANN001
    note = db.get(Note, note_id)
    if note is None or note.deleted_at is not None or not note_permission_service.can_edit_personal_note(db, note, user_id):
        raise HTTPException(status_code=404, detail="Note not found")
    return note


@router.post("/notes/{note_id}/append")
def append_agent_note(
    note_id: str,
    payload: AgentNoteAppend,
    db: DbSession,
    settings: CurrentSettings,
    user: CurrentAgent,
) -> dict[str, Any]:
    note = _require_note_editor(db, note_id, user.id)
    return document_request(
        settings,
        document_name=f"note:{note.id}",
        seed=_note_seed(note),
        actor_id=user.id,
        operation="append-body",
        expected_version=payload.expected_version,
        content_json=_markdown_document(payload.markdown, "agent-append.md"),
    )


@router.put("/notes/{note_id}")
def replace_agent_note(
    note_id: str,
    payload: AgentNoteReplace,
    db: DbSession,
    settings: CurrentSettings,
    user: CurrentAgent,
) -> dict[str, Any]:
    note = _require_note_editor(db, note_id, user.id)
    return document_request(
        settings,
        document_name=f"note:{note.id}",
        seed=_note_seed(note),
        actor_id=user.id,
        operation="replace-body",
        expected_version=payload.expected_version,
        content_json=_markdown_document(payload.markdown, "agent-note.md"),
        title=payload.title,
    )


@router.get("/tasks", response_model=list[AgentTaskSummary])
def list_agent_tasks(
    db: DbSession,
    user: CurrentAgent,
    q: str | None = Query(default=None),
    list_name: str | None = Query(default=None, alias="list"),
    due_on: date | None = Query(default=None, alias="dueOn"),
    completed: bool | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
) -> list[AgentTaskSummary]:
    tasks = todo_service.list_todos(
        db,
        user.id,
        selected_date=due_on,
        q=q,
        list_name=list_name,
        completed=completed,
        limit=limit,
        offset=offset,
    )
    return [
        AgentTaskSummary(
            id=task.id,
            title=task.title,
            status=task.status,
            my_status=(assignment.status if assignment else None),
            priority=task.priority,
            due_at=task.due_at,
            due_end_at=task.due_end_at,
            list_name=task.list_name,
            tags=task.tags,
            team_id=task.team_id,
            updated_at=task.updated_at,
        )
        for task in tasks
        for assignment in [todo_service.active_assignment(task, user.id)]
    ]


@router.get("/tasks/{task_id}")
def get_agent_task(
    task_id: str, db: DbSession, settings: CurrentSettings, user: CurrentAgent,
) -> dict[str, Any]:
    task = todo_service.get_todo_or_404(db, task_id, user.id)
    body = document_request(
        settings, document_name=f"task:{task.id}", seed=_task_body_seed(task), actor_id=user.id,
    )
    metadata = document_request(
        settings, document_name=f"task-meta:{task.id}", seed=_task_metadata_seed(task), actor_id=user.id,
    )
    result = todo_read(db, task, user.id, include_sources=True).model_dump(mode="json", by_alias=True)
    result.update({
        "contentJson": body["contentJson"],
        "bodyVersion": body["version"],
        "metadataVersion": metadata["version"],
        "title": metadata["metadata"]["title"],
    })
    return result


@router.post("/tasks", status_code=status.HTTP_201_CREATED)
def create_agent_task(
    payload: AgentTaskCreate, db: DbSession, settings: CurrentSettings, user: CurrentAgent,
) -> dict[str, Any]:
    task = todo_service.create_todo(db, payload, user.id, commit=False)
    task_notification_service.notify_task_created(db, task, user.id, commit=False)
    event_stream.queue_task_changed(db, task)
    db.commit()
    return get_agent_task(task.id, db, settings, user)


@router.put("/tasks/{task_id}/body")
def replace_agent_task_body(
    task_id: str,
    payload: AgentTaskBodyUpdate,
    db: DbSession,
    settings: CurrentSettings,
    user: CurrentAgent,
) -> dict[str, Any]:
    task = todo_service.get_todo_or_404(db, task_id, user.id)
    if not todo_service.can_edit_content(db, task, user.id):
        raise HTTPException(status_code=403, detail="没有修改该任务正文的权限")
    return document_request(
        settings,
        document_name=f"task:{task.id}",
        seed=_task_body_seed(task),
        actor_id=user.id,
        operation="replace-body",
        expected_version=payload.expected_version,
        content_json=_markdown_document(payload.markdown, "agent-task.md"),
    )


@router.patch("/tasks/{task_id}/metadata")
def update_agent_task_metadata(
    task_id: str,
    payload: AgentTaskMetadataUpdate,
    db: DbSession,
    settings: CurrentSettings,
    user: CurrentAgent,
) -> dict[str, Any]:
    task = todo_service.get_todo_or_404(db, task_id, user.id)
    if not todo_service.can_edit(db, task, user.id):
        raise HTTPException(status_code=403, detail="没有修改该任务属性的权限")
    due_at = payload.due_at if "due_at" in payload.model_fields_set else task.due_at
    due_end_at = payload.due_end_at if "due_end_at" in payload.model_fields_set else task.due_end_at
    reminder_at = payload.reminder_at if "reminder_at" in payload.model_fields_set else task.reminder_at
    recurrence_type = (
        payload.recurrence_type if "recurrence_type" in payload.model_fields_set else task.recurrence_type
    )
    if reminder_at is not None and due_at is None:
        raise HTTPException(status_code=422, detail="设置提醒前必须先设置截止时间")
    if reminder_at is not None and due_at is not None and reminder_at > due_at:
        raise HTTPException(status_code=422, detail="提醒时间不能晚于截止时间")
    if recurrence_type.value != "NONE" and due_at is None:
        raise HTTPException(status_code=422, detail="重复待办必须设置执行时间")
    if due_end_at is not None and (due_at is None or due_end_at < due_at):
        raise HTTPException(status_code=422, detail="结束时间不能早于开始时间")
    values = payload.model_dump(
        exclude={"expected_version"}, exclude_unset=True, mode="json", by_alias=True,
    )
    return document_request(
        settings,
        document_name=f"task-meta:{task.id}",
        seed=_task_metadata_seed(task),
        actor_id=user.id,
        operation="update-metadata",
        expected_version=payload.expected_version,
        metadata=values,
    )
