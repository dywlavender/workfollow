from datetime import date
from pathlib import Path
from typing import Annotated
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Response, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.dependencies import CurrentUser, DbSession
from app.models.note import Attachment, Note
from app.models.todo import TaskFileAccess, Todo
from app.models.team_note import SubmissionFileAccess, TeamFileAccess, TeamNote
from app.schemas.note import AttachmentRead
from app.services.note_permission_service import can_edit_team_note, has_editable_share
from app.services.note_service import attachment_ids_in_document, embedded_rendered_attachment_ids, get_note_or_404
from app.services.note_share_service import can_read_shared_note
from app.services.team_note_service import can_access_attachment
from app.services import todo_service


router = APIRouter(prefix="/attachments", tags=["attachments"])
AppSettings = Annotated[Settings, Depends(get_settings)]
ALLOWED_SUFFIXES = {
    "png", "jpg", "jpeg", "webp", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
    "md", "txt", "mp4", "mov", "m4v", "webm", "drawio",
}
DIAGRAM_SOURCE_SUFFIX = ".drawio"


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
    note = db.get(Note, note_id)
    # The owner and EDITABLE share holders may add binaries (pasted images,
    # standalone files). Read-only share holders cannot.
    if note is None or note.deleted_at is not None or (
        note.owner_id != user.id and not has_editable_share(db, note_id, user.id)
    ):
        raise HTTPException(status_code=404, detail="Note not found")
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


def _diagram_snapshot_referenced(db: Session, attachment_id: str) -> bool:
    """投稿或已发布团队知识是否仍持有该字节——持有则不允许原地覆盖。"""

    if db.scalar(select(SubmissionFileAccess.id).where(SubmissionFileAccess.attachment_id == attachment_id).limit(1)):
        return True
    return db.scalar(select(TeamFileAccess.id).where(TeamFileAccess.attachment_id == attachment_id).limit(1)) is not None


def _resolve_diagram_edit_context(db: Session, user: CurrentUser, source: Attachment, preview: Attachment):
    """流程图两张附件必须同属一个笔记、代办或团队知识，且用户有对应编辑权。

    判定顺序：贡献者本人或有可编辑分享的协作者按笔记上下文（图被团队快照
    引用时保存会自动 COW）；团队知识授权（TeamFileAccess）持有附件时按团队
    知识上下文放行给可编辑成员；再退回代办；都不匹配则拒绝。
    """

    if (source.note_id is None) != (preview.note_id is None) or (
        source.note_id is not None and source.note_id != preview.note_id
    ):
        raise HTTPException(status_code=400, detail="流程图源与预览不属于同一个笔记")

    if source.note_id is not None:
        note = db.get(Note, source.note_id)
        if note is not None and note.deleted_at is None and (
            note.owner_id == user.id or has_editable_share(db, source.note_id, user.id)
        ):
            return note
        # 发布到团队知识后，附件同时挂在贡献者的原笔记下并持有团队授权；
        # 团队知识的可编辑成员按团队知识上下文放行。
        source_grant = db.scalar(select(TeamFileAccess).where(TeamFileAccess.attachment_id == source.id))
        preview_grant = db.scalar(select(TeamFileAccess).where(TeamFileAccess.attachment_id == preview.id))
        if source_grant is not None and preview_grant is not None and source_grant.team_note_id == preview_grant.team_note_id:
            team_note = db.get(TeamNote, source_grant.team_note_id)
            if team_note is not None and can_edit_team_note(db, team_note, user.id):
                return team_note
        raise HTTPException(status_code=403, detail="没有修改该流程图的权限")

    # note_id 为空：团队知识附件或代办附件。
    source_grant = db.scalar(select(TeamFileAccess).where(TeamFileAccess.attachment_id == source.id))
    preview_grant = db.scalar(select(TeamFileAccess).where(TeamFileAccess.attachment_id == preview.id))
    if source_grant is not None and preview_grant is not None and source_grant.team_note_id == preview_grant.team_note_id:
        team_note = db.get(TeamNote, source_grant.team_note_id)
        if team_note is not None and can_edit_team_note(db, team_note, user.id):
            return team_note

    task_source = db.scalar(select(TaskFileAccess).where(TaskFileAccess.attachment_id == source.id))
    task_preview = db.scalar(select(TaskFileAccess).where(TaskFileAccess.attachment_id == preview.id))
    if task_source is None or task_preview is None or task_source.task_id != task_preview.task_id:
        raise HTTPException(status_code=400, detail="流程图源与预览不属于同一个笔记、代办或团队知识")
    task = todo_service.get_todo_or_404(db, task_source.task_id, user.id)
    if task.team_id is None:
        todo_service.require_creator(task, user.id)
    elif not todo_service.can_edit_content(db, task, user.id):
        raise HTTPException(status_code=403, detail="没有修改该代办的流程图权限")
    return task


def _copy_diagram_attachment(
    db: Session,
    settings: Settings,
    template: Attachment,
    content: bytes,
    *,
    note_id: str | None,
) -> Attachment:
    today = date.today()
    suffix = Path(template.original_name).suffix.lower().lstrip(".") or "bin"
    storage_name = f"{uuid4()}.{suffix}"
    relative_path = Path("data") / "files" / f"{today.year:04d}" / f"{today.month:02d}" / storage_name
    target = settings.files_dir / f"{today.year:04d}" / f"{today.month:02d}" / storage_name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(content)
    attachment = Attachment(
        owner_id=template.owner_id,
        note_id=note_id,
        original_name=template.original_name,
        storage_name=storage_name,
        mime_type=template.mime_type,
        size=len(content),
        revision=1,
        file_path=relative_path.as_posix(),
    )
    db.add(attachment)
    return attachment


