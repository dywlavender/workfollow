"""Add system quick links and first-run onboarding state.

Revision ID: 0024
Revises: 0023
Create Date: 2026-08-11
"""

from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0024"
down_revision: str | Sequence[str] | None = "0023"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("onboarding_version", sa.Integer(), nullable=False, server_default="1"),
    )

    with op.batch_alter_table("quick_links") as batch_op:
        batch_op.add_column(
            sa.Column(
                "scope",
                sa.String(length=16),
                nullable=False,
                server_default="PERSONAL",
            )
        )
        batch_op.add_column(sa.Column("description", sa.Text(), nullable=True))
        batch_op.add_column(
            sa.Column(
                "created_by_id",
                sa.String(length=36),
                sa.ForeignKey("users.id", name="fk_quick_links_created_by_id_users", ondelete="SET NULL"),
                nullable=True,
            )
        )
        batch_op.add_column(
            sa.Column(
                "updated_by_id",
                sa.String(length=36),
                sa.ForeignKey("users.id", name="fk_quick_links_updated_by_id_users", ondelete="SET NULL"),
                nullable=True,
            )
        )

    op.create_index(
        "ix_quick_links_scope_group_sort",
        "quick_links",
        ["scope", "group_name", "sort_order", "created_at"],
    )

    bind = op.get_bind()
    bind.execute(
        sa.text(
            "UPDATE quick_links SET created_by_id = owner_id, updated_by_id = owner_id "
            "WHERE created_by_id IS NULL OR updated_by_id IS NULL"
        )
    )
    bind.execute(sa.text("UPDATE users SET onboarding_version = 1 WHERE onboarding_version IS NULL"))


def downgrade() -> None:
    op.drop_index("ix_quick_links_scope_group_sort", table_name="quick_links")
    with op.batch_alter_table("quick_links") as batch_op:
        batch_op.drop_column("updated_by_id")
        batch_op.drop_column("created_by_id")
        batch_op.drop_column("description")
        batch_op.drop_column("scope")
    op.drop_column("users", "onboarding_version")
