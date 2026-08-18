"""Add persisted system roles and team creation permission.

Revision ID: 0023
Revises: 0022
Create Date: 2026-08-11
"""
from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0023"
down_revision: str | Sequence[str] | None = "0022"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("system_role", sa.String(length=16), nullable=False, server_default="NORMAL"),
    )
    op.add_column(
        "users",
        sa.Column("can_create_team", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    bind = op.get_bind()
    bind.execute(
        sa.text(
            "UPDATE users SET system_role = 'ROOT', can_create_team = :enabled "
            "WHERE lower(username) = 'root'"
        ),
        {"enabled": True},
    )


def downgrade() -> None:
    op.drop_column("users", "can_create_team")
    op.drop_column("users", "system_role")
