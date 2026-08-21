"""Add the external HTTP notification delivery queue.

Revision ID: 0028
Revises: 0027
Create Date: 2026-08-21
"""

from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0028"
down_revision: str | Sequence[str] | None = "0027"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "external_notification_deliveries",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("user_id", sa.String(length=36), nullable=False),
        sa.Column("username", sa.String(length=80), nullable=False),
        sa.Column("notification_type", sa.String(length=32), nullable=False),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("data_json", sa.JSON(), nullable=False),
        sa.Column("delivery_key", sa.String(length=255), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("next_attempt_at", sa.DateTime(), nullable=False),
        sa.Column("last_attempt_at", sa.DateTime(), nullable=True),
        sa.Column("last_error", sa.Text(), nullable=True),
        sa.Column("sent_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("delivery_key"),
    )
    op.create_index(
        "ix_external_notification_status_next_attempt",
        "external_notification_deliveries",
        ["status", "next_attempt_at"],
    )
    op.create_index(
        "ix_external_notification_user_created",
        "external_notification_deliveries",
        ["user_id", "created_at"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_external_notification_user_created",
        table_name="external_notification_deliveries",
    )
    op.drop_index(
        "ix_external_notification_status_next_attempt",
        table_name="external_notification_deliveries",
    )
    op.drop_table("external_notification_deliveries")
