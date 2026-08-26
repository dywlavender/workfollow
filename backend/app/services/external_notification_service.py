from __future__ import annotations

import logging
import threading
from datetime import datetime, time, timedelta
from functools import lru_cache
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.db.session import SessionLocal
from app.models.auth import User, UserStatus
from app.models.notification import (
    ExternalDeliveryStatus,
    ExternalNotificationDelivery,
    NotificationType,
)
from app.models.todo import Todo, TodoAssignment, TodoAssignmentStatus, TodoStatus, local_now, new_uuid


logger = logging.getLogger(__name__)


class ExternalNotificationError(RuntimeError):
    pass


@lru_cache(maxsize=32)
def _notification_timezone(timezone_name: str) -> ZoneInfo | None:
    try:
        return ZoneInfo(timezone_name)
    except ZoneInfoNotFoundError:
        logger.error(
            "通知时区数据不可用 timezone=%s；请安装 tzdata 依赖后重启服务",
            timezone_name,
        )
    except ValueError:
        logger.error("通知时区配置无效 timezone=%s；示例：Asia/Shanghai", timezone_name)
    return None


def notification_now(settings: Settings | None = None) -> datetime:
    """Return the configured notification timezone as a naive wall-clock value."""
    current_settings = settings or get_settings()
    timezone_name = (current_settings.notification_timezone or "").strip()
    timezone = _notification_timezone(timezone_name)
    if timezone is None:
        return local_now()
    return datetime.now(timezone).replace(microsecond=0, tzinfo=None)


def _digest_time(settings: Settings) -> time:
    try:
        return time.fromisoformat(settings.notification_daily_digest_time)
    except ValueError as exc:
        raise ValueError("notification_daily_digest_time 必须是 HH:MM 格式") from exc


def external_notifications_enabled(settings: Settings | None = None) -> bool:
    return bool((settings or get_settings()).notification_http_url.strip())


def public_route_url(path: str, settings: Settings | None = None) -> str:
    """Build a browser URL for a route in the WorkFollow SPA.

    The public origin is deployment-specific, so it is never inferred from
    the notification receiver URL.  With no origin configured we retain a
    relative URL, which is useful for same-origin consumers and makes the
    missing deployment setting visible in the payload instead of silently
    linking to the wrong host.
    """
    normalized_path = path if path.startswith("/") else f"/{path}"
    current_settings = settings or get_settings()
    configured_base = (
        current_settings.server_url.strip()
        or current_settings.notification_public_url.strip()
    )
    base = configured_base.rstrip("/")
    return f"{base}{normalized_path}" if base else normalized_path


def task_public_url(task_id: str, settings: Settings | None = None) -> str:
    return public_route_url(
        f"/todos?{urlencode({'view': 'all', 'todo': task_id})}",
        settings,
    )


def _delivery_url(data_json: dict[str, object] | None, settings: Settings | None = None) -> str | None:
    """Read the canonical browser URL from a queued delivery payload."""
    if not isinstance(data_json, dict):
        return None
    direct = data_json.get("url") or data_json.get("taskUrl")
    if isinstance(direct, str) and direct.strip():
        return direct.strip()
    task = data_json.get("task")
    if isinstance(task, dict):
        nested = task.get("url") or task.get("taskUrl")
        if isinstance(nested, str) and nested.strip():
            return nested.strip()
        task_id = task.get("id")
        if isinstance(task_id, str) and task_id.strip():
            return task_public_url(task_id.strip(), settings)
    task_id = data_json.get("taskId")
    if isinstance(task_id, str) and task_id.strip():
        return task_public_url(task_id.strip(), settings)
    return None


