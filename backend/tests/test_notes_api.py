from fastapi.testclient import TestClient


def test_note_create_update_search_and_folder_delete_protection(client: TestClient) -> None:
    folder = client.post("/api/folders", json={"name": "项目资料"}).json()
    note = client.post(
        "/api/notes",
        json={
            "folderId": folder["id"],
            "title": "接口治理方案",
            "contentJson": {"type": "doc", "content": [{"type": "paragraph"}]},
            "plainText": "需要确认历史数据处理方式",
        },
    )

    assert note.status_code == 201
    note_id = note.json()["id"]
    assert client.delete(f"/api/folders/{folder['id']}").status_code == 409
    assert [item["id"] for item in client.get("/api/notes?q=历史数据").json()] == [note_id]

    updated = client.put(f"/api/notes/{note_id}", json={"title": "接口治理方案 v2", "folderId": None})
    assert updated.json()["title"] == "接口治理方案 v2"
    assert updated.json()["folderId"] is None

    assert client.delete(f"/api/folders/{folder['id']}").status_code == 204
    assert client.delete(f"/api/notes/{note_id}").status_code == 204
    assert client.get(f"/api/notes/{note_id}").status_code == 404


def test_create_note_from_builtin_template(client: TestClient) -> None:
    templates = client.get("/api/note-templates").json()

    assert [item["name"] for item in templates] == ["空白笔记", "需求分析", "技术方案", "材料阅读", "会议记录", "问题分析"]
    note = client.post(f"/api/notes/from-template/{templates[1]['id']}")
    assert note.status_code == 201
    assert note.json()["title"] == "需求分析"
    assert note.json()["contentJson"]["content"][0]["type"] == "heading"
    assert "背景" in note.json()["plainText"]
    assert [item["id"] for item in client.get("/api/notes?q=背景").json()] == [note.json()["id"]]


def test_attachment_upload_download_and_delete(client: TestClient) -> None:
    note = client.post("/api/notes", json={"title": "附件测试"}).json()
    uploaded = client.post(
        "/api/attachments",
        data={"noteId": note["id"]},
        files={"file": ("readme.txt", b"hello workfollow", "text/plain")},
    )

    assert uploaded.status_code == 201
    attachment = uploaded.json()
    assert attachment["originalName"] == "readme.txt"
    assert attachment["storageName"] != "readme.txt"
    assert client.get(attachment["url"]).content == b"hello workfollow"
    assert len(client.get(f"/api/attachments?note_id={note['id']}").json()) == 1

    assert client.delete(f"/api/attachments/{attachment['id']}").status_code == 204
    assert client.get(attachment["url"]).status_code == 404


def test_soft_deleted_note_revokes_attachment_url(client: TestClient) -> None:
    note = client.post("/api/notes", json={"title": "隐私测试"}).json()
    uploaded = client.post(
        "/api/attachments",
        data={"noteId": note["id"]},
        files={"file": ("private.txt", b"private", "text/plain")},
    ).json()

    assert client.delete(f"/api/notes/{note['id']}").status_code == 204
    assert client.get(uploaded["url"]).status_code == 404


def test_personal_note_copy_clones_attachment_and_keeps_folder(client: TestClient) -> None:
    folder = client.post("/api/folders", json={"name": "副本目录"}).json()
    source = client.post("/api/notes", json={"title": "待复制笔记", "folderId": folder["id"]}).json()
    uploaded = client.post(
        "/api/attachments",
        data={"noteId": source["id"]},
        files={"file": ("copy-source.txt", b"personal copy", "text/plain")},
    ).json()
    content = {"type": "doc", "content": [{
        "type": "file", "attrs": {
            "fileId": uploaded["id"], "src": uploaded["url"],
        },
    }]}
    assert client.put(f"/api/notes/{source['id']}", json={"contentJson": content}).status_code == 200

    copied_response = client.post(f"/api/notes/{source['id']}/copy")
    assert copied_response.status_code == 201, copied_response.text
    copied = copied_response.json()
    copied_files = client.get("/api/attachments", params={"note_id": copied["id"]}).json()
    assert copied["title"] == "待复制笔记 副本"
    assert copied["folderId"] == folder["id"]
    assert copied["copiedFromNoteId"] == source["id"]
    assert copied_files[0]["id"] != uploaded["id"]
    assert copied["contentJson"]["content"][0]["attrs"]["fileId"] == copied_files[0]["id"]

    assert client.delete(f"/api/attachments/{uploaded['id']}").status_code == 204
    assert client.get(copied_files[0]["url"]).content == b"personal copy"
    assert client.delete(f"/api/attachments/{copied_files[0]['id']}").status_code == 204
