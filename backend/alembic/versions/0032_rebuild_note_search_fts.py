"""Repair the derived SQLite FTS5 index after the collaboration rollout."""

from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0032"
down_revision: str | Sequence[str] | None = "0031"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "sqlite":
        return
    try:
        has_fts = bind.scalar(
            sa.text("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'note_search' LIMIT 1")
        )
    except Exception:
        # A damaged optional index must never prevent the relational schema
        # from migrating. The application will use its LIKE fallback and can
        # attempt a repair once the database is available again.
        return
    if has_fts:
        # ``note_search`` is an external-content index; the relational
        # ``search_documents`` table remains authoritative.
        try:
            # Keep Alembic's outer transaction intact if the derived FTS
            # segment pages are malformed. A savepoint lets us remove only
            # the optional index and continue with normal writes.
            with bind.begin_nested():
                bind.exec_driver_sql("INSERT INTO note_search(note_search) VALUES ('rebuild')")
        except Exception:
            try:
                for trigger in ("search_documents_au", "search_documents_ad", "search_documents_ai"):
                    bind.exec_driver_sql(f"DROP TRIGGER IF EXISTS {trigger}")
                bind.exec_driver_sql("DROP TABLE IF EXISTS note_search")
            except Exception:
                # If the underlying SQLite file is damaged beyond the FTS
                # table, leave it for the runtime repair/backup path instead
                # of masking the original migration result.
                return


def downgrade() -> None:
    # Rebuilding a derived index has no schema change to reverse.
    return
