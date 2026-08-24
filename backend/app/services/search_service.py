from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Literal

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.models.auth import User
from app.services.search_index_service import fts_available
from app.services.system_permission_service import is_root


SearchSource = Literal["personal", "shared", "knowledge"]
_MARK_OPEN = "\x01"
_MARK_CLOSE = "\x02"


@dataclass
class SearchCandidate:
    source: SearchSource
    id: str
    title: str
    excerpt: list[dict[str, object]]
    folder_id: str | None
    team_id: str | None
    updated_at: datetime
    rank: float


def _coerce_datetime(value: object) -> datetime:
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            pass
    return datetime.min


def _literal_match_query(query: str) -> str:
    # Quoting makes user input literal instead of allowing FTS5 operators.
    return f'"{query.replace(chr(34), chr(34) * 2)}"'


def _excerpt_parts(value: str | None) -> list[dict[str, object]]:
    if not value:
        return []
    parts: list[dict[str, object]] = []
    cursor = 0
    while cursor < len(value):
        start = value.find(_MARK_OPEN, cursor)
        if start < 0:
            if value[cursor:]:
                parts.append({"text": value[cursor:], "matched": False})
            break
        if start > cursor:
            parts.append({"text": value[cursor:start], "matched": False})
        end = value.find(_MARK_CLOSE, start + 1)
        if end < 0:
            parts.append({"text": value[start + 1:], "matched": True})
            break
        parts.append({"text": value[start + 1:end], "matched": True})
        cursor = end + 1
    return [part for part in parts if part["text"]]


def _search_sql(source: SearchSource, use_fts: bool) -> str:
    if source in {"personal", "shared"}:
        from_clause = (
            "note_search JOIN search_documents sd ON sd.id = note_search.rowid "
            "JOIN notes n ON n.id = sd.source_id"
            if use_fts else
            "search_documents sd JOIN notes n ON n.id = sd.source_id"
        )
        source_condition = "sd.source_type = 'PERSONAL' AND n.deleted_at IS NULL"
        permission = "n.owner_id = :user_id" if source == "personal" else """
            n.owner_id <> :user_id
            AND EXISTS (
                SELECT 1
                FROM note_shares ns
                JOIN teams share_team ON share_team.id = ns.team_id
                JOIN users share_owner ON share_owner.id = ns.shared_by_user_id
                JOIN team_members target_member
                  ON target_member.team_id = ns.team_id
                 AND target_member.user_id = :user_id
                 AND target_member.status = 'ACTIVE'
                JOIN team_members owner_member
                  ON owner_member.team_id = ns.team_id
                 AND owner_member.user_id = ns.shared_by_user_id
                 AND owner_member.status = 'ACTIVE'
                WHERE ns.note_id = n.id
                  AND ns.shared_with_user_id = :user_id
                  AND ns.status = 'ACTIVE'
                  AND share_team.status = 'ACTIVE'
                  AND share_owner.status = 'ACTIVE'
            )
        """
        match = "note_search MATCH :personal_match_query" if use_fts else """
            (
                sd.title LIKE :pattern
                OR sd.body LIKE :pattern
            )
        """
        select_rank = (
            "bm25(note_search, 8.0, 1.0, 5.0, 3.0)"
            if use_fts else
            "CASE WHEN lower(n.title) = lower(:raw_query) THEN 0 "
            "WHEN lower(n.title) LIKE lower(:prefix_pattern) THEN 1 "
            "WHEN lower(n.title) LIKE lower(:pattern) THEN 2 ELSE 3 END"
        )
        excerpt = (
            "CASE "
            "WHEN instr(highlight(note_search, 0, :mark_open, :mark_close), :mark_open) > 0 "
            "THEN highlight(note_search, 0, :mark_open, :mark_close) "
            "ELSE snippet(note_search, 1, :mark_open, :mark_close, '…', 18) END"
            if use_fts else "''"
        )
        return f"""
            SELECT n.id AS source_id, n.title, n.folder_id, NULL AS team_id,
                   n.updated_at, {select_rank} AS rank, {excerpt} AS excerpt
            FROM {from_clause}
            WHERE {source_condition} AND {permission} AND {match}
            ORDER BY rank ASC, n.updated_at DESC
            LIMIT :candidate_limit
        """

    from_clause = (
        "note_search JOIN search_documents sd ON sd.id = note_search.rowid "
        "JOIN team_notes tn ON tn.id = sd.source_id"
        if use_fts else
        "search_documents sd JOIN team_notes tn ON tn.id = sd.source_id"
    )
    match = "note_search MATCH :match_query" if use_fts else """
        (
            sd.title LIKE :pattern
            OR sd.body LIKE :pattern
            OR sd.tags_text LIKE :pattern
            OR sd.category_name LIKE :pattern
        )
    """
    permission = """
        tn.status = 'PUBLISHED'
        AND (:team_id IS NULL OR tn.team_id = :team_id)
        AND (
            (
                :is_root = 1
                AND EXISTS (
                    SELECT 1 FROM teams root_team
                    WHERE root_team.id = tn.team_id AND root_team.status = 'ACTIVE'
                )
            )
            OR EXISTS (
                SELECT 1
                FROM team_members member
                JOIN teams member_team ON member_team.id = member.team_id
                WHERE member.team_id = tn.team_id
                  AND member.user_id = :user_id
                  AND member.status = 'ACTIVE'
                  AND member_team.status = 'ACTIVE'
            )
        )
    """
    select_rank = (
        "bm25(note_search, 8.0, 1.0, 5.0, 3.0)"
        if use_fts else
        "CASE WHEN lower(tn.title) = lower(:raw_query) THEN 0 "
        "WHEN lower(tn.title) LIKE lower(:prefix_pattern) THEN 1 "
        "WHEN lower(tn.title) LIKE lower(:pattern) THEN 2 ELSE 3 END"
    )
    excerpt = (
        "CASE "
        "WHEN instr(highlight(note_search, 0, :mark_open, :mark_close), :mark_open) > 0 "
        "THEN highlight(note_search, 0, :mark_open, :mark_close) "
        "WHEN instr(highlight(note_search, 2, :mark_open, :mark_close), :mark_open) > 0 "
        "THEN highlight(note_search, 2, :mark_open, :mark_close) "
        "WHEN instr(highlight(note_search, 3, :mark_open, :mark_close), :mark_open) > 0 "
        "THEN highlight(note_search, 3, :mark_open, :mark_close) "
        "ELSE snippet(note_search, 1, :mark_open, :mark_close, '…', 18) END"
        if use_fts else "''"
    )
    return f"""
        SELECT tn.id AS source_id, tn.title, NULL AS folder_id, tn.team_id,
               tn.updated_at, {select_rank} AS rank, {excerpt} AS excerpt
        FROM {from_clause}
        WHERE {permission} AND {match}
        ORDER BY rank ASC, tn.updated_at DESC
        LIMIT :candidate_limit
    """