def _replace_attachment_bytes(settings: Settings, attachment: Attachment, content: bytes) -> None:
    target = settings.files_dir.parent.parent / attachment.file_path
    if not target.is_file():
        raise HTTPException(status_code=404, detail="Attachment file not found")
    temp = target.with_name(f"{target.name}.tmp-{uuid4().hex}")
    temp.write_bytes(content)
    temp.replace(target)


@router.put("/diagram-content")
async def save_diagram_content(
    db: DbSession,
    settings: AppSettings,
    user: CurrentUser,
    sourceAttachmentId: Annotated[str, Form()],
    previewAttachmentId: Annotated[str, Form()],
    expectedRevision: Annotated[int, Form()],
    file: Annotated[UploadFile, File()],
    preview: Annotated[UploadFile, File()],
) -> dict:
    """流程图源与预览的一次性成对保存。

    无快照引用时原地覆盖：revision 条件更新充当乐观锁，两行任一不匹配整体
    409；任一附件被投稿/发布快照持有时整体写时复制出新的一对，旧附件脱离
    笔记继续服务原快照。文件先写临时名再原子改名，两个文件与数据库行在同
    一事务内生效。
    """
    source_attachment = get_attachment_or_404(db, sourceAttachmentId)
    preview_attachment = get_attachment_or_404(db, previewAttachmentId)
    context = _resolve_diagram_edit_context(db, user, source_attachment, preview_attachment)
    is_task_context = isinstance(context, Todo)
    payload = await file.read(settings.max_upload_bytes + 1)
    preview_payload = await preview.read(settings.max_upload_bytes + 1)
    if len(payload) > settings.max_upload_bytes or len(preview_payload) > settings.max_upload_bytes:
        raise HTTPException(status_code=413, detail="流程图文件不能超过 25MB")

    if _diagram_snapshot_referenced(db, source_attachment.id) or _diagram_snapshot_referenced(db, preview_attachment.id):
        # 团队知识上下文的新对以纯团队附件存在（note_id 为空，靠复制出的
        # TeamFileAccess 授权行服务团队访问），不挂在贡献者的个人笔记下，
        # 避免贡献者删除笔记时连坐团队正在使用的图。
        is_team_context = isinstance(context, TeamNote)
        note_id = None if is_team_context else source_attachment.note_id
        new_source = _copy_diagram_attachment(db, settings, source_attachment, payload, note_id=note_id)
        new_preview = _copy_diagram_attachment(db, settings, preview_attachment, preview_payload, note_id=note_id)
        db.flush()
        # 旧一对脱离当前笔记，继续服务已提交的快照（retained_elsewhere 语义）。
        source_attachment.note_id = None
        preview_attachment.note_id = None
        if isinstance(context, TeamNote):
            # 团队知识上下文：新对以团队附件形式存在（note_id 为空），并复制
            # 团队授权行，团队成员（含贡献者之外的人）继续可见与可编辑。
            for old_attachment, new_attachment in ((source_attachment, new_source), (preview_attachment, new_preview)):
                for grant in db.scalars(select(TeamFileAccess).where(TeamFileAccess.attachment_id == old_attachment.id)):
                    db.add(TeamFileAccess(
                        team_id=grant.team_id,
                        team_note_id=grant.team_note_id,
                        attachment_id=new_attachment.id,
                        granted_by_id=user.id,
                    ))
        elif is_task_context:
            task = context
            db.add(TaskFileAccess(task_id=task.id, attachment_id=new_source.id, granted_by_id=user.id))
            db.add(TaskFileAccess(task_id=task.id, attachment_id=new_preview.id, granted_by_id=user.id))
            task.attachment_ids = [
                new_source.id if item == source_attachment.id else new_preview.id if item == preview_attachment.id else item
                for item in (task.attachment_ids or [])
            ]
        db.commit()
        db.refresh(new_source)
        db.refresh(new_preview)
        return {
            "sourceAttachmentId": new_source.id,
            "previewAttachmentId": new_preview.id,
            "revision": new_source.revision,
            "copied": True,
        }

    result_source = db.execute(
        update(Attachment)
        .where(Attachment.id == source_attachment.id, Attachment.revision == expectedRevision)
        .values(revision=expectedRevision + 1, size=len(payload))
    )
    result_preview = db.execute(
        update(Attachment)
        .where(Attachment.id == previewAttachmentId, Attachment.revision == expectedRevision)
        .values(revision=expectedRevision + 1, size=len(preview_payload))
    )
    if result_source.rowcount != 1 or result_preview.rowcount != 1:
        db.rollback()
        current = db.get(Attachment, source_attachment.id)
        raise HTTPException(
            status_code=409,
            detail={"message": "流程图已被他人更新，请选择覆盖或加载最新版本", "currentRevision": current.revision if current else expectedRevision},
        )
    _replace_attachment_bytes(settings, source_attachment, payload)
    _replace_attachment_bytes(settings, preview_attachment, preview_payload)
    db.commit()
    return {
        "sourceAttachmentId": source_attachment.id,
        "previewAttachmentId": preview_attachment.id,
        "revision": expectedRevision + 1,
        "copied": False,
    }


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
        if attachment.id in embedded_rendered_attachment_ids(note.content_json):
            raise HTTPException(status_code=409, detail="文件正在正文中使用，请先从正文移除")
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
