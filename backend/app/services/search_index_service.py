from __future__ import annotations

from collections.abc import Iterable
import logging

from sqlalchemy import delete, select, text
from sqlalchemy.exc import DatabaseError
from sqlalchemy.orm import Session

from app.models.note import Note
from app.models.search import SearchDocument
from app.models.team_note import TeamNote, TeamNoteCategory


PERSONAL_SOURCE = "PERSONAL"
TEAM_SOURCE = "TEAM"
logger = logging.getLogger(__name__)


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


def ensure_fts_index(db: Session) -> bool:
    """Create the optional FTS5 projection when it is missing.

    ``search_documents`` remains the source of truth and the application can
    always use its LIKE fallback.  Recreating the derived table on startup
    restores ranked search after a previous corruption recovery dropped it,
    while SQLite builds without FTS5 simply keep the fallback behavior.
    """

    if db.get_bind().dialect.name != "sqlite":
        return False
    if fts_available(db):
        return True
    try:
        db.execute(text(
            "CREATE VIRTUAL TABLE note_search USING fts5("
            "title, body, tags_text, category_name, "
            "content='search_documents', content_rowid='id', tokenize='trigram'"
            ")"
        ))
        db.execute(text(
            "CREATE TRIGGER search_documents_ai AFTER INSERT ON search_documents BEGIN "
            "INSERT INTO note_search(rowid, title, body, tags_text, category_name) "
            "VALUES (new.id, new.title, new.body, new.tags_text, new.category_name); END"
        ))
        db.execute(text(
            "CREATE TRIGGER search_documents_ad AFTER DELETE ON search_documents BEGIN "
            "INSERT INTO note_search(note_search, rowid, title, body, tags_text, category_name) "
            "VALUES ('delete', old.id, old.title, old.body, old.tags_text, old.category_name); END"
        ))
        db.execute(text(
            "CREATE TRIGGER search_documents_au AFTER UPDATE OF title, body, tags_text, category_name "
            "ON search_documents BEGIN "
            "INSERT INTO note_search(note_search, rowid, title, body, tags_text, category_name) "
            "VALUES ('delete', old.id, old.title, old.body, old.tags_text, old.category_name); "
            "INSERT INTO note_search(rowid, title, body, tags_text, category_name) "
            "VALUES (new.id, new.title, new.body, new.tags_text, new.category_name); END"
        ))
        db.execute(text("INSERT INTO note_search(note_search) VALUES ('rebuild')"))
        db.commit()
        logger.info("SQLite FTS5 索引缺失，已从 search_documents 重建")
        return True
    except DatabaseError:
        db.rollback()
        return False


def rebuild_fts_index(db: Session) -> bool:
    """Rebuild the derived FTS5 index from ``search_documents``.

    The FTS table is an index, not a source of truth.  Rebuilding it is safe
    when its internal segment pages are damaged (SQLite may still report the
    ordinary tables as healthy in that situation).
    """

    if not fts_available(db):
        return False
    try:
        db.execute(text("INSERT INTO note_search(note_search) VALUES ('rebuild')"))
        db.commit()
        return True
    except DatabaseError:
        db.rollback()
        return False


def disable_fts_index(db: Session) -> bool:
    """Disable only the derived FTS table when its segment pages are damaged.

    ``search_documents`` is the relational source of truth. Dropping the
    optional virtual table lets normal writes continue through the LIKE
    fallback instead of repeatedly failing every note projection.
    """

    if not fts_available(db):
        return False
    try:
        for trigger in ("search_documents_au", "search_documents_ad", "search_documents_ai"):
            db.execute(text(f"DROP TRIGGER IF EXISTS {trigger}"))
        db.execute(text("DROP TABLE IF EXISTS note_search"))
        db.commit()
        # Recreate immediately when the SQLite build supports FTS5. If the
        # extension is unavailable (or the file is still unhealthy), the
        # relational LIKE path remains the safe fallback.
        if ensure_fts_index(db):
            logger.warning("SQLite FTS5 索引损坏，已删除并从 search_documents 重建")
        else:
            logger.warning("SQLite FTS5 索引不可恢复，已停用派生索引并回退到普通搜索")
        return True
    except DatabaseError:
        db.rollback()
        logger.exception("停用损坏的 SQLite FTS5 索引失败")
        return False


def recover_fts_after_error(db: Session, error: BaseException) -> bool:
    """Repair/disable FTS after a write-trigger error and report recovery."""

    if "malformed" not in str(error).lower():
        return False
    db.rollback()
    if rebuild_fts_index(db):
        logger.warning("检测到损坏的 SQLite FTS5 索引，已重建后重试写入")
        return True
    return disable_fts_index(db)


def repair_fts_index(db: Session) -> bool:
    """Detect and repair a corrupt external-content FTS5 index.

    ``PRAGMA integrity_check`` does not inspect every FTS5 segment.  A no-op
    projection update exercises the same delete/insert triggers used by note
    saves, without changing the relational data.  If SQLite reports a
    malformed database, rebuild the derived index and let normal writes retry
    on the next request.
    """

    # A missing optional index is a valid degraded-mode state. Do not create
    # a virtual table from the health check itself: startup may run alongside
    # a migration, and the relational LIKE path remains correct meanwhile.
    # ``disable_fts_index`` is the explicit recovery path that may recreate it
    # after a confirmed corruption.
    if not fts_available(db):
        return False
    try:
        row_id = db.scalar(text("SELECT id FROM search_documents ORDER BY id LIMIT 1"))
    except DatabaseError:
        # The optional FTS index must never prevent the relational application
        # from starting. If the source projection itself is damaged, leave it
        # for the database repair workflow and let normal requests surface the
        # real storage error instead of failing during FastAPI lifespan setup.
        db.rollback()
        logger.exception("读取搜索源表失败，跳过 SQLite FTS 健康检查")
        return False
    if row_id is None:
        db.rollback()
        return False
    try:
        db.execute(
            text("UPDATE search_documents SET body = body WHERE id = :id"),
            {"id": row_id},
        )
        db.rollback()
        return False
    except DatabaseError:
        db.rollback()
        try:
            rebuilt = rebuild_fts_index(db)
        except Exception:
            db.rollback()
            logger.exception("SQLite FTS5 索引损坏且自动重建失败")
            rebuilt = False
        if rebuilt:
            logger.warning("检测到损坏的 SQLite FTS5 索引，已从 search_documents 重建")
            return True
        return disable_fts_index(db)
