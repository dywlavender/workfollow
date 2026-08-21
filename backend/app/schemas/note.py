from datetime import datetime
from typing import Any

from pydantic import Field, field_validator

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
    is_knowledge_update_draft: bool = False
    copied_from_team_note_version_no: int | None = None
    copied_from_team_note_snapshot_hash: str | None = None
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None


class NoteTemplateRead(ApiModel):
    id: str
    name: str
    content_json: dict[str, Any]
    is_builtin: bool
    sort_order: int
    owner_id: str | None
    description: str | None
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None


def _validate_template_document(value: dict[str, Any]) -> dict[str, Any]:
    if value.get("type") != "doc" or not isinstance(value.get("content"), list):
        raise ValueError("模板正文必须是有效的编辑器文档")
    return value


class NoteTemplateCreate(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=2000)
    content_json: dict[str, Any] = Field(default_factory=lambda: {"type": "doc", "content": [{"type": "paragraph"}]})
    sort_order: int = 100

    @field_validator("name")
    @classmethod
    def validate_name(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("模板名称不能为空")
        return value

    @field_validator("description")
    @classmethod
    def normalize_description(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        return value or None

    @field_validator("content_json")
    @classmethod
    def validate_content_json(cls, value: dict[str, Any]) -> dict[str, Any]:
        return _validate_template_document(value)


class NoteTemplateUpdate(ApiModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=2000)
    content_json: dict[str, Any] | None = None
    sort_order: int | None = None

    @field_validator("name")
    @classmethod
    def validate_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        if not value:
            raise ValueError("模板名称不能为空")
        return value

    @field_validator("description")
    @classmethod
    def normalize_description(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        return value or None

    @field_validator("content_json", mode="before")
    @classmethod
    def validate_content_json(cls, value: object) -> dict[str, Any]:
        if value is None:
            raise ValueError("模板正文不能为空")
        if not isinstance(value, dict):
            raise ValueError("模板正文必须是有效的编辑器文档")
        return _validate_template_document(value)


class NoteTemplateFromNoteCreate(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=2000)

    @field_validator("name")
    @classmethod
    def validate_name(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("模板名称不能为空")
        return value

    @field_validator("description")
    @classmethod
    def normalize_description(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        return value or None


class AttachmentRead(ApiModel):
    id: str
    note_id: str | None
    original_name: str
    storage_name: str
    mime_type: str
    size: int
    url: str = ""
    created_at: datetime
