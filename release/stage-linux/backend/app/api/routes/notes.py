from fastapi import APIRouter, Query, Response, status

from app.core.dependencies import CurrentSettings, CurrentUser, DbSession
from app.models.note import NoteTemplate
from app.schemas.note import NoteCreate, NoteRead, NoteTemplateRead, NoteUpdate
from app.services import note_service
from app.services.template_service import seed_builtin_templates


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


@router.get("/notes/{note_id}", response_model=NoteRead)
def get_note(note_id: str, db: DbSession, user: CurrentUser) -> NoteRead:
    return note_service.get_note_or_404(db, note_id, user.id)


@router.post("/notes", response_model=NoteRead, status_code=status.HTTP_201_CREATED)
def post_note(payload: NoteCreate, db: DbSession, user: CurrentUser) -> NoteRead:
    return note_service.create_note(db, payload, user.id)


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
def put_note(note_id: str, payload: NoteUpdate, db: DbSession, user: CurrentUser) -> NoteRead:
    return note_service.update_note(db, note_service.get_note_or_404(db, note_id, user.id), payload)


@router.delete("/notes/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_note(note_id: str, db: DbSession, user: CurrentUser) -> Response:
    note_service.soft_delete_note(db, note_service.get_note_or_404(db, note_id, user.id))
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/note-templates", response_model=list[NoteTemplateRead])
def get_templates(db: DbSession, user: CurrentUser) -> list[NoteTemplateRead]:
    seed_builtin_templates(db)
    from sqlalchemy import select

    return list(db.scalars(select(NoteTemplate).order_by(NoteTemplate.sort_order)))


@router.post("/notes/from-template/{template_id}", response_model=NoteRead, status_code=status.HTTP_201_CREATED)
def create_from_template(
    template_id: str,
    db: DbSession,
    user: CurrentUser,
    folder_id: str | None = Query(default=None, alias="folderId"),
) -> NoteRead:
    seed_builtin_templates(db)
    template = db.get(NoteTemplate, template_id)
    if template is None:
        from fastapi import HTTPException

        raise HTTPException(status_code=404, detail="NoteTemplate not found")
    return note_service.create_note(
        db,
        NoteCreate(
            folder_id=folder_id,
            title=template.name,
            content_json=template.content_json,
            plain_text=note_service.content_to_plain_text(template.content_json),
        ),
        user.id,
    )
