from datetime import datetime
from typing import Literal

from pydantic import Field

from app.schemas.base import ApiModel


SearchScope = Literal["all", "personal", "shared", "knowledge"]


class SearchExcerptPart(ApiModel):
    text: str
    matched: bool = False


class SearchItem(ApiModel):
    source: Literal["personal", "shared", "knowledge"]
    id: str
    title: str
    excerpt: list[SearchExcerptPart] = Field(default_factory=list)
    folder_id: str | None = None
    team_id: str | None = None
    updated_at: datetime


class SearchResponse(ApiModel):
    query: str
    items: list[SearchItem]
    total: int
    has_more: bool
