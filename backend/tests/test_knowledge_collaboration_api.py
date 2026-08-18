from fastapi.testclient import TestClient
from sqlalchemy import func, select

from app.core.config import Settings, get_settings
from app.models.auth import SystemRole, User, UserStatus
from app.models.note import Attachment, Note
from app.models.team_note import TeamNote, TeamNoteSubmission, TeamNoteVersion
from app.services.auth_service import password_hash


def add_user(db, suffix: str) -> User:  # noqa: ANN001
    user = User(
        id=f"90000000-0000-0000-0000-{suffix:0>12}",
        username=f"knowledge-{suffix}",
        password_hash=password_hash.hash("member-password"),
        nickname=f"知识成员{suffix}",
        status=UserStatus.ACTIVE,
    )
    db.add(user)
    db.commit()
    return user


def login(app, username: str) -> TestClient:  # noqa: ANN001
    result = TestClient(app)
    response = result.post("/api/auth/login", json={"identifier": username, "password": "member-password"})
    assert response.status_code == 200, response.text
    return result


def setup_team(client: TestClient, db):  # noqa: ANN001
    member = add_user(db, "1")
    outsider = add_user(db, "2")
    team_id = client.post("/api/teams", json={"name": "知识闭环团队"}).json()["id"]
    assert client.post(
        f"/api/teams/{team_id}/members", json={"identifier": member.username, "role": "MEMBER"}
    ).status_code == 201
    return team_id, member, outsider, login(client.app, member.username), login(client.app, outsider.username)


