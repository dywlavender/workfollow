from datetime import date
import logging
from typing import Annotated

import secrets

from fastapi import APIRouter, Header, HTTPException, Query, Response, status
from sqlalchemy.orm import Session

from app.core.dependencies import CurrentSettings, CurrentUser, DbSession
from app.models.todo import Todo, TodoAssignmentStatus, TodoStatus
from app.schemas.resource_relation import TaskBriefPermissions, TaskBriefRead
from app.schemas.todo import (
    ReminderAcknowledge,
    TodoAssigneesUpdate,
    TodoAssignmentRead,
    TodoCompleteResult,
    TodoCollaborationMetadata,
    TodoCollaborationSnapshot,
    TodoCreate,
    TodoListCreate,
    TodoListDeleteResult,
    TodoListMove,
    TodoListRead,
    TodoListUpdate,
    TodoMyStatusUpdate,
    TodoPermissions,
    TodoRead,
    TodoTransfer,
    TodoProjectionUpdate,
)
from app.services import audit_service, event_stream, resource_relation_service, task_notification_service, todo_list_service, todo_service
from app.services.content_projection import content_json_semantically_equal


router = APIRouter(tags=["tasks"])
logger = logging.getLogger(__name__)


def todo_list_read(item) -> TodoListRead:  # noqa: ANN001
    return TodoListRead(
        id=item.id,
        name=item.name,
        sort_order=item.sort_order,
        protected=todo_list_service.is_protected_name(item.name),
    )


@router.get("/lists", response_model=list[TodoListRead])
def get_todo_lists(db: DbSession, user: CurrentUser) -> list[TodoListRead]:
    items = todo_list_service.list_catalog(db)
    db.commit()
    return [todo_list_read(item) for item in items]


@router.post("/lists", response_model=TodoListRead, status_code=status.HTTP_201_CREATED)
def post_todo_list(payload: TodoListCreate, db: DbSession, user: CurrentUser) -> TodoListRead:
    return todo_list_read(todo_list_service.create(db, payload.name, user.id))


@router.put("/lists/{list_id}", response_model=TodoListRead)
def put_todo_list(list_id: str, payload: TodoListUpdate, db: DbSession, user: CurrentUser) -> TodoListRead:
    item, _moved_count = todo_list_service.rename(db, list_id, payload.name)
    return todo_list_read(item)


@router.delete("/lists/{list_id}", response_model=TodoListDeleteResult)
def delete_todo_list(list_id: str, db: DbSession, user: CurrentUser) -> TodoListDeleteResult:
    item = todo_list_service.get_or_404(db, list_id)
    deleted_name = item.name
    moved_count = todo_list_service.delete(db, list_id)
    return TodoListDeleteResult(
        name=deleted_name,
        fallback_list_name=todo_list_service.FALLBACK_TODO_LIST_NAME,
        moved_task_count=moved_count,
    )


def todo_read(db: Session, todo, user_id: str, *, include_sources: bool = False) -> TodoRead:  # noqa: ANN001
    active = [assignment for assignment in todo.assignments if assignment.active]
    mine = next((assignment for assignment in active if assignment.user_id == user_id), None)
    editable = todo_service.can_edit(db, todo, user_id)
    result = TodoRead.model_validate(todo)
    return result.model_copy(update={
        "assignments": [TodoAssignmentRead.model_validate(item) for item in active],
        "my_assignment": TodoAssignmentRead.model_validate(mine) if mine else None,
        "completed_assignments": sum(item.status.value == "DONE" for item in active),
        "total_assignments": len(active),
        "permissions": TodoPermissions(
            editable=editable,
            content_editable=editable or todo_service.can_edit_content(db, todo, user_id),
            deletable=todo.creator_id == user_id,
            assignable=todo_service.can_assign(db, todo, user_id),
            completable=mine is not None and todo.status != TodoStatus.ABANDONED,
        ),
        "sources": resource_relation_service.task_sources_for_user(db, todo.id, user_id)
        if include_sources else [],
    })


