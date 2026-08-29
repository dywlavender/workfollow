from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import Field, field_validator, model_validator

from app.models.todo import (
    RecurrenceType,
    TodoAssignmentStatus,
    TodoPriority,
    TodoStatus,
)
from app.schemas.base import ApiModel
from app.schemas.todo import TodoCreate


class AgentNoteAppend(ApiModel):
    markdown: str = Field(min_length=1, max_length=5_000_000)
    expected_version: str = Field(min_length=1, max_length=500)


class AgentNoteReplace(AgentNoteAppend):
    title: str | None = Field(default=None, min_length=1, max_length=500)

    @field_validator("title")
    @classmethod
    def normalize_title(cls, value: str | None) -> str | None:
        return value.strip() if value is not None else None


class AgentTaskCreate(TodoCreate):
    pass


class AgentTaskSummary(ApiModel):
    """Compact task metadata for model-facing lists.

    Full bodies, member profiles and collaboration versions are deliberately
    reserved for the per-task read endpoint.
    """

    id: str
    title: str
    status: TodoStatus
    my_status: TodoAssignmentStatus | None = None
    priority: TodoPriority
    due_at: datetime | None = None
    due_end_at: datetime | None = None
    list_name: str
    tags: list[str]
    team_id: str | None = None
    updated_at: datetime


class AgentTaskBodyUpdate(ApiModel):
    markdown: str = Field(max_length=5_000_000)
    expected_version: str = Field(min_length=1, max_length=500)


class AgentTaskMetadataUpdate(ApiModel):
    expected_version: str = Field(min_length=1, max_length=500)
    title: str | None = Field(default=None, min_length=1, max_length=500)
    priority: TodoPriority | None = None
    due_at: datetime | None = None
    due_end_at: datetime | None = None
    reminder_at: datetime | None = None
    recurrence_type: RecurrenceType | None = None
    recurrence_config: dict[str, Any] | None = None
    tags: list[str] | None = Field(default=None, max_length=20)

    @model_validator(mode="after")
    def require_change(self) -> "AgentTaskMetadataUpdate":
        fields = self.model_fields_set - {"expected_version"}
        if not fields:
            raise ValueError("至少提供一个要更新的任务字段")
        if self.title is not None:
            self.title = self.title.strip()
        if self.tags is not None:
            self.tags = list(dict.fromkeys(tag.strip().lstrip("#") for tag in self.tags if tag.strip().lstrip("#")))
        return self
