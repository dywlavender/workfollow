"""Single-process event fan-out for the same-origin SSE endpoint.

Events are attached to the SQLAlchemy session and published from
``after_commit`` so clients never observe a state change that later rolls
back. The current deployment is one Uvicorn process; ``Last-Event-ID`` replay
covers short reconnects and the frontend performs targeted reconciliation when
it reconnects.
"""

from __future__ import annotations

import asyncio
import json
import threading
from collections import deque
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from sqlalchemy import event, func, select
from sqlalchemy.orm import Session

from app.models.note import Note
from app.models.note_share import NoteShare, NoteShareStatus
from app.models.notification import Notification
from app.models.resource_relation import ResourceRelation, ResourceType
from app.models.team import TeamMember, TeamMemberStatus
from app.models.team_note import TeamNote
from app.models.auth import User, UserStatus
from app.models.todo import Todo


@dataclass(frozen=True)
class StreamEvent:
    event_id: int
    name: str
    data: dict[str, Any]
    audience: frozenset[str]


@dataclass(eq=False)
class Subscriber:
    user_id: str
    loop: asyncio.AbstractEventLoop
    queue: asyncio.Queue[StreamEvent]

    def offer(self, item: StreamEvent) -> None:
        if self.queue.full():
            try:
                self.queue.get_nowait()
            except asyncio.QueueEmpty:
                pass
        self.queue.put_nowait(item)


class EventHub:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._next_id = 0
        self._history: deque[StreamEvent] = deque(maxlen=512)
        self._subscribers: dict[str, set[Subscriber]] = {}

    def subscribe(self, user_id: str, last_event_id: int | None) -> tuple[Subscriber, list[StreamEvent]]:
        loop = asyncio.get_running_loop()
        subscriber = Subscriber(user_id, loop, asyncio.Queue(maxsize=128))
        with self._lock:
            replay = [
                item for item in self._history
                if (last_event_id is None or item.event_id > last_event_id)
                and user_id in item.audience
            ]
            self._subscribers.setdefault(user_id, set()).add(subscriber)
        return subscriber, replay

    def unsubscribe(self, subscriber: Subscriber) -> None:
        with self._lock:
            subscribers = self._subscribers.get(subscriber.user_id)
            if not subscribers:
                return
            subscribers.discard(subscriber)
            if not subscribers:
                self._subscribers.pop(subscriber.user_id, None)

    def publish(self, audience: set[str] | frozenset[str], name: str, data: dict[str, Any]) -> None:
        if not audience:
            return
        with self._lock:
            self._next_id += 1
            item = StreamEvent(self._next_id, name, data, frozenset(audience))
            self._history.append(item)
            subscribers = [
                subscriber
                for user_id in audience
                for subscriber in self._subscribers.get(user_id, ())
            ]
        for subscriber in subscribers:
            subscriber.loop.call_soon_threadsafe(subscriber.offer, item)


hub = EventHub()
PENDING_EVENTS_KEY = "workfollow_pending_stream_events"
PENDING_TEAM_NOTES_KEY = "workfollow_pending_team_note_events"
PENDING_NOTES_KEY = "workfollow_pending_note_events"


def _queue(db: Session, audience: set[str] | frozenset[str], name: str, data: dict[str, Any]) -> None:
    if not audience:
        return
    pending = db.info.setdefault(PENDING_EVENTS_KEY, [])
    pending.append((set(audience), name, data))


def queue_notification_counts(db: Session, user_ids: set[str] | list[str]) -> None:
    for user_id in set(user_ids):
        count = int(db.scalar(
            select(func.count(Notification.id)).where(
                Notification.user_id == user_id,
                Notification.read_at.is_(None),
            )
        ) or 0)
        _queue(db, {user_id}, "notification.count", {"count": count})


def _active_team_members(db: Session, team_id: str) -> set[str]:
    return set(db.scalars(select(TeamMember.user_id).where(
        TeamMember.team_id == team_id,
        TeamMember.status == TeamMemberStatus.ACTIVE,
    )).all())


def task_viewer_ids(db: Session, todo: Todo) -> set[str]:
    """Return users who can see a task or a note that references it."""

    audience = {todo.creator_id}
    audience.update(item.user_id for item in todo.assignments if item.active)
    if todo.team_id:
        audience.update(_active_team_members(db, todo.team_id))

    relations = db.scalars(select(ResourceRelation).where(
        ResourceRelation.target_type == ResourceType.TASK,
        ResourceRelation.target_id == todo.id,
        ResourceRelation.deleted_at.is_(None),
    )).all()
    for relation in relations:
        if relation.source_type == ResourceType.PERSONAL_NOTE:
            note = db.get(Note, relation.source_id)
            if note is None or note.deleted_at is not None:
                continue
            audience.add(note.owner_id)
            audience.update(db.scalars(select(NoteShare.shared_with_user_id).where(
                NoteShare.note_id == note.id,
                NoteShare.status == NoteShareStatus.ACTIVE,
            )).all())
        elif relation.source_type == ResourceType.TEAM_NOTE:
            team_id = db.scalar(select(TeamNote.team_id).where(TeamNote.id == relation.source_id))
            if team_id:
                audience.update(_active_team_members(db, team_id))
    return audience