def add_external_notification(
    db: Session,
    user_id: str,
    notification_type: NotificationType,
    message: str,
    *,
    delivery_key: str | None = None,
    data_json: dict[str, object] | None = None,
    settings: Settings | None = None,
) -> ExternalNotificationDelivery | None:
    """Add one external delivery to the current transaction without committing."""
    current_settings = settings or get_settings()
    if not external_notifications_enabled(current_settings):
        logger.info(
            "【外部通知入口】跳过 type=%s user_id=%s 原因=通知接口地址为空",
            notification_type.value,
            user_id,
        )
        return None
    user = db.get(User, user_id)
    if user is None or user.status != UserStatus.ACTIVE:
        logger.warning(
            "【外部通知入口】跳过 type=%s user_id=%s 原因=用户不存在或已停用",
            notification_type.value,
            user_id,
        )
        return None
    key = delivery_key or f"event:{new_uuid()}:{user_id}"
    if db.scalar(
        select(ExternalNotificationDelivery.id).where(ExternalNotificationDelivery.delivery_key == key)
    ) is not None:
        logger.info(
            "【外部通知入口】跳过 type=%s user_id=%s 原因=重复投递",
            notification_type.value,
            user_id,
        )
        return None
    delivery = ExternalNotificationDelivery(
        user_id=user.id,
        username=user.username,
        notification_type=notification_type,
        message=message,
        data_json=data_json or {},
        delivery_key=key,
    )
    db.add(delivery)
    logger.info(
        "【外部通知入口】加入发送队列 type=%s username=%s task_id=%s task_title=%s",
        notification_type.value,
        user.username,
        (data_json or {}).get("taskId", "-"),
        (data_json or {}).get("taskTitle", "-"),
    )
    return delivery


def add_external_notifications(
    db: Session,
    items: list[tuple[str, NotificationType, str, str, dict[str, object] | None]],
) -> list[ExternalNotificationDelivery]:
    added: list[ExternalNotificationDelivery] = []
    for user_id, notification_type, message, delivery_key, data_json in items:
        delivery = add_external_notification(
            db,
            user_id,
            notification_type,
            message,
            delivery_key=delivery_key,
            data_json=data_json,
        )
        if delivery is not None:
            added.append(delivery)
    return added


def _external_url(base_url: str, username: str, message: str, url: str | None = None) -> str:
    parsed = urlsplit(base_url)
    query = parse_qsl(parsed.query, keep_blank_values=True)
    query.extend([("userIds", username), ("msg", message)])
    if url:
        query.append(("url", url))
    return urlunsplit((parsed.scheme, parsed.netloc, parsed.path, urlencode(query), parsed.fragment))


def send_external_notification(
    username: str,
    message: str,
    settings: Settings | None = None,
    *,
    url: str | None = None,
) -> int:
    current_settings = settings or get_settings()
    base_url = current_settings.notification_http_url.strip()
    if not base_url:
        return 0
    request = Request(
        _external_url(base_url, username, message, url),
        method="GET",
        headers={"Accept": "*/*", "User-Agent": "WorkFollow-Notification/1.0"},
    )
    try:
        with urlopen(request, timeout=current_settings.notification_http_timeout_seconds) as response:
            if not 200 <= response.status < 300:
                raise ExternalNotificationError(f"外部通知接口返回 HTTP {response.status}")
            return response.status
    except HTTPError as exc:
        raise ExternalNotificationError(f"外部通知接口返回 HTTP {exc.code}") from exc
    except URLError as exc:
        raise ExternalNotificationError(f"外部通知接口请求失败：{exc.reason}") from exc
    except TimeoutError as exc:
        raise ExternalNotificationError("外部通知接口请求超时") from exc


def _claim_next_delivery(db: Session, now: datetime, settings: Settings) -> ExternalNotificationDelivery | None:
    stale_before = now - timedelta(seconds=max(current_timeout(settings) * 2, 60))
    db.execute(
        update(ExternalNotificationDelivery)
        .where(
            ExternalNotificationDelivery.status == ExternalDeliveryStatus.SENDING,
            ExternalNotificationDelivery.last_attempt_at.is_not(None),
            ExternalNotificationDelivery.last_attempt_at < stale_before,
        )
        .values(status=ExternalDeliveryStatus.PENDING, next_attempt_at=now)
    )
    db.commit()
    delivery_id = db.scalar(
        select(ExternalNotificationDelivery.id)
        .where(
            ExternalNotificationDelivery.status == ExternalDeliveryStatus.PENDING,
            ExternalNotificationDelivery.next_attempt_at <= now,
        )
        .order_by(ExternalNotificationDelivery.created_at.asc())
        .limit(1)
    )
    if delivery_id is None:
        return None
    result = db.execute(
        update(ExternalNotificationDelivery)
        .where(
            ExternalNotificationDelivery.id == delivery_id,
            ExternalNotificationDelivery.status == ExternalDeliveryStatus.PENDING,
        )
        .values(
            status=ExternalDeliveryStatus.SENDING,
            attempts=ExternalNotificationDelivery.attempts + 1,
            last_attempt_at=now,
        )
    )
    db.commit()
    if result.rowcount != 1:
        return None
    return db.get(ExternalNotificationDelivery, delivery_id)