def test_root_can_manage_nonmember_team_knowledge_and_team_attachments(client: TestClient, db, tmp_path) -> None:
    root = add_user(db, "root-access")
    root.system_role = SystemRole.ROOT
    db.commit()
    root_client = login(client.app, root.username)

    settings = Settings(files_dir=tmp_path / "data" / "files")
    client.app.dependency_overrides[get_settings] = lambda: settings
    team_id = client.post("/api/teams", json={"name": "root 管理团队"}).json()["id"]
    source = client.post("/api/notes", json={"title": "附件来源"}).json()
    uploaded = client.post(
        "/api/attachments",
        data={"noteId": source["id"]},
        files={"file": ("root-access.txt", b"root team binary", "text/plain")},
    )
    assert uploaded.status_code == 201, uploaded.text
    attachment_id = uploaded.json()["id"]
    knowledge = client.post(
        "/api/team/knowledge",
        json={
            "title": "root 可管理的知识",
            "contentJson": {"type": "doc", "content": []},
            "attachmentIds": [attachment_id],
        },
        params={"teamId": team_id},
    )
    assert knowledge.status_code == 201, knowledge.text
    note_id = knowledge.json()["id"]

    listed = root_client.get("/api/team/knowledge", params={"teamId": team_id})
    assert listed.status_code == 200, listed.text
    assert listed.json()[0]["id"] == note_id
    assert listed.json()[0]["permissions"]["canEdit"] is True
    assert root_client.get(f"/api/attachments/{attachment_id}").content == b"root team binary"
    updated = root_client.put(
        f"/api/team/knowledge/{note_id}",
        params={"teamId": team_id},
        json={"title": "root 已修改"},
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["title"] == "root 已修改"

    category = root_client.post(
        "/api/team/knowledge/categories", params={"teamId": team_id}, json={"name": "系统规范"}
    )
    assert category.status_code == 201, category.text

    author = add_user(db, "root-submit-author")
    assert client.post(
        f"/api/teams/{team_id}/members", json={"identifier": author.username, "role": "MEMBER"}
    ).status_code == 201
    author_client = login(client.app, author.username)
    personal = author_client.post("/api/notes", json={"title": "待审核投稿"}).json()
    submission = author_client.post(
        f"/api/notes/{personal['id']}/submissions", params={"teamId": team_id}, json={"type": "CREATE"}
    )
    assert submission.status_code == 201, submission.text
    review = root_client.get("/api/note-submissions/review", params={"teamId": team_id})
    assert review.status_code == 200, review.text
    assert review.json()[0]["id"] == submission.json()["id"]
    approved = root_client.post(f"/api/note-submissions/{submission.json()['id']}/approve", json={})
    assert approved.status_code == 200, approved.text


def test_revision_approval_keeps_snapshot_provenance_and_independent_lifecycle(client: TestClient, db) -> None:
    team_id, member, _outsider, member_client, _outsider_client = setup_team(client, db)
    category = client.post("/api/team/knowledge/categories", json={"name": "技术", "sortOrder": 10})
    assert category.status_code == 201, category.text
    category_id = category.json()["id"]
    source = member_client.post("/api/notes", json={
        "title": "接口规范 V1",
        "contentJson": {"type": "doc", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "V1 正文"}]}]},
        "plainText": "V1 正文",
    }).json()

    submitted = member_client.post(f"/api/notes/{source['id']}/submissions", json={
        "type": "CREATE", "categoryId": category_id, "tags": ["API"], "message": "第一版",
    })
    assert submitted.status_code == 201, submitted.text
    submission = submitted.json()
    assert submission["snapshotPlainText"] == "V1 正文"
    assert len(submission["snapshotHash"]) == 64
    submitted_notifications = client.get("/api/notifications", params={"unreadOnly": True}).json()
    assert any(
        item["type"] == "TEAM_NOTE_SUBMITTED"
        and item["dataJson"]["teamId"] == team_id
        and item["dataJson"]["submissionId"] == submission["id"]
        for item in submitted_notifications
    )

    # The reviewer sees the immutable V1 snapshot even after the personal source changes.
    assert member_client.put(f"/api/notes/{source['id']}", json={
        "title": "接口规范 V2", "plainText": "V2 正文",
        "contentJson": {"type": "doc", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "V2 正文"}]}]},
    }).status_code == 200
    review_list = client.get("/api/note-submissions/review").json()
    assert review_list[0]["snapshotPlainText"] == "V1 正文"

    revision = client.post(
        f"/api/note-submissions/{submission['id']}/request-revision",
        json={"reason": "请补充新版流程", "reasonCode": "MISSING_SECTION"},
    )
    assert revision.status_code == 200, revision.text
    assert revision.json()["status"] == "NEEDS_REVISION"
    assert member_client.post(
        f"/api/note-submissions/{submission['id']}/resubmit",
        json={"type": "CREATE", "categoryId": category_id, "tags": ["API", "新版"]},
    ).status_code == 200
    pending_v2 = member_client.get("/api/note-submissions/mine").json()[0]
    assert pending_v2["revisionNo"] == 2
    assert pending_v2["snapshotPlainText"] == "V2 正文"

    approved = client.post(
        f"/api/note-submissions/{submission['id']}/approve",
        json={"title": "接口规范", "categoryId": category_id, "tags": ["API", "正式"]},
    )
    assert approved.status_code == 200, approved.text
    knowledge = approved.json()
    assert knowledge["plainText"] == "V2 正文"
    assert knowledge["sourceNoteId"] == source["id"]
    assert knowledge["sourceAuthorId"] == member.id
    assert knowledge["sourceSubmissionId"] == submission["id"]
    assert knowledge["category"]["name"] == "技术"
    assert knowledge["tags"] == ["API", "正式"]

    assert member_client.delete(f"/api/notes/{source['id']}").status_code == 204
    retained = member_client.get(f"/api/team/knowledge/{knowledge['id']}")
    assert retained.status_code == 200
    assert retained.json()["plainText"] == "V2 正文"
    assert retained.json()["permissions"]["canEdit"] is False
    assert db.scalar(select(func.count(TeamNoteVersion.id)).where(
        TeamNoteVersion.team_note_id == knowledge["id"]
    )) == 1


