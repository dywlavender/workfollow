"""Remove user email data and constraints.

Revision ID: 0025
Revises: 0024
Create Date: 2026-08-17
"""
from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0025"
down_revision: str | Sequence[str] | None = "0024"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    columns = {column["name"] for column in inspector.get_columns("users")}
    if "email" not in columns:
        return
    with op.batch_alter_table("users", recreate="always") as batch_op:
        batch_op.drop_column("email")


def downgrade() -> None:
    # Removing identity data is intentionally irreversible.
    pass
