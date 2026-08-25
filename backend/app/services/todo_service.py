from __future__ import annotations

import calendar
from datetime import date, datetime, time, timedelta
from typing import Any

from fastapi import HTTPException, status
from sqlalchemy import Select, and_, case, exists, func, or_, select
from sqlalchemy.orm import Session, joinedload

from app.models.auth import SystemRole, User
from app.models.team import Team, TeamMember, TeamMemberRole, TeamMemberStatus, TeamStatus
from app.models.todo import (
    RecurrenceType,
    Todo,
    TodoAssignment,
    TodoAssignmentStatus,
    TodoSourceType,
    TodoStatus,
    local_now,
)
from app.schemas.todo import TodoCreate, TodoUpdate
from app.services.note_service import content_to_plain_text


VALID_VIEWS = {
    "all", "inbox", "today", "week", "month", "completed",
    "collaboration", "assigned-to-me", "assigned-by-me",
    "linkable",
}
CONTENT_EDITABLE_FIELDS = frozenset({"content_json", "description"})


def _task_statement() -> Select[tuple[Todo]]:
    return select(Todo).options(
        joinedload(Todo.creator),
        joinedload(Todo.assignments).joinedload(TodoAssignment.user),
    )


def active_assignment(todo: Todo, user_id: str) -> TodoAssignment | None:
    return next((item for item in todo.assignments if item.user_id == user_id and item.active), None)


def active_membership(db: Session, user_id: str, team_id: str | None = None) -> TeamMember | None:
    statement = select(TeamMember).where(
        TeamMember.user_id == user_id,
        TeamMember.status == TeamMemberStatus.ACTIVE,
    )
    if team_id is not None:
        statement = statement.where(TeamMember.team_id == team_id)
    return db.scalar(statement.order_by(TeamMember.joined_at.desc()))


def can_view(db: Session, todo: Todo, user_id: str) -> bool:
    user = db.get(User, user_id)
    if user is not None and user.system_role == SystemRole.ROOT and todo.team_id is not None:
        return True
    if todo.team_id is not None:
        membership = active_membership(db, user_id, todo.team_id)
        if membership is None:
            return False
        if membership.role in (TeamMemberRole.OWNER, TeamMemberRole.ADMIN):
            return True
    if todo.creator_id == user_id:
        return True
    assignment = active_assignment(todo, user_id)
    if assignment is None:
        return False
    return True


def can_edit(db: Session, todo: Todo, user_id: str) -> bool:
    if todo.creator_id == user_id:
        return True
    user = db.get(User, user_id)
    if user is not None and user.system_role == SystemRole.ROOT and todo.team_id is not None:
        return True
    membership = active_membership(db, user_id, todo.team_id) if todo.team_id else None
    return membership is not None and membership.role in (TeamMemberRole.OWNER, TeamMemberRole.ADMIN)


def can_edit_content(db: Session, todo: Todo, user_id: str) -> bool:
    """Return whether the actor may edit the task document without its metadata."""
    if todo.creator_id == user_id:
        return True
    user = db.get(User, user_id)
    if user is not None and user.system_role == SystemRole.ROOT and todo.team_id is not None:
        return True
    membership = active_membership(db, user_id, todo.team_id) if todo.team_id else None
    if membership is not None and membership.role in (TeamMemberRole.OWNER, TeamMemberRole.ADMIN):
        return True
    return active_assignment(todo, user_id) is not None and (todo.team_id is None or membership is not None)


def can_assign(db: Session, todo: Todo, user_id: str) -> bool:
    user = db.get(User, user_id)
    if user is not None and user.system_role == SystemRole.ROOT and todo.team_id is not None:
        return True
    if todo.creator_id != user_id:
        return False
    membership = active_membership(db, user_id, todo.team_id) if todo.team_id else active_membership(db, user_id)
    return membership is not None and membership.role in (TeamMemberRole.OWNER, TeamMemberRole.ADMIN)


