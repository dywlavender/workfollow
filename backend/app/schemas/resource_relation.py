from datetime import datetime

from pydantic import Field, model_validator

from app.models.resource_relation import RelationType, ResourceType
from app.models.todo import TodoPriority, TodoStatus
from app.schemas.auth import UserRead
from app.schemas.base import ApiModel


class TaskSourceCreate(ApiModel):
    resource_type: ResourceType
    resource_id: str = Field(min_length=1, max_length=36)
    block_id: str | None = Field(default=None, max_length=64)
    excerpt: str | None = Field(default=None, max_length=2000)

    @model_validator(mode="after")
    def require_note_source(self) -> "TaskSourceCreate":
        if self.resource_type not in (ResourceType.PERSONAL_NOTE, ResourceType.TEAM_NOTE):
            raise ValueError("任务来源必须是个人笔记或团队知识")
        if self.excerpt is not None:
            self.excerpt = self.excerpt.strip() or None
        return self


class ResourceRelationCreate(ApiModel):
    source_type: ResourceType
    source_id: str = Field(min_length=1, max_length=36)
    source_block_id: str | None = Field(default=None, max_length=64)
    target_type: ResourceType
    target_id: str = Field(min_length=1, max_length=36)
    relation_type: RelationType = RelationType.REFERENCES
    source_excerpt: str | None = Field(default=None, max_length=2000)


class ResourceRelationRead(ApiModel):
    id: str
    source_type: ResourceType
    source_id: str
    source_block_id: str | None
    target_type: ResourceType
    target_id: str
    relation_type: RelationType
    source_excerpt: str | None
    created_by_id: str | None
    created_at: datetime


class TaskSourceRead(ApiModel):
    relation_id: str
    resource_type: ResourceType
    resource_id: str | None = None
    block_id: str | None = None
    title: str | None = None
    excerpt: str | None = None
    accessible: bool


class TaskBriefPermissions(ApiModel):
    completable: bool = False


class TaskBriefRead(ApiModel):
    id: str
    accessible: bool
    deleted: bool = False
    title: str | None = None
    status: TodoStatus | None = None
    priority: TodoPriority | None = None
    due_at: datetime | None = None
    assignees: list[UserRead] = Field(default_factory=list)
    permissions: TaskBriefPermissions = Field(default_factory=TaskBriefPermissions)
