from fastapi.testclient import TestClient

from app.models.auth import User, UserStatus
from app.models.note import Attachment
from app.models.team_note import TeamNote
from app.models.team_note import TeamNoteSubmission
from app.services import team_note_service
from app.services.auth_service import password_hash
from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session
import pytest


def add_note_user(db, user_id: str, username: str) -> User:
    user = User(
        id=user_id,
        username=username,
        password_hash=password_hash.hash("member-password"),
        nickname=username.title(),
        status=UserStatus.ACTIVE,
    )
    db.add(user)
    db.commit()
    return user


def login_note_user(app, username: str) -> TestClient:
    client = TestClient(app)
    response = client.post(
        "/api/auth/login", json={"identifier": username, "password": "member-password"}
    )
    assert response.status_code == 200, response.text
    return client


def test_submission_is_snapshot_and_approval_creates_independent_team_note(client: TestClient, db, user_id: str) -> None:
    member = add_note_user(db, "40000000-0000-0000-0000-000000000001", "author")
    viewer = add_note_user(db, "40000000-0000-0000-0000-000000000003", "viewer")
    team = client.post("/api/teams", json={"name": "知识团队"}).json()
    team_id = team["id"]
    assert client.post(
        f"/api/teams/{team_id}/members", json={"identifier": member.username, "role": "MEMBER"}
    ).status_code == 201
    assert client.post(
        f"/api/teams/{team_id}/members", json={"identifier": viewer.username, "role": "MEMBER"}
    ).status_code == 201
    member_client = login_note_user(client.app, member.username)

    source = member_client.post(
        "/api/notes",
        json={
            "title": "初始标题",
            "contentJson": {"type": "doc", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "快照内容 v1"}]}]},
            "plainText": "快照内容 v1",
        },
    )
    assert source.status_code == 201, source.text
    source_id = source.json()["id"]
    attachment = Attachment(
        id="40000000-0000-0000-0000-000000000010",
        owner_id=member.id,
        note_id=source_id,
        original_name="snapshot.txt",
        storage_name="snapshot.txt",
        mime_type="text/plain",
        size=12,
        file_path="data/files/not-created-for-test.txt",
    )
    db.add(attachment)
    db.commit()

    submitted = member_client.post(
        f"/api/teams/{team_id}/note-submissions", json={"sourceNoteId": source_id}
    )
    assert submitted.status_code == 201, submitted.text
    submission = submitted.json()
    assert submission["status"] == "PENDING"
    assert submission["snapshotTitle"] == "初始标题"
    assert submission["snapshotAttachmentIds"] == [attachment.id]

    # Personal edits after submission must not mutate the stored snapshot.
    assert member_client.put(
        f"/api/notes/{source_id}",
        json={
            "title": "后来修改",
            "contentJson": {"type": "doc", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "个人笔记 v2"}]}]},
            "plainText": "个人笔记 v2",
        },
    ).status_code == 200

    approved = client.post(f"/api/teams/{team_id}/note-submissions/{submission['id']}/approve")
    assert approved.status_code == 200, approved.text
    team_note = approved.json()
    assert team_note["title"] == "初始标题"
    assert team_note["plainText"] == "快照内容 v1"
    assert team_note["attachmentIds"] == [attachment.id]
    assert team_note["sourceNoteId"] == source_id
    assert team_note["sourceAuthorId"] == member.id
    assert team_note["sourceSubmissionId"] == submission["id"]
    assert team_note["sourceType"] == "MEMBER_SUBMISSION"

    viewer_client = login_note_user(client.app, viewer.username)
    visible = viewer_client.get(f"/api/teams/{team_id}/notes/{team_note['id']}")
    assert visible.status_code == 200
    assert visible.json()["contentJson"] == submission["snapshotContentJson"]
    assert viewer_client.put(
        f"/api/teams/{team_id}/notes/{team_note['id']}", json={"title": "成员不能改"}
    ).status_code == 403

    # The file is absent on disk, but the first request reaches the file layer;
    # after membership removal the same capability is rejected earlier.
    accessible_before_removal = viewer_client.get(f"/api/attachments/{attachment.id}")
    assert accessible_before_removal.status_code == 404
    assert accessible_before_removal.json()["detail"] == "Attachment file not found"
    assert client.delete(f"/api/teams/{team_id}/members/{viewer.id}").status_code == 204
    assert viewer_client.get(f"/api/teams/{team_id}/notes/{team_note['id']}").status_code == 404
    inaccessible_after_removal = viewer_client.get(f"/api/attachments/{attachment.id}")
    assert inaccessible_after_removal.status_code == 404
    assert inaccessible_after_removal.json()["detail"] == "Attachment not found"


def test_team_note_admin_crud_and_member_submission_visibility(client: TestClient, db) -> None:
    member = add_note_user(db, "40000000-0000-0000-0000-000000000002", "reader")
    team = client.post("/api/teams", json={"name": "审批流程"}).json()
    team_id = team["id"]
    assert client.post(
        f"/api/teams/{team_id}/members", json={"identifier": member.username, "role": "MEMBER"}
    ).status_code == 201
    direct = client.post(
        f"/api/teams/{team_id}/notes",
        json={"title": "团队公告", "contentJson": {"type": "doc", "content": []}},
    )
    assert direct.status_code == 201, direct.text
    note_id = direct.json()["id"]
    member_client = login_note_user(client.app, member.username)
    assert member_client.get(f"/api/teams/{team_id}/notes").status_code == 200
    assert member_client.delete(f"/api/teams/{team_id}/notes/{note_id}").status_code == 403
    assert client.put(f"/api/teams/{team_id}/notes/{note_id}", json={"title": "团队公告 v2"}).status_code == 200


def test_stale_concurrent_approval_creates_only_one_team_note(client: TestClient, db) -> None:
    member = add_note_user(db, "40000000-0000-0000-0000-000000000021", "submitter")
    team_id = client.post("/api/teams", json={"name": "并发审核"}).json()["id"]
    assert client.post(
        f"/api/teams/{team_id}/members", json={"identifier": member.username, "role": "MEMBER"}
    ).status_code == 201
    member_client = login_note_user(client.app, member.username)
    note_id = member_client.post(
        "/api/notes", json={"title": "快照", "contentJson": {"type": "doc", "content": []}}
    ).json()["id"]
    submission_id = member_client.post(
        f"/api/teams/{team_id}/note-submissions", json={"sourceNoteId": note_id}
    ).json()["id"]

    with Session(bind=db.get_bind(), expire_on_commit=False) as first, Session(bind=db.get_bind(), expire_on_commit=False) as second:
        stale_first = first.get(TeamNoteSubmission, submission_id)
        stale_second = second.get(TeamNoteSubmission, submission_id)
        assert stale_first is not None and stale_second is not None
        team_note_service.approve_submission(first, stale_first, "20000000-0000-0000-0000-000000000001")
        with pytest.raises(HTTPException) as conflict:
            team_note_service.approve_submission(second, stale_second, "20000000-0000-0000-0000-000000000001")
        assert conflict.value.status_code == 409

    assert db.scalar(select(func.count(TeamNote.id)).where(TeamNote.source_submission_id == submission_id)) == 1
