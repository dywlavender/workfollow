from fastapi.testclient import TestClient
from sqlalchemy import text

from app.models.auth import User, UserStatus
from app.services.auth_service import password_hash


def add_search_user(db, user_id: str, username: str) -> User:
    user = User(
        id=user_id,
        username=username,
        password_hash=password_hash.hash("member-password"),
        nickname=username,
        status=UserStatus.ACTIVE,
    )
    db.add(user)
    db.commit()
    return user


def login_search_user(app, username: str) -> TestClient:
    result = TestClient(app)
    response = result.post("/api/auth/login", json={"identifier": username, "password": "member-password"})
    assert response.status_code == 200, response.text
    return result


def test_personal_search_supports_tags_capture_and_inbox(client: TestClient) -> None:
    captured = client.post(
        "/api/notes/capture",
        json={"text": "会议记录\n确认搜索方案", "tags": ["工作", "工作"]},
    )
    assert captured.status_code == 201, captured.text
    note = captured.json()
    assert note["title"] == "会议记录"
    assert note["tags"] == ["工作"]

    assert client.get("/api/notes", params={"unfiled": True}).json()[0]["id"] == note["id"]
    assert client.get("/api/notes/tags").json() == ["工作"]
    assert client.get("/api/notes/counts").json() == {"unfiled": 1}
    assert client.get("/api/search", params={"q": "搜索方案"}).json()["items"][0]["id"] == note["id"]

    updated = client.put(f"/api/notes/{note['id']}", json={"tags": ["项目"]})
    assert updated.status_code == 200
    assert client.get("/api/notes", params={"tags": "项目"}).json()[0]["id"] == note["id"]
    assert client.get("/api/search", params={"q": "项目"}).json()["items"][0]["id"] == note["id"]


def test_search_does_not_leak_private_notes_or_revoked_shares(client: TestClient, db) -> None:
    target = add_search_user(db, "60000000-0000-0000-0000-000000000001", "search-reader")
    team_id = client.post("/api/teams", json={"name": "搜索权限团队"}).json()["id"]
    assert client.post(
        f"/api/teams/{team_id}/members", json={"identifier": target.username, "role": "MEMBER"}
    ).status_code == 201
    private = client.post("/api/notes", json={"title": "只属于自己的秘密", "plainText": "权限关键词"}).json()
    shared = client.post("/api/notes", json={"title": "可以共享的记录", "plainText": "共享关键词"}).json()
    assert client.post(f"/api/notes/{shared['id']}/shares", json={"identifier": target.username}).status_code == 201
    target_client = login_search_user(client.app, target.username)

    own_results = target_client.get("/api/search", params={"q": "权限关键词"})
    assert own_results.status_code == 200
    assert own_results.json()["items"] == []
    shared_results = target_client.get("/api/search", params={"q": "共享关键词"}).json()["items"]
    assert [item["id"] for item in shared_results] == [shared["id"]]

    assert client.delete(f"/api/notes/{shared['id']}/shares/{target.id}").status_code == 204
    assert target_client.get("/api/search", params={"q": "共享关键词"}).json()["items"] == []


def test_search_input_is_literal_and_two_character_queries_use_fallback(client: TestClient) -> None:
    note = client.post("/api/notes", json={"title": "括号 ( 记录", "plainText": "会议安排"}).json()
    response = client.get("/api/search", params={"q": "会议"})
    assert response.status_code == 200, response.text
    assert response.json()["items"][0]["id"] == note["id"]
    literal = client.get("/api/search", params={"q": "("})
    assert literal.status_code == 200


