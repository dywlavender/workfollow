from collections.abc import Mapping, Sequence
from copy import deepcopy
from datetime import date
from pathlib import Path
import shutil
from typing import Any
from uuid import uuid4

from sqlalchemy import Text as SqlText
from sqlalchemy import cast, or_, select
from sqlalchemy.orm import Session

from fastapi import HTTPException

from app.core.config import Settings
from app.models.note import Attachment, Folder, Note
from app.models.todo import local_now
from app.schemas.note import FolderCreate, FolderUpdate, NoteCreate, NoteUpdate


def content_to_plain_text(content_json: Mapping[str, object] | None) -> str:
    """Extract searchable text from a TipTap JSON document."""

    if not content_json:
        return ""
    chunks: list[str] = []

    def visit(node: object) -> None:
        if not isinstance(node, Mapping):
            return
        node_type = node.get("type")
        if node_type == "text":
            value = node.get("text")
            if isinstance(value, str):
                chunks.append(value)
        elif node_type == "hardBreak":
            chunks.append("\n")
        children = node.get("content")
        if isinstance(children, list):
            for child in children:
                visit(child)
        if isinstance(node_type, str) and node_type in {
            "paragraph",
            "heading",
            "blockquote",
            "codeBlock",
            "listItem",
            "taskItem",
        }:
            chunks.append("\n")

    visit(content_json)
    lines = [line.strip() for line in "".join(chunks).splitlines()]
    return "\n".join(line for line in lines if line).strip()


def get_folder_or_404(db: Session, folder_id: str, owner_id: str | None = None) -> Folder:
    statement = select(Folder).where(Folder.id == folder_id)
    if owner_id is not None:
        statement = statement.where(Folder.owner_id == owner_id)
    folder = db.scalar(statement)
    if folder is None:
        raise HTTPException(status_code=404, detail="Folder not found")
    return folder


def _ensure_parent_is_valid(db: Session, folder_id: str | None, parent_id: str | None, owner_id: str) -> None:
    if parent_id is None:
        return
    get_folder_or_404(db, parent_id, owner_id)
    current = parent_id
    while current:
        if current == folder_id:
            raise HTTPException(status_code=422, detail="文件夹不能移动到自身或子文件夹中")
        parent = db.get(Folder, current)
        current = parent.parent_id if parent else None


def list_folders(db: Session, owner_id: str) -> list[Folder]:
    return list(
        db.scalars(
            select(Folder)
            .where(Folder.owner_id == owner_id)
            .order_by(Folder.parent_id, Folder.sort_order, Folder.created_at)
        )
    )


def create_folder(db: Session, payload: FolderCreate, owner_id: str) -> Folder:
    _ensure_parent_is_valid(db, None, payload.parent_id, owner_id)
    data = payload.model_dump()
    data["name"] = payload.name.strip()
    folder = Folder(**data, owner_id=owner_id)
    db.add(folder)
    db.commit()
    db.refresh(folder)
    return folder


def update_folder(db: Session, folder: Folder, payload: FolderUpdate) -> Folder:
    changes = payload.model_dump(exclude_unset=True)
    if "parent_id" in changes:
        _ensure_parent_is_valid(db, folder.id, changes["parent_id"], folder.owner_id)
    if "name" in changes:
        changes["name"] = (changes["name"] or "").strip()
        if not changes["name"]:
            raise HTTPException(status_code=422, detail="文件夹名称不能为空")
    for field, value in changes.items():
        setattr(folder, field, value)
    db.commit()
    db.refresh(folder)
    return folder


def delete_folder(db: Session, folder: Folder) -> None:
    has_notes = db.scalar(select(Note.id).where(Note.folder_id == folder.id, Note.deleted_at.is_(None)).limit(1))
    has_children = db.scalar(select(Folder.id).where(Folder.parent_id == folder.id).limit(1))
    if has_notes:
        raise HTTPException(status_code=409, detail="该文件夹存在笔记，请先移动笔记。")
    if has_children:
        raise HTTPException(status_code=409, detail="该文件夹存在子文件夹，请先移动子文件夹。")
    db.delete(folder)
    db.commit()


def get_note_or_404(db: Session, note_id: str, owner_id: str | None = None) -> Note:
    statement = select(Note).where(Note.id == note_id)
    if owner_id is not None:
        statement = statement.where(Note.owner_id == owner_id)
    note = db.scalar(statement)
    if note is None or note.deleted_at is not None:
        raise HTTPException(status_code=404, detail="Note not found")
    return note


def list_notes(
    db: Session,
    owner_id: str,
    folder_id: str | None = None,
    q: str | None = None,
    favorite: bool | None = None,
    limit: int = 100,
    offset: int = 0,
) -> list[Note]:
    statement = select(Note).where(Note.owner_id == owner_id, Note.deleted_at.is_(None))
    if folder_id:
        statement = statement.where(Note.folder_id == folder_id)
    if favorite is not None:
        statement = statement.where(Note.is_favorite.is_(favorite))
    if q and q.strip():
        pattern = f"%{q.strip()}%"
        # The JSON fallback keeps notes created by older versions searchable
        # while their derived plain_text is repaired on the next save.
        statement = statement.where(
            or_(
                Note.title.like(pattern),
                Note.plain_text.like(pattern),
                cast(Note.content_json, SqlText).like(pattern),
            )
        )
    return list(db.scalars(statement.order_by(Note.updated_at.desc()).limit(limit).offset(offset)))


