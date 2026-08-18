from datetime import datetime
from urllib.parse import urlsplit

from pydantic import Field, field_validator

from app.models.quick_link import QuickLinkScope
from app.schemas.base import ApiModel


def validate_external_url(value: str) -> str:
    stripped = value.strip()
    parsed = urlsplit(stripped)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError("网址必须是有效的 http:// 或 https:// 地址")
    return stripped


class QuickLinkCreate(ApiModel):
    name: str = Field(min_length=1, max_length=120)
    url: str = Field(min_length=1, max_length=2048)
    icon: str | None = Field(default=None, max_length=32)
    group_name: str | None = Field(default=None, max_length=120)
    description: str | None = Field(default=None, max_length=500)
    sort_order: int = 0

    @field_validator("name", "url")
    @classmethod
    def strip_required(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("字段不能为空")
        return stripped

    @field_validator("url")
    @classmethod
    def validate_url(cls, value: str) -> str:
        return validate_external_url(value)

    @field_validator("icon", "group_name", "description")
    @classmethod
    def strip_optional(cls, value: str | None) -> str | None:
        return value.strip() or None if value is not None else None


class QuickLinkUpdate(ApiModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    url: str | None = Field(default=None, min_length=1, max_length=2048)
    icon: str | None = Field(default=None, max_length=32)
    group_name: str | None = Field(default=None, max_length=120)
    description: str | None = Field(default=None, max_length=500)
    sort_order: int | None = None

    @field_validator("name")
    @classmethod
    def strip_name(cls, value: str | None) -> str | None:
        return value.strip() if value is not None else None

    @field_validator("url")
    @classmethod
    def validate_url(cls, value: str | None) -> str | None:
        return validate_external_url(value) if value is not None else None

    @field_validator("icon", "group_name", "description")
    @classmethod
    def strip_optional(cls, value: str | None) -> str | None:
        return value.strip() or None if value is not None else None


class QuickLinkRead(ApiModel):
    id: str
    scope: QuickLinkScope
    name: str
    url: str
    icon: str
    group_name: str | None
    description: str | None
    sort_order: int
    created_by_id: str | None
    updated_by_id: str | None
    created_at: datetime
    updated_at: datetime


class QuickLinkReorderItem(ApiModel):
    id: str
    sort_order: int


class QuickLinkReorder(ApiModel):
    items: list[QuickLinkReorderItem] = Field(default_factory=list)
    ids: list[str] | None = None
