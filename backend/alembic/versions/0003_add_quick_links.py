"""Add QuickLink model.

Revision ID: 0003
Revises: 0002
Create Date: 2026-08-08
"""
from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0003"
down_revision: str | Sequence[str] | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "quick_links",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("url", sa.String(length=2048), nullable=False),
        sa.Column("icon", sa.String(length=32), nullable=False),
        sa.Column("group_name", sa.String(length=120), nullable=True),
        sa.Column("sort_order", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_quick_links_sort_order", "quick_links", ["sort_order", "created_at"])


def downgrade() -> None:
    op.drop_index("ix_quick_links_sort_order", table_name="quick_links")
    op.drop_table("quick_links")

