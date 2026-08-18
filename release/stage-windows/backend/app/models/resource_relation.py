from __future__ import annotations

from datetime import datetime
from enum import Enum

from sqlalchemy import DateTime, Enum as SqlEnum, ForeignKey, Index, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.todo import local_now, new_uuid


class ResourceType(str, Enum):
    PERSONAL_NOTE = "PERSONAL_NOTE"
    TEAM_NOTE = "TEAM_NOTE"
    TASK = "TASK"


class RelationType(str, Enum):
    CREATED_FROM = "CREATED_FROM"
    REFERENCES = "REFERENCES"


class ResourceRelation(Base):
    __tablename__ = "resource_relations"
    __table_args__ = (
        Index(
            "ix_resource_relations_source_active",
            "source_type",
            "source_id",
            "deleted_at",
        ),
        Index(
            "ix_resource_relations_target_active",
            "target_type",
            "target_id",
            "deleted_at",
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    source_type: Mapped[ResourceType] = mapped_column(
        SqlEnum(ResourceType, native_enum=False, length=24), nullable=False
    )
    source_id: Mapped[str] = mapped_column(String(36), nullable=False)
    source_block_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    target_type: Mapped[ResourceType] = mapped_column(
        SqlEnum(ResourceType, native_enum=False, length=24), nullable=False
    )
    target_id: Mapped[str] = mapped_column(String(36), nullable=False)
    relation_type: Mapped[RelationType] = mapped_column(
        SqlEnum(RelationType, native_enum=False, length=24), nullable=False
    )
    source_excerpt: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_by_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=local_now, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    created_by: Mapped["User | None"] = relationship()
