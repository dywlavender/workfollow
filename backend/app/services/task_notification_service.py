from __future__ import annotations

import logging

from app.models.auth import User
from app.models.notification import NotificationType
from app.models.todo import Todo, new_uuid
from app.services import external_notification_service, notification_dispatcher
from sqlalchemy.orm import Session


logger = logging.getLogger(__name__)


def _task_data(todo: Todo, event: str, **extra: object) -> dict[str, object]:
    return {"taskId": todo.id, "teamId": todo.team_id, "taskTitle": todo.title, "event": event, **extra}


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
        body=f"{actor_name}将任务“{todo.title}”分配给你。",
        external_message=f"【任务】{actor_name}将任务“{todo.title}”分配给你。",
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

    groups = (
        (
            "added",
            added_ids,
            NotificationType.TEAM_TASK_ASSIGNED,
            NotificationType.TASK_ASSIGNEE_ADDED,
            "你有新的指派任务",
            f"{actor_name}将任务“{todo.title}”分配给你。",
            f"【任务】{actor_name}将任务“{todo.title}”分配给你。",
        ),
        (
            "removed",
            removed_ids,
            NotificationType.TEAM_TASK_CANCELLED,
            NotificationType.TASK_ASSIGNEE_REMOVED,
            "任务分配已取消",
            f"{actor_name}取消了你在任务“{todo.title}”中的分配。",
            f"【任务】{actor_name}取消了你在“{todo.title}”中的分配。",
        ),
        (
            "updated",
            unchanged_ids,
            NotificationType.TEAM_TASK_UPDATED,
            NotificationType.TASK_ASSIGNMENT_CHANGED,
            "任务成员已调整",
            f"{actor_name}调整了任务“{todo.title}”的分配成员。",
            f"【任务】{actor_name}调整了“{todo.title}”的分配成员。",
        ),
    )
    for group_name, group_ids, in_app_type, external_type, title, body, external_message in groups:
        event_key = f"task-assignment-changed:{todo.id}:{event_id}:{group_name}"
        data = _task_data(todo, "TASK_ASSIGNMENT_CHANGED", eventKey=event_key, **base_data)
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
        title="任务分配已完成",
        body=f"{actor_name}已完成任务“{todo.title}”的分配。",
        external_message=f"【任务】{actor_name}已完成“{todo.title}”的分配。",
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
        body=f"{actor_name}完成了任务“{todo.title}”。",
        external_message=f"【任务】{actor_name}完成了任务“{todo.title}”。",
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
        body=f"{actor_name}取消了任务“{todo.title}”。",
        external_message=f"【任务】{actor_name}取消了任务“{todo.title}”。",
        data_json=data,
        event_key=event_key,
        commit=commit,
    )
    _log_external_queue(todo, "TASK_CANCELLED", result)
