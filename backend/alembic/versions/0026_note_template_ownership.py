"""Add ownership and lifecycle fields to note templates.

Revision ID: 0026
Revises: 0025
Create Date: 2026-08-18
"""

from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0026"
down_revision: str | Sequence[str] | None = "0025"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("note_templates", sa.Column("owner_id", sa.String(length=36), nullable=True))
    op.add_column("note_templates", sa.Column("description", sa.Text(), nullable=True))
    op.add_column("note_templates", sa.Column("created_at", sa.DateTime(), nullable=True))
    op.add_column("note_templates", sa.Column("updated_at", sa.DateTime(), nullable=True))
    op.add_column("note_templates", sa.Column("deleted_at", sa.DateTime(), nullable=True))

    bind = op.get_bind()
    bind.execute(sa.text("UPDATE note_templates SET owner_id = NULL WHERE is_builtin = TRUE"))
    bind.execute(
        sa.text(
            "UPDATE note_templates SET created_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP "
            "WHERE created_at IS NULL OR updated_at IS NULL"
        )
    )

    with op.batch_alter_table("note_templates", recreate="always") as batch_op:
        batch_op.alter_column(
            "created_at",
            existing_type=sa.DateTime(),
            nullable=False,
        )
        batch_op.alter_column(
            "updated_at",
            existing_type=sa.DateTime(),
            nullable=False,
        )
        batch_op.create_foreign_key(
            "fk_note_templates_owner_id_users",
            "users",
            ["owner_id"],
            ["id"],
            ondelete="CASCADE",
        )
        batch_op.create_check_constraint(
            "ck_note_templates_builtin_owner",
            "(is_builtin = TRUE AND owner_id IS NULL) OR "
            "(is_builtin = FALSE AND owner_id IS NOT NULL)",
        )

    op.create_index("ix_note_templates_owner_id", "note_templates", ["owner_id"])
    op.create_index(
        "ix_note_templates_owner_deleted_sort",
        "note_templates",
        ["owner_id", "deleted_at", "sort_order"],
    )
    op.create_index(
        "uq_note_templates_owner_name_active",
        "note_templates",
        ["owner_id", "name"],
        unique=True,
        sqlite_where=sa.text("deleted_at IS NULL"),
        postgresql_where=sa.text("deleted_at IS NULL"),
    )


def downgrade() -> None:
    op.drop_index("uq_note_templates_owner_name_active", table_name="note_templates")
    op.drop_index("ix_note_templates_owner_deleted_sort", table_name="note_templates")
    op.drop_index("ix_note_templates_owner_id", table_name="note_templates")
    with op.batch_alter_table("note_templates", recreate="always") as batch_op:
        batch_op.drop_constraint("ck_note_templates_builtin_owner", type_="check")
        batch_op.drop_constraint("fk_note_templates_owner_id_users", type_="foreignkey")
        batch_op.drop_column("deleted_at")
        batch_op.drop_column("updated_at")
        batch_op.drop_column("created_at")
        batch_op.drop_column("description")
        batch_op.drop_column("owner_id")
