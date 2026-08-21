from fastapi.testclient import TestClient

from app.core.config import Settings, get_settings
from app.api.routes.notes import router as notes_router


def test_static_markdown_import_route_precedes_note_id_route() -> None:
    paths = [route.path for route in notes_router.routes]

    assert paths.index("/notes/import-markdown") < paths.index("/notes/{note_id}")


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


def test_import_markdown_creates_independent_editable_note(client: TestClient) -> None:
    current = client.post("/api/notes", json={"title": "当前笔记", "plainText": "原有内容"}).json()
    folder = client.post("/api/folders", json={"name": "导入资料"}).json()
    markdown = (
        "---\n"
        "title: Markdown 标题\n"
        "---\n"
        "# 正文标题\n\n"
        "这是 **重点** 和 [参考链接](https://example.com)。\n\n"
        "- [ ] 待处理\n"
        "- [x] 已完成\n\n"
        "> 引用内容\n\n"
        "```python\nprint('ok')\n```\n\n"
        "| 名称 | 状态 |\n| --- | --- |\n| A | 通过 |\n"
    )

    imported = client.post(
        "/api/notes/import-markdown",
        data={"folderId": folder["id"]},
        files={"file": ("report.md", markdown.encode("utf-8"), "text/markdown")},
    )

    assert imported.status_code == 201, imported.text
    note = imported.json()
    assert note["id"] != current["id"]
    assert note["title"] == "Markdown 标题"
    assert note["folderId"] == folder["id"]
    assert "重点" in note["plainText"]
    assert note["contentJson"]["content"][0]["type"] == "heading"
    assert note["contentJson"]["content"][2]["type"] == "taskList"
    assert note["contentJson"]["content"][2]["content"][1]["attrs"]["checked"] is True
    assert note["contentJson"]["content"][5]["type"] == "table"
    assert client.get(f"/api/notes/{current['id']}").json()["plainText"] == "原有内容"


def test_import_markdown_validates_extension_encoding_and_title_override(client: TestClient) -> None:
    unsupported = client.post(
        "/api/notes/import-markdown",
        files={"file": ("report.txt", b"# title", "text/plain")},
    )
    assert unsupported.status_code == 415

    invalid_encoding = client.post(
        "/api/notes/import-markdown",
        data={"title": "手动标题"},
        files={"file": ("report.md", b"\xff\xfe", "text/markdown")},
    )
    assert invalid_encoding.status_code == 422

    oversized = client.post(
        "/api/notes/import-markdown",
        files={"file": ("large.md", b"a" * (5 * 1024 * 1024 + 1), "text/markdown")},
    )
    assert oversized.status_code == 413

    overridden = client.post(
        "/api/notes/import-markdown",
        data={"title": "用户指定标题"},
        files={"file": ("report.markdown", "# 文件标题\n\n正文".encode("utf-8"), "text/markdown")},
    )
    assert overridden.status_code == 201
    assert overridden.json()["title"] == "用户指定标题"


def test_import_markdown_does_not_keep_unsafe_links_or_local_images(client: TestClient) -> None:
    imported = client.post(
        "/api/notes/import-markdown",
        files={
            "file": (
                "safe.md",
                "[危险](javascript:alert(1))\n\n![本地图片](./images/a.png)".encode("utf-8"),
                "text/markdown",
            )
        },
    )

    assert imported.status_code == 201
    document = imported.json()["contentJson"]
    assert not any(mark.get("type") == "link" for node in document["content"][0].get("content", []) for mark in node.get("marks", []))
    assert "[图片：本地图片]" in imported.json()["plainText"]


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


def test_removed_embedded_image_is_cleaned_but_standalone_file_remains(
    client: TestClient, tmp_path
) -> None:
    settings = Settings(files_dir=tmp_path / "data" / "files")
    client.app.dependency_overrides[get_settings] = lambda: settings
    note = client.post("/api/notes", json={"title": "正文图片清理"}).json()
    image = client.post(
        "/api/attachments",
        data={"noteId": note["id"]},
        files={"file": ("pasted.png", b"image-bytes", "image/png")},
    ).json()
    document = {
        "type": "doc",
        "content": [{"type": "image", "attrs": {
            "src": image["url"], "alt": "pasted.png", "attachmentId": image["id"],
        }}],
    }
    assert client.put(f"/api/notes/{note['id']}", json={"contentJson": document}).status_code == 200

    standalone = client.post(
        "/api/attachments",
        data={"noteId": note["id"]},
        files={"file": ("reference.txt", b"keep me", "text/plain")},
    ).json()
    assert client.delete(f"/api/attachments/{image['id']}").status_code == 409

    empty_document = {"type": "doc", "content": [{"type": "paragraph"}]}
    assert client.put(
        f"/api/notes/{note['id']}", json={"contentJson": empty_document}
    ).status_code == 200

    remaining = client.get("/api/attachments", params={"note_id": note["id"]}).json()
    assert [item["id"] for item in remaining] == [standalone["id"]]
    assert client.get(image["url"]).status_code == 404
    assert client.get(standalone["url"]).content == b"keep me"
    assert list(settings.files_dir.rglob(image["storageName"])) == []


def test_legacy_src_only_embedded_image_is_cleaned(client: TestClient, tmp_path) -> None:
    settings = Settings(files_dir=tmp_path / "data" / "files")
    client.app.dependency_overrides[get_settings] = lambda: settings
    note = client.post("/api/notes", json={"title": "旧图片正文"}).json()
    image = client.post(
        "/api/attachments",
        data={"noteId": note["id"]},
        files={"file": ("legacy.png", b"legacy-image", "image/png")},
    ).json()
    legacy_document = {
        "type": "doc",
        "content": [{"type": "image", "attrs": {"src": image["url"]}}],
    }
    assert client.put(
        f"/api/notes/{note['id']}", json={"contentJson": legacy_document}
    ).status_code == 200
    assert client.put(
        f"/api/notes/{note['id']}",
        json={"contentJson": {"type": "doc", "content": [{"type": "paragraph"}]}},
    ).status_code == 200
    assert client.get(image["url"]).status_code == 404


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
