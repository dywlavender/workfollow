"""Add the complete note collaboration and knowledge lifecycle.

Revision ID: 0019
Revises: 0018
Create Date: 2026-08-09
"""
from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0019"
down_revision: str | Sequence[str] | None = "0018"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "team_note_categories",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("team_id", sa.String(length=36), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["team_id"], ["teams.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("team_id", "name", name="uq_team_note_categories_team_name"),
    )
    op.create_index("ix_team_note_categories_team_sort", "team_note_categories", ["team_id", "sort_order"])

    with op.batch_alter_table("notes") as batch:
        batch.add_column(sa.Column("is_favorite", sa.Boolean(), nullable=False, server_default=sa.false()))
        batch.add_column(sa.Column("copied_from_note_id", sa.String(length=36), nullable=True))
        batch.add_column(sa.Column("copied_from_team_note_id", sa.String(length=36), nullable=True))

    with op.batch_alter_table("note_shares") as batch:
        batch.add_column(sa.Column("team_id", sa.String(length=36), nullable=True))
        batch.create_foreign_key("fk_note_shares_team_id", "teams", ["team_id"], ["id"], ondelete="CASCADE")
    op.execute(
        "UPDATE note_shares SET team_id = ("
        "SELECT owner_member.team_id FROM team_members owner_member "
        "JOIN team_members target_member ON target_member.team_id = owner_member.team_id "
        "WHERE owner_member.user_id = note_shares.shared_by_user_id "
        "AND target_member.user_id = note_shares.shared_with_user_id "
        "AND owner_member.status = 'ACTIVE' AND target_member.status = 'ACTIVE' LIMIT 1)"
    )
    op.execute("UPDATE note_shares SET status = 'REVOKED', revoked_at = CURRENT_TIMESTAMP WHERE team_id IS NULL")

    with op.batch_alter_table("team_notes") as batch:
        batch.add_column(sa.Column("category_id", sa.String(length=36), nullable=True))
        batch.add_column(sa.Column("tags", sa.JSON(), nullable=False, server_default="[]"))
        batch.add_column(sa.Column("source_type", sa.String(length=24), nullable=False, server_default="ADMIN_CREATED"))
        batch.add_column(sa.Column("source_note_id", sa.String(length=36), nullable=True))
        batch.add_column(sa.Column("source_author_id", sa.String(length=36), nullable=True))
        batch.add_column(sa.Column("status", sa.String(length=16), nullable=False, server_default="PUBLISHED"))
        batch.add_column(sa.Column("published_at", sa.DateTime(), nullable=True))
        batch.add_column(sa.Column("archived_at", sa.DateTime(), nullable=True))
        batch.create_foreign_key("fk_team_notes_category", "team_note_categories", ["category_id"], ["id"], ondelete="SET NULL")
        batch.create_foreign_key("fk_team_notes_source_author", "users", ["source_author_id"], ["id"], ondelete="SET NULL")
        batch.create_index("ix_team_notes_category", ["category_id"])
    op.execute("UPDATE team_notes SET published_at = created_at")
    op.execute(
        "UPDATE team_notes SET source_type = 'MEMBER_SUBMISSION', "
        "source_note_id = (SELECT source_note_id FROM team_note_submissions s WHERE s.id = team_notes.source_submission_id), "
        "source_author_id = (SELECT applicant_id FROM team_note_submissions s WHERE s.id = team_notes.source_submission_id) "
        "WHERE source_submission_id IS NOT NULL"
    )
    op.execute("UPDATE team_notes SET source_author_id = created_by_id WHERE source_author_id IS NULL")
    with op.batch_alter_table("team_notes") as batch:
        batch.alter_column("published_at", existing_type=sa.DateTime(), nullable=False)

    with op.batch_alter_table("team_note_submissions") as batch:
        batch.add_column(sa.Column("submission_type", sa.String(length=16), nullable=False, server_default="CREATE"))
        batch.add_column(sa.Column("source_author_id", sa.String(length=36), nullable=True))
        batch.add_column(sa.Column("target_team_note_id", sa.String(length=36), nullable=True))
        batch.add_column(sa.Column("snapshot_hash", sa.String(length=64), nullable=False, server_default=""))
        batch.add_column(sa.Column("proposed_category_id", sa.String(length=36), nullable=True))
        batch.add_column(sa.Column("proposed_tags_json", sa.JSON(), nullable=False, server_default="[]"))
        batch.add_column(sa.Column("submission_message", sa.Text(), nullable=True))
        batch.add_column(sa.Column("review_reason_code", sa.String(length=64), nullable=True))
        batch.add_column(sa.Column("review_comment", sa.Text(), nullable=True))
        batch.add_column(sa.Column("revision_no", sa.Integer(), nullable=False, server_default="1"))
        batch.create_foreign_key("fk_submissions_source_author", "users", ["source_author_id"], ["id"])
        batch.create_foreign_key("fk_submissions_target_note", "team_notes", ["target_team_note_id"], ["id"], ondelete="SET NULL")
        batch.create_foreign_key("fk_submissions_category", "team_note_categories", ["proposed_category_id"], ["id"], ondelete="SET NULL")
    op.execute("UPDATE team_note_submissions SET source_author_id = applicant_id, review_comment = review_reason")
    with op.batch_alter_table("team_note_submissions") as batch:
        batch.alter_column("source_author_id", existing_type=sa.String(length=36), nullable=False)

    op.create_table(
        "team_note_versions",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("team_note_id", sa.String(length=36), nullable=False),
        sa.Column("version_no", sa.Integer(), nullable=False),
        sa.Column("title", sa.String(length=500), nullable=False),
        sa.Column("content_json", sa.JSON(), nullable=False),
        sa.Column("plain_text", sa.Text(), nullable=False),
        sa.Column("attachment_ids", sa.JSON(), nullable=False),
        sa.Column("category_id", sa.String(length=36), nullable=True),
        sa.Column("tags", sa.JSON(), nullable=False),
        sa.Column("change_type", sa.String(length=32), nullable=False),
        sa.Column("changed_by_id", sa.String(length=36), nullable=True),
        sa.Column("source_submission_id", sa.String(length=36), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["team_note_id"], ["team_notes.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["changed_by_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("team_note_id", "version_no", name="uq_team_note_versions_note_version"),
        sa.UniqueConstraint("source_submission_id", name="uq_team_note_versions_submission"),
    )
    op.create_index("ix_team_note_versions_note_created", "team_note_versions", ["team_note_id", "created_at"])
    op.execute(
        "INSERT INTO team_note_versions "
        "(id, team_note_id, version_no, title, content_json, plain_text, attachment_ids, category_id, tags, change_type, changed_by_id, source_submission_id, created_at) "
        "SELECT lower(hex(randomblob(16))), id, 1, title, content_json, plain_text, attachment_ids, category_id, tags, "
        "CASE WHEN source_submission_id IS NULL THEN 'ADMIN_CREATE' ELSE 'SUBMISSION_CREATE' END, "
        "created_by_id, source_submission_id, created_at FROM team_notes"
    )

    op.create_table(
        "submission_file_access",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("submission_id", sa.String(length=36), nullable=False),
        sa.Column("attachment_id", sa.String(length=36), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["submission_id"], ["team_note_submissions.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["attachment_id"], ["attachments.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("submission_id", "attachment_id", name="uq_submission_file_access_submission_attachment"),
    )
    op.create_index("ix_submission_file_access_attachment", "submission_file_access", ["attachment_id"])
    op.execute(
        "INSERT OR IGNORE INTO submission_file_access (id, submission_id, attachment_id, created_at) "
        "SELECT lower(hex(randomblob(16))), s.id, a.id, s.created_at "
        "FROM team_note_submissions s JOIN attachments a ON a.note_id = s.source_note_id "
        "JOIN json_each(s.snapshot_attachment_ids) j ON j.value = a.id"
    )


def downgrade() -> None:
    op.drop_index("ix_submission_file_access_attachment", table_name="submission_file_access")
    op.drop_table("submission_file_access")
    op.drop_index("ix_team_note_versions_note_created", table_name="team_note_versions")
    op.drop_table("team_note_versions")
    with op.batch_alter_table("team_note_submissions") as batch:
        batch.drop_constraint("fk_submissions_category", type_="foreignkey")
        batch.drop_constraint("fk_submissions_target_note", type_="foreignkey")
        batch.drop_constraint("fk_submissions_source_author", type_="foreignkey")
        for column in (
            "revision_no", "review_comment", "review_reason_code", "submission_message", "proposed_tags_json",
            "proposed_category_id", "snapshot_hash", "target_team_note_id", "source_author_id", "submission_type",
        ):
            batch.drop_column(column)
    with op.batch_alter_table("team_notes") as batch:
        batch.drop_index("ix_team_notes_category")
        batch.drop_constraint("fk_team_notes_source_author", type_="foreignkey")
        batch.drop_constraint("fk_team_notes_category", type_="foreignkey")
        for column in (
            "archived_at", "published_at", "status", "source_author_id", "source_note_id", "source_type", "tags", "category_id",
        ):
            batch.drop_column(column)
    with op.batch_alter_table("note_shares") as batch:
        batch.drop_constraint("fk_note_shares_team_id", type_="foreignkey")
        batch.drop_column("team_id")
    with op.batch_alter_table("notes") as batch:
        batch.drop_column("copied_from_team_note_id")
        batch.drop_column("copied_from_note_id")
        batch.drop_column("is_favorite")
    op.drop_index("ix_team_note_categories_team_sort", table_name="team_note_categories")
    op.drop_table("team_note_categories")
