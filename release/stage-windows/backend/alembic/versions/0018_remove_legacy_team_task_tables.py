"""Remove the duplicate legacy team-task fact source.

Revision ID: 0018
Revises: 0017
Create Date: 2026-08-09
"""
from typing import Sequence

from alembic import op


revision: str = "0018"
down_revision: str | Sequence[str] | None = "0017"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # 0016 and 0017 have already copied every task, assignment, and file grant
    # into the unified Task tables. Dropping these tables is what makes that
    # invariant structural instead of merely conventional.
    op.drop_table("team_task_file_access")
    op.drop_table("team_task_assignments")
    op.drop_table("team_tasks")
    op.drop_index("ix_todos_transferred_team_task_id", table_name="todos")
    with op.batch_alter_table("todos", recreate="always") as batch:
        batch.drop_column("transferred_team_task_id")


def downgrade() -> None:
    # The removed rows were merged into todos/task_assignments and cannot be
    # losslessly split back into a duplicate fact source.
    raise RuntimeError("0018 is intentionally irreversible; restore the pre-0016 database backup instead")
