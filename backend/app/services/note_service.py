from collections.abc import Mapping, Sequence
from copy import deepcopy
from datetime import date
from pathlib import Path
import shutil
from typing import Any
from uuid import uuid4

from sqlalchemy import Text as SqlText
from sqlalchemy import cast, func, or_, select
from sqlalchemy.orm import Session, load_only

from fastapi import HTTPException

from app.core.config import Settings
from app.models.note import Attachment, Folder, Note
from app.models.team_note import SubmissionFileAccess, TeamFileAccess
from app.models.todo import local_now
from app.schemas.note import FolderCreate, FolderUpdate, NoteCapture, NoteCreate, NoteUpdate
from app.services import search_index_service


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
    tags: list[str] | None = None,
    unfiled: bool = False,
    limit: int = 100,
    offset: int = 0,
    summary: bool = False,
) -> list[Note]:
    statement = select(Note).where(Note.owner_id == owner_id, Note.deleted_at.is_(None))
    if summary:
        statement = statement.options(load_only(
            Note.id,
            Note.folder_id,
            Note.title,
            Note.tags,
            Note.is_favorite,
            Note.copied_from_note_id,
            Note.copied_from_team_note_id,
            Note.is_knowledge_update_draft,
            Note.copied_from_team_note_version_no,
            Note.copied_from_team_note_snapshot_hash,
            Note.created_at,
            Note.updated_at,
            Note.deleted_at,
        ))
    if folder_id:
        statement = statement.where(Note.folder_id == folder_id)
    if favorite is not None:
        statement = statement.where(Note.is_favorite.is_(favorite))
    if unfiled:
        statement = statement.where(Note.folder_id.is_(None))
    normalized_tags = [tag.strip() for tag in (tags or []) if tag.strip()]
    for tag in normalized_tags:
        tag_values = func.json_each(Note.tags).table_valued("value").alias("note_tag")
        statement = statement.where(
            select(tag_values.c.value).where(tag_values.c.value == tag).correlate(Note).exists()
        )
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


def list_note_tags(db: Session, owner_id: str) -> list[str]:
    values = db.scalars(
        select(Note.tags).where(Note.owner_id == owner_id, Note.deleted_at.is_(None))
    ).all()
    tags = {tag.strip() for row in values if isinstance(row, list) for tag in row if isinstance(tag, str) and tag.strip()}
    return sorted(tags, key=lambda item: (item.casefold(), item))


def count_unfiled_notes(db: Session, owner_id: str) -> int:
    return int(db.scalar(
        select(func.count(Note.id)).where(
            Note.owner_id == owner_id,
            Note.deleted_at.is_(None),
            Note.folder_id.is_(None),
        )
    ) or 0)


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
    search_index_service.upsert_personal_note(db, note)
    if commit:
        db.commit()
        db.refresh(note)
    return note


def _plain_text_to_document(value: str) -> dict[str, Any]:
    paragraphs = []
    for line in value.splitlines() or [""]:
        paragraph: dict[str, Any] = {"type": "paragraph"}
        if line:
            paragraph["content"] = [{"type": "text", "text": line}]
        paragraphs.append(paragraph)
    return {"type": "doc", "content": paragraphs}


def capture_note(db: Session, payload: NoteCapture, owner_id: str) -> Note:
    first_line = next((line.strip() for line in payload.text.splitlines() if line.strip()), "")
    title = (payload.title or first_line or "未命名笔记").strip()[:500]
    return create_note(
        db,
        NoteCreate(
            folder_id=None,
            title=title,
            content_json=_plain_text_to_document(payload.text),
            plain_text=payload.text,
            tags=payload.tags,
        ),
        owner_id,
    )


def _attachment_id_from_url(value: object) -> str | None:
    if not isinstance(value, str) or "/api/attachments/" not in value:
        return None
    candidate = value.rsplit("/api/attachments/", 1)[-1]
    return candidate.split("/", 1)[0].split("?", 1)[0].split("#", 1)[0] or None


def attachment_ids_in_document(content_json: Mapping[str, object] | None) -> set[str]:
    """Return all attachment ids referenced by a note document."""

    found: set[str] = set()

    def visit(value: object) -> None:
        if isinstance(value, Mapping):
            attrs = value.get("attrs")
            if isinstance(attrs, Mapping):
                for key in ("attachmentId", "fileId", "attachment_id", "file_id"):
                    candidate = attrs.get(key)
                    if isinstance(candidate, str) and candidate:
                        found.add(candidate)
                candidate = _attachment_id_from_url(attrs.get("src"))
                if candidate:
                    found.add(candidate)
            children = value.get("content")
            if isinstance(children, list):
                for child in children:
                    visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(content_json)
    return found


