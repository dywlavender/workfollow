from __future__ import annotations

from collections.abc import Iterable

from sqlalchemy import delete, select, text
from sqlalchemy.orm import Session

from app.models.note import Note
from app.models.search import SearchDocument
from app.models.team_note import TeamNote, TeamNoteCategory


PERSONAL_SOURCE = "PERSONAL"
TEAM_SOURCE = "TEAM"


def tags_to_text(tags: Iterable[str] | None) -> str:
    return " ".join(
        " ".join(str(tag).strip().split())
        for tag in (tags or [])
        if isinstance(tag, str) and tag.strip()
    )


def upsert_personal_note(db: Session, note: Note) -> None:
    if note.deleted_at is not None:
        remove_source(db, PERSONAL_SOURCE, note.id)
        return
    document = db.scalar(
        select(SearchDocument).where(
            SearchDocument.source_type == PERSONAL_SOURCE,
            SearchDocument.source_id == note.id,
        )
    )
    if document is None:
        document = SearchDocument(source_type=PERSONAL_SOURCE, source_id=note.id)
        db.add(document)
    document.owner_id = note.owner_id
    document.team_id = None
    document.title = note.title or ""
    document.body = note.plain_text or ""
    document.tags_text = ""
    document.category_name = ""


def upsert_team_note(db: Session, note: TeamNote) -> None:
    document = db.scalar(
        select(SearchDocument).where(
            SearchDocument.source_type == TEAM_SOURCE,
            SearchDocument.source_id == note.id,
        )
    )
    if document is None:
        document = SearchDocument(source_type=TEAM_SOURCE, source_id=note.id)
        db.add(document)
    document.owner_id = None
    document.team_id = note.team_id
    document.title = note.title or ""
    document.body = note.plain_text or ""
    document.tags_text = tags_to_text(note.tags)
    # Read the category by id instead of relying on a possibly stale ORM
    # relationship. Category deletion clears ``category_id`` in the same
    # transaction, so the search projection must reflect that immediately.
    document.category_name = (
        db.scalar(select(TeamNoteCategory.name).where(TeamNoteCategory.id == note.category_id))
        if note.category_id else ""
    ) or ""


def remove_source(db: Session, source_type: str, source_id: str) -> None:
    db.execute(
        delete(SearchDocument).where(
            SearchDocument.source_type == source_type,
            SearchDocument.source_id == source_id,
        )
    )


def sync_team_category(db: Session, team_id: str, category_id: str) -> None:
    """Refresh category text after a category rename."""

    category = db.get(TeamNoteCategory, category_id)
    if category is None or category.team_id != team_id:
        return
    notes = db.scalars(
        select(TeamNote).where(TeamNote.team_id == team_id, TeamNote.category_id == category_id)
    ).all()
    for note in notes:
        upsert_team_note(db, note)


def fts_available(db: Session) -> bool:
    try:
        return db.scalar(
            text("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'note_search' LIMIT 1")
        ) == 1
    except Exception:
        return False
