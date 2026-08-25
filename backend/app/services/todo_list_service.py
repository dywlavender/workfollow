from __future__ import annotations

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.todo import Todo, local_now
from app.models.todo_list import TodoList
from app.services import event_stream


DEFAULT_TODO_LIST_NAMES = ("收集箱", "工作", "个人", "学习")
FALLBACK_TODO_LIST_NAME = DEFAULT_TODO_LIST_NAMES[0]


def normalize_name(value: str) -> str:
    name = value.strip()
    if not name:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="清单名称不能为空")
    return name


def is_protected_name(name: str) -> bool:
    return name in DEFAULT_TODO_LIST_NAMES


def _next_sort_order(db: Session) -> int:
    current = db.scalar(select(TodoList.sort_order).order_by(TodoList.sort_order.desc()).limit(1))
    return int(current or len(DEFAULT_TODO_LIST_NAMES) - 1) + 1


def ensure_list(db: Session, name: str, created_by_id: str | None = None) -> TodoList | None:
    """Ensure custom names introduced by old task clients are catalogued."""

    normalized = normalize_name(name)
    if is_protected_name(normalized):
        return None
    existing = db.scalar(select(TodoList).where(TodoList.name == normalized))
    if existing is not None:
        return existing
    item = TodoList(name=normalized, sort_order=_next_sort_order(db), created_by_id=created_by_id)
    db.add(item)
    db.flush()
    return item


def list_catalog(db: Session) -> list[TodoList]:
    """Return protected defaults plus persisted custom names.

    The migration backfills historical task names. The fallback query keeps
    databases upgraded from an older build readable even if a legacy name was
    written by an old client during deployment.
    """

    rows = list(db.scalars(select(TodoList).order_by(TodoList.sort_order, TodoList.created_at, TodoList.name)))
    known = {item.name for item in rows}
    missing_defaults = set(DEFAULT_TODO_LIST_NAMES) - known
    for index, name in enumerate(DEFAULT_TODO_LIST_NAMES):
        if name in missing_defaults:
            db.add(TodoList(name=name, sort_order=index))
    legacy_names = set(db.scalars(select(Todo.list_name).distinct()).all())
    for name in sorted(legacy_names - known - set(DEFAULT_TODO_LIST_NAMES)):
        ensure_list(db, name)
    if missing_defaults or legacy_names - known - set(DEFAULT_TODO_LIST_NAMES):
        db.flush()
        rows = list(db.scalars(select(TodoList).order_by(TodoList.sort_order, TodoList.created_at, TodoList.name)))

    by_name = {item.name: item for item in rows}
    defaults = [
        by_name.get(name) or TodoList(name=name, sort_order=index)
        for index, name in enumerate(DEFAULT_TODO_LIST_NAMES)
    ]
    custom = [item for item in rows if item.name not in DEFAULT_TODO_LIST_NAMES]
    return [*defaults, *custom]


def get_or_404(db: Session, list_id: str) -> TodoList:
    item = db.get(TodoList, list_id)
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="清单不存在")
    return item


def create(db: Session, name: str, created_by_id: str) -> TodoList:
    normalized = normalize_name(name)
    if is_protected_name(normalized):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="该名称属于内置清单")
    if db.scalar(select(TodoList).where(TodoList.name == normalized)) is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="清单名称已存在")
    item = TodoList(name=normalized, sort_order=_next_sort_order(db), created_by_id=created_by_id)
    db.add(item)
    db.flush()
    event_stream.queue_todo_list_changed(db, action="CREATED", name=item.name)
    db.commit()
    db.refresh(item)
    return item


def rename(db: Session, list_id: str, name: str) -> tuple[TodoList, int]:
    item = get_or_404(db, list_id)
    if is_protected_name(item.name):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="内置清单不能重命名")
    normalized = normalize_name(name)
    if is_protected_name(normalized):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="不能使用内置清单名称")
    duplicate = db.scalar(select(TodoList).where(TodoList.name == normalized, TodoList.id != item.id))
    if duplicate is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="清单名称已存在")
    if normalized == item.name:
        return item, 0

    previous_name = item.name
    tasks = list(db.scalars(select(Todo).where(Todo.list_name == previous_name)).all())
    item.name = normalized
    for task in tasks:
        task.list_name = normalized
        task.updated_at = local_now()
    db.flush()
    for task in tasks:
        event_stream.queue_task_changed(db, task)
    event_stream.queue_todo_list_changed(
        db, action="RENAMED", name=normalized, previous_name=previous_name
    )
    db.commit()
    return item, len(tasks)


def delete(db: Session, list_id: str) -> int:
    item = get_or_404(db, list_id)
    if is_protected_name(item.name):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="内置清单不能删除")

    deleted_name = item.name
    tasks = list(db.scalars(select(Todo).where(Todo.list_name == deleted_name)).all())
    for task in tasks:
        task.list_name = FALLBACK_TODO_LIST_NAME
        task.updated_at = local_now()
    db.delete(item)
    db.flush()
    for task in tasks:
        event_stream.queue_task_changed(db, task)
    event_stream.queue_todo_list_changed(
        db,
        action="DELETED",
        name=FALLBACK_TODO_LIST_NAME,
        previous_name=deleted_name,
    )
    db.commit()
    return len(tasks)
