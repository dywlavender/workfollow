from copy import deepcopy

from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, File, Form, HTTPException, Query, Response, UploadFile, status

from app.core.dependencies import CurrentSettings, CurrentUser, DbSession
from app.schemas.note import NoteCreate, NoteRead, NoteUpdate
from app.services import note_service
from app.services.markdown_import_service import MarkdownImportError, parse_markdown
from app.services.template_service import get_accessible_template_or_404, seed_builtin_templates


router = APIRouter(tags=["notes"])


@router.get("/notes", response_model=list[NoteRead])
def get_notes(
    db: DbSession,
    user: CurrentUser,
    folder_id: str | None = Query(default=None, alias="folderId"),
    q: str | None = Query(default=None),
    favorite: bool | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
) -> list[NoteRead]:
    return note_service.list_notes(
        db, user.id, folder_id=folder_id, q=q, favorite=favorite, limit=limit, offset=offset
    )


@router.post("/notes", response_model=NoteRead, status_code=status.HTTP_201_CREATED)
def post_note(payload: NoteCreate, db: DbSession, user: CurrentUser) -> NoteRead:
    return note_service.create_note(db, payload, user.id)


@router.post("/notes/import-markdown", response_model=NoteRead, status_code=status.HTTP_201_CREATED)
async def import_markdown(
    db: DbSession,
    settings: CurrentSettings,
    user: CurrentUser,
    file: Annotated[UploadFile, File()],
    folder_id: Annotated[str | None, Form(alias="folderId")] = None,
    title: Annotated[str | None, Form()] = None,
) -> NoteRead:
    original_name = Path(file.filename or "").name
    suffix = Path(original_name).suffix.lower()
    if suffix not in {".md", ".markdown"}:
        raise HTTPException(status_code=415, detail="只支持导入 .md 或 .markdown 文件")

    content = await file.read(settings.max_markdown_import_bytes + 1)
    if len(content) > settings.max_markdown_import_bytes:
        raise HTTPException(status_code=413, detail="Markdown 文件不能超过 5MB")
    try:
        markdown = content.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise HTTPException(status_code=422, detail="Markdown 文件必须使用 UTF-8 编码") from exc

    try:
        content_json, derived_title = parse_markdown(markdown, original_name)
    except MarkdownImportError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    requested_title = (title or "").strip()
    note = note_service.create_note(
        db,
        NoteCreate(
            folder_id=folder_id,
            title=requested_title or derived_title,
            content_json=content_json,
            plain_text=note_service.content_to_plain_text(content_json),
        ),
        user.id,
    )
    return note


# Keep this dynamic route after the static Markdown import route above.
# Older Starlette versions match the first path with the same shape and would
# otherwise return 405 for POST /notes/import-markdown.
@router.get("/notes/{note_id}", response_model=NoteRead)
def get_note(note_id: str, db: DbSession, user: CurrentUser) -> NoteRead:
    return note_service.get_note_or_404(db, note_id, user.id)


@router.post("/notes/{note_id}/copy", response_model=NoteRead, status_code=status.HTTP_201_CREATED)
def copy_note(note_id: str, db: DbSession, settings: CurrentSettings, user: CurrentUser) -> NoteRead:
    source = note_service.get_note_or_404(db, note_id, user.id)
    return note_service.copy_note_with_attachments(
        db,
        title=f"{source.title} 副本",
        content_json=source.content_json,
        plain_text=source.plain_text,
        source_attachments=list(source.attachments),
        owner_id=user.id,
        settings=settings,
        folder_id=source.folder_id,
        copied_from_note_id=source.id,
    )


@router.put("/notes/{note_id}", response_model=NoteRead)
def put_note(
    note_id: str,
    payload: NoteUpdate,
    db: DbSession,
    settings: CurrentSettings,
    user: CurrentUser,
) -> NoteRead:
    return note_service.update_note(db, note_service.get_note_or_404(db, note_id, user.id), payload, settings)


@router.delete("/notes/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_note(note_id: str, db: DbSession, user: CurrentUser) -> Response:
    note_service.soft_delete_note(db, note_service.get_note_or_404(db, note_id, user.id))
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/notes/from-template/{template_id}", response_model=NoteRead, status_code=status.HTTP_201_CREATED)
def create_from_template(
    template_id: str,
    db: DbSession,
    user: CurrentUser,
    folder_id: str | None = Query(default=None, alias="folderId"),
) -> NoteRead:
    seed_builtin_templates(db)
    template = get_accessible_template_or_404(db, template_id, user.id)
    return note_service.create_note(
        db,
        NoteCreate(
            folder_id=folder_id,
            title=template.name,
            content_json=deepcopy(template.content_json),
            plain_text=note_service.content_to_plain_text(template.content_json),
        ),
        user.id,
    )
