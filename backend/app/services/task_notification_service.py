from __future__ import annotations

from datetime import datetime, time
import logging

from app.models.auth import User
from app.models.notification import NotificationType
from app.models.todo import Todo, TodoAssignment, TodoPriority, new_uuid
from app.services import external_notification_service, notification_dispatcher
from sqlalchemy.orm import Session


logger = logging.getLogger(__name__)


_PRIORITY_LABELS = {
    TodoPriority.NONE: "未设置",
    TodoPriority.LOW: "低",
    TodoPriority.MEDIUM: "中",
    TodoPriority.HIGH: "高",
}
_CHANGE_LABELS = {
    "title": "标题",
    "description": "描述",
    "priority": "优先级",
    "listName": "清单",
    "tags": "标签",
    "reminderAt": "提醒时间",
    "recurrenceType": "重复规则",
    "attachmentCount": "附件数量",
    "status": "状态",
}
_MAX_DESCRIPTION_EXCERPT = 180


def _iso(value: datetime | None) -> str | None:
    return value.isoformat() if value else None


def _display_name(user: User | None, user_id: str | None = None) -> str:
    if user is not None:
        return user.nickname or user.username
    return user_id or "成员"


def _excerpt(value: str | None) -> str | None:
    if not value:
        return None
    normalized = " ".join(value.split())
    if len(normalized) <= _MAX_DESCRIPTION_EXCERPT:
        return normalized
    return normalized[:_MAX_DESCRIPTION_EXCERPT].rstrip() + "…"


def _format_datetime(value: datetime | None) -> str:
    if value is None:
        return "未设置"
    result = value.strftime("%Y-%m-%d")
    if value.time() != time.min:
        result += value.strftime(" %H:%M")
    return result


def _format_due_range(todo: Todo) -> str:
    start = _format_datetime(todo.due_at)
    if todo.due_end_at is None or (
        todo.due_at is not None and todo.due_end_at.date() == todo.due_at.date()
    ):
        return start
    return f"{start} 至 {_format_datetime(todo.due_end_at)}"


def _format_iso_datetime(value: object) -> str:
    if not value:
        return "未设置"
    if isinstance(value, datetime):
        return _format_datetime(value)
    if isinstance(value, str):
        try:
            return _format_datetime(datetime.fromisoformat(value))
        except ValueError:
            return value
    return str(value)


def _priority_label(value: object) -> str:
    try:
        priority = TodoPriority(value)
    except (TypeError, ValueError):
        return str(value)
    return _PRIORITY_LABELS[priority]


def _active_assignments(todo: Todo) -> list[TodoAssignment]:
    return [item for item in todo.assignments if item.active]


def _assignee_views(todo: Todo, user_ids: set[str] | None = None) -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    for assignment in todo.assignments:
        if user_ids is not None and assignment.user_id not in user_ids:
            continue
        result.append({
            "id": assignment.user_id,
            "name": _display_name(assignment.user, assignment.user_id),
            "status": assignment.status.value,
            "active": assignment.active,
        })
    return result


def _assignee_names(todo: Todo, user_ids: set[str]) -> str:
    names = [item["name"] for item in _assignee_views(todo, user_ids)]
    return "、".join(str(name) for name in names) or "无"


def task_snapshot(todo: Todo) -> dict[str, object]:
    """Return the concise, JSON-safe task snapshot shared by notifications."""
    active = _active_assignments(todo)
    return {
        "id": todo.id,
        "title": todo.title,
        "descriptionExcerpt": _excerpt(todo.description),
        "teamId": todo.team_id,
        "teamName": todo.team.name if todo.team is not None else None,
        "dueAt": _iso(todo.due_at),
        "dueEndAt": _iso(todo.due_end_at),
        "priority": todo.priority.value,
        "status": todo.status.value,
        "listName": todo.list_name,
        "tags": list(todo.tags or []),
        "reminderAt": _iso(todo.reminder_at),
        "recurrenceType": todo.recurrence_type.value,
        "attachmentCount": len(todo.attachment_ids or []),
        "assigneeIds": [item.user_id for item in active],
        "assignees": _assignee_views(todo, {item.user_id for item in active}),
        "completedAssignments": sum(item.status.value == "DONE" for item in active),
        "totalAssignments": len(active),
        "completedAt": _iso(todo.completed_at),
        "createdAt": _iso(todo.created_at),
        "updatedAt": _iso(todo.updated_at),
    }


