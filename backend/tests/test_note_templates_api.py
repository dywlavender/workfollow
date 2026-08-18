from fastapi.testclient import TestClient

from app.main import app


EMPTY_DOCUMENT = {"type": "doc", "content": [{"type": "paragraph"}]}


def create_other_user_client() -> TestClient:
    other = TestClient(app)
    response = other.post(
        "/api/auth/register",
        json={"username": "other-template-user", "password": "other-template-password"},
    )
    assert response.status_code == 201, response.text
    return other


def test_personal_template_crud_and_duplicate_validation(client: TestClient) -> None:
    created = client.post(
        "/api/note-templates",
        json={
            "name": "周报",
            "description": "每周工作总结",
            "contentJson": EMPTY_DOCUMENT,
            "sortOrder": 100,
        },
    )
    assert created.status_code == 201, created.text
    template = created.json()
    assert template["isBuiltin"] is False
    assert template["ownerId"]
    assert template["description"] == "每周工作总结"

    duplicate = client.post("/api/note-templates", json={"name": "周报", "contentJson": EMPTY_DOCUMENT})
    assert duplicate.status_code == 409
    assert client.post("/api/note-templates", json={"name": "   "}).status_code == 422
    assert client.post(
        "/api/note-templates",
        json={"name": "非法正文", "contentJson": {"type": "paragraph"}},
    ).status_code == 422
    assert client.put(
        f"/api/note-templates/{template['id']}",
        json={"contentJson": None},
    ).status_code == 422

    updated = client.put(
        f"/api/note-templates/{template['id']}",
        json={"name": "项目周报", "description": "项目组每周总结", "sortOrder": 20},
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["name"] == "项目周报"
    assert updated.json()["sortOrder"] == 20

    listed = client.get("/api/note-templates")
    assert listed.status_code == 200
    assert [item["name"] for item in listed.json() if not item["isBuiltin"]] == ["项目周报"]

    assert client.delete(f"/api/note-templates/{template['id']}").status_code == 204
    assert template["id"] not in {item["id"] for item in client.get("/api/note-templates").json()}
    recreated = client.post("/api/note-templates", json={"name": "项目周报", "contentJson": EMPTY_DOCUMENT})
    assert recreated.status_code == 201, recreated.text


def test_builtin_templates_are_read_only(client: TestClient) -> None:
    builtin = next(item for item in client.get("/api/note-templates").json() if item["isBuiltin"])

    assert client.put(f"/api/note-templates/{builtin['id']}", json={"name": "被禁止"}).status_code == 403
    assert client.delete(f"/api/note-templates/{builtin['id']}").status_code == 403
    assert client.get("/api/note-templates").json()[0]["ownerId"] is None


def test_template_access_isolated_between_users(client: TestClient) -> None:
    personal = client.post("/api/note-templates", json={"name": "私有模板", "contentJson": EMPTY_DOCUMENT}).json()
    other = create_other_user_client()
    try:
        other_templates = other.get("/api/note-templates")
        assert other_templates.status_code == 200
        assert personal["id"] not in {item["id"] for item in other_templates.json()}
        assert other.put(f"/api/note-templates/{personal['id']}", json={"name": "越权修改"}).status_code == 404
        assert other.delete(f"/api/note-templates/{personal['id']}").status_code == 404
        assert other.post(f"/api/notes/from-template/{personal['id']}").status_code == 404
    finally:
        other.close()


def test_save_from_note_and_template_copy_survive_template_changes(client: TestClient) -> None:
    source = client.post(
        "/api/notes",
        json={
            "title": "可保存为模板的笔记",
            "contentJson": {"type": "doc", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "原始正文"}]}]},
        },
    ).json()
    saved = client.post(
        f"/api/note-templates/from-note/{source['id']}",
        json={"name": "从笔记复制", "description": "来源笔记模板"},
    )
    assert saved.status_code == 201, saved.text
    template = saved.json()
    assert template["contentJson"] == source["contentJson"]

    created_note = client.post(f"/api/notes/from-template/{template['id']}")
    assert created_note.status_code == 201, created_note.text
    copied_content = created_note.json()["contentJson"]

    changed_content = {"type": "doc", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "模板已修改"}]}]}
    assert client.put(f"/api/note-templates/{template['id']}", json={"contentJson": changed_content}).status_code == 200
    assert client.delete(f"/api/note-templates/{template['id']}").status_code == 204

    still_there = client.get(f"/api/notes/{created_note.json()['id']}")
    assert still_there.status_code == 200
    assert still_there.json()["contentJson"] == copied_content
    assert still_there.json()["contentJson"] != changed_content

    other = create_other_user_client()
    try:
        assert other.post(
            f"/api/note-templates/from-note/{source['id']}",
            json={"name": "无权来源"},
        ).status_code == 404
    finally:
        other.close()
