from datetime import datetime
from typing import Any

from pydantic import Field

from app.schemas.base import ApiModel


class FolderCreate(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    parent_id: str | None = None
    sort_order: int = 0


class FolderUpdate(ApiModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    parent_id: str | None = None
    sort_order: int | None = None


class FolderRead(ApiModel):
    id: str
    parent_id: str | None
    name: str
    sort_order: int
    created_at: datetime
    updated_at: datetime


class NoteCreate(ApiModel):
    folder_id: str | None = None
    title: str = Field(default="未命名笔记", min_length=1, max_length=500)
    content_json: dict[str, Any] = Field(default_factory=lambda: {"type": "doc", "content": [{"type": "paragraph"}]})
    plain_text: str = ""


class NoteUpdate(ApiModel):
    folder_id: str | None = None
    title: str | None = Field(default=None, min_length=1, max_length=500)
    content_json: dict[str, Any] | None = None
    plain_text: str | None = None
    is_favorite: bool | None = None


class NoteRead(ApiModel):
    id: str
    folder_id: str | None
    title: str
    content_json: dict[str, Any]
    plain_text: str
    is_favorite: bool
    copied_from_note_id: str | None
    copied_from_team_note_id: str | None
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None


class NoteTemplateRead(ApiModel):
    id: str
    name: str
    content_json: dict[str, Any]
    is_builtin: bool
    sort_order: int


class AttachmentRead(ApiModel):
    id: str
    note_id: str | None
    original_name: str
    storage_name: str
    mime_type: str
    size: int
    url: str = ""
    created_at: datetime