def current_timeout(settings: Settings) -> float:
    return max(float(settings.notification_http_timeout_seconds), 0.1)


def _finish_delivery(
    db: Session,
    delivery: ExternalNotificationDelivery,
    now: datetime,
    error: Exception | None,
    settings: Settings,
) -> None:
    if error is None:
        delivery.status = ExternalDeliveryStatus.SENT
        delivery.sent_at = now
        delivery.last_error = None
    elif delivery.attempts >= max(settings.notification_http_retry_count, 1):
        delivery.status = ExternalDeliveryStatus.FAILED
        delivery.last_error = str(error)[:2000]
    else:
        delivery.status = ExternalDeliveryStatus.PENDING
        delivery.last_error = str(error)[:2000]
        delay_seconds = min(300, 2 ** max(delivery.attempts - 1, 0))
        delivery.next_attempt_at = now + timedelta(seconds=delay_seconds)
    db.commit()


def dispatch_pending(
    db: Session,
    *,
    settings: Settings | None = None,
    now: datetime | None = None,
    max_items: int = 100,
) -> int:
    current_settings = settings or get_settings()
    if not external_notifications_enabled(current_settings):
        return 0
    sent_count = 0
    for _ in range(max_items):
        current = now or notification_now(current_settings)
        delivery = _claim_next_delivery(db, current, current_settings)
        if delivery is None:
            break
        error: Exception | None = None
        http_status: int | None = None
        try:
            http_status = send_external_notification(
                delivery.username,
                delivery.message,
                current_settings,
                url=_delivery_url(delivery.data_json, current_settings),
            )
        except Exception as exc:  # delivery state must be persisted for every network failure
            error = exc
        _finish_delivery(db, delivery, current, error, current_settings)
        if error is None:
            sent_count += 1
            logger.info(
                "外部通知发送成功 delivery_id=%s type=%s username=%s attempts=%s http_status=%s",
                delivery.id,
                delivery.notification_type.value,
                delivery.username,
                delivery.attempts,
                http_status,
            )
        elif delivery.status == ExternalDeliveryStatus.FAILED:
            logger.error(
                "外部通知最终失败 delivery_id=%s type=%s username=%s attempts=%s error=%s",
                delivery.id,
                delivery.notification_type.value,
                delivery.username,
                delivery.attempts,
                error,
            )
        else:
            logger.warning(
                "外部通知发送失败，将重试 delivery_id=%s type=%s username=%s attempts=%s error=%s",
                delivery.id,
                delivery.notification_type.value,
                delivery.username,
                delivery.attempts,
                error,
            )
    return sent_count


def _daily_due_label(due_at: datetime) -> str:
    result = due_at.strftime("%m月%d日")
    if due_at.time() != time.min:
        result += due_at.strftime(" %H:%M")
    return result


def _daily_message(
    overdue: list[tuple[str, str, datetime]],
    today: list[tuple[str, str, datetime]],
    url: str,
) -> str:
    def labels(rows: list[tuple[str, str, datetime]]) -> str:
        return "、".join(f"{title}（{_daily_due_label(due_at)}）" for _, title, due_at in rows[:5])

    parts: list[str] = []
    if overdue:
        suffix = "" if len(overdue) <= 5 else f"；另有 {len(overdue) - 5} 项未展开"
        parts.append(f"逾期 {len(overdue)} 项：{labels(overdue)}{suffix}")
    if today:
        suffix = "" if len(today) <= 5 else f"；另有 {len(today) - 5} 项未展开"
        parts.append(f"今日 {len(today)} 项：{labels(today)}{suffix}")
    return "【每日待办】" + "；".join(parts) + f"；查看今日待办：{url}"