def get_todo_or_404(db: Session, todo_id: str, user_id: str | None = None) -> Todo:
    result = db.execute(_task_statement().where(Todo.id == todo_id).execution_options(populate_existing=True))
    todo = result.unique().scalar_one_or_none()
    if todo is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Todo not found")
    if user_id is not None and not can_view(db, todo, user_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Todo not found")
    return todo


def require_creator(todo: Todo, user_id: str) -> None:
    if todo.creator_id != user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="只有任务创建者可以修改任务主体")


def require_editor(db: Session, todo: Todo, user_id: str) -> None:
    if not can_edit(db, todo, user_id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="没有修改该任务的权限")


def _day_bounds(value: date) -> tuple[datetime, datetime]:
    start = datetime.combine(value, time.min)
    return start, start + timedelta(days=1)


def build_todo_query(
    user_id: str,
    view: str | None = None,
    selected_date: date | None = None,
    q: str | None = None,
    list_name: str | None = None,
) -> Select[tuple[Todo]]:
    mine = exists().where(
        TodoAssignment.task_id == Todo.id,
        TodoAssignment.user_id == user_id,
        TodoAssignment.active.is_(True),
    )
    statement = _task_statement()
    today = date.today()
    team_admin = exists().where(
        TeamMember.team_id == Todo.team_id,
        TeamMember.user_id == user_id,
        TeamMember.status == TeamMemberStatus.ACTIVE,
        TeamMember.role.in_((TeamMemberRole.OWNER, TeamMemberRole.ADMIN)),
    )
    system_root = exists().where(User.id == user_id, User.system_role == SystemRole.ROOT)
    team_access = or_(team_admin, and_(Todo.team_id.is_not(None), system_root))

    if view == "linkable":
        statement = statement.where(or_(Todo.creator_id == user_id, mine))
    elif view == "assigned-by-me":
        assigned_other = exists().where(
            TodoAssignment.task_id == Todo.id,
            TodoAssignment.user_id != user_id,
            TodoAssignment.active.is_(True),
        )
        statement = statement.where(Todo.creator_id == user_id, assigned_other)
    elif view == "collaboration":
        # Collaboration is the aggregate team-task view.  A creator must still
        # see work they assigned exclusively to other members, while members
        # only see tasks with their own active Assignment.
        statement = statement.where(
            Todo.team_id.is_not(None),
            or_(Todo.creator_id == user_id, mine, team_admin, system_root),
        )
    elif view == "assigned-to-me":
        statement = statement.where(mine, Todo.creator_id != user_id)
    else:
        # Personal tasks remain private. Team OWNER/ADMIN and ROOT can see
        # team tasks even when they were not explicitly assigned to them.
        statement = statement.where(or_(mine, team_access))

    # A member who left a team no longer receives its collaborative tasks.
    active_team = exists().where(
        TeamMember.team_id == Todo.team_id,
        TeamMember.user_id == user_id,
        TeamMember.status == TeamMemberStatus.ACTIVE,
    )
    statement = statement.where(or_(Todo.team_id.is_(None), active_team, system_root))

    if list_name and list_name.strip():
        statement = statement.where(Todo.list_name == list_name.strip())

    if selected_date is not None:
        start, end = _day_bounds(selected_date)
        statement = statement.where(Todo.due_at >= start, Todo.due_at < end)
    elif view:
        if view not in VALID_VIEWS:
            raise HTTPException(status_code=422, detail=f"Unknown todo view: {view}")
        if view == "all":
            pass
        elif view == "completed":
            my_done = exists().where(
                TodoAssignment.task_id == Todo.id,
                TodoAssignment.user_id == user_id,
                TodoAssignment.active.is_(True),
                TodoAssignment.status == TodoAssignmentStatus.DONE,
            )
            statement = statement.where(or_(
                my_done,
                Todo.status == TodoStatus.ABANDONED,
                and_(Todo.status == TodoStatus.DONE, team_access),
            ))
        elif view in ("collaboration", "assigned-to-me", "assigned-by-me", "linkable"):
            pass
        else:
            if view == "inbox":
                statement = statement.where(Todo.due_at.is_(None))
            elif view == "today":
                start, end = _day_bounds(today)
                # Keep unfinished overdue work visible, while terminal history is
                # limited to the selected period so a smart list does not turn
                # into an unbounded archive.
                statement = statement.where(
                    Todo.due_at < end,
                    or_(Todo.status == TodoStatus.TODO, Todo.due_at >= start),
                )
            elif view == "week":
                monday = today - timedelta(days=today.weekday())
                start, _ = _day_bounds(monday)
                end = start + timedelta(days=7)
                statement = statement.where(
                    Todo.due_at < end,
                    or_(Todo.status == TodoStatus.TODO, Todo.due_at >= start),
                )
            elif view == "month":
                month_start = today.replace(day=1)
                next_month = (month_start.replace(day=28) + timedelta(days=4)).replace(day=1)
                start, _ = _day_bounds(month_start)
                end, _ = _day_bounds(next_month)
                statement = statement.where(
                    Todo.due_at < end,
                    or_(Todo.status == TodoStatus.TODO, Todo.due_at >= start),
                )

    if q and q.strip():
        pattern = f"%{q.strip()}%"
        statement = statement.where(or_(Todo.title.like(pattern), Todo.description.like(pattern)))

    if view == "all":
        return statement.order_by(Todo.due_at.is_(None), Todo.due_at.desc(), Todo.created_at.desc(), Todo.id.desc())
    if view == "linkable":
        return statement.order_by(
            case((Todo.status == TodoStatus.TODO, 0), else_=1),
            Todo.updated_at.desc(),
            Todo.id.desc(),
        )
    return statement.order_by(Todo.status.asc(), Todo.due_at.is_(None), Todo.due_at.asc(), Todo.created_at.desc())


