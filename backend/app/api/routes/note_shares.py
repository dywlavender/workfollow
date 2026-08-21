from __future__ import annotations

from fastapi import APIRouter, Response, status

from app.core.dependencies import CurrentSettings, CurrentUser, DbSession
from app.schemas.note import AttachmentRead, NoteRead
from app.schemas.note_share import NoteShareCreate, NoteShareRead, SharedNoteRead
from app.services import audit_service, note_service, note_share_service
from app.models.notification import NotificationType
from app.services.notification_service import notify_user


router = APIRouter(tags=["note-shares"])


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
        previous_ids = {item.shared_with_user_id for item in note_share_service.list_note_shares(db, note.id, user.id)}
        shares = note_share_service.sync_note_shares(db, note, user.id, payload.user_ids)
        current_ids = {item.shared_with_user_id for item in shares}
        for share in shares:
            if share.shared_with_user_id not in previous_ids:
                notify_user(
                    db,
                    share.shared_with_user_id,
                    NotificationType.NOTE_SHARED,
                    "你收到一篇共享笔记",
                    f"用户 {user.nickname} 向你共享了“{note.title}”（只读）。",
                    actor_user_id=user.id,
                    data_json={"noteId": note_id, "shareId": share.id},
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
    notify_user(
        db,
        share.shared_with_user_id,
        NotificationType.NOTE_SHARED,
        "你收到一篇共享笔记",
        f"用户 {user.nickname} 向你共享了“{note.title}”（只读）。",
        actor_user_id=user.id,
        data_json={"noteId": note_id, "shareId": share.id},
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
    note_service.get_note_or_404(db, note_id, user.id)
    share = note_share_service.get_share_or_404(db, note_id, share_id, user.id)
    note_share_service.revoke_note_share(db, share)
    audit_service.record_audit(
        db, actor_user_id=user.id, action="NOTE_SHARE_REVOKED", resource_type="NOTE_SHARE", resource_id=share_id,
        metadata_json={"noteId": note_id, "sharedWithUserId": share.shared_with_user_id},
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/shared/notes", response_model=list[SharedNoteRead])
def list_shared_notes(db: DbSession, user: CurrentUser) -> list[SharedNoteRead]:
    return [_shared_note_read(note, share) for note, share in note_share_service.list_shared_notes(db, user.id)]


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
        source_attachments=list(source.attachments),
        owner_id=user.id,
        settings=settings,
        copied_from_note_id=source.id,
    )
