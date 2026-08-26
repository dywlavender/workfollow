from functools import lru_cache
from pathlib import Path

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


BACKEND_DIR = Path(__file__).resolve().parents[2]
PROJECT_DIR = BACKEND_DIR.parent


class Settings(BaseSettings):
    app_name: str = "打勾 API"
    app_version: str = "0.1.0"
    database_url: str = f"sqlite:///{(PROJECT_DIR / 'data' / 'workfollow.db').as_posix()}"
    cors_origins: list[str] = ["http://localhost:5173", "http://127.0.0.1:5173"]
    uploads_dir: Path = PROJECT_DIR / "data" / "uploads"
    files_dir: Path = PROJECT_DIR / "data" / "files"
    max_upload_bytes: int = 25 * 1024 * 1024
    max_markdown_import_bytes: int = 5 * 1024 * 1024
    session_days: int = 30
    session_cookie_secure: bool = False
    notification_http_url: str = ""
    # The browser-facing WorkFollow address used in deep links.  It is a
    # server-level setting because links are also useful to future channels.
    server_url: str = ""
    # Kept for existing local configuration; server_url is the canonical name.
    notification_public_url: str = ""
    notification_http_timeout_seconds: float = 5.0
    notification_http_retry_count: int = 3
    notification_worker_interval_seconds: float = 2.0
    # Consecutive title/description autosaves are merged during this idle
    # window; explicit task actions continue to notify immediately.
    notification_task_edit_quiet_seconds: float = 3.0
    notification_timezone: str = "Asia/Shanghai"
    notification_daily_digest_time: str = "08:30"
    database_pool_size: int = 15
    database_max_overflow: int = 10
    database_pool_pre_ping: bool = True

    model_config = SettingsConfigDict(
        env_file=(PROJECT_DIR / ".env", BACKEND_DIR / ".env"),
        env_prefix="WORKFOLLOW_",
        extra="ignore",
    )

    @field_validator("cors_origins", mode="before")
    @classmethod
    def parse_cors_origins(cls, value: object) -> object:
        if isinstance(value, str) and not value.startswith("["):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        return value


@lru_cache
def get_settings() -> Settings:
    return Settings()