def task_change_snapshot(todo: Todo) -> dict[str, object]:
    """Capture mutable fields before an update for a before/after diff."""
    return {
        "title": todo.title,
        "description": todo.description or "",
        "dueAt": _iso(todo.due_at),
        "dueEndAt": _iso(todo.due_end_at),
        "priority": todo.priority.value,
        "status": todo.status.value,
        "listName": todo.list_name,
        "tags": list(todo.tags or []),
        "reminderAt": _iso(todo.reminder_at),
        "recurrenceType": todo.recurrence_type.value,
        "recurrenceConfig": todo.recurrence_config,
        "attachmentCount": len(todo.attachment_ids or []),
    }


def task_changes(before: dict[str, object], after: dict[str, object]) -> dict[str, dict[str, object]]:
    """Build a compact JSON-safe diff for task update notifications."""
    changed: dict[str, dict[str, object]] = {}
    fields = (
        "title", "description", "dueAt", "dueEndAt", "priority", "listName", "tags",
        "reminderAt", "recurrenceType", "recurrenceConfig", "attachmentCount", "status",
    )
    for field in fields:
        if before.get(field) != after.get(field):
            previous = before.get(field)
            current = after.get(field)
            if field == "description":
                previous = _excerpt(str(previous) if previous else None)
                current = _excerpt(str(current) if current else None)
            changed[field] = {"before": previous, "after": current}
    return changed


def _public_change_snapshot(snapshot: dict[str, object]) -> dict[str, object]:
    public = dict(snapshot)
    public["description"] = _excerpt(str(snapshot.get("description") or ""))
    return public


def _task_context(todo: Todo) -> str:
    parts = [f"截止：{_format_due_range(todo)}"]
    if todo.priority != TodoPriority.NONE:
        parts.append(f"优先级：{_priority_label(todo.priority)}")
    if todo.team is not None:
        parts.append(f"团队：{todo.team.name}")
    return "；".join(parts)


def _change_text(after: dict[str, object], changes: dict[str, dict[str, object]]) -> str:
    parts: list[str] = []
    if "dueAt" in changes or "dueEndAt" in changes:
        due = f"截止时间改为{_format_iso_datetime(after.get('dueAt'))}"
        if after.get("dueEndAt"):
            due += f" 至 {_format_iso_datetime(after.get('dueEndAt'))}"
        parts.append(due)
    for field, change in changes.items():
        if field in {"dueAt", "dueEndAt"}:
            continue
        if field == "title":
            parts.append(f"标题改为“{change['after']}”")
        elif field == "description":
            parts.append("描述已更新")
        elif field == "priority":
            parts.append(f"优先级改为{_priority_label(change['after'])}")
        elif field == "listName":
            parts.append(f"清单改为“{change['after']}”")
        elif field == "tags":
            tags = change["after"] or []
            parts.append(f"标签改为{','.join(tags) if tags else '无'}")
        elif field == "reminderAt":
            parts.append(f"提醒时间改为{_format_iso_datetime(change['after'])}")
        elif field == "recurrenceType":
            parts.append(f"重复规则改为{change['after']}")
        elif field == "recurrenceConfig":
            parts.append("重复规则已更新")
        elif field == "attachmentCount":
            parts.append(f"附件数量改为{change['after']}个")
        elif field == "status":
            parts.append(f"状态改为{change['after']}")
        else:
            parts.append(f"{_CHANGE_LABELS.get(field, field)}已更新")
    return "；".join(parts) or "任务信息已更新"


def _task_data(todo: Todo, event: str, **extra: object) -> dict[str, object]:
    payload: dict[str, object] = {
        "taskId": todo.id,
        "teamId": todo.team_id,
        "taskTitle": todo.title,
        "event": event,
        "eventType": event,
        "task": task_snapshot(todo),
        **extra,
    }
    if payload.get("actorId"):
        payload["actor"] = {
            "id": payload["actorId"],
            "name": payload.get("actorName") or "用户",
        }
    return payload


