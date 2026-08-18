"""Add durable Note and Task resource relations.

Revision ID: 0022
Revises: 0021
Create Date: 2026-08-11
"""
from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0022"
down_revision: str | Sequence[str] | None = "0021"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "resource_relations",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("source_type", sa.String(length=24), nullable=False),
        sa.Column("source_id", sa.String(length=36), nullable=False),
        sa.Column("source_block_id", sa.String(length=64), nullable=True),
        sa.Column("target_type", sa.String(length=24), nullable=False),
        sa.Column("target_id", sa.String(length=36), nullable=False),
        sa.Column("relation_type", sa.String(length=24), nullable=False),
        sa.Column("source_excerpt", sa.Text(), nullable=True),
        sa.Column("created_by_id", sa.String(length=36), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("deleted_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["created_by_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_resource_relations_source_active",
        "resource_relations",
        ["source_type", "source_id", "deleted_at"],
    )
    op.create_index(
        "ix_resource_relations_target_active",
        "resource_relations",
        ["target_type", "target_id", "deleted_at"],
    )
    # Preserve the existing Note -> Task links as durable backlinks.
    op.execute(
        "INSERT INTO resource_relations "
        "(id, source_type, source_id, target_type, target_id, relation_type, source_excerpt, created_by_id, created_at) "
        "SELECT lower(hex(randomblob(16))), 'PERSONAL_NOTE', source_note_id, 'TASK', id, "
        "'CREATED_FROM', source_excerpt, creator_id, created_at FROM todos "
        "WHERE source_note_id IS NOT NULL"
    )


def downgrade() -> None:
    op.drop_index("ix_resource_relations_target_active", table_name="resource_relations")
    op.drop_index("ix_resource_relations_source_active", table_name="resource_relations")
    op.drop_table("resource_relations")