@router.get("", response_model=list[TodoRead])
def get_todos(
    db: DbSession,
    user: CurrentUser,
    view: str | None = Query(default=None),
    selected_date: date | None = Query(default=None, alias="date"),
    q: str | None = Query(default=None),
    list_name: str | None = Query(default=None, alias="list"),
    limit: int = Query(default=100, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
) -> list[TodoRead]:
    return [todo_read(db, todo, user.id) for todo in todo_service.list_todos(
        db, user.id, view=view, selected_date=selected_date, q=q, list_name=list_name, limit=limit, offset=offset
    )]


@router.get("/reminders/due", response_model=list[TodoRead])
def get_due_reminders(db: DbSession, user: CurrentUser) -> list[TodoRead]:
    return [todo_read(db, todo, user.id) for todo in todo_service.due_reminders(db, user.id)]


@router.get("/brief", response_model=list[TaskBriefRead])
def get_task_briefs(
    db: DbSession,
    user: CurrentUser,
    ids: Annotated[list[str], Query()],
) -> list[TaskBriefRead]:
    unique_ids = list(dict.fromkeys(ids))
    if len(unique_ids) > 100:
        raise HTTPException(status_code=422, detail="一次最多读取 100 个任务")
    result: list[TaskBriefRead] = []
    for task_id in unique_ids:
        todo = db.get(Todo, task_id)
        if todo is None:
            result.append(TaskBriefRead(id=task_id, accessible=False, deleted=True))
            continue
        if not todo_service.can_view(db, todo, user.id):
            result.append(TaskBriefRead(id=task_id, accessible=False))
            continue
        assignment = todo_service.active_assignment(todo, user.id)
        result.append(TaskBriefRead(
            id=todo.id,
            accessible=True,
            title=todo.title,
            status=todo.status,
            priority=todo.priority,
            due_at=todo.due_at,
            assignees=[item.user for item in todo.assignments if item.active],
            permissions=TaskBriefPermissions(
                completable=assignment is not None and todo.status != TodoStatus.ABANDONED
            ),
        ))
    return result


@router.get("/{todo_id}", response_model=TodoRead)
def get_todo(todo_id: str, db: DbSession, user: CurrentUser) -> TodoRead:
    return todo_read(
        db, todo_service.get_todo_or_404(db, todo_id, user.id), user.id, include_sources=True
    )


@router.put("/{todo_id}/collaboration-snapshot", status_code=status.HTTP_204_NO_CONTENT, include_in_schema=False)
def put_collaboration_snapshot(
    todo_id: str,
    payload: TodoCollaborationSnapshot,
    db: DbSession,
    settings: CurrentSettings,
    internal_token: str | None = Header(default=None, alias="X-WorkFollow-Collaboration-Token"),
) -> Response:
    """Persist the merged Yjs document as the normal task projection.

    This endpoint is intentionally not a browser API.  Hocuspocus runs beside
    FastAPI and authenticates every WebSocket connection through the normal
    session cookie before it can produce a snapshot.  Keeping the bridge
    internal prevents a client from bypassing task permissions while still
    letting the existing search/list/read APIs consume the latest body.
    """
    configured = settings.collaboration_internal_token
    if not configured or not internal_token or not secrets.compare_digest(internal_token, configured):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="协同服务未授权")

    todo = db.get(Todo, todo_id)
    if todo is None:
        # The collaboration document can outlive a deleted task briefly.  A
        # no-op keeps the provider from retrying a snapshot forever.
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    actors = set(payload.actor_ids)
    if payload.actor_id:
        actors.add(payload.actor_id)
    if any(not todo_service.can_edit_content(db, todo, actor_id) for actor_id in actors):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="没有修改该任务正文的权限")

    # Links/references are part of the collaborative body, not a second HTTP
    # side channel. Reconcile their backlink rows in the same transaction as
    # the body projection so a failed projection cannot leave a dangling edge.
    # Do this even for a semantically identical snapshot: block ids are editor
    # metadata ignored by the no-op check, but they still identify the exact
    # paragraph a backlink should open.
    relation_actor = payload.actor_id or next(iter(payload.actor_ids), None) or todo.creator_id
    resource_relation_service.sync_task_relations(
        db,
        todo.id,
        relation_actor,
        resource_relation_service.resource_references_in_document(payload.content_json),
    )
    # A Yjs provider may replay the current document when a tab opens or
    # switches away. Treat an identical projection as a true no-op before
    # touching the ORM object; otherwise SQLAlchemy's ``onupdate`` timestamp
    # and search index make a read-only open look like a task edit. The
    # relation reconciliation above is committed separately so a block-only
    # move can still update the backlink anchor without notifying the task.
    if content_json_semantically_equal(payload.content_json, todo.content_json):
        db.commit()
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    before = task_notification_service.task_change_snapshot(todo)
    updated = todo_service.update_todo(
        db,
        todo,
        TodoProjectionUpdate(content_json=payload.content_json),
        payload.actor_id,
        commit=False,
    )
    if not task_notification_service.task_changes(
        before,
        task_notification_service.task_change_snapshot(updated),
    ):
        # A collaboration handshake or an editor initialization can submit
        # the same projection without any user edit. Do not fan that no-op out
        # as a task-change event.
        db.commit()
        return Response(status_code=status.HTTP_204_NO_CONTENT)
    notification_actor = task_notification_service.preferred_task_notification_actor(
        db, updated, payload.actor_ids, payload.actor_id,
    )
    if notification_actor:
        task_notification_service.notify_task_updated(
            db, updated, notification_actor, before, commit=False
        )
    event_stream.queue_task_changed(db, updated)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.put("/{todo_id}/collaboration-metadata", status_code=status.HTTP_204_NO_CONTENT, include_in_schema=False)