def embedded_image_attachment_ids(content_json: Mapping[str, object] | None) -> set[str]:
    """Return attachment ids used by image nodes, including legacy src-only nodes."""

    found: set[str] = set()

    def visit(value: object) -> None:
        if not isinstance(value, Mapping):
            if isinstance(value, list):
                for child in value:
                    visit(child)
            return
        if value.get("type") == "image":
            attrs = value.get("attrs")
            if isinstance(attrs, Mapping):
                for key in ("attachmentId", "fileId", "attachment_id", "file_id"):
                    candidate = attrs.get(key)
                    if isinstance(candidate, str) and candidate:
                        found.add(candidate)
                        break
                else:
                    candidate = _attachment_id_from_url(attrs.get("src"))
                    if candidate:
                        found.add(candidate)
        children = value.get("content")
        if isinstance(children, list):
            for child in children:
                visit(child)

    visit(content_json)
    return found


def _has_external_attachment_access(db: Session, attachment_id: str) -> bool:
    return bool(
        db.scalar(select(TeamFileAccess.id).where(
            TeamFileAccess.attachment_id == attachment_id
        ).limit(1))
        or db.scalar(select(SubmissionFileAccess.id).where(
            SubmissionFileAccess.attachment_id == attachment_id
        ).limit(1))
    )


def _cleanup_removed_embedded_images(
    db: Session,
    note: Note,
    next_content: Mapping[str, object] | None,
    settings: Settings,
) -> list[Path]:
    referenced_ids = attachment_ids_in_document(next_content)
    attachments = list(db.scalars(select(Attachment).where(Attachment.note_id == note.id)))
    paths_to_remove: list[Path] = []
    for attachment in attachments:
        if not attachment.mime_type.lower().startswith("image/") or attachment.id in referenced_ids:
            continue
        if _has_external_attachment_access(db, attachment.id):
            # The personal note no longer owns the binary, but an already
            # submitted or published collaboration snapshot still does.
            attachment.note_id = None
            continue
        paths_to_remove.append(settings.files_dir.parent.parent / attachment.file_path)
        db.delete(attachment)
    return paths_to_remove


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
    tags: list[str] | None = None,
    source_attachments: Sequence[Attachment],
    owner_id: str,
    settings: Settings,
    folder_id: str | None = None,
    copied_from_note_id: str | None = None,
    copied_from_team_note_id: str | None = None,
    is_knowledge_update_draft: bool = False,
    copied_from_team_note_version_no: int | None = None,
    copied_from_team_note_snapshot_hash: str | None = None,
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
            tags=list(tags or []),
            copied_from_note_id=copied_from_note_id,
            copied_from_team_note_id=copied_from_team_note_id,
            is_knowledge_update_draft=is_knowledge_update_draft,
            copied_from_team_note_version_no=copied_from_team_note_version_no,
            copied_from_team_note_snapshot_hash=copied_from_team_note_snapshot_hash,
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
        search_index_service.upsert_personal_note(db, note)
        db.commit()
        db.refresh(note)
        return note
    except Exception:
        db.rollback()
        for target in created_files:
            target.unlink(missing_ok=True)
        raise


def update_note(db: Session, note: Note, payload: NoteUpdate, settings: Settings) -> Note:
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
    paths_to_remove: list[Path] = []
    if "content_json" in changes:
        from app.services import resource_relation_service
        from app.models.resource_relation import ResourceRelation, ResourceType

        referenced_attachment_ids = attachment_ids_in_document(changes["content_json"])
        has_old_images = db.scalar(select(Attachment.id).where(
            Attachment.note_id == note.id,
            Attachment.mime_type.ilike("image/%"),
        ).limit(1)) is not None
        if referenced_attachment_ids or has_old_images:
            paths_to_remove = _cleanup_removed_embedded_images(
                db,
                note,
                changes["content_json"],
                settings,
            )

        retained_task_ids = resource_relation_service.task_ids_in_document(changes["content_json"])
        has_old_task_relations = db.scalar(select(ResourceRelation.id).where(
            ResourceRelation.source_type == ResourceType.PERSONAL_NOTE,
            ResourceRelation.source_id == note.id,
            ResourceRelation.target_type == ResourceType.TASK,
            ResourceRelation.created_by_id == note.owner_id,
            ResourceRelation.deleted_at.is_(None),
        ).limit(1)) is not None
        if retained_task_ids or has_old_task_relations:
            resource_relation_service.sync_personal_note_relations(
                db,
                note.id,
                note.owner_id,
                retained_task_ids,
            )
    search_index_service.upsert_personal_note(db, note)
    db.commit()
    for path in paths_to_remove:
        path.unlink(missing_ok=True)
    db.refresh(note)
    return note


def soft_delete_note(db: Session, note: Note) -> None:
    note.deleted_at = local_now()
    search_index_service.remove_source(db, search_index_service.PERSONAL_SOURCE, note.id)
    db.commit()