def list_todos(
    db: Session,
    owner_id: str,
    view: str | None = None,
    selected_date: date | None = None,
    q: str | None = None,
    list_name: str | None = None,
    limit: int = 100,
    offset: int = 0,
) -> list[Todo]:
    result = db.execute(
        build_todo_query(
            owner_id, view=view, selected_date=selected_date, q=q, list_name=list_name
        ).limit(limit).offset(offset)
    )
    return list(result.unique().scalars())


def _validated_assignment_team(
    db: Session,
    creator_id: str,
    assignee_ids: list[str],
    requested_team_id: str | None = None,
) -> str | None:
    unique_ids = list(dict.fromkeys(assignee_ids))
    if not unique_ids:
        raise HTTPException(status_code=422, detail="任务至少需要一名执行成员")

    desired_ids = set(unique_ids)
    actor = db.get(User, creator_id)
    if requested_team_id is not None:
        team = db.scalar(select(Team).where(
            Team.id == requested_team_id,
            Team.status == TeamStatus.ACTIVE,
        ))
        if team is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Team not found")

        actor_membership = db.scalar(select(TeamMember).where(
            TeamMember.team_id == requested_team_id,
            TeamMember.user_id == creator_id,
            TeamMember.status == TeamMemberStatus.ACTIVE,
        ))
        is_root = actor is not None and actor.system_role == SystemRole.ROOT
        if not is_root and (
            actor_membership is None
            or actor_membership.role not in (TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
        ):
            raise HTTPException(status_code=403, detail="只有团队 OWNER / ADMIN 或系统管理员可以指派其他成员")

        active_member_ids = set(db.scalars(select(TeamMember.user_id).where(
            TeamMember.team_id == requested_team_id,
            TeamMember.user_id.in_(unique_ids),
            TeamMember.status == TeamMemberStatus.ACTIVE,
        )))
        if active_member_ids != desired_ids:
            raise HTTPException(status_code=422, detail="只能把任务分配给指定团队的当前成员")
        return requested_team_id

    if desired_ids == {creator_id}:
        return None

    memberships = db.scalars(select(TeamMember).where(
        TeamMember.user_id == creator_id,
        TeamMember.status == TeamMemberStatus.ACTIVE,
        TeamMember.role.in_((TeamMemberRole.OWNER, TeamMemberRole.ADMIN)),
    ).order_by(TeamMember.joined_at.desc())).all()
    if not memberships:
        if actor is not None and actor.system_role == SystemRole.ROOT:
            raise HTTPException(status_code=422, detail="系统管理员创建团队任务时必须指定 teamId")
        raise HTTPException(status_code=403, detail="只有团队 OWNER / ADMIN 可以指派其他成员")
    for membership in memberships:
        active_ids = set(db.scalars(select(TeamMember.user_id).where(
            TeamMember.team_id == membership.team_id,
            TeamMember.user_id.in_(unique_ids),
            TeamMember.status == TeamMemberStatus.ACTIVE,
        )))
        if active_ids == desired_ids:
            return membership.team_id
    raise HTTPException(status_code=422, detail="只能把任务分配给同一团队的当前成员")


def sync_assignments(db: Session, todo: Todo, assignee_ids: list[str], actor_id: str) -> None:
    desired = set(dict.fromkeys(assignee_ids))
    if not desired:
        raise HTTPException(status_code=422, detail="任务至少需要一名执行成员")
    existing = {assignment.user_id: assignment for assignment in todo.assignments}
    now = local_now()
    for user_id, assignment in existing.items():
        if user_id not in desired and assignment.active:
            assignment.active = False
            assignment.removed_at = now
    for user_id in desired:
        assignment = existing.get(user_id)
        if assignment is None:
            todo.assignments.append(TodoAssignment(user_id=user_id, assigned_by_id=actor_id))
        elif not assignment.active:
            assignment.active = True
            assignment.removed_at = None
            assignment.assigned_by_id = actor_id
            assignment.assigned_at = now


def recompute_task_status(todo: Todo) -> None:
    if todo.status == TodoStatus.ABANDONED:
        return
    assignments = [item for item in todo.assignments if item.active]
    if assignments and all(item.status == TodoAssignmentStatus.DONE for item in assignments):
        todo.status = TodoStatus.DONE
        todo.completed_at = todo.completed_at or local_now()
    else:
        todo.status = TodoStatus.TODO
        todo.completed_at = None


def create_todo(db: Session, payload: TodoCreate, owner_id: str, *, commit: bool = True) -> Todo:
    assignee_ids = payload.assignee_ids if payload.assignee_ids is not None else [owner_id]
    team_id = _validated_assignment_team(db, owner_id, assignee_ids, payload.team_id)
    source = payload.source
    if source is None and payload.source_type == TodoSourceType.NOTE and payload.source_note_id:
        from app.models.resource_relation import ResourceType
        from app.schemas.resource_relation import TaskSourceCreate

        source = TaskSourceCreate(
            resource_type=ResourceType.PERSONAL_NOTE,
            resource_id=payload.source_note_id,
            excerpt=payload.source_excerpt,
        )
    values = payload.model_dump(exclude={"assignee_ids", "source", "team_id"})
    if source is not None:
        # ResourceRelation is authoritative. These columns are kept populated
        # only so old clients can still recognize a note-backed task.
        values["source_type"] = TodoSourceType.NOTE
        values["source_note_id"] = source.resource_id
        values["source_excerpt"] = source.excerpt
    todo = Todo(**values, owner_id=owner_id, creator_id=owner_id, team_id=team_id)
    db.add(todo)
    db.flush()
    from app.services.todo_list_service import ensure_list

    ensure_list(db, todo.list_name, owner_id)
    sync_assignments(db, todo, assignee_ids, owner_id)
    if source is not None:
        # Lazy import avoids a service cycle because relation permissions reuse
        # this module's Task access rules.
        from app.services import resource_relation_service

        resource_relation_service.create_task_source_relation(db, todo, source, owner_id)
    if commit:
        db.commit()
    else:
        db.flush()
    return get_todo_or_404(db, todo.id, owner_id)


def update_todo(
    db: Session,
    todo: Todo,
    payload: TodoUpdate,
    actor_id: str | None = None,
    *,
    commit: bool = True,
) -> Todo:
    changes = payload.model_dump(exclude_unset=True)
    if actor_id is not None and not can_edit(db, todo, actor_id):
        if not can_edit_content(db, todo, actor_id):
            raise HTTPException(status_code=403, detail="没有修改该任务正文的权限")
        if set(changes) - CONTENT_EDITABLE_FIELDS:
            raise HTTPException(status_code=403, detail="被指派人只能编辑任务正文")
    if "title" in changes:
        title = (changes["title"] or "").strip()
        if not title:
            raise HTTPException(status_code=422, detail="待办标题不能为空")
        changes["title"] = title

    due_at = changes.get("due_at", todo.due_at)
    due_end_at = changes.get("due_end_at", todo.due_end_at)
    reminder_at = changes.get("reminder_at", todo.reminder_at)
    recurrence_type = changes.get("recurrence_type", todo.recurrence_type)
    if reminder_at is not None and due_at is None:
        raise HTTPException(status_code=422, detail="设置提醒前必须先设置截止时间")
    if reminder_at is not None and due_at is not None and reminder_at > due_at:
        raise HTTPException(status_code=422, detail="提醒时间不能晚于截止时间")
    if recurrence_type != RecurrenceType.NONE and due_at is None:
        raise HTTPException(status_code=422, detail="重复待办必须设置执行时间")
    if due_end_at is not None and (due_at is None or due_end_at < due_at):
        raise HTTPException(status_code=422, detail="结束时间不能早于开始时间")
    if recurrence_type == RecurrenceType.NONE:
        changes["recurrence_config"] = None
    if "reminder_at" in changes or "due_at" in changes:
        changes["reminded_at"] = None
    if "list_name" in changes:
        changes["list_name"] = (changes["list_name"] or "").strip() or "收集箱"
        from app.services.todo_list_service import ensure_list

        ensure_list(db, changes["list_name"], actor_id)
    if "tags" in changes:
        changes["tags"] = list(dict.fromkeys(tag.strip() for tag in (changes["tags"] or []) if tag.strip()))
    if "content_json" in changes:
        # Tiptap JSON is the authoritative task document. Keep description as
        # a plain-text compatibility/search projection instead of independent
        # editor state that can drift from the document.
        changes["description"] = content_to_plain_text(changes["content_json"]) or None

    for field, value in changes.items():
        setattr(todo, field, value)
    if commit:
        db.commit()
    else:
        db.flush()
    db.refresh(todo)
    return todo


def update_assignees(
    db: Session,
    todo: Todo,
    actor_id: str,
    assignee_ids: list[str],
    *,
    commit: bool = True,
) -> Todo:
    actor = db.get(User, actor_id)
    if actor is not None and actor.system_role == SystemRole.ROOT and todo.team_id is not None:
        desired_ids = set(dict.fromkeys(assignee_ids))
        active_member_ids = set(db.scalars(select(TeamMember.user_id).where(
            TeamMember.team_id == todo.team_id,
            TeamMember.status == TeamMemberStatus.ACTIVE,
            TeamMember.user_id.in_(desired_ids),
        ))) if desired_ids else set()
        if not desired_ids or active_member_ids != desired_ids:
            raise HTTPException(status_code=422, detail="只能把任务分配给当前团队成员")
    else:
        require_creator(todo, actor_id)
        todo.team_id = _validated_assignment_team(db, actor_id, assignee_ids)
    sync_assignments(db, todo, assignee_ids, actor_id)
    recompute_task_status(todo)
    if commit:
        db.commit()
    else:
        db.flush()
    return get_todo_or_404(db, todo.id, actor_id)


def _add_months(value: datetime, months: int, preferred_day: int) -> datetime:
    month_index = value.year * 12 + value.month - 1 + months
    year, month_zero = divmod(month_index, 12)
    month = month_zero + 1
    day = min(preferred_day, calendar.monthrange(year, month)[1])
    return value.replace(year=year, month=month, day=day)


def calculate_next_due(todo: Todo) -> datetime:
    if todo.due_at is None:
        raise ValueError("Recurring todo is missing due_at")
    config: dict[str, Any] = todo.recurrence_config or {}
    interval = max(int(config.get("interval", 1)), 1)
    recurrence_type = todo.recurrence_type

    if recurrence_type == RecurrenceType.DAILY:
        return todo.due_at + timedelta(days=interval)
    if recurrence_type == RecurrenceType.WEEKLY:
        return todo.due_at + timedelta(weeks=interval)
    if recurrence_type == RecurrenceType.MONTHLY:
        return _add_months(todo.due_at, interval, int(config.get("day", todo.due_at.day)))
    if recurrence_type == RecurrenceType.CUSTOM:
        frequency = str(config.get("frequency", "")).upper()
        if frequency == "DAILY":
            return todo.due_at + timedelta(days=interval)
        if frequency == "WEEKLY":
            return todo.due_at + timedelta(weeks=interval)
        if frequency == "MONTHLY":
            return _add_months(todo.due_at, interval, int(config.get("day", todo.due_at.day)))
        raise ValueError("Custom recurrence requires DAILY, WEEKLY, or MONTHLY frequency")
    raise ValueError("Todo is not recurring")


def complete_todo(
    db: Session,
    todo: Todo,
    user_id: str,
    *,
    commit: bool = True,
) -> tuple[Todo, Todo | None]:
    # `generated_from_id` is unique, so treating it as an idempotency key prevents
    # retries (or two rapid clicks) from creating two next occurrences.
    existing = db.scalar(select(Todo).where(Todo.generated_from_id == todo.id))
    assignment = active_assignment(todo, user_id)
    if assignment is None:
        raise HTTPException(status_code=403, detail="只能修改自己的任务执行状态")
    if todo.status == TodoStatus.ABANDONED:
        raise HTTPException(status_code=409, detail="已取消的任务不能更新")
    if assignment.status == TodoAssignmentStatus.DONE:
        return todo, existing

    assignment.status = TodoAssignmentStatus.DONE
    assignment.completed_at = local_now()
    recompute_task_status(todo)
    next_todo: Todo | None = None
    if todo.status == TodoStatus.DONE and todo.recurrence_type != RecurrenceType.NONE:
        if existing is not None:
            # A previous request may have committed the child before the caller
            # observed the response. Reuse it instead of expanding the series.
            next_todo = existing
        else:
            next_due = calculate_next_due(todo)
            reminder_offset = todo.due_at - todo.reminder_at if todo.reminder_at and todo.due_at else None
            next_todo = Todo(
                title=todo.title,
                owner_id=todo.owner_id,
                creator_id=todo.creator_id,
                team_id=todo.team_id,
                description=todo.description,
                content_json=todo.content_json,
                attachment_ids=list(todo.attachment_ids or []),
                priority=todo.priority,
                due_at=next_due,
                due_end_at=(next_due + (todo.due_end_at - todo.due_at)) if todo.due_end_at and todo.due_at else None,
                reminder_at=next_due - reminder_offset if reminder_offset else None,
                recurrence_type=todo.recurrence_type,
                recurrence_config=todo.recurrence_config,
                list_name=todo.list_name,
                tags=todo.tags,
                source_type=todo.source_type,
                source_note_id=todo.source_note_id,
                source_excerpt=todo.source_excerpt,
                recurring_series_id=todo.recurring_series_id or todo.id,
                generated_from_id=todo.id,
            )
            db.add(next_todo)
            db.flush()
            for source in todo.assignments:
                if source.active:
                    next_todo.assignments.append(
                        TodoAssignment(user_id=source.user_id, assigned_by_id=todo.creator_id)
                    )
        todo.recurring_series_id = todo.recurring_series_id or todo.id

    if commit:
        db.commit()
    else:
        db.flush()
    db.refresh(todo)
    if next_todo:
        db.refresh(next_todo)
    return todo, next_todo


def restore_todo(db: Session, todo: Todo, user_id: str, *, commit: bool = True) -> Todo:
    # Restoring an occurrence means its automatically-created future branch is
    # no longer valid. Remove active descendants, but keep already-completed
    # history as detached records so restoring does not erase the audit trail.
    descendants: list[Todo] = []
    frontier = [todo.id]
    while frontier:
        children = list(db.scalars(select(Todo).where(Todo.generated_from_id.in_(frontier))))
        if not children:
            break
        descendants.extend(children)
        frontier = [child.id for child in children]
    for child in reversed(descendants):
        if child.status == TodoStatus.DONE:
            # Release the unique idempotency key so completing the restored
            # occurrence can create a fresh next occurrence.
            child.generated_from_id = None
        else:
            db.delete(child)
    assignment = active_assignment(todo, user_id)
    if assignment is None:
        raise HTTPException(status_code=403, detail="只能修改自己的任务执行状态")
    assignment.status = TodoAssignmentStatus.TODO
    assignment.completed_at = None
    todo.status = TodoStatus.TODO
    recompute_task_status(todo)
    todo.reminded_at = None
    if commit:
        db.commit()
    else:
        db.flush()
    db.refresh(todo)
    return todo


def abandon_todo(db: Session, todo: Todo, *, commit: bool = True) -> Todo:
    if todo.status == TodoStatus.ABANDONED:
        return todo
    todo.status = TodoStatus.ABANDONED
    todo.completed_at = None
    todo.reminded_at = None
    if commit:
        db.commit()
    else:
        db.flush()
    db.refresh(todo)
    return todo


def update_my_status(
    db: Session,
    todo: Todo,
    user_id: str,
    new_status: TodoAssignmentStatus,
    *,
    commit: bool = True,
) -> tuple[Todo, Todo | None]:
    if new_status == TodoAssignmentStatus.DONE:
        return complete_todo(db, todo, user_id, commit=commit)
    if todo.status == TodoStatus.ABANDONED:
        raise HTTPException(status_code=409, detail="已取消的任务不能更新")
    assignment = active_assignment(todo, user_id)
    if assignment is None:
        raise HTTPException(status_code=403, detail="只能修改自己的任务执行状态")
    assignment.status = new_status
    assignment.completed_at = None
    recompute_task_status(todo)
    if commit:
        db.commit()
    else:
        db.flush()
    return get_todo_or_404(db, todo.id, user_id), None


def acknowledge_reminder(
    db: Session,
    todo: Todo,
    reminded_at: datetime | None = None,
    *,
    commit: bool = True,
) -> Todo:
    todo.reminded_at = reminded_at or local_now()
    if commit:
        db.commit()
    else:
        db.flush()
    db.refresh(todo)
    return todo


def due_reminders(db: Session, owner_id: str, now: datetime | None = None) -> list[Todo]:
    current = now or local_now()
    statement = (
        select(Todo)
        .where(
            and_(
                exists().where(
                    TodoAssignment.task_id == Todo.id,
                    TodoAssignment.user_id == owner_id,
                    TodoAssignment.active.is_(True),
                    TodoAssignment.status != TodoAssignmentStatus.DONE,
                ),
                Todo.status == TodoStatus.TODO,
                Todo.reminder_at.is_not(None),
                Todo.reminder_at <= current,
                Todo.reminded_at.is_(None),
            )
        )
        .order_by(Todo.reminder_at.asc())
    )
    return list(db.scalars(statement))