def put_collaboration_metadata(
    todo_id: str,
    payload: TodoCollaborationMetadata,
    db: DbSession,
    settings: CurrentSettings,
    internal_token: str | None = Header(default=None, alias="X-WorkFollow-Collaboration-Token"),
) -> Response:
    """Persist the shared Yjs metadata projection.

    The collaboration service authenticates the WebSocket before it can write
    here. ``actor_id`` is still passed through the normal task update service so
    metadata remains restricted to creators, owners, admins, and root users.
    """
    configured = settings.collaboration_internal_token
    if not configured or not internal_token or not secrets.compare_digest(internal_token, configured):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="协同服务未授权")

    todo = db.get(Todo, todo_id)
    if todo is None:
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    actors = set(payload.actor_ids)
    if payload.actor_id:
        actors.add(payload.actor_id)
    if any(not todo_service.can_edit(db, todo, actor_id) for actor_id in actors):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="没有修改该任务属性的权限")

    before = task_notification_service.task_change_snapshot(todo)
    values = payload.model_dump(exclude={"actor_id", "actor_ids"})
    if values.get("list_name") is None:
        values.pop("list_name", None)
    # A title field may be empty briefly while the shared Y.Text is being
    # edited. Keep the last valid SQL title until a non-empty value arrives.
    if not values["title"]:
        values["title"] = todo.title

    current_values = {
        "title": todo.title,
        "due_at": todo.due_at,
        "due_end_at": todo.due_end_at,
        "priority": todo.priority,
        "reminder_at": todo.reminder_at,
        "recurrence_type": todo.recurrence_type,
        "recurrence_config": todo.recurrence_config,
        "tags": list(todo.tags or []),
    }
    comparable_values = {
        key: value for key, value in values.items()
        if key in current_values
    }
    if "recurrence_type" in comparable_values and getattr(comparable_values["recurrence_type"], "value", comparable_values["recurrence_type"]) == "NONE":
        comparable_values["recurrence_config"] = None
    if "tags" in comparable_values:
        comparable_values["tags"] = list(dict.fromkeys(comparable_values["tags"] or []))
    if comparable_values and all(current_values[key] == value for key, value in comparable_values.items()):
        return Response(status_code=status.HTTP_204_NO_CONTENT)
    updated = todo_service.update_todo(
        db,
        todo,
        TodoProjectionUpdate(**values),
        payload.actor_id,
        commit=False,
    )
    if not task_notification_service.task_changes(
        before,
        task_notification_service.task_change_snapshot(updated),
    ):
        # Metadata can be projected again when a task detail view is opened;
        # identical values are not an update and must not emit notifications.
        db.commit()
        return Response(status_code=status.HTTP_204_NO_CONTENT)
    notification_actor = task_notification_service.preferred_task_notification_actor(
        db, updated, payload.actor_ids, payload.actor_id,
    )
    if notification_actor:
        task_notification_service.notify_task_updated(
            db, updated, notification_actor, before, commit=False
        )
    event_stream.queue_task_changed(db, updated)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("", response_model=TodoRead, status_code=status.HTTP_201_CREATED)