def _actor_name(db: Session, actor_id: str) -> str:
    user = db.get(User, actor_id)
    return (user.nickname or user.username) if user is not None else "用户"


def _log_external_queue(todo: Todo, event: str, result: notification_dispatcher.NotificationDispatchResult) -> None:
    if result.external_count:
        logger.info(
            "任务外部通知已入队 task_id=%s event=%s count=%s",
            todo.id,
            event,
            result.external_count,
        )


def notify_task_created(db: Session, todo: Todo, actor_id: str, *, commit: bool = True) -> None:
    """Notify assignees when a task is initially assigned."""
    actor_name = _actor_name(db, actor_id)
    active_ids = [item.user_id for item in todo.assignments if item.active]
    event_key = f"task-assigned:{todo.id}:{new_uuid()}"
    data = _task_data(
        todo,
        "TASK_ASSIGNEE_ADDED",
        actorId=actor_id,
        actorName=actor_name,
        assigneeIds=active_ids,
        eventKey=event_key,
    )
    context = _task_context(todo)
    logger.info(
        "【通知触发入口】任务创建 task_id=%s title=%s participants=%s recipients=%s external_enabled=%s",
        todo.id,
        todo.title,
        len(active_ids),
        len(notification_dispatcher.recipient_ids(active_ids, actor_id)),
        external_notification_service.external_notifications_enabled(),
    )
    result = notification_dispatcher.dispatch_event(
        db,
        event="TASK_ASSIGNEE_ADDED",
        participant_ids=active_ids,
        actor_user_id=actor_id,
        in_app_type=NotificationType.TEAM_TASK_ASSIGNED,
        external_type=NotificationType.TASK_ASSIGNEE_ADDED,
        title="你有新的指派任务",
        body=f"{actor_name}将任务“{todo.title}”分配给你；{context}。",
        external_message=f"【任务分配】{actor_name}将任务“{todo.title}”分配给你；{context}。",
        data_json=data,
        event_key=event_key,
        commit=commit,
    )
    _log_external_queue(todo, "TASK_ASSIGNEE_ADDED", result)


def notify_assignees_changed(
    db: Session,
    todo: Todo,
    actor_id: str,
    previous_ids: set[str],
    current_ids: set[str],
    *,
    commit: bool = True,
) -> None:
    """Notify affected participants about an assignment change."""
    added_ids = current_ids - previous_ids
    removed_ids = previous_ids - current_ids
    all_participants = previous_ids | current_ids
    recipients = notification_dispatcher.recipient_ids(all_participants, actor_id)
    logger.info(
        "【通知触发入口】任务成员变更 task_id=%s title=%s added=%s removed=%s recipients=%s changed=%s external_enabled=%s",
        todo.id,
        todo.title,
        len(added_ids),
        len(removed_ids),
        len(recipients),
        bool(added_ids or removed_ids),
        external_notification_service.external_notifications_enabled(),
    )
    if not added_ids and not removed_ids:
        return

    actor_name = _actor_name(db, actor_id)
    event_id = new_uuid()
    base_data = {
        "actorId": actor_id,
        "actorName": actor_name,
        "addedAssigneeIds": sorted(added_ids),
        "removedAssigneeIds": sorted(removed_ids),
    }
    unchanged_ids = all_participants - added_ids - removed_ids
    total_in_app = 0
    total_external = 0

    context = _task_context(todo)
    member_change = (
        f"新增：{_assignee_names(todo, added_ids)}；移除：{_assignee_names(todo, removed_ids)}"
    )
    groups = (
        (
            "added",
            added_ids,
            NotificationType.TEAM_TASK_ASSIGNED,
            NotificationType.TASK_ASSIGNEE_ADDED,
            "TASK_ASSIGNEE_ADDED",
            "你有新的指派任务",
            f"{actor_name}将任务“{todo.title}”分配给你；{context}。",
            f"【任务分配】{actor_name}将任务“{todo.title}”分配给你；{context}。",
        ),
        (
            "removed",
            removed_ids,
            NotificationType.TEAM_TASK_CANCELLED,
            NotificationType.TASK_ASSIGNEE_REMOVED,
            "TASK_ASSIGNEE_REMOVED",
            "任务分配已取消",
            f"{actor_name}取消了你在任务“{todo.title}”中的分配；{context}。",
            f"【任务分配取消】{actor_name}取消了你在“{todo.title}”中的分配；{context}。",
        ),
        (
            "updated",
            unchanged_ids,
            NotificationType.TEAM_TASK_UPDATED,
            NotificationType.TASK_ASSIGNMENT_CHANGED,
            "TASK_ASSIGNMENT_CHANGED",
            "任务成员已调整",
            f"{actor_name}调整了任务“{todo.title}”的分配成员（{member_change}）；{context}。",
            f"【任务成员调整】{actor_name}调整了“{todo.title}”的分配成员（{member_change}）；{context}。",
        ),
    )
    for (
        group_name,
        group_ids,
        in_app_type,
        external_type,
        event_name,
        title,
        body,
        external_message,
    ) in groups:
        event_key = f"task-assignment-changed:{todo.id}:{event_id}:{group_name}"
        data = _task_data(
            todo,
            event_name,
            eventKey=event_key,
            **base_data,
            change={
                "addedAssigneeIds": sorted(added_ids),
                "removedAssigneeIds": sorted(removed_ids),
                "addedAssignees": _assignee_views(todo, added_ids),
                "removedAssignees": _assignee_views(todo, removed_ids),
            },
        )
        result = notification_dispatcher.dispatch_event(
            db,
            event=f"TASK_ASSIGNMENT_CHANGED:{group_name}",
            participant_ids=group_ids,
            actor_user_id=actor_id,
            in_app_type=in_app_type,
            external_type=external_type,
            title=title,
            body=body,
            external_message=external_message,
            data_json=data,
            event_key=event_key,
            commit=False,
        )
        total_in_app += result.in_app_count
        total_external += result.external_count

    if total_in_app or total_external:
        if commit:
            db.commit()
        logger.info(
            "统一任务成员变更通知已完成 task_id=%s in_app=%s external=%s",
            todo.id,
            total_in_app,
            total_external,
        )


