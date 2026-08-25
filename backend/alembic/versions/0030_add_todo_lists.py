"""Persist the shared task-list catalog."""

from datetime import datetime
import uuid
from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0030"
down_revision: str | Sequence[str] | None = "0029"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

DEFAULT_NAMES = ("收集箱", "工作", "个人", "学习")


def upgrade() -> None:
    op.create_table(
        "todo_lists",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_by_id", sa.String(length=36), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["created_by_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("name", name="uq_todo_lists_name"),
    )
    op.create_index("ix_todo_lists_sort_order", "todo_lists", ["sort_order", "created_at"])

    bind = op.get_bind()
    now = datetime.now().replace(microsecond=0)
    rows = [
        {
            "id": str(uuid.uuid4()),
            "name": name,
            "sort_order": index,
            "created_by_id": None,
            "created_at": now,
            "updated_at": now,
        }
        for index, name in enumerate(DEFAULT_NAMES)
    ]
    bind.execute(sa.table(
        "todo_lists",
        sa.column("id", sa.String()),
        sa.column("name", sa.String()),
        sa.column("sort_order", sa.Integer()),
        sa.column("created_by_id", sa.String()),
        sa.column("created_at", sa.DateTime()),
        sa.column("updated_at", sa.DateTime()),
    ).insert(), rows)

    legacy_names = [name for (name,) in bind.execute(
        sa.text("SELECT DISTINCT list_name FROM todos WHERE list_name IS NOT NULL")
    )]
    custom_rows = [
        {
            "id": str(uuid.uuid4()),
            "name": name,
            "sort_order": len(DEFAULT_NAMES) + index,
            "created_by_id": None,
            "created_at": now,
            "updated_at": now,
        }
        for index, name in enumerate(sorted(set(legacy_names) - set(DEFAULT_NAMES)))
    ]
    if custom_rows:
        bind.execute(sa.table(
            "todo_lists",
            sa.column("id", sa.String()),
            sa.column("name", sa.String()),
            sa.column("sort_order", sa.Integer()),
            sa.column("created_by_id", sa.String()),
            sa.column("created_at", sa.DateTime()),
            sa.column("updated_at", sa.DateTime()),
        ).insert(), custom_rows)


def downgrade() -> None:
    op.drop_index("ix_todo_lists_sort_order", table_name="todo_lists")
    op.drop_table("todo_lists")
