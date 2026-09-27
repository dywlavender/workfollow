"""流程图附件：成对保存端点、revision 乐观锁、删除保护与成对清理。"""

import base64
import uuid

from app.core.config import get_settings
from app.models.note import Attachment, Note
from app.models.team_note import SubmissionFileAccess
from app.services.note_service import (
    _cleanup_removed_embedded_images,
    attachment_ids_in_document,
)
from sqlalchemy import select

_PNG_BYTES = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)


def _create_note(client) -> str:
    response = client.post("/api/notes", json={"title": "流程图冒烟"})
    assert response.status_code == 201, response.text
    return response.json()["id"]


def _upload_pair(client, note_id: str) -> tuple[str, str]:
    source = client.post(
        "/api/attachments",
        data={"noteId": note_id},
        files={"file": ("流程图.drawio", b"<mxfile><diagram/></mxfile>", "application/xml")},
    )
    preview = client.post(
        "/api/attachments",
        data={"noteId": note_id},
        files={"file": ("流程图-预览.png", _PNG_BYTES, "image/png")},
    )
    assert source.status_code == 201, source.text
    assert preview.status_code == 201, preview.text
    return source.json()["id"], preview.json()["id"]


def _diagram_document(source_id: str, preview_id: str, revision: int = 1) -> dict:
    return {
        "type": "doc",
        "content": [
            {"type": "paragraph", "content": [{"type": "text", "text": "图"}]},
            {
                "type": "diagramBlock",
                "attrs": {
                    "sourceAttachmentId": source_id,
                    "previewAttachmentId": preview_id,
                    "revision": revision,
                    "title": "冒烟流程图",
                },
            },
        ],
    }


def test_attachment_ids_in_document_recognizes_diagram_attrs(db) -> None:
    document = _diagram_document("src-1", "preview-1")
    ids = attachment_ids_in_document(document)
    assert {"src-1", "preview-1"} <= ids


def test_diagram_pair_save_and_revision_conflict(client) -> None:
    note_id = _create_note(client)
    source_id, preview_id = _upload_pair(client, note_id)

    saved = client.put(
        "/api/attachments/diagram-content",
        data={"sourceAttachmentId": source_id, "previewAttachmentId": preview_id, "expectedRevision": "1"},
        files={"file": ("流程图.drawio", b"<mxfile>v2</mxfile>", "application/xml"), "preview": ("流程图-预览.png", _PNG_BYTES, "image/png")},
    )
    assert saved.status_code == 200, saved.text
    body = saved.json()
    assert body == {
        "sourceAttachmentId": source_id,
        "previewAttachmentId": preview_id,
        "revision": 2,
        "copied": False,
    }

    conflict = client.put(
        "/api/attachments/diagram-content",
        data={"sourceAttachmentId": source_id, "previewAttachmentId": preview_id, "expectedRevision": "1"},
        files={"file": ("流程图.drawio", b"<mxfile>v3</mxfile>", "application/xml"), "preview": ("流程图-预览.png", _PNG_BYTES, "image/png")},
    )
    assert conflict.status_code == 409
    assert conflict.json()["detail"]["currentRevision"] == 2

    again = client.put(
        "/api/attachments/diagram-content",
        data={"sourceAttachmentId": source_id, "previewAttachmentId": preview_id, "expectedRevision": "2"},
        files={"file": ("流程图.drawio", b"<mxfile>v3</mxfile>", "application/xml"), "preview": ("流程图-预览.png", _PNG_BYTES, "image/png")},
    )
    assert again.status_code == 200
    assert again.json()["revision"] == 3


def test_diagram_attachment_delete_guard_and_pair_cleanup(client, db) -> None:
    note_id = _create_note(client)
    source_id, preview_id = _upload_pair(client, note_id)

    note = db.get(Note, note_id)
    note.content_json = _diagram_document(source_id, preview_id)
    db.commit()

    blocked = client.delete(f"/api/attachments/{source_id}")
    assert blocked.status_code == 409
    blocked = client.delete(f"/api/attachments/{preview_id}")
    assert blocked.status_code == 409

    # 节点移除后：成对清理 .drawio 与预览 PNG。
    note = db.get(Note, note_id)
    note.content_json = {"type": "doc", "content": [{"type": "paragraph"}]}
    db.commit()
    removed = _cleanup_removed_embedded_images(db, note, note.content_json, get_settings())
    db.commit()
    assert len(removed) == 2
    remaining = db.scalars(select(Attachment).where(Attachment.note_id == note_id)).all()
    assert remaining == []


def test_diagram_save_copies_pair_when_snapshot_holds_reference(client, db) -> None:
    note_id = _create_note(client)
    source_id, preview_id = _upload_pair(client, note_id)

    note = db.get(Note, note_id)
    note.content_json = _diagram_document(source_id, preview_id)
    db.commit()
    db.add(SubmissionFileAccess(id=str(uuid.uuid4()), submission_id=str(uuid.uuid4()), attachment_id=source_id))
    db.commit()

    saved = client.put(
        "/api/attachments/diagram-content",
        data={"sourceAttachmentId": source_id, "previewAttachmentId": preview_id, "expectedRevision": "1"},
        files={"file": ("流程图.drawio", b"<mxfile>snapshot-safe</mxfile>", "application/xml"), "preview": ("流程图-预览.png", _PNG_BYTES, "image/png")},
    )
    assert saved.status_code == 200, saved.text
    body = saved.json()
    assert body["copied"] is True
    assert body["sourceAttachmentId"] != source_id
    assert body["previewAttachmentId"] != preview_id
    assert body["revision"] == 1

    # 旧一对脱离笔记但保留字节服务快照；新一对挂到当前笔记。
    old_source = db.get(Attachment, source_id)
    assert old_source is not None and old_source.note_id is None
    new_source = db.get(Attachment, body["sourceAttachmentId"])
    assert new_source is not None and new_source.note_id == note_id
