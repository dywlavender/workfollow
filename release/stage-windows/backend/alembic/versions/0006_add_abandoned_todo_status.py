"""Add abandoned todo status and expand the status column.

Revision ID: 0006
Revises: 0005
Create Date: 2026-08-09
"""
from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0006"
down_revision: str | Sequence[str] | None = "0005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("todos") as batch_op:
        batch_op.alter_column(
            "status",
            existing_type=sa.String(length=4),
            type_=sa.String(length=16),
            existing_nullable=False,
        )


def downgrade() -> None:
    op.execute("UPDATE todos SET status = 'TODO' WHERE status = 'ABANDONED'")
    with op.batch_alter_table("todos") as batch_op:
        batch_op.alter_column(
            "status",
            existing_type=sa.String(length=16),
            type_=sa.String(length=4),
            existing_nullable=False,
        )
