from datetime import date, datetime, timedelta

from fastapi.testclient import TestClient


def test_todo_crud_and_smart_views(client: TestClient) -> None:
    today = date.today()
    due_at = datetime.combine(today, datetime.min.time()).replace(hour=15)
    scheduled = client.post(
        "/api/todos",
        json={"title": "今天完成接口", "dueAt": due_at.isoformat(), "priority": "HIGH"},
    )
    unscheduled = client.post("/api/todos", json={"title": "研究执行计划"})

    assert scheduled.status_code == 201
    assert unscheduled.status_code == 201
    assert unscheduled.json()["dueAt"] is None
    assert {todo["title"] for todo in client.get("/api/todos?view=today").json()} == {"今天完成接口"}
    assert {todo["title"] for todo in client.get("/api/todos?view=inbox").json()} == {"研究执行计划"}

    todo_id = scheduled.json()["id"]
    updated = client.put(f"/api/todos/{todo_id}", json={"description": "接口说明", "priority": "MEDIUM"})
    assert updated.json()["description"] == "接口说明"
    assert updated.json()["priority"] == "MEDIUM"

    completed = client.post(f"/api/todos/{todo_id}/complete")
    assert completed.json()["todo"]["status"] == "DONE"
    assert len(client.get("/api/todos?view=completed").json()) == 1

    assert client.post(f"/api/todos/{todo_id}/restore").json()["status"] == "TODO"
    assert client.delete(f"/api/todos/{todo_id}").status_code == 204
    assert client.get(f"/api/todos/{todo_id}").status_code == 404


def test_todo_search_is_scoped_to_current_view(client: TestClient) -> None:
    today = datetime.combine(date.today(), datetime.min.time()).replace(hour=16)
    client.post("/api/todos", json={"title": "整理季度报告", "dueAt": today.isoformat()})
    reading = client.post("/api/todos", json={"title": "整理阅读清单"}).json()
    checkup = client.post("/api/todos", json={"title": "预约体检", "description": "整理检查材料"}).json()
    client.put(f"/api/todos/{reading['id']}", json={"dueAt": None})
    client.put(f"/api/todos/{checkup['id']}", json={"dueAt": None})

    today_results = client.get("/api/todos", params={"view": "today", "q": "整理"}).json()
    inbox_results = client.get("/api/todos", params={"view": "inbox", "q": "整理"}).json()

    assert [todo["title"] for todo in today_results] == ["整理季度报告"]
    assert {todo["title"] for todo in inbox_results} == {"整理阅读清单", "预约体检"}


def test_task_content_json_is_authoritative_and_searchable(client: TestClient) -> None:
    created = client.post("/api/todos", json={"title": "结构化正文"}).json()
    content = {
        "type": "doc",
        "content": [{"type": "paragraph", "content": [{"type": "text", "text": "校验清单内容"}]}],
    }

    updated = client.put(f"/api/todos/{created['id']}", json={"contentJson": content, "description": "过期 HTML"})

    assert updated.status_code == 200
    assert updated.json()["contentJson"] == content
    assert updated.json()["description"] == "校验清单内容"
    assert [item["id"] for item in client.get("/api/todos", params={"view": "inbox", "q": "校验清单"}).json()] == [created["id"]]


def test_all_view_orders_every_todo_by_due_at_descending(client: TestClient) -> None:
    early = client.post(
        "/api/todos",
        json={"title": "较早到期", "dueAt": "2026-08-10T09:00:00"},
    ).json()
    client.post(
        "/api/todos",
        json={"title": "较晚到期", "dueAt": "2026-08-12T18:00:00"},
    )
    unscheduled = client.post("/api/todos", json={"title": "没有日期"}).json()
    client.put(f"/api/todos/{unscheduled['id']}", json={"dueAt": None})
    client.post(f"/api/todos/{early['id']}/complete")

    results = client.get("/api/todos", params={"view": "all"})

    assert results.status_code == 200
    assert [todo["title"] for todo in results.json()] == ["较晚到期", "较早到期", "没有日期"]
    assert results.json()[1]["status"] == "DONE"


