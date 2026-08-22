"""Add personal note tags and the unified note search index.

The relational search document table is portable. SQLite deployments with FTS5
get the trigram virtual table and its synchronisation triggers; other SQLite
builds keep the table available for the LIKE fallback.
"""

import json
from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0029"
down_revision: str | Sequence[str] | None = "0028"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _plain_text(document: object) -> str:
    """Small migration-local TipTap text extractor.

    Historical migrations must not import the live service module: future
    application changes must not make an old migration un-runnable.
    """

    if isinstance(document, str):
        try:
            document = json.loads(document)
        except json.JSONDecodeError:
            return ""
    chunks: list[str] = []

    def visit(node: object) -> None:
        if not isinstance(node, dict):
            return
        if node.get("type") == "text" and isinstance(node.get("text"), str):
            chunks.append(node["text"])
        if node.get("type") == "hardBreak":
            chunks.append("\n")
        children = node.get("content")
        if isinstance(children, list):
            for child in children:
                visit(child)
        if node.get("type") in {"paragraph", "heading", "blockquote", "codeBlock", "listItem", "taskItem"}:
            chunks.append("\n")

    visit(document)
    return "\n".join(line.strip() for line in "".join(chunks).splitlines() if line.strip()).strip()


def _tags_text(value: object) -> str:
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except json.JSONDecodeError:
            return ""
    if not isinstance(value, list):
        return ""
    return " ".join(str(item).strip() for item in value if isinstance(item, str) and item.strip())


def _create_fts(bind: sa.Connection) -> bool:
    if bind.dialect.name != "sqlite":
        return False
    try:
        bind.exec_driver_sql(
            "CREATE VIRTUAL TABLE note_search USING fts5("
            "title, body, tags_text, category_name, "
            "content='search_documents', content_rowid='id', tokenize='trigram'"
            ")"
        )
    except Exception:
        # The normal table remains usable by the search service's LIKE
        # fallback on SQLite builds compiled without FTS5.
        return False
    bind.exec_driver_sql(
        "CREATE TRIGGER search_documents_ai AFTER INSERT ON search_documents BEGIN "
        "INSERT INTO note_search(rowid, title, body, tags_text, category_name) "
        "VALUES (new.id, new.title, new.body, new.tags_text, new.category_name); END"
    )
    bind.exec_driver_sql(
        "CREATE TRIGGER search_documents_ad AFTER DELETE ON search_documents BEGIN "
        "INSERT INTO note_search(note_search, rowid, title, body, tags_text, category_name) "
        "VALUES ('delete', old.id, old.title, old.body, old.tags_text, old.category_name); END"
    )
    bind.exec_driver_sql(
        "CREATE TRIGGER search_documents_au AFTER UPDATE OF title, body, tags_text, category_name "
        "ON search_documents BEGIN "
        "INSERT INTO note_search(note_search, rowid, title, body, tags_text, category_name) "
        "VALUES ('delete', old.id, old.title, old.body, old.tags_text, old.category_name); "
        "INSERT INTO note_search(rowid, title, body, tags_text, category_name) "
        "VALUES (new.id, new.title, new.body, new.tags_text, new.category_name); END"
    )
    bind.exec_driver_sql("INSERT INTO note_search(note_search) VALUES ('rebuild')")
    return True


def upgrade() -> None:
    with op.batch_alter_table("notes") as batch:
        batch.add_column(sa.Column("tags", sa.JSON(), nullable=False, server_default="[]"))

    op.create_table(
        "search_documents",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("source_type", sa.String(length=16), nullable=False),
        sa.Column("source_id", sa.String(length=36), nullable=False),
        sa.Column("owner_id", sa.String(length=36), nullable=True),
        sa.Column("team_id", sa.String(length=36), nullable=True),
        sa.Column("title", sa.String(length=500), nullable=False, server_default=""),
        sa.Column("body", sa.Text(), nullable=False, server_default=""),
        sa.Column("tags_text", sa.Text(), nullable=False, server_default=""),
        sa.Column("category_name", sa.String(length=120), nullable=False, server_default=""),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("source_type", "source_id", name="uq_search_documents_source"),
    )
    op.create_index("ix_search_documents_owner", "search_documents", ["owner_id"])
    op.create_index("ix_search_documents_team", "search_documents", ["team_id"])

    bind = op.get_bind()
    # Repair legacy rows before copying them into the search projection.
    note_rows = bind.execute(sa.text("SELECT id, content_json FROM notes WHERE COALESCE(plain_text, '') = ''")).all()
    for note_id, content_json in note_rows:
        bind.execute(
            sa.text("UPDATE notes SET plain_text = :plain_text WHERE id = :id"),
            {"id": note_id, "plain_text": _plain_text(content_json)},
        )

    note_rows = bind.execute(
        sa.text("SELECT id, owner_id, title, plain_text, tags FROM notes WHERE deleted_at IS NULL")
    ).mappings().all()
    for row in note_rows:
        bind.execute(
            sa.text(
                "INSERT INTO search_documents "
                "(source_type, source_id, owner_id, team_id, title, body, tags_text, category_name) "
                "VALUES ('PERSONAL', :source_id, :owner_id, NULL, :title, :body, :tags_text, '')"
            ),
            {
                "source_id": row["id"],
                "owner_id": row["owner_id"],
                "title": row["title"] or "",
                "body": row["plain_text"] or "",
                "tags_text": _tags_text(row["tags"]),
            },
        )

    team_rows = bind.execute(
        sa.text(
            "SELECT tn.id, tn.team_id, tn.title, tn.plain_text, tn.tags, "
            "COALESCE(tnc.name, '') AS category_name "
            "FROM team_notes tn LEFT JOIN team_note_categories tnc ON tnc.id = tn.category_id"
        )
    ).mappings().all()
    for row in team_rows:
        bind.execute(
            sa.text(
                "INSERT INTO search_documents "
                "(source_type, source_id, owner_id, team_id, title, body, tags_text, category_name) "
                "VALUES ('TEAM', :source_id, NULL, :team_id, :title, :body, :tags_text, :category_name)"
            ),
            {
                "source_id": row["id"],
                "team_id": row["team_id"],
                "title": row["title"] or "",
                "body": row["plain_text"] or "",
                "tags_text": _tags_text(row["tags"]),
                "category_name": row["category_name"] or "",
            },
        )

    _create_fts(bind)


def downgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name == "sqlite":
        for trigger in ("search_documents_au", "search_documents_ad", "search_documents_ai"):
            bind.exec_driver_sql(f"DROP TRIGGER IF EXISTS {trigger}")
        bind.exec_driver_sql("DROP TABLE IF EXISTS note_search")
    op.drop_index("ix_search_documents_team", table_name="search_documents")
    op.drop_index("ix_search_documents_owner", table_name="search_documents")
    op.drop_table("search_documents")
    with op.batch_alter_table("notes") as batch:
        batch.drop_column("tags")
