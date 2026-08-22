from __future__ import annotations

from sqlalchemy import Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class SearchDocument(Base):
    """Stable relational content row behind the SQLite FTS5 index.

    FTS5 rowids are integers. Keeping that rowid on a normal table avoids
    coupling the index to the implicit rowids of UUID-backed business tables.
    """

    __tablename__ = "search_documents"
    __table_args__ = (
        UniqueConstraint("source_type", "source_id", name="uq_search_documents_source"),
        Index("ix_search_documents_owner", "owner_id"),
        Index("ix_search_documents_team", "team_id"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    source_type: Mapped[str] = mapped_column(String(16), nullable=False)
    source_id: Mapped[str] = mapped_column(String(36), nullable=False)
    owner_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    team_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    title: Mapped[str] = mapped_column(String(500), nullable=False, default="")
    body: Mapped[str] = mapped_column(Text, nullable=False, default="")
    tags_text: Mapped[str] = mapped_column(Text, nullable=False, default="")
    category_name: Mapped[str] = mapped_column(String(120), nullable=False, default="")