def test_update_submission_preserves_team_note_id_and_creates_version(client: TestClient, db) -> None:
    _team_id, member, _outsider, member_client, _outsider_client = setup_team(client, db)
    original = client.post("/api/team/knowledge", json={
        "title": "上线规范", "contentJson": {"type": "doc", "content": []}, "plainText": "V1",
    })
    assert original.status_code == 201, original.text
    knowledge_id = original.json()["id"]
    copied = member_client.post(f"/api/team/knowledge/{knowledge_id}/copy")
    assert copied.status_code == 201, copied.text
    personal = copied.json()
    assert personal["copiedFromTeamNoteId"] == knowledge_id
    assert member_client.put(f"/api/notes/{personal['id']}", json={
        "title": "上线规范", "plainText": "V2",
        "contentJson": {"type": "doc", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "V2"}]}]},
    }).status_code == 200
    submission = member_client.post(f"/api/notes/{personal['id']}/submissions", json={
        "type": "UPDATE", "targetTeamNoteId": knowledge_id, "message": "补充新版流程",
    })
    assert submission.status_code == 201, submission.text
    approved = client.post(
        f"/api/note-submissions/{submission.json()['id']}/approve", json={}
    )
    assert approved.status_code == 200, approved.text
    assert approved.json()["id"] == knowledge_id
    assert approved.json()["plainText"] == "V2"
    assert approved.json()["sourceAuthorId"] == member.id
    versions = member_client.get(f"/api/team/knowledge/{knowledge_id}/versions")
    assert versions.status_code == 200
    assert [item["versionNo"] for item in versions.json()] == [2, 1]
    assert db.scalar(select(func.count(TeamNote.id)).where(TeamNote.id == knowledge_id)) == 1


def test_withdraw_archive_and_backend_permissions(client: TestClient, db) -> None:
    team_id, member, outsider, member_client, outsider_client = setup_team(client, db)
    source = member_client.post("/api/notes", json={"title": "待撤回"}).json()
    submission = member_client.post(f"/api/notes/{source['id']}/submissions", json={"type": "CREATE"}).json()
    assert member_client.post(f"/api/note-submissions/{submission['id']}/withdraw").json()["status"] == "WITHDRAWN"
    assert member_client.post(f"/api/note-submissions/{submission['id']}/withdraw").status_code == 409
    assert client.post(f"/api/note-submissions/{submission['id']}/approve", json={}).status_code == 409

    knowledge = client.post("/api/team/knowledge", json={"title": "归档知识"}).json()
    assert member_client.put(f"/api/team/knowledge/{knowledge['id']}", json={"title": "越权"}).status_code == 403
    assert member_client.post(f"/api/team/knowledge/{knowledge['id']}/archive").status_code == 403
    assert outsider_client.get(f"/api/team/knowledge/{knowledge['id']}").status_code == 404
    assert client.post(f"/api/team/knowledge/{knowledge['id']}/archive").json()["status"] == "ARCHIVED"
    assert member_client.get(f"/api/team/knowledge/{knowledge['id']}").status_code == 404
    assert client.post(f"/api/team/knowledge/{knowledge['id']}/restore").json()["status"] == "PUBLISHED"

    # Leaving the team revokes both knowledge and team-bound live shares.
    shared_source = client.post("/api/notes", json={"title": "团队内分享"}).json()
    assert client.post(f"/api/notes/{shared_source['id']}/shares", json={"userIds": [member.id]}).status_code == 201
    assert member_client.get(f"/api/shared/notes/{shared_source['id']}").status_code == 200
    assert client.delete(f"/api/teams/{team_id}/members/{member.id}").status_code == 204
    assert member_client.get(f"/api/shared/notes/{shared_source['id']}").status_code == 404
    assert member_client.get(f"/api/team/knowledge/{knowledge['id']}").status_code == 404
    assert outsider.id != member.id


