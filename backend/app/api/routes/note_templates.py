from copy import deepcopy

from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import select

from app.core.dependencies import CurrentUser, DbSession
from app.models.note import Note
from app.schemas.note import (
    NoteTemplateCreate,
    NoteTemplateFromNoteCreate,
    NoteTemplateRead,
    NoteTemplateUpdate,
)
from app.services.note_permission_service import can_view_personal_note
from app.services.template_service import (
    create_template,
    delete_template,
    list_accessible_templates,
    seed_builtin_templates,
    update_template,
)


router = APIRouter(prefix="/note-templates", tags=["note-templates"])


@router.get("", response_model=list[NoteTemplateRead])
def get_templates(db: DbSession, user: CurrentUser) -> list[NoteTemplateRead]:
    seed_builtin_templates(db)
    return list_accessible_templates(db, user.id)


@router.post("", response_model=NoteTemplateRead, status_code=status.HTTP_201_CREATED)
def post_template(payload: NoteTemplateCreate, db: DbSession, user: CurrentUser) -> NoteTemplateRead:
    return create_template(db, payload, user.id)


@router.post("/from-note/{note_id}", response_model=NoteTemplateRead, status_code=status.HTTP_201_CREATED)
def post_template_from_note(
    note_id: str,
    payload: NoteTemplateFromNoteCreate,
    db: DbSession,
    user: CurrentUser,
) -> NoteTemplateRead:
    note = db.scalar(select(Note).where(Note.id == note_id))
    if note is None or note.deleted_at is not None or not can_view_personal_note(db, note, user.id):
        raise HTTPException(status_code=404, detail="Note not found")
    return create_template(
        db,
        NoteTemplateCreate(
            name=payload.name,
            description=payload.description,
            content_json=deepcopy(note.content_json),
            sort_order=100,
        ),
        user.id,
    )


@router.put("/{template_id}", response_model=NoteTemplateRead)
def put_template(
    template_id: str,
    payload: NoteTemplateUpdate,
    db: DbSession,
    user: CurrentUser,
) -> NoteTemplateRead:
    return update_template(db, template_id, payload, user.id)


@router.delete("/{template_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_template(template_id: str, db: DbSession, user: CurrentUser) -> Response:
    delete_template(db, template_id, user.id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