def notify_task_assignment_completed(
    db: Session,
    todo: Todo,
    actor_id: str,
    *,
    commit: bool = True,
) -> None:
    actor_name = _actor_name(db, actor_id)
    active_ids = [item.user_id for item in todo.assignments if item.active]
    event_key = f"task-assignment-completed:{todo.id}:{new_uuid()}"
    data = _task_data(
        todo,
        "TASK_ASSIGNMENT_COMPLETED",
        actorId=actor_id,
        actorName=actor_name,
        completedBy=actor_id,
        eventKey=event_key,
    )
    context = _task_context(todo)
    active = _active_assignments(todo)
    progress = f"{sum(item.status.value == 'DONE' for item in active)}/{len(active)}"
    logger.info(
        "【通知触发入口】成员完成分配 task_id=%s title=%s participants=%s recipients=%s external_enabled=%s",
        todo.id,
        todo.title,
        len(active_ids),
        len(notification_dispatcher.recipient_ids(active_ids, actor_id)),
        external_notification_service.external_notifications_enabled(),
    )
    result = notification_dispatcher.dispatch_event(
        db,
        event="TASK_ASSIGNMENT_COMPLETED",
        participant_ids=active_ids,
        actor_user_id=actor_id,
        in_app_type=NotificationType.TEAM_TASK_UPDATED,
        external_type=NotificationType.TASK_ASSIGNMENT_COMPLETED,
        title="成员已完成任务",
        body=f"{actor_name}已完成任务“{todo.title}”；当前进度：{progress}；{context}。",
        external_message=f"【任务进度】{actor_name}已完成任务“{todo.title}”；当前进度：{progress}；{context}。",
        data_json=data,
        event_key=event_key,
        commit=commit,
    )
    _log_external_queue(todo, "TASK_ASSIGNMENT_COMPLETED", result)