def _query_source(
    db: Session,
    user: User,
    source: SearchSource,
    query: str,
    team_id: str | None,
    candidate_limit: int,
) -> list[SearchCandidate]:
    use_fts = fts_available(db) and len(query) >= 3
    params: dict[str, object] = {
        "user_id": user.id,
        "team_id": team_id,
        "is_root": 1 if is_root(user) else 0,
        "candidate_limit": candidate_limit,
        "raw_query": query,
        "pattern": f"%{query}%",
        "prefix_pattern": f"{query}%",
        "match_query": _literal_match_query(query),
        "personal_match_query": f"{{title body}} : {_literal_match_query(query)}",
        "mark_open": _MARK_OPEN,
        "mark_close": _MARK_CLOSE,
    }
    rows = db.execute(text(_search_sql(source, use_fts)), params).mappings().all()
    # FTS5 can be present while an older/local database still has an empty or
    # stale index (for example after an interrupted migration). Keep the
    # relational projection as a correctness fallback instead of showing a
    # false empty result set.
    if use_fts and not rows:
        rows = db.execute(text(_search_sql(source, False)), params).mappings().all()
    return [
        SearchCandidate(
            source=source,
            id=str(row["source_id"]),
            title=row["title"] or "未命名笔记",
            excerpt=_excerpt_parts(row["excerpt"]),
            folder_id=row["folder_id"],
            team_id=row["team_id"],
            updated_at=_coerce_datetime(row["updated_at"]),
            rank=float(row["rank"] or 0),
        )
        for row in rows
    ]


def search(
    db: Session,
    user: User,
    query: str,
    scope: str = "all",
    team_id: str | None = None,
    limit: int = 20,
    offset: int = 0,
) -> tuple[list[SearchCandidate], int, bool]:
    query = query.strip()
    if not query:
        return [], 0, False
    sources: list[SearchSource] = {
        "all": ["personal", "shared", "knowledge"],
        "personal": ["personal"],
        "shared": ["shared"],
        "knowledge": ["knowledge"],
    }.get(scope, [])
    if not sources:
        return [], 0, False
    candidate_limit = min(max(limit * 4 + offset, 40), 200)
    candidates = [
        item
        for source in sources
        for item in _query_source(db, user, source, query, team_id, candidate_limit)
    ]
    candidates.sort(key=lambda item: (item.rank, -item.updated_at.timestamp()))
    total = len(candidates)
    page = candidates[offset:offset + limit]
    return page, total, total > offset + limit