def post_todo(payload: TodoCreate, db: DbSession, user: CurrentUser) -> TodoRead:
    logger.info(
        "【任务接口入口】创建任务 actor=%s assignee_count=%s title=%s",
        user.username,
        len(payload.assignee_ids or [user.id]),
        payload.title,
    )
    todo = todo_service.create_todo(db, payload, user.id, commit=False)
    task_notification_service.notify_task_created(db, todo, user.id, commit=False)
    if todo.team_id:
        audit_service.record_audit(
            db,
            actor_user_id=user.id,
            action="TASK_ASSIGNED",
            resource_type="TASK",
            resource_id=todo.id,
            team_id=todo.team_id,
            metadata_json={"assigneeIds": [item.user_id for item in todo.assignments if item.active]},
        )
    event_stream.queue_task_changed(db, todo)
    db.commit()
    return todo_read(db, todo, user.id, include_sources=True)


@router.put("/{todo_id}/list", response_model=TodoRead)
def put_todo_list_location(todo_id: str, payload: TodoListMove, db: DbSession, user: CurrentUser) -> TodoRead:
    """Move a task as a named transaction; task fields are Yjs-owned."""
    todo = todo_service.get_todo_or_404(db, todo_id, user.id)
    before = task_notification_service.task_change_snapshot(todo)
    updated = todo_service.update_todo(
        db, todo, TodoProjectionUpdate(list_name=payload.list_name), user.id, commit=False
    )
    task_notification_service.notify_task_updated(
        db, updated, user.id, before, commit=False
    )
    event_stream.queue_task_changed(db, updated)
    db.commit()
    return todo_read(db, updated, user.id)


@router.post("/{todo_id}/complete", response_model=TodoCompleteResult)
def complete_todo(todo_id: str, db: DbSession, user: CurrentUser) -> TodoCompleteResult:
    logger.info("【任务接口入口】完成任务 actor=%s task_id=%s", user.username, todo_id)
    current = todo_service.get_todo_or_404(db, todo_id, user.id)
    assignment = todo_service.active_assignment(current, user.id)
    was_done = assignment is None or assignment.status == TodoAssignmentStatus.DONE
    todo, next_todo = todo_service.complete_todo(db, current, user.id, commit=False)
    if not was_done:
        if todo.status == TodoStatus.DONE:
            task_notification_service.notify_task_completed(db, todo, user.id, commit=False)
        else:
            task_notification_service.notify_task_assignment_completed(db, todo, user.id, commit=False)
    event_stream.queue_task_changed(db, todo)
    if next_todo:
        event_stream.queue_task_changed(db, next_todo)
    db.commit()
    return TodoCompleteResult(
        todo=todo_read(db, todo, user.id),
        next_todo=todo_read(db, next_todo, user.id) if next_todo else None,
    )


@router.post("/{todo_id}/restore", response_model=TodoRead)
def restore_todo(todo_id: str, db: DbSession, user: CurrentUser) -> TodoRead:
    current = todo_service.get_todo_or_404(db, todo_id, user.id)
    before = task_notification_service.task_change_snapshot(current)
    todo = todo_service.restore_todo(
        db, current, user.id, commit=False
    )
    task_notification_service.notify_task_updated(
        db, todo, user.id, before, commit=False
    )
    event_stream.queue_task_changed(db, todo)
    db.commit()
    return todo_read(db, todo, user.id)


@router.put("/{todo_id}/my-status", response_model=TodoRead)
def put_my_status(todo_id: str, payload: TodoMyStatusUpdate, db: DbSession, user: CurrentUser) -> TodoRead:
    logger.info(
        "【任务接口入口】更新任务状态 actor=%s task_id=%s status=%s",
        user.username,
        todo_id,
        payload.status.value,
    )
    current = todo_service.get_todo_or_404(db, todo_id, user.id)
    assignment = todo_service.active_assignment(current, user.id)
    was_done = assignment is None or assignment.status == TodoAssignmentStatus.DONE
    todo, next_todo = todo_service.update_my_status(
        db, current, user.id, payload.status, commit=False
    )
    if payload.status == TodoAssignmentStatus.DONE and not was_done:
        if todo.status == TodoStatus.DONE:
            task_notification_service.notify_task_completed(db, todo, user.id, commit=False)
        else:
            task_notification_service.notify_task_assignment_completed(db, todo, user.id, commit=False)
    event_stream.queue_task_changed(db, todo)
    if next_todo:
        event_stream.queue_task_changed(db, next_todo)
    db.commit()
    return todo_read(db, todo, user.id)


