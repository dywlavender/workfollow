"""Attach files to the unified task fact source.

Revision ID: 0017
Revises: 0016
Create Date: 2026-08-09
"""
from __future__ import annotations

import json
from datetime import datetime
from typing import Sequence
from uuid import uuid4

from alembic import op
import sqlalchemy as sa


revision: str = "0017"
down_revision: str | Sequence[str] | None = "0016"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "task_file_access",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("task_id", sa.String(length=36), nullable=False),
        sa.Column("attachment_id", sa.String(length=36), nullable=False),
        sa.Column("granted_by_id", sa.String(length=36), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["task_id"], ["todos.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["attachment_id"], ["attachments.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["granted_by_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("task_id", "attachment_id", name="uq_task_file_access_task_attachment"),
    )
    op.create_index("ix_task_file_access_attachment", "task_file_access", ["attachment_id"])

    bind = op.get_bind()
    now = datetime.now().replace(microsecond=0)
    for row in bind.execute(sa.text(
        "SELECT id, creator_id, attachment_ids FROM todos WHERE attachment_ids IS NOT NULL"
    )).mappings():
        raw = row["attachment_ids"]
        attachment_ids = json.loads(raw) if isinstance(raw, str) else (raw or [])
        for attachment_id in dict.fromkeys(attachment_ids):
            exists = bind.execute(sa.text("SELECT id FROM attachments WHERE id=:id"), {"id": attachment_id}).scalar()
            if exists is None:
                continue
            bind.execute(sa.text(
                "INSERT INTO task_file_access (id, task_id, attachment_id, granted_by_id, created_at) "
                "VALUES (:id, :task_id, :attachment_id, :granted_by_id, :created_at)"
            ), {
                "id": str(uuid4()),
                "task_id": row["id"],
                "attachment_id": attachment_id,
                "granted_by_id": row["creator_id"],
                "created_at": now,
            })


def downgrade() -> None:
    op.drop_index("ix_task_file_access_attachment", table_name="task_file_access")
    op.drop_table("task_file_access")
