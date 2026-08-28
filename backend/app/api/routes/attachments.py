from datetime import date
from pathlib import Path
from typing import Annotated
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Response, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.dependencies import CurrentUser, DbSession
from app.models.note import Attachment, Note
from app.models.todo import TaskFileAccess
from app.models.team_note import SubmissionFileAccess, TeamFileAccess
from app.schemas.note import AttachmentRead
from app.services.note_service import embedded_image_attachment_ids, get_note_or_404
from app.services.note_share_service import can_read_shared_note
from app.services.team_note_service import can_access_attachment
from app.services import todo_service


router = APIRouter(prefix="/attachments", tags=["attachments"])
AppSettings = Annotated[Settings, Depends(get_settings)]
ALLOWED_SUFFIXES = {
    "png", "jpg", "jpeg", "webp", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
    "md", "txt", "mp4", "mov", "m4v", "webm",
}


def attachment_read(attachment: Attachment) -> AttachmentRead:
    return AttachmentRead.model_validate(attachment).model_copy(update={"url": f"/api/attachments/{attachment.id}"})


def get_attachment_or_404(db: Session, attachment_id: str) -> Attachment:
    attachment = db.get(Attachment, attachment_id)
    if attachment is None:
        raise HTTPException(status_code=404, detail="Attachment not found")
    return attachment


@router.get("", response_model=list[AttachmentRead])
def list_attachments(note_id: str, db: DbSession, user: CurrentUser) -> list[AttachmentRead]:
    note = db.get(Note, note_id)
    if note is None or note.deleted_at is not None or (note.owner_id != user.id and not can_read_shared_note(db, note_id, user.id)):
        raise HTTPException(status_code=404, detail="Note not found")
    items = db.scalars(select(Attachment).where(Attachment.note_id == note_id).order_by(Attachment.created_at))
    return [attachment_read(item) for item in items]


@router.post("", response_model=AttachmentRead, status_code=status.HTTP_201_CREATED)
async def upload_attachment(
    db: DbSession,
    settings: AppSettings,
    user: CurrentUser,
    note_id: Annotated[str, Form(alias="noteId")],
    file: Annotated[UploadFile, File()],
) -> AttachmentRead:
    get_note_or_404(db, note_id, user.id)
    original_name = Path(file.filename or "attachment").name
    suffix = Path(original_name).suffix.lower().lstrip(".")
    if suffix not in ALLOWED_SUFFIXES:
        raise HTTPException(status_code=415, detail="不支持的附件类型")
    content = await file.read(settings.max_upload_bytes + 1)
    if len(content) > settings.max_upload_bytes:
        raise HTTPException(status_code=413, detail="附件不能超过 25MB")

    today = date.today()
    storage_name = f"{uuid4()}.{suffix}"
    relative_path = Path("data") / "files" / f"{today.year:04d}" / f"{today.month:02d}" / storage_name
    target = settings.files_dir / f"{today.year:04d}" / f"{today.month:02d}" / storage_name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(content)

    attachment = Attachment(
        owner_id=user.id,
        note_id=note_id,
        original_name=original_name,
        storage_name=storage_name,
        mime_type=file.content_type or "application/octet-stream",
        size=len(content),
        file_path=relative_path.as_posix(),
    )
    db.add(attachment)
    db.commit()
    db.refresh(attachment)
    return attachment_read(attachment)


