from datetime import datetime, timedelta

from sqlalchemy.orm import Session

from app.models.todo import RecurrenceType, TodoStatus
from app.schemas.todo import TodoCreate
from app.services.todo_service import complete_todo, create_todo, restore_todo


def test_complete_and_restore_todo(db: Session, user_id: str) -> None:
    todo = create_todo(db, TodoCreate(title="完成接口"), user_id)

    completed, next_todo = complete_todo(db, todo, user_id)

    assert completed.status == TodoStatus.DONE
    assert completed.completed_at is not None
    assert next_todo is None

    restored = restore_todo(db, completed, user_id)
    assert restored.status == TodoStatus.TODO
    assert restored.completed_at is None


def test_completing_recurring_todo_creates_one_next_instance(db: Session, user_id: str) -> None:
    due_at = datetime(2026, 8, 14, 18)
    todo = create_todo(
        db,
        TodoCreate(
            title="整理周报",
            due_at=due_at,
            reminder_at=due_at - timedelta(hours=1),
            recurrence_type=RecurrenceType.WEEKLY,
            recurrence_config={"weekday": 4},
        ),
        user_id,
    )

    completed, next_todo = complete_todo(db, todo, user_id)
    completed_again, same_next_todo = complete_todo(db, completed, user_id)

    assert next_todo is not None
    assert next_todo.due_at == datetime(2026, 8, 21, 18)
    assert next_todo.reminder_at == datetime(2026, 8, 21, 17)
    assert next_todo.generated_from_id == todo.id
    assert next_todo.recurring_series_id == todo.id
    assert completed_again.id == completed.id
    assert same_next_todo is not None
    assert same_next_todo.id == next_todo.id
