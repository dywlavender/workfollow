"""Queue autosave notifications until the task edit becomes idle."""

from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0031"
down_revision: str | Sequence[str] | None = "0030"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "pending_task_update_notifications",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("task_id", sa.String(length=36), nullable=False),
        sa.Column("recipient_id", sa.String(length=36), nullable=False),
        sa.Column("actor_user_id", sa.String(length=36), nullable=True),
        sa.Column("before_json", sa.JSON(), nullable=False),
        sa.Column("after_json", sa.JSON(), nullable=False),
        sa.Column("next_attempt_at", sa.DateTime(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["task_id"], ["todos.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["recipient_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["actor_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "task_id",
            "recipient_id",
            name="uq_pending_task_update_task_recipient",
        ),
    )
    op.create_index(
        "ix_pending_task_update_next_attempt",
        "pending_task_update_notifications",
        ["next_attempt_at"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_pending_task_update_next_attempt",
        table_name="pending_task_update_notifications",
    )
    op.drop_table("pending_task_update_notifications")
