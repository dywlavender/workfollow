"""Add team task list/tags and todo transfer link.

Revision ID: 0015
Revises: 0014
Create Date: 2026-08-09
"""
from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0015"
down_revision: str | Sequence[str] | None = "0014"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("team_tasks") as batch:
        batch.add_column(sa.Column("list_name", sa.String(length=120), nullable=False, server_default="收集箱"))
        batch.add_column(sa.Column("tags", sa.JSON(), nullable=False, server_default="[]"))

    with op.batch_alter_table("todos") as batch:
        batch.add_column(sa.Column("transferred_team_task_id", sa.String(length=36), nullable=True))
    op.create_index("ix_todos_transferred_team_task_id", "todos", ["transferred_team_task_id"])


def downgrade() -> None:
    op.drop_index("ix_todos_transferred_team_task_id", table_name="todos")
    with op.batch_alter_table("todos") as batch:
        batch.drop_column("transferred_team_task_id")
    with op.batch_alter_table("team_tasks") as batch:
        batch.drop_column("tags")
        batch.drop_column("list_name")
