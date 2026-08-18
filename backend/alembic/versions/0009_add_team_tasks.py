"""Add team tasks and assignments.

Revision ID: 0009
Revises: 0008
Create Date: 2026-08-09
"""
from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0009"
down_revision: str | Sequence[str] | None = "0008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "team_tasks",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("team_id", sa.String(length=36), nullable=False),
        sa.Column("creator_id", sa.String(length=36), nullable=False),
        sa.Column("title", sa.String(length=500), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("content_json", sa.JSON(), nullable=True),
        sa.Column("priority", sa.String(length=16), nullable=False),
        sa.Column("due_at", sa.DateTime(), nullable=True),
        sa.Column("due_end_at", sa.DateTime(), nullable=True),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("completed_at", sa.DateTime(), nullable=True),
        sa.Column("cancelled_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["team_id"], ["teams.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["creator_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_team_tasks_team_status_due", "team_tasks", ["team_id", "status", "due_at"])
    op.create_index("ix_team_tasks_creator", "team_tasks", ["creator_id", "created_at"])
    op.create_table(
        "team_task_assignments",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("team_task_id", sa.String(length=36), nullable=False),
        sa.Column("user_id", sa.String(length=36), nullable=False),
        sa.Column("assigned_by_id", sa.String(length=36), nullable=True),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("assigned_at", sa.DateTime(), nullable=False),
        sa.Column("completed_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["team_task_id"], ["team_tasks.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["assigned_by_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("team_task_id", "user_id", name="uq_team_task_assignments_task_user"),
    )
    op.create_index("ix_team_task_assignments_user_status", "team_task_assignments", ["user_id", "status"])
    op.create_index("ix_team_task_assignments_task_status", "team_task_assignments", ["team_task_id", "status"])


def downgrade() -> None:
    op.drop_index("ix_team_task_assignments_task_status", table_name="team_task_assignments")
    op.drop_index("ix_team_task_assignments_user_status", table_name="team_task_assignments")
    op.drop_table("team_task_assignments")
    op.drop_index("ix_team_tasks_creator", table_name="team_tasks")
    op.drop_index("ix_team_tasks_team_status_due", table_name="team_tasks")
    op.drop_table("team_tasks")
