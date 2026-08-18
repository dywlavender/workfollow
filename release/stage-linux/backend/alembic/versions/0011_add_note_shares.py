"""Add live read-only note shares.

Revision ID: 0011
Revises: 0010
Create Date: 2026-08-09
"""
from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0011"
down_revision: str | Sequence[str] | None = "0010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "note_shares",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("note_id", sa.String(length=36), nullable=False),
        sa.Column("shared_by_user_id", sa.String(length=36), nullable=False),
        sa.Column("shared_with_user_id", sa.String(length=36), nullable=False),
        sa.Column("permission", sa.String(length=16), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("revoked_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["note_id"], ["notes.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["shared_by_user_id"], ["users.id"]),
        sa.ForeignKeyConstraint(["shared_with_user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("note_id", "shared_with_user_id", name="uq_note_shares_note_user"),
    )
    op.create_index("ix_note_shares_shared_user_status", "note_shares", ["shared_with_user_id", "status"])
    op.create_index("ix_note_shares_note_status", "note_shares", ["note_id", "status"])


def downgrade() -> None:
    op.drop_index("ix_note_shares_note_status", table_name="note_shares")
    op.drop_index("ix_note_shares_shared_user_status", table_name="note_shares")
    op.drop_table("note_shares")