@router.put("/{todo_id}/assignees", response_model=TodoRead)
def put_assignees(todo_id: str, payload: TodoAssigneesUpdate, db: DbSession, user: CurrentUser) -> TodoRead:
    logger.info(
        "【任务接口入口】修改任务成员 actor=%s task_id=%s assignee_count=%s",
        user.username,
        todo_id,
        len(payload.assignee_ids),
    )
    current = todo_service.get_todo_or_404(db, todo_id, user.id)
    previous = {item.user_id for item in current.assignments if item.active}
    todo = todo_service.update_assignees(db, current, user.id, payload.assignee_ids, commit=False)
    current_ids = {item.user_id for item in todo.assignments if item.active}
    task_notification_service.notify_assignees_changed(
        db, todo, user.id, previous, current_ids, commit=False
    )
    event_stream.queue_task_changed(db, todo)
    db.commit()
    return todo_read(db, todo, user.id)


@router.post("/{todo_id}/abandon", response_model=TodoRead)
def abandon_todo(todo_id: str, db: DbSession, user: CurrentUser) -> TodoRead:
    logger.info("【任务接口入口】取消任务 actor=%s task_id=%s", user.username, todo_id)
    todo = todo_service.get_todo_or_404(db, todo_id, user.id)
    todo_service.require_creator(todo, user.id)
    participant_ids = {item.user_id for item in todo.assignments if item.active}
    cancelled = todo_service.abandon_todo(db, todo, commit=False)
    task_notification_service.notify_task_cancelled(
        db, cancelled, user.id, participant_ids, commit=False
    )
    event_stream.queue_task_changed(db, cancelled)
    db.commit()
    return todo_read(db, cancelled, user.id)


@router.post("/{todo_id}/reminded", response_model=TodoRead)
def mark_reminded(todo_id: str, payload: ReminderAcknowledge, db: DbSession, user: CurrentUser) -> TodoRead:
    todo = todo_service.acknowledge_reminder(
        db,
        todo_service.get_todo_or_404(db, todo_id, user.id),
        payload.reminded_at,
        commit=False,
    )
    event_stream.queue_task_changed(db, todo)
    db.commit()
    return todo_read(db, todo, user.id)


@router.delete("/{todo_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_todo(todo_id: str, db: DbSession, user: CurrentUser) -> Response:
    todo = todo_service.get_todo_or_404(db, todo_id, user.id)
    todo_service.require_creator(todo, user.id)
    event_stream.queue_task_changed(db, todo, deleted=True)
    db.delete(todo)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/{todo_id}/transfer", response_model=TodoRead)
def transfer_todo(todo_id: str, payload: TodoTransfer, db: DbSession, user: CurrentUser) -> TodoRead:
    """Compatibility endpoint: assignment now updates the same Task row."""
    logger.info(
        "【任务接口入口】移交任务 actor=%s task_id=%s assignee_count=%s",
        user.username,
        todo_id,
        len(payload.assignee_ids),
    )
    todo = todo_service.get_todo_or_404(db, todo_id, user.id)
    if todo.status != TodoStatus.TODO:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="只有进行中的待办可以移交团队")
    assignee_ids = payload.assignee_ids or [user.id]
    previous = {item.user_id for item in todo.assignments if item.active}
    task = todo_service.update_assignees(db, todo, user.id, assignee_ids, commit=False)
    if task.team_id != payload.team_id:
        raise HTTPException(status_code=422, detail="指派成员必须属于指定团队")
    current_ids = {item.user_id for item in task.assignments if item.active}
    task_notification_service.notify_assignees_changed(
        db, task, user.id, previous, current_ids, commit=False
    )
    event_stream.queue_task_changed(db, task)
    audit_service.record_audit(
        db, actor_user_id=user.id, action="TASK_ASSIGNED", resource_type="TASK", resource_id=task.id,
        team_id=payload.team_id,
        metadata_json={
            "assigneeIds": [assignment.user_id for assignment in task.assignments],
        },
    )
    db.commit()
    return todo_read(db, task, user.id)
