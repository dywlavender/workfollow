from fastapi import APIRouter, Query, Response, status

from app.core.dependencies import CurrentUser, DbSession
from app.schemas.notification import NotificationRead, NotificationReadResult, NotificationUnreadCount
from app.services import notification_service


router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("", response_model=list[NotificationRead])
def get_notifications(
    db: DbSession,
    user: CurrentUser,
    unread_only: bool = Query(default=False, alias="unreadOnly"),
    limit: int = Query(default=100, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
) -> list[NotificationRead]:
    return notification_service.list_notifications(db, user.id, unread_only, limit, offset)


@router.get("/unread/count", response_model=NotificationUnreadCount)
def get_unread_count(db: DbSession, user: CurrentUser) -> NotificationUnreadCount:
    return NotificationUnreadCount(count=notification_service.count_unread(db, user.id))


@router.post("/{notification_id}/read", response_model=NotificationReadResult)
def read_notification(notification_id: str, db: DbSession, user: CurrentUser) -> NotificationReadResult:
    notification = notification_service.mark_read(db, notification_id, user.id)
    return NotificationReadResult(id=notification.id, read_at=notification.read_at)


@router.post("/read-all", response_model=dict[str, int])
def read_all_notifications(db: DbSession, user: CurrentUser) -> dict[str, int]:
    return {"updated": notification_service.mark_all_read(db, user.id)}


@router.delete("/{notification_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_notification(notification_id: str, db: DbSession, user: CurrentUser) -> Response:
    notification_service.delete_notification(db, notification_id, user.id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("", status_code=status.HTTP_204_NO_CONTENT)
def delete_all_notifications(db: DbSession, user: CurrentUser) -> Response:
    notification_service.delete_all_notifications(db, user.id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
