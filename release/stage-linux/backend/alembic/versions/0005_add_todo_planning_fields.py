"""Add task range, list, and tags.

Revision ID: 0005
Revises: 0004
Create Date: 2026-08-08
"""
from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0005"
down_revision: str | Sequence[str] | None = "0004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("todos", sa.Column("due_end_at", sa.DateTime(), nullable=True))
    op.add_column("todos", sa.Column("list_name", sa.String(length=120), nullable=False, server_default="收集箱"))
    op.add_column("todos", sa.Column("tags", sa.JSON(), nullable=False, server_default=sa.text("'[]'")))


def downgrade() -> None:
    op.drop_column("todos", "tags")
    op.drop_column("todos", "list_name")
    op.drop_column("todos", "due_end_at")
