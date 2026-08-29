from copy import deepcopy
import secrets

from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, File, Form, Header, HTTPException, Query, Response, UploadFile, status

from app.core.dependencies import CurrentSettings, CurrentUser, DbSession
from app.models.note import Note
from app.models.team_note import TeamNoteSubmissionStatus
from app.schemas.note import (
    NoteCapture,
    NoteCollaborationAccess,
    NoteCollaborationSnapshot,
    NoteCounts,
    NoteCreate,
    NoteFavoriteUpdate,
    NoteFolderMove,
    NoteListItem,
    NoteNavigationCounts,
    NoteRead,
    NoteUpdate,
    SharedByMeNoteRead,
)
from app.schemas.auth import UserRead
from app.services import note_permission_service, note_service, note_share_service, team_note_service
from app.services.content_projection import content_json_semantically_equal
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
    shared_count = note_share_service.count_shared_notes(db, user.id)
    shared_by_me_count = note_share_service.count_notes_shared_by_me(db, user.id)
    knowledge_count = 0
    submissions_pending = 0
    review_pending = 0
    if team_id:
        can_access_team = user_is_root(db, user.id) or note_permission_service.membership(db, user.id, team_id) is not None
        if not can_access_team:
            raise HTTPException(status_code=404, detail="Team not found")
        knowledge_count = team_note_service.count_published_notes(db, team_id)
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
        shared=shared_count,
        shared_by_me=shared_by_me_count,
        knowledge=knowledge_count,
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


# Keep these named collaboration and business-action routes before the dynamic
# note route. Older Starlette versions match the first path with the same
# shape, so their order is part of the API contract.
@router.get("/notes/shared-by-me", response_model=list[SharedByMeNoteRead])
def list_notes_shared_by_me(db: DbSession, user: CurrentUser) -> list[SharedByMeNoteRead]:
    """Notes I own that still have at least one active share, with holders."""
    return [
        SharedByMeNoteRead.model_validate({
            **NoteListItem.model_validate(note).model_dump(),
            "shared_with": [UserRead.model_validate(holder) for holder in users],
        })
        for note, users in note_share_service.list_notes_shared_by_me(db, user.id)
    ]


@router.get("/notes/{note_id}/collaboration-access", response_model=NoteCollaborationAccess, include_in_schema=False)
def get_note_collaboration_access(note_id: str, db: DbSession, user: CurrentUser) -> NoteCollaborationAccess:
    note = db.get(Note, note_id)
    if note is None or not note_permission_service.can_view_personal_note(db, note, user.id):
        raise HTTPException(status_code=404, detail="Note not found")
    return NoteCollaborationAccess(
        can_view=True,
        can_edit=note_permission_service.can_edit_personal_note(db, note, user.id),
    )


@router.put("/notes/{note_id}/collaboration-snapshot", status_code=status.HTTP_204_NO_CONTENT, include_in_schema=False)
def put_note_collaboration_snapshot(
    note_id: str,
    payload: NoteCollaborationSnapshot,
    db: DbSession,
    settings: CurrentSettings,
    internal_token: str | None = Header(default=None, alias="X-WorkFollow-Collaboration-Token"),
) -> Response:
    configured = settings.collaboration_internal_token
    if not configured or not internal_token or not secrets.compare_digest(internal_token, configured):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="协同服务未授权")

    note = db.get(Note, note_id)
    if note is None or note.deleted_at is not None:
        return Response(status_code=status.HTTP_204_NO_CONTENT)
    actors = set(payload.actor_ids)
    if payload.actor_id:
        actors.add(payload.actor_id)
    # The WebSocket authorize check is the front gate; this is the back gate.
    # Editable share holders may drive the projection like the owner, everyone
    # else (including revoked or downgraded share holders) is rejected so a
    # stale collaboration connection cannot keep writing after its grant ends.
    allowed_actors = {note.owner_id} | note_share_service.editable_share_user_ids(db, note.id)
    if any(actor_id not in allowed_actors for actor_id in actors):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="没有修改笔记的权限")

    # Opening or switching a collaborative note can replay the current Y.Doc
    # snapshot. Do not run the normal update service for an identical payload:
    # it would still advance ``updated_at`` and fan out a misleading event.
    title = payload.title.strip()
    if title == note.title and content_json_semantically_equal(payload.content_json, note.content_json):
        # Relation anchors may legitimately change while the canonical
        # document remains identical (for example, an editor assigns a new
        # block id during hydration). Reconcile those edges in the true no-op
        # branch; the normal update service performs the same reconciliation
        # for an actual body/title change, so doing it before that call would
        # add pending relation rows twice in one SQLAlchemy session.
        from app.services import resource_relation_service

        resource_relation_service.sync_personal_note_relations(
            db,
            note.id,
            note.owner_id,
            retained_task_ids=(),
            references=resource_relation_service.resource_references_in_document(payload.content_json),
        )
        db.commit()
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    # The WebSocket permission check is authoritative for browser writes. The
    # bridge still validates the actor when one is supplied, so a stale or
    # misconfigured collaboration connection cannot project a shared user's edit.
    note_service.update_note(
        db,
        note,
        NoteUpdate(title=title, content_json=payload.content_json),
        settings,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.put("/notes/{note_id}/folder", response_model=NoteRead)
def move_note_folder(
    note_id: str,
    payload: NoteFolderMove,
    db: DbSession,
    settings: CurrentSettings,
    user: CurrentUser,
) -> NoteRead:
    note = note_service.get_note_or_404(db, note_id, user.id)
    return note_service.update_note(db, note, NoteUpdate(folder_id=payload.folder_id), settings)


@router.put("/notes/{note_id}/favorite", response_model=NoteRead)
def set_note_favorite(
    note_id: str,
    payload: NoteFavoriteUpdate,
    db: DbSession,
    settings: CurrentSettings,
    user: CurrentUser,
) -> NoteRead:
    note = note_service.get_note_or_404(db, note_id, user.id)
    return note_service.update_note(db, note, NoteUpdate(is_favorite=payload.is_favorite), settings)


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
