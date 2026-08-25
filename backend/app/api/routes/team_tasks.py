"""Compatibility routes for clients created before tasks were unified.

These endpoints deliberately operate on ``Todo`` + ``TodoAssignment``.  They
must never create or mutate the legacy ``team_tasks`` tables.
"""
from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query, Response, status
from sqlalchemy import select
from sqlalchemy.orm import joinedload

from app.core.dependencies import CurrentUser, DbSession
from app.models.team import TeamMemberRole
from app.models.todo import Todo, TodoAssignment, TodoAssignmentStatus, TodoStatus
from app.schemas.team import (
    MyTaskRead,
    TeamTaskAssignmentRead,
    TeamTaskAssignmentStatusUpdate,
    TeamTaskCreate,
    TeamTaskRead,
    TeamTaskUpdate,
)
from app.schemas.todo import TodoCreate, TodoUpdate
from app.services import event_stream, task_notification_service, team_service, todo_service
from app.services.team_note_service import attachment_reads


router = APIRouter(tags=["legacy-team-task-compatibility"], include_in_schema=False)


def _assignment_read(assignment: TodoAssignment) -> TeamTaskAssignmentRead:
    return TeamTaskAssignmentRead(
        id=assignment.id,
        team_task_id=assignment.task_id,
        user_id=assignment.user_id,
        assigned_by_id=assignment.assigned_by_id,
        status="DONE" if assignment.status == TodoAssignmentStatus.DONE else "TODO",
        assigned_at=assignment.assigned_at,
        completed_at=assignment.completed_at,
        created_at=assignment.created_at,
        updated_at=assignment.updated_at,
        user=assignment.user,
    )


def task_read(db, task: Todo) -> TeamTaskRead:  # noqa: ANN001
    assignments = [_assignment_read(item) for item in task.assignments if item.active]
    completed = sum(item.status.value == "DONE" for item in assignments)
    total = len(assignments)
    return TeamTaskRead(
        id=task.id,
        team_id=task.team_id or "",
        creator_id=task.creator_id,
        title=task.title,
        description=task.description,
        content_json=task.content_json,
        priority=task.priority,
        due_at=task.due_at,
        due_end_at=task.due_end_at,
        reminder_at=task.reminder_at,
        recurrence_type=task.recurrence_type,
        recurrence_config=task.recurrence_config,
        attachment_ids=list(task.attachment_ids or []),
        attachments=attachment_reads(db, list(task.attachment_ids or [])),
        list_name=task.list_name,
        tags=list(task.tags or []),
        status="CANCELLED" if task.status == TodoStatus.ABANDONED else (
            "COMPLETED" if task.status == TodoStatus.DONE else "ACTIVE"
        ),
        completed_at=task.completed_at,
        cancelled_at=task.updated_at if task.status == TodoStatus.ABANDONED else None,
        created_at=task.created_at,
        updated_at=task.updated_at,
        assignments=assignments,
        total_assignments=total,
        completed_assignments=completed,
        progress=round(completed * 100 / total) if total else 0,
    )


def _team_task(db, team_id: str, task_id: str, user_id: str) -> Todo:  # noqa: ANN001
    team_service.require_member(db, team_id, user_id)
    task = todo_service.get_todo_or_404(db, task_id, user_id)
    # A self-only task created through the retired endpoint had no team_id. It
    # remains readable only by its creator; real collaborative tasks must match.
    if task.team_id not in (None, team_id) or (task.team_id is None and task.creator_id != user_id):
        raise HTTPException(status_code=404, detail="Task not found")
    return task


