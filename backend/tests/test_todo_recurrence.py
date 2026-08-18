from datetime import datetime

import pytest

from app.models.todo import RecurrenceType, Todo, TodoStatus
from app.schemas.todo import TodoCreate
from app.services.todo_service import calculate_next_due, complete_todo, create_todo, restore_todo


@pytest.mark.parametrize(
    ("recurrence_type", "config", "due_at", "expected"),
    [
        (RecurrenceType.DAILY, None, datetime(2026, 8, 8, 9), datetime(2026, 8, 9, 9)),
        (
            RecurrenceType.WEEKLY,
            {"weekday": 4},
            datetime(2026, 8, 14, 18),
            datetime(2026, 8, 21, 18),
        ),
        (
            RecurrenceType.MONTHLY,
            {"day": 10},
            datetime(2026, 8, 10, 9, 30),
            datetime(2026, 9, 10, 9, 30),
        ),
        (
            RecurrenceType.MONTHLY,
            {"day": 31},
            datetime(2027, 1, 31, 9),
            datetime(2027, 2, 28, 9),
        ),
    ],
)
def test_calculate_next_due(
    recurrence_type: RecurrenceType,
    config: dict[str, int] | None,
    due_at: datetime,
    expected: datetime,
) -> None:
    todo = Todo(title="测试", recurrence_type=recurrence_type, recurrence_config=config, due_at=due_at)

    assert calculate_next_due(todo) == expected


def test_restore_removes_generated_occurrence_and_allows_one_new_occurrence(db, user_id) -> None:  # noqa: ANN001
    todo = create_todo(
        db,
        TodoCreate(
            title="每周复盘",
            recurrence_type=RecurrenceType.WEEKLY,
            recurrence_config={"weekday": 4},
            due_at=datetime(2026, 8, 7, 18),
        ),
        user_id,
    )

    completed, next_todo = complete_todo(db, todo, user_id)
    assert completed.status.value == "DONE"
    assert next_todo is not None
    first_next_id = next_todo.id

    restore_todo(db, completed, user_id)
    assert db.get(Todo, first_next_id) is None
    assert len(db.query(Todo).all()) == 1

    _, replacement = complete_todo(db, completed, user_id)
    assert replacement is not None
    assert replacement.id != first_next_id
    assert len(db.query(Todo).all()) == 2


def test_complete_is_idempotent_when_generated_child_already_exists(db, user_id) -> None:  # noqa: ANN001
    todo = create_todo(
        db,
        TodoCreate(
            title="每日同步",
            recurrence_type=RecurrenceType.DAILY,
            due_at=datetime(2026, 8, 8, 9),
        ),
        user_id,
    )

    _, first = complete_todo(db, todo, user_id)
    _, second = complete_todo(db, todo, user_id)
    assert first is not None and second is not None
    assert first.id == second.id
    assert len(db.query(Todo).all()) == 2


def test_restore_keeps_completed_history_but_cancels_future_branch(db, user_id) -> None:  # noqa: ANN001
    todo = create_todo(
        db,
        TodoCreate(
            title="每周复盘",
            recurrence_type=RecurrenceType.WEEKLY,
            due_at=datetime(2026, 8, 7, 18),
        ),
        user_id,
    )

    _, first_next = complete_todo(db, todo, user_id)
    assert first_next is not None
    _, second_next = complete_todo(db, first_next, user_id)
    assert second_next is not None

    restore_todo(db, todo, user_id)
    assert db.get(Todo, first_next.id) is not None
    assert db.get(Todo, first_next.id).status == TodoStatus.DONE
    assert db.get(Todo, second_next.id) is None

    _, replacement = complete_todo(db, todo, user_id)
    assert replacement is not None
    assert replacement.id != first_next.id
