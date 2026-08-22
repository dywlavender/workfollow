from __future__ import annotations

from fastapi import APIRouter, Query, Response, status

from app.core.dependencies import CurrentSettings, CurrentUser, DbSession
from app.models.note_share import NoteShareStatus
from app.models.notification import NotificationType
from app.schemas.note import AttachmentRead, NoteRead
from app.schemas.note_share import NoteShareCreate, NoteShareRead, SharedNoteRead
from app.services import audit_service, note_service, note_share_service, notification_dispatcher


router = APIRouter(tags=["note-shares"])


def _dispatch_share_notification(
    db,
    *,
    note,
    recipient_id: str,
    actor_id: str,
    actor_name: str,
    share_id: str,
    revoked: bool = False,
    event_key: str | None = None,
) -> None:  # noqa: ANN001
    notification_type = NotificationType.NOTE_SHARE_REVOKED if revoked else NotificationType.NOTE_SHARED
    title = "共享权限已取消" if revoked else "你收到一篇共享笔记"
    body = (
        f"用户 {actor_name} 已取消与你共享“{note.title}”。"
        if revoked
        else f"用户 {actor_name} 向你共享了“{note.title}”（只读）。"
    )
    data_json = {"noteId": note.id, "shareId": share_id}
    if event_key:
        data_json["eventKey"] = event_key
    notification_dispatcher.dispatch_event(
        db,
        event="note_share_revoked" if revoked else "note_shared",
        participant_ids=[recipient_id],
        actor_user_id=actor_id,
        in_app_type=notification_type,
        external_type=None,
        title=title,
        body=body,
        data_json=data_json,
        event_key=event_key,
    )


def _shared_note_read(note, share) -> SharedNoteRead:  # noqa: ANN001
    base = NoteRead.model_validate(note)
    attachments = [
        AttachmentRead.model_validate(item).model_copy(update={"url": f"/api/attachments/{item.id}"})
        for item in note.attachments
    ]
    return SharedNoteRead.model_validate(
        {
            **base.model_dump(),
            "attachments": attachments,
            "shared_by_user_id": share.shared_by_user_id,
            "shared_by": share.shared_by,
            "permission": share.permission,
        }
    )


@router.post("/notes/{note_id}/shares", response_model=NoteShareRead | list[NoteShareRead], status_code=status.HTTP_201_CREATED)
def create_share(note_id: str, payload: NoteShareCreate, db: DbSession, user: CurrentUser) -> NoteShareRead | list[NoteShareRead]:
    note = note_service.get_note_or_404(db, note_id, user.id)
    if payload.user_ids is not None:
        previous_shares = note_share_service.list_note_shares(db, note.id, user.id, include_revoked=True)
        previous_by_user = {item.shared_with_user_id: item for item in previous_shares}
        previous_ids = {
            item.shared_with_user_id
            for item in previous_shares
            if item.status == NoteShareStatus.ACTIVE
        }
        shares = note_share_service.sync_note_shares(db, note, user.id, payload.user_ids)
        current_ids = {item.shared_with_user_id for item in shares}
        for share in shares:
            if share.shared_with_user_id not in previous_ids:
                previous = previous_by_user.get(share.shared_with_user_id)
                _dispatch_share_notification(
                    db,
                    note=note,
                    recipient_id=share.shared_with_user_id,
                    actor_id=user.id,
                    actor_name=user.nickname,
                    share_id=share.id,
                    event_key=(
                        f"note-share-granted:{share.id}:"
                        f"{previous.revoked_at.isoformat() if previous and previous.revoked_at else 'initial'}"
                    ),
                )
        for user_id in previous_ids - current_ids:
            revoked_share = previous_by_user[user_id]
            _dispatch_share_notification(
                db,
                note=note,
                recipient_id=user_id,
                actor_id=user.id,
                actor_name=user.nickname,
                share_id=revoked_share.id,
                revoked=True,
                event_key=(
                    f"note-share-revoked:{revoked_share.id}:"
                    f"{revoked_share.revoked_at.isoformat() if revoked_share.revoked_at else 'unknown'}"
                ),
            )
        audit_service.record_audit(
            db, actor_user_id=user.id, action="NOTE_SHARES_SYNCED", resource_type="NOTE", resource_id=note.id,
            metadata_json={
                "sharedWithUserIds": sorted(current_ids),
                "revokedUserIds": sorted(previous_ids - current_ids),
            },
        )
        return shares
    share = note_share_service.create_note_share(db, note, user.id, payload)
    _dispatch_share_notification(
        db,
        note=note,
        recipient_id=share.shared_with_user_id,
        actor_id=user.id,
        actor_name=user.nickname,
        share_id=share.id,
    )
    audit_service.record_audit(
        db, actor_user_id=user.id, action="NOTE_SHARE_CREATED", resource_type="NOTE_SHARE", resource_id=share.id,
        metadata_json={"noteId": note_id, "sharedWithUserId": share.shared_with_user_id},
    )
    return share


@router.get("/notes/{note_id}/shares", response_model=list[NoteShareRead])
def list_shares(note_id: str, db: DbSession, user: CurrentUser) -> list[NoteShareRead]:
    note_service.get_note_or_404(db, note_id, user.id)
    return note_share_service.list_note_shares(db, note_id, user.id)


@router.delete("/notes/{note_id}/shares/{share_id}", status_code=status.HTTP_204_NO_CONTENT)
def revoke_share(note_id: str, share_id: str, db: DbSession, user: CurrentUser) -> Response:
    note = note_service.get_note_or_404(db, note_id, user.id)
    share = note_share_service.get_share_or_404(db, note_id, share_id, user.id)
    note_share_service.revoke_note_share(db, share)
    _dispatch_share_notification(
        db,
        note=note,
        recipient_id=share.shared_with_user_id,
        actor_id=user.id,
        actor_name=user.nickname,
        share_id=share.id,
        revoked=True,
        event_key=(
            f"note-share-revoked:{share.id}:"
            f"{share.revoked_at.isoformat() if share.revoked_at else 'unknown'}"
        ),
    )
    audit_service.record_audit(
        db, actor_user_id=user.id, action="NOTE_SHARE_REVOKED", resource_type="NOTE_SHARE", resource_id=share_id,
        metadata_json={"noteId": note_id, "sharedWithUserId": share.shared_with_user_id},
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/shared/notes", response_model=list[SharedNoteRead])
def list_shared_notes(
    db: DbSession,
    user: CurrentUser,
    q: str | None = Query(default=None, max_length=200),
) -> list[SharedNoteRead]:
    return [_shared_note_read(note, share) for note, share in note_share_service.list_shared_notes(db, user.id, q=q)]


@router.get("/shared/notes/{note_id}", response_model=SharedNoteRead)
def get_shared_note(note_id: str, db: DbSession, user: CurrentUser) -> SharedNoteRead:
    note, share = note_share_service.get_shared_note_or_404(db, note_id, user.id)
    return _shared_note_read(note, share)


@router.post("/shared/notes/{note_id}/copy", response_model=NoteRead, status_code=status.HTTP_201_CREATED)
def copy_shared_note(note_id: str, db: DbSession, settings: CurrentSettings, user: CurrentUser) -> NoteRead:
    source, _share = note_share_service.get_shared_note_or_404(db, note_id, user.id)
    return note_service.copy_note_with_attachments(
        db,
        title=source.title,
        content_json=source.content_json,
        plain_text=source.plain_text,
        tags=source.tags,
        source_attachments=list(source.attachments),
        owner_id=user.id,
        settings=settings,
        copied_from_note_id=source.id,
    )