def create_note(db: Session, payload: NoteCreate, owner_id: str, *, commit: bool = True) -> Note:
    if payload.folder_id:
        get_folder_or_404(db, payload.folder_id, owner_id)
    data = payload.model_dump()
    data["title"] = payload.title.strip()
    if not (data.get("plain_text") or "").strip():
        data["plain_text"] = content_to_plain_text(data.get("content_json"))
    note = Note(**data, owner_id=owner_id)
    db.add(note)
    db.flush()
    if commit:
        db.commit()
        db.refresh(note)
    return note


def _rewrite_attachment_references(value: Any, id_map: Mapping[str, str]) -> Any:
    """Return a detached TipTap document whose attachment references use cloned IDs."""

    if isinstance(value, dict):
        rewritten: dict[str, Any] = {}
        for key, child in value.items():
            if key in {"fileId", "attachmentId", "file_id", "attachment_id"} and isinstance(child, str):
                rewritten[key] = id_map.get(child, child)
            elif key == "src" and isinstance(child, str) and "/api/attachments/" in child:
                updated = child
                for old_id, new_id in id_map.items():
                    updated = updated.replace(f"/api/attachments/{old_id}", f"/api/attachments/{new_id}")
                rewritten[key] = updated
            else:
                rewritten[key] = _rewrite_attachment_references(child, id_map)
        return rewritten
    if isinstance(value, list):
        return [_rewrite_attachment_references(child, id_map) for child in value]
    return deepcopy(value)


def copy_note_with_attachments(
    db: Session,
    *,
    title: str,
    content_json: dict[str, Any],
    plain_text: str,
    source_attachments: Sequence[Attachment],
    owner_id: str,
    settings: Settings,
    folder_id: str | None = None,
    copied_from_note_id: str | None = None,
    copied_from_team_note_id: str | None = None,
) -> Note:
    """Clone a note and its files so the new personal copy has an independent lifecycle."""

    created_files: list[Path] = []
    try:
        note = Note(
            owner_id=owner_id,
            folder_id=folder_id,
            title=title.strip(),
            content_json=deepcopy(content_json),
            plain_text=plain_text,
            copied_from_note_id=copied_from_note_id,
            copied_from_team_note_id=copied_from_team_note_id,
        )
        db.add(note)
        db.flush()

        today = date.today()
        id_map: dict[str, str] = {}
        for source in source_attachments:
            source_path = settings.files_dir.parent.parent / source.file_path
            if not source_path.is_file():
                raise HTTPException(status_code=409, detail=f"附件“{source.original_name}”文件已丢失，无法复制")
            suffix = Path(source.storage_name).suffix or Path(source.original_name).suffix
            storage_name = f"{uuid4()}{suffix.lower()}"
            relative_path = Path("data") / "files" / f"{today.year:04d}" / f"{today.month:02d}" / storage_name
            target = settings.files_dir / f"{today.year:04d}" / f"{today.month:02d}" / storage_name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_path, target)
            created_files.append(target)

            cloned = Attachment(
                owner_id=owner_id,
                note_id=note.id,
                original_name=source.original_name,
                storage_name=storage_name,
                mime_type=source.mime_type,
                size=source.size,
                file_path=relative_path.as_posix(),
            )
            db.add(cloned)
            db.flush()
            id_map[source.id] = cloned.id

        note.content_json = _rewrite_attachment_references(content_json, id_map)
        db.commit()
        db.refresh(note)
        return note
    except Exception:
        db.rollback()
        for target in created_files:
            target.unlink(missing_ok=True)
        raise


def update_note(db: Session, note: Note, payload: NoteUpdate) -> Note:
    changes = payload.model_dump(exclude_unset=True)
    if "folder_id" in changes and changes["folder_id"]:
        get_folder_or_404(db, changes["folder_id"], note.owner_id)
    if "title" in changes:
        changes["title"] = (changes["title"] or "").strip()
        if not changes["title"]:
            raise HTTPException(status_code=422, detail="笔记标题不能为空")
    if "content_json" in changes and not (changes.get("plain_text") or "").strip():
        changes["plain_text"] = content_to_plain_text(changes["content_json"])
    for field, value in changes.items():
        setattr(note, field, value)
    if "content_json" in changes:
        from app.services import resource_relation_service

        resource_relation_service.sync_personal_note_relations(
            db,
            note.id,
            note.owner_id,
            resource_relation_service.task_ids_in_document(changes["content_json"]),
        )
    db.commit()
    db.refresh(note)
    return note


def soft_delete_note(db: Session, note: Note) -> None:
    note.deleted_at = local_now()
    db.commit()
