"""Unify personal and assigned work on the existing todos task table.

Revision ID: 0016
Revises: 0015
Create Date: 2026-08-09
"""
from __future__ import annotations

from datetime import datetime
from typing import Sequence
from uuid import uuid4

from alembic import op
import sqlalchemy as sa


revision: str = "0016"
down_revision: str | Sequence[str] | None = "0015"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _uuid() -> str:
    return str(uuid4())


def upgrade() -> None:
    with op.batch_alter_table("todos") as batch:
        batch.add_column(sa.Column("creator_id", sa.String(length=36), nullable=True))
        batch.add_column(sa.Column("team_id", sa.String(length=36), nullable=True))
        batch.add_column(sa.Column("content_json", sa.JSON(), nullable=True))
        batch.add_column(sa.Column("attachment_ids", sa.JSON(), nullable=False, server_default="[]"))

    op.create_table(
        "task_assignments",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("task_id", sa.String(length=36), nullable=False),
        sa.Column("user_id", sa.String(length=36), nullable=False),
        sa.Column("assigned_by_id", sa.String(length=36), nullable=True),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("assigned_at", sa.DateTime(), nullable=False),
        sa.Column("completed_at", sa.DateTime(), nullable=True),
        sa.Column("removed_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["task_id"], ["todos.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["assigned_by_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("task_id", "user_id", name="uq_task_assignments_task_user"),
    )
    op.create_index(
        "ix_task_assignments_user_active_status", "task_assignments", ["user_id", "active", "status"]
    )
    op.create_index(
        "ix_task_assignments_task_active_status", "task_assignments", ["task_id", "active", "status"]
    )

    bind = op.get_bind()
    now = datetime.now().replace(microsecond=0)
    bind.execute(sa.text("UPDATE todos SET creator_id = owner_id WHERE creator_id IS NULL"))

    # Every historical personal task becomes a self-assigned task without
    # changing its identity, dates, recurrence chain, or completion history.
    old_todos = bind.execute(sa.text(
        "SELECT id, owner_id, status, completed_at, created_at, updated_at FROM todos"
    )).mappings().all()
    for row in old_todos:
        bind.execute(sa.text(
            "INSERT INTO task_assignments "
            "(id, task_id, user_id, assigned_by_id, status, active, assigned_at, completed_at, removed_at, created_at, updated_at) "
            "VALUES (:id, :task_id, :user_id, :user_id, :status, 1, :assigned_at, :completed_at, NULL, :created_at, :updated_at)"
        ), {
            "id": _uuid(),
            "task_id": row["id"],
            "user_id": row["owner_id"],
            "status": "DONE" if row["status"] == "DONE" else "TODO",
            "assigned_at": row["created_at"] or now,
            "completed_at": row["completed_at"] if row["status"] == "DONE" else None,
            "created_at": row["created_at"] or now,
            "updated_at": row["updated_at"] or now,
        })

    # Old transfer rows are merged back into their original Todo identity.
    transferred = {
        row["team_task_id"]: row["todo_id"]
        for row in bind.execute(sa.text(
            "SELECT id AS todo_id, transferred_team_task_id AS team_task_id "
            "FROM todos WHERE transferred_team_task_id IS NOT NULL"
        )).mappings()
    }
    team_tasks = bind.execute(sa.text("SELECT * FROM team_tasks")).mappings().all()
    for task in team_tasks:
        destination_id = transferred.get(task["id"], task["id"])
        mapped_status = "DONE" if task["status"] == "COMPLETED" else (
            "ABANDONED" if task["status"] == "CANCELLED" else "TODO"
        )
        values = {
            "id": destination_id,
            "owner_id": task["creator_id"],
            "creator_id": task["creator_id"],
            "team_id": task["team_id"],
            "title": task["title"],
            "description": task["description"],
            "content_json": task["content_json"],
            "attachment_ids": task["attachment_ids"] or "[]",
            "status": mapped_status,
            "priority": task["priority"],
            "due_at": task["due_at"],
            "due_end_at": task["due_end_at"],
            "reminder_at": task["reminder_at"],
            "recurrence_type": task["recurrence_type"],
            "recurrence_config": task["recurrence_config"],
            "list_name": task["list_name"] or "收集箱",
            "tags": task["tags"] or "[]",
            "completed_at": task["completed_at"],
            "created_at": task["created_at"],
            "updated_at": task["updated_at"],
        }
        if task["id"] in transferred:
            bind.execute(sa.text(
                "UPDATE todos SET owner_id=:owner_id, creator_id=:creator_id, team_id=:team_id, title=:title, "
                "description=:description, content_json=:content_json, attachment_ids=:attachment_ids, status=:status, "
                "priority=:priority, due_at=:due_at, due_end_at=:due_end_at, reminder_at=:reminder_at, "
                "recurrence_type=:recurrence_type, recurrence_config=:recurrence_config, list_name=:list_name, tags=:tags, "
                "completed_at=:completed_at, updated_at=:updated_at, transferred_team_task_id=NULL WHERE id=:id"
            ), values)
            bind.execute(sa.text("UPDATE task_assignments SET active=0, removed_at=:now WHERE task_id=:id"), {
                "now": now, "id": destination_id,
            })
        else:
            bind.execute(sa.text(
                "INSERT INTO todos "
                "(id, owner_id, creator_id, team_id, title, description, content_json, attachment_ids, status, priority, "
                "due_at, due_end_at, reminder_at, reminded_at, recurrence_type, recurrence_config, list_name, tags, "
                "source_type, source_note_id, source_excerpt, recurring_series_id, generated_from_id, "
                "transferred_team_task_id, completed_at, created_at, updated_at) "
                "VALUES (:id, :owner_id, :creator_id, :team_id, :title, :description, :content_json, :attachment_ids, "
                ":status, :priority, :due_at, :due_end_at, :reminder_at, NULL, :recurrence_type, :recurrence_config, "
                ":list_name, :tags, 'MANUAL', NULL, NULL, NULL, NULL, NULL, :completed_at, :created_at, :updated_at)"
            ), values)

    for assignment in bind.execute(sa.text("SELECT * FROM team_task_assignments")).mappings().all():
        task_id = transferred.get(assignment["team_task_id"], assignment["team_task_id"])
        existing = bind.execute(sa.text(
            "SELECT id FROM task_assignments WHERE task_id=:task_id AND user_id=:user_id"
        ), {"task_id": task_id, "user_id": assignment["user_id"]}).scalar_one_or_none()
        values = {
            "id": existing or assignment["id"],
            "task_id": task_id,
            "user_id": assignment["user_id"],
            "assigned_by_id": assignment["assigned_by_id"],
            "status": assignment["status"],
            "assigned_at": assignment["assigned_at"],
            "completed_at": assignment["completed_at"],
            "created_at": assignment["created_at"],
            "updated_at": assignment["updated_at"],
        }
        if existing:
            bind.execute(sa.text(
                "UPDATE task_assignments SET assigned_by_id=:assigned_by_id, status=:status, active=1, "
                "assigned_at=:assigned_at, completed_at=:completed_at, removed_at=NULL, updated_at=:updated_at WHERE id=:id"
            ), values)
        else:
            bind.execute(sa.text(
                "INSERT INTO task_assignments "
                "(id, task_id, user_id, assigned_by_id, status, active, assigned_at, completed_at, removed_at, created_at, updated_at) "
                "VALUES (:id, :task_id, :user_id, :assigned_by_id, :status, 1, :assigned_at, :completed_at, NULL, :created_at, :updated_at)"
            ), values)

    with op.batch_alter_table("todos", recreate="always") as batch:
        batch.alter_column("creator_id", existing_type=sa.String(length=36), nullable=False)
        batch.create_foreign_key("fk_todos_creator_id", "users", ["creator_id"], ["id"])
        batch.create_foreign_key("fk_todos_team_id", "teams", ["team_id"], ["id"], ondelete="SET NULL")
    op.create_index("ix_todos_creator_id", "todos", ["creator_id"])
    op.create_index("ix_todos_team_id", "todos", ["team_id"])
    op.create_index("ix_todos_creator_created_at", "todos", ["creator_id", "created_at"])
    op.create_index("ix_todos_team_status_due_at", "todos", ["team_id", "status", "due_at"])


def downgrade() -> None:
    op.drop_index("ix_todos_team_status_due_at", table_name="todos")
    op.drop_index("ix_todos_creator_created_at", table_name="todos")
    op.drop_index("ix_todos_team_id", table_name="todos")
    op.drop_index("ix_todos_creator_id", table_name="todos")
    with op.batch_alter_table("todos", recreate="always") as batch:
        batch.drop_constraint("fk_todos_team_id", type_="foreignkey")
        batch.drop_constraint("fk_todos_creator_id", type_="foreignkey")
        batch.drop_column("attachment_ids")
        batch.drop_column("content_json")
        batch.drop_column("team_id")
        batch.drop_column("creator_id")
    op.drop_index("ix_task_assignments_task_active_status", table_name="task_assignments")
    op.drop_index("ix_task_assignments_user_active_status", table_name="task_assignments")
    op.drop_table("task_assignments")
