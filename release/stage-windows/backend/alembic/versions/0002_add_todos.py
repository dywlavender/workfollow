"""Add Todo model.

Revision ID: 0002
Revises: 0001
Create Date: 2026-08-08
"""
from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0002"
down_revision: str | Sequence[str] | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "todos",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("title", sa.String(length=500), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("status", sa.Enum("TODO", "DONE", name="todostatus", native_enum=False), nullable=False),
        sa.Column("priority", sa.Enum("NONE", "LOW", "MEDIUM", "HIGH", name="todopriority", native_enum=False), nullable=False),
        sa.Column("due_at", sa.DateTime(), nullable=True),
        sa.Column("reminder_at", sa.DateTime(), nullable=True),
        sa.Column("reminded_at", sa.DateTime(), nullable=True),
        sa.Column("recurrence_type", sa.Enum("NONE", "DAILY", "WEEKLY", "MONTHLY", "CUSTOM", name="recurrencetype", native_enum=False), nullable=False),
        sa.Column("recurrence_config", sa.JSON(), nullable=True),
        sa.Column("source_type", sa.Enum("MANUAL", "NOTE", "AI", name="todosourcetype", native_enum=False), nullable=False),
        sa.Column("source_note_id", sa.String(length=36), nullable=True),
        sa.Column("source_excerpt", sa.Text(), nullable=True),
        sa.Column("recurring_series_id", sa.String(length=36), nullable=True),
        sa.Column("generated_from_id", sa.String(length=36), nullable=True),
        sa.Column("completed_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("generated_from_id"),
    )
    op.create_index("ix_todos_created_at", "todos", ["created_at"])
    op.create_index("ix_todos_status_due_at", "todos", ["status", "due_at"])


def downgrade() -> None:
    op.drop_index("ix_todos_status_due_at", table_name="todos")
    op.drop_index("ix_todos_created_at", table_name="todos")
    op.drop_table("todos")

