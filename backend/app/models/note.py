from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import JSON, Boolean, CheckConstraint, DateTime, ForeignKey, Index, Integer, String, Text, text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.todo import local_now, new_uuid


class Folder(Base):
    __tablename__ = "folders"
    __table_args__ = (Index("ix_folders_parent_sort", "parent_id", "sort_order"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    owner_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    parent_id: Mapped[str | None] = mapped_column(ForeignKey("folders.id"), nullable=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, onupdate=local_now, nullable=False)

    parent: Mapped[Folder | None] = relationship(remote_side="Folder.id", back_populates="children")
    children: Mapped[list[Folder]] = relationship(back_populates="parent")
    notes: Mapped[list[Note]] = relationship(back_populates="folder")
    owner: Mapped["User"] = relationship(back_populates="folders")


class Note(Base):
    __tablename__ = "notes"
    __table_args__ = (
        Index("ix_notes_folder_updated", "folder_id", "updated_at"),
        Index("ix_notes_deleted_at", "deleted_at"),
        Index("ix_notes_owner_updated_at", "owner_id", "updated_at"),
        Index(
            "ix_notes_owner_update_draft_target",
            "owner_id",
            "copied_from_team_note_id",
            "is_knowledge_update_draft",
            "deleted_at",
        ),
        Index(
            "uq_notes_owner_active_update_draft_target",
            "owner_id",
            "copied_from_team_note_id",
            unique=True,
            sqlite_where=text("is_knowledge_update_draft = TRUE AND deleted_at IS NULL"),
            postgresql_where=text("is_knowledge_update_draft = TRUE AND deleted_at IS NULL"),
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    owner_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    folder_id: Mapped[str | None] = mapped_column(ForeignKey("folders.id"), nullable=True)
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    content_json: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    plain_text: Mapped[str] = mapped_column(Text, default="", nullable=False)
    tags: Mapped[list[str]] = mapped_column(JSON, default=list, nullable=False)
    is_favorite: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    copied_from_note_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    copied_from_team_note_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    is_knowledge_update_draft: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    copied_from_team_note_version_no: Mapped[int | None] = mapped_column(Integer, nullable=True)
    copied_from_team_note_snapshot_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, onupdate=local_now, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    folder: Mapped[Folder | None] = relationship(back_populates="notes")
    attachments: Mapped[list[Attachment]] = relationship(back_populates="note", cascade="all, delete-orphan")
    owner: Mapped["User"] = relationship(back_populates="notes")


class Attachment(Base):
    __tablename__ = "attachments"
    __table_args__ = (Index("ix_attachments_note_created", "note_id", "created_at"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    owner_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    note_id: Mapped[str | None] = mapped_column(ForeignKey("notes.id"), nullable=True)
    original_name: Mapped[str] = mapped_column(String(500), nullable=False)
    storage_name: Mapped[str] = mapped_column(String(100), nullable=False, unique=True)
    mime_type: Mapped[str] = mapped_column(String(200), nullable=False)
    size: Mapped[int] = mapped_column(Integer, nullable=False)
    file_path: Mapped[str] = mapped_column(String(1000), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)

    note: Mapped[Note | None] = relationship(back_populates="attachments")
    owner: Mapped["User"] = relationship(back_populates="attachments")


class NoteTemplate(Base):
    __tablename__ = "note_templates"
    __table_args__ = (
        CheckConstraint(
            "(is_builtin = TRUE AND owner_id IS NULL) OR "
            "(is_builtin = FALSE AND owner_id IS NOT NULL)",
            name="ck_note_templates_builtin_owner",
        ),
        Index("ix_note_templates_owner_deleted_sort", "owner_id", "deleted_at", "sort_order"),
        Index(
            "uq_note_templates_owner_name_active",
            "owner_id",
            "name",
            unique=True,
            sqlite_where=text("deleted_at IS NULL"),
            postgresql_where=text("deleted_at IS NULL"),
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    content_json: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    is_builtin: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    owner_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, onupdate=local_now, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    owner: Mapped["User | None"] = relationship(back_populates="note_templates")
