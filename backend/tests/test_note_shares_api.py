from fastapi.testclient import TestClient

from app.core.config import Settings, get_settings
from app.models.auth import User, UserStatus
from app.models.note import Attachment
from app.services.auth_service import password_hash
from tests.collaboration_helpers import project_note


def add_share_user(db, user_id: str, username: str) -> User:
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


def login_share_user(app, username: str) -> TestClient:
    client = TestClient(app)
    response = client.post(
        "/api/auth/login", json={"identifier": username, "password": "member-password"}
    )
    assert response.status_code == 200, response.text
    return client


def test_note_share_is_live_read_only_and_revocable(client: TestClient, db) -> None:
    target = add_share_user(db, "50000000-0000-0000-0000-000000000001", "reader")
    team_id = client.post("/api/teams", json={"name": "共享团队"}).json()["id"]
    assert client.post(
        f"/api/teams/{team_id}/members", json={"identifier": target.username, "role": "MEMBER"}
    ).status_code == 201
    source = client.post(
        "/api/notes",
        json={
            "title": "实时标题 v1",
            "contentJson": {"type": "doc", "content": []},
            "plainText": "实时内容 v1",
        },
    )
    assert source.status_code == 201
    note_id = source.json()["id"]
    attachment = Attachment(
        id="50000000-0000-0000-0000-000000000010",
        owner_id="20000000-0000-0000-0000-000000000001",
        note_id=note_id,
        original_name="shared.txt",
        storage_name="shared.txt",
        mime_type="text/plain",
        size=5,
        file_path="data/files/shared-file-not-created.txt",
    )
    db.add(attachment)
    db.commit()

    shared = client.post(f"/api/notes/{note_id}/shares", json={"identifier": target.username})
    assert shared.status_code == 201, shared.text
    assert shared.json()["teamId"] == team_id
    share_id = shared.json()["id"]
    assert client.post(f"/api/notes/{note_id}/shares", json={"identifier": target.username}).status_code == 409

    target_client = login_share_user(client.app, target.username)
    shared_list = target_client.get("/api/shared/notes")
    assert shared_list.status_code == 200
    assert shared_list.json()[0]["title"] == "实时标题 v1"
    assert shared_list.json()[0]["attachments"][0]["id"] == attachment.id
    shared_detail = target_client.get(f"/api/shared/notes/{note_id}")
    assert shared_detail.json()["plainText"] == "实时内容 v1"
    assert shared_detail.json()["attachments"][0]["originalName"] == "shared.txt"
    assert target_client.get(f"/api/attachments", params={"note_id": note_id}).status_code == 200
    assert target_client.get(f"/api/attachments/{attachment.id}").json()["detail"] == "Attachment file not found"

    # The shared endpoint reads the same PersonalNote row; it does not copy it.
    assert project_note(
        client,
        note_id,
        title="实时标题 v2",
        content_json={"type": "doc", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "实时内容 v2"}]}]},
    ).status_code == 204
    assert target_client.get(f"/api/shared/notes/{note_id}").json()["title"] == "实时标题 v2"
    assert target_client.put(f"/api/notes/{note_id}/favorite", json={"isFavorite": True}).status_code == 404
    assert target_client.put(f"/api/shared/notes/{note_id}", json={"title": "越权修改"}).status_code == 405

    assert client.delete(f"/api/notes/{note_id}/shares/{share_id}").status_code == 204
    revoked_notifications = target_client.get("/api/notifications", params={"unreadOnly": True}).json()
    assert any(item["type"] == "NOTE_SHARE_REVOKED" for item in revoked_notifications)
    assert client.delete(f"/api/notes/{note_id}/shares/{share_id}").status_code == 404
    assert target_client.get(f"/api/shared/notes/{note_id}").status_code == 404
    assert target_client.get(f"/api/shared/notes").json() == []
    assert target_client.get(f"/api/attachments/{attachment.id}").json()["detail"] == "Attachment not found"


def test_note_cannot_be_shared_to_owner(client: TestClient, user_id: str) -> None:
    note = client.post("/api/notes", json={"title": "禁止自分享"}).json()

    assert client.post(
        f"/api/notes/{note['id']}/shares", json={"identifier": "tester"}
    ).status_code == 422
    assert client.post(
        f"/api/notes/{note['id']}/shares", json={"userIds": [user_id]}
    ).status_code == 422
    assert client.get(f"/api/notes/{note['id']}/shares").json() == []


def test_syncing_share_recipients_can_revoke_access_and_notify(client: TestClient, db) -> None:
    target = add_share_user(db, "50000000-0000-0000-0000-000000000006", "sync-reader")
    team_id = client.post("/api/teams", json={"name": "同步撤销团队"}).json()["id"]
    assert client.post(
        f"/api/teams/{team_id}/members", json={"identifier": target.username, "role": "MEMBER"}
    ).status_code == 201
    note = client.post("/api/notes", json={"title": "同步撤销"}).json()
    target_client = login_share_user(client.app, target.username)

    assert client.post(
        f"/api/notes/{note['id']}/shares", json={"userIds": [target.id]}
    ).status_code == 201
    assert target_client.get(f"/api/shared/notes/{note['id']}").status_code == 200

    assert client.post(
        f"/api/notes/{note['id']}/shares", json={"userIds": []}
    ).status_code == 201
    assert target_client.get(f"/api/shared/notes/{note['id']}").status_code == 404
    notifications = target_client.get("/api/notifications", params={"unreadOnly": True}).json()
    assert any(item["type"] == "NOTE_SHARE_REVOKED" for item in notifications)