def test_submission_rejects_forged_private_file_reference(client: TestClient, db) -> None:
    _team_id, _member, outsider, member_client, _outsider_client = setup_team(client, db)
    private = Note(
        owner_id=outsider.id,
        title="别人私有文件容器",
        content_json={"type": "doc", "content": []},
        plain_text="",
    )
    db.add(private)
    db.commit()
    from app.models.note import Attachment
    attachment = Attachment(
        owner_id=outsider.id,
        note_id=private.id,
        original_name="secret.txt",
        storage_name="forged-secret.txt",
        mime_type="text/plain",
        size=6,
        file_path="data/files/not-created-for-forged-test.txt",
    )
    db.add(attachment)
    db.commit()
    malicious = member_client.post("/api/notes", json={
        "title": "恶意引用",
        "contentJson": {"type": "doc", "content": [{"type": "file", "attrs": {"fileId": attachment.id}}]},
    }).json()
    response = member_client.post(f"/api/notes/{malicious['id']}/submissions", json={"type": "CREATE"})
    assert response.status_code == 403
    assert db.scalar(select(func.count(TeamNoteSubmission.id))) == 0


def test_knowledge_attachment_survives_personal_detach_and_copy_is_independent(
    client: TestClient, db, tmp_path
) -> None:
    settings = Settings(files_dir=tmp_path / "data" / "files")
    client.app.dependency_overrides[get_settings] = lambda: settings
    team_id, member, _outsider, member_client, _outsider_client = setup_team(client, db)
    source = client.post("/api/notes", json={"title": "知识附件来源"}).json()
    attachment_id = "90000000-0000-0000-0000-000000000099"
    source_file = settings.files_dir / "knowledge-source.pdf"
    source_file.parent.mkdir(parents=True, exist_ok=True)
    source_file.write_bytes(b"knowledge binary")
    db.add(Attachment(
        id=attachment_id,
        owner_id="20000000-0000-0000-0000-000000000001",
        note_id=source["id"],
        original_name="knowledge-source.pdf",
        storage_name="knowledge-source.pdf",
        mime_type="application/pdf",
        size=16,
        file_path="data/files/knowledge-source.pdf",
    ))
    db.commit()
    content = {"type": "doc", "content": [{
        "type": "file", "attrs": {"fileId": attachment_id, "src": f"/api/attachments/{attachment_id}"},
    }]}
    knowledge_response = client.post("/api/team/knowledge", json={
        "title": "稳定附件知识", "contentJson": content, "attachmentIds": [attachment_id],
    })
    assert knowledge_response.status_code == 201, knowledge_response.text
    knowledge = knowledge_response.json()

    # Removing the attachment from the personal source only detaches it; the
    # published team resource keeps its own reference and access grant.
    assert client.delete(f"/api/attachments/{attachment_id}").status_code == 204
    assert member_client.get(f"/api/attachments/{attachment_id}").content == b"knowledge binary"

    copied_response = member_client.post(f"/api/team/knowledge/{knowledge['id']}/copy")
    assert copied_response.status_code == 201, copied_response.text
    copied = copied_response.json()
    copied_attachments = member_client.get("/api/attachments", params={"note_id": copied["id"]}).json()
    assert len(copied_attachments) == 1
    copied_id = copied_attachments[0]["id"]
    assert copied_id != attachment_id
    assert copied["contentJson"]["content"][0]["attrs"]["fileId"] == copied_id
    assert member_client.get(f"/api/attachments/{copied_id}").content == b"knowledge binary"
    assert copied["copiedFromTeamNoteId"] == knowledge["id"]

    assert client.delete(f"/api/teams/{team_id}/members/{member.id}").status_code == 204
    assert member_client.get(f"/api/attachments/{attachment_id}").status_code == 404
    # Leaving a team revokes team capabilities only; the independent personal
    # copy and its cloned binary remain the member's own asset.
    assert member_client.get(f"/api/attachments/{copied_id}").content == b"knowledge binary"


