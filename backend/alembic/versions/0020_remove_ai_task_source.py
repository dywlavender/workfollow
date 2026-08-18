"""Remove the legacy AI task source marker.

Revision ID: 0020
Revises: 0019
Create Date: 2026-08-09
"""
from typing import Sequence

from alembic import op


revision: str = "0020"
down_revision: str | Sequence[str] | None = "0019"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Preserve legacy tasks while removing the obsolete executable feature:
    # note-backed suggestions remain note tasks; all others become manual.
    op.execute(
        "UPDATE todos SET source_type = CASE "
        "WHEN source_note_id IS NOT NULL THEN 'NOTE' ELSE 'MANUAL' END "
        "WHERE source_type = 'AI'"
    )


def downgrade() -> None:
    # The former AI marker carried no durable provenance that can be inferred
    # after conversion, so downgrade intentionally keeps the preserved values.
    pass