def test_only_note_owner_can_create_or_list_shares(client: TestClient, db) -> None:
    target = add_share_user(db, "50000000-0000-0000-0000-000000000002", "reader2")
    note = client.post("/api/notes", json={"title": "私有笔记"}).json()
    # Platform users outside the owner's active team are not valid share targets.
    assert client.post(
        f"/api/notes/{note['id']}/shares", json={"identifier": target.username}
    ).status_code == 422
    target_client = login_share_user(client.app, target.username)
    assert target_client.post(
        f"/api/notes/{note['id']}/shares", json={"identifier": "tester"}
    ).status_code == 404
    assert target_client.get(f"/api/notes/{note['id']}/shares").status_code == 404


def test_copy_shared_note_clones_binary_and_rewrites_content_references(client: TestClient, db, tmp_path) -> None:
    settings = Settings(files_dir=tmp_path / "data" / "files")
    client.app.dependency_overrides[get_settings] = lambda: settings
    target = add_share_user(db, "50000000-0000-0000-0000-000000000003", "copy-reader")
    team_id = client.post("/api/teams", json={"name": "副本团队"}).json()["id"]
    assert client.post(
        f"/api/teams/{team_id}/members", json={"identifier": target.username, "role": "MEMBER"}
    ).status_code == 201

    attachment_id = "50000000-0000-0000-0000-000000000030"
    source = client.post("/api/notes", json={
        "title": "带附件的共享笔记",
        "contentJson": {"type": "doc", "content": [{
            "type": "file", "attrs": {
                "fileId": attachment_id,
                "src": f"/api/attachments/{attachment_id}",
            },
        }]},
    }).json()
    source_file = settings.files_dir / "shared-original.txt"
    source_file.parent.mkdir(parents=True, exist_ok=True)
    source_file.write_text("independent copy", encoding="utf-8")
    db.add(Attachment(
        id=attachment_id,
        owner_id="20000000-0000-0000-0000-000000000001",
        note_id=source["id"],
        original_name="shared-original.txt",
        storage_name="shared-original.txt",
        mime_type="text/plain",
        size=16,
        file_path="data/files/shared-original.txt",
    ))
    db.commit()
    assert client.post(f"/api/notes/{source['id']}/shares", json={"userIds": [target.id]}).status_code == 201

    target_client = login_share_user(client.app, target.username)
    copied_response = target_client.post(f"/api/shared/notes/{source['id']}/copy")
    assert copied_response.status_code == 201, copied_response.text
    copied = copied_response.json()
    copied_attachments = target_client.get("/api/attachments", params={"note_id": copied["id"]}).json()
    assert len(copied_attachments) == 1
    copied_id = copied_attachments[0]["id"]
    assert copied_id != attachment_id
    assert copied["contentJson"]["content"][0]["attrs"]["fileId"] == copied_id
    assert copied["contentJson"]["content"][0]["attrs"]["src"] == f"/api/attachments/{copied_id}"

    assert client.delete(f"/api/attachments/{attachment_id}").status_code == 204
    retained = target_client.get(f"/api/attachments/{copied_id}")
    assert retained.status_code == 200
    assert retained.content == b"independent copy"


def test_share_is_revoked_when_sharer_leaves_team(client: TestClient, db) -> None:
    sharer = add_share_user(db, "50000000-0000-0000-0000-000000000004", "departing-sharer")
    reader = add_share_user(db, "50000000-0000-0000-0000-000000000005", "remaining-reader")
    team_id = client.post("/api/teams", json={"name": "离队分享团队"}).json()["id"]
    assert client.post(
        f"/api/teams/{team_id}/members", json={"identifier": sharer.username, "role": "ADMIN"}
    ).status_code == 201
    assert client.post(
        f"/api/teams/{team_id}/members", json={"identifier": reader.username, "role": "MEMBER"}
    ).status_code == 201
    sharer_client = login_share_user(client.app, sharer.username)
    reader_client = login_share_user(client.app, reader.username)
    note = sharer_client.post("/api/notes", json={"title": "离队前分享"}).json()
    assert sharer_client.post(
        f"/api/notes/{note['id']}/shares", json={"userIds": [reader.id]}
    ).status_code == 201
    assert reader_client.get(f"/api/shared/notes/{note['id']}").status_code == 200

    assert client.delete(f"/api/teams/{team_id}/members/{sharer.id}").status_code == 204
    assert reader_client.get(f"/api/shared/notes/{note['id']}").status_code == 404
    assert reader_client.get("/api/shared/notes").json() == []