def notify_task_completed(db: Session, todo: Todo, actor_id: str, *, commit: bool = True) -> None:
    actor_name = _actor_name(db, actor_id)
    active_ids = [item.user_id for item in todo.assignments if item.active]
    event_key = f"task-completed:{todo.id}:{new_uuid()}"
    data = _task_data(
        todo,
        "TASK_COMPLETED",
        actorId=actor_id,
        actorName=actor_name,
        completedBy=actor_id,
        eventKey=event_key,
    )
    context = _task_context(todo)
    completed_at = _format_datetime(todo.completed_at)
    logger.info(
        "【通知触发入口】任务全部完成 task_id=%s title=%s participants=%s recipients=%s external_enabled=%s",
        todo.id,
        todo.title,
        len(active_ids),
        len(notification_dispatcher.recipient_ids(active_ids, actor_id)),
        external_notification_service.external_notifications_enabled(),
    )
    result = notification_dispatcher.dispatch_event(
        db,
        event="TASK_COMPLETED",
        participant_ids=active_ids,
        actor_user_id=actor_id,
        in_app_type=NotificationType.TEAM_TASK_UPDATED,
        external_type=NotificationType.TASK_COMPLETED,
        title="任务已全部完成",
        body=f"{actor_name}完成了任务“{todo.title}”；完成时间：{completed_at}；{context}。",
        external_message=f"【任务完成】{actor_name}完成了任务“{todo.title}”；完成时间：{completed_at}；{context}。",
        data_json=data,
        event_key=event_key,
        commit=commit,
    )
    _log_external_queue(todo, "TASK_COMPLETED", result)


def notify_task_cancelled(
    db: Session,
    todo: Todo,
    actor_id: str,
    participant_ids: set[str],
    *,
    commit: bool = True,
) -> None:
    actor_name = _actor_name(db, actor_id)
    event_key = f"task-cancelled:{todo.id}:{new_uuid()}"
    data = _task_data(
        todo,
        "TASK_CANCELLED",
        actorId=actor_id,
        actorName=actor_name,
        eventKey=event_key,
    )
    context = _task_context(todo)
    cancelled_at = _format_datetime(todo.updated_at)
    logger.info(
        "【通知触发入口】任务取消 task_id=%s title=%s participants=%s recipients=%s external_enabled=%s",
        todo.id,
        todo.title,
        len(participant_ids),
        len(notification_dispatcher.recipient_ids(participant_ids, actor_id)),
        external_notification_service.external_notifications_enabled(),
    )
    result = notification_dispatcher.dispatch_event(
        db,
        event="TASK_CANCELLED",
        participant_ids=participant_ids,
        actor_user_id=actor_id,
        in_app_type=NotificationType.TEAM_TASK_CANCELLED,
        external_type=NotificationType.TASK_CANCELLED,
        title="任务已取消",
        body=f"{actor_name}取消了任务“{todo.title}”；取消时间：{cancelled_at}；{context}。",
        external_message=f"【任务取消】{actor_name}取消了任务“{todo.title}”；取消时间：{cancelled_at}；{context}。",
        data_json=data,
        event_key=event_key,
        commit=commit,
    )
    _log_external_queue(todo, "TASK_CANCELLED", result)


def notify_task_updated(
    db: Session,
    todo: Todo,
    actor_id: str,
    before: dict[str, object],
    *,
    commit: bool = True,
) -> None:
    """Notify active assignees when editable task details change."""
    after = task_change_snapshot(todo)
    changes = task_changes(before, after)
    if not changes:
        return

    actor_name = _actor_name(db, actor_id)
    active_ids = [item.user_id for item in _active_assignments(todo)]
    event_key = f"task-updated:{todo.id}:{new_uuid()}"
    change_text = _change_text(after, changes)
    context = _task_context(todo)
    data = _task_data(
        todo,
        "TASK_UPDATED",
        actorId=actor_id,
        actorName=actor_name,
        changedFields=list(changes),
        changes=changes,
        previousTask=_public_change_snapshot(before),
        eventKey=event_key,
    )
    result = notification_dispatcher.dispatch_event(
        db,
        event="TASK_UPDATED",
        participant_ids=active_ids,
        actor_user_id=actor_id,
        in_app_type=NotificationType.TEAM_TASK_UPDATED,
        external_type=NotificationType.TASK_UPDATED,
        title="任务信息已更新",
        body=f"{actor_name}更新了任务“{todo.title}”：{change_text}；{context}。",
        external_message=f"【任务更新】{actor_name}更新了“{todo.title}”：{change_text}；{context}。",
        data_json=data,
        event_key=event_key,
        commit=commit,
    )
    _log_external_queue(todo, "TASK_UPDATED", result)
