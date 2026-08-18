from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any

from sqlalchemy import JSON, DateTime, Enum as SqlEnum, ForeignKey, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.todo import local_now, new_uuid


class TeamNoteSubmissionStatus(str, Enum):
    PENDING = "PENDING"
    NEEDS_REVISION = "NEEDS_REVISION"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"
    WITHDRAWN = "WITHDRAWN"


class TeamNoteSubmissionType(str, Enum):
    CREATE = "CREATE"
    UPDATE = "UPDATE"


class TeamNoteStatus(str, Enum):
    PUBLISHED = "PUBLISHED"
    ARCHIVED = "ARCHIVED"


class TeamNoteSourceType(str, Enum):
    ADMIN_CREATED = "ADMIN_CREATED"
    MEMBER_SUBMISSION = "MEMBER_SUBMISSION"


class TeamNoteCategory(Base):
    __tablename__ = "team_note_categories"
    __table_args__ = (
        UniqueConstraint("team_id", "name", name="uq_team_note_categories_team_name"),
        Index("ix_team_note_categories_team_sort", "team_id", "sort_order"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    team_id: Mapped[str] = mapped_column(ForeignKey("teams.id", ondelete="CASCADE"), nullable=False)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, onupdate=local_now, nullable=False)

    team: Mapped["Team"] = relationship()


class TeamNote(Base):
    __tablename__ = "team_notes"
    __table_args__ = (Index("ix_team_notes_team_updated", "team_id", "updated_at"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    team_id: Mapped[str] = mapped_column(ForeignKey("teams.id", ondelete="CASCADE"), nullable=False)
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    content_json: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    plain_text: Mapped[str] = mapped_column(Text, default="", nullable=False)
    attachment_ids: Mapped[list[str]] = mapped_column(JSON, default=list, nullable=False)
    category_id: Mapped[str | None] = mapped_column(
        ForeignKey("team_note_categories.id", ondelete="SET NULL"), nullable=True, index=True
    )
    tags: Mapped[list[str]] = mapped_column(JSON, default=list, nullable=False)
    source_type: Mapped[TeamNoteSourceType] = mapped_column(
        SqlEnum(TeamNoteSourceType, native_enum=False, length=24),
        default=TeamNoteSourceType.ADMIN_CREATED,
        nullable=False,
    )
    source_note_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    source_author_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    source_submission_id: Mapped[str | None] = mapped_column(String(36), nullable=True, unique=True)
    status: Mapped[TeamNoteStatus] = mapped_column(
        SqlEnum(TeamNoteStatus, native_enum=False, length=16), default=TeamNoteStatus.PUBLISHED, nullable=False
    )
    published_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)
    archived_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_by_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    updated_by_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, onupdate=local_now, nullable=False)

    team: Mapped["Team"] = relationship(back_populates="notes")
    category: Mapped["TeamNoteCategory | None"] = relationship()
    source_author: Mapped["User | None"] = relationship(foreign_keys=[source_author_id])
    created_by: Mapped["User | None"] = relationship(foreign_keys=[created_by_id])
    updated_by: Mapped["User | None"] = relationship(foreign_keys=[updated_by_id])


class TeamNoteSubmission(Base):
    __tablename__ = "team_note_submissions"
    __table_args__ = (
        Index("ix_team_note_submissions_team_status", "team_id", "status", "created_at"),
        Index("ix_team_note_submissions_applicant", "applicant_id", "created_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    team_id: Mapped[str] = mapped_column(ForeignKey("teams.id", ondelete="CASCADE"), nullable=False)
    submission_type: Mapped[TeamNoteSubmissionType] = mapped_column(
        SqlEnum(TeamNoteSubmissionType, native_enum=False, length=16),
        default=TeamNoteSubmissionType.CREATE,
        nullable=False,
    )
    source_note_id: Mapped[str] = mapped_column(ForeignKey("notes.id"), nullable=False)
    applicant_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False)
    source_author_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False)
    target_team_note_id: Mapped[str | None] = mapped_column(
        ForeignKey("team_notes.id", ondelete="SET NULL"), nullable=True
    )
    snapshot_title: Mapped[str] = mapped_column(String(500), nullable=False)
    snapshot_content_json: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    snapshot_plain_text: Mapped[str] = mapped_column(Text, default="", nullable=False)
    snapshot_attachment_ids: Mapped[list[str]] = mapped_column(JSON, default=list, nullable=False)
    snapshot_hash: Mapped[str] = mapped_column(String(64), default="", nullable=False)
    proposed_category_id: Mapped[str | None] = mapped_column(
        ForeignKey("team_note_categories.id", ondelete="SET NULL"), nullable=True
    )
    proposed_tags_json: Mapped[list[str]] = mapped_column(JSON, default=list, nullable=False)
    submission_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[TeamNoteSubmissionStatus] = mapped_column(
        SqlEnum(TeamNoteSubmissionStatus, native_enum=False, length=16),
        default=TeamNoteSubmissionStatus.PENDING,
        nullable=False,
    )
    reviewer_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    review_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    review_reason_code: Mapped[str | None] = mapped_column(String(64), nullable=True)
    review_comment: Mapped[str | None] = mapped_column(Text, nullable=True)
    revision_no: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    approved_team_note_id: Mapped[str | None] = mapped_column(
        ForeignKey("team_notes.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, onupdate=local_now, nullable=False)

    team: Mapped["Team"] = relationship()
    source_note: Mapped["Note"] = relationship()
    applicant: Mapped["User"] = relationship(foreign_keys=[applicant_id])
    source_author: Mapped["User"] = relationship(foreign_keys=[source_author_id])
    reviewer: Mapped["User | None"] = relationship(foreign_keys=[reviewer_id])
    approved_team_note: Mapped["TeamNote | None"] = relationship(foreign_keys=[approved_team_note_id])
    target_team_note: Mapped["TeamNote | None"] = relationship(foreign_keys=[target_team_note_id])
    proposed_category: Mapped["TeamNoteCategory | None"] = relationship()


class TeamNoteVersion(Base):
    __tablename__ = "team_note_versions"
    __table_args__ = (
        UniqueConstraint("team_note_id", "version_no", name="uq_team_note_versions_note_version"),
        UniqueConstraint("source_submission_id", name="uq_team_note_versions_submission"),
        Index("ix_team_note_versions_note_created", "team_note_id", "created_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    team_note_id: Mapped[str] = mapped_column(ForeignKey("team_notes.id", ondelete="CASCADE"), nullable=False)
    version_no: Mapped[int] = mapped_column(Integer, nullable=False)
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    content_json: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    plain_text: Mapped[str] = mapped_column(Text, default="", nullable=False)
    attachment_ids: Mapped[list[str]] = mapped_column(JSON, default=list, nullable=False)
    category_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    tags: Mapped[list[str]] = mapped_column(JSON, default=list, nullable=False)
    change_type: Mapped[str] = mapped_column(String(32), nullable=False)
    changed_by_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    source_submission_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)

    team_note: Mapped[TeamNote] = relationship()
    changed_by: Mapped["User | None"] = relationship()


class SubmissionFileAccess(Base):
    __tablename__ = "submission_file_access"
    __table_args__ = (
        UniqueConstraint("submission_id", "attachment_id", name="uq_submission_file_access_submission_attachment"),
        Index("ix_submission_file_access_attachment", "attachment_id"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    submission_id: Mapped[str] = mapped_column(
        ForeignKey("team_note_submissions.id", ondelete="CASCADE"), nullable=False
    )
    attachment_id: Mapped[str] = mapped_column(ForeignKey("attachments.id", ondelete="CASCADE"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)

    submission: Mapped[TeamNoteSubmission] = relationship()
    attachment: Mapped["Attachment"] = relationship()


class TeamFileAccess(Base):
    __tablename__ = "team_file_access"
    __table_args__ = (
        UniqueConstraint("team_note_id", "attachment_id", name="uq_team_file_access_note_attachment"),
        Index("ix_team_file_access_team", "team_id", "created_at"),
        Index("ix_team_file_access_attachment", "attachment_id", "team_id"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    team_id: Mapped[str] = mapped_column(ForeignKey("teams.id", ondelete="CASCADE"), nullable=False)
    attachment_id: Mapped[str] = mapped_column(ForeignKey("attachments.id", ondelete="CASCADE"), nullable=False)
    team_note_id: Mapped[str] = mapped_column(ForeignKey("team_notes.id", ondelete="CASCADE"), nullable=False)
    granted_by_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)

    team: Mapped["Team"] = relationship()
    attachment: Mapped["Attachment"] = relationship()
    team_note: Mapped[TeamNote | None] = relationship()
    granted_by: Mapped["User | None"] = relationship(foreign_keys=[granted_by_id])
