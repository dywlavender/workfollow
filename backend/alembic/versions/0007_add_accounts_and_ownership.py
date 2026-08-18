"""Add accounts, sessions, and ownership to personal resources.

Revision ID: 0007
Revises: 0006
Create Date: 2026-08-09
"""
from __future__ import annotations

import os
from datetime import datetime
from typing import Sequence
from uuid import uuid4

from alembic import op
import sqlalchemy as sa
from pwdlib import PasswordHash


revision: str = "0007"
down_revision: str | Sequence[str] | None = "0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _now() -> datetime:
    return datetime.now().replace(microsecond=0)


def _add_owner(table_name: str) -> None:
    op.add_column(table_name, sa.Column("owner_id", sa.String(length=36), nullable=True))
    bind = op.get_bind()
    owner_id = bind.execute(sa.text("SELECT id FROM users ORDER BY created_at LIMIT 1")).scalar_one()
    bind.execute(sa.text(f"UPDATE {table_name} SET owner_id = :owner_id"), {"owner_id": owner_id})
    with op.batch_alter_table(table_name, recreate="always") as batch_op:
        batch_op.alter_column(
            "owner_id",
            existing_type=sa.String(length=36),
            nullable=False,
        )
        batch_op.create_foreign_key(f"fk_{table_name}_owner_id", "users", ["owner_id"], ["id"])
    op.create_index(f"ix_{table_name}_owner_id", table_name, ["owner_id"])


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("username", sa.String(length=80), nullable=False),
        sa.Column("password_hash", sa.Text(), nullable=False),
        sa.Column("nickname", sa.String(length=120), nullable=False),
        sa.Column("avatar_url", sa.String(length=1000), nullable=True),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.Column("last_login_at", sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("username"),
    )
    op.create_table(
        "auth_sessions",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("user_id", sa.String(length=36), nullable=False),
        sa.Column("token_hash", sa.String(length=128), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("revoked_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token_hash"),
    )
    op.create_index("ix_auth_sessions_user_expires", "auth_sessions", ["user_id", "expires_at"])

    bind = op.get_bind()
    username = os.environ.get("WORKFOLLOW_BOOTSTRAP_USERNAME", "local").strip().lower() or "local"
    password = os.environ.get("WORKFOLLOW_BOOTSTRAP_PASSWORD", "local-only-change-me")
    user_id = str(uuid4())
    now = _now()
    bind.execute(
        sa.text(
            "INSERT INTO users "
            "(id, username, password_hash, nickname, avatar_url, status, created_at, updated_at, last_login_at) "
            "VALUES (:id, :username, :password_hash, :nickname, NULL, 'ACTIVE', :created_at, :updated_at, NULL)"
        ),
        {
            "id": user_id,
            "username": username,
            "password_hash": PasswordHash.recommended().hash(password),
            "nickname": "本地用户",
            "created_at": now,
            "updated_at": now,
        },
    )

    for table_name in ("todos", "folders", "notes", "attachments", "quick_links"):
        _add_owner(table_name)


def downgrade() -> None:
    for table_name in ("quick_links", "attachments", "notes", "folders", "todos"):
        op.drop_index(f"ix_{table_name}_owner_id", table_name=table_name)
        with op.batch_alter_table(table_name, recreate="always") as batch_op:
            batch_op.drop_constraint(f"fk_{table_name}_owner_id", type_="foreignkey")
            batch_op.drop_column("owner_id")
    op.drop_index("ix_auth_sessions_user_expires", table_name="auth_sessions")
    op.drop_table("auth_sessions")
    op.drop_table("users")
