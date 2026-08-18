"""Add team notes, snapshot submissions, and team file access.

Revision ID: 0010
Revises: 0009
Create Date: 2026-08-09
"""
from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0010"
down_revision: str | Sequence[str] | None = "0009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "team_notes",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("team_id", sa.String(length=36), nullable=False),
        sa.Column("title", sa.String(length=500), nullable=False),
        sa.Column("content_json", sa.JSON(), nullable=False),
        sa.Column("plain_text", sa.Text(), nullable=False),
        sa.Column("attachment_ids", sa.JSON(), nullable=False),
        sa.Column("created_by_id", sa.String(length=36), nullable=True),
        sa.Column("updated_by_id", sa.String(length=36), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["team_id"], ["teams.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["created_by_id"], ["users.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["updated_by_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_team_notes_team_updated", "team_notes", ["team_id", "updated_at"])
    op.create_table(
        "team_note_submissions",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("team_id", sa.String(length=36), nullable=False),
        sa.Column("source_note_id", sa.String(length=36), nullable=False),
        sa.Column("applicant_id", sa.String(length=36), nullable=False),
        sa.Column("snapshot_title", sa.String(length=500), nullable=False),
        sa.Column("snapshot_content_json", sa.JSON(), nullable=False),
        sa.Column("snapshot_plain_text", sa.Text(), nullable=False),
        sa.Column("snapshot_attachment_ids", sa.JSON(), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("reviewer_id", sa.String(length=36), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(), nullable=True),
        sa.Column("review_reason", sa.Text(), nullable=True),
        sa.Column("approved_team_note_id", sa.String(length=36), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["team_id"], ["teams.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["source_note_id"], ["notes.id"]),
        sa.ForeignKeyConstraint(["applicant_id"], ["users.id"]),
        sa.ForeignKeyConstraint(["reviewer_id"], ["users.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["approved_team_note_id"], ["team_notes.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_team_note_submissions_team_status", "team_note_submissions", ["team_id", "status", "created_at"])
    op.create_index("ix_team_note_submissions_applicant", "team_note_submissions", ["applicant_id", "created_at"])
    op.create_table(
        "team_file_access",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("team_id", sa.String(length=36), nullable=False),
        sa.Column("attachment_id", sa.String(length=36), nullable=False),
        sa.Column("team_note_id", sa.String(length=36), nullable=False),
        sa.Column("granted_by_id", sa.String(length=36), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["team_id"], ["teams.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["attachment_id"], ["attachments.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["team_note_id"], ["team_notes.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["granted_by_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("team_note_id", "attachment_id", name="uq_team_file_access_note_attachment"),
    )
    op.create_index("ix_team_file_access_team", "team_file_access", ["team_id", "created_at"])
    op.create_index("ix_team_file_access_attachment", "team_file_access", ["attachment_id", "team_id"])


def downgrade() -> None:
    op.drop_index("ix_team_file_access_attachment", table_name="team_file_access")
    op.drop_index("ix_team_file_access_team", table_name="team_file_access")
    op.drop_table("team_file_access")
    op.drop_index("ix_team_note_submissions_applicant", table_name="team_note_submissions")
    op.drop_index("ix_team_note_submissions_team_status", table_name="team_note_submissions")
    op.drop_table("team_note_submissions")
    op.drop_index("ix_team_notes_team_updated", table_name="team_notes")
    op.drop_table("team_notes")
