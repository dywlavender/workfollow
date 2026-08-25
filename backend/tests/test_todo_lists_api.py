def test_todo_list_catalog_can_create_rename_and_delete(client) -> None:
    initial = client.get("/api/tasks/lists")
    assert initial.status_code == 200
    assert [item["name"] for item in initial.json()] == ["收集箱", "工作", "个人", "学习"]
    assert all(item["protected"] for item in initial.json())

    created = client.post("/api/tasks/lists", json={"name": "项目"})
    assert created.status_code == 201
    project = created.json()
    assert project["name"] == "项目"
    assert project["protected"] is False

    task = client.post("/api/tasks", json={"title": "项目任务", "listName": "项目"}).json()
    renamed = client.put(f"/api/tasks/lists/{project['id']}", json={"name": "交付"})
    assert renamed.status_code == 200
    assert client.get(f"/api/tasks/{task['id']}").json()["listName"] == "交付"
    assert [item["id"] for item in client.get("/api/tasks", params={"list": "交付"}).json()] == [task["id"]]

    deleted = client.delete(f"/api/tasks/lists/{project['id']}")
    assert deleted.status_code == 200
    assert deleted.json()["movedTaskCount"] == 1
    assert client.get(f"/api/tasks/{task['id']}").json()["listName"] == "收集箱"
    assert all(item["name"] != "交付" for item in client.get("/api/tasks/lists").json())


def test_builtin_todo_lists_cannot_be_renamed_or_deleted(client) -> None:
    builtin = next(item for item in client.get("/api/tasks/lists").json() if item["name"] == "收集箱")
    assert client.put(f"/api/tasks/lists/{builtin['id']}", json={"name": "待整理"}).status_code == 409
    assert client.delete(f"/api/tasks/lists/{builtin['id']}").status_code == 409


def test_todo_list_names_are_unique(client) -> None:
    assert client.post("/api/tasks/lists", json={"name": "工作"}).status_code == 409
    created = client.post("/api/tasks/lists", json={"name": "研究"}).json()
    assert client.post("/api/tasks/lists", json={"name": "研究"}).status_code == 409
    assert client.put(f"/api/tasks/lists/{created['id']}", json={"name": "个人"}).status_code == 409
