from collections.abc import Generator

from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import get_settings


settings = get_settings()
connect_args = {"check_same_thread": False} if settings.database_url.startswith("sqlite") else {}
engine_options: dict[str, object] = {
    "connect_args": connect_args,
    "pool_pre_ping": settings.database_pool_pre_ping,
}
# SQLite has one writer, but a file-backed SQLite deployment still benefits
# from separate reader connections under the LAN workload. In-memory SQLite
# uses a special pool that does not accept QueuePool sizing.
if ":memory:" not in settings.database_url:
    engine_options.update(
        pool_size=settings.database_pool_size,
        max_overflow=settings.database_max_overflow,
    )
engine = create_engine(settings.database_url, **engine_options)


if settings.database_url.startswith("sqlite"):
    @event.listens_for(engine, "connect")
    def _enable_sqlite_foreign_keys(dbapi_connection, _connection_record) -> None:  # noqa: ANN001
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        # WAL lets readers and the single writer proceed concurrently instead of
        # blocking every read during a write transaction — critical when several
        # people save notes at the same time on a single-node deploy.
        cursor.execute("PRAGMA journal_mode=WAL")
        # NORMAL is safe under WAL (no corruption) and skips the per-commit fsync.
        cursor.execute("PRAGMA synchronous=NORMAL")
        # Wait up to 5s for the write lock instead of failing instantly.
        cursor.execute("PRAGMA busy_timeout=5000")
        cursor.close()


SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def get_db() -> Generator[Session, None, None]:
    with SessionLocal() as session:
        yield session
