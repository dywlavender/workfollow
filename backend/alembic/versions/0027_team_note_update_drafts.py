"""Track update drafts and the target version used for knowledge submissions.

Revision ID: 0027
Revises: 0026
Create Date: 2026-08-19
"""

from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0027"
down_revision: str | Sequence[str] | None = "0026"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("notes") as batch_op:
        batch_op.add_column(
            sa.Column("is_knowledge_update_draft", sa.Boolean(), nullable=False, server_default=sa.false())
        )
        batch_op.add_column(sa.Column("copied_from_team_note_version_no", sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column("copied_from_team_note_snapshot_hash", sa.String(length=64), nullable=True))

    op.create_index(
        "ix_notes_owner_update_draft_target",
        "notes",
        ["owner_id", "copied_from_team_note_id", "is_knowledge_update_draft", "deleted_at"],
    )
    op.create_index(
        "uq_notes_owner_active_update_draft_target",
        "notes",
        ["owner_id", "copied_from_team_note_id"],
        unique=True,
        sqlite_where=sa.text("is_knowledge_update_draft = TRUE AND deleted_at IS NULL"),
        postgresql_where=sa.text("is_knowledge_update_draft = TRUE AND deleted_at IS NULL"),
    )

    with op.batch_alter_table("team_note_submissions") as batch_op:
        batch_op.add_column(sa.Column("base_team_note_version_no", sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column("base_team_note_snapshot_hash", sa.String(length=64), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("team_note_submissions") as batch_op:
        batch_op.drop_column("base_team_note_snapshot_hash")
        batch_op.drop_column("base_team_note_version_no")

    op.drop_index("uq_notes_owner_active_update_draft_target", table_name="notes")
    op.drop_index("ix_notes_owner_update_draft_target", table_name="notes")
    with op.batch_alter_table("notes") as batch_op:
        batch_op.drop_column("copied_from_team_note_snapshot_hash")
        batch_op.drop_column("copied_from_team_note_version_no")
        batch_op.drop_column("is_knowledge_update_draft")
