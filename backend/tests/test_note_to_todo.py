from fastapi.testclient import TestClient


def test_create_todo_from_note_selection(client: TestClient) -> None:
    note = client.post(
        "/api/notes",
        json={"title": "流程优化分析", "plainText": "历史数据处理方式需要业务确认"},
    ).json()

    todo = client.post(
        "/api/todos",
        json={
            "title": "历史数据处理方式需要业务确认",
            "sourceType": "NOTE",
            "sourceNoteId": note["id"],
            "sourceExcerpt": "历史数据处理方式需要业务确认",
        },
    )

    assert todo.status_code == 201
    assert todo.json()["sourceType"] == "NOTE"
    assert todo.json()["sourceNoteId"] == note["id"]
    assert todo.json()["sourceExcerpt"] == "历史数据处理方式需要业务确认"

