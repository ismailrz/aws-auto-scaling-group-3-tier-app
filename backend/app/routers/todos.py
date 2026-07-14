from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app import crud
from app.database import get_db
from app.schemas import TodoCreate, TodoRead, TodoUpdate

router = APIRouter(prefix="/todos", tags=["todos"])


@router.get("", response_model=list[TodoRead])
def list_todos(db: Session = Depends(get_db)) -> list[TodoRead]:
    return crud.get_todos(db)


@router.post("", response_model=TodoRead, status_code=status.HTTP_201_CREATED)
def create_todo(todo_in: TodoCreate, db: Session = Depends(get_db)) -> TodoRead:
    return crud.create_todo(db, todo_in)


@router.get("/{todo_id}", response_model=TodoRead)
def get_todo(todo_id: int, db: Session = Depends(get_db)) -> TodoRead:
    todo = crud.get_todo(db, todo_id)
    if todo is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Todo not found")
    return todo


@router.put("/{todo_id}", response_model=TodoRead)
def update_todo(todo_id: int, todo_in: TodoUpdate, db: Session = Depends(get_db)) -> TodoRead:
    todo = crud.get_todo(db, todo_id)
    if todo is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Todo not found")
    return crud.update_todo(db, todo, todo_in)


@router.delete("/{todo_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_todo(todo_id: int, db: Session = Depends(get_db)) -> None:
    todo = crud.get_todo(db, todo_id)
    if todo is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Todo not found")
    crud.delete_todo(db, todo)