def test_knowledge_search_is_scoped_to_published_team_content(client: TestClient) -> None:
    team = client.post("/api/teams", json={"name": "统一搜索知识团队"}).json()
    team_id = team["id"]
    created = client.post(
        "/api/team/knowledge",
        params={"teamId": team_id},
        json={"title": "团队检索规范", "plainText": "团队知识关键词", "tags": ["规范"]},
    )
    assert created.status_code == 201, created.text
    result = client.get("/api/search", params={"q": "团队知识关键词", "scope": "knowledge", "teamId": team_id})
    assert result.status_code == 200, result.text
    assert [item["id"] for item in result.json()["items"]] == [created.json()["id"]]

    archived = client.post(
        f"/api/team/knowledge/{created.json()['id']}/archive", params={"teamId": team_id}
    )
    assert archived.status_code == 200, archived.text
    assert client.get("/api/search", params={"q": "团队知识关键词", "scope": "knowledge", "teamId": team_id}).json()["items"] == []


def test_category_changes_refresh_the_knowledge_search_projection(client: TestClient) -> None:
    team_id = client.post("/api/teams", json={"name": "搜索分类同步团队"}).json()["id"]
    category = client.post(
        "/api/team/knowledge/categories", params={"teamId": team_id}, json={"name": "旧分类"}
    ).json()
    note = client.post(
        "/api/team/knowledge",
        params={"teamId": team_id},
        json={"title": "分类同步知识", "categoryId": category["id"]},
    ).json()
    assert [item["id"] for item in client.get("/api/search", params={"q": "旧分类", "scope": "knowledge"}).json()["items"]] == [note["id"]]

    renamed = client.put(
        f"/api/team/knowledge/categories/{category['id']}",
        params={"teamId": team_id},
        json={"name": "新分类"},
    )
    assert renamed.status_code == 200, renamed.text
    assert client.get("/api/search", params={"q": "旧分类", "scope": "knowledge"}).json()["items"] == []
    assert [item["id"] for item in client.get("/api/search", params={"q": "新分类", "scope": "knowledge"}).json()["items"]] == [note["id"]]

    deleted = client.delete(
        f"/api/team/knowledge/categories/{category['id']}", params={"teamId": team_id}
    )
    assert deleted.status_code == 204, deleted.text
    assert client.get("/api/search", params={"q": "新分类", "scope": "knowledge"}).json()["items"] == []


def test_search_uses_fts5_highlight_when_available(client: TestClient, db) -> None:
    db.execute(text(
        "CREATE VIRTUAL TABLE note_search USING fts5("
        "title, body, tags_text, category_name, content='search_documents', "
        "content_rowid='id', tokenize='trigram')"
    ))
    db.execute(text(
        "CREATE TRIGGER search_documents_ai AFTER INSERT ON search_documents BEGIN "
        "INSERT INTO note_search(rowid, title, body, tags_text, category_name) "
        "VALUES (new.id, new.title, new.body, new.tags_text, new.category_name); END"
    ))
    db.execute(text(
        "CREATE TRIGGER search_documents_ad AFTER DELETE ON search_documents BEGIN "
        "INSERT INTO note_search(note_search, rowid, title, body, tags_text, category_name) "
        "VALUES ('delete', old.id, old.title, old.body, old.tags_text, old.category_name); END"
    ))
    db.execute(text(
        "CREATE TRIGGER search_documents_au AFTER UPDATE OF title, body, tags_text, category_name "
        "ON search_documents BEGIN "
        "INSERT INTO note_search(note_search, rowid, title, body, tags_text, category_name) "
        "VALUES ('delete', old.id, old.title, old.body, old.tags_text, old.category_name); "
        "INSERT INTO note_search(rowid, title, body, tags_text, category_name) "
        "VALUES (new.id, new.title, new.body, new.tags_text, new.category_name); END"
    ))
    db.execute(text("INSERT INTO note_search(note_search) VALUES ('rebuild')"))
    db.commit()

    note = client.post("/api/notes", json={"title": "FTS 高亮标题", "plainText": "这是搜索高亮验证正文"}).json()
    result = client.get("/api/search", params={"q": "高亮标题"})
    assert result.status_code == 200, result.text
    item = next(item for item in result.json()["items"] if item["id"] == note["id"])
    assert any(part["matched"] for part in item["excerpt"])
