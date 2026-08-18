from datetime import datetime
from enum import Enum

from sqlalchemy import Enum as SqlEnum, ForeignKey, Index, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.todo import local_now, new_uuid


class QuickLinkScope(str, Enum):
    PERSONAL = "PERSONAL"
    SYSTEM = "SYSTEM"


class QuickLink(Base):
    __tablename__ = "quick_links"
    __table_args__ = (
        Index("ix_quick_links_sort_order", "sort_order", "created_at"),
        Index("ix_quick_links_scope_group_sort", "scope", "group_name", "sort_order", "created_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    owner_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    scope: Mapped[QuickLinkScope] = mapped_column(
        SqlEnum(QuickLinkScope, native_enum=False, length=16), default=QuickLinkScope.PERSONAL, nullable=False
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    url: Mapped[str] = mapped_column(String(2048), nullable=False)
    icon: Mapped[str] = mapped_column(String(32), nullable=False)
    group_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_by_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    updated_by_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(default=local_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(default=local_now, onupdate=local_now, nullable=False)

    owner: Mapped["User"] = relationship(back_populates="quick_links", foreign_keys=[owner_id])
    created_by: Mapped["User | None"] = relationship(foreign_keys=[created_by_id])
    updated_by: Mapped["User | None"] = relationship(foreign_keys=[updated_by_id])
