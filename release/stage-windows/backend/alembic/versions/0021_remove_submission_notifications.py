"""Remove manager notifications for new knowledge submissions.

Revision ID: 0021
Revises: 0020
Create Date: 2026-08-09
"""
from typing import Sequence

from alembic import op


revision: str = "0021"
down_revision: str | Sequence[str] | None = "0020"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute("DELETE FROM notifications WHERE type = 'TEAM_NOTE_SUBMITTED'")


def downgrade() -> None:
    # Deleted notification rows cannot be reconstructed safely.
    pass