def enqueue_daily_task_digests(
    db: Session,
    *,
    settings: Settings | None = None,
    now: datetime | None = None,
) -> int:
    current_settings = settings or get_settings()
    if not external_notifications_enabled(current_settings):
        return 0
    current = now or notification_now(current_settings)
    if current.time() < _digest_time(current_settings):
        return 0
    start = datetime.combine(current.date(), time.min)
    end = start + timedelta(days=1)
    users = db.scalars(select(User).where(User.status == UserStatus.ACTIVE)).all()
    added = 0
    for user in users:
        rows = db.execute(
            select(Todo.id, Todo.title, Todo.due_at)
            .join(TodoAssignment, TodoAssignment.task_id == Todo.id)
            .where(
                TodoAssignment.user_id == user.id,
                TodoAssignment.active.is_(True),
                TodoAssignment.status != TodoAssignmentStatus.DONE,
                Todo.status == TodoStatus.TODO,
                Todo.due_at.is_not(None),
                Todo.due_at < end,
            )
            .order_by(Todo.due_at.asc(), Todo.created_at.asc())
        ).all()
        overdue = [(task_id, title, due_at) for task_id, title, due_at in rows if due_at < start]
        today = [(task_id, title, due_at) for task_id, title, due_at in rows if start <= due_at < end]
        if not overdue and not today:
            continue
        event_key = f"daily-task-digest:{current.date().isoformat()}"
        delivery_key = f"{event_key}:{user.id}"
        legacy_delivery_key = f"daily-task-digest:{user.id}:{current.date().isoformat()}"
        if db.scalar(
            select(ExternalNotificationDelivery.id).where(
                ExternalNotificationDelivery.delivery_key.in_((delivery_key, legacy_delivery_key))
            )
        ) is not None:
            continue
        from app.services import notification_dispatcher

        digest_url = public_route_url("/todos?view=today", current_settings)
        message = _daily_message(overdue, today, digest_url)
        result = notification_dispatcher.dispatch_event(
            db,
            event="DAILY_TASK_DIGEST",
            participant_ids=[user.id],
            actor_user_id=None,
            in_app_type=NotificationType.DAILY_TASK_DIGEST,
            external_type=NotificationType.DAILY_TASK_DIGEST,
            title="每日待办提醒",
            body=message,
            external_message=message,
            data_json={
                "date": current.date().isoformat(),
                "overdueTaskIds": [task_id for task_id, _, _ in overdue],
                "todayTaskIds": [task_id for task_id, _, _ in today],
                "overdueTasks": [
                    {
                        "id": task_id,
                        "title": title,
                        "dueAt": due_at.isoformat(),
                        "url": task_public_url(task_id, current_settings),
                    }
                    for task_id, title, due_at in overdue
                ],
                "todayTasks": [
                    {
                        "id": task_id,
                        "title": title,
                        "dueAt": due_at.isoformat(),
                        "url": task_public_url(task_id, current_settings),
                    }
                    for task_id, title, due_at in today
                ],
                "url": digest_url,
                "eventKey": event_key,
            },
            event_key=event_key,
            settings=current_settings,
            commit=False,
        )
        added += result.changed
    if added:
        db.commit()
        logger.info(
            "每日待办统一通知已分发 date=%s count=%s",
            current.date().isoformat(),
            added,
        )
    return added


class NotificationWorker:
    """Single-process dispatcher used by the packaged FastAPI deployment."""

    def __init__(self, settings: Settings | None = None) -> None:
        self.settings = settings or get_settings()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        if self._thread is not None:
            return
        self._thread = threading.Thread(target=self._run, name="workfollow-notifications", daemon=True)
        self._thread.start()
        logger.info(
            "通知后台发送器已启动 interval_seconds=%s external_enabled=%s",
            self.settings.notification_worker_interval_seconds,
            external_notifications_enabled(self.settings),
        )

    def stop(self) -> None:
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=max(self.settings.notification_worker_interval_seconds + 1, 3))
            self._thread = None
            logger.info("通知后台发送器已停止")

    def _run(self) -> None:
        # Import lazily because task_notification_service itself uses this
        # module for URL construction and external delivery helpers.
        from app.services.task_notification_service import (
            dispatch_pending_task_update_notifications,
        )

        while not self._stop.is_set():
            try:
                with SessionLocal() as db:
                    dispatch_pending_task_update_notifications(db, settings=self.settings)
                    enqueue_daily_task_digests(db, settings=self.settings)
                    dispatch_pending(db, settings=self.settings)
            except Exception:
                logger.exception("通知后台任务执行失败")
            self._stop.wait(max(self.settings.notification_worker_interval_seconds, 0.5))
