"""Harden team workflows and add team task planning/files.

Revision ID: 0014
Revises: 0013
Create Date: 2026-08-09
"""
from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0014"
down_revision: str | Sequence[str] | None = "0013"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("team_tasks") as batch:
        batch.add_column(sa.Column("reminder_at", sa.DateTime(), nullable=True))
        batch.add_column(sa.Column("recurrence_type", sa.String(length=16), nullable=False, server_default="NONE"))
        batch.add_column(sa.Column("recurrence_config", sa.JSON(), nullable=True))
        batch.add_column(sa.Column("attachment_ids", sa.JSON(), nullable=False, server_default="[]"))
        batch.add_column(sa.Column("client_request_id", sa.String(length=64), nullable=True))
        batch.create_unique_constraint(
            "uq_team_tasks_client_request", ["team_id", "creator_id", "client_request_id"]
        )

    with op.batch_alter_table("team_notes") as batch:
        batch.add_column(sa.Column("source_submission_id", sa.String(length=36), nullable=True))
        batch.create_unique_constraint("uq_team_notes_source_submission_id", ["source_submission_id"])
    op.execute(
        "UPDATE team_notes SET source_submission_id = ("
        "SELECT id FROM team_note_submissions "
        "WHERE team_note_submissions.approved_team_note_id = team_notes.id LIMIT 1"
        ") WHERE EXISTS (SELECT 1 FROM team_note_submissions "
        "WHERE team_note_submissions.approved_team_note_id = team_notes.id)"
    )

    with op.batch_alter_table("attachments") as batch:
        batch.alter_column("note_id", existing_type=sa.String(length=36), nullable=True)

    op.create_table(
        "team_task_file_access",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("team_id", sa.String(length=36), nullable=False),
        sa.Column("attachment_id", sa.String(length=36), nullable=False),
        sa.Column("team_task_id", sa.String(length=36), nullable=False),
        sa.Column("granted_by_id", sa.String(length=36), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["team_id"], ["teams.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["attachment_id"], ["attachments.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["team_task_id"], ["team_tasks.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["granted_by_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("team_task_id", "attachment_id", name="uq_team_task_file_access_task_attachment"),
    )
    op.create_index("ix_team_task_file_access_team", "team_task_file_access", ["team_id", "created_at"])
    op.create_index(
        "ix_team_task_file_access_attachment", "team_task_file_access", ["attachment_id", "team_id"]
    )
    op.create_index("ix_todos_owner_due_at", "todos", ["owner_id", "due_at"])
    op.create_index("ix_notes_owner_updated_at", "notes", ["owner_id", "updated_at"])


def downgrade() -> None:
    op.drop_index("ix_notes_owner_updated_at", table_name="notes")
    op.drop_index("ix_todos_owner_due_at", table_name="todos")
    op.drop_index("ix_team_task_file_access_attachment", table_name="team_task_file_access")
    op.drop_index("ix_team_task_file_access_team", table_name="team_task_file_access")
    op.drop_table("team_task_file_access")
    with op.batch_alter_table("attachments") as batch:
        batch.alter_column("note_id", existing_type=sa.String(length=36), nullable=False)
    with op.batch_alter_table("team_notes") as batch:
        batch.drop_constraint("uq_team_notes_source_submission_id", type_="unique")
        batch.drop_column("source_submission_id")
    with op.batch_alter_table("team_tasks") as batch:
        batch.drop_constraint("uq_team_tasks_client_request", type_="unique")
        batch.drop_column("client_request_id")
        batch.drop_column("attachment_ids")
        batch.drop_column("recurrence_config")
        batch.drop_column("recurrence_type")
        batch.drop_column("reminder_at")
