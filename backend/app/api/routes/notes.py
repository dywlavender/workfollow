from copy import deepcopy

from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, File, Form, HTTPException, Query, Response, UploadFile, status

from app.core.dependencies import CurrentSettings, CurrentUser, DbSession
from app.models.team_note import TeamNoteSubmissionStatus
from app.schemas.note import NoteCapture, NoteCounts, NoteCreate, NoteListItem, NoteNavigationCounts, NoteRead, NoteUpdate
from app.services import note_permission_service, note_service, team_note_service
from app.services.system_permission_service import user_is_root
from app.services.markdown_import_service import MarkdownImportError, parse_markdown
from app.services.template_service import get_accessible_template_or_404, seed_builtin_templates


router = APIRouter(tags=["notes"])


@router.get("/notes", response_model=list[NoteListItem])
def get_notes(
    db: DbSession,
    user: CurrentUser,
    folder_id: str | None = Query(default=None, alias="folderId"),
    q: str | None = Query(default=None),
    favorite: bool | None = Query(default=None),
    unfiled: bool = Query(default=False),
    limit: int = Query(default=100, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
) -> list[NoteListItem]:
    return [NoteListItem.model_validate(note) for note in note_service.list_notes(
        db,
        user.id,
        folder_id=folder_id,
        q=q,
        favorite=favorite,
        unfiled=unfiled,
        limit=limit,
        offset=offset,
        summary=True,
    )]


@router.get("/notes/counts", response_model=NoteCounts)
def get_note_counts(db: DbSession, user: CurrentUser) -> NoteCounts:
    return NoteCounts(unfiled=note_service.count_unfiled_notes(db, user.id))


@router.get("/notes/navigation-counts", response_model=NoteNavigationCounts)
def get_navigation_counts(
    db: DbSession,
    user: CurrentUser,
    team_id: str | None = Query(default=None, alias="teamId"),
) -> NoteNavigationCounts:
    counts = note_service.navigation_counts(db, user.id)
    submissions_pending = 0
    review_pending = 0
    if team_id:
        can_access_team = user_is_root(db, user.id) or note_permission_service.membership(db, user.id, team_id) is not None
        if not can_access_team:
            raise HTTPException(status_code=404, detail="Team not found")
        pending_statuses = [TeamNoteSubmissionStatus.PENDING, TeamNoteSubmissionStatus.NEEDS_REVISION]
        submissions_pending = team_note_service.count_submissions(
            db, team_id, applicant_id=user.id, statuses=pending_statuses
        )
        if note_permission_service.can_review_submission(db, user.id, team_id):
            review_pending = team_note_service.count_submissions(
                db, team_id, statuses=[TeamNoteSubmissionStatus.PENDING]
            )
    return NoteNavigationCounts(
        **counts,
        submissions_pending=submissions_pending,
        review_pending=review_pending,
    )


@router.post("/notes", response_model=NoteRead, status_code=status.HTTP_201_CREATED)
def post_note(payload: NoteCreate, db: DbSession, user: CurrentUser) -> NoteRead:
    return note_service.create_note(db, payload, user.id)


@router.post("/notes/capture", response_model=NoteRead, status_code=status.HTTP_201_CREATED)
def capture_note(payload: NoteCapture, db: DbSession, user: CurrentUser) -> NoteRead:
    return note_service.capture_note(db, payload, user.id)


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