@router.get("/teams/{team_id}/tasks", response_model=list[TeamTaskRead])
def list_tasks(
    team_id: str,
    db: DbSession,
    user: CurrentUser,
    limit: int = Query(default=100, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
) -> list[TeamTaskRead]:
    team_service.require_member(db, team_id, user.id)
    assigned = todo_service.list_todos(db, user.id, limit=limit, offset=offset)
    created = todo_service.list_todos(db, user.id, view="assigned-by-me", limit=limit, offset=offset)
    tasks = {task.id: task for task in [*assigned, *created] if task.team_id == team_id}
    return [task_read(db, task) for task in tasks.values()]


@router.post("/teams/{team_id}/tasks", response_model=TeamTaskRead, status_code=status.HTTP_201_CREATED)
def create_task(team_id: str, payload: TeamTaskCreate, db: DbSession, user: CurrentUser) -> TeamTaskRead:
    # Keep the retired endpoint at least as strict as its original contract.
    # MEMBER users create their own tasks through /tasks, but cannot invoke an
    # ADMIN team-task API even when they only select themselves.
    team_service.require_role(db, team_id, user.id, TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
    assignee_ids = payload.assignee_ids or [user.id]
    task = todo_service.create_todo(db, TodoCreate(
        title=payload.title,
        description=payload.description,
        content_json=payload.content_json,
        attachment_ids=payload.attachment_ids,
        priority=payload.priority,
        due_at=payload.due_at,
        due_end_at=payload.due_end_at,
        reminder_at=payload.reminder_at,
        recurrence_type=payload.recurrence_type,
        recurrence_config=payload.recurrence_config,
        list_name=payload.list_name,
        tags=payload.tags,
        team_id=team_id,
        assignee_ids=assignee_ids,
    ), user.id, commit=False)
    if task.team_id not in (None, team_id):
        raise HTTPException(status_code=422, detail="指派成员必须属于指定团队")
    task_notification_service.notify_task_created(db, task, user.id, commit=False)
    event_stream.queue_task_changed(db, task)
    db.commit()
    return task_read(db, task)


@router.get("/teams/{team_id}/tasks/{task_id}", response_model=TeamTaskRead)
def get_task(team_id: str, task_id: str, db: DbSession, user: CurrentUser) -> TeamTaskRead:
    return task_read(db, _team_task(db, team_id, task_id, user.id))


@router.put("/teams/{team_id}/tasks/{task_id}", response_model=TeamTaskRead)
def update_task(
    team_id: str,
    task_id: str,
    payload: TeamTaskUpdate,
    db: DbSession,
    user: CurrentUser,
) -> TeamTaskRead:
    task = _team_task(db, team_id, task_id, user.id)
    todo_service.require_creator(task, user.id)
    before = task_notification_service.task_change_snapshot(task)
    changes = payload.model_dump(exclude_unset=True)
    assignee_ids = changes.pop("assignee_ids", None)
    requested_status = changes.pop("status", None)
    changes.pop("client_request_id", None)
    if changes:
        task = todo_service.update_todo(db, task, TodoUpdate(**changes), user.id, commit=False)
        task_notification_service.notify_task_updated(
            db, task, user.id, before, commit=False
        )
    if assignee_ids is not None:
        previous_ids = {item.user_id for item in task.assignments if item.active}
        task = todo_service.update_assignees(db, task, user.id, assignee_ids, commit=False)
        current_ids = {item.user_id for item in task.assignments if item.active}
        task_notification_service.notify_assignees_changed(
            db, task, user.id, previous_ids, current_ids, commit=False
        )
    if requested_status is not None and requested_status.value == "CANCELLED":
        participant_ids = {item.user_id for item in task.assignments if item.active}
        task = todo_service.abandon_todo(db, task, commit=False)
        task_notification_service.notify_task_cancelled(
            db, task, user.id, participant_ids, commit=False
        )
    event_stream.queue_task_changed(db, task)
    db.commit()
    return task_read(db, task)


@router.delete("/teams/{team_id}/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task(team_id: str, task_id: str, db: DbSession, user: CurrentUser) -> Response:
    task = _team_task(db, team_id, task_id, user.id)
    todo_service.require_creator(task, user.id)
    participant_ids = {item.user_id for item in task.assignments if item.active}
    cancelled = todo_service.abandon_todo(db, task, commit=False)
    task_notification_service.notify_task_cancelled(
        db, cancelled, user.id, participant_ids, commit=False
    )
    event_stream.queue_task_changed(db, cancelled)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/team-task-assignments/{assignment_id}/status", response_model=TeamTaskAssignmentRead)
def update_assignment_status(
    assignment_id: str,
    payload: TeamTaskAssignmentStatusUpdate,
    db: DbSession,
    user: CurrentUser,
) -> TeamTaskAssignmentRead:
    assignment = db.scalar(select(TodoAssignment).options(
        joinedload(TodoAssignment.user), joinedload(TodoAssignment.task)
    ).where(TodoAssignment.id == assignment_id, TodoAssignment.active.is_(True)))
    if assignment is None:
        raise HTTPException(status_code=404, detail="Task assignment not found")
    if assignment.user_id != user.id:
        raise HTTPException(status_code=403, detail="成员只能修改自己的任务分配状态")
    was_done = assignment.status == TodoAssignmentStatus.DONE
    updated_task, next_task = todo_service.update_my_status(
        db,
        todo_service.get_todo_or_404(db, assignment.task_id, user.id),
        user.id,
        TodoAssignmentStatus.DONE if payload.status.value == "DONE" else TodoAssignmentStatus.TODO,
        commit=False,
    )
    if payload.status.value == "DONE" and not was_done:
        if updated_task.status == TodoStatus.DONE:
            task_notification_service.notify_task_completed(db, updated_task, user.id, commit=False)
        else:
            task_notification_service.notify_task_assignment_completed(db, updated_task, user.id, commit=False)
    event_stream.queue_task_changed(db, updated_task)
    if next_task:
        event_stream.queue_task_changed(db, next_task)
    db.commit()
    db.refresh(assignment)
    return _assignment_read(assignment)


@router.get("/my/tasks", response_model=list[MyTaskRead])
def get_my_tasks(db: DbSession, user: CurrentUser) -> list[MyTaskRead]:
    tasks = todo_service.list_todos(db, user.id)
    return [MyTaskRead(
        source_type="TEAM" if task.team_id else "PERSONAL",
        id=task.id,
        title=task.title,
        description=task.description,
        priority=task.priority,
        due_at=task.due_at,
        due_end_at=task.due_end_at,
        status=(todo_service.active_assignment(task, user.id).status.value if todo_service.active_assignment(task, user.id) else task.status.value),
        task_status=task.status.value,
        team_id=task.team_id,
        team_name=task.team.name if task.team else None,
        team_task_id=task.id if task.team_id else None,
        assignment_id=(todo_service.active_assignment(task, user.id).id if todo_service.active_assignment(task, user.id) else None),
        list_name=task.list_name,
        tags=task.tags,
    ) for task in tasks]