def test_only_managers_can_maintain_knowledge_categories(client: TestClient, db) -> None:
    _team_id, _member, _outsider, member_client, _outsider_client = setup_team(client, db)
    category = client.post("/api/team/knowledge/categories", json={"name": "旧分类"})
    assert category.status_code == 201, category.text
    category_id = category.json()["id"]
    assert member_client.put(
        f"/api/team/knowledge/categories/{category_id}", json={"name": "越权修改"}
    ).status_code == 403
    renamed = client.put(f"/api/team/knowledge/categories/{category_id}", json={"name": "新分类"})
    assert renamed.status_code == 200
    assert renamed.json()["name"] == "新分类"
    knowledge = client.post("/api/team/knowledge", json={
        "title": "分类下知识", "categoryId": category_id,
    }).json()
    assert member_client.delete(f"/api/team/knowledge/categories/{category_id}").status_code == 403
    assert client.delete(f"/api/team/knowledge/categories/{category_id}").status_code == 204
    assert client.get(f"/api/team/knowledge/{knowledge['id']}").json()["categoryId"] is None


def test_knowledge_search_and_related_suggestions_cover_content_category_and_tags(
    client: TestClient, db
) -> None:
    _team_id, _member, _outsider, member_client, _outsider_client = setup_team(client, db)
    category = client.post("/api/team/knowledge/categories", json={"name": "技术开发"}).json()
    existing = client.post("/api/team/knowledge", json={
        "title": "Tiptap 开发规范",
        "plainText": "包含唯一正文关键词 ProseMirrorBridge",
        "categoryId": category["id"],
        "tags": ["VueRichText"],
    }).json()
    for query in ("Tiptap", "ProseMirrorBridge", "技术开发", "VueRichText"):
        result = client.get("/api/team/knowledge", params={"q": query})
        assert result.status_code == 200
        assert [item["id"] for item in result.json()] == [existing["id"]]

    source = member_client.post("/api/notes", json={
        "title": "Tiptap 使用经验", "plainText": "投稿正文",
    }).json()
    submission = member_client.post(f"/api/notes/{source['id']}/submissions", json={
        "type": "CREATE", "categoryId": category["id"], "tags": ["VueRichText"],
    }).json()
    related = client.get(f"/api/note-submissions/{submission['id']}/related")
    assert related.status_code == 200
    assert existing["id"] in [item["id"] for item in related.json()]


def test_submission_file_remains_available_to_reviewer_and_team_after_source_detach(
    client: TestClient, db, tmp_path
) -> None:
    settings = Settings(files_dir=tmp_path / "data" / "files")
    client.app.dependency_overrides[get_settings] = lambda: settings
    _team_id, member, _outsider, member_client, _outsider_client = setup_team(client, db)
    attachment_id = "90000000-0000-0000-0000-000000000199"
    source = member_client.post("/api/notes", json={
        "title": "投稿文件来源",
        "contentJson": {"type": "doc", "content": [{
            "type": "file", "attrs": {"fileId": attachment_id},
        }]},
    }).json()
    source_file = settings.files_dir / "submission-proof.txt"
    source_file.parent.mkdir(parents=True, exist_ok=True)
    source_file.write_bytes(b"submission snapshot binary")
    db.add(Attachment(
        id=attachment_id,
        owner_id=member.id,
        note_id=source["id"],
        original_name="submission-proof.txt",
        storage_name="submission-proof.txt",
        mime_type="text/plain",
        size=26,
        file_path="data/files/submission-proof.txt",
    ))
    db.commit()
    submission = member_client.post(
        f"/api/notes/{source['id']}/submissions", json={"type": "CREATE"}
    )
    assert submission.status_code == 201, submission.text

    assert member_client.delete(f"/api/attachments/{attachment_id}").status_code == 204
    assert client.get(f"/api/attachments/{attachment_id}").content == b"submission snapshot binary"
    approved = client.post(
        f"/api/note-submissions/{submission.json()['id']}/approve", json={}
    )
    assert approved.status_code == 200, approved.text
    assert member_client.get(f"/api/attachments/{attachment_id}").content == b"submission snapshot binary"