def test_smart_view_includes_overdue_and_current_period_terminal_states(client: TestClient) -> None:
    today = date.today()
    yesterday = datetime.combine(today - timedelta(days=1), datetime.min.time())
    today_due = datetime.combine(today, datetime.min.time())

    overdue = client.post("/api/todos", json={"title": "逾期未完成", "dueAt": yesterday.isoformat()}).json()
    active = client.post("/api/todos", json={"title": "今天待办", "dueAt": today_due.isoformat()}).json()
    done = client.post("/api/todos", json={"title": "今天完成", "dueAt": today_due.isoformat()}).json()
    abandoned = client.post("/api/todos", json={"title": "今天放弃", "dueAt": today_due.isoformat()}).json()

    client.post(f"/api/todos/{done['id']}/complete")
    abandoned_response = client.post(f"/api/todos/{abandoned['id']}/abandon")
    assert abandoned_response.status_code == 200
    assert abandoned_response.json()["status"] == "ABANDONED"

    today_results = client.get("/api/todos", params={"view": "today"}).json()
    assert {todo["id"] for todo in today_results} == {overdue["id"], active["id"], done["id"], abandoned["id"]}
    assert {todo["status"] for todo in client.get("/api/todos", params={"view": "completed"}).json()} == {"DONE", "ABANDONED"}

    restored = client.post(f"/api/todos/{abandoned['id']}/restore")
    assert restored.status_code == 200
    assert restored.json()["status"] == "TODO"


def test_due_reminder_is_acknowledged(client: TestClient) -> None:
    now = datetime.now().replace(microsecond=0)
    response = client.post(
        "/api/todos",
        json={
            "title": "提醒任务",
            "dueAt": (now + timedelta(minutes=10)).isoformat(),
            "reminderAt": (now - timedelta(minutes=1)).isoformat(),
        },
    )
    todo_id = response.json()["id"]

    due = client.get("/api/todos/reminders/due").json()
    assert [todo["id"] for todo in due] == [todo_id]

    acknowledged = client.post(f"/api/todos/{todo_id}/reminded", json={})
    assert acknowledged.json()["remindedAt"] is not None
    assert client.get("/api/todos/reminders/due").json() == []


def test_reminder_cannot_be_later_than_due_at(client: TestClient) -> None:
    response = client.post(
        "/api/todos",
        json={
            "title": "时间校验",
            "dueAt": "2026-08-08T10:00:00",
            "reminderAt": "2026-08-08T11:00:00",
        },
    )
    assert response.status_code == 422

    todo = client.post(
        "/api/todos",
        json={"title": "可更新提醒", "dueAt": "2026-08-08T10:00:00"},
    ).json()
    updated = client.put(
        f"/api/todos/{todo['id']}",
        json={"reminderAt": "2026-08-08T11:00:00"},
    )
    assert updated.status_code == 422


def test_task_range_list_and_tags_share_one_persisted_state(client: TestClient) -> None:
    created = client.post(
        "/api/todos",
        json={
            "title": "发布版本",
            "dueAt": "2026-08-10T09:30:00",
            "dueEndAt": "2026-08-12T09:30:00",
            "listName": "工作",
            "tags": ["发布", "发布", " P0 "],
        },
    )
    assert created.status_code == 201
    task = created.json()
    assert task["dueEndAt"] == "2026-08-12T09:30:00"
    assert task["listName"] == "工作"
    assert task["tags"] == ["发布", "P0"]
    assert [item["id"] for item in client.get("/api/todos", params={"list": "工作"}).json()] == [task["id"]]
    assert client.get("/api/todos", params={"list": "个人"}).json() == []

    updated = client.put(
        f"/api/todos/{task['id']}",
        json={"dueAt": None, "dueEndAt": None, "listName": "个人", "tags": ["生活"]},
    )
    assert updated.status_code == 200
    assert updated.json()["dueAt"] is None
    assert updated.json()["dueEndAt"] is None
    assert updated.json()["listName"] == "个人"
    assert updated.json()["tags"] == ["生活"]
    assert [item["id"] for item in client.get("/api/todos", params={"list": "个人"}).json()] == [task["id"]]

    invalid = client.post(
        "/api/todos",
        json={"title": "错误区间", "dueAt": "2026-08-12T10:00:00", "dueEndAt": "2026-08-11T10:00:00"},
    )
    assert invalid.status_code == 422


def test_restoring_recurring_todo_cancels_its_generated_next_instance(client: TestClient) -> None:
    created = client.post(
        "/api/todos",
        json={
            "title": "重复待办",
            "dueAt": "2026-08-08T09:00:00",
            "recurrenceType": "DAILY",
        },
    )
    assert created.status_code == 201
    todo_id = created.json()["id"]

    completed = client.post(f"/api/todos/{todo_id}/complete").json()
    next_id = completed["nextTodo"]["id"]
    assert client.get(f"/api/todos/{next_id}").status_code == 200

    assert client.post(f"/api/todos/{todo_id}/restore").status_code == 200
    assert client.get(f"/api/todos/{next_id}").status_code == 404

    completed_again = client.post(f"/api/todos/{todo_id}/complete").json()
    assert completed_again["nextTodo"] is not None
    assert completed_again["nextTodo"]["id"] != next_id