@router.post("/task", response_model=AttachmentRead, status_code=status.HTTP_201_CREATED)
@router.post("/team-task", response_model=AttachmentRead, status_code=status.HTTP_201_CREATED, include_in_schema=False)
async def upload_team_task_attachment(
    db: DbSession,
    settings: AppSettings,
    user: CurrentUser,
    task_id: Annotated[str, Form(alias="taskId")],
    file: Annotated[UploadFile, File()],
    team_id: Annotated[str | None, Form(alias="teamId")] = None,
) -> AttachmentRead:
    task = todo_service.get_todo_or_404(db, task_id, user.id)
    if task.team_id is None:
        todo_service.require_creator(task, user.id)
    else:
        if not todo_service.can_edit_content(db, task, user.id):
            raise HTTPException(status_code=403, detail="没有修改该任务正文的权限")
    if team_id is not None and task.team_id not in (None, team_id):
        raise HTTPException(status_code=404, detail="Task not found")
    original_name = Path(file.filename or "attachment").name
    suffix = Path(original_name).suffix.lower().lstrip(".")
    if suffix not in ALLOWED_SUFFIXES:
        raise HTTPException(status_code=415, detail="不支持的附件类型")
    content = await file.read(settings.max_upload_bytes + 1)
    if len(content) > settings.max_upload_bytes:
        raise HTTPException(status_code=413, detail="附件不能超过 25MB")

    today = date.today()
    storage_name = f"{uuid4()}.{suffix}"
    relative_path = Path("data") / "files" / f"{today.year:04d}" / f"{today.month:02d}" / storage_name
    target = settings.files_dir / f"{today.year:04d}" / f"{today.month:02d}" / storage_name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(content)
    attachment = Attachment(
        owner_id=user.id,
        note_id=None,
        original_name=original_name,
        storage_name=storage_name,
        mime_type=file.content_type or "application/octet-stream",
        size=len(content),
        file_path=relative_path.as_posix(),
    )
    db.add(attachment)
    db.flush()
    task.attachment_ids = [*list(task.attachment_ids or []), attachment.id]
    db.add(TaskFileAccess(task_id=task.id, attachment_id=attachment.id, granted_by_id=user.id))
    db.commit()
    db.refresh(attachment)
    return attachment_read(attachment)


@router.get("/{attachment_id}")
def download_attachment(attachment_id: str, db: DbSession, settings: AppSettings, user: CurrentUser) -> FileResponse:
    attachment = get_attachment_or_404(db, attachment_id)
    # Personal ownership or an explicit active-team TeamFileAccess grant is
    # required. Membership is checked again here, so removing a member
    # immediately revokes access even if a cached URL is still visible.
    if not can_access_attachment(db, attachment, user.id):
        raise HTTPException(status_code=404, detail="Attachment not found")
    target = settings.files_dir.parent.parent / attachment.file_path
    if not target.is_file():
        raise HTTPException(status_code=404, detail="Attachment file not found")
    return FileResponse(target, media_type=attachment.mime_type, filename=attachment.original_name)


@router.delete("/{attachment_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_attachment(attachment_id: str, db: DbSession, settings: AppSettings, user: CurrentUser) -> Response:
    attachment = get_attachment_or_404(db, attachment_id)
    if attachment.note_id is None:
        access = db.scalar(select(TaskFileAccess).where(TaskFileAccess.attachment_id == attachment.id))
        if access is None:
            raise HTTPException(status_code=404, detail="Attachment not found")
        task = todo_service.get_todo_or_404(db, access.task_id, user.id)
        if task.team_id is None:
            todo_service.require_creator(task, user.id)
        else:
            # Members may edit the shared body and upload a file into it, but
            # deleting a binary is a task-level metadata/destructive action.
            # Keep that operation with the creator/team administrators; this
            # also prevents one assignee from removing a file another assignee
            # is still using.
            if not todo_service.can_edit(db, task, user.id):
                raise HTTPException(status_code=403, detail="没有删除该任务附件的权限")
        if task is not None:
            task.attachment_ids = [item for item in (task.attachment_ids or []) if item != attachment.id]
    else:
        note = get_note_or_404(db, attachment.note_id, user.id)
        if attachment.id in embedded_image_attachment_ids(note.content_json):
            raise HTTPException(status_code=409, detail="图片正在正文中使用，请先从正文移除图片")
        # A submission snapshot or published knowledge entry owns an independent
        # reference to the binary. Removing it from the personal note must not
        # destroy the team's copy of that resource.
        retained_elsewhere = db.scalar(select(TeamFileAccess.id).where(
            TeamFileAccess.attachment_id == attachment.id
        ).limit(1)) or db.scalar(select(SubmissionFileAccess.id).where(
            SubmissionFileAccess.attachment_id == attachment.id
        ).limit(1))
        if retained_elsewhere:
            attachment.note_id = None
            db.commit()
            return Response(status_code=status.HTTP_204_NO_CONTENT)
    target = settings.files_dir.parent.parent / attachment.file_path
    target.unlink(missing_ok=True)
    db.delete(attachment)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