def queue_task_changed(db: Session, todo: Todo, *, deleted: bool = False) -> None:
    assignments = [item.user_id for item in todo.assignments if item.active]
    payload = {
        "taskId": todo.id,
        "brief": {
            "title": todo.title,
            "status": todo.status.value,
            "priority": todo.priority.value,
            "dueAt": todo.due_at.isoformat() if todo.due_at else None,
            "dueEndAt": todo.due_end_at.isoformat() if todo.due_end_at else None,
            "assigneeIds": assignments,
            "updatedAt": todo.updated_at.isoformat() if todo.updated_at else None,
            "deleted": deleted,
        },
    }
    _queue(db, task_viewer_ids(db, todo), "task.changed", payload)


def note_viewer_ids(db: Session, note: Note) -> set[str]:
    audience = {note.owner_id}
    audience.update(db.scalars(select(NoteShare.shared_with_user_id).where(
        NoteShare.note_id == note.id,
        NoteShare.status == NoteShareStatus.ACTIVE,
    )).all())
    return audience


def queue_note_changed(db: Session, note: Note, *, deleted: bool = False) -> None:
    updated_at = note.updated_at.isoformat() if isinstance(note.updated_at, datetime) else None
    _queue(db, note_viewer_ids(db, note), "note.changed", {
        "noteId": note.id,
        "title": note.title,
        "folderId": note.folder_id,
        "isFavorite": bool(note.is_favorite),
        "updatedAt": updated_at,
        "deleted": deleted,
    })


def queue_todo_list_changed(
    db: Session,
    *,
    action: str,
    name: str,
    previous_name: str | None = None,
) -> None:
    audience = set(db.scalars(select(User.id).where(User.status == UserStatus.ACTIVE)).all())
    _queue(db, audience, "todo_list.changed", {
        "action": action,
        "name": name,
        "previousName": previous_name,
    })


def _queue_team_note_change(db: Session, note: TeamNote, *, deleted: bool = False) -> None:
    team_id = note.team_id
    if not team_id:
        return
    status = note.status.value if hasattr(note.status, "value") else str(note.status)
    updated_at = note.updated_at.isoformat() if isinstance(note.updated_at, datetime) else None
    _queue(db, _active_team_members(db, team_id), "team_note.changed", {
        "teamId": team_id,
        "noteId": note.id,
        "title": note.title,
        "categoryId": note.category_id,
        "status": "DELETED" if deleted else status,
        "updatedAt": updated_at,
    })


@event.listens_for(Session, "after_flush")
def _capture_team_note_changes(session: Session, _flush_context: object) -> None:
    seen = session.info.setdefault(PENDING_TEAM_NOTES_KEY, set())
    changes: dict[str, tuple[TeamNote, bool]] = {}
    for item in (*session.new, *session.dirty):
        if isinstance(item, TeamNote):
            changes[item.id] = (item, False)
    for item in session.deleted:
        if isinstance(item, TeamNote):
            changes[item.id] = (item, True)
    for note_id, (item, deleted) in changes.items():
        if note_id in seen:
            continue
        seen.add(note_id)
        _queue_team_note_change(session, item, deleted=deleted)


@event.listens_for(Session, "after_flush")
def _capture_note_changes(session: Session, _flush_context: object) -> None:
    seen = session.info.setdefault(PENDING_NOTES_KEY, set())
    changes: dict[str, tuple[Note, bool]] = {}
    for item in (*session.new, *session.dirty):
        if isinstance(item, Note):
            if item not in session.new and not session.is_modified(item, include_collections=False):
                continue
            changes[item.id] = (item, bool(item.deleted_at))
    for item in session.deleted:
        if isinstance(item, Note):
            changes[item.id] = (item, True)
    for note_id, (item, deleted) in changes.items():
        if note_id in seen:
            continue
        seen.add(note_id)
        queue_note_changed(session, item, deleted=deleted)


@event.listens_for(Session, "after_commit")
def _publish_after_commit(session: Session) -> None:
    pending = session.info.pop(PENDING_EVENTS_KEY, [])
    session.info.pop(PENDING_TEAM_NOTES_KEY, None)
    session.info.pop(PENDING_NOTES_KEY, None)
    for audience, name, data in pending:
        hub.publish(audience, name, data)


@event.listens_for(Session, "after_rollback")
def _discard_after_rollback(session: Session) -> None:
    session.info.pop(PENDING_EVENTS_KEY, None)
    session.info.pop(PENDING_TEAM_NOTES_KEY, None)
    session.info.pop(PENDING_NOTES_KEY, None)


def parse_last_event_id(value: str | None) -> int | None:
    try:
        return int(value) if value else None
    except ValueError:
        return None


def format_sse(item: StreamEvent) -> str:
    return (
        f"id: {item.event_id}\n"
        f"event: {item.name}\n"
        f"data: {json.dumps(item.data, ensure_ascii=False, separators=(',', ':'))}\n\n"
    )
