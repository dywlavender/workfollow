"""Add folders, notes, templates, and attachments.

Revision ID: 0004
Revises: 0003
Create Date: 2026-08-08
"""
from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0004"
down_revision: str | Sequence[str] | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "folders",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("parent_id", sa.String(length=36), nullable=True),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["parent_id"], ["folders.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_folders_parent_sort", "folders", ["parent_id", "sort_order"])
    op.create_table(
        "note_templates",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("content_json", sa.JSON(), nullable=False),
        sa.Column("is_builtin", sa.Boolean(), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_table(
        "notes",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("folder_id", sa.String(length=36), nullable=True),
        sa.Column("title", sa.String(length=500), nullable=False),
        sa.Column("content_json", sa.JSON(), nullable=False),
        sa.Column("plain_text", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.Column("deleted_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["folder_id"], ["folders.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_notes_deleted_at", "notes", ["deleted_at"])
    op.create_index("ix_notes_folder_updated", "notes", ["folder_id", "updated_at"])
    op.create_table(
        "attachments",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("note_id", sa.String(length=36), nullable=False),
        sa.Column("original_name", sa.String(length=500), nullable=False),
        sa.Column("storage_name", sa.String(length=100), nullable=False),
        sa.Column("mime_type", sa.String(length=200), nullable=False),
        sa.Column("size", sa.Integer(), nullable=False),
        sa.Column("file_path", sa.String(length=1000), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["note_id"], ["notes.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("storage_name"),
    )
    op.create_index("ix_attachments_note_created", "attachments", ["note_id", "created_at"])


def downgrade() -> None:
    op.drop_index("ix_attachments_note_created", table_name="attachments")
    op.drop_table("attachments")
    op.drop_index("ix_notes_folder_updated", table_name="notes")
    op.drop_index("ix_notes_deleted_at", table_name="notes")
    op.drop_table("notes")
    op.drop_table("note_templates")
    op.drop_index("ix_folders_parent_sort", table_name="folders")
    op.drop_table("folders")

