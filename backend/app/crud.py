from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Todo
from app.schemas import TodoCreate, TodoUpdate


def get_todos(db: Session) -> list[Todo]:
    return list(db.scalars(select(Todo).order_by(Todo.created_at.desc())))


def get_todo(db: Session, todo_id: int) -> Todo | None:
    return db.get(Todo, todo_id)


def create_todo(db: Session, todo_in: TodoCreate) -> Todo:
    todo = Todo(**todo_in.model_dump())
    db.add(todo)
    db.commit()
    db.refresh(todo)
    return todo


def update_todo(db: Session, todo: Todo, todo_in: TodoUpdate) -> Todo:
    for field, value in todo_in.model_dump(exclude_unset=True).items():
        setattr(todo, field, value)
    db.commit()
    db.refresh(todo)
    return todo


def delete_todo(db: Session, todo: Todo) -> None:
    db.delete(todo)
    db.commit()
