from functools import lru_cache
from pathlib import Path

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


BACKEND_DIR = Path(__file__).resolve().parents[2]
PROJECT_DIR = BACKEND_DIR.parent


class Settings(BaseSettings):
    app_name: str = "WorkFollow API"
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
    notification_http_timeout_seconds: float = 5.0
    notification_http_retry_count: int = 3
    notification_worker_interval_seconds: float = 2.0
    notification_timezone: str = "Asia/Shanghai"
    notification_daily_digest_time: str = "08:30"

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
